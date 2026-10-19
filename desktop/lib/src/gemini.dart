import 'dart:convert';
import 'dart:io';

/// Thin Gemini REST client built on dart:io so the app needs no HTTP package.
class GeminiException implements Exception {
  GeminiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class Gemini {
  Gemini(this.apiKey, {this.model = 'gemini-2.5-flash'});

  final String apiKey;
  final String model;

  static const List<String> models = <String>[
    'gemini-2.5-flash',
    'gemini-2.5-pro',
    'gemini-2.5-flash-lite',
  ];

  static const String _base =
      'https://generativelanguage.googleapis.com/v1beta/models';

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
    if (apiKey.trim().isEmpty) {
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
        if (model.startsWith('gemini-2.5'))
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

    final Uri uri = Uri.parse('$_base/$model:generateContent?key=$apiKey');
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 60);
    try {
      String? lastError;
      for (int attempt = 0; attempt < retries; attempt++) {
        try {
          final HttpClientRequest req = await client.postUrl(uri);
          req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
          req.add(utf8.encode(jsonEncode(body)));
          final HttpClientResponse res = await req.close();
          final String text = await res.transform(utf8.decoder).join();
          if (res.statusCode != 200) {
            lastError = 'HTTP ${res.statusCode}: ${_trim(text)}';
            if (<int>[429, 500, 502, 503, 504].contains(res.statusCode) &&
                attempt < retries - 1) {
              final int wait = 4 * (1 << attempt);
              log?.call('   rate limited (${res.statusCode}), retrying in ${wait}s');
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
            if (attempt < retries - 1) {
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
          if (attempt == retries - 1) {
            throw GeminiException('Network error: $lastError');
          }
          await Future<void>.delayed(Duration(seconds: 4 * (1 << attempt)));
        }
      }
      throw GeminiException(lastError ?? 'Unknown error');
    } finally {
      client.close(force: true);
    }
  }

  /// Same as [generate] but guarantees a decoded JSON object.
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
