import 'dart:convert';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../models/studio_models.dart';

class GeminiCookieService {
  static const String geminiUrl = 'https://gemini.google.com/app';

  static Future<bool> hasActiveSession() async {
    final cookies = await CookieManager.instance().getCookies(
      url: WebUri('https://gemini.google.com'),
    );
    return cookies.any((c) => c.name == '__Secure-1PSID' && c.value.isNotEmpty);
  }

  static String buildAdobeStockPrompt(String sceneName, String shaderSnippet) {
    return '''
Analyze the attached video keyframe and generate commercial microstock metadata.
Scene Name: $sceneName
Visual Context: $shaderSnippet

Follow strict stock contributor policy & buyer-search SEO rules:
- No real-world brand logos/trademarks (e.g. Apple, Nike, Disney, Adobe, Sony).
- Return ONLY a valid JSON object (no markdown fences, no extra text):
{
  "title": "Concise commercial stock video title under 70 characters",
  "category": "Abstract",
  "keywords": ["45 to 49 single-word or short relevant lowercase keywords ordered by relevance"]
}
''';
  }

  /// Uses the exact SNlM0e + content-push.googleapis.com/upload + StreamGenerate RPC
  /// extracted from adobe-stock-meta-writer.zip (runs with logged-in Gemini cookies).
  static String buildDirectRpcScript(String promptText, String base64Image) {
    final safePrompt = jsonEncode(promptText);
    final safeImg = jsonEncode(base64Image);
    return '''
(async function() {
  try {
    const htmlRes = await fetch('https://gemini.google.com/app', { credentials: 'include' });
    const html = await htmlRes.text();
    const atMatch = html.match(/"SNlM0e":"([^"]+)"/);
    const blMatch = html.match(/"cfb2h":"([^"]+)"/);
    const fsidMatch = html.match(/"FdrFJe":"([^"]+)"/);
    if (!atMatch) return JSON.stringify({ ok: false, error: 'SNlM0e token not found. Please sign in to Gemini.' });

    const at = atMatch[1];
    const bl = blMatch ? blMatch[1] : 'boq_assistant-bard-web-server_20250101.00_p0';
    const fsid = fsidMatch ? fsidMatch[1] : '';

    // 1. Upload keyframe JPEG to content-push.googleapis.com/upload
    const bin = atob($safeImg);
    const bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    const fd = new FormData();
    fd.append('file', new Blob([bytes], { type: 'image/jpeg' }), 'keyframe.jpg');

    const upRes = await fetch('https://content-push.googleapis.com/upload', {
      method: 'POST',
      headers: { 'Push-ID': 'feeds/mcudyrk2a4khkz', 'X-Tenant-Id': 'bard-storage' },
      body: fd,
      credentials: 'include'
    });
    const fileRef = (await upRes.text()).trim();
    if (!upRes.ok || !fileRef) return JSON.stringify({ ok: false, error: 'Image upload HTTP ' + upRes.status });

    // 2. Call StreamGenerate RPC
    const qs = '?bl=' + encodeURIComponent(bl) + (fsid ? '&f.sid=' + encodeURIComponent(fsid) : '') + '&hl=en&_reqid=' + (Math.floor(Math.random() * 900000) + 100000) + '&rt=c';
    const inner = JSON.stringify([[ $safePrompt, 0, null, [[[fileRef], 'keyframe.jpg']], null, null, 0 ], null, ['', '', '']]);
    const freq = JSON.stringify([null, inner]);
    const form = 'f.req=' + encodeURIComponent(freq) + '&at=' + encodeURIComponent(at) + '&';

    const rpcRes = await fetch('https://gemini.google.com/_/BardChatUi/data/assistant.lamda.BardFrontendService/StreamGenerate' + qs, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8', 'X-Same-Domain': '1' },
      body: form,
      credentials: 'include'
    });
    const rawText = await rpcRes.text();
    const jsonMatch = rawText.match(/\{[\s\S]*?"title"[\s\S]*?"keywords"[\s\S]*?\}/);
    if (jsonMatch) {
      return JSON.stringify({ ok: true, data: jsonMatch[0].replace(/\\"/g, '"').replace(/\\n/g, ' ') });
    }
    return JSON.stringify({ ok: false, error: 'Could not parse JSON from StreamGenerate response', raw: rawText.slice(0, 400) });
  } catch (e) {
    return JSON.stringify({ ok: false, error: String(e) });
  }
})();
''';
  }

  static String buildDomInjectionScript(String promptText, String base64Image) =>
      buildDirectRpcScript(promptText, base64Image);

  static AdobeMetadata? parseJsonFromText(String raw) {
    final match = RegExp(r'\{[\s\S]*\}').firstMatch(raw);
    if (match == null) return null;
    try {
      final decoded = jsonDecode(match.group(0)!);
      if (decoded is Map<String, dynamic>) {
        return AdobeMetadata.fromJson(decoded);
      }
    } catch (_) {}
    return null;
  }
}
