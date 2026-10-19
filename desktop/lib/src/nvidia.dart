import 'dart:convert';
import 'dart:io';

import 'gemini.dart' show KeyPool;
import 'llm.dart';

/// Thin client for build.nvidia.com, which speaks the OpenAI chat format.
///
/// Built on dart:io so the app still needs no HTTP package, and it shares the
/// same rotating [KeyPool] as the Gemini client, so you can paste a whole pile
/// of `nvapi-...` keys and let the app spread the load.
class Nvidia implements LlmClient {
  Nvidia(String apiKey, {this.model = 'z-ai/glm-5.2'})
      : pool = KeyPool(apiKey);

  final KeyPool pool;
  final String model;

  /// The model pool. Ordered the way most books should be written: a strong
  /// generalist first, the big reasoner for hard plots, the fast one for
  /// drafts.
  static const List<String> models = <String>[
    'z-ai/glm-5.2',
    'nvidia/nemotron-3-super-120b-a12b',
    'nvidia/nemotron-3-ultra-550b-a55b',
    'nvidia/nemotron-3.5-lightning-30b-a3b',
  ];

  /// Nemotron exposes an explicit thinking switch in its chat template.
  static bool supportsThinking(String model) => model.startsWith('nvidia/');

  static const String _url =
      'https://integrate.api.nvidia.com/v1/chat/completions';

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
      throw LlmException('No NVIDIA API key. Add one in Settings.');
    }

    final List<Map<String, String>> messages = <Map<String, String>>[
      if (system != null && system.trim().isNotEmpty)
        <String, String>{'role': 'system', 'content': system},
      <String, String>{
        'role': 'user',
        'content': asJson
            ? '$prompt\n\nReturn one JSON object and nothing else. '
                'No markdown fences, no commentary.'
            : prompt,
      },
    ];

    final Map<String, dynamic> body = <String, dynamic>{
      'model': model,
      'messages': messages,
      'temperature': temperature,
      'top_p': 0.95,
      'max_tokens': maxTokens,
      'stream': false,
      if (supportsThinking(model))
        'chat_template_kwargs': <String, dynamic>{'thinking': thinking > 0},
    };
    final List<int> payload = utf8.encode(jsonEncode(body));

    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 60);
    try {
      String? lastError;
      final int tries = retries * (pool.length > 1 ? 2 : 1);
      for (int attempt = 0; attempt < tries; attempt++) {
        final String key = pool.next();
        try {
          final HttpClientRequest req = await client.postUrl(Uri.parse(_url));
          req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
          req.headers.set(HttpHeaders.acceptHeader, 'application/json');
          req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
          req.add(payload);
          final HttpClientResponse res = await req.close();
          final String text = await res.transform(utf8.decoder).join();

          if (res.statusCode != 200) {
            lastError = 'HTTP ${res.statusCode}: ${_trim(text)}';
            final bool quota = res.statusCode == 429;
            final bool dead = res.statusCode == 401 || res.statusCode == 403;
            if ((quota || dead) && pool.length > 1) {
              pool.rest(key, Duration(seconds: dead ? 3600 : 60));
              if (pool.hasReadyAlternative(key) && attempt < tries - 1) {
                log?.call('   ${pool.label(key)} '
                    '${dead ? "rejected" : "rate limited"}, switching key');
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
            throw LlmException(lastError);
          }

          final Map<String, dynamic> out =
              jsonDecode(text) as Map<String, dynamic>;
          final List<dynamic> choices =
              (out['choices'] as List<dynamic>?) ?? <dynamic>[];
          if (choices.isEmpty) {
            throw LlmException('Model returned nothing: ${_trim(text)}');
          }
          final Map<String, dynamic> first =
              choices.first as Map<String, dynamic>;
          final Map<String, dynamic> msg =
              (first['message'] as Map<String, dynamic>?) ??
                  <String, dynamic>{};
          final String result = (msg['content'] ?? '').toString().trim();
          if (result.isEmpty) {
            lastError =
                'Empty response (finish_reason=${first['finish_reason']})';
            if (attempt < tries - 1) {
              log?.call('   $lastError, retrying');
              await Future<void>.delayed(const Duration(seconds: 5));
              continue;
            }
            throw LlmException(lastError);
          }
          return _stripThinking(result);
        } on LlmException {
          rethrow;
        } catch (e) {
          lastError = e.toString();
          if (attempt == tries - 1) {
            throw LlmException('Network error: $lastError');
          }
          await Future<void>.delayed(
              Duration(seconds: 4 * (1 << (attempt > 4 ? 4 : attempt))));
        }
      }
      throw LlmException(lastError ?? 'Unknown error');
    } finally {
      client.close(force: true);
    }
  }

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
    final String clean = _stripFences(raw);
    try {
      return jsonDecode(clean) as Map<String, dynamic>;
    } on FormatException {
      final int s = clean.indexOf('{');
      final int e = clean.lastIndexOf('}');
      if (s >= 0 && e > s) {
        return jsonDecode(clean.substring(s, e + 1)) as Map<String, dynamic>;
      }
      throw LlmException('Model did not return valid JSON.');
    }
  }

  /// Reasoning models sometimes prepend a <think> block. Drop it.
  static String _stripThinking(String s) {
    final int end = s.indexOf('</think>');
    return end < 0 ? s : s.substring(end + 8).trim();
  }

  static String _stripFences(String s) {
    String t = s.trim();
    if (t.startsWith('```')) {
      final int nl = t.indexOf('\n');
      if (nl > 0) t = t.substring(nl + 1);
      if (t.endsWith('```')) t = t.substring(0, t.length - 3);
    }
    return t.trim();
  }

  static String _trim(String s) =>
      s.length <= 300 ? s : '${s.substring(0, 300)}...';
}
