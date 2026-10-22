import 'dart:convert';
import 'dart:io';
import '../lib/veilor_config.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

void main() {
  var passed = 0;
  void test(String name, void Function() action) {
    action();
    passed++;
    stdout.writeln('PASS $name');
  }

  final original =
      jsonDecode(File('test/fixtures/vless_profile.json').readAsStringSync());
  final builder = MinimalConfigBuilder();
  Map<String, Object?> build(
          {Object? raw,
          int port = 39081,
          String proxy = 'test-vless',
          String dnsProxy = 'test-vless',
          String direct = 'test-direct',
          String dnsAddress = 'https://dns.example.invalid/dns-query'}) =>
      builder.build(
          rawProfile: raw ?? original,
          proxyTag: proxy,
          listenPort: port,
          dnsPlan: SingleServerDnsPlan(
              resolverAddress: 'udp://192.0.2.53',
              outboundAddress: 'udp://192.0.2.54',
              directAddress: 'tls://dns-direct.example.invalid',
              proxyAddress: dnsAddress,
              directOutboundTag: direct,
              proxyOutboundTag: dnsProxy,
              strategy: DnsIpStrategy.preferIpv4));

  void fails(void Function() action, MinimalConfigFailure expected) {
    try {
      action();
    } on MinimalConfigException catch (e) {
      check(e.failure == expected, 'Wrong typed error');
      return;
    }
    throw StateError('Expected $expected');
  }

  test('missing route target rejected by our validator', () {
    final config = build();
    (config['route'] as Map<String, Object?>)['final'] = 'missing';
    fails(() => validateMinimalReferences(config),
        MinimalConfigFailure.danglingReference);
  });
  test('missing DNS detour and bootstrap rejected', () {
    for (final key in ['detour', 'domain_resolver']) {
      final config = build();
      final dns = config['dns'] as Map<String, Object?>;
      final server =
          (dns['servers'] as List<Object?>).last as Map<String, Object?>;
      server[key] = key == 'detour' ? 'missing' : {'server': 'missing'};
      fails(() => validateMinimalReferences(config),
          MinimalConfigFailure.danglingReference);
    }
  });
  test('duplicate outbound tag rejected', () {
    final config = build();
    final outbounds = config['outbounds'] as List<Object?>;
    (outbounds.last as Map<String, Object?>)['tag'] = 'test-direct';
    fails(() => validateMinimalReferences(config),
        MinimalConfigFailure.danglingReference);
  });
  test('complete config has exactly expected sections', () {
    final config = build();
    check(config.keys.join(',') == 'log,dns,inbounds,outbounds,route',
        'Sections');
    check(jsonDecode(jsonEncode(config)) is Map<String, dynamic>,
        'Serialization');
  });
  test('single loopback mixed inbound without system proxy or TUN', () {
    final inbounds = build()['inbounds'] as List<Object?>;
    final inbound = inbounds.single as Map<String, Object?>;
    check(
        inbound['type'] == 'mixed' &&
            inbound['listen'] == '127.0.0.1' &&
            inbound['listen_port'] == 39081 &&
            inbound['set_system_proxy'] == false,
        'Unexpected system or network exposure');
  });
  test('route points to proxy; port 53 hijack is scoped to test inbound', () {
    final route = build()['route'] as Map<String, Object?>;
    final rule =
        (route['rules'] as List<Object?>).single as Map<String, Object?>;
    check(
        route['final'] == 'test-vless' &&
            rule['action'] == 'hijack-dns' &&
            rule['port'] == 53 &&
            (rule['inbound'] as List<String>).single == 'mixed_in_proxy',
        'Route changed');
  });
  test('all DNS detours, final and resolver tags resolve inside config', () {
    final config = build();
    final outbounds = config['outbounds'] as List<Object?>;
    final outboundTags =
        outbounds.cast<Map<String, Object?>>().map((v) => v['tag']).toSet();
    check(outboundTags.length == 2, 'Duplicate tags');
    final dns = config['dns'] as Map<String, Object?>;
    final servers =
        (dns['servers'] as List<Object?>).cast<Map<String, Object?>>();
    final dnsTags = servers.map((v) => v['tag']).toSet();
    check(dnsTags.contains(dns['final']), 'Missing DNS final');
    for (final server in servers) {
      check(server['detour'] == null || outboundTags.contains(server['detour']),
          'Dangling DNS detour');
      if (server['domain_resolver'] case final Map<String, Object?> resolver) {
        check(dnsTags.contains(resolver['server']), 'Dangling bootstrap');
      }
    }
    final route = config['route'] as Map<String, Object?>;
    check(outboundTags.contains(route['final']), 'Dangling route final');
    check(
        dnsTags.contains((route['default_domain_resolver']
            as Map<String, Object?>)['server']),
        'Dangling outbound resolver');
  });
  test('outbound fields match earlier golden and metadata stays removed', () {
    final config = build();
    final outbound =
        (config['outbounds'] as List<Object?>).last as Map<String, Object?>;
    check(
        outbound['tag'] == 'test-vless' &&
            !outbound.containsKey('groupid') &&
            outbound['uuid'] == original['uuid'] &&
            outbound['server'] == original['server'],
        'Profile content lost');
  });
  test('full build leaves source unchanged and outputs independent', () {
    final before = jsonEncode(original);
    final a = build();
    final b = build();
    ((a['outbounds'] as List<Object?>).last as Map<String, Object?>)['server'] =
        'changed';
    check(jsonEncode(original) == before && jsonEncode(a) != jsonEncode(b),
        'Input/output alias');
  });
  test('unprivileged listen port range enforced', () {
    for (final port in [-1, 0, 80, 65536]) {
      fails(() => build(port: port), MinimalConfigFailure.invalidPort);
    }
    build(port: 1024);
    build(port: 65535);
  });
  test('unsupported profile never silently converted to VLESS', () {
    fails(() => build(raw: {'type': 'wireguard'}),
        MinimalConfigFailure.unsupportedProfile);
  });
  test('proxy and DNS role tags must agree and be distinct', () {
    fails(() => build(dnsProxy: 'another'), MinimalConfigFailure.tagMismatch);
    fails(() => build(direct: 'test-vless'), MinimalConfigFailure.tagMismatch);
    fails(
        () => build(proxy: '', dnsProxy: ''), MinimalConfigFailure.tagMismatch);
  });
  test('chains and external resolver references explicitly rejected', () {
    for (final key in ['detour', 'domain_resolver']) {
      final raw = Map<String, dynamic>.from(original as Map<String, dynamic>);
      raw[key] = 'absent-tag';
      fails(() => build(raw: raw), MinimalConfigFailure.externalReference);
    }
  });
  test('missing server, invalid port and UUID rejected', () {
    for (final change in [
      {'server': ''},
      {'server_port': 0},
      {'uuid': 'bad'}
    ]) {
      final raw = {...original as Map<String, dynamic>, ...change};
      fails(() => build(raw: raw), MinimalConfigFailure.invalidProfile);
    }
  });
  test('DNS failure aborts whole config and preserves typed reason', () {
    try {
      build(dnsAddress: 'fakeip');
    } on MinimalConfigException catch (e) {
      check(
          e.failure == MinimalConfigFailure.dns &&
              e.dnsFailure == DnsFailure.unsupportedTransport,
          'DNS error lost');
      return;
    }
    throw StateError('Partial config returned');
  });
  stdout.writeln('$passed minimal config tests passed');
}
