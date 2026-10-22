import 'dart:io';
import '../lib/veilor_vpn_state.dart';
import '../lib/transport_bridge.dart';

void check(bool value, String reason) {
  if (!value) throw StateError(reason);
}

void unconfirmed(VpnTransportBridge bridge) {
  final s = bridge.snapshot;
  check(
      !s.vpn.confirmed &&
          !s.vpn.started &&
          !s.vpn.toggleOn &&
          !s.vpn.canShowSessionDuration &&
          !s.canShowSessionDuration &&
          s.vpn.indicator != VpnIndicator.connected,
      'Unverified connection shown');
}

void main() {
  var passed = 0;
  void test(String name, void Function() action) {
    action();
    passed++;
    stdout.writeln('PASS $name');
  }

  test('launch and readiness cannot manufacture connected or off', () {
    final b = VpnTransportBridge();
    unconfirmed(b);
    final token = b.beginSession()!;
    check(b.snapshot.busy, 'Start not busy');
    check(!b.observeVerifiedState(token, VpnPhase.connected),
        'Callback before readiness accepted');
    b.ready(token);
    unconfirmed(b);
    check(b.snapshot.stage == TransportStage.ready && !b.snapshot.busy,
        'Readiness stage');
  });
  test('HTTP reload acknowledgement cannot confirm VPN', () {
    final b = VpnTransportBridge();
    final t = b.beginSession()!;
    b.ready(t);
    final command = b.beginReload(t)!;
    check(b.snapshot.reloading, 'Missing pending reload');
    b.finishReload(command);
    unconfirmed(b);
  });
  test('only explicit verified state enables green and timer', () {
    final b = VpnTransportBridge();
    final t = b.beginSession()!;
    b.ready(t);
    b.observeVerifiedState(t, VpnPhase.connected);
    check(
        b.snapshot.vpn.indicator == VpnIndicator.connected &&
            b.snapshot.canShowSessionDuration,
        'Verified connection lost');
    b.observeVerifiedState(t, VpnPhase.unknown);
    unconfirmed(b);
  });
  test('reload invalidates old connected observation', () {
    final b = VpnTransportBridge();
    final t = b.beginSession()!;
    b.ready(t);
    b.observeVerifiedState(t, VpnPhase.connected);
    final command = b.beginReload(t)!;
    unconfirmed(b);
    b.finishReload(command);
    unconfirmed(b);
  });
  test('newer verified callback wins over late reload error', () {
    final b = VpnTransportBridge();
    final t = b.beginSession()!;
    b.ready(t);
    final command = b.beginReload(t)!;
    b.observeVerifiedState(t, VpnPhase.connected);
    b.finishReload(command, failure: const VpnFailure(VpnFailureKind.timeout));
    check(b.snapshot.vpn.started && b.snapshot.vpn.failure == null,
        'Late result overwrote callback');
  });
  test('command rejection produces error without guessing off', () {
    final b = VpnTransportBridge();
    final t = b.beginSession()!;
    b.ready(t);
    final command = b.beginReload(t)!;
    b.finishReload(command,
        failure: const VpnFailure(VpnFailureKind.operation));
    unconfirmed(b);
    check(
        b.snapshot.vpn.failure?.kind == VpnFailureKind.operation &&
            b.snapshot.vpn.indicator == VpnIndicator.error,
        'Rejection not reported');
  });
  test('stop supersedes pending reload and rejects connected callbacks', () {
    final b = VpnTransportBridge();
    final t = b.beginSession()!;
    b.ready(t);
    final command = b.beginReload(t)!;
    b.beginStop(t);
    check(!b.finishReload(command), 'Late reload accepted');
    check(!b.observeVerifiedState(t, VpnPhase.connected),
        'Connected during stop');
    b.processExited(t);
    b.closed(t);
    check(
        b.snapshot.stage == TransportStage.stopped &&
            b.snapshot.vpn.failure == null,
        'Normal stop marked error');
    unconfirmed(b);
  });
  test('unexpected exit clears green and blocks late command result', () {
    final b = VpnTransportBridge();
    final t = b.beginSession()!;
    b.ready(t);
    final command = b.beginReload(t)!;
    b.observeVerifiedState(t, VpnPhase.connected);
    b.processExited(t);
    check(!b.finishReload(command), 'Result after exit accepted');
    unconfirmed(b);
    check(
        b.snapshot.stage == TransportStage.failed &&
            b.snapshot.vpn.failure?.kind == VpnFailureKind.serviceExit,
        'Exit failure missing');
  });
  test('exit alone does not permit new start before resource cleanup', () {
    final b = VpnTransportBridge();
    final t = b.beginSession()!;
    b.ready(t);
    check(!b.closed(t), 'Closed before exit');
    b.processExited(t);
    check(b.beginSession() == null, 'New process before cleanup');
    b.closed(t);
    check(b.beginSession() != null, 'Cannot start after cleanup');
  });
  test('old session cannot affect replacement', () {
    final b = VpnTransportBridge();
    final a = b.beginSession()!;
    b.ready(a);
    b.processExited(a);
    b.closed(a);
    final next = b.beginSession()!;
    b.ready(next);
    b.observeVerifiedState(next, VpnPhase.connected);
    check(
        !b.ready(a) &&
            !b.processExited(a) &&
            !b.closed(a) &&
            !b.observeVerifiedState(a, VpnPhase.disconnected),
        'Old session event accepted');
    check(b.snapshot.vpn.started, 'Replacement overwritten');
  });
  test('tokens cannot cross bridge instances', () {
    final a = VpnTransportBridge();
    final b = VpnTransportBridge();
    final ta = a.beginSession()!;
    b.beginSession();
    check(!b.ready(ta) && !b.processExited(ta) && !b.beginStop(ta),
        'Foreign token accepted');
  });
  test('duplicate starts, ready and reload results rejected', () {
    final b = VpnTransportBridge();
    final t = b.beginSession()!;
    check(b.beginSession() == null, 'Double start');
    b.ready(t);
    check(!b.ready(t), 'Duplicate ready');
    final command = b.beginReload(t)!;
    check(b.beginReload(t) == null, 'Double reload');
    b.finishReload(command);
    check(!b.finishReload(command), 'Duplicate result');
  });
  test('start timeout leaves unknown error and permits a clean retry', () {
    final b = VpnTransportBridge();
    final t = b.beginSession()!;
    b.startFailed(t, const VpnFailure(VpnFailureKind.timeout));
    unconfirmed(b);
    check(
        b.snapshot.vpn.failure?.kind == VpnFailureKind.timeout, 'Timeout lost');
    final retry = b.beginSession()!;
    b.ready(retry);
    check(b.snapshot.vpn.failure == null, 'Old failure survived new session');
    unconfirmed(b);
  });
  test('forced stop remains visible as an error, not connected', () {
    final b = VpnTransportBridge();
    final t = b.beginSession()!;
    b.ready(t);
    b.beginStop(t);
    b.processExited(t);
    b.closed(t, forced: true);
    unconfirmed(b);
    check(
        b.snapshot.stage == TransportStage.stopped &&
            b.snapshot.vpn.indicator == VpnIndicator.error,
        'Forced stop hidden');
  });
  stdout.writeln('$passed transport policy tests passed.');
}
