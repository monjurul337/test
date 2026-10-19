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
  void rest(String key, Duration d) => _cooldown[key] = DateTime.now().add(d);

  /// Whether at least one other key is ready right now.
  bool hasReadyAlternative(String current) {
    final DateTime now = DateTime.now();
    return keys.any(
      (String k) =>
          k != current && (_cooldown[k] == null || _cooldown[k]!.isBefore(now)),
    );
  }
}
