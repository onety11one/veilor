// Projection behavior adapted from Karing SingboxConfigBuilder.buildOutbound,
// commit e3c19f1eb1225dbd48a4862f0983b82d0af8de69 (GPL-3.0-or-later).
// See NOTICE.md and the archived upstream license in this repository.

export 'src/dns.dart';
export 'src/minimal_config.dart';

enum ProfileProjectionFailure { missingRaw, invalidJson, invalidTag }

final class ProfileProjectionException implements Exception {
  const ProfileProjectionException(this.failure);
  final ProfileProjectionFailure failure;
  @override
  String toString() => 'ProfileProjectionException(${failure.name})';
}

/// Projects a single ProxyConfig.raw JSON object into an outbound fragment.
/// NOT a protocol validator, parser of subscription links, full configuration,
/// DNS/inbound/route generator or endpoint migration.
final class OutboundProjector {
  static const _metadata = {
    'groupid',
    'ip',
    'attach',
    'latency',
    'outlet_ip',
    'outlet_region',
  };

  /// Caller passes the current ProxyConfig.tag, which overrides raw['tag'].
  /// Unknown JSON fields, nulls, array order and nested objects are preserved.
  /// Input and output share no mutable maps or lists.
  Map<String, Object?> project({required Object? raw, required String tag}) {
    if (raw is! Map) {
      throw const ProfileProjectionException(
        ProfileProjectionFailure.missingRaw,
      );
    }
    if (tag.trim().isEmpty) {
      throw const ProfileProjectionException(
        ProfileProjectionFailure.invalidTag,
      );
    }
    final result = <String, Object?>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      if (key is! String) {
        throw const ProfileProjectionException(
          ProfileProjectionFailure.invalidJson,
        );
      }
      // Metadata and stale raw tag are not part of the projected payload.
      if (_metadata.contains(key) || key == 'tag') continue;
      result[key] = _copyJson(entry.value, 0);
    }
    result['tag'] = tag;
    return result;
  }

  Object? _copyJson(Object? value, int depth) {
    if (depth > 64) {
      throw const ProfileProjectionException(
        ProfileProjectionFailure.invalidJson,
      );
    }
    if (value == null || value is String || value is bool || value is int) {
      return value;
    }
    if (value is double && value.isFinite) return value;
    if (value is List) {
      return [for (final item in value) _copyJson(item, depth + 1)];
    }
    if (value is Map) {
      final copied = <String, Object?>{};
      for (final entry in value.entries) {
        if (entry.key is! String) {
          throw const ProfileProjectionException(
            ProfileProjectionFailure.invalidJson,
          );
        }
        copied[entry.key as String] = _copyJson(entry.value, depth + 1);
      }
      return copied;
    }
    throw const ProfileProjectionException(
      ProfileProjectionFailure.invalidJson,
    );
  }
}
