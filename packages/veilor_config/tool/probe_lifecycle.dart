import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../lib/veilor_config.dart';

void require(bool condition, String reason) {
  if (!condition) throw StateError(reason);
}

Future<void> socksGreeting(int port) async {
  final socket = await Socket.connect(InternetAddress.loopbackIPv4, port,
      timeout: const Duration(milliseconds: 300));
  try {
    // Negotiate SOCKS5 only. No CONNECT, DNS query or destination is sent.
    socket.add([5, 1, 0]);
    await socket.flush();
    final bytes = <int>[];
    await for (final chunk
        in socket.timeout(const Duration(milliseconds: 500))) {
      bytes.addAll(chunk);
      if (bytes.length >= 2) break;
    }
    require(bytes.length >= 2 && bytes[0] == 5 && bytes[1] == 0,
        'Unexpected SOCKS5 negotiation');
  } finally {
    socket.destroy();
  }
}

Future<int> listenerOwner(int port) async {
  if (!Platform.isWindows) throw UnsupportedError('Windows probe only');
  final result = await Process.run('powershell.exe', [
    '-NoProfile',
    '-NonInteractive',
    '-Command',
    '(Get-NetTCPConnection -State Listen -LocalAddress 127.0.0.1 '
        '-LocalPort $port -ErrorAction Stop).OwningProcess',
  ]).timeout(const Duration(seconds: 10));
  require(result.exitCode == 0, 'Cannot verify listener process owner');
  return int.parse((result.stdout as String).trim());
}

final class ChildCore {
  ChildCore(this.process) {
    // Keep at most 16 KiB combined synthetic-run diagnostics, drain the rest.
    void capture(List<int> chunk) {
      if (_diagnostic.length < 16384) {
        _diagnostic.addAll(chunk.take(16384 - _diagnostic.length));
      }
    }

    outDone = process.stdout.listen(capture).asFuture<void>();
    errDone = process.stderr.listen(capture).asFuture<void>();
    exited = process.exitCode.then((code) {
      exitValue = code;
      return code;
    });
  }
  final Process process;
  late final Future<void> outDone;
  late final Future<void> errDone;
  late final Future<int> exited;
  int? exitValue;
  final List<int> _diagnostic = [];
  String get diagnostic => utf8.decode(_diagnostic, allowMalformed: true);

  Future<int> terminate() async {
    if (exitValue == null) {
      process.kill();
    }
    try {
      return await exited.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      return await exited.timeout(const Duration(seconds: 5));
    } finally {
      await Future.wait([outDone, errDone]);
    }
  }
}

/// Isolated lifecycle experiment. Fixed synthetic config; loopback-only input;
/// no system proxy, TUN, service install, outbound requests or user settings.
Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln(
        'Usage: dart run tool/probe_lifecycle.dart <verified-core.exe>');
    exitCode = 64;
    return;
  }
  final executable = File(args.single).absolute.path;
  final directory = await Directory.systemTemp.createTemp('veilor-lifecycle-');
  final file = File('${directory.path}/synthetic.json');
  final children = <ChildCore>[];
  ServerSocket? reservation;
  final results = <Map<String, Object?>>[];
  try {
    reservation = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = reservation.port;
    await reservation.close();
    reservation = null;
    final raw =
        jsonDecode(File('test/fixtures/vless_profile.json').readAsStringSync());
    final config = MinimalConfigBuilder().build(
      rawProfile: raw,
      proxyTag: 'test-vless',
      listenPort: port,
      dnsPlan: const SingleServerDnsPlan(
        resolverAddress: 'udp://192.0.2.53',
        outboundAddress: 'udp://192.0.2.54',
        directAddress: 'tls://dns-direct.example.invalid',
        proxyAddress: 'https://dns.example.invalid/dns-query',
        directOutboundTag: 'test-direct',
        proxyOutboundTag: 'test-vless',
        strategy: DnsIpStrategy.preferIpv4,
      ),
    );
    await file.writeAsString(jsonEncode(config));

    Future<ChildCore> launch() async {
      final process = await Process.start(
          executable, ['run', '--disable-color', '-c', file.path],
          workingDirectory: directory.path);
      final child = ChildCore(process);
      children.add(child);
      return child;
    }

    for (var cycle = 1; cycle <= 2; cycle++) {
      final child = await launch();
      final deadline = DateTime.now().add(const Duration(seconds: 8));
      var ready = false;
      while (DateTime.now().isBefore(deadline)) {
        require(child.exitValue == null,
            'Core exited before readiness: ${child.diagnostic}');
        try {
          await socksGreeting(port);
          ready = true;
          break;
        } on SocketException {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
      require(ready, 'Core readiness deadline exceeded');
      final owner = await listenerOwner(port);
      require(owner == child.process.pid, 'Listener is not owned by our child');
      final stopped = await child.terminate();
      // Binding the same port proves listener cleanup (without reuse/shared).
      reservation = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      await reservation.close();
      reservation = null;
      results.add({
        'case': 'start-stop-$cycle',
        'pid': child.process.pid,
        'port': port,
        'socks5Negotiated': true,
        'listenerOwnerVerified': true,
        'processExited': child.exitValue != null,
        'exitCode': stopped,
        'portReusable': true,
        'stopMechanism': 'terminate owned process; not service graceful stop',
      });
    }

    // Conflict belongs to this test. Never stop an arbitrary port owner.
    reservation = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    final failed = await launch();
    final code = await failed.exited.timeout(const Duration(seconds: 8));
    require(code != 0, 'Occupied port did not cause startup failure');
    require(
        await listenerOwner(port) == pid, 'Original test listener disturbed');
    results.add({
      'case': 'occupied-port',
      'pid': failed.process.pid,
      'exitCode': code,
      'startupFailureDetected': true,
      'originalListenerPreserved': true,
    });
    await reservation.close();
    reservation = null;
    final released =
        await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    await released.close();
    // Regression: check accepted this config, run rejects its direct detour.
    final dns = config['dns'] as Map<String, Object?>;
    final bootstrap =
        (dns['servers'] as List<Object?>).first as Map<String, Object?>;
    bootstrap['detour'] = 'test-direct';
    await file.writeAsString(jsonEncode(config));
    final invalidDns = await launch();
    final invalidCode =
        await invalidDns.exited.timeout(const Duration(seconds: 8));
    await invalidDns.errDone;
    require(
        invalidCode != 0 &&
            invalidDns.diagnostic.contains('empty direct outbound'),
        'Expected runtime DNS detour rejection');
    results.add({
      'case': 'empty-direct-dns-detour',
      'pid': invalidDns.process.pid,
      'exitCode': invalidCode,
      'runtimeRejectionDetected': true,
    });
    stdout.writeln(const JsonEncoder.withIndent('  ').convert({
      'scope': 'isolated loopback lifecycle; SOCKS greeting only',
      'vpnServiceRestored': false,
      'results': results,
    }));
  } finally {
    for (final child in children) {
      await child.terminate();
    }
    await reservation?.close();
    if (await file.exists()) await file.delete();
    await directory.delete();
  }
}
