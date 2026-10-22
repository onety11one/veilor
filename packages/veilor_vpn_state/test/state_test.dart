import 'dart:io';
import '../lib/veilor_vpn_state.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void main() {
  var passed = 0;
  void test(String name, void Function() action) {
    action();
    passed++;
    stdout.writeln('PASS $name');
  }

  test('initial state is unknown, not disconnected', () {
    final s = VpnStateStore().snapshot;
    check(
      s.phase == VpnPhase.unknown &&
          !s.confirmed &&
          !s.started &&
          !s.toggleEnabled &&
          !s.canShowSessionDuration,
      'Initial state pretends to know VPN status',
    );
  });
  test(
    'map all six observed names, reject names and ordinals not verified',
    () {
      for (final phase in VpnPhase.values.where((p) => p != VpnPhase.unknown)) {
        check(VpnPhase.fromServiceName(phase.name) == phase, 'Name mapping');
      }
      for (final name in ['2', 'CONNECTED', 'error', 'futureState', '']) {
        check(
          VpnPhase.fromServiceName(name) == VpnPhase.unknown,
          'Unverified state guessed',
        );
      }
    },
  );
  for (final phase in [VpnPhase.invalid, VpnPhase.disconnected]) {
    test('$phase enables start without a timer', () {
      final store = VpnStateStore()..observe(phase);
      final s = store.snapshot;
      check(
        s.toggleEnabled &&
            !s.toggleOn &&
            !s.canShowSessionDuration &&
            s.indicator == VpnIndicator.neutral,
        'Off presentation',
      );
      check(store.beginOperation(VpnOperation.stop) == null, 'Stop while off');
      check(store.beginOperation(VpnOperation.start) != null, 'Cannot start');
    });
  }
  test('confirmed connected enables stop, timer and green indicator', () {
    final store = VpnStateStore()..observe(VpnPhase.connected);
    final s = store.snapshot;
    check(
      s.started &&
          s.toggleOn &&
          s.toggleEnabled &&
          s.canShowSessionDuration &&
          s.indicator == VpnIndicator.connected,
      'Connected presentation',
    );
    check(store.beginOperation(VpnOperation.start) == null, 'Double start');
    check(store.beginOperation(VpnOperation.stop) != null, 'Cannot stop');
  });
  for (final phase in [
    VpnPhase.connecting,
    VpnPhase.reasserting,
    VpnPhase.disconnecting,
  ]) {
    test('$phase blocks repeat taps and stops confirmed timer display', () {
      final store = VpnStateStore()..observe(phase);
      final s = store.snapshot;
      check(
        s.busy && !s.toggleEnabled && !s.started && !s.canShowSessionDuration,
        'Transition presentation',
      );
      for (final op in VpnOperation.values) {
        check(store.beginOperation(op) == null, 'Command during transition');
      }
    });
  }
  test(
    'local start intent and successful result do not fabricate connection',
    () {
      final store = VpnStateStore()..observe(VpnPhase.disconnected);
      final op = store.beginOperation(VpnOperation.start)!;
      check(
        store.snapshot.phase == VpnPhase.disconnected && store.snapshot.busy,
        'Intent changed service phase',
      );
      check(
        store.beginOperation(VpnOperation.start) == null,
        'Concurrent command',
      );
      store.completeOperation(op);
      check(
        !store.snapshot.confirmed &&
            !store.snapshot.toggleEnabled &&
            !store.snapshot.started,
        'Success fabricated confirmed state',
      );
      store.completeStateRead(store.beginStateRead(), VpnPhase.connected);
      check(
        store.snapshot.started && store.snapshot.toggleEnabled,
        'Fresh read',
      );
    },
  );
  test('normal start callbacks then result', () {
    final store = VpnStateStore()..observe(VpnPhase.disconnected);
    final op = store.beginOperation(VpnOperation.start)!;
    store.observe(VpnPhase.connecting);
    store.observe(VpnPhase.connected);
    check(!store.snapshot.toggleEnabled, 'Tap enabled before command finished');
    store.completeOperation(op);
    check(
      store.snapshot.started && store.snapshot.toggleEnabled,
      'Connected callback lost',
    );
  });
  test('normal stop callbacks then result', () {
    final store = VpnStateStore()..observe(VpnPhase.connected);
    final op = store.beginOperation(VpnOperation.stop)!;
    store.observe(VpnPhase.disconnecting);
    store.observe(VpnPhase.disconnected);
    store.completeOperation(op);
    check(
      store.snapshot.toggleEnabled &&
          !store.snapshot.started &&
          !store.snapshot.busy &&
          store.snapshot.failure == null,
      'Stop result',
    );
  });
  for (final kind in [
    VpnFailureKind.preparation,
    VpnFailureKind.operation,
    VpnFailureKind.timeout,
  ]) {
    test('$kind survives disconnected callback after failed start', () {
      final store = VpnStateStore()..observe(VpnPhase.disconnected);
      final op = store.beginOperation(VpnOperation.start)!;
      store.completeOperation(op, failure: VpnFailure(kind));
      store.observe(VpnPhase.disconnected);
      check(
        store.snapshot.failure?.kind == kind &&
            store.snapshot.indicator == VpnIndicator.error &&
            store.snapshot.toggleEnabled,
        'Error hidden by disconnect',
      );
      store.beginOperation(VpnOperation.start);
      check(store.snapshot.failure == null, 'Retry did not clear old error');
    });
  }
  test('stop failure is not reported as disconnected', () {
    final store = VpnStateStore()..observe(VpnPhase.connected);
    final op = store.beginOperation(VpnOperation.stop)!;
    store.completeOperation(
      op,
      failure: const VpnFailure(VpnFailureKind.operation),
    );
    check(
      store.snapshot.phase == VpnPhase.connected &&
          !store.snapshot.confirmed &&
          !store.snapshot.toggleEnabled,
      'Unconfirmed stop changed phase',
    );
    store.observe(VpnPhase.connected);
    check(
      store.snapshot.started &&
          store.snapshot.failure != null &&
          store.snapshot.indicator == VpnIndicator.error,
      'Stop failure hidden',
    );
  });
  for (final operation in [VpnOperation.reload, VpnOperation.restart]) {
    test('$operation keeps reasserting distinct', () {
      final store = VpnStateStore()..observe(VpnPhase.connected);
      final op = store.beginOperation(operation)!;
      store.observe(VpnPhase.reasserting);
      check(
        store.snapshot.phase == VpnPhase.reasserting && store.snapshot.busy,
        'Reasserting lost',
      );
      store.observe(VpnPhase.connected);
      store.completeOperation(op);
      check(store.snapshot.started && store.snapshot.toggleEnabled, 'Recovery');
    });
  }
  test('stale initial state read cannot replace a service callback', () {
    final store = VpnStateStore();
    final read = store.beginStateRead();
    store.observe(VpnPhase.connected);
    check(
      !store.completeStateRead(read, VpnPhase.disconnected) &&
          store.snapshot.started,
      'Late query overwrote callback',
    );
    check(!store.failStateRead(read), 'Late query error overwrote callback');
  });
  test('only latest read wins; read tokens cannot be replayed', () {
    final store = VpnStateStore();
    final old = store.beginStateRead();
    final latest = store.beginStateRead();
    check(
      !store.completeStateRead(old, VpnPhase.connected),
      'Old read accepted',
    );
    check(
      store.completeStateRead(latest, VpnPhase.disconnected),
      'Latest rejected',
    );
    check(
      !store.completeStateRead(latest, VpnPhase.connected),
      'Replay accepted',
    );
  });
  test('foreign tokens and duplicate command completions are ignored', () {
    final a = VpnStateStore()..observe(VpnPhase.disconnected);
    final b = VpnStateStore()..observe(VpnPhase.disconnected);
    check(
      !a.completeStateRead(b.beginStateRead(), VpnPhase.connected),
      'Foreign read',
    );
    final op = a.beginOperation(VpnOperation.start)!;
    check(!b.completeOperation(op), 'Foreign command');
    a.completeOperation(op);
    a.observe(VpnPhase.disconnected);
    final next = a.beginOperation(VpnOperation.start)!;
    check(
      !a.completeOperation(op) && a.snapshot.busy,
      'Old completion accepted',
    );
    a.completeOperation(next);
  });
  test('state read failure preserves last phase as unconfirmed', () {
    final store = VpnStateStore()..observe(VpnPhase.connected);
    store.failStateRead(store.beginStateRead());
    check(
      store.snapshot.phase == VpnPhase.connected &&
          !store.snapshot.confirmed &&
          !store.snapshot.toggleEnabled &&
          !store.snapshot.canShowSessionDuration &&
          store.snapshot.failure?.kind == VpnFailureKind.stateUnavailable,
      'Read failure presented as ordinary off',
    );
    store.observe(VpnPhase.connected);
    check(store.snapshot.started && store.snapshot.failure == null, 'Recovery');
  });
  test('new connected session clears an old failure', () {
    final store = VpnStateStore()..observe(VpnPhase.disconnected);
    store.reportFailure(const VpnFailure(VpnFailureKind.serviceExit));
    store.observe(VpnPhase.connected);
    check(store.snapshot.failure == null, 'Recovered connection kept error');
  });
  test('unknown native value never enables the toggle', () {
    final store = VpnStateStore()..observe(VpnPhase.connected);
    store.observe(VpnPhase.fromServiceName('new-state'));
    check(
      !store.snapshot.confirmed &&
          !store.snapshot.started &&
          !store.snapshot.toggleEnabled,
      'Unknown interpreted as known state',
    );
  });
  test('diagnostics and dismissal do not alter service phase', () {
    final store = VpnStateStore()..observe(VpnPhase.connected);
    store.reportFailure(const VpnFailure(VpnFailureKind.serviceExit));
    check(
      store.snapshot.started && store.snapshot.indicator == VpnIndicator.error,
      'Diagnostic inferred disconnect',
    );
    store.dismissFailure();
    check(store.snapshot.started && store.snapshot.failure == null, 'Dismiss');
  });
  stdout.writeln('$passed tests passed');
}
