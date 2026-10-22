import 'dart:convert';
import 'dart:io';

import '../lib/veilor_core_readonly.dart';

/// Explicit opt-in smoke probe. Never writes or prints the source configuration.
Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('Usage: dart run tool/probe_local.dart <service_core.json>');
    exitCode = 64;
    return;
  }
  CoreReadonlyClient? client;
  try {
    final root = jsonDecode(await File(args.single).readAsString());
    final api = root['experimental']['clash_api'];
    final address = api['external_controller'] as String;
    var endpoint = Uri.parse(
      address.contains('://') ? address : 'http://$address',
    );
    // Listening wildcards are mapped explicitly; never requested as hosts.
    if (endpoint.host == '0.0.0.0') {
      endpoint = endpoint.replace(host: '127.0.0.1');
    } else if (endpoint.host == '::' || endpoint.host == '[::]') {
      endpoint = endpoint.replace(host: '::1');
    }
    client = CoreReadonlyClient(
      endpoint: endpoint,
      secret: api['secret'] as String? ?? '',
    );
    final version = await client.readVersion();
    final metrics = await client.readMetrics();
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert({
        'scope': 'GET /version and /connections only; no VPN control',
        'version': version.version,
        'observedAt': metrics.observedAt.toIso8601String(),
        'memoryBytes': metrics.memoryBytes,
        'sessionSeconds': metrics.sessionDuration?.inSeconds,
        'inboundConnections': metrics.inboundConnections,
        'outboundConnections': metrics.outboundConnections,
        'downloadBytesPerSecond': metrics.downloadBytesPerSecond,
        'uploadBytesPerSecond': metrics.uploadBytesPerSecond,
      }),
    );
  } on CoreReadException catch (e) {
    stderr.writeln(e);
    exitCode = 1;
  } catch (_) {
    // Configuration parser errors can contain source fragments. Suppress them.
    stderr.writeln('Cannot read a valid local controller configuration.');
    exitCode = 1;
  } finally {
    client?.close();
  }
}
