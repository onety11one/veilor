import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'windows_port_owner.dart';
import 'command_reply.dart';
import 'windows_launch_plan.dart';

/// Lab observations, deliberately separate from FlutterVpnServiceState.
enum LabPhase { starting, readySignalReceived, stopped, failed }

enum LabFailure {
  timeout,
  earlyExit,
  invalidAnnouncement,
  http,
  notRunning,
  ownershipMismatch,
  ownershipUnavailable,
  invalidReply,
  commandRejected
}

final class LabException implements Exception {
  const LabException(this.failure);
  final LabFailure failure;
  @override
  String toString() => 'LabException(${failure.name})';
}

enum MockScenario {
  normal,
  noReady,
  earlyExit,
  noStopExit,
  httpError,
  redirect,
  oversized,
  hanging,
  crashAfterReady,
  invalidAnnouncement,
  foreignControl,
  commandError,
  commandErrorExit,
  malformedReply,
  missingErrorField,
  wrongErrorType,
  missingExtra,
  releaseControl,
}

final class LabStopResult {
  const LabStopResult(this.exitCode, {required this.forced});
  final int exitCode;
  final bool forced;
}

/// Owns ONLY the bundled synthetic Dart child. No arbitrary exe/port input.
/// Not a production backend and not proof that a VPN tunnel is working.
final class MockCoreSession {
  MockCoreSession._(this._directory);

  final Directory _directory;
  Process? _process;
  Future<int>? _exit;
  ServerSocket? _readyListener;
  StreamSubscription<Socket>? _readySubscription;
  StreamSubscription<String>? _stdoutSubscription;
  final _announcement = Completer<int>();
  final _ready = Completer<void>();
  LabPhase _phase = LabPhase.starting;
  int? _controlPort;
  int? _exitCode;
  bool _stopping = false;
  Future<LabStopResult>? _stop;
  WindowsPortOwner? _portOwner;
  WindowsLaunchPlan? _launchPlan;

  LabPhase get phase => _phase;
  int get pid => _process!.pid;
  int get parentPort => _readyListener!.port;
  int get controlPort => _controlPort!;
  int? get exitCode => _exitCode;
  Future<int> get whenExited => _exit!;
  String get workingDirectory => _directory.path;

  static Future<MockCoreSession> start({
    MockScenario scenario = MockScenario.normal,
    Duration timeout = const Duration(seconds: 5),
    int? foreignPortForTest,
    bool fixedPortPlan = false,
    Directory? workspaceParent,
  }) async {
    if (timeout <= Duration.zero) throw ArgumentError.value(timeout, 'timeout');
    if (!fixedPortPlan && workspaceParent != null)
      throw ArgumentError('workspaceParent requires fixed-port plan');
    if (scenario == MockScenario.foreignControl &&
        (foreignPortForTest == null ||
            foreignPortForTest < 1 ||
            foreignPortForTest > 65535)) {
      throw ArgumentError('foreignControl requires a test listener port');
    }
    if (fixedPortPlan &&
        (scenario == MockScenario.foreignControl ||
            scenario == MockScenario.invalidAnnouncement)) {
      throw ArgumentError('Announcement scenarios require announcement mode');
    }
    final plan = fixedPortPlan
        ? await WindowsLaunchPlan.prepare(
            core: {
              'outbounds': [
                {'type': 'direct', 'tag': 'synthetic'}
              ]
            },
            serviceOptions: {'labOnly': true},
            temporaryParent: workspaceParent,
          )
        : null;
    final session = MockCoreSession._(plan?.directory ??
        await Directory.systemTemp.createTemp('veilor-transport-lab-'));
    session._launchPlan = plan;
    session._controlPort = plan?.controlPort;
    try {
      // Bind before starting the child; port 0 lets the OS allocate atomically.
      final listener = plan?.parentListener ??
          await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      session._readyListener = listener;
      session._readySubscription = listener.listen((socket) {
        socket.destroy();
        if (!session._ready.isCompleted) session._ready.complete();
      });
      final config = plan?.serviceConfig ??
          File('${session._directory.path}/service.json');
      if (plan == null)
        await config.writeAsString(jsonEncode({
          'labOnly': true,
          if (scenario == MockScenario.foreignControl)
            'foreignPort': foreignPortForTest,
        }));
      final script = File.fromUri(
        Platform.script.resolve('../tool/mock_core.dart'),
      );
      // Tests live under test/ and the demonstration entry point under tool/.
      // No shell and no installed Karing executable is involved.
      // The SDK's dart.exe CLI spawns dartvm.exe on this Windows SDK. Start
      // the VM directly so the owned Process PID is the socket owner PID.
      final runtime = File.fromUri(
          File(Platform.resolvedExecutable).uri.resolve('dartvm.exe'));
      if (!await runtime.exists())
        throw UnsupportedError('Direct Dart VM is required');
      await plan?.releaseControlLease();
      final process = await Process.start(
        runtime.path,
        [
          script.path,
          if (plan != null)
            ...plan.arguments
          else ...[
            'run2',
            '--service-config', config.path,
            '--service-http-port',
            '0', // Mock-only atomic allocation extension.
            '--connected-port', '${listener.port}',
          ],
          '--mock-scenario',
          scenario.name,
        ],
        workingDirectory:
            plan?.workingDirectory.path ?? session._directory.path,
        runInShell: false,
      );
      session._process = process;
      session._exit = process.exitCode.then((code) {
        session._exitCode = code;
        if (!session._stopping) session._phase = LabPhase.failed;
        return code;
      });
      // Drain both pipes, without retaining diagnostics or raw config values.
      unawaited(process.stderr.drain<void>());
      if (plan != null) {
        unawaited(process.stdout.drain<void>());
      } else {
        session._stdoutSubscription = process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
          session._readAnnouncement,
          onError: (Object _) {
            session._rejectAnnouncement();
          },
        );
      }
      final initialized = Future.wait<Object?>([
        if (plan == null) session._announcement.future,
        session._ready.future,
      ]);
      await Future.any<Object?>([
        initialized,
        session._exit!.then<Object?>((_) {
          throw const LabException(LabFailure.earlyExit);
        }),
      ]).timeout(timeout);
      if (session._exitCode != null) {
        throw const LabException(LabFailure.earlyExit);
      }
      session._controlPort ??= await session._announcement.future;
      session._verifyOwner();
      session._phase = LabPhase.readySignalReceived;
      return session;
    } on TimeoutException {
      await session._abort();
      throw const LabException(LabFailure.timeout);
    } catch (_) {
      await session._abort();
      rethrow;
    }
  }

  void _rejectAnnouncement() {
    if (!_announcement.isCompleted) {
      _announcement.completeError(
        const LabException(LabFailure.invalidAnnouncement),
      );
    }
  }

  void _readAnnouncement(String line) {
    if (_announcement.isCompleted) return;
    try {
      final value = jsonDecode(line);
      if (value is! Map<String, dynamic> ||
          value['controlPort'] is! int ||
          (value['controlPort'] as int) < 1 ||
          (value['controlPort'] as int) > 65535) {
        _rejectAnnouncement();
        return;
      }
      _announcement.complete(value['controlPort'] as int);
    } catch (_) {
      _rejectAnnouncement();
    }
  }

  Future<void> reload({Duration timeout = const Duration(seconds: 2)}) =>
      _request('/reload/', timeout);

  void _verifyOwner() {
    if (_exitCode != null) throw const LabException(LabFailure.notRunning);
    int? owner;
    try {
      owner = (_portOwner ??= WindowsPortOwner()).listenerPid(controlPort);
    } catch (_) {
      throw const LabException(LabFailure.ownershipUnavailable);
    }
    if (owner != pid) {
      throw const LabException(LabFailure.ownershipMismatch);
    }
  }

  Future<void> _request(String path, Duration timeout) async {
    if (_phase != LabPhase.readySignalReceived || _exitCode != null) {
      throw const LabException(LabFailure.notRunning);
    }
    _verifyOwner();
    final client = HttpClient()
      ..findProxy = ((_) => 'DIRECT')
      ..connectionTimeout = timeout;
    try {
      await (() async {
        final request = await client.getUrl(
          Uri(scheme: 'http', host: '127.0.0.1', port: controlPort, path: path),
        );
        request.followRedirects = false;
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) {
          throw const LabException(LabFailure.http);
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          if (bytes.length + chunk.length > 16384)
            throw const LabException(LabFailure.http);
          bytes.addAll(chunk);
        }
        ReplyKind reply;
        try {
          reply = parseCommandReply(bytes, reload: path == '/reload/');
        } on FormatException {
          throw const LabException(LabFailure.invalidReply);
        }
        if (reply == ReplyKind.rejected)
          throw const LabException(LabFailure.commandRejected);
      })()
          .timeout(timeout);
    } on TimeoutException {
      throw const LabException(LabFailure.timeout);
    } on LabException {
      rethrow;
    } catch (_) {
      throw const LabException(LabFailure.http);
    } finally {
      client.close(force: true);
    }
  }

  Future<LabStopResult> stop({Duration timeout = const Duration(seconds: 2)}) =>
      _stop ??= _stopOwned(timeout);

  Future<LabStopResult> _stopOwned(Duration timeout) async {
    _stopping = true;
    var forced = false;
    try {
      if (_exitCode == null) {
        try {
          await _request('/stop/', timeout);
          await _exit!.timeout(timeout);
        } catch (_) {
          // Kill only the Process object created by this session.
          if (_exitCode == null) {
            forced = true;
            _process!.kill();
          }
        }
      }
      final code = await _exit!.timeout(const Duration(seconds: 5));
      _phase = LabPhase.stopped;
      return LabStopResult(code, forced: forced);
    } finally {
      await _disposeResources();
    }
  }

  Future<void> _abort() async {
    _stopping = true;
    if (_process != null && _exitCode == null) _process!.kill();
    if (_exit != null) await _exit!.timeout(const Duration(seconds: 5));
    _phase = LabPhase.failed;
    await _disposeResources();
  }

  Future<void> _disposeResources() async {
    await _stdoutSubscription?.cancel();
    await _readySubscription?.cancel();
    await _readyListener?.close();
    if (_launchPlan != null) {
      await _launchPlan!.close();
    } else if (await _directory.exists()) {
      await _directory.delete(recursive: true);
    }
  }
}
