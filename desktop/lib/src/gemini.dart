import 'dart:convert';
import 'dart:io';

import 'llm.dart';

/// Thin Gemini REST client built on dart:io so the app needs no HTTP package.
class GeminiException extends LlmException {
  GeminiException(super.message);
}

/// A rotating pool of Gemini API keys.
///
/// Paste as many keys as you like - one per line, or separated by commas or
/// spaces. Every request takes the next healthy key, so the free-tier
/// per-key rate limit is shared out instead of blocking the whole book.
class KeyPool {
  KeyPool(String raw) : keys = parse(raw);

  final List<String> keys;

  int _cursor = 0;
  static final Map<String, DateTime> _cooldown = <String, DateTime>{};

  /// Splits a blob of pasted text into unique, plausible-looking keys.
  static List<String> parse(String raw) {
    final List<String> out = <String>[];
    for (final String piece in raw.split(RegExp(r'[\s,;]+'))) {
      final String k = piece.trim();
      if (k.length >= 20 && !out.contains(k)) out.add(k);
    }
    return out;
  }

  bool get isEmpty => keys.isEmpty;
  int get length => keys.length;

  /// Human label for logs: never prints the key itself.
  String label(String key) {
    final int i = keys.indexOf(key);
    return 'key ${i + 1}/${keys.length}';
  }

  /// The next key that is not cooling down, else the one that frees up first.
  String next() {
    final DateTime now = DateTime.now();
    for (int i = 0; i < keys.length; i++) {
      final String k = keys[(_cursor + i) % keys.length];
      final DateTime? until = _cooldown[k];
      if (until == null || until.isBefore(now)) {
        _cursor = (keys.indexOf(k) + 1) % keys.length;
        return k;
      }
    }
    String best = keys.first;
    for (final String k in keys) {
      if (_cooldown[k]!.isBefore(_cooldown[best]!)) best = k;
    }
    return best;
  }

  /// Benches a key that hit a quota or auth error.
  void rest(String key, Duration d) =>
      _cooldown[key] = DateTime.now().add(d);

  /// Whether at least one other key is ready right now.
  bool hasReadyAlternative(String current) {
    final DateTime now = DateTime.now();
    return keys.any((String k) =>
        k != current &&
        (_cooldown[k] == null || _cooldown[k]!.isBefore(now)));
  }
}

class Gemini implements LlmClient {
  Gemini(String apiKey, {this.model = 'gemini-flash-latest'})
      : pool = KeyPool(apiKey);

  final KeyPool pool;
  final String model;

  /// Only the rolling aliases, so the app follows Google's current flash models
  /// without a code change.
  static const List<String> models = <String>[
    'gemini-flash-latest',
    'gemini-flash-lite-latest',
  ];

  /// Models that accept generationConfig.thinkingConfig.
  static bool supportsThinking(String model) =>
      model.startsWith('gemini-2.5') ||
      model == 'gemini-flash-latest' ||
      model == 'gemini-flash-lite-latest';

  static const String _base =
      'https://generativelanguage.googleapis.com/v1beta/models';

  @override
  Future<String> generate(
    String prompt, {
    String? system,
    double temperature = 0.9,
    int maxTokens = 8192,
    bool asJson = false,
    int thinking = 0,
    int retries = 5,
    void Function(String)? log,
  }) async {
    if (pool.isEmpty) {
      throw GeminiException('No Gemini API key. Add one in Settings.');
    }
    final Map<String, dynamic> body = <String, dynamic>{
      'contents': <Map<String, dynamic>>[
        <String, dynamic>{
          'role': 'user',
          'parts': <Map<String, String>>[<String, String>{'text': prompt}],
        }
      ],
      'generationConfig': <String, dynamic>{
        'temperature': temperature,
        'maxOutputTokens': maxTokens,
        if (asJson) 'responseMimeType': 'application/json',
        if (supportsThinking(model))
          'thinkingConfig': <String, dynamic>{'thinkingBudget': thinking},
      },
      'safetySettings': <Map<String, String>>[
        for (final String c in <String>[
          'HARM_CATEGORY_HARASSMENT',
          'HARM_CATEGORY_HATE_SPEECH',
          'HARM_CATEGORY_SEXUALLY_EXPLICIT',
          'HARM_CATEGORY_DANGEROUS_CONTENT',
        ])
          <String, String>{'category': c, 'threshold': 'BLOCK_ONLY_HIGH'}
      ],
      if (system != null)
        'systemInstruction': <String, dynamic>{
          'parts': <Map<String, String>>[<String, String>{'text': system}]
        },
    };

    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 60);
    try {
      String? lastError;
      final int tries = retries * (pool.length > 1 ? 2 : 1);
      for (int attempt = 0; attempt < tries; attempt++) {
        final String key = pool.next();
        final Uri uri =
            Uri.parse('$_base/$model:generateContent?key=$key');
        try {
          final HttpClientRequest req = await client.postUrl(uri);
          req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
          req.add(utf8.encode(jsonEncode(body)));
          final HttpClientResponse res = await req.close();
          final String text = await res.transform(utf8.decoder).join();
          if (res.statusCode != 200) {
            lastError = 'HTTP ${res.statusCode}: ${_trim(text)}';
            final bool quota = res.statusCode == 429;
            final bool dead =
                res.statusCode == 400 || res.statusCode == 403;
            if ((quota || dead) && pool.length > 1) {
              pool.rest(key,
                  Duration(seconds: dead ? 3600 : 60));
              if (pool.hasReadyAlternative(key) && attempt < tries - 1) {
                log?.call('   ${pool.label(key)} ${dead ? "rejected" : "rate limited"}'
                    ', switching key');
                continue;
              }
            }
            if (<int>[429, 500, 502, 503, 504].contains(res.statusCode) &&
                attempt < tries - 1) {
              final int wait = 4 * (1 << (attempt > 4 ? 4 : attempt));
              log?.call(
                  '   rate limited (${res.statusCode}), retrying in ${wait}s');
              await Future<void>.delayed(Duration(seconds: wait));
              continue;
            }
            throw GeminiException(lastError);
          }
          final Map<String, dynamic> out =
              jsonDecode(text) as Map<String, dynamic>;
          final List<dynamic> cands =
              (out['candidates'] as List<dynamic>?) ?? <dynamic>[];
          if (cands.isEmpty) {
            throw GeminiException('Model returned nothing: ${_trim(text)}');
          }
          final Map<String, dynamic> cand = cands.first as Map<String, dynamic>;
          final List<dynamic> parts =
              ((cand['content'] as Map<String, dynamic>?)?['parts']
                      as List<dynamic>?) ??
                  <dynamic>[];
          final String result = parts
              .map((dynamic p) => (p as Map<String, dynamic>)['text'] ?? '')
              .join()
              .trim();
          if (result.isEmpty) {
            lastError = 'Empty response (finishReason=${cand['finishReason']})';
            if (attempt < tries - 1) {
              log?.call('   $lastError, retrying');
              await Future<void>.delayed(const Duration(seconds: 5));
              continue;
            }
            throw GeminiException(lastError);
          }
          return result;
        } on GeminiException {
          rethrow;
        } catch (e) {
          lastError = e.toString();
          if (attempt == tries - 1) {
            throw GeminiException('Network error: $lastError');
          }
          await Future<void>.delayed(
              Duration(seconds: 4 * (1 << (attempt > 4 ? 4 : attempt))));
        }
      }
      throw GeminiException(lastError ?? 'Unknown error');
    } finally {
      client.close(force: true);
    }
  }

  /// Same as [generate] but guarantees a decoded JSON object.
  @override
  Future<Map<String, dynamic>> generateJson(
    String prompt, {
    String? system,
    double temperature = 0.9,
    int maxTokens = 16384,
    int thinking = 0,
    void Function(String)? log,
  }) async {
    final String raw = await generate(
      prompt,
      system: system,
      temperature: temperature,
      maxTokens: maxTokens,
      asJson: true,
      thinking: thinking,
      log: log,
    );
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } on FormatException {
      final int s = raw.indexOf('{');
      final int e = raw.lastIndexOf('}');
      if (s >= 0 && e > s) {
        return jsonDecode(raw.substring(s, e + 1)) as Map<String, dynamic>;
      }
      throw GeminiException('Model did not return valid JSON.');
    }
  }

  static String _trim(String s) =>
      s.length <= 300 ? s : '${s.substring(0, 300)}...';
}
