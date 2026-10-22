import 'dart:convert';
import 'dart:io';
import '../lib/windows_launch_plan.dart';

/// Read-only audit of the previously captured core. Never starts the file.
Future<void> main(List<String> args) async {
  if (args.length != 1) throw ArgumentError('Expected one snapshot file path');
  const digest =
      '023ed74fa5015aacf09d83ac7d4a80f9d48dbc0459018e8d75303d7d80d6a9ea';
  final plan = await WindowsLaunchPlan.prepare(core: {});
  var result = 'preflightPassed';
  try {
    try {
      await plan.auditExecutable(File(args.single), digest);
    } on LaunchException catch (error) {
      result = error.failure.name;
    }
  } finally {
    await plan.close();
  }
  stdout.writeln(jsonEncode({
    'scope':
        'Read-only file hash, x64 PE header and process basename audit; not runtime compatibility',
    'knownCoreVersion': '1.2.25+2802',
    'expectedSha256': digest,
    'result': result,
    'executionPerformed': false,
  }));
}
