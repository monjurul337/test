import 'dart:convert';
import 'package:http/http.dart' as http;

/// Uses Google Gemini AI to understand natural language (Bangla/English/Banglish)
/// and converts it into an executable action. Falls back to [parseCommand] if
/// no API key is set or in case of network issues.
Future<List<String>> parseCommandWithAi(String raw, {String? geminiApiKey}) async {
  final key = geminiApiKey?.trim();
  if (key == null || key.isEmpty) {
    return parseCommand(raw);
  }

  try {
    final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$key');
    final prompt = '''
You are a desktop control AI assistant for Windows PC.
The user speaks or writes in Bengali, English, or Banglish.
Convert their natural command into a JSON object: {"type": "<TYPE>", "payload": "<PAYLOAD>"}.

Supported TYPES:
- OPEN_APP: payload is app name or executable (e.g. notepad, chrome, calc, explorer, code, etc.)
- OPEN_URL: payload is full URL (e.g. https://www.youtube.com/results?search_query=..., https://google.com, etc.)
- SCREENSHOT: payload is empty string ""
- STATUS: payload is empty string "" (for CPU, RAM, disk, battery, or overall PC health)
- LOCK: payload is empty string ""
- SHUTDOWN: payload is empty string ""
- RESTART: payload is empty string ""
- CANCEL_SHUTDOWN: payload is empty string ""
- SPEAK: payload is text for PC to speak out loud via TTS
- POWERSHELL: payload is a safe PowerShell command for other system inquiries or actions

User command: "$raw"

Return ONLY valid JSON with keys "type" and "payload". No markdown formatting, no backticks.
''';

    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': prompt}
            ]
          }
        ],
        'generationConfig': {
          'responseMimeType': 'application/json',
          'temperature': 0.1,
        }
      }),
    ).timeout(const Duration(seconds: 10));

    if (res.statusCode >= 200 && res.statusCode < 300) {
      final data = jsonDecode(res.body);
      final text = data['candidates']?[0]?['content']?['parts']?[0]?['text'];
      if (text != null) {
        final parsed = jsonDecode(text.toString().trim());
        if (parsed is Map && parsed.containsKey('type')) {
          final t = (parsed['type'] ?? '').toString().toUpperCase();
          final p = (parsed['payload'] ?? '').toString();
          if (t.isNotEmpty) {
            return [t, p];
          }
        }
      }
    }
  } catch (_) {
    // Fall back to rule-based parser on any error
  }

  return parseCommand(raw);
}

/// Turns free text (English / Bangla / Banglish) into a structured command
/// understood by the PC Agent. Returns [type, payload].
List<String> parseCommand(String raw) {
  final text = raw.trim();
  final t = text.toLowerCase();

  bool has(List<String> words) => words.any(t.contains);

  if (has(['cancel shutdown', 'শাটডাউন বাতিল', 'বাতিল কর'])) {
    return ['CANCEL_SHUTDOWN', ''];
  }
  if (has(['screenshot', 'স্ক্রিনশট', 'স্ক্রিন শট'])) {
    return ['SCREENSHOT', ''];
  }
  if (has(['restart', 'রিস্টার্ট', 'reboot'])) {
    return ['RESTART', ''];
  }
  if (has(['shutdown', 'শাটডাউন', 'শাট ডাউন'])) {
    return ['SHUTDOWN', ''];
  }
  if (has(['lock', 'লক'])) {
    return ['LOCK', ''];
  }
  if (has(['status', 'অবস্থা', 'cpu', 'ram', 'স্ট্যাটাস'])) {
    return ['STATUS', ''];
  }
  if (t.startsWith('say ') || t.startsWith('বলো ')) {
    return ['SPEAK', text.substring(4).trim()];
  }

  // YouTube with an optional search / play query
  if (has(['youtube', 'ইউটিউব'])) {
    final q = _afterKeywords(text, ['play', 'search', 'চালাও', 'বাজাও', 'খোঁজো']);
    if (q.isNotEmpty && !q.toLowerCase().contains('youtube')) {
      return ['OPEN_URL', 'https://www.youtube.com/results?search_query=${Uri.encodeComponent(q)}'];
    }
    return ['OPEN_URL', 'https://www.youtube.com'];
  }
  if (has(['google', 'গুগল'])) {
    final q = _afterKeywords(text, ['search', 'সার্চ', 'খোঁজো', 'for']);
    if (q.isNotEmpty && !q.toLowerCase().contains('google')) {
      return ['OPEN_URL', 'https://www.google.com/search?q=${Uri.encodeComponent(q)}'];
    }
    return ['OPEN_URL', 'https://www.google.com'];
  }
  if (t.startsWith('http://') || t.startsWith('https://')) {
    return ['OPEN_URL', text];
  }
  if (has(['github', 'গিটহাব'])) {
    return ['OPEN_URL', 'https://github.com'];
  }
  if (has(['facebook', 'ফেসবুক'])) {
    return ['OPEN_URL', 'https://www.facebook.com'];
  }
  if (has(['gmail', 'জিমেইল', 'ইমেইল'])) {
    return ['OPEN_URL', 'https://mail.google.com'];
  }

  const apps = <String, List<String>>{
    'notepad': ['notepad', 'নোটপ্যাড'],
    'calculator': ['calculator', 'ক্যালকুলেটর', 'calc'],
    'chrome': ['chrome', 'ক্রোম'],
    'code': ['vs code', 'vscode', 'visual studio code'],
    'explorer': ['file explorer', 'explorer', 'ফাইল'],
    'paint': ['paint', 'পেইন্ট'],
    'taskmgr': ['task manager'],
    'cmd': ['command prompt', 'cmd'],
    'powershell': ['powershell'],
  };
  for (final entry in apps.entries) {
    if (entry.value.any(t.contains)) return ['OPEN_APP', entry.key];
  }

  // Fallback: strip open-verbs and let the agent try to start it as an app.
  var rest = text
      .replaceAll(RegExp(r'^(open|start|launch|খোলো|খুলো|চালু করো|চালাও)\s+', caseSensitive: false), '')
      .trim();
  if (rest.toLowerCase() == 'pc' || rest.isEmpty) return ['STATUS', ''];
  return ['OPEN_APP', rest];
}

String _afterKeywords(String text, List<String> keywords) {
  final lower = text.toLowerCase();
  for (final k in keywords) {
    final idx = lower.indexOf(k);
    if (idx >= 0) {
      return text.substring(idx + k.length).trim();
    }
  }
  return '';
}
