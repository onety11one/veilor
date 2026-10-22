import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Synthetic process only. Does not read user profiles or configure a VPN.
Future<void> main(List<String> args) async {
  String argument(String name) => args[args.indexOf(name) + 1];
  if (args.length != 9 || args.first != 'run2') exit(64);
  final requestedPort = int.parse(argument('--service-http-port'));
  final config = jsonDecode(
    await File(argument('--service-config')).readAsString(),
  );
  if (config is! Map<String, dynamic> || config['labOnly'] != true) exit(64);
  if (requestedPort != 0) {
    for (final field in [
      'base_dir',
      'work_dir',
      'cache_dir',
      'core_path',
      'log_path',
      'err_path'
    ]) {
      if (config[field] is! String ||
          !(config[field] as String).startsWith(Directory.current.parent.path))
        exit(65);
    }
    if (!await File(config['core_path'] as String).exists()) exit(65);
    if (config['work_dir'] != Directory.current.path) exit(65);
  }
  final scenario = argument('--mock-scenario');
  if (scenario == 'earlyExit') exit(23);
  final server =
      await HttpServer.bind(InternetAddress.loopbackIPv4, requestedPort);
  if (requestedPort != 0) {
    stdout.writeln('Synthetic diagnostic, not a port announcement.');
  } else {
    stdout.writeln(
      jsonEncode({
        'controlPort': scenario == 'invalidAnnouncement'
            ? -1
            : scenario == 'foreignControl'
                ? config['foreignPort']
                : server.port,
      }),
    );
  }
  await stdout.flush();
  if (scenario != 'noReady') {
    final socket = await Socket.connect(
      '127.0.0.1',
      int.parse(argument('--connected-port')),
    );
    await socket.close();
  }
  if (scenario == 'crashAfterReady') {
    Timer(const Duration(milliseconds: 250), () => exit(29));
  }
  await for (final request in server) {
    if (request.method != 'GET') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
    } else if (request.uri.path == '/reload/') {
      if (scenario == 'hanging') continue;
      if (scenario == 'httpError') {
        request.response.statusCode = HttpStatus.internalServerError;
      } else if (scenario == 'redirect') {
        request.response.statusCode = HttpStatus.found;
        request.response.headers.set(HttpHeaders.locationHeader, '/stop/');
      } else if (scenario == 'oversized') {
        request.response.write('x' * 20000);
      } else {
        request.response.write(switch (scenario) {
          'commandError' ||
          'commandErrorExit' =>
            '{"err":"synthetic-private-error","extra":{"synthetic":true}}',
          'malformedReply' => 'not-json',
          'missingErrorField' => '{"extra":null}',
          'wrongErrorType' => '{"err":false,"extra":null}',
          'missingExtra' => '{"err":null}',
          _ => '{"err":null,"extra":null}',
        });
      }
    } else if (request.uri.path != '/stop/') {
      request.response.statusCode = HttpStatus.notFound;
    } else {
      request.response.write('{"err":null}');
    }
    await request.response.close();
    if (request.uri.path == '/reload/' && scenario == 'commandErrorExit') {
      Timer(const Duration(milliseconds: 250), () => exit(31));
    }
    if (request.uri.path == '/reload/' && scenario == 'releaseControl') {
      await server.close(force: true);
      Timer.periodic(const Duration(hours: 1), (_) {});
      break;
    }
    if (request.uri.path == '/stop/' && scenario != 'noStopExit') {
      await server.close(force: true);
      exit(0);
    }
  }
}
