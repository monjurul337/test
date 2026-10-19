import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'gemini.dart' show KeyPool;
import 'llm.dart';

/// Text-to-image for real cover art, so a cover is a painted scene rather
/// than generated geometry.
///
/// Cover art always runs on FLUX.1-schnell through NVIDIA, using the rotating
/// [KeyPool] built from your NVIDIA keys, whichever model writes the prose.
class ImageGen {
  ImageGen({required String keys, required this.model})
    : raw = keys,
      pool = KeyPool(keys);

  final String raw;
  final String model;
  final KeyPool pool;

  /// The "no art" choice: fall back to the built-in geometric cover.
  static const String off = 'off';

  /// The one cover engine. Apache-2.0 licensed, so covers may be sold, and
  /// fast enough at four steps to be the default.
  static const String flux = 'black-forest-labs/flux.1-schnell';

  /// Cover art is always FLUX.1-schnell through NVIDIA, whichever model is
  /// writing the prose.
  static const List<String> models = <String>[off, flux];

  static List<String> modelsFor(String provider) => models;

  /// Keeps a saved choice valid.
  static String fixModel(String provider, String model) =>
      models.contains(model) ? model : flux;

  /// Friendly label for the picker.
  static String label(String model) =>
      model == off ? 'Off - geometric cover' : 'FLUX.1-schnell (NVIDIA)';

  /// Returns PNG or JPEG bytes, or throws.
  Future<Uint8List> render(String prompt, {void Function(String)? log}) async {
    if (pool.isEmpty) {
      throw LlmException(
        'Cover art needs an NVIDIA API key from build.nvidia.com. '
        'Add one in Session and API keys, or set the cover art to Off.',
      );
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
