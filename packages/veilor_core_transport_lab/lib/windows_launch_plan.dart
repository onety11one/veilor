import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'windows_process_names.dart';
import 'local_rule_assets.dart';

enum LaunchFailure {
  invalidConfig,
  hashMismatch,
  invalidExecutable,
  singletonConflict,
  closed
}

final class LaunchException implements Exception {
  const LaunchException(this.failure);
  final LaunchFailure failure;
  @override
  String toString() => 'LaunchException(${failure.name})';
}

/// Prepared paths/ports and partial service JSON, NOT a complete SDK schema.
/// Does not execute the subject. Fixed port is released just before a launcher
/// starts its child; a competing bind must be treated as a failed launch.
final class WindowsLaunchPlan {
  WindowsLaunchPlan._(
      this.directory,
      this.parentListener,
      this._controlLease,
      this.controlPort,
      this.serviceConfig,
      this.coreConfig,
      this.workingDirectory);

  final Directory directory;
  final ServerSocket parentListener;
  ServerSocket? _controlLease;
  final int controlPort;
  final File serviceConfig;
  final File coreConfig;
  final Directory workingDirectory;
  bool _closed = false;
  Future<void>? _closing;

  static const managedKeys = {
    'base_dir',
    'work_dir',
    'cache_dir',
    'core_path',
    'log_path',
    'err_path',
  };

  static Future<WindowsLaunchPlan> prepare({
    required Map<String, Object?> core,
    Map<String, Object?> serviceOptions = const {},
    Directory? temporaryParent,
    Directory? bundledAssetsRoot,
  }) async {
    if (serviceOptions.keys.any(managedKeys.contains))
      throw const LaunchException(LaunchFailure.invalidConfig);
    final ruleAssets = LocalRuleAssets.fromCore(core);
    if (ruleAssets.paths.isNotEmpty && bundledAssetsRoot == null) {
      throw const AssetException(AssetFailure.missingFile);
    }
    // Serialize before allocation; NaN/non-JSON input must not leave resources.
    String payload;
    String options;
    try {
      payload = jsonEncode(core);
      options = jsonEncode(serviceOptions);
    } catch (_) {
      throw const LaunchException(LaunchFailure.invalidConfig);
    }
    final parentPath =
        await (temporaryParent ?? Directory.systemTemp).resolveSymbolicLinks();
    final root = await Directory(parentPath).createTemp('veilor-launch-');
    ServerSocket? parent;
    ServerSocket? control;
    try {
      final dirs = <String, Directory>{};
      for (final name in ['base', 'work', 'cache', 'logs']) {
        dirs[name] = await Directory.fromUri(root.uri.resolve(name)).create();
      }
      if (bundledAssetsRoot != null) {
        await ruleAssets.stage(
            assetsRoot: bundledAssetsRoot, work: dirs['work']!);
      }
      parent = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      control = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final coreFile = File.fromUri(root.uri.resolve('service_core.json'));
      final serviceFile = File.fromUri(root.uri.resolve('service.json'));
      await coreFile.writeAsString(payload, flush: true);
      final fields = jsonDecode(options) as Map<String, dynamic>;
      fields.addAll({
        'base_dir': dirs['base']!.path,
        'work_dir': dirs['work']!.path,
        'cache_dir': dirs['cache']!.path,
        'core_path': coreFile.path,
        'log_path':
            File.fromUri(dirs['logs']!.uri.resolve('service_core.log')).path,
        'err_path':
            File.fromUri(dirs['logs']!.uri.resolve('service_error.log')).path,
      });
      await serviceFile.writeAsString(jsonEncode(fields), flush: true);
      return WindowsLaunchPlan._(root, parent, control, control.port,
          serviceFile, coreFile, dirs['work']!);
    } catch (_) {
      await parent?.close();
      await control?.close();
      await root.delete(recursive: true);
      rethrow;
    }
  }

  List<String> get arguments {
    if (_closed) throw const LaunchException(LaunchFailure.closed);
    return List.unmodifiable([
      'run2',
      '--service-config',
      serviceConfig.path,
      '--service-http-port',
      '$controlPort',
      '--connected-port',
      '${parentListener.port}',
    ]);
  }

  Future<void> releaseControlLease() async {
    if (_closed) throw const LaunchException(LaunchFailure.closed);
    await _controlLease?.close();
    _controlLease = null;
  }

  /// Read-only exact-file hash/PE/singleton gate. Does not bypass SDK checks.
  /// The caller must recheck immediately before launch; it is a snapshot.
  Future<void> auditExecutable(File executable, String expectedSha256) async {
    if (_closed) throw const LaunchException(LaunchFailure.closed);
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(expectedSha256))
      throw ArgumentError('Expected SHA-256');
    final resolved = File(await executable.resolveSymbolicLinks());
    if ((await sha256.bind(resolved.openRead()).first).toString() !=
        expectedSha256) {
      throw const LaunchException(LaunchFailure.hashMismatch);
    }
    final handle = await resolved.open();
    try {
      final length = await handle.length();
      final header = await handle.read(64);
      if (header.length != 64 || header[0] != 77 || header[1] != 90)
        throw const LaunchException(LaunchFailure.invalidExecutable);
      final pe = header[60] |
          (header[61] << 8) |
          (header[62] << 16) |
          (header[63] << 24);
      if (pe < 64 || pe + 26 > length)
        throw const LaunchException(LaunchFailure.invalidExecutable);
      await handle.setPosition(pe);
      final signature = await handle.read(26);
      if (signature[0] != 80 ||
          signature[1] != 69 ||
          signature[2] != 0 ||
          signature[3] != 0 ||
          signature[4] != 0x64 ||
          signature[5] != 0x86 ||
          signature[24] != 0x0b ||
          signature[25] != 2) {
        throw const LaunchException(LaunchFailure.invalidExecutable);
      }
    } finally {
      await handle.close();
    }
    final basename = resolved.uri.pathSegments.last;
    // The recovered singleton uses Go EqualFold. Restrict this initial gate
    // to ASCII exe names rather than pretend Dart lowercasing equals all of it.
    if (!RegExp(r'^[a-z0-9_.-]+\.exe$', caseSensitive: false)
        .hasMatch(basename)) {
      throw const LaunchException(LaunchFailure.invalidExecutable);
    }
    if (hasRunningWindowsBasename(basename))
      throw const LaunchException(LaunchFailure.singletonConflict);
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    await _controlLease?.close();
    await parentListener.close();
    if (await directory.exists()) {
      // Refuse a replaced root link instead of following it during cleanup.
      if (await directory.resolveSymbolicLinks() != directory.absolute.path)
        throw StateError('Launch root changed');
      await directory.delete(recursive: true);
    }
  }
}
