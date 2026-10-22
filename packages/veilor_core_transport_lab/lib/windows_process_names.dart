import 'dart:ffi';
import 'dart:io';

typedef _SnapshotN = IntPtr Function(Uint32, Uint32);
typedef _Snapshot = int Function(int, int);
typedef _WalkN = Int32 Function(IntPtr, Pointer<Void>);
typedef _Walk = int Function(int, Pointer<Void>);
typedef _CloseN = Int32 Function(IntPtr);
typedef _Close = int Function(int);
typedef _HeapN = Pointer<Void> Function();
typedef _Heap = Pointer<Void> Function();
typedef _AllocN = Pointer<Void> Function(Pointer<Void>, Uint32, IntPtr);
typedef _Alloc = Pointer<Void> Function(Pointer<Void>, int, int);
typedef _FreeN = Int32 Function(Pointer<Void>, Uint32, Pointer<Void>);
typedef _Free = int Function(Pointer<Void>, int, Pointer<Void>);
typedef _ErrorN = Uint32 Function();
typedef _Error = int Function();

/// Read-only process basename comparison. No argv, credentials or list logging.
bool hasRunningWindowsBasename(String basename) {
  if (!Platform.isWindows || sizeOf<IntPtr>() != 8)
    throw UnsupportedError('Windows x64 required');
  if (basename.isEmpty || basename.contains(RegExp(r'[/\\]')))
    throw ArgumentError('Expected basename');
  final kernel = DynamicLibrary.open('kernel32.dll');
  final snapshot =
      kernel.lookupFunction<_SnapshotN, _Snapshot>('CreateToolhelp32Snapshot');
  final first = kernel.lookupFunction<_WalkN, _Walk>('Process32FirstW');
  final next = kernel.lookupFunction<_WalkN, _Walk>('Process32NextW');
  final close = kernel.lookupFunction<_CloseN, _Close>('CloseHandle');
  final lastError = kernel.lookupFunction<_ErrorN, _Error>('GetLastError');
  final heap = kernel.lookupFunction<_HeapN, _Heap>('GetProcessHeap')();
  final alloc = kernel.lookupFunction<_AllocN, _Alloc>('HeapAlloc');
  final free = kernel.lookupFunction<_FreeN, _Free>('HeapFree');
  if (heap == nullptr) throw StateError('Process inventory unavailable');
  final handle = snapshot(2, 0); // TH32CS_SNAPPROCESS
  if (handle == -1) throw StateError('Process inventory unavailable');
  Pointer<Void> entry = nullptr;
  try {
    entry = alloc(heap, 8, 568); // PROCESSENTRY32W on Windows x64
    if (entry == nullptr) throw StateError('Process inventory unavailable');
    entry.cast<Uint32>().value = 568;
    var ok = first(handle, entry);
    while (ok != 0) {
      // szExeFile offset 44, WCHAR[MAX_PATH=260]. No process is opened.
      final units = (entry.cast<Uint8>() + 44).cast<Uint16>().asTypedList(260);
      final end = units.indexOf(0);
      if (end < 0) throw StateError('Process inventory truncated');
      final name = String.fromCharCodes(units.sublist(0, end));
      if (name.toLowerCase() == basename.toLowerCase()) return true;
      ok = next(handle, entry);
    }
    if (lastError() != 18) throw StateError('Process inventory incomplete');
    return false;
  } finally {
    if (entry != nullptr) free(heap, 0, entry);
    close(handle);
  }
}
