import 'dart:io';

enum DnsFailure {
  invalidAddress,
  unsupportedTransport,
  bootstrapRequired,
  invalidTag,
  invalidStrategy,
  conflictingTags,
}

/// Safe diagnostics: no URL, credentials, domain names or settings content.
final class DnsBuildError {
  const DnsBuildError(this.kind);
  final DnsFailure kind;
  @override
  String toString() => 'DnsBuildError(${kind.name})';
}

final class DnsBuildResult<T> {
  const DnsBuildResult.success(T value)
      : data = value,
        error = null;
  DnsBuildResult.failure(DnsFailure kind)
      : data = null,
        error = DnsBuildError(kind);
  final T? data;
  final DnsBuildError? error;
}

enum DnsIpStrategy {
  ipv4Only('ipv4_only'),
  preferIpv4('prefer_ipv4'),
  preferIpv6('prefer_ipv6'),
  ipv6Only('ipv6_only');

  const DnsIpStrategy(this.wireName);
  final String wireName;
}

final class DnsDomainResolver {
  const DnsDomainResolver({required this.server, required this.strategy});
  final String server;
  final DnsIpStrategy strategy;
  Map<String, Object?> toJson() => {
        'server': server,
        'strategy': strategy.wireName,
      };
}

/// Modern typed DNS server schema, not the historical address/addresses model.
final class DnsServer {
  const DnsServer._({
    required this.tag,
    required this.type,
    required this.host,
    required this.port,
    required this.detour,
    this.path,
    this.domainResolver,
  });
  final String tag;
  final String type;
  final String host;
  final int port;
  final String? detour;
  final String? path;
  final DnsDomainResolver? domainResolver;
  Map<String, Object?> toJson() => {
        'tag': tag,
        'type': type,
        'server': host,
        'server_port': port,
        if (detour != null) 'detour': detour,
        if (path != null) 'path': path,
        if (domainResolver != null) 'domain_resolver': domainResolver!.toJson(),
      };
}

/// Pure parsing only. No host resolution or DNS/network requests.
final class DnsAddressParser {
  const DnsAddressParser();

  DnsBuildResult<DnsServer> parse({
    required String address,
    required String tag,
    String? detour,
    DnsDomainResolver? domainResolver,
  }) {
    if (tag.trim().isEmpty ||
        (detour != null && detour.trim().isEmpty) ||
        (domainResolver != null && domainResolver.server.trim().isEmpty)) {
      return DnsBuildResult.failure(DnsFailure.invalidTag);
    }
    try {
      if (address.trim() != address || address.contains(RegExp(r'\s'))) {
        return DnsBuildResult.failure(DnsFailure.invalidAddress);
      }
      final uri = Uri.tryParse(address);
      if (uri == null) {
        return DnsBuildResult.failure(DnsFailure.invalidAddress);
      }
      if (!{'udp', 'tcp', 'tls', 'https'}.contains(uri.scheme)) {
        return DnsBuildResult.failure(DnsFailure.unsupportedTransport);
      }
      if (!uri.hasAuthority ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment ||
          uri.authority.endsWith(':0') ||
          uri.authority.endsWith(':')) {
        return DnsBuildResult.failure(DnsFailure.invalidAddress);
      }
      final host = uri.host.replaceAll('[', '').replaceAll(']', '');
      final literal = InternetAddress.tryParse(host);
      if (literal == null && !_domain(host)) {
        return DnsBuildResult.failure(DnsFailure.invalidAddress);
      }
      if (literal == null && domainResolver == null) {
        return DnsBuildResult.failure(DnsFailure.bootstrapRequired);
      }
      // Uri normalizes an explicit :0 away for unknown schemes. Inspect the
      // original authority so it cannot silently become the default DNS port.
      final rawAuthority =
          address.split('://').last.split(RegExp(r'[/#?]')).first;
      final explicitPort = RegExp(r':([0-9]+)$').firstMatch(rawAuthority);
      final port = explicitPort != null
          ? (int.tryParse(explicitPort.group(1)!) ?? -1)
          : switch (uri.scheme) {
              'tls' => 853,
              'https' => 443,
              _ => 53,
            };
      if (rawAuthority.endsWith(':') ||
          port < 1 ||
          port > 65535 ||
          (uri.scheme != 'https' && uri.path.isNotEmpty)) {
        return DnsBuildResult.failure(DnsFailure.invalidAddress);
      }
      return DnsBuildResult.success(DnsServer._(
        tag: tag,
        type: uri.scheme,
        host: host,
        port: port,
        detour: detour,
        path: uri.scheme == 'https'
            ? (uri.path.isEmpty ? '/dns-query' : uri.path)
            : null,
        domainResolver: domainResolver,
      ));
    } on FormatException {
      return DnsBuildResult.failure(DnsFailure.invalidAddress);
    }
  }

  bool _domain(String value) {
    if (value.length > 253 || RegExp(r'^[0-9.]+$').hasMatch(value))
      return false;
    final host =
        value.endsWith('.') ? value.substring(0, value.length - 1) : value;
    return host.split('.').every((label) =>
        label.isNotEmpty &&
        label.length <= 63 &&
        RegExp(r'^[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?$').hasMatch(label));
  }
}

/// Deliberately explicit test scope: one server per role, no fakeip/ECS/static
/// hosts/rules or Karing batch. Never accepts a full settings object and drops
/// its unsupported features. Not a replacement for SingboxConfigBuilder.dns.
final class SingleServerDnsPlan {
  const SingleServerDnsPlan({
    required this.resolverAddress,
    required this.outboundAddress,
    required this.directAddress,
    required this.proxyAddress,
    required this.directOutboundTag,
    required this.proxyOutboundTag,
    required this.strategy,
  });
  final String resolverAddress;
  final String outboundAddress;
  final String directAddress;
  final String proxyAddress;
  final String directOutboundTag;
  final String proxyOutboundTag;
  final DnsIpStrategy strategy;
}

final class DnsFragment {
  DnsFragment._(List<DnsServer> servers, this.strategy)
      : servers = List.unmodifiable(servers);
  final List<DnsServer> servers;
  final DnsIpStrategy strategy;
  Map<String, Object?> toJson() => {
        'final': 'dns_proxy_out',
        'servers': [for (final server in servers) server.toJson()],
        'rules': <Object?>[],
        'strategy': strategy.wireName,
        'independent_cache': true,
        'cache_capacity': 1024,
      };
}

final class MinimalDnsBuilder {
  const MinimalDnsBuilder();
  DnsBuildResult<DnsFragment> build(SingleServerDnsPlan plan) {
    if (plan.directOutboundTag == plan.proxyOutboundTag) {
      return DnsBuildResult.failure(DnsFailure.conflictingTags);
    }
    const parser = DnsAddressParser();
    // Bootstrap must be a literal IP to avoid self-resolution cycles.
    final bootstrap = parser.parse(
      address: plan.resolverAddress,
      tag: 'dns_resolver_out',
    );
    if (bootstrap.error != null) {
      return DnsBuildResult.failure(bootstrap.error!.kind);
    }
    final resolver =
        DnsDomainResolver(server: 'dns_resolver_out', strategy: plan.strategy);
    final servers = <DnsServer>[bootstrap.data!];
    for (final item in [
      ('dns_outbound_out', plan.outboundAddress, null),
      ('dns_direct_out', plan.directAddress, null),
      ('dns_proxy_out', plan.proxyAddress, plan.proxyOutboundTag),
    ]) {
      final result = parser.parse(
          address: item.$2,
          tag: item.$1,
          detour: item.$3,
          domainResolver: resolver);
      if (result.error != null) {
        return DnsBuildResult.failure(result.error!.kind);
      }
      servers.add(result.data!);
    }
    return DnsBuildResult.success(DnsFragment._(servers, plan.strategy));
  }
}
