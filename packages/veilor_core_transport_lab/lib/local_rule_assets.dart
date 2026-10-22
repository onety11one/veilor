import 'dart:io';

enum AssetFailure {
  unsupportedRuleSet,
  unsafePath,
  missingFile,
  invalidHeader,
  destinationExists
}

final class AssetException implements Exception {
  const AssetException(this.failure);
  final AssetFailure failure;
  @override
  String toString() => 'AssetException(${failure.name})';
}

/// Limited to the three local binary asset families emitted by the recovered
/// builder. Does not rewrite profiles or download remote rules.
final class LocalRuleAssets {
  LocalRuleAssets._(this.paths, this.remoteCount);
  final List<String> paths;
  final int remoteCount;
  static const _prefix = 'flutter_assets/assets/';
  static final _safe = RegExp(
      r'^flutter_assets/assets/datas/(geoip|geosite|acl)/[a-zA-Z0-9_@+.!-]+\.srs$');

  factory LocalRuleAssets.fromCore(Map<String, Object?> core) {
    final route = core['route'];
    if (route == null) return LocalRuleAssets._(const [], 0);
    if (route is! Map)
      throw const AssetException(AssetFailure.unsupportedRuleSet);
    final rules = route['rule_set'];
    if (rules == null) return LocalRuleAssets._(const [], 0);
    if (rules is! List)
      throw const AssetException(AssetFailure.unsupportedRuleSet);
    final paths = <String>{};
    var remote = 0;
    for (final rule in rules) {
      if (rule is! Map)
        throw const AssetException(AssetFailure.unsupportedRuleSet);
      if (rule['type'] == 'remote') {
        remote++;
        continue;
      }
      if (rule['type'] == 'inline') continue;
      if (rule['type'] != 'local' ||
          rule['format'] != 'binary' ||
          rule['is_asset'] == true) {
        throw const AssetException(AssetFailure.unsupportedRuleSet);
      }
      final path = rule['path'];
      if (path is! String || !_safe.hasMatch(path) || path.contains('..')) {
        throw const AssetException(AssetFailure.unsafePath);
      }
      paths.add(path);
    }
    return LocalRuleAssets._(List.unmodifiable(paths.toList()..sort()), remote);
  }

  /// assetsRoot is the public repo/package assets folder; destination is the
  /// launcher's private work folder. Publish atomically after all files copy.
  Future<void> stage(
      {required Directory assetsRoot, required Directory work}) async {
    if (paths.isEmpty) return;
    final sourceRoot = Directory(await assetsRoot.resolveSymbolicLinks());
    final workRoot = Directory(await work.resolveSymbolicLinks());
    final destination =
        Directory.fromUri(workRoot.uri.resolve('flutter_assets'));
    if (await FileSystemEntity.type(destination.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw const AssetException(AssetFailure.destinationExists);
    }
    final staging = await workRoot.createTemp('veilor-assets-');
    try {
      for (final path in paths) {
        final source = File.fromUri(
            sourceRoot.uri.resolve(path.substring(_prefix.length)));
        if (!await source.exists())
          throw const AssetException(AssetFailure.missingFile);
        final resolved = await source.resolveSymbolicLinks();
        final base = sourceRoot.absolute.path.toLowerCase();
        if (!resolved
            .toLowerCase()
            .startsWith('$base${Platform.pathSeparator}')) {
          throw const AssetException(AssetFailure.unsafePath);
        }
        final handle = await File(resolved).open();
        try {
          final header = await handle.read(3);
          if (header.length != 3 ||
              header[0] != 83 ||
              header[1] != 82 ||
              header[2] != 83) {
            throw const AssetException(AssetFailure.invalidHeader);
          }
        } finally {
          await handle.close();
        }
        final output = File.fromUri(staging.uri.resolve(path));
        await output.parent.create(recursive: true);
        await File(resolved).copy(output.path);
      }
      await Directory.fromUri(staging.uri.resolve('flutter_assets'))
          .rename(destination.path);
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }
}
