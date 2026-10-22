import 'dart:async';
import 'dart:convert';
import 'dart:io';

enum CoreReadFailure {
  closed,
  timeout,
  unavailable,
  unauthorized,
  httpStatus,
  invalidResponse,
  responseTooLarge,
}

/// Never contains the controller secret, raw response or connection metadata.
final class CoreReadException implements Exception {
  const CoreReadException(this.failure, {this.statusCode});
  final CoreReadFailure failure;
  final int? statusCode;
  @override
  String toString() => 'CoreReadException(${failure.name}'
      '${statusCode == null ? '' : ', HTTP $statusCode'})';
}

final class CoreVersion {
  const CoreVersion(this.version, {this.meta, this.premium});
  final String version;
  final bool? meta;
  final bool? premium;
}

/// API availability does not imply that VPN is connected.
/// Null means absent/invalid/unsupported; zero is a reported measurement.
final class CoreMetrics {
  const CoreMetrics({
    required this.observedAt,
    this.startedAt,
    this.memoryBytes,
    this.inboundConnections,
    this.outboundConnections,
    this.downloadBytesPerSecond,
    this.uploadBytesPerSecond,
    this.downloadBytes,
    this.uploadBytes,
  });
  final DateTime observedAt;
  final DateTime? startedAt;
  final int? memoryBytes;
  final int? inboundConnections;
  final int? outboundConnections;
  final num? downloadBytesPerSecond;
  final num? uploadBytesPerSecond;
  final int? downloadBytes;
  final int? uploadBytes;

  Duration? get sessionDuration {
    final start = startedAt;
    if (start == null || start.isAfter(observedAt)) return null;
    return observedAt.difference(start);
  }
}

/// Makes only GET /version and GET /connections requests, without redirects.
/// Each request owns a client so a deadline aborts both headers and body reads.
final class CoreReadonlyClient {
  CoreReadonlyClient({
    required Uri endpoint,
    String secret = '',
    this.timeout = const Duration(seconds: 3),
    this.maxResponseBytes = 8 * 1024 * 1024,
    DateTime Function()? clock,
  })  : _endpoint = endpoint,
        _secret = secret,
        _clock = clock ?? DateTime.now {
    if (endpoint.scheme != 'http' ||
        !{'localhost', '127.0.0.1', '::1', '[::1]'}.contains(endpoint.host) ||
        endpoint.userInfo.isNotEmpty ||
        endpoint.hasQuery ||
        endpoint.hasFragment ||
        (endpoint.path.isNotEmpty && endpoint.path != '/') ||
        endpoint.port <= 0) {
      throw ArgumentError('Expected a loopback HTTP controller origin');
    }
    if (timeout <= Duration.zero || maxResponseBytes <= 0) {
      throw ArgumentError('Deadline and response limit must be positive');
    }
    if (secret.contains('\r') || secret.contains('\n')) {
      throw ArgumentError('Invalid controller secret');
    }
  }

  final Uri _endpoint;
  final String _secret;
  final Duration timeout;
  final int maxResponseBytes;
  final DateTime Function() _clock;
  final Set<HttpClient> _active = {};
  bool _closed = false;

  Future<CoreVersion> readVersion() async {
    final json = await _get('/version');
    final version = json['version'];
    if (version is! String || version.trim().isEmpty) {
      throw const CoreReadException(CoreReadFailure.invalidResponse);
    }
    return CoreVersion(
      version,
      meta: json['meta'] is bool ? json['meta'] as bool : null,
      premium: json['premium'] is bool ? json['premium'] as bool : null,
    );
  }

  Future<CoreMetrics> readMetrics() async {
    final json = await _get('/connections');
    final start = json['startTime'];
    // Require an explicit timezone; do not interpret core time as local time.
    final startedAt =
        start is String && RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(start)
            ? DateTime.tryParse(start)?.toUtc()
            : null;
    return CoreMetrics(
      observedAt: _clock().toUtc(),
      startedAt: startedAt,
      memoryBytes: _integer(json['memory']),
      inboundConnections: _integer(json['connectionsInCount']),
      outboundConnections: _integer(json['connectionsOutCount']),
      downloadBytesPerSecond: _number(json['downloadSpeed']),
      uploadBytesPerSecond: _number(json['uploadSpeed']),
      downloadBytes: _integer(json['downloadTotal']),
      uploadBytes: _integer(json['uploadTotal']),
    );
  }

  static num? _number(Object? value) =>
      value is num && value.isFinite && value >= 0 ? value : null;

  static int? _integer(Object? value) {
    if (value is int) return value >= 0 ? value : null;
    final number = _number(value);
    // Avoid rounding/clamping oversized floating-point counters to a fake int.
    if (number == null ||
        number > 9007199254740991 ||
        number != number.truncateToDouble()) return null;
    return number.toInt();
  }

  Future<Map<String, dynamic>> _get(String path) async {
    if (_closed) throw const CoreReadException(CoreReadFailure.closed);
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    _active.add(client);
    try {
      return await _request(client, path).timeout(timeout);
    } on CoreReadException {
      rethrow;
    } on TimeoutException {
      throw const CoreReadException(CoreReadFailure.timeout);
    } on FormatException {
      throw const CoreReadException(CoreReadFailure.invalidResponse);
    } catch (_) {
      throw CoreReadException(
        _closed ? CoreReadFailure.closed : CoreReadFailure.unavailable,
      );
    } finally {
      _active.remove(client);
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> _request(HttpClient client, String path) async {
    final request = await client.getUrl(_endpoint.replace(path: path));
    request.followRedirects = false;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (_secret.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_secret');
    }
    final response = await request.close();
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw CoreReadException(
        CoreReadFailure.unauthorized,
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode != 200) {
      throw CoreReadException(
        CoreReadFailure.httpStatus,
        statusCode: response.statusCode,
      );
    }
    if (response.contentLength > maxResponseBytes) {
      throw const CoreReadException(CoreReadFailure.responseTooLarge);
    }
    final bytes = <int>[];
    await for (final chunk in response) {
      if (bytes.length + chunk.length > maxResponseBytes) {
        throw const CoreReadException(CoreReadFailure.responseTooLarge);
      }
      bytes.addAll(chunk);
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic>) {
      throw const CoreReadException(CoreReadFailure.invalidResponse);
    }
    return decoded;
  }

  void close() {
    _closed = true;
    for (final client in _active) {
      client.close(force: true);
    }
    _active.clear();
  }
}
