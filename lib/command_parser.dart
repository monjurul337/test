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
You are Maliha, an autonomous desktop AI assistant for Windows PC.
The user speaks or writes in Bengali, English, or Banglish.
Convert their natural command into a JSON object: {"type": "<TYPE>", "payload": "<PAYLOAD>"}.

Supported TYPES:
- OPEN_APP: payload is app name or executable (e.g. notepad, chrome, calc, explorer, code, etc.)
- OPEN_URL: payload is full URL (e.g. https://www.youtube.com/results?search_query=..., https://google.com, etc.)
- SCREENSHOT: payload is empty string ""
- SCREEN_VISION: payload is user's question or instruction about the current screen (e.g. "Explain what's happening", "Check for errors", etc.)
- WEBCAM_CAPTURE: payload is empty string "" (for capturing stealth room/webcam photos)
- FILE_FETCH: payload is target file name or search query (e.g. "resume.pdf", "main.dart", "report.docx")
- FILE_LIST: payload is directory ("desktop", "downloads", or "documents")
- CLIPBOARD_GET: payload is empty string "" (to read PC clipboard)
- CLIPBOARD_SET: payload is text to copy into Windows clipboard
- BATTERY_GUARD: payload is empty string "" (for battery %, AC power state & power cut detection)
- SCHEDULE_TASK: payload is "<minutes> <action>" (e.g. "30 shutdown", "15 lock", "60 restart")
- STATUS: payload is empty string "" (for CPU, RAM, disk, battery health)
- LOCK: payload is empty string ""
- SHUTDOWN: payload is empty string ""
- RESTART: payload is empty string ""
- CANCEL_SHUTDOWN: payload is empty string ""
- SPEAK: payload is text for PC to speak out loud via TTS
- POWERSHELL: payload is a safe PowerShell command

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

  // 1. Safety & Power Controls
  if (has(['cancel shutdown', 'শাটডাউন বাতিল', 'বাতিল কর'])) {
    return ['CANCEL_SHUTDOWN', ''];
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

  // 2. Screen Vision & Screenshot
  if (has(['explain screen', 'screen vision', 'স্ক্রিন বুঝিয়ে বলো', 'স্ক্রিন এনালাইসিস', 'স্ক্রিনে কী', 'স্ক্রিনে কি', 'analyze screen', 'screen analyze'])) {
    return ['SCREEN_VISION', text];
  }
  if (has(['screenshot', 'স্ক্রিনশট', 'স্ক্রিন শট', 'snip', 'capture screen'])) {
    return ['SCREENSHOT', ''];
  }

  // 3. Stealth Webcam Sentry
  if (has(['webcam', 'ওয়েবক্যাম', 'ক্যামেরা', 'রুমের ছবি', 'cam photo', 'camera photo', 'take photo'])) {
    return ['WEBCAM_CAPTURE', ''];
  }

  // 4. Universal Clipboard
  if (t.startsWith('copy to pc ') || t.startsWith('পিসিতে কপি করো ') || t.startsWith('পিসিতে পেস্ট করো ')) {
    final payload = text.replaceFirst(RegExp(r'^(copy to pc|পিসিতে কপি করো|পিসিতে পেস্ট করো)\s+', caseSensitive: false), '').trim();
    return ['CLIPBOARD_SET', payload];
  }
  if (has(['clipboard', 'ক্লিপবোর্ড', 'get clipboard', 'read clipboard', 'ক্লিপবোর্ড দেখাও'])) {
    return ['CLIPBOARD_GET', ''];
  }

  // 5. Remote File Fetcher & Lister
  if (has(['list files', 'ফাইল লিস্ট', 'ফাইলগুলো দেখাও', 'show files'])) {
    if (has(['download', 'ডাউনলোড'])) return ['FILE_LIST', 'downloads'];
    if (has(['document', 'ডকুমেন্ট'])) return ['FILE_LIST', 'documents'];
    return ['FILE_LIST', 'desktop'];
  }
  if (t.startsWith('file fetch ') || t.startsWith('fetch file ') || t.startsWith('send file ') ||
      t.startsWith('ফাইল পাঠাও ') || t.startsWith('ফাইল দাও ') || t.startsWith('ডাউনলোড করো ')) {
    final target = text.replaceFirst(RegExp(r'^(file fetch|fetch file|send file|ফাইল পাঠাও|ফাইল দাও|ডাউনলোড করো)\s+', caseSensitive: false), '').trim();
    return ['FILE_FETCH', target];
  }

  // 6. Battery & Power Cut Guard
  if (has(['battery', 'ব্যাটারি', 'পাওয়ার', 'বিদ্যুৎ', 'চার্জ', 'power cut', 'power status'])) {
    return ['BATTERY_GUARD', ''];
  }

  // 7. Scheduled Tasks
  if (t.startsWith('schedule ') || t.startsWith('টাইমার ')) {
    final rest = text.replaceFirst(RegExp(r'^(schedule|টাইমার)\s+', caseSensitive: false), '').trim();
    return ['SCHEDULE_TASK', rest];
  }
  if (has(['মিনিট পর', 'minutes later', 'min later'])) {
    final match = RegExp(r'(\d+)\s*(মিনিট|min)').firstMatch(text);
    final mins = match != null ? match.group(1) : '30';
    if (has(['বন্ধ', 'shutdown'])) return ['SCHEDULE_TASK', '$mins shutdown'];
    if (has(['লক', 'lock'])) return ['SCHEDULE_TASK', '$mins lock'];
    if (has(['রিস্টার্ট', 'restart'])) return ['SCHEDULE_TASK', '$mins restart'];
    return ['SCHEDULE_TASK', '$mins shutdown'];
  }

  // 8. PC Status & Hardware Diagnostics
  if (has(['status', 'অবস্থা', 'cpu', 'ram', 'স্ট্যাটাস'])) {
    return ['STATUS', ''];
  }

  // 9. Speech Synthesizer
  if (t.startsWith('say ') || t.startsWith('বলো ')) {
    return ['SPEAK', text.substring(4).trim()];
  }

  // 10. Web Navigation & Searches
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

  // 11. Known Windows Applications
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
