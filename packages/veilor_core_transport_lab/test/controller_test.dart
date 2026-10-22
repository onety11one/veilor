import 'dart:async';
import 'dart:io';
import 'package:veilor_vpn_state/transport_bridge.dart';
import 'package:veilor_vpn_state/veilor_vpn_state.dart';
import '../lib/lab_vpn_controller.dart';
import '../lib/veilor_core_transport_lab.dart';

void check(bool value, String reason) {
  if (!value) throw StateError(reason);
}

void noVpn(TransportVpnSnapshot s) {
  check(
      !s.vpn.started &&
          !s.vpn.confirmed &&
          !s.canShowSessionDuration &&
          s.vpn.indicator != VpnIndicator.connected,
      'Transport invented VPN state');
}

Future<void> waitStage(LabVpnController c, TransportStage target) async {
  if (c.snapshot.stage == target) return;
  await c.changes
      .firstWhere((s) => s.stage == target)
      .timeout(const Duration(seconds: 5));
}

Future<void> expectError(Future<void> Function() action) async {
  try {
    await action();
  } catch (_) {
    return;
  }
  throw StateError('Expected error');
}

Future<void> main() async {
  var passed = 0;
  Future<void> test(String name, Future<void> Function() action) async {
    await action();
    passed++;
    stdout.writeln('PASS $name');
  }

  await test('fixed-port launch feeds controller without inventing VPN state',
      () async {
    final c = LabVpnController();
    try {
      await c.start(fixedPortPlan: true);
      check(
          c.snapshot.stage == TransportStage.ready, 'Fixed-port start failed');
      noVpn(c.snapshot);
      await c.reload();
      noVpn(c.snapshot);
      await c.stop();
      check(
          c.snapshot.stage == TransportStage.stopped &&
              c.snapshot.vpn.failure == null,
          'Fixed-port stop failed');
    } finally {
      await c.dispose();
    }
  });

  await test('dispose during successful launch waits and reaps the child',
      () async {
    final c = LabVpnController();
    final launch = c.start();
    await expectError(() => c.start());
    final closing = c.dispose();
    check(identical(closing, c.dispose()), 'Duplicate dispose');
    await expectError(() => c.start());
    await launch;
    await closing;
    check(
        c.snapshot.stage == TransportStage.stopped, 'Launch survived disposal');
    noVpn(c.snapshot);
  });
  await test('dispose during readiness timeout closes cleanly', () async {
    final c = LabVpnController();
    final launch = expectError(() => c.start(
        scenario: MockScenario.noReady, timeout: const Duration(seconds: 1)));
    await c.dispose();
    await launch;
    check(
        c.snapshot.stage == TransportStage.failed &&
            c.snapshot.vpn.failure?.kind == VpnFailureKind.timeout,
        'Disposal erased timeout');
    noVpn(c.snapshot);
  });
  await test('reload timeout reaches state without a connected timer',
      () async {
    final c = LabVpnController();
    try {
      await c.start(scenario: MockScenario.hanging);
      await expectError(
          () => c.reload(timeout: const Duration(milliseconds: 200)));
      check(
          c.snapshot.vpn.failure?.kind == VpnFailureKind.timeout &&
              !c.snapshot.reloading,
          'Timeout classification or pending command');
      noVpn(c.snapshot);
    } finally {
      await c.dispose();
    }
  });

  await test('start/reload/stop emit coherent snapshots without green or timer',
      () async {
    final c = LabVpnController();
    final seen = <TransportVpnSnapshot>[];
    final subscription = c.changes.listen(seen.add);
    try {
      await c.start();
      await c.reload();
      await c.stop();
      await Future<void>.delayed(Duration.zero);
      for (final s in seen) {
        noVpn(s);
      }
      check(
          seen.any((s) => s.stage == TransportStage.starting) &&
              seen.any((s) => s.stage == TransportStage.ready) &&
              seen.any((s) => s.reloading) &&
              c.snapshot.stage == TransportStage.stopped,
          'Events missing');
      check(c.snapshot.vpn.failure == null, 'Normal stop failed');
    } finally {
      await c.dispose();
      await subscription.cancel();
    }
  });
  for (final entry in {
    MockScenario.noReady: VpnFailureKind.timeout,
    MockScenario.earlyExit: VpnFailureKind.serviceExit,
    MockScenario.invalidAnnouncement: VpnFailureKind.preparation,
  }.entries) {
    await test('start ${entry.key.name} maps failure and cleans before retry',
        () async {
      final c = LabVpnController();
      try {
        await expectError(() =>
            c.start(scenario: entry.key, timeout: const Duration(seconds: 1)));
        check(
            c.snapshot.stage == TransportStage.failed &&
                c.snapshot.vpn.failure?.kind == entry.value,
            'Failure classification');
        noVpn(c.snapshot);
        await c.start();
        check(c.snapshot.vpn.failure == null, 'Retry retains error');
      } finally {
        await c.dispose();
      }
    });
  }
  await test('rejected reload followed by exit becomes serviceExit', () async {
    final c = LabVpnController();
    try {
      await c.start(scenario: MockScenario.commandErrorExit);
      await expectError(() => c.reload());
      check(c.snapshot.vpn.failure?.kind == VpnFailureKind.operation,
          'Command rejection lost');
      await waitStage(c, TransportStage.failed);
      check(c.snapshot.vpn.failure?.kind == VpnFailureKind.serviceExit,
          'Exit not propagated');
      noVpn(c.snapshot);
    } finally {
      await c.dispose();
    }
  });
  await test('forced stop reports error and next session clears it', () async {
    final c = LabVpnController();
    try {
      await c.start(scenario: MockScenario.noStopExit);
      await c.stop(timeout: const Duration(milliseconds: 150));
      check(
          c.snapshot.stage == TransportStage.stopped &&
              c.snapshot.vpn.failure?.kind == VpnFailureKind.operation,
          'Forced stop hidden');
      await c.start();
      noVpn(c.snapshot);
      check(c.snapshot.vpn.failure == null, 'New session error');
    } finally {
      await c.dispose();
    }
  });
  await test(
      'stop supersedes hanging reload; late HTTP result cannot revive state',
      () async {
    final c = LabVpnController();
    try {
      await c.start(scenario: MockScenario.hanging);
      final reload = expectError(
          () => c.reload(timeout: const Duration(milliseconds: 500)));
      await c.stop();
      await reload;
      check(
          c.snapshot.stage == TransportStage.stopped &&
              c.snapshot.vpn.failure == null,
          'Late reload overwrote stop');
      noVpn(c.snapshot);
    } finally {
      await c.dispose();
    }
  });
  await test(
      'duplicate start rejected, duplicate stop shared, dispose blocks launch',
      () async {
    final c = LabVpnController();
    try {
      await c.start();
      await expectError(() => c.start());
      final a = c.stop();
      final b = c.stop();
      check(identical(a, b), 'Two stop operations');
      await a;
    } finally {
      await c.dispose();
    }
    await expectError(() => c.start());
  });
  stdout.writeln(
      '$passed controller integration tests passed; no native VPN source connected.');
}
