import '../veilor_config.dart' show OutboundProjector;
import 'dns.dart';

enum MinimalConfigFailure {
  invalidPort,
  invalidProfile,
  unsupportedProfile,
  externalReference,
  tagMismatch,
  dns,
  danglingReference,
}

final class MinimalConfigException implements Exception {
  const MinimalConfigException(this.failure, {this.dnsFailure});
  final MinimalConfigFailure failure;
  final DnsFailure? dnsFailure;
  @override
  String toString() => 'MinimalConfigException(${failure.name})';
}

/// First complete synthetic configuration, NOT a replacement for full Karing
/// settings, TUN, selectable modes, rule sets, chains, auto-select or endpoints.
final class MinimalConfigBuilder {
  Map<String, Object?> build({
    required Object? rawProfile,
    required String proxyTag,
    required int listenPort,
    required SingleServerDnsPlan dnsPlan,
  }) {
    if (listenPort < 1024 || listenPort > 65535) {
      throw const MinimalConfigException(MinimalConfigFailure.invalidPort);
    }
    if (rawProfile is! Map || rawProfile['type'] != 'vless') {
      throw const MinimalConfigException(
          MinimalConfigFailure.unsupportedProfile);
    }
    // No missing chain members or caller-supplied resolver/selector references.
    if (rawProfile['detour'] != null || rawProfile['domain_resolver'] != null) {
      throw const MinimalConfigException(
          MinimalConfigFailure.externalReference);
    }
    if (dnsPlan.proxyOutboundTag != proxyTag ||
        proxyTag.trim().isEmpty ||
        dnsPlan.directOutboundTag.trim().isEmpty ||
        dnsPlan.directOutboundTag == proxyTag) {
      throw const MinimalConfigException(MinimalConfigFailure.tagMismatch);
    }
    final server = rawProfile['server'];
    final serverPort = rawProfile['server_port'];
    final uuid = rawProfile['uuid'];
    if (server is! String ||
        server.trim().isEmpty ||
        serverPort is! int ||
        serverPort < 1 ||
        serverPort > 65535 ||
        uuid is! String ||
        !RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
            .hasMatch(uuid)) {
      throw const MinimalConfigException(MinimalConfigFailure.invalidProfile);
    }
    final dns = const MinimalDnsBuilder().build(dnsPlan);
    if (dns.error != null) {
      throw MinimalConfigException(MinimalConfigFailure.dns,
          dnsFailure: dns.error!.kind);
    }
    final proxy = OutboundProjector().project(raw: rawProfile, tag: proxyTag);
    final config = <String, Object?>{
      'log': {'level': 'warn', 'timestamp': true},
      'dns': dns.data!.toJson(),
      'inbounds': [
        {
          'type': 'mixed',
          'tag': 'mixed_in_proxy',
          'listen': '127.0.0.1',
          'listen_port': listenPort,
          'set_system_proxy': false,
        },
      ],
      'outbounds': [
        {'type': 'direct', 'tag': dnsPlan.directOutboundTag},
        proxy,
      ],
      'route': {
        'rules': [
          {
            'inbound': ['mixed_in_proxy'],
            'port': 53,
            'action': 'hijack-dns',
          },
        ],
        'final': proxyTag,
        'default_domain_resolver': {
          'server': 'dns_outbound_out',
          'strategy': dnsPlan.strategy.wireName,
        },
      },
    };
    validateMinimalReferences(config);
    return config;
  }
}

/// Cross-reference checks for the exact minimal schema emitted above.
void validateMinimalReferences(Map<String, Object?> config) {
  Never invalid() => throw const MinimalConfigException(
      MinimalConfigFailure.danglingReference);
  try {
    final outbounds =
        (config['outbounds'] as List<Object?>).cast<Map<String, Object?>>();
    final inbounds =
        (config['inbounds'] as List<Object?>).cast<Map<String, Object?>>();
    final dns = config['dns'] as Map<String, Object?>;
    final servers =
        (dns['servers'] as List<Object?>).cast<Map<String, Object?>>();
    final outboundTags = outbounds.map((v) => v['tag']).toSet();
    final inboundTags = inbounds.map((v) => v['tag']).toSet();
    final dnsTags = servers.map((v) => v['tag']).toSet();
    if (outboundTags.length != outbounds.length ||
        inboundTags.length != inbounds.length ||
        dnsTags.length != servers.length ||
        [...outboundTags, ...inboundTags, ...dnsTags]
            .any((tag) => tag is! String || tag.trim().isEmpty)) invalid();
    if (!dnsTags.contains(dns['final'])) invalid();
    for (final server in servers) {
      if (server['detour'] != null && !outboundTags.contains(server['detour']))
        invalid();
      final resolver = server['domain_resolver'];
      if (resolver != null &&
          !dnsTags.contains((resolver as Map<String, Object?>)['server']))
        invalid();
    }
    final route = config['route'] as Map<String, Object?>;
    if (!outboundTags.contains(route['final']) ||
        !dnsTags.contains((route['default_domain_resolver']
            as Map<String, Object?>)['server'])) invalid();
    for (final rule
        in (route['rules'] as List<Object?>).cast<Map<String, Object?>>()) {
      for (final tag in rule['inbound'] as List<Object?>) {
        if (!inboundTags.contains(tag)) invalid();
      }
      if (rule['outbound'] != null && !outboundTags.contains(rule['outbound']))
        invalid();
    }
  } on MinimalConfigException {
    rethrow;
  } catch (_) {
    invalid();
  }
}
