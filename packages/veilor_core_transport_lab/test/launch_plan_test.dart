import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import '../lib/windows_launch_plan.dart';
import '../lib/windows_process_names.dart';
import '../lib/veilor_core_transport_lab.dart';

void check(bool value, String reason) {
  if (!value) throw StateError(reason);
}

Future<void> failure(
    Future<void> Function() run, LaunchFailure expected) async {
  try {
    await run();
  } on LaunchException catch (e) {
    check(e.failure == expected, 'Wrong launch failure');
    return;
  }
  throw StateError('Expected launch failure');
}

Future<void> portReleased(int port) async {
  final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
  await listener.close();
}

Future<Set<String>> launchDirectories() async => {
      await for (final e in Directory.systemTemp.list())
        if (e is Directory &&
            e.path
                .split(Platform.pathSeparator)
                .last
                .startsWith('veilor-launch-'))
          e.path,
    };
List<int> peFixture() {
  final bytes = List<int>.filled(256, 0);
  bytes[0] = 77;
  bytes[1] = 90;
  bytes[60] = 64;
  bytes[64] = 80;
  bytes[65] = 69;
  bytes[68] = 0x64;
  bytes[69] = 0x86;
  bytes[88] = 0x0b;
  bytes[89] = 2;
  return bytes;
}

Future<void> main() async {
  var passed = 0;
  Future<void> test(String label, Future<void> Function() action) async {
    await action();
    passed++;
    stdout.writeln('PASS $label');
  }

  final before = await launchDirectories();
  await test('fixed-port argv handles spaces and Cyrillic workspace paths',
      () async {
    final parent =
        await Directory.systemTemp.createTemp('veilor-launch-path тест ');
    MockCoreSession? session;
    try {
      session = await MockCoreSession.start(
          fixedPortPlan: true, workspaceParent: parent);
      await session.reload();
      final result = await session.stop();
      check(result.exitCode == 0 && !result.forced,
          'Unicode/space path launch failed');
      check(await parent.list().isEmpty, 'Session root not removed');
    } finally {
      await session?.stop();
      await parent.delete(recursive: true);
    }
  });
  await test(
      'serializer isolates paths and preserves caller metadata without putting it in argv',
      () async {
    final metadata = <String, Object?>{
      'secret': 'synthetic-secret',
      'custom': {'label': 'тест & "quoted"'}
    };
    final core = <String, Object?>{
      'outbounds': [
        {'type': 'direct', 'tag': 'тест'}
      ]
    };
    final plan =
        await WindowsLaunchPlan.prepare(core: core, serviceOptions: metadata);
    try {
      metadata['secret'] = 'changed';
      core.clear();
      final config = jsonDecode(await plan.serviceConfig.readAsString())
          as Map<String, dynamic>;
      check(config['secret'] == 'synthetic-secret',
          'Caller data not snapshotted');
      for (final key in WindowsLaunchPlan.managedKeys) {
        check(
            (config[key] as String).startsWith('${plan.directory.path}/') ||
                (config[key] as String).startsWith('${plan.directory.path}\\'),
            'Path outside workspace');
      }
      check(
          (jsonDecode(await plan.coreConfig.readAsString())
                  as Map)['outbounds'] !=
              null,
          'Core snapshot lost');
      final args = plan.arguments;
      check(
          args.length == 7 &&
              args[0] == 'run2' &&
              args[2] == plan.serviceConfig.path,
          'CLI argument shape');
      check(int.parse(args[4]) == plan.controlPort && args[4] != '0',
          'Disabled service HTTP port');
      check(
          !args.join(' ').contains('synthetic-secret') &&
              !args.join(' ').contains('quoted'),
          'Config in argv');
      check(!config.containsKey('control_port'), 'Invented Clash port default');
    } finally {
      await plan.close();
    }
  });
  await test('caller cannot override managed core path', () async {
    await failure(() async {
      await WindowsLaunchPlan.prepare(
          core: {}, serviceOptions: {'core_path': 'outside'});
    }, LaunchFailure.invalidConfig);
  });
  await test('non-JSON options rejected before allocation', () async {
    await failure(() async {
      await WindowsLaunchPlan.prepare(
          core: {}, serviceOptions: {'x': double.nan});
    }, LaunchFailure.invalidConfig);
  });
  await test(
      'control port held until release, both ports and directory cleaned',
      () async {
    final plan = await WindowsLaunchPlan.prepare(core: {});
    final parent = plan.parentListener.port;
    final control = plan.controlPort;
    final directory = plan.directory.path;
    try {
      var blocked = false;
      try {
        final other =
            await ServerSocket.bind(InternetAddress.loopbackIPv4, control);
        await other.close();
      } on SocketException {
        blocked = true;
      }
      check(blocked, 'Control lease did not reserve port');
      await plan.releaseControlLease();
      await portReleased(control);
    } finally {
      await plan.close();
    }
    await plan.close();
    await portReleased(parent);
    await portReleased(control);
    check(!await Directory(directory).exists(), 'Workspace leaked');
    await failure(() => plan.releaseControlLease(), LaunchFailure.closed);
  });
  await test('two plans have separate roots and ports', () async {
    final a = await WindowsLaunchPlan.prepare(core: {});
    WindowsLaunchPlan? b;
    try {
      b = await WindowsLaunchPlan.prepare(core: {});
      check(
          a.directory.path != b.directory.path &&
              a.controlPort != b.controlPort &&
              a.parentListener.port != b.parentListener.port,
          'Plans overlap');
      await a.close();
      check(await b.serviceConfig.exists(), 'Cleanup crossed sessions');
    } finally {
      await a.close();
      await b?.close();
    }
  });
  await test('process inventory finds own executable case-insensitively',
      () async {
    final name = File(Platform.resolvedExecutable).uri.pathSegments.last;
    check(hasRunningWindowsBasename(name.toUpperCase()), 'Own process absent');
    check(!hasRunningWindowsBasename('veilor-absent-9c8e37-test.exe'),
        'Absent process reported');
  });
  await test('hash mismatch blocks before executable launch', () async {
    final plan = await WindowsLaunchPlan.prepare(core: {});
    try {
      final exe = await File('${plan.directory.path}/fixture.exe')
          .writeAsBytes(peFixture());
      await failure(() => plan.auditExecutable(exe, '0' * 64),
          LaunchFailure.hashMismatch);
    } finally {
      await plan.close();
    }
  });
  await test('matching hash does not turn a non-PE file into executable',
      () async {
    final plan = await WindowsLaunchPlan.prepare(core: {});
    try {
      final bytes = [1, 2, 3];
      final exe =
          await File('${plan.directory.path}/fixture.exe').writeAsBytes(bytes);
      await failure(
          () => plan.auditExecutable(exe, sha256.convert(bytes).toString()),
          LaunchFailure.invalidExecutable);
    } finally {
      await plan.close();
    }
  });
  await test('PE fixture with pinned hash passes read-only header gate only',
      () async {
    final plan = await WindowsLaunchPlan.prepare(core: {});
    try {
      final bytes = peFixture();
      final exe = await File('${plan.directory.path}/veilor-fixture-9c8e37.exe')
          .writeAsBytes(bytes);
      await plan.auditExecutable(exe, sha256.convert(bytes).toString());
    } finally {
      await plan.close();
    }
  });
  await test(
      'same executable basename in another directory blocks singleton conflict',
      () async {
    final plan = await WindowsLaunchPlan.prepare(core: {});
    try {
      final bytes = peFixture();
      final name =
          File(Platform.resolvedExecutable).uri.pathSegments.last.toUpperCase();
      final exe =
          await File('${plan.directory.path}/$name').writeAsBytes(bytes);
      await failure(
          () => plan.auditExecutable(exe, sha256.convert(bytes).toString()),
          LaunchFailure.singletonConflict);
    } finally {
      await plan.close();
    }
  });
  await test('fixed-port child starts without stdout port announcement',
      () async {
    final s = await MockCoreSession.start(fixedPortPlan: true);
    final dir = s.workingDirectory;
    final port = s.controlPort;
    try {
      check(s.phase == LabPhase.readySignalReceived, 'No readiness');
      await s.reload();
      final stopped = await s.stop();
      check(stopped.exitCode == 0 && !stopped.forced,
          'Fixed-port lifecycle failed');
    } finally {
      await s.stop();
    }
    await portReleased(port);
    check(!await Directory(dir).exists(), 'Plan cleanup missing');
  });
  await test('fixed-port timeout cleans prepared workspace and child',
      () async {
    try {
      await MockCoreSession.start(
          fixedPortPlan: true,
          scenario: MockScenario.noReady,
          timeout: const Duration(seconds: 1));
    } on LabException catch (e) {
      check(e.failure == LabFailure.timeout, 'Wrong timeout');
      return;
    }
    throw StateError('Expected timeout');
  });
  await test(
      'port stolen after lease release fails child bind, foreign listener untouched',
      () async {
    final plan = await WindowsLaunchPlan.prepare(
        core: {}, serviceOptions: {'labOnly': true});
    HttpServer? foreign;
    Process? child;
    StreamSubscription<Socket>? ready;
    var signals = 0;
    var requests = 0;
    try {
      ready = plan.parentListener.listen((s) {
        signals++;
        s.destroy();
      });
      await plan.releaseControlLease();
      foreign =
          await HttpServer.bind(InternetAddress.loopbackIPv4, plan.controlPort);
      foreign.listen((r) {
        requests++;
        unawaited(r.response.close());
      });
      final runtime = File.fromUri(
          File(Platform.resolvedExecutable).uri.resolve('dartvm.exe'));
      final script =
          File.fromUri(Platform.script.resolve('../tool/mock_core.dart'));
      child = await Process.start(runtime.path,
          [script.path, ...plan.arguments, '--mock-scenario', 'normal'],
          workingDirectory: plan.workingDirectory.path, runInShell: false);
      unawaited(child.stdout.drain<void>());
      unawaited(child.stderr.drain<void>());
      check(await child.exitCode.timeout(const Duration(seconds: 5)) != 0,
          'Child ignored occupied port');
      check(signals == 0 && requests == 0,
          'Foreign listener contacted or false readiness');
    } finally {
      child?.kill();
      if (child != null) await child.exitCode;
      await ready?.cancel();
      await foreign?.close(force: true);
      await plan.close();
    }
  });
  await test('all launch workspaces released after successful and failed runs',
      () async {
    check((await launchDirectories()).difference(before).isEmpty,
        'Launch directories leaked');
  });
  stdout
      .writeln('$passed launch preparation tests passed; no Karing execution.');
}
