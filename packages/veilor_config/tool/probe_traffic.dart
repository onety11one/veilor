import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../lib/veilor_config.dart';
import 'probe_lifecycle.dart'
    show ChildCore, listenerOwner, require, socksGreeting;

/// Local-only data path: HTTP proxy -> VLESS/WebSocket -> local HTTP origin.
/// Optional TLS with temporary per-process trust. No user profiles.
Future<void> main(List<String> args) async {
  final tlsMode = args.length == 3 && args[1] == '--tls';
  if (args.length != 1 && !tlsMode) {
    stderr.writeln(
        'Usage: dart run tool/probe_traffic.dart <verified-core.exe> [--tls <openssl.exe>]');
    exitCode = 64;
    return;
  }
  final executable = File(args.first).absolute.path;
  final temp = await Directory.systemTemp.createTemp('veilor-traffic-');
  final files = <File>[];
  final children = <ChildCore>[];
  final sockets = <ServerSocket>[];
  final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var originHits = 0;
  const uuid = '00000000-0000-4000-8000-000000000001';
  final payload = List<int>.generate(65536, (i) => i % 251);
  final expected = payload.reversed.toList();
  final observations = <Map<String, Object?>>[];
  final originSubscription = origin.listen((request) async {
    try {
      originHits++;
      final body = <int>[];
      await for (final chunk in request) {
        require(
            body.length + chunk.length <= payload.length, 'Origin body limit');
        body.addAll(chunk);
      }
      require(request.method == 'POST' && request.uri.path == '/synthetic',
          'Unexpected origin request');
      require(
          body.length == payload.length &&
              List.generate(body.length, (i) => body[i] == payload[i])
                  .every((v) => v),
          'Origin upload mismatch');
      request.response.headers.contentType = ContentType.binary;
      request.response.add(body.reversed.toList());
      await request.response.close();
    } catch (_) {
      request.response.statusCode = 500;
      await request.response.close();
    }
  });
  try {
    final trustedCert = File('${temp.path}/server-cert.pem');
    final trustedKey = File('${temp.path}/server-key.pem');
    final unrelatedCert = File('${temp.path}/unrelated-cert.pem');
    final unrelatedKey = File('${temp.path}/unrelated-key.pem');
    if (tlsMode) {
      files.addAll([trustedCert, trustedKey, unrelatedCert, unrelatedKey]);
      Future<void> certificate(File cert, File key, String name) async {
        final process = await Process.start(
            File(args[2]).absolute.path,
            [
              'req',
              '-x509',
              '-newkey',
              'rsa:2048',
              '-nodes',
              '-sha256',
              '-days',
              '1',
              '-subj',
              '/CN=$name',
              '-addext',
              'subjectAltName=DNS:$name',
              '-addext',
              'basicConstraints=critical,CA:TRUE',
              '-keyout',
              key.path,
              '-out',
              cert.path,
            ],
            workingDirectory: temp.path);
        final out = process.stdout.drain<void>();
        final err = process.stderr.drain<void>();
        try {
          require(
              await process.exitCode.timeout(const Duration(seconds: 15)) == 0,
              'Temporary certificate generation failed');
        } finally {
          process.kill();
          await process.exitCode;
          await Future.wait([out, err]);
        }
      }

      await certificate(trustedCert, trustedKey, 'veilor-test.invalid');
      await certificate(unrelatedCert, unrelatedKey, 'unrelated-test.invalid');
    }
    Future<int> freePort() async {
      final bound = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      sockets.add(bound);
      return bound.port;
    }

    final serverPort = await freePort();
    final clientPort = await freePort();
    for (final socket in sockets) {
      await socket.close();
    }
    sockets.clear();
    final serverConfig = <String, Object?>{
      'log': {'level': 'warn'},
      'inbounds': [
        {
          'type': 'vless',
          'tag': 'local-vless',
          'listen': '127.0.0.1',
          'listen_port': serverPort,
          'users': [
            {'uuid': uuid}
          ],
          'transport': {'type': 'ws', 'path': '/synthetic-test'},
        }
      ],
      'outbounds': [
        {'type': 'direct', 'tag': 'local-direct'}
      ],
      'route': {'final': 'local-direct'},
    };
    if (tlsMode) {
      ((serverConfig['inbounds'] as List<Object?>).single
          as Map<String, Object?>)['tls'] = {
        'enabled': true,
        'certificate_path': trustedCert.path,
        'key_path': trustedKey.path,
        'min_version': '1.2',
        'alpn': ['http/1.1'],
      };
    }
    final clientConfig = MinimalConfigBuilder().build(
      rawProfile: {
        'type': 'vless',
        'server': '127.0.0.1',
        'server_port': serverPort,
        'uuid': uuid,
        'transport': {'type': 'ws', 'path': '/synthetic-test'},
        if (tlsMode)
          'tls': {
            'enabled': true,
            'server_name': 'veilor-test.invalid',
            'certificate_path': trustedCert.path,
            'insecure': false,
            'min_version': '1.2',
            'alpn': ['http/1.1'],
          },
      },
      proxyTag: 'test-vless',
      listenPort: clientPort,
      dnsPlan: const SingleServerDnsPlan(
        resolverAddress: 'udp://127.0.0.1:59999',
        outboundAddress: 'udp://127.0.0.1:59999',
        directAddress: 'udp://127.0.0.1:59999',
        proxyAddress: 'udp://127.0.0.1:59999',
        directOutboundTag: 'test-direct',
        proxyOutboundTag: 'test-vless',
        strategy: DnsIpStrategy.preferIpv4,
      ),
    );
    final serverFile = File('${temp.path}/server.json');
    if (tlsMode) {
      clientConfig['log'] = {'level': 'debug'};
    }
    final clientFile = File('${temp.path}/client.json');
    files.addAll([serverFile, clientFile]);
    await serverFile.writeAsString(jsonEncode(serverConfig));
    await clientFile.writeAsString(jsonEncode(clientConfig));

    Future<ChildCore> launch(File file, int port, {bool mixed = false}) async {
      final child = ChildCore(await Process.start(
          executable, ['run', '--disable-color', '-c', file.path],
          workingDirectory: temp.path));
      children.add(child);
      final deadline = DateTime.now().add(const Duration(seconds: 8));
      var ready = false;
      while (DateTime.now().isBefore(deadline)) {
        require(child.exitValue == null,
            'Core startup failed: ${child.diagnostic}');
        try {
          if (mixed) {
            await socksGreeting(port);
          } else {
            final socket = await Socket.connect(
                InternetAddress.loopbackIPv4, port,
                timeout: const Duration(milliseconds: 200));
            socket.destroy();
          }
          ready = true;
          break;
        } on SocketException {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
      require(ready && await listenerOwner(port) == child.process.pid,
          'Readiness/owner check failed');
      return child;
    }

    Future<bool> transfer() async {
      final http = HttpClient()
        ..findProxy = ((_) => 'PROXY 127.0.0.1:$clientPort')
        ..connectionTimeout = const Duration(seconds: 2);
      try {
        return await (() async {
          final request = await http
              .postUrl(Uri.parse('http://127.0.0.1:${origin.port}/synthetic'));
          request.followRedirects = false;
          request.contentLength = payload.length;
          request.add(payload);
          final response = await request.close();
          final received = <int>[];
          await for (final chunk in response) {
            require(received.length + chunk.length <= expected.length,
                'Response limit');
            received.addAll(chunk);
          }
          return response.statusCode == 200 &&
              received.length == expected.length &&
              List.generate(received.length, (i) => received[i] == expected[i])
                  .every((v) => v);
        })()
            .timeout(const Duration(seconds: 5));
      } on Exception {
        return false;
      } finally {
        http.close(force: true);
      }
    }

    var server = await launch(serverFile, serverPort);
    var client = await launch(clientFile, clientPort, mixed: true);
    require(
        await transfer() && originHits == 1, 'Initial VLESS transfer failed');
    observations.add({
      'case': 'round-trip',
      'uploadBytes': payload.length,
      'downloadBytes': expected.length,
      'exactBytesVerified': true
    });

    await server.terminate();
    require(!await transfer() && originHits == 1 && client.exitValue == null,
        'Unavailable server bypassed or client crashed');
    observations.add({
      'case': 'server-unavailable',
      'requestFailed': true,
      'originNotReached': true,
      'clientStillRunning': true
    });

    server = await launch(serverFile, serverPort);
    require(await transfer() && originHits == 2, 'Transfer did not recover');
    observations.add({'case': 'server-restarted', 'exactBytesVerified': true});

    await client.terminate();
    ((clientConfig['outbounds'] as List<Object?>).last
            as Map<String, Object?>)['uuid'] =
        '00000000-0000-4000-8000-000000000002';
    await clientFile.writeAsString(jsonEncode(clientConfig));
    client = await launch(clientFile, clientPort, mixed: true);
    require(!await transfer() && originHits == 2 && client.exitValue == null,
        'Wrong UUID accepted or bypassed');
    observations.add({
      'case': 'wrong-uuid',
      'requestFailed': true,
      'originNotReached': true,
      'clientStillRunning': true
    });
    if (tlsMode) {
      final proxy = (clientConfig['outbounds'] as List<Object?>).last
          as Map<String, Object?>;
      proxy['uuid'] = uuid;
      final tls = proxy['tls'] as Map<String, Object?>;
      for (final testCase in [
        'untrusted-certificate',
        'wrong-server-name',
        'trust-restored'
      ]) {
        await client.terminate();
        tls['certificate_path'] = testCase == 'untrusted-certificate'
            ? unrelatedCert.path
            : trustedCert.path;
        tls['server_name'] = testCase == 'wrong-server-name'
            ? 'wrong-name.invalid'
            : 'veilor-test.invalid';
        require(
            tls['insecure'] == false, 'TLS verification unexpectedly disabled');
        await clientFile.writeAsString(jsonEncode(clientConfig));
        client = await launch(clientFile, clientPort, mixed: true);
        final passed = await transfer();
        if (testCase == 'trust-restored') {
          require(passed && originHits == 3, 'Trusted TLS did not recover');
          observations.add({'case': testCase, 'exactBytesVerified': true});
        } else {
          require(!passed && originHits == 2 && client.exitValue == null,
              'Invalid TLS certificate accepted or client crashed');
          require(
              testCase == 'untrusted-certificate'
                  ? client.diagnostic.contains('unknown authority')
                  : client.diagnostic.contains('certificate is valid for') &&
                      client.diagnostic.contains('wrong-name.invalid'),
              'Expected certificate failure diagnostic missing for $testCase: ${client.diagnostic}');
          observations.add({
            'case': testCase,
            'requestFailed': true,
            'originNotReached': true,
            'certificateFailureVerified': true,
            'clientStillRunning': true
          });
        }
      }
    }
    await client.terminate();
    await server.terminate();
    for (final port in [clientPort, serverPort]) {
      final bound = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      await bound.close();
    }
    stdout.writeln(const JsonEncoder.withIndent('  ').convert({
      'scope': tlsMode
          ? 'local HTTP -> mixed -> VLESS/WebSocket/TLS -> local HTTP'
          : 'local HTTP -> mixed -> VLESS over WebSocket -> local HTTP; no TLS',
      'tlsVerificationEnabled': tlsMode,
      'systemTrustChanged': false,
      'pids': children.map((c) => c.process.pid).toList(),
      'ports': [clientPort, serverPort, origin.port],
      'originHits': originHits,
      'corePortsReleased': true,
      'results': observations,
    }));
  } finally {
    for (final child in children) {
      await child.terminate();
    }
    for (final socket in sockets) {
      await socket.close();
    }
    await origin.close(force: true);
    await originSubscription.cancel();
    for (final file in files) {
      if (await file.exists()) await file.delete();
    }
    await temp.delete();
  }
}
