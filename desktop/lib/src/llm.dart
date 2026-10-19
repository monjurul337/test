import 'gemini_web.dart';
import 'nvidia.dart';

/// Anything that can be thrown by a model provider.
class LlmException implements Exception {
  LlmException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The two back ends the app can write with.
class Providers {
  static const String gemini = 'gemini';
  static const String nvidia = 'nvidia';

  static const List<String> all = <String>[gemini, nvidia];

  static String label(String p) =>
      p == nvidia ? 'NVIDIA (build.nvidia.com)' : 'Gemini (cookie session)';

  /// Where to create keys, shown in the key dialog.
  static String keyHome(String p) =>
      p == nvidia ? 'build.nvidia.com' : 'gemini.google.com';

  static List<String> models(String p) =>
      p == nvidia ? Nvidia.models : <String>['gemini-web (cookie)'];

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

/// Builds the right client for [provider] from a blob of pasted keys.
LlmClient createClient({
  required String provider,
  required String keys,
  required String model,
}) =>
    provider == Providers.nvidia ? Nvidia(keys, model: model) : GeminiWeb(keys);
