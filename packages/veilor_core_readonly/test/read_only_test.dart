// Standalone integration suite: dart run test/read_only_test.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../lib/veilor_core_readonly.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> failure(
  Future<Object?> Function() action,
  CoreReadFailure expected,
) async {
  try {
    await action();
  } on CoreReadException catch (e) {
    check(e.failure == expected, 'Expected $expected, got ${e.failure}');
    check(!e.toString().contains('test-secret'), 'Error exposed credential');
    return;
  }
  throw StateError('Expected $expected');
}

Future<void> main() async {
  var passed = 0;
  Future<void> test(String name, Future<void> Function() action) async {
    await action();
    passed++;
    stdout.writeln('PASS $name');
  }

  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final endpoint = Uri.parse('http://127.0.0.1:${server.port}');
  var handler = (HttpRequest request) async {
    request.response.write('{}');
    await request.response.close();
  };
  final subscription = server.listen((request) async {
    try {
      await handler(request);
    } catch (_) {
      // Deadline/close tests intentionally terminate the peer connection.
      try {
        await request.response.close();
      } catch (_) {}
    }
  });
  void respond(Object value, {int status = 200}) {
    handler = (request) async {
      request.response.statusCode = status;
      request.response.write(jsonEncode(value));
      await request.response.close();
    };
  }

  final now = DateTime.utc(2026, 10, 21, 12);
  final client = CoreReadonlyClient(
    endpoint: endpoint,
    secret: 'test-secret',
    clock: () => now,
  );
  try {
    await test('only GET and correct paths / authorization', () async {
      final paths = <String>[];
      handler = (request) async {
        check(request.method == 'GET', 'Unexpected mutation');
        check(
          request.headers.value('authorization') == 'Bearer test-secret',
          'Authorization missing',
        );
        paths.add(request.uri.path);
        request.response.write(
          request.uri.path == '/version'
              ? '{"version":"sing-box test","meta":true,"premium":false}'
              : '{}',
        );
        await request.response.close();
      };
      final version = await client.readVersion();
      await client.readMetrics();
      check(
        version.version == 'sing-box test' &&
            version.meta == true &&
            version.premium == false,
        'Version decoding',
      );
      check(paths.join(',') == '/version,/connections', 'Unexpected endpoint');
    });
    await test('metrics map and core session timestamp', () async {
      respond({
        'memory': 1048576,
        'connectionsInCount': 7,
        'connectionsOutCount': 5,
        'connections': [
          {
            'metadata': {'host': 'must-not-be-retained'},
          },
        ],
        'downloadSpeed': 12.5,
        'uploadSpeed': 8,
        'downloadTotal': 1234,
        'uploadTotal': 5678,
        'startTime': '2026-10-21T14:59:35+03:00',
      });
      final m = await client.readMetrics();
      check(
        m.memoryBytes == 1048576 &&
            m.inboundConnections == 7 &&
            m.outboundConnections == 5,
        'Wrong count/memory mapping',
      );
      check(
        m.downloadBytesPerSecond == 12.5 &&
            m.uploadBytesPerSecond == 8 &&
            m.downloadBytes == 1234 &&
            m.uploadBytes == 5678,
        'Traffic mapping',
      );
      check(m.sessionDuration == const Duration(seconds: 25), 'Core timestamp');
      check(m.observedAt == now, 'Observation timestamp');
    });
    await test(
      'missing values stay unknown, no array-length fallback',
      () async {
        respond({
          'connections': [1, 2, 3],
        });
        final m = await client.readMetrics();
        check(
          m.inboundConnections == null &&
              m.memoryBytes == null &&
              m.sessionDuration == null &&
              m.downloadBytesPerSecond == null,
          'Missing measurements became zero',
        );
      },
    );
    await test('reported zero stays zero', () async {
      respond({'memory': 0, 'connectionsInCount': 0, 'uploadSpeed': 0});
      final m = await client.readMetrics();
      check(
        m.memoryBytes == 0 &&
            m.inboundConnections == 0 &&
            m.uploadBytesPerSecond == 0,
        'Zero lost',
      );
    });
    await test('oversized floating-point counter stays unknown', () async {
      respond({'memory': 1e100});
      check((await client.readMetrics()).memoryBytes == null,
          'Oversized counter clamped');
    });
    await test('invalid numeric fields unavailable', () async {
      respond({
        'memory': -1,
        'connectionsInCount': 1.5,
        'connectionsOutCount': '7',
        'downloadSpeed': -3,
        'uploadTotal': true,
      });
      final m = await client.readMetrics();
      check(
        m.memoryBytes == null &&
            m.inboundConnections == null &&
            m.outboundConnections == null &&
            m.downloadBytesPerSecond == null &&
            m.uploadBytes == null,
        'Invalid measurement accepted',
      );
    });
    for (final time in [
      'invalid',
      '2026-10-21T12:00:00',
      '2026-10-22T12:00:00Z',
    ]) {
      await test('invalid/ambiguous/future time $time', () async {
        respond({'startTime': time});
        check(
          (await client.readMetrics()).sessionDuration == null,
          'Invalid duration accepted',
        );
      });
    }
    for (final code in [401, 403, 404, 500]) {
      await test('HTTP $code', () async {
        respond({'secret': 'test-secret'}, status: code);
        await failure(
          client.readVersion,
          code == 401 || code == 403
              ? CoreReadFailure.unauthorized
              : CoreReadFailure.httpStatus,
        );
      });
    }
    await test('redirect is never followed', () async {
      var requests = 0;
      handler = (request) async {
        requests++;
        request.response.statusCode = 302;
        request.response.headers.set('location', '$endpoint/elsewhere');
        await request.response.close();
      };
      await failure(client.readVersion, CoreReadFailure.httpStatus);
      check(requests == 1, 'Redirect followed');
    });
    for (final body in [
      'not json',
      '[]',
      '{"version":123}',
      '{"version":""}',
    ]) {
      await test('invalid version response $body', () async {
        handler = (request) async {
          request.response.write(body);
          await request.response.close();
        };
        await failure(client.readVersion, CoreReadFailure.invalidResponse);
      });
    }
    await test('response limit including chunked body', () async {
      final limited = CoreReadonlyClient(
        endpoint: endpoint,
        maxResponseBytes: 16,
      );
      try {
        respond({'version': 'x' * 100});
        await failure(limited.readVersion, CoreReadFailure.responseTooLarge);
      } finally {
        limited.close();
      }
    });
    await test('deadline covers body after headers', () async {
      final fast = CoreReadonlyClient(
        endpoint: endpoint,
        timeout: const Duration(milliseconds: 50),
      );
      handler = (request) async {
        request.response.write('{');
        await request.response.flush();
        await Future<void>.delayed(const Duration(milliseconds: 200));
        request.response.write('}');
        await request.response.close();
      };
      try {
        await failure(fast.readMetrics, CoreReadFailure.timeout);
      } finally {
        fast.close();
      }
    });
    await test('close rejects subsequent reads', () async {
      final closed = CoreReadonlyClient(endpoint: endpoint)..close();
      await failure(closed.readMetrics, CoreReadFailure.closed);
    });
    await test('close cancels an active request', () async {
      final arrived = Completer<void>();
      handler = (request) async {
        arrived.complete();
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await request.response.close();
      };
      final cancellable = CoreReadonlyClient(endpoint: endpoint);
      final pending = failure(cancellable.readMetrics, CoreReadFailure.closed);
      await arrived.future;
      cancellable.close();
      await pending;
    });
    await test('metrics rejects a non-object response', () async {
      respond([]);
      await failure(client.readMetrics, CoreReadFailure.invalidResponse);
    });
    await test('deadline covers waiting for headers', () async {
      handler = (request) async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await request.response.close();
      };
      final fast = CoreReadonlyClient(
          endpoint: endpoint, timeout: const Duration(milliseconds: 50));
      try {
        await failure(fast.readVersion, CoreReadFailure.timeout);
      } finally {
        fast.close();
      }
    });
    await test('unsafe endpoints rejected before network access', () async {
      for (final url in [
        'http://example.com:123',
        'https://127.0.0.1:123',
        'http://0.0.0.0:123',
        'http://user:secret@localhost:123',
        'http://localhost:123/path',
        'http://localhost:123?secret=123',
      ]) {
        try {
          CoreReadonlyClient(endpoint: Uri.parse(url));
        } on ArgumentError {
          continue;
        }
        throw StateError('Unsafe endpoint accepted');
      }
    });
  } finally {
    client.close();
    await server.close(force: true);
    await subscription.cancel();
  }
  await test('unavailable controller', () async {
    final stopped = CoreReadonlyClient(endpoint: endpoint);
    try {
      await failure(stopped.readVersion, CoreReadFailure.unavailable);
    } finally {
      stopped.close();
    }
  });
  stdout.writeln('$passed tests passed');
}
