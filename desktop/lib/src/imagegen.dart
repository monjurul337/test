import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'gemini.dart' show KeyPool;
import 'llm.dart';
import 'gemini_web.dart';

/// Text-to-image for real cover art, so a cover is a painted scene rather
/// than generated geometry.
///
/// Both providers are called with the same rotating [KeyPool] as the writing
/// models, so your bulk keys cover art generation too.
class ImageGen {
  ImageGen({required this.provider, required String keys, required this.model})
    : raw = keys,
      pool = KeyPool(provider == Providers.nvidia ? keys : '');

  final String raw;
  final String provider;
  final String model;
  final KeyPool pool;

  /// The "no art" choice: fall back to the built-in geometric cover.
  static const String off = 'off';

  static const List<String> geminiModels = <String>['gemini-web-image'];

  static const List<String> nvidiaModels = <String>[
    'black-forest-labs/flux.1-schnell',
    'black-forest-labs/flux.1-dev',
    'stabilityai/stable-diffusion-3.5-large',
  ];

  static List<String> modelsFor(String provider) => <String>[
    off,
    ...(provider == Providers.nvidia ? nvidiaModels : geminiModels),
  ];

  /// Keeps a saved choice valid when the provider changes.
  static String fixModel(String provider, String model) =>
      modelsFor(provider).contains(model) ? model : off;

  /// Returns PNG or JPEG bytes, or throws.
  Future<Uint8List> render(String prompt, {void Function(String)? log}) async {
    if (provider == Providers.gemini) {
      final GeminiWeb client = GeminiWeb(raw);
      try {
        return await client.generateImage(prompt, log: log);
      } finally {
        client.dispose();
      }
    }
    if (pool.isEmpty) {
      throw LlmException('No API key for cover art.');
    }
    return _nvidia(prompt, log: log);
  }

  // NVIDIA image API. Gemini artwork uses the cookie session above.

  Future<Uint8List> _nvidia(String prompt, {void Function(String)? log}) async {
    final bool sd = model.startsWith('stabilityai');
    final Map<String, dynamic> body = sd
        ? <String, dynamic>{
            'prompt': prompt,
            'aspect_ratio': '9:16',
            'cfg_scale': 5,
            'mode': 'text-to-image',
            'output_format': 'png',
          }
        : <String, dynamic>{
            'prompt': prompt,
            'width': 832,
            'height': 1216,
            'cfg_scale': 3.5,
            'steps': model.endsWith('schnell') ? 4 : 30,
            'seed': 0,
          };

    final String text = await _post(
      (String _) => Uri.parse('https://ai.api.nvidia.com/v1/genai/$model'),
      body,
      bearer: true,
      log: log,
    );
    final Map<String, dynamic> out = jsonDecode(text) as Map<String, dynamic>;

    final List<dynamic> artifacts =
        (out['artifacts'] as List<dynamic>?) ?? <dynamic>[];
    for (final dynamic a in artifacts) {
      final String? b64 = (a as Map<String, dynamic>)['base64'] as String?;
      if (b64 != null && b64.isNotEmpty) return base64Decode(b64);
    }
    final String? direct = out['image'] as String?;
    if (direct != null && direct.isNotEmpty) return base64Decode(direct);
    throw LlmException('The image model returned no picture.');
  }

  // ------------------------------------------------------------------ HTTP

  Future<String> _post(
    Uri Function(String key) url,
    Map<String, dynamic> body, {
    required bool bearer,
    void Function(String)? log,
  }) async {
    final List<int> payload = utf8.encode(jsonEncode(body));
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 60);
    try {
      String? lastError;
      final int tries = pool.length > 1 ? 6 : 3;
      for (int attempt = 0; attempt < tries; attempt++) {
        final String key = pool.next();
        try {
          final HttpClientRequest req = await client.postUrl(url(key));
          req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
          req.headers.set(HttpHeaders.acceptHeader, 'application/json');
          if (bearer) {
            req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
          }
          req.add(payload);
          final HttpClientResponse res = await req.close();
          final String text = await res.transform(utf8.decoder).join();
          if (res.statusCode == 200) return text;

          lastError =
              'HTTP ${res.statusCode}: '
              '${text.length > 240 ? '${text.substring(0, 240)}...' : text}';
          final bool dead =
              res.statusCode == 401 ||
              res.statusCode == 403 ||
              res.statusCode == 404;
          if ((res.statusCode == 429 || dead) && pool.length > 1) {
            pool.rest(key, Duration(seconds: dead ? 3600 : 60));
            if (pool.hasReadyAlternative(key) && attempt < tries - 1) {
              log?.call('   cover art: ${pool.label(key)} refused, next key');
              continue;
            }
          }
          if (res.statusCode >= 500 && attempt < tries - 1) {
            await Future<void>.delayed(const Duration(seconds: 5));
            continue;
          }
          throw LlmException(lastError);
        } on LlmException {
          rethrow;
        } catch (e) {
          lastError = e.toString();
          if (attempt == tries - 1) {
            throw LlmException('Cover art failed: $lastError');
          }
          await Future<void>.delayed(const Duration(seconds: 4));
        }
      }
      throw LlmException(lastError ?? 'Cover art failed.');
    } finally {
      client.close(force: true);
    }
  }
}
