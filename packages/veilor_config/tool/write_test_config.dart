import 'dart:convert';
import 'dart:io';
import '../lib/veilor_config.dart';

/// Generates only a fixed synthetic fixture. Never reads user VPN settings.
void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('Usage: dart run tool/write_test_config.dart <output.json>');
    exitCode = 64;
    return;
  }
  final raw =
      jsonDecode(File('test/fixtures/vless_profile.json').readAsStringSync());
  final config = MinimalConfigBuilder().build(
    rawProfile: raw,
    proxyTag: 'test-vless',
    listenPort: 39081,
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
  File(args.single).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(config)}\n');
  stdout.writeln('Synthetic config written. No core started.');
}
