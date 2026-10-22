import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../lib/veilor_config.dart';

/// Run only the core's check subcommand, on a generated synthetic fixture.
/// Never pass user settings here. This does not start a proxy or VPN service.
Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln(
        'Usage: dart run tool/check_with_core.dart <core.exe> <synthetic.json>');
    exitCode = 64;
    return;
  }
  final executable = File(args[0]).absolute.path;
  final fixture =
      jsonDecode(await File(args[1]).readAsString()) as Map<String, dynamic>;
  // Refuse arbitrary config input. This tool is deliberately fixture-specific.
  final expectedProxy =
      (fixture['outbounds'] as List<dynamic>).last as Map<String, dynamic>;
  if (expectedProxy['server'] != 'vpn.example.invalid' ||
      expectedProxy['uuid'] != '00000000-0000-4000-8000-000000000001') {
    throw ArgumentError('Expected the fixed synthetic fixture');
  }
  final temporary = await Directory.systemTemp.createTemp('veilor-core-check-');
  final files = <File>[];
  try {
    final observations = <Map<String, Object?>>[];
    for (final name in ['valid', 'missing-route-target', 'invalid-transport']) {
      final config = jsonDecode(jsonEncode(fixture)) as Map<String, dynamic>;
      if (name == 'missing-route-target') {
        (config['route'] as Map<String, dynamic>)['final'] =
            'missing-test-outbound';
      } else if (name == 'invalid-transport') {
        ((config['outbounds'] as List<dynamic>).last
            as Map<String, dynamic>)['transport'] = {
          'type': 'not-a-real-test-transport'
        };
      }
      final file = File('${temporary.path}/$name.json');
      files.add(file);
      await file.writeAsString(jsonEncode(config));
      final process = await Process.start(
          executable, ['check', '--disable-color', '-c', file.path]);
      final output = process.stdout.transform(utf8.decoder).join();
      final error = process.stderr.transform(utf8.decoder).join();
      int code;
      try {
        code = await process.exitCode.timeout(const Duration(seconds: 10));
      } on TimeoutException {
        process.kill();
        await process.exitCode;
        rethrow;
      }
      final stdoutText = await output;
      final stderrText = await error;
      var referencesRejected = false;
      try {
        validateMinimalReferences(config);
      } on MinimalConfigException {
        referencesRejected = true;
      }
      final correct = switch (name) {
        'valid' => code == 0 && !referencesRejected,
        'missing-route-target' => referencesRejected,
        _ => code != 0,
      };
      observations.add({
        'case': name, 'exitCode': code, 'expectedResult': correct,
        'referencesRejected': referencesRejected,
        // All input is synthetic. Do not print full configuration or core logs.
        'hasDiagnostic': stdoutText.isNotEmpty || stderrText.isNotEmpty,
      });
      if (!correct) exitCode = 1;
    }
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(observations));
  } finally {
    for (final file in files) {
      if (await file.exists()) await file.delete();
    }
    await temporary.delete();
  }
}
