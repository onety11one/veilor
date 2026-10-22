import 'dart:async';
import 'dart:io';
import '../lib/veilor_core_transport_lab.dart';
import '../lib/windows_port_owner.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> expectFailure(
  Future<Object?> Function() action,
  LabFailure kind,
) async {
  try {
    await action();
  } on LabException catch (error) {
    check(!error.toString().contains('synthetic-private-error'),
        'Raw error leaked');
    check(error.failure == kind, 'Unexpected failure category: $error');
    return;
  }
  throw StateError('Expected failure: ${kind.name}');
}

Future<void> expectPortReleased(int port) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
  await server.close();
}

Future<Set<String>> labDirectories() async => {
      await for (final entity in Directory.systemTemp.list())
        if (entity is Directory &&
            entity.path
                .split(Platform.pathSeparator)
                .last
                .startsWith('veilor-transport-lab-'))
          entity.path,
    };

Future<void> main() async {
  var passed = 0;
  Future<void> test(String name, Future<void> Function() action) async {
    await action();
    passed++;
    stdout.writeln('PASS $name');
  }

  final before = await labDirectories();
  await test('reload rejection remains an error when followed by process exit',
      () async {
    final session =
        await MockCoreSession.start(scenario: MockScenario.commandErrorExit);
    try {
      await expectFailure(() => session.reload(), LabFailure.commandRejected);
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (session.exitCode == null && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      check(session.exitCode == 31 && session.phase == LabPhase.failed,
          'Delayed exit lost');
    } finally {
      await session.stop();
    }
  });
  await test(
      'Windows table distinguishes exact listener, wildcard and closed port',
      () async {
    final query = WindowsPortOwner();
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    try {
      check(query.listenerPid(port) == pid, 'Incorrect loopback owner');
    } finally {
      await server.close();
    }
    check(query.listenerPid(port) == null, 'Closed listener remains owned');
    final wildcard = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    try {
      check(query.listenerPid(wildcard.port) == null,
          'Wildcard accepted as isolated');
    } finally {
      await wildcard.close();
    }
  });
  await test(
      'foreign announced port receives no HTTP request and survives cleanup',
      () async {
    final foreign = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requests = 0;
    final subscription = foreign.listen((request) {
      requests++;
      unawaited(request.response.close());
    });
    try {
      await expectFailure(
          () => MockCoreSession.start(
                scenario: MockScenario.foreignControl,
                foreignPortForTest: foreign.port,
              ),
          LabFailure.ownershipMismatch);
      check(requests == 0, 'Sent a request to foreign listener');
      check(WindowsPortOwner().listenerPid(foreign.port) == pid,
          'Foreign listener affected');
    } finally {
      await subscription.cancel();
      await foreign.close(force: true);
    }
  });
  for (final scenario in [
    MockScenario.commandError,
    MockScenario.malformedReply,
    MockScenario.missingErrorField,
    MockScenario.wrongErrorType,
    MockScenario.missingExtra
  ]) {
    await test('HTTP 200 ${scenario.name} is not command success', () async {
      final session = await MockCoreSession.start(scenario: scenario);
      try {
        await expectFailure(
            () => session.reload(),
            scenario == MockScenario.commandError
                ? LabFailure.commandRejected
                : LabFailure.invalidReply);
      } finally {
        await session.stop();
      }
    });
  }
  await test('port reassigned after readiness is rejected before stop request',
      () async {
    final session =
        await MockCoreSession.start(scenario: MockScenario.releaseControl);
    HttpServer? replacement;
    StreamSubscription<HttpRequest>? subscription;
    var requests = 0;
    try {
      final port = session.controlPort;
      await session.reload();
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (replacement == null) {
        try {
          replacement =
              await HttpServer.bind(InternetAddress.loopbackIPv4, port);
        } on SocketException {
          if (DateTime.now().isAfter(deadline)) rethrow;
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      }
      subscription = replacement.listen((request) {
        requests++;
        unawaited(request.response.close());
      });
      final stopped = await session.stop();
      check(stopped.forced && session.exitCode != null,
          'Owned child not cleaned');
      check(requests == 0, 'Stop sent to replacement process');
      check(
          WindowsPortOwner().listenerPid(port) == pid, 'Replacement affected');
    } finally {
      await session.stop();
      await subscription?.cancel();
      await replacement?.close(force: true);
    }
  });
  await test(
    'ready handshake, reload, graceful stop and resource release',
    () async {
      final s = await MockCoreSession.start();
      final readyPort = s.parentPort;
      final httpPort = s.controlPort;
      final dir = s.workingDirectory;
      try {
        check(
          s.phase == LabPhase.readySignalReceived && s.exitCode == null,
          'Not live',
        );
        await s.reload();
        final stopped = await s.stop();
        check(
          stopped.exitCode == 0 && !stopped.forced,
          'Graceful shutdown failed',
        );
        check(s.phase == LabPhase.stopped, 'Stop phase');
        await expectPortReleased(readyPort);
        await expectPortReleased(httpPort);
        check(!await Directory(dir).exists(), 'Temporary config retained');
      } finally {
        await s.stop();
      }
    },
  );
  await test('early exit wins over readiness wait', () async {
    await expectFailure(
      () => MockCoreSession.start(scenario: MockScenario.earlyExit),
      LabFailure.earlyExit,
    );
  });
  await test('missing readiness times out and cleans child', () async {
    await expectFailure(
      () => MockCoreSession.start(
        scenario: MockScenario.noReady,
        timeout: const Duration(seconds: 1),
      ),
      LabFailure.timeout,
    );
  });
  await test('invalid control port rejected and child cleaned', () async {
    await expectFailure(
      () => MockCoreSession.start(scenario: MockScenario.invalidAnnouncement),
      LabFailure.invalidAnnouncement,
    );
  });
  await test('HTTP 200 on stop is not proof of process exit', () async {
    final s = await MockCoreSession.start(scenario: MockScenario.noStopExit);
    final port = s.controlPort;
    try {
      final result = await s.stop(timeout: const Duration(milliseconds: 150));
      check(
        result.forced && s.exitCode != null,
        'Unresponsive owned child not reaped',
      );
      await expectPortReleased(port);
    } finally {
      await s.stop();
    }
  });
  for (final scenario in [
    MockScenario.httpError,
    MockScenario.redirect,
    MockScenario.oversized,
    MockScenario.hanging,
  ]) {
    await test(
      'reload ${scenario.name} fails, session can still stop',
      () async {
        final s = await MockCoreSession.start(scenario: scenario);
        try {
          await expectFailure(
            () => s.reload(timeout: const Duration(milliseconds: 300)),
            scenario == MockScenario.hanging
                ? LabFailure.timeout
                : LabFailure.http,
          );
          // Redirect target is /stop/: survival proves it was not followed.
          check(
            s.exitCode == null,
            'Control request unexpectedly terminated child',
          );
          final result = await s.stop();
          check(
            !result.forced && result.exitCode == 0,
            'Stop after failed reload',
          );
        } finally {
          await s.stop();
        }
      },
    );
  }
  await test('unexpected exit invalidates ready state', () async {
    final s = await MockCoreSession.start(
      scenario: MockScenario.crashAfterReady,
    );
    try {
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (s.exitCode == null && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      check(
        s.exitCode == 29 && s.phase == LabPhase.failed,
        'Crash not observed',
      );
      await expectFailure(() => s.reload(), LabFailure.notRunning);
    } finally {
      await s.stop();
    }
  });
  await test('concurrent sessions cannot stop each other', () async {
    final a = await MockCoreSession.start();
    MockCoreSession? b;
    try {
      b = await MockCoreSession.start();
      check(
        a.pid != b.pid &&
            a.controlPort != b.controlPort &&
            a.parentPort != b.parentPort,
        'Not isolated',
      );
      check(
        a.workingDirectory != b.workingDirectory,
        'Shared config directory',
      );
      await a.stop();
      await b.reload();
      check(b.exitCode == null, 'Stopping A affected B');
    } finally {
      await a.stop();
      await b?.stop();
    }
  });
  await test(
    'duplicate stop shares completion, commands after stop fail',
    () async {
      final s = await MockCoreSession.start();
      try {
        final first = s.stop();
        final second = s.stop();
        check(identical(first, second), 'Duplicate stop operation');
        await Future.wait([first, second]);
        await expectFailure(() => s.reload(), LabFailure.notRunning);
      } finally {
        await s.stop();
      }
    },
  );
  await test(
    'no temporary sessions remain after success or failures',
    () async {
      final after = await labDirectories();
      check(after.difference(before).isEmpty, 'Leaked temporary directory');
    },
  );
  stdout.writeln('$passed integration tests passed; synthetic children only.');
}
