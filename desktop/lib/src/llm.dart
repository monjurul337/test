import 'gemini.dart';
import 'gemini_web.dart';
import 'nvidia.dart';

/// Anything that can be thrown by a model provider.
class LlmException implements Exception {
  LlmException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The three back ends the app can write with.
class Providers {
  static const String gemini = 'gemini';
  static const String web = 'gemini-web';
  static const String nvidia = 'nvidia';

  static const List<String> all = <String>[gemini, nvidia, web];

  static String label(String p) {
    if (p == nvidia) return 'NVIDIA (build.nvidia.com)';
    if (p == web) return 'Gemini Web (cookie session)';
    return 'Google Gemini';
  }

  /// Where to create keys, shown in the key dialog.
  static String keyHome(String p) {
    if (p == nvidia) return 'build.nvidia.com';
    if (p == web) return 'gemini.google.com - export the session JSON';
    return 'aistudio.google.com/apikey';
  }

  static List<String> models(String p) =>
      p == nvidia ? Nvidia.models : Gemini.models;

  static String defaultModel(String p) => models(p).first;

  /// Keeps a saved model valid when the provider changes.
  static String fixModel(String p, String model) =>
      models(p).contains(model) ? model : defaultModel(p);
}

/// What the writer talks to. Both providers expose the same two calls.
abstract class LlmClient {
  Future<String> generate(
    String prompt, {
    String? system,
    double temperature,
    int maxTokens,
    bool asJson,
    int thinking,
    int retries,
    void Function(String)? log,
  });

  Future<Map<String, dynamic>> generateJson(
    String prompt, {
    String? system,
    double temperature,
    int maxTokens,
    int thinking,
    void Function(String)? log,
  });
}

/// Builds the right client for [provider]. [keys] is the Gemini/NVIDIA key
/// blob, or the exported Gemini web session JSON for the cookie provider.
LlmClient createClient({
  required String provider,
  required String keys,
  required String model,
}) {
  if (provider == Providers.nvidia) return Nvidia(keys, model: model);
  if (provider == Providers.web) return GeminiWeb(keys);
  return Gemini(keys, model: model);
}
