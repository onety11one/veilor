import 'dart:convert';
import 'dart:io';
import '../lib/veilor_config.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Object? normalize(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: normalize(value[key])};
  }
  if (value is List) return value.map(normalize).toList();
  return value;
}

bool equal(Object? a, Object? b) =>
    jsonEncode(normalize(a)) == jsonEncode(normalize(b));

// Execute the actual archived methods with the historical copy helper.
// ProxyConfig is reduced to raw/tag because these methods read only them.
Future<List<dynamic>> historical(List<Map<String, Object?>> cases) async {
  final source = File(
    '../../research/karing-vpn-service-reference/lib/app/utils/singbox_config_builder.dart',
  ).readAsStringSync();
  final begin = source.indexOf('  static bool canBuildOutbound(');
  final end = source.indexOf('  static void _rulesetAddGeosite(', begin);
  check(begin >= 0 && end > begin, 'Historical source structure changed');
  final methods = source.substring(begin, end);
  final helper = File('test/reference/deep_copy_utils.dart').absolute.uri;
  final temp = await Directory.systemTemp.createTemp('veilor-projection-test-');
  Process? process;
  try {
    final runner = File('${temp.path}/oracle.dart');
    await runner.writeAsString('''
import 'dart:io';
import 'dart:convert';
import '$helper';
class ProxyConfig {
  ProxyConfig(this.raw, this.tag);
  dynamic raw;
  String tag;
}
class HistoricalBuilder {
$methods
}
Future<void> main() async {
  final cases = jsonDecode(await stdin.transform(utf8.decoder).join()) as List;
  final results = [];
  for (final item in cases) {
    final profile = ProxyConfig(item['raw'], item['tag']);
    results.add({'outbound': HistoricalBuilder.buildOutbound(profile),
      'rawAfter': profile.raw});
  }
  stdout.write(jsonEncode(results));
}
''');
    process = await Process.start(Platform.resolvedExecutable, [runner.path]);
    final output = process.stdout.transform(utf8.decoder).join();
    final errors = process.stderr.transform(utf8.decoder).join();
    process.stdin.write(jsonEncode(cases));
    await process.stdin.close();
    final code = await process.exitCode.timeout(const Duration(seconds: 10));
    check(code == 0, 'Historical oracle failed: ${await errors}');
    return jsonDecode(await output) as List<dynamic>;
  } finally {
    process?.kill();
    await temp.delete(recursive: true);
  }
}

Future<void> main() async {
  var passed = 0;
  void test(String name, void Function() action) {
    action();
    passed++;
    stdout.writeln('PASS $name');
  }

  final projector = OutboundProjector();
  final fixture =
      jsonDecode(File('test/fixtures/vless_profile.json').readAsStringSync())
          as Map<String, dynamic>;
  final expected = jsonDecode(
    File('test/fixtures/vless_outbound.expected.json').readAsStringSync(),
  );
  test('VLESS synthetic fixture matches independently specified golden', () {
    check(
      equal(projector.project(raw: fixture, tag: 'test-vless'), expected),
      'VLESS outbound mismatch',
    );
  });
  final cases = <Map<String, Object?>>[
    {'raw': fixture, 'tag': 'test-vless'},
    {
      'raw': {'type': 'direct', 'tag': 'stale'},
      'tag': 'direct-test',
    },
    {
      'raw': {
        'type': 'shadowsocks',
        'tag': 'ss',
        'method': 'test-method',
        'password': 'synthetic-password',
        'server': 'ss.example.invalid',
        'server_port': 1234,
      },
      'tag': 'ss',
    },
    {
      'raw': {
        'type': 'unknown-future-protocol',
        'custom': {
          'flag': true,
          'optional': null,
          'items': [
            1,
            'text',
            {
              'nested': [false],
            },
          ],
        },
        'detour': 'chain-test',
      },
      'tag': 'future',
    },
    {
      'raw': {
        'type': 'vless',
        'ip': 'metadata',
        'tls': {'ip': 'nested-kept', 'latency': 'nested-kept'},
        'unknown_list': [null, 0, false],
      },
      'tag': 'nested',
    },
    {
      'raw': {
        'type': 'wireguard',
        'peers': [
          {'server': 'wg.example.invalid'},
        ],
      },
      'tag': 'wg-fragment-only',
    },
  ];
  final oracle = await historical(cases);
  for (var i = 0; i < cases.length; i++) {
    test('output matches actual historical builder case $i', () {
      check(
        equal(
          projector.project(
            raw: cases[i]['raw'],
            tag: cases[i]['tag'] as String,
          ),
          (oracle[i] as Map<String, dynamic>)['outbound'],
        ),
        'Historical difference',
      );
    });
  }
  test(
    'projection never mutates raw tag, unlike historical implementation',
    () {
      final before = jsonEncode(fixture);
      projector.project(raw: fixture, tag: 'current-tag');
      check(
        jsonEncode(fixture) == before && fixture['tag'] == 'outdated-tag',
        'Input mutated',
      );
      check(
        (oracle[0] as Map<String, dynamic>)['rawAfter']['tag'] == 'test-vless',
        'Historical side effect not reproduced by oracle',
      );
    },
  );
  test('nested arrays and maps are independent in both directions', () {
    final raw = <String, Object?>{
      'type': 'vless',
      'tls': {
        'alpn': ['h2'],
        'nested': [
          {'value': 1},
        ],
      },
    };
    final result = projector.project(raw: raw, tag: 'copy-test');
    final outputTls = result['tls'] as Map<String, Object?>;
    (outputTls['alpn'] as List<Object?>).add('http/1.1');
    final inputTls = raw['tls'] as Map<String, Object?>;
    check((inputTls['alpn'] as List<Object?>).length == 1, 'Array alias');
    ((inputTls['nested'] as List<Object?>)[0]
        as Map<String, Object?>)['value'] = 2;
    check(
      ((outputTls['nested'] as List<Object?>)[0]
              as Map<String, Object?>)['value'] ==
          1,
      'Map inside array alias',
    );
  });
  test('output from repeated builds cannot affect another build', () {
    final a = projector.project(raw: fixture, tag: 'a');
    final b = projector.project(raw: fixture, tag: 'b');
    (a['tls'] as Map<String, Object?>)['enabled'] = false;
    check(
      (b['tls'] as Map<String, Object?>)['enabled'] == true,
      'Repeated output alias',
    );
  });
  void fails(Object? raw, String tag, ProfileProjectionFailure expected) {
    try {
      projector.project(raw: raw, tag: tag);
    } on ProfileProjectionException catch (e) {
      check(e.failure == expected, 'Wrong failure');
      check(
        !e.toString().contains('synthetic-password'),
        'Error leaks raw data',
      );
      return;
    }
    throw StateError('Expected projection failure');
  }

  test('null and non-map raw are rejected', () {
    for (final raw in [null, <Object?>[], 'synthetic-password', 42]) {
      fails(raw, 'test', ProfileProjectionFailure.missingRaw);
    }
  });
  test('empty current tag is rejected, with no silent raw fallback', () {
    fails(fixture, ' ', ProfileProjectionFailure.invalidTag);
  });
  test('non-JSON objects, numbers and keys are rejected', () {
    for (final raw in [
      {1: 'synthetic-password'},
      {
        'nested': {1: 'synthetic-password'},
      },
      {'value': double.nan},
      {'value': double.infinity},
      {'value': DateTime.utc(2026)},
    ]) {
      fails(raw, 'test', ProfileProjectionFailure.invalidJson);
    }
  });
  test('cyclic input is bounded and rejected', () {
    final cycle = <Object?>[];
    cycle.add(cycle);
    fails({'value': cycle}, 'test', ProfileProjectionFailure.invalidJson);
  });
  stdout.writeln('$passed tests passed; 6 actual historical comparisons');
}
