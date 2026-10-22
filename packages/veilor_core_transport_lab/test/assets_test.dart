import 'dart:io';
import 'package:crypto/crypto.dart';
import '../lib/local_rule_assets.dart';
import '../lib/windows_launch_plan.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Map<String, Object?> core(List<Object?> entries) => {
      'route': {'rule_set': entries}
    };
Map<String, Object?> local(String path) =>
    {'type': 'local', 'format': 'binary', 'path': path};
Future<void> expectFailure(
    Future<void> Function() action, AssetFailure expected) async {
  try {
    await action();
  } on AssetException catch (e) {
    check(e.failure == expected, 'Wrong asset failure');
    return;
  }
  throw StateError('Expected asset failure');
}

Future<void> main() async {
  var passed = 0;
  Future<void> test(String name, Future<void> Function() action) async {
    await action();
    passed++;
    stdout.writeln('PASS $name');
  }

  await test(
      'empty, inline and remote sets do not invent local files or downloads',
      () async {
    check(LocalRuleAssets.fromCore({}).paths.isEmpty, 'Empty profile');
    final plan = LocalRuleAssets.fromCore(core([
      {'type': 'inline', 'rules': <Object?>[]},
      {'type': 'remote', 'url': 'https://example.invalid/test.srs'}
    ]));
    check(
        plan.paths.isEmpty && plan.remoteCount == 1, 'Remote treated as local');
  });
  await test('same local path deduplicated without changing input', () async {
    const path = 'flutter_assets/assets/datas/geoip/ru.srs';
    final input = core([local(path), local(path)]);
    check(LocalRuleAssets.fromCore(input).paths.length == 1, 'Duplicate files');
    check(((input['route'] as Map)['rule_set'] as List).length == 2,
        'Profile mutated');
  });
  for (final path in [
    '../ru.srs',
    'C:/outside.srs',
    'flutter_assets/assets/datas/geoip/../ru.srs',
    r'flutter_assets\assets\datas\geoip\ru.srs',
    'flutter_assets/assets/datas/geoip/%2e%2e.srs'
  ]) {
    await test('unsafe local path rejected ${passed + 1}', () async {
      await expectFailure(() async {
        LocalRuleAssets.fromCore(core([local(path)]));
      }, AssetFailure.unsafePath);
    });
  }
  await test('unknown or Android asset mode rejected explicitly', () async {
    await expectFailure(() async {
      LocalRuleAssets.fromCore(core([
        {'type': 'future'}
      ]));
    }, AssetFailure.unsupportedRuleSet);
    await expectFailure(() async {
      LocalRuleAssets.fromCore(core([
        {
          'type': 'local',
          'format': 'binary',
          'path': 'flutter_assets/assets/datas/geoip/ru.srs',
          'is_asset': true
        }
      ]));
    }, AssetFailure.unsupportedRuleSet);
  });
  final repoAssets =
      Directory.fromUri(Platform.script.resolve('../../../assets/'));
  await test(
      'every bundled SRS filename, including @!cn, remains representable',
      () async {
    final entries = <Object?>[];
    await for (final entity
        in Directory.fromUri(repoAssets.uri.resolve('datas'))
            .list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.srs')) {
        final relative = entity.uri.path.substring(repoAssets.uri.path.length);
        entries.add(local('flutter_assets/assets/$relative'));
      }
    }
    check(
        entries.isNotEmpty &&
            LocalRuleAssets.fromCore(core(entries)).paths.length ==
                entries.length,
        'Bundled rules rejected');
  });
  await test(
      'launch preparation stages referenced assets without changing core config',
      () async {
    final profile = core([local('flutter_assets/assets/datas/geoip/ru.srs')]);
    final launch = await WindowsLaunchPlan.prepare(
        core: profile, bundledAssetsRoot: repoAssets);
    try {
      check(
          await File.fromUri(launch.workingDirectory.uri
                  .resolve('flutter_assets/assets/datas/geoip/ru.srs'))
              .exists(),
          'Launch asset absent');
      check(
          (await launch.coreConfig.readAsString())
              .contains('flutter_assets/assets/datas/geoip/ru.srs'),
          'Rule path rewritten');
    } finally {
      await launch.close();
    }
    await expectFailure(() async {
      await WindowsLaunchPlan.prepare(core: profile);
    }, AssetFailure.missingFile);
  });
  await test(
      'repository rule files staged byte-for-byte at builder-relative paths',
      () async {
    final launch = await WindowsLaunchPlan.prepare(core: {});
    try {
      final manifest = LocalRuleAssets.fromCore(core([
        local('flutter_assets/assets/datas/geoip/ru.srs'),
        local('flutter_assets/assets/datas/geosite/youtube.srs'),
        local('flutter_assets/assets/datas/geosite/bilibili@!cn.srs')
      ]));
      await manifest.stage(
          assetsRoot: repoAssets, work: launch.workingDirectory);
      for (final path in manifest.paths) {
        final source = File.fromUri(repoAssets.uri
            .resolve(path.substring('flutter_assets/assets/'.length)));
        final target = File.fromUri(launch.workingDirectory.uri.resolve(path));
        check(
            await sha256.bind(source.openRead()).first ==
                await sha256.bind(target.openRead()).first,
            'Asset bytes changed');
      }
      await expectFailure(
          () => manifest.stage(
              assetsRoot: repoAssets, work: launch.workingDirectory),
          AssetFailure.destinationExists);
    } finally {
      await launch.close();
    }
  });
  await test('missing asset fails without publishing partial flutter_assets',
      () async {
    final launch = await WindowsLaunchPlan.prepare(core: {});
    try {
      final manifest = LocalRuleAssets.fromCore(core([
        local('flutter_assets/assets/datas/geoip/ru.srs'),
        local('flutter_assets/assets/datas/geosite/veilor-missing-9c8e37.srs')
      ]));
      await expectFailure(
          () => manifest.stage(
              assetsRoot: repoAssets, work: launch.workingDirectory),
          AssetFailure.missingFile);
      check(
          !await Directory.fromUri(
                  launch.workingDirectory.uri.resolve('flutter_assets'))
              .exists(),
          'Partial files published');
      check(await launch.workingDirectory.list().isEmpty, 'Staging leaked');
    } finally {
      await launch.close();
    }
  });
  await test('bad header is rejected without changing original source',
      () async {
    final launch = await WindowsLaunchPlan.prepare(core: {});
    try {
      final source = File.fromUri(
          launch.directory.uri.resolve('source/datas/geoip/bad.srs'));
      await source.parent.create(recursive: true);
      await source.writeAsBytes([1, 2, 3]);
      final manifest = LocalRuleAssets.fromCore(
          core([local('flutter_assets/assets/datas/geoip/bad.srs')]));
      await expectFailure(
          () => manifest.stage(
              assetsRoot:
                  Directory.fromUri(launch.directory.uri.resolve('source')),
              work: launch.workingDirectory),
          AssetFailure.invalidHeader);
      check(
          (await source.readAsBytes()).join(',') == '1,2,3', 'Source changed');
    } finally {
      await launch.close();
    }
  });
  stdout.writeln(
      '$passed local asset tests passed; no network or core execution.');
}
