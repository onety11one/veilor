// Pure URI construction; no HttpClient, sockets, profiles or credentials.
import 'dart:convert';
void main() {
  const rawPath = 'stop?';
  // Dart 3.12.2 HttpClient.open splits query before constructing Uri.
  final marker = rawPath.indexOf('?');
  final uri = Uri(scheme: 'http', host: '127.0.0.1', port: 12345,
      path: rawPath.substring(0, marker), query: rawPath.substring(marker + 1));
  if (uri.toString() != 'http://127.0.0.1:12345/stop') {
    throw StateError('Unexpected URI normalization');
  }
  print(jsonEncode({'syntheticOnly': true, 'networkUsed': false,
      'uri': uri.toString(), 'path': uri.path, 'query': uri.query}));
}
