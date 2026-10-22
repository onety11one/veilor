import 'dart:async';
import 'package:veilor_vpn_state/veilor_vpn_state.dart';
import 'package:veilor_vpn_state/transport_bridge.dart';
import 'veilor_core_transport_lab.dart';

/// Integration adapter for synthetic processes only. No method here invents
/// a connected/disconnected callback, and no verified-state source is wired.
final class LabVpnController {
  final _bridge = VpnTransportBridge();
  final _changes = StreamController<TransportVpnSnapshot>.broadcast();
  MockCoreSession? _session;
  TransportSessionToken? _token;
  Future<void>? _exitHandling;
  Future<void>? _stopping;
  Future<void>? _startFuture;
  Future<void>? _disposeFuture;
  bool _disposed = false;
  bool _closing = false;
  bool _starting = false;

  TransportVpnSnapshot get snapshot => _bridge.snapshot;
  Stream<TransportVpnSnapshot> get changes => _changes.stream;
  void _emit() {
    if (!_disposed) _changes.add(snapshot);
  }

  Future<void> start({
    MockScenario scenario = MockScenario.normal,
    Duration timeout = const Duration(seconds: 5),
    bool fixedPortPlan = false,
  }) {
    if (_disposed || _closing)
      throw StateError('Controller closing or disposed');
    if (_starting || _session != null)
      throw StateError('Session is still owned');
    return _startFuture = _start(scenario, timeout, fixedPortPlan);
  }

  Future<void> _start(
      MockScenario scenario, Duration timeout, bool fixedPortPlan) async {
    final token = _bridge.beginSession();
    if (token == null) throw StateError('Session is still owned');
    _starting = true;
    _token = token;
    _stopping = null;
    _emit();
    try {
      final session = await MockCoreSession.start(
          scenario: scenario, timeout: timeout, fixedPortPlan: fixedPortPlan);
      _session = session;
      _bridge.ready(token);
      _emit();
      _exitHandling = session.whenExited.then((_) => _onExit(token, session));
    } catch (error) {
      _bridge.startFailed(token, VpnFailure(_failure(error, preparing: true)));
      _token = null;
      _emit();
      rethrow;
    } finally {
      _starting = false;
    }
  }

  Future<void> _onExit(
      TransportSessionToken token, MockCoreSession session) async {
    if (!_bridge.processExited(token)) return;
    _emit();
    if (snapshot.stage == TransportStage.stopping) return;
    // Reap resources on unexpected exit, without clearing the failure state.
    await session.stop();
    _bridge.closed(token);
    if (identical(_session, session)) {
      _session = null;
      _token = null;
    }
    _emit();
  }

  Future<void> reload({Duration timeout = const Duration(seconds: 2)}) async {
    if (_disposed || _closing || _session == null || _token == null)
      throw StateError('No session');
    final command = _bridge.beginReload(_token!);
    if (command == null) throw StateError('Command already pending');
    final session = _session!;
    _emit();
    try {
      await session.reload(timeout: timeout);
      _bridge.finishReload(command);
    } catch (error) {
      _bridge.finishReload(command, failure: VpnFailure(_failure(error)));
      rethrow;
    } finally {
      _emit();
    }
  }

  Future<void> stop({Duration timeout = const Duration(seconds: 2)}) {
    if (_starting) throw StateError('Start is still pending');
    return _stopping ??= _stop(timeout);
  }

  Future<void> _stop(Duration timeout) async {
    final session = _session;
    final token = _token;
    if (session == null || token == null) return;
    if (!_bridge.beginStop(token)) {
      await _exitHandling;
      return;
    }
    _emit();
    final result = await session.stop(timeout: timeout);
    _bridge.processExited(token); // Idempotent if exit observer already ran.
    _bridge.closed(token, forced: result.forced);
    if (identical(_session, session)) {
      _session = null;
      _token = null;
    }
    _emit();
  }

  /// Waits for the bounded launch attempt, then reaps the owned session.
  Future<void> dispose() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    _closing = true;
    try {
      await _startFuture;
    } catch (_) {
      // start() already records the failure and the launcher cleans the child.
    }
    await stop();
    await _exitHandling;
    _disposed = true;
    await _changes.close();
  }

  static VpnFailureKind _failure(Object error, {bool preparing = false}) {
    if (error is LabException) {
      return switch (error.failure) {
        LabFailure.timeout => VpnFailureKind.timeout,
        LabFailure.earlyExit ||
        LabFailure.notRunning =>
          VpnFailureKind.serviceExit,
        LabFailure.ownershipMismatch ||
        LabFailure.ownershipUnavailable ||
        LabFailure.invalidAnnouncement =>
          VpnFailureKind.preparation,
        _ => VpnFailureKind.operation,
      };
    }
    return preparing ? VpnFailureKind.preparation : VpnFailureKind.operation;
  }
}
