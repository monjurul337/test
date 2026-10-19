import 'dart:convert';
import 'dart:mirrors';

import '../lib/src/gemini_web.dart';
import '../lib/src/llm.dart';
import '../lib/src/imagegen.dart';

void check(bool condition, String name) {
  if (!condition) throw StateError('FAIL: $name');
}

void main() {
  // Dummy strings only: no real credentials or live requests in this test.
  final cookies = [
    {
      'name': '__Secure-1PSID',
      'value': 'dummy-only',
      'domain': '.google.com',
      'path': '/',
    },
    {'name': 'evil', 'value': 'excluded', 'domain': 'notgoogle.com'},
    {
      'name': 'expired',
      'value': 'excluded',
      'domain': '.google.com',
      'expires': 1,
    },
    {
      'name': 'wrongPath',
      'value': 'excluded',
      'domain': '.google.com',
      'path': '/other',
    },
    {
      'name': 'injected',
      'value': 'bad\r\nCookie: nope',
      'domain': '.google.com',
    },
  ];
  for (final input in [
    cookies,
    {'cookies': cookies},
    {'session': cookies},
    {
      'nested': {'cookies': cookies},
    },
  ]) {
    final session = GeminiWebSession.parse(jsonEncode(input));
    check(
      session.cookieHeader == '__Secure-1PSID=dummy-only',
      'cookie scope/expiry/header sanitation',
    );
  }
  for (final input in [
    '',
    '{}',
    '[]',
    'not json',
    '[{"name":"SID","value":"x","domain":"notgoogle.com"}]',
  ]) {
    var rejected = false;
    try {
      GeminiWebSession.parse(input);
    } catch (_) {
      rejected = true;
    }
    check(rejected, 'reject missing or invalid credentials');
  }
  check(
    createClient(
      provider: Providers.gemini,
      keys: jsonEncode(cookies),
      model: 'ignored',
    ) is GeminiWeb,
    'Gemini factory',
  );
  check(
    Providers.fixModel(Providers.gemini, 'gemini-flash-latest') ==
        'gemini-web (cookie)',
    'migrate model',
  );
  check(
    ImageGen.modelsFor(Providers.gemini).join(',') == 'off,gemini-web-image',
    'cover routing',
  );
  final cli = GeminiWebClient(GeminiWebSession.parse(jsonEncode(cookies)));
  final symbol = MirrorSystem.getSymbol(
    '_parseStream',
    reflectClass(GeminiWebClient).owner as LibraryMirror,
  );
  final payload = [
    null,
    null,
    null,
    null,
    [
      [
        'candidate',
        ['A complete answer.'],
      ],
    ],
  ];
  final stream =
      ")]}'\n123\n${jsonEncode([
        ['wrb.fr', null, jsonEncode(payload)],
      ])}";
  check(
    reflect(cli).invoke(symbol, [stream]).reflectee == 'A complete answer.',
    'canonical stream response',
  );
  var refusedMetadata = false;
  try {
    reflect(cli).invoke(symbol, ['[["metadata-only"]]']);
  } catch (_) {
    refusedMetadata = true;
  }
  check(refusedMetadata, 'do not publish protocol metadata as prose');
  cli.dispose();
  print(
    'PASS: session input formats, cookie boundaries, expiry, injection filtering, factory, model migration and artwork choices. No live request made.',
  );
}
