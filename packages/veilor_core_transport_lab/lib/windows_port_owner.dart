import 'dart:ffi';
import 'dart:io';

typedef _GetTableNative = Uint32 Function(
    Pointer<Void>, Pointer<Uint32>, Int32, Uint32, Int32, Uint32);
typedef _GetTable = int Function(
    Pointer<Void>, Pointer<Uint32>, int, int, int, int);
typedef _GetHeapNative = Pointer<Void> Function();
typedef _GetHeap = Pointer<Void> Function();
typedef _AllocNative = Pointer<Void> Function(Pointer<Void>, Uint32, IntPtr);
typedef _Alloc = Pointer<Void> Function(Pointer<Void>, int, int);
typedef _FreeNative = Int32 Function(Pointer<Void>, Uint32, Pointer<Void>);
typedef _Free = int Function(Pointer<Void>, int, Pointer<Void>);

/// Read-only Windows x64 TCP table query. No process enumeration or commands.
/// A snapshot check, not authentication or protection against port-reuse races.
final class WindowsPortOwner {
  WindowsPortOwner() {
    if (!Platform.isWindows || sizeOf<IntPtr>() != 8) {
      throw UnsupportedError('Windows x64 is required');
    }
    final ipHelper = DynamicLibrary.open('iphlpapi.dll');
    final kernel = DynamicLibrary.open('kernel32.dll');
    _getTable = ipHelper
        .lookupFunction<_GetTableNative, _GetTable>('GetExtendedTcpTable');
    _heap = kernel.lookupFunction<_GetHeapNative, _GetHeap>('GetProcessHeap')();
    _alloc = kernel.lookupFunction<_AllocNative, _Alloc>('HeapAlloc');
    _free = kernel.lookupFunction<_FreeNative, _Free>('HeapFree');
    if (_heap == nullptr) throw StateError('TCP owner query unavailable');
  }

  late final _GetTable _getTable;
  late final Pointer<Void> _heap;
  late final _Alloc _alloc;
  late final _Free _free;

  Pointer<Void> _allocate(int bytes) {
    final result = _alloc(_heap, 8, bytes); // HEAP_ZERO_MEMORY
    if (result == nullptr) throw StateError('TCP owner allocation failed');
    return result;
  }

  /// Only a single, exact 127.0.0.1 listener is accepted; ambiguity fails closed.
  int? listenerPid(int port) {
    if (port < 1 || port > 65535) throw ArgumentError.value(port, 'port');
    final size = _allocate(4).cast<Uint32>();
    Pointer<Void> table = nullptr;
    try {
      // AF_INET=2, TCP_TABLE_OWNER_PID_LISTENER=3. Retry boundedly if it grows.
      var status = _getTable(nullptr, size, 0, 2, 3, 0);
      for (var attempt = 0; attempt < 3; attempt++) {
        final capacity = size.value;
        if ((status != 122 && status != 0) ||
            capacity < 4 ||
            capacity > 16 * 1024 * 1024) {
          throw StateError('TCP owner query failed');
        }
        table = _allocate(capacity);
        status = _getTable(table, size, 0, 2, 3, 0);
        if (status == 122) {
          _free(_heap, 0, table);
          table = nullptr;
          continue;
        }
        if (status != 0 || size.value > capacity)
          throw StateError('TCP owner query failed');
        final bytes = table.cast<Uint8>().asTypedList(capacity);
        final words = table.cast<Uint32>().asTypedList(capacity ~/ 4);
        final count = words[0];
        // MIB_TCPTABLE_OWNER_PID: DWORD count; rows of six DWORDs (24 bytes).
        if (count > (capacity - 4) ~/ 24) throw StateError('Invalid TCP table');
        int? owner;
        for (var i = 0; i < count; i++) {
          final row = 4 + i * 24;
          if (words[row ~/ 4] != 2) continue; // MIB_TCP_STATE_LISTEN
          final address = bytes.sublist(row + 4, row + 8);
          final localPort = (bytes[row + 8] << 8) | bytes[row + 9];
          if (localPort != port) continue;
          final exactLoopback = address[0] == 127 &&
              address[1] == 0 &&
              address[2] == 0 &&
              address[3] == 1;
          final wildcard = address.every((v) => v == 0);
          if (wildcard) return null;
          if (!exactLoopback) continue;
          if (owner != null) return null;
          owner = words[(row + 20) ~/ 4];
        }
        return owner;
      }
      throw StateError('TCP table changed repeatedly');
    } finally {
      if (table != nullptr) _free(_heap, 0, table);
      _free(_heap, 0, size.cast<Void>());
    }
  }
}
