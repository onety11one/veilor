import 'veilor_vpn_state.dart';

enum TransportStage { idle, starting, ready, stopping, stopped, failed }

final class TransportSessionToken {
  TransportSessionToken._();
}

final class TransportCommandToken {
  TransportCommandToken._(this._session, this._verifiedRevision);
  final TransportSessionToken _session;
  final int _verifiedRevision;
}

final class TransportVpnSnapshot {
  const TransportVpnSnapshot(this.stage, this.vpn, {required this.reloading});
  final TransportStage stage;
  final VpnSnapshot vpn;
  final bool reloading;
  bool get busy =>
      stage == TransportStage.starting ||
      stage == TransportStage.stopping ||
      reloading;
  bool get canShowSessionDuration =>
      stage == TransportStage.ready && vpn.canShowSessionDuration;
}

/// Pure policy for one OWNED session, not a global/system VPN status detector.
/// Transport readiness/HTTP success/exit never manufacture a VPN phase.
final class VpnTransportBridge {
  final _store = VpnStateStore();
  TransportStage _stage = TransportStage.idle;
  TransportSessionToken? _session;
  TransportCommandToken? _reload;
  bool _exited = false;
  int _verifiedRevision = 0;

  TransportVpnSnapshot get snapshot =>
      TransportVpnSnapshot(_stage, _store.snapshot, reloading: _reload != null);

  TransportSessionToken? beginSession() {
    if (_session != null) return null;
    final token = TransportSessionToken._();
    _session = token;
    _exited = false;
    _reload = null;
    _verifiedRevision = 0;
    _store.dismissFailure();
    _store.observe(VpnPhase.unknown);
    _stage = TransportStage.starting;
    return token;
  }

  bool _current(TransportSessionToken token) => identical(token, _session);
  bool ready(TransportSessionToken token) {
    if (!_current(token) || _exited || _stage != TransportStage.starting)
      return false;
    _stage = TransportStage.ready;
    return true;
  }

  /// Reserved for a verified service callback/currentState adapter. The lab
  /// transport has no such source; only tests call this until it is recovered.
  bool observeVerifiedState(TransportSessionToken token, VpnPhase phase) {
    if (!_current(token) || _exited || _stage != TransportStage.ready)
      return false;
    _verifiedRevision++;
    _store.observe(phase);
    return true;
  }

  TransportCommandToken? beginReload(TransportSessionToken token) {
    if (!_current(token) ||
        _exited ||
        _stage != TransportStage.ready ||
        _reload != null) return null;
    final command = TransportCommandToken._(token, _verifiedRevision);
    _reload = command;
    _store.observe(VpnPhase.unknown);
    return command;
  }

  bool finishReload(TransportCommandToken command, {VpnFailure? failure}) {
    if (!identical(command, _reload) || !_current(command._session) || _exited)
      return false;
    _reload = null;
    // A fresh verified callback must win over a late command result.
    if (_verifiedRevision == command._verifiedRevision && failure != null) {
      _store.reportFailure(failure);
    }
    return true;
  }

  bool beginStop(TransportSessionToken token) {
    if (!_current(token) || _exited || _stage != TransportStage.ready)
      return false;
    _reload = null; // Late reload completion cannot overwrite stop/exit.
    _store.observe(VpnPhase.unknown);
    _stage = TransportStage.stopping;
    return true;
  }

  bool processExited(TransportSessionToken token) {
    if (!_current(token) || _exited) return false;
    _exited = true;
    _reload = null;
    _store.observe(VpnPhase.unknown);
    if (_stage != TransportStage.stopping) {
      _stage = TransportStage.failed;
      _store.reportFailure(const VpnFailure(VpnFailureKind.serviceExit));
    }
    return true;
  }

  /// Caller has confirmed process exit AND disposed its resources. Releasing
  /// this token permits the next session; an exit alone is insufficient.
  bool closed(TransportSessionToken token, {bool forced = false}) {
    if (!_current(token) || !_exited) return false;
    _session = null;
    if (_stage == TransportStage.stopping) {
      _stage = TransportStage.stopped;
      if (forced)
        _store.reportFailure(const VpnFailure(VpnFailureKind.operation));
    }
    return true;
  }

  /// Start failed and the launcher has already reaped any child/cleaned up.
  bool startFailed(TransportSessionToken token, VpnFailure failure) {
    if (!_current(token) || _stage != TransportStage.starting) return false;
    _session = null;
    _exited = true;
    _stage = TransportStage.failed;
    _store.observe(VpnPhase.unknown);
    _store.reportFailure(failure);
    return true;
  }
}
