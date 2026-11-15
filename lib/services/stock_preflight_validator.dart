import 'dart:ui';

class PreflightResult {
  final bool durationOk;
  final bool resolutionOk;
  final bool metadataClean;
  final List<String> warnings;

  const PreflightResult({
    required this.durationOk,
    required this.resolutionOk,
    required this.metadataClean,
    required this.warnings,
  });

  bool get allPassed => durationOk && resolutionOk && metadataClean;
}

class StockPreflightValidator {
  static const _bannedTerms = {
    'adobe', 'shutterstock', 'istock', 'getty', 'pond5', 'freepik',
    'apple', 'iphone', 'ipad', 'samsung', 'galaxy', 'sony', 'nike',
    'adidas', 'disney', 'marvel', 'coca-cola', 'google', 'microsoft',
    'youtube', 'tiktok', 'instagram', 'facebook', 'bitcoin', 'ethereum',
  };

  static PreflightResult validate({
    required Duration? duration,
    required Size? resolution,
    required String title,
    required List<String> keywords,
  }) {
    final warnings = <String>[];
    final secs = duration?.inMilliseconds ?? 0;
    final durationOk = secs >= 4800 && secs <= 60000;
    if (!durationOk) {
      warnings.add('Duration must be 5s–60s for Adobe Stock (got ${(secs / 1000).toStringAsFixed(1)}s).');
    }

    final w = resolution?.width ?? 0;
    final h = resolution?.height ?? 0;
    final resolutionOk = (w >= 1920 && h >= 1080) || (w >= 1080 && h >= 1920);
    if (!resolutionOk) {
      warnings.add('Resolution should be at least 1080p (${w.toInt()}x${h.toInt()}).');
    }

    final lowerTitle = title.toLowerCase();
    final foundBanned = <String>[];
    for (final b in _bannedTerms) {
      if (lowerTitle.contains(b) || keywords.any((k) => k.toLowerCase() == b)) {
        foundBanned.add(b);
      }
    }
    if (foundBanned.isNotEmpty) {
      warnings.add('Remove trademark/banned terms: ${foundBanned.join(", ")}');
    }
    if (title.trim().length < 5) {
      warnings.add('Title is too short.');
    }
    if (keywords.length < 10) {
      warnings.add('Add at least 10 keywords (currently ${keywords.length}).');
    }

    final metadataClean = foundBanned.isEmpty && title.trim().length >= 5 && keywords.length >= 10;
    return PreflightResult(
      durationOk: durationOk,
      resolutionOk: resolutionOk,
      metadataClean: metadataClean,
      warnings: warnings,
    );
  }

  static List<String> sanitizeKeywords(List<String> tags) {
    return tags
        .map((t) => t.trim().toLowerCase())
        .where((t) => t.isNotEmpty && !_bannedTerms.contains(t))
        .toSet()
        .take(49)
        .toList();
  }
}
