import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../lib/veilor_config.dart';
import 'probe_lifecycle.dart'
    show ChildCore, listenerOwner, require, socksGreeting;

bool same(List<int> a, List<int> b) =>
    a.length == b.length &&
    List.generate(a.length, (i) => a[i] == b[i]).every((v) => v);

final class SocksConnection {
  SocksConnection(this.socket) : input = StreamIterator(socket);
  final Socket socket;
  final StreamIterator<List<int>> input;
  final pending = <int>[];
  Future<List<int>> read(int count) async {
    while (pending.length < count) {
      require(await input.moveNext().timeout(const Duration(seconds: 2)),
          'Unexpected SOCKS/TCP EOF');
      pending.addAll(input.current);
      require(pending.length <= 131072, 'TCP response bound');
    }
    final result = pending.sublist(0, count);
    pending.removeRange(0, count);
    return result;
  }

  Future<int> request(int command, int port) async {
    socket.add([5, 1, 0]);
    await socket.flush();
    require(same(await read(2), [5, 0]), 'SOCKS auth negotiation');
    socket.add([
      5,
      command,
      0,
      1,
      ...command == 3 ? [0, 0, 0, 0] : [127, 0, 0, 1],
      port >> 8,
      port & 255
    ]);
    await socket.flush();
    final head = await read(4);
    require(head[0] == 5 && head[1] == 0 && head[2] == 0 && head[3] == 1,
        'SOCKS request rejected/unsupported reply');
    final bound = await read(6);
    require(
        same(bound.sublist(0, 4), [127, 0, 0, 1]) ||
            same(bound.sublist(0, 4), [0, 0, 0, 0]),
        'Nonlocal relay reply');
    return bound[4] * 256 + bound[5];
  }

  Future<void> close() async {
    socket.destroy();
    await input.cancel();
  }
}

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln(
        'Usage: dart run tool/probe_socks_udp.dart <verified-core.exe>');
    exitCode = 64;
    return;
  }
  final executable = File(args.single).absolute.path;
  final temp = await Directory.systemTemp.createTemp('veilor-socks-udp-');
  final files = <File>[];
  final children = <ChildCore>[];
  final activeTcp = <Socket>[];
  final tcpTarget = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final udpTarget =
      await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
  var tcpHits = 0;
  var udpHits = 0;
  final payload = List<int>.generate(65536, (i) => i % 251);
  final tcpSubscription = tcpTarget.listen((socket) async {
    activeTcp.add(socket);
    try {
      final body = <int>[];
      await for (final chunk in socket) {
        body.addAll(chunk);
        require(body.length <= payload.length, 'TCP upload bound');
        if (body.length == payload.length) {
          require(same(body, payload), 'TCP target received wrong bytes');
          tcpHits++;
          socket.add(body.reversed.toList());
          await socket.flush();
          break;
        }
      }
    } finally {
      socket.destroy();
    }
  });
  final udpSubscription = udpTarget.listen((event) {
    if (event == RawSocketEvent.read) {
      Datagram? packet;
      while ((packet = udpTarget.receive()) != null) {
        final value = packet!;
        require(value.address.isLoopback, 'Nonlocal datagram');
        udpHits++;
        udpTarget.send(value.data.reversed.toList(), value.address, value.port);
      }
    }
  });
  final reservations = <ServerSocket>[];
  try {
    Future<int> freePort() async {
      final bound = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      reservations.add(bound);
      return bound.port;
    }

    final serverPort = await freePort(), clientPort = await freePort();
    for (final s in reservations) {
      await s.close();
    }
    reservations.clear();
    const uuid = '00000000-0000-4000-8000-000000000001';
    final serverConfig = {
      'log': {'level': 'warn'},
      'inbounds': [
        {
          'type': 'vless',
          'tag': 'vless-local',
          'listen': '127.0.0.1',
          'listen_port': serverPort,
          'users': [
            {'uuid': uuid}
          ],
          'transport': {'type': 'ws', 'path': '/synthetic-test'}
        }
      ],
      'outbounds': [
        {'type': 'direct', 'tag': 'local-direct'}
      ],
      'route': {'final': 'local-direct'},
    };
    final clientConfig = MinimalConfigBuilder().build(
        rawProfile: {
          'type': 'vless',
          'server': '127.0.0.1',
          'server_port': serverPort,
          'uuid': uuid,
          'packet_encoding': 'xudp',
          'transport': {'type': 'ws', 'path': '/synthetic-test'},
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
            strategy: DnsIpStrategy.preferIpv4));
    final sf = File('${temp.path}/server.json'),
        cf = File('${temp.path}/client.json');
    files.addAll([sf, cf]);
    await sf.writeAsString(jsonEncode(serverConfig));
    await cf.writeAsString(jsonEncode(clientConfig));
    Future<ChildCore> launch(File file, int port, {bool mixed = false}) async {
      final child = ChildCore(await Process.start(
          executable, ['run', '--disable-color', '-c', file.path],
          workingDirectory: temp.path));
      children.add(child);
      final deadline = DateTime.now().add(const Duration(seconds: 8));
      var ready = false;
      while (DateTime.now().isBefore(deadline)) {
        require(child.exitValue == null, 'Startup failed: ${child.diagnostic}');
        try {
          if (mixed) {
            await socksGreeting(port);
          } else {
            final s = await Socket.connect(InternetAddress.loopbackIPv4, port,
                timeout: const Duration(milliseconds: 200));
            s.destroy();
          }
          ready = true;
          break;
        } on SocketException {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
      require(ready && await listenerOwner(port) == child.process.pid,
          'Listener ownership/readiness');
      return child;
    }

    Future<SocksConnection> connect() async => SocksConnection(
        await Socket.connect(InternetAddress.loopbackIPv4, clientPort,
            timeout: const Duration(seconds: 1)));
    Future<bool> tcpTransfer() async {
      final connection = await connect();
      try {
        await connection.request(1, tcpTarget.port);
        connection.socket.add(payload);
        await connection.socket.flush();
        return same(
            await connection.read(payload.length), payload.reversed.toList());
      } catch (_) {
        return false;
      } finally {
        await connection.close();
      }
    }

    Future<bool> udpTransfer(int size) async {
      final control = await connect();
      final udp = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      StreamSubscription<RawSocketEvent>? subscription;
      try {
        final relay = await control.request(3, 0);
        require(relay > 0, 'No UDP relay port');
        final body = List<int>.generate(size, (i) => (i + size) % 251);
        final received = Completer<bool>();
        subscription = udp.listen((event) {
          if (event != RawSocketEvent.read) return;
          final packet = udp.receive();
          if (packet == null || received.isCompleted) return;
          final data = packet.data;
          received.complete(packet.address.isLoopback &&
              packet.port == relay &&
              data.length == body.length + 10 &&
              same(data.sublist(0, 4), [0, 0, 0, 1]) &&
              same(data.sublist(4, 8), [127, 0, 0, 1]) &&
              data[8] * 256 + data[9] == udpTarget.port &&
              same(data.sublist(10), body.reversed.toList()));
        });
        final bytes = [
          0,
          0,
          0,
          1,
          127,
          0,
          0,
          1,
          udpTarget.port >> 8,
          udpTarget.port & 255,
          ...body
        ];
        require(
            udp.send(bytes, InternetAddress.loopbackIPv4, relay) ==
                bytes.length,
            'UDP send failed');
        return await received.future.timeout(const Duration(milliseconds: 1200),
            onTimeout: () => false);
      } catch (_) {
        return false;
      } finally {
        udp.close();
        await subscription?.cancel();
        await control.close();
      }
    }

    var server = await launch(sf, serverPort);
    var client = await launch(cf, clientPort, mixed: true);
    require(
        await tcpTransfer() && tcpHits == 1, 'SOCKS CONNECT transfer failed');
    for (final size in [1, 128, 1200, 4096]) {
      require(await udpTransfer(size),
          'SOCKS UDP/XUDP transfer failed for $size bytes');
    }
    require(udpHits == 4, 'Unexpected UDP target traffic');
    await server.terminate();
    require(
        !await tcpTransfer() &&
            !await udpTransfer(128) &&
            tcpHits == 1 &&
            udpHits == 4,
        'Unavailable server bypassed');
    require(client.exitValue == null, 'Client crashed');
    server = await launch(sf, serverPort);
    require(
        await tcpTransfer() &&
            await udpTransfer(1200) &&
            tcpHits == 2 &&
            udpHits == 5,
        'Recovery failed');
    await client.terminate();
    ((clientConfig['outbounds'] as List<Object?>).last
            as Map<String, Object?>)['uuid'] =
        '00000000-0000-4000-8000-000000000002';
    await cf.writeAsString(jsonEncode(clientConfig));
    client = await launch(cf, clientPort, mixed: true);
    require(
        !await tcpTransfer() &&
            !await udpTransfer(128) &&
            tcpHits == 2 &&
            udpHits == 5,
        'Wrong UUID accepted or bypassed');
    require(client.exitValue == null, 'Client crashed on bad UUID');
    await client.terminate();
    await server.terminate();
    for (final port in [clientPort, serverPort]) {
      final socket =
          await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      await socket.close();
    }
    stdout.writeln(const JsonEncoder.withIndent('  ').convert({
      'scope':
          'loopback SOCKS5 CONNECT and UDP ASSOCIATE -> VLESS/WebSocket/XUDP; no TLS',
      'pids': children.map((c) => c.process.pid).toList(),
      'ports': [clientPort, serverPort, tcpTarget.port, udpTarget.port],
      'tcpRoundTripBytes': 65536,
      'udpPayloadSizes': [1, 128, 1200, 4096],
      'tcpTargetHits': tcpHits,
      'udpTargetHits': udpHits,
      'exactBytesVerified': true,
      'serverUnavailableRejected': true,
      'serverRestartRecovered': true,
      'wrongUuidRejected': true,
      'clientSurvivedFailures': true,
      'corePortsReleased': true,
    }));
  } finally {
    for (final child in children) {
      await child.terminate();
    }
    for (final s in reservations) {
      await s.close();
    }
    for (final s in activeTcp) {
      s.destroy();
    }
    await tcpTarget.close();
    await tcpSubscription.cancel();
    udpTarget.close();
    await udpSubscription.cancel();
    for (final f in files) {
      if (await f.exists()) await f.delete();
    }
    await temp.delete();
  }
}
