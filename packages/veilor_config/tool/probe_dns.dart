import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../lib/veilor_config.dart';
import 'probe_lifecycle.dart'
    show ChildCore, listenerOwner, require, socksGreeting;
import 'probe_socks_udp.dart' show SocksConnection, same;

List<int> query(String name, int id) => [
      id >> 8,
      id & 255,
      1,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      0,
      0,
      ...name.split('.').expand((s) => [s.length, ...ascii.encode(s)]),
      0,
      0,
      1,
      0,
      1
    ];

int nameEnd(List<int> bytes, int offset) {
  for (var limit = 0; limit < 64; limit++) {
    require(offset < bytes.length, 'Truncated DNS name');
    final size = bytes[offset++];
    if (size == 0) return offset;
    if ((size & 192) == 192) {
      require(offset < bytes.length, 'Truncated DNS pointer');
      return offset + 1;
    }
    require(size <= 63 && offset + size <= bytes.length, 'Invalid DNS label');
    offset += size;
  }
  throw StateError('DNS label bound');
}

bool answer(List<int> bytes, int id, List<int> expected) {
  if (bytes.length < 12 ||
      bytes[0] * 256 + bytes[1] != id ||
      (bytes[2] & 128) == 0 ||
      (bytes[3] & 15) != 0) return false;
  var offset = 12;
  for (var i = 0; i < bytes[4] * 256 + bytes[5]; i++) {
    offset = nameEnd(bytes, offset) + 4;
  }
  for (var i = 0; i < bytes[6] * 256 + bytes[7]; i++) {
    offset = nameEnd(bytes, offset);
    require(offset + 10 <= bytes.length, 'Truncated DNS RR');
    final type = bytes[offset] * 256 + bytes[offset + 1],
        klass = bytes[offset + 2] * 256 + bytes[offset + 3];
    final length = bytes[offset + 8] * 256 + bytes[offset + 9];
    offset += 10;
    require(offset + length <= bytes.length, 'Truncated DNS RDATA');
    if (type == 1 &&
        klass == 1 &&
        length == 4 &&
        same(bytes.sublist(offset, offset + 4), expected)) return true;
    offset += length;
  }
  return false;
}

final class DnsStub {
  DnsStub(this.socket, this.ip) {
    subscription = socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      Datagram? packet;
      while ((packet = socket.receive()) != null) {
        final p = packet!, bytes = p.data;
        require(
            p.address.isLoopback &&
                bytes.length >= 12 &&
                bytes[4] == 0 &&
                bytes[5] == 1,
            'Unexpected DNS request');
        final end = nameEnd(bytes, 12);
        final labels = <String>[];
        var index = 12;
        while (bytes[index] != 0) {
          final size = bytes[index++];
          labels.add(ascii.decode(bytes.sublist(index, index + size)));
          index += size;
        }
        final name = labels.join('.');
        require(
            name.endsWith('.test.invalid') &&
                bytes[end] == 0 &&
                bytes[end + 1] == 1,
            'Non-test/A DNS request');
        names.add(name);
        final response = [
          bytes[0],
          bytes[1],
          129,
          128,
          0,
          1,
          0,
          1,
          0,
          0,
          0,
          0,
          ...bytes.sublist(12, end + 4),
          192,
          12,
          0,
          1,
          0,
          1,
          0,
          0,
          0,
          0,
          0,
          4,
          ...ip
        ];
        socket.send(response, p.address, p.port);
      }
    });
  }
  final RawDatagramSocket socket;
  final List<int> ip;
  final names = <String>[];
  late final StreamSubscription<RawSocketEvent> subscription;
  Future<void> close() async {
    socket.close();
    await subscription.cancel();
  }
}

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('Usage: dart run tool/probe_dns.dart <verified-core.exe>');
    exitCode = 64;
    return;
  }
  final executable = File(args.single).absolute.path;
  final temp = await Directory.systemTemp.createTemp('veilor-dns-');
  final files = <File>[];
  final children = <ChildCore>[];
  final reservations = <ServerSocket>[];
  final direct = DnsStub(
      await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0),
      [192, 0, 2, 10]);
  final proxy = DnsStub(
      await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0),
      [192, 0, 2, 20]);
  final results = <Map<String, Object?>>[];
  try {
    Future<int> port() async {
      final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      reservations.add(s);
      return s.port;
    }

    final sp = await port(), cp = await port();
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
          'tag': 'local-vless',
          'listen': '127.0.0.1',
          'listen_port': sp,
          'users': [
            {'uuid': uuid}
          ],
          'transport': {'type': 'ws', 'path': '/synthetic-test'}
        }
      ],
      'outbounds': [
        {'type': 'direct', 'tag': 'local-direct'}
      ],
      'route': {'final': 'local-direct'}
    };
    final config = MinimalConfigBuilder().build(
        rawProfile: {
          'type': 'vless',
          'server': '127.0.0.1',
          'server_port': sp,
          'uuid': uuid,
          'packet_encoding': 'xudp',
          'transport': {'type': 'ws', 'path': '/synthetic-test'}
        },
        proxyTag: 'test-vless',
        listenPort: cp,
        dnsPlan: SingleServerDnsPlan(
            resolverAddress: 'udp://127.0.0.1:${direct.socket.port}',
            outboundAddress: 'udp://127.0.0.1:${direct.socket.port}',
            directAddress: 'udp://127.0.0.1:${direct.socket.port}',
            proxyAddress: 'udp://127.0.0.1:${proxy.socket.port}',
            directOutboundTag: 'test-direct',
            proxyOutboundTag: 'test-vless',
            strategy: DnsIpStrategy.ipv4Only));
    // Test-only explicit rule, not migration of the full Karing rules model.
    final dns = config['dns'] as Map<String, Object?>;
    dns['disable_cache'] = true;
    dns['rules'] = [
      {
        'domain_suffix': ['direct.test.invalid'],
        'action': 'route',
        'server': 'dns_direct_out'
      }
    ];
    final sf = File('${temp.path}/server.json'),
        cf = File('${temp.path}/client.json');
    files.addAll([sf, cf]);
    await sf.writeAsString(jsonEncode(serverConfig));
    await cf.writeAsString(jsonEncode(config));
    Future<ChildCore> launch(File file, int p, {bool mixed = false}) async {
      final child = ChildCore(await Process.start(
          executable, ['run', '--disable-color', '-c', file.path],
          workingDirectory: temp.path));
      children.add(child);
      var ready = false;
      final deadline = DateTime.now().add(const Duration(seconds: 8));
      while (DateTime.now().isBefore(deadline)) {
        require(child.exitValue == null,
            'Core startup failed: ${child.diagnostic}');
        try {
          if (mixed) {
            await socksGreeting(p);
          } else {
            final s = await Socket.connect(InternetAddress.loopbackIPv4, p,
                timeout: const Duration(milliseconds: 200));
            s.destroy();
          }
          ready = true;
          break;
        } on SocketException {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
      require(ready && await listenerOwner(p) == child.process.pid,
          'Listener ownership/readiness');
      return child;
    }

    var id = 100;
    Future<bool> resolve(String name, List<int> expected,
        {bool tcp = false}) async {
      final tx = ++id, request = query(name, id);
      final control = SocksConnection(await Socket.connect(
          InternetAddress.loopbackIPv4, cp,
          timeout: const Duration(seconds: 1)));
      RawDatagramSocket? udp;
      StreamSubscription<RawSocketEvent>? sub;
      try {
        if (tcp) {
          await control.request(1, 53);
          control.socket
              .add([request.length >> 8, request.length & 255, ...request]);
          await control.socket.flush();
          final prefix = await control.read(2),
              length = prefix[0] * 256 + prefix[1];
          require(length <= 4096, 'DNS TCP size bound');
          return answer(await control.read(length), tx, expected);
        }
        final relay = await control.request(3, 0);
        udp = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
        final done = Completer<List<int>>();
        final socket = udp;
        sub = socket.listen((event) {
          if (event != RawSocketEvent.read) return;
          final packet = socket.receive();
          if (packet == null || done.isCompleted) return;
          final bytes = packet.data;
          if (packet.address.isLoopback &&
              packet.port == relay &&
              bytes.length >= 22 &&
              same(bytes.sublist(0, 4), [0, 0, 0, 1]) &&
              same(bytes.sublist(4, 8), [127, 0, 0, 1]) &&
              bytes[8] == 0 &&
              bytes[9] == 53) done.complete(bytes.sublist(10));
        });
        socket.send([0, 0, 0, 1, 127, 0, 0, 1, 0, 53, ...request],
            InternetAddress.loopbackIPv4, relay);
        return answer(
            await done.future.timeout(const Duration(milliseconds: 1500)),
            tx,
            expected);
      } catch (_) {
        return false;
      } finally {
        udp?.close();
        await sub?.cancel();
        await control.close();
      }
    }

    var server = await launch(sf, sp);
    final client = await launch(cf, cp, mixed: true);
    require(await resolve('udp.direct.test.invalid', direct.ip),
        'Direct DNS over hijacked UDP failed');
    require(
        direct.names.contains('udp.direct.test.invalid') &&
            !proxy.names.contains('udp.direct.test.invalid'),
        'Wrong direct DNS path');
    results.add({
      'case': 'direct-dns-via-udp-hijack',
      'answerVerified': true,
      'correctStubReached': true
    });
    require(await resolve('udp.proxy.test.invalid', proxy.ip),
        'Proxied DNS over UDP failed');
    require(
        proxy.names.contains('udp.proxy.test.invalid') &&
            !direct.names.contains('udp.proxy.test.invalid'),
        'Wrong proxy DNS path');
    results.add({
      'case': 'proxy-dns-via-udp-hijack',
      'answerVerified': true,
      'correctStubReached': true
    });
    require(await resolve('tcp.proxy.test.invalid', proxy.ip, tcp: true),
        'DNS TCP hijack failed');
    require(proxy.names.contains('tcp.proxy.test.invalid'),
        'TCP DNS bypassed proxy stub');
    results.add({'case': 'proxy-dns-via-tcp-hijack', 'answerVerified': true});
    await server.terminate();
    require(await resolve('down.direct.test.invalid', direct.ip),
        'Direct DNS depends on proxy');
    require(
        !await resolve('down.proxy.test.invalid', proxy.ip) &&
            !proxy.names.contains('down.proxy.test.invalid') &&
            !direct.names.contains('down.proxy.test.invalid'),
        'Proxy DNS leaked/fell back');
    results.add({
      'case': 'server-unavailable',
      'directStillWorks': true,
      'proxyFailsWithoutDirectFallback': true
    });
    server = await launch(sf, sp);
    require(await resolve('recovered.proxy.test.invalid', proxy.ip),
        'Proxy DNS recovery failed');
    require(client.exitValue == null, 'Client crashed');
    results.add({
      'case': 'server-restarted',
      'proxyDnsRecovered': true,
      'sameClientProcess': true
    });
    await server.terminate();
    await client.terminate();
    for (final p in [sp, cp]) {
      final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, p);
      await s.close();
    }
    stdout.writeln(const JsonEncoder.withIndent('  ').convert({
      'scope':
          'loopback DNS A via SOCKS5 UDP/TCP hijack; direct and VLESS/WebSocket/XUDP; no TLS',
      'pids': children.map((c) => c.process.pid).toList(),
      'tcpPorts': [cp, sp],
      'udpStubPorts': [direct.socket.port, proxy.socket.port],
      'directQueries': direct.names,
      'proxyQueries': proxy.names,
      'cacheDisabled': true,
      'port53ListenerCreated': false,
      'corePortsReleased': true,
      'results': results
    }));
  } finally {
    for (final child in children) {
      await child.terminate();
    }
    for (final s in reservations) {
      await s.close();
    }
    await direct.close();
    await proxy.close();
    for (final file in files) {
      if (await file.exists()) await file.delete();
    }
    await temp.delete();
  }
}
