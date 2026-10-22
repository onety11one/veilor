/// Names observed at call sites, NOT a reconstruction of native enum ordinals.
enum VpnPhase {
  unknown,
  invalid,
  disconnected,
  connecting,
  connected,
  reasserting,
  disconnecting;

  static VpnPhase fromServiceName(String name) => switch (name) {
        'invalid' => invalid,
        'disconnected' => disconnected,
        'connecting' => connecting,
        'connected' => connected,
        'reasserting' => reasserting,
        'disconnecting' => disconnecting,
        _ => unknown,
      };

  bool get isTransition =>
      this == connecting || this == reasserting || this == disconnecting;
}

enum VpnOperation { start, stop, restart, reload }

/// Categories must come from explicit backend results, not text matching.
enum VpnFailureKind {
  preparation,
  operation,
  timeout,
  serviceExit,
  stateUnavailable,
}

/// No raw native parameters, stderr, server names or credentials in UI state.
final class VpnFailure {
  const VpnFailure(this.kind);
  final VpnFailureKind kind;
}

enum VpnIndicator { neutral, connected, error }

final class VpnSnapshot {
  const VpnSnapshot._({
    this.phase = VpnPhase.unknown,
    this.confirmed = false,
    this.pending,
    this.failure,
  });

  /// Last observation, which can be stale when confirmed is false.
  final VpnPhase phase;
  final bool confirmed;
  final VpnOperation? pending;
  final VpnFailure? failure;

  bool get busy => pending != null || (confirmed && phase.isTransition);
  bool get started => confirmed && phase == VpnPhase.connected;
  bool get toggleOn => started;
  bool get toggleEnabled =>
      confirmed &&
      !busy &&
      (phase == VpnPhase.invalid ||
          phase == VpnPhase.disconnected ||
          phase == VpnPhase.connected);

  /// Caller also needs a current core startTime; never start a timer here.
  bool get canShowSessionDuration => started;

  VpnIndicator get indicator => failure != null
      ? VpnIndicator.error
      : started
          ? VpnIndicator.connected
          : VpnIndicator.neutral;
}

/// Tokens are bound to this store and prevent late reads/results overwriting
/// newer observations. No ordering guarantees of the missing native plugin
/// are assumed; future backend must subscribe before querying initial state.
final class StateReadToken {
  StateReadToken._(this._owner, this._revision, this._serial);
  final Object _owner;
  final int _revision;
  final int _serial;
}

final class OperationToken {
  OperationToken._(this._owner, this.operation, this._observation);
  final Object _owner;
  final VpnOperation operation;
  final int _observation;
}

/// Synchronous state reducer only. Does not launch/stop VPN, poll, read files,
/// use HTTP, change proxy settings or infer state from metrics/subscription.
final class VpnStateStore {
  final Object _identity = Object();
  VpnSnapshot _snapshot = const VpnSnapshot._();
  int _revision = 0;
  int _observation = 0;
  int _readSerial = 0;
  OperationToken? _operation;

  VpnSnapshot get snapshot => _snapshot;

  StateReadToken beginStateRead() =>
      StateReadToken._(_identity, _revision, ++_readSerial);

  bool completeStateRead(StateReadToken token, VpnPhase phase) {
    if (!_acceptRead(token)) return false;
    observe(phase);
    return true;
  }

  bool failStateRead(StateReadToken token) {
    if (!_acceptRead(token)) return false;
    _revision++;
    _snapshot = VpnSnapshot._(
      phase: _snapshot.phase,
      pending: _snapshot.pending,
      failure: const VpnFailure(VpnFailureKind.stateUnavailable),
    );
    return true;
  }

  bool _acceptRead(StateReadToken token) =>
      identical(token._owner, _identity) &&
      token._revision == _revision &&
      token._serial == _readSerial;

  /// Used only for a trusted service callback or accepted currentState read.
  /// Unknown/new names invalidate confirmation instead of meaning "off".
  void observe(VpnPhase phase) {
    _revision++;
    _observation++;
    var failure = _snapshot.failure;
    if (failure?.kind == VpnFailureKind.stateUnavailable ||
        (phase == VpnPhase.connected &&
            _snapshot.phase != VpnPhase.connected)) {
      failure = null;
    }
    _snapshot = VpnSnapshot._(
      phase: phase,
      confirmed: phase != VpnPhase.unknown,
      pending: _snapshot.pending,
      failure: failure,
    );
  }

  /// Local intent does not pretend that service has changed its phase.
  OperationToken? beginOperation(VpnOperation operation) {
    if (!_snapshot.toggleEnabled) return null;
    final connected = _snapshot.started;
    if (operation == VpnOperation.start ? connected : !connected) return null;
    final token = OperationToken._(_identity, operation, _observation);
    _operation = token;
    _revision++;
    _snapshot = VpnSnapshot._(
      phase: _snapshot.phase,
      confirmed: _snapshot.confirmed,
      pending: operation,
    );
    return token;
  }

  /// Even success cannot manufacture connected/disconnected. If no observation
  /// arrived during the command, require a fresh state read before another tap.
  bool completeOperation(OperationToken token, {VpnFailure? failure}) {
    if (!identical(token._owner, _identity) || !identical(token, _operation))
      return false;
    _operation = null;
    _revision++;
    _snapshot = VpnSnapshot._(
      phase: _snapshot.phase,
      confirmed: _snapshot.confirmed && _observation > token._observation,
      failure: failure ?? _snapshot.failure,
    );
    return true;
  }

  /// Explicit backend diagnostic; does not imply the service is disconnected.
  void reportFailure(VpnFailure failure) {
    _revision++;
    _snapshot = VpnSnapshot._(
      phase: _snapshot.phase,
      confirmed: _snapshot.confirmed,
      pending: _snapshot.pending,
      failure: failure,
    );
  }

  void dismissFailure() {
    _revision++;
    _snapshot = VpnSnapshot._(
      phase: _snapshot.phase,
      confirmed: _snapshot.confirmed,
      pending: _snapshot.pending,
    );
  }
}
