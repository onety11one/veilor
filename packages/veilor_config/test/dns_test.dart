import 'dart:convert';
import 'dart:io';
import '../lib/veilor_config.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

SingleServerDnsPlan plan(
        {String resolver = 'udp://192.0.2.53',
        String proxy = 'https://dns.example.invalid/dns-query',
        String directTag = 'test-direct',
        String proxyTag = 'test-vless',
        DnsIpStrategy strategy = DnsIpStrategy.preferIpv4}) =>
    SingleServerDnsPlan(
      resolverAddress: resolver,
      outboundAddress: 'udp://192.0.2.54',
      directAddress: 'tls://dns-direct.example.invalid',
      proxyAddress: proxy,
      directOutboundTag: directTag,
      proxyOutboundTag: proxyTag,
      strategy: strategy,
    );

void main() {
  var count = 0;
  void test(String name, void Function() run) {
    run();
    count++;
    stdout.writeln('PASS $name');
  }

  const parser = DnsAddressParser();
  const resolver = DnsDomainResolver(
      server: 'bootstrap', strategy: DnsIpStrategy.preferIpv4);
  const builder = MinimalDnsBuilder();
  test('direct DNS omits empty-direct detour; proxy DNS keeps explicit detour',
      () {
    final servers = builder.build(plan()).data!.servers;
    for (final server in servers) {
      final json = server.toJson();
      check(
          server.tag == 'dns_proxy_out'
              ? json['detour'] == 'test-vless'
              : !json.containsKey('detour'),
          'Runtime-invalid empty direct detour generated');
    }
  });
  for (final item in [('udp', 53), ('tcp', 53), ('tls', 853), ('https', 443)]) {
    test('${item.$1} default port and modern schema', () {
      final result = parser.parse(
          address: '${item.$1}://192.0.2.53',
          tag: 'dns-test',
          detour: 'test-direct');
      check(result.error == null && result.data?.port == item.$2, 'Port');
      final json = result.data!.toJson();
      check(
          json['type'] == item.$1 &&
              json['server'] == '192.0.2.53' &&
              !json.containsKey('address') &&
              !json.containsKey('address_resolver'),
          'Legacy schema leaked');
    });
  }
  test('explicit port, IPv6 brackets removed from server', () {
    final result = parser.parse(
        address: 'udp://[2001:db8::53]:5353', tag: 'v6', detour: 'test-direct');
    check(result.data?.host == '2001:db8::53' && result.data?.port == 5353,
        'IPv6/port parsing');
  });
  test('domain server has explicit bootstrap and strategy', () {
    final result = parser.parse(
        address: 'tls://dns.example.invalid',
        tag: 'tls',
        detour: 'test-vless',
        domainResolver: resolver);
    final json = result.data!.toJson();
    check(
        (json['domain_resolver'] as Map<String, Object?>)['server'] ==
                'bootstrap' &&
            (json['domain_resolver'] as Map<String, Object?>)['strategy'] ==
                'prefer_ipv4' &&
            json['detour'] == 'test-vless',
        'Resolver/detour mapping');
  });
  test('domain without bootstrap rejected', () {
    final result = parser.parse(
        address: 'tls://dns.example.invalid',
        tag: 'tls',
        detour: 'test-direct');
    check(
        result.error?.kind == DnsFailure.bootstrapRequired &&
            result.data == null,
        'Silent system DNS fallback');
  });
  test('HTTPS default and explicit paths', () {
    for (final path in ['', '/custom-query']) {
      final result = parser.parse(
          address: 'https://192.0.2.53$path', tag: 'doh', detour: 'test-vless');
      check(result.data?.path == (path.isEmpty ? '/dns-query' : path),
          'DoH path');
    }
  });
  for (final address in [
    'local',
    'dhcp://auto',
    'quic://192.0.2.53',
    'h3://192.0.2.53/dns-query',
    'rcode://success',
    'fakeip'
  ]) {
    test('unsupported address fails explicitly: $address', () {
      final result =
          parser.parse(address: address, tag: 'test', detour: 'direct');
      check(
          result.error?.kind == DnsFailure.unsupportedTransport &&
              result.data == null,
          'Unsupported transport accepted');
    });
  }
  test('bad URL, credentials, fragments, query and ports rejected', () {
    for (final address in [
      'udp://',
      'udp://192.0.2.53:0',
      'udp://192.0.2.53:65536',
      'udp://192.0.2.53:bad',
      'udp://user:synthetic-secret@192.0.2.53',
      'https://192.0.2.53/dns-query?token=synthetic-secret',
      'https://192.0.2.53/dns-query#fragment',
      'udp://192.0.2.53/path',
      ' udp://192.0.2.53',
      'udp://bad host',
      'udp://999.999.999.999',
      'udp://bad_host.invalid'
    ]) {
      final result = parser.parse(
          address: address,
          tag: 'test',
          detour: 'direct',
          domainResolver: resolver);
      check(result.error != null && result.data == null,
          'Invalid synthetic URL accepted: ' + address);
      check(
          !result.error.toString().contains('synthetic-secret'), 'Leaked URL');
    }
  });
  test('empty tags rejected', () {
    for (final tags in [('', 'direct'), ('dns', ''), (' ', 'direct')]) {
      final result = parser.parse(
          address: 'udp://192.0.2.53', tag: tags.$1, detour: tags.$2);
      check(result.error?.kind == DnsFailure.invalidTag, 'Empty tag');
    }
  });
  test('minimal four-role DNS matches independent golden', () {
    final result = builder.build(plan());
    check(result.error == null, 'Minimal build failed');
    final actual = jsonDecode(jsonEncode(result.data!.toJson()));
    final expected =
        jsonDecode(File('test/fixtures/dns.expected.json').readAsStringSync());
    check(_canonical(actual) == _canonical(expected), 'DNS golden differs');
  });
  test('proxy DNS explicitly goes through selected proxy, bootstrap direct',
      () {
    final servers = builder.build(plan()).data!.servers;
    check(
        servers.singleWhere((s) => s.tag == 'dns_proxy_out').detour ==
            'test-vless',
        'Proxy DNS might leak via implicit direct dialer');
    check(
        servers.where((s) => s.tag != 'dns_proxy_out').every(
            (s) => s.detour == null && !s.toJson().containsKey('detour')),
        'Direct DNS role changed');
  });
  test('domain bootstrap fails rather than resolving itself', () {
    final result =
        builder.build(plan(resolver: 'https://bootstrap.example.invalid'));
    check(
        result.error?.kind == DnsFailure.bootstrapRequired &&
            result.data == null,
        'Circular bootstrap accepted');
  });
  test('one unsupported server aborts entire build', () {
    final result = builder.build(plan(proxy: 'h3://192.0.2.53'));
    check(
        result.error?.kind == DnsFailure.unsupportedTransport &&
            result.data == null,
        'Partial DNS config returned');
  });
  test('direct and proxy tag cannot be identical', () {
    check(
        builder.build(plan(directTag: 'same', proxyTag: 'same')).error?.kind ==
            DnsFailure.conflictingTags,
        'Conflicting tags');
  });
  test('all current IP strategies are serialized by wire name', () {
    for (final strategy in DnsIpStrategy.values) {
      check(
          builder.build(plan(strategy: strategy)).data!.toJson()['strategy'] ==
              strategy.wireName,
          'IP strategy');
    }
  });
  test('serialization is independent and does not expose mutable server list',
      () {
    final fragment = builder.build(plan()).data!;
    final first = fragment.toJson();
    (first['servers'] as List<Object?>).clear();
    check((fragment.toJson()['servers'] as List<Object?>).length == 4,
        'Serialization mutated model');
    try {
      fragment.servers.clear();
    } on UnsupportedError {
      return;
    }
    throw StateError('Server list is mutable');
  });
  stdout.writeln('$count DNS tests passed');
}

String _canonical(Object? value) {
  Object? sort(Object? v) {
    if (v is Map) {
      final keys = v.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: sort(v[key])};
    }
    if (v is List) return v.map(sort).toList();
    return v;
  }

  return jsonEncode(sort(value));
}
