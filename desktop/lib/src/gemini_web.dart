import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'llm.dart';

/// Gemini Web (cookie session) client.
///
/// Talks to gemini.google.com with the cookies the user exported from their
/// own browser, hitting the same `BardFrontendService/StreamGenerate`
/// endpoint the web app itself calls. Used when API keys run out of quota.
///
/// Accepted session formats:
///  1. Playwright storageState `{"cookies":[...],"origins":[...]}`
///  2. Raw browser-extension cookie array `[{"name":...,"value":...}]`
///  3. Object with the cookies under a nested/alternate key
///
/// The key auth cookies are SID, SSID, APISID, SAPISID, __Secure-1PSID and
/// __Secure-3PSID. An expired/invalid session (login redirect, missing
/// `SNlM0e`, HTTP 401/403) is reported as "re-export your session" instead
/// of failing silently. Every prompt starts a fresh chat, like opening
/// gemini.google.com/app/new.
const String geminiWebUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

/// Label stored as the model of anything produced through the cookie session.
const String geminiWebModelLabel = 'gemini-web (cookie)';

/// The auth cookies a healthy session must contain.
const List<String> geminiWebKeyCookies = <String>[
  'SID',
  'SSID',
  'APISID',
  'SAPISID',
  '__Secure-1PSID',
  '__Secure-3PSID',
];

/// Thrown for every Gemini-web problem. [expired] is true when the fix is
/// "re-export the cookies" rather than "retry".
class GeminiWebException extends LlmException {
  final bool expired;
  GeminiWebException(super.message, {this.expired = false});
}

/// One normalized cookie (Playwright storageState shape).
class GeminiWebCookie {
  final String name;
  final String value;
  final String domain;
  final String path;
  final int expires;
  final bool httpOnly;
  final bool secure;
  final String sameSite;

  const GeminiWebCookie({
    required this.name,
    required this.value,
    required this.domain,
    required this.path,
    required this.expires,
    required this.httpOnly,
    required this.secure,
    required this.sameSite,
  });

  bool get isGoogle => <String>[
    'google.com',
    '.google.com',
    'gemini.google.com',
    '.gemini.google.com',
  ].contains(domain.toLowerCase());

  String get header => '$name=$value';
}

/// A parsed + normalized Gemini web session.
class GeminiWebSession {
  final List<GeminiWebCookie> cookies;

  /// Which of the accepted input formats was detected.
  final String format;

  const GeminiWebSession(this.cookies, this.format);

  List<GeminiWebCookie> get googleCookies =>
      cookies.where((GeminiWebCookie c) => c.isGoogle).toList();

  /// Key auth cookie names present in this session.
  List<String> get authCookies => <String>[
    for (final String n in geminiWebKeyCookies)
      if (cookies.any(
        (GeminiWebCookie c) => c.name == n && c.value.trim().isNotEmpty,
      ))
        n,
  ];

  /// Cookie header for gemini.google.com - google.com cookies only, exactly
  /// what the browser would send.
  String get cookieHeader {
    final Set<String> seen = <String>{};
    final List<String> parts = <String>[];
    for (final GeminiWebCookie c in cookies) {
      if (!c.isGoogle || c.path != '/') continue;
      if (c.expires > 0 &&
          c.expires <= DateTime.now().millisecondsSinceEpoch ~/ 1000)
        continue;
      if (RegExp(r'[;\r\n]').hasMatch(c.name + c.value)) continue;
      if (c.name.isEmpty || c.value.isEmpty) continue;
      if (!seen.add(c.name)) continue;
      parts.add(c.header);
    }
    return parts.join('; ');
  }

  /// One-line human summary for logs and dialogs.
  String get summary {
    final List<String> auth = authCookies;
    return '${cookies.length} cookies · ${googleCookies.length} google.com · '
        'auth: ${auth.isEmpty ? 'NONE - session will fail' : auth.join(', ')}';
  }

  /// Cheap cookie count for UI helpers; 0 when [raw] is not a session.
  static int countCookies(String raw) {
    try {
      return parse(raw).cookies.length;
    } catch (_) {
      return 0;
    }
  }

  /// `expirationDate` (float) -> `expires` (int seconds, -1 = session),
  /// sameSite casing, hostOnly/storeId/session stripped.
  static List<GeminiWebCookie> _normalize(List<dynamic> raw) {
    final List<GeminiWebCookie> out = <GeminiWebCookie>[];
    for (final dynamic item in raw) {
      if (item is! Map) continue;
      final String name = (item['name'] ?? '').toString().trim();
      if (name.isEmpty || RegExp(r'[;=\r\n]').hasMatch(name)) continue;
      final String value = (item['value'] ?? '').toString();

      String sameSite = 'None';
      final dynamic rawSame = item['sameSite'];
      if (rawSame != null && rawSame.toString().trim().isNotEmpty) {
        final String ss = rawSame.toString().toLowerCase();
        if (ss == 'lax') {
          sameSite = 'Lax';
        } else if (ss == 'strict') {
          sameSite = 'Strict';
        } else if (ss == 'none' || ss == 'no_restriction') {
          sameSite = 'None';
        }
      }

      int expires = -1;
      final dynamic e = item['expires'] ?? item['expirationDate'];
      if (e is num) {
        expires = e.floor();
      } else if (e != null) {
        final double? parsed = double.tryParse(e.toString());
        if (parsed != null) expires = parsed.floor();
      }

      String domain = (item['domain'] ?? '').toString().trim();
      if (domain.isEmpty) domain = '.google.com';

      String path = (item['path'] ?? '/').toString();
      if (path.isEmpty) path = '/';

      out.add(
        GeminiWebCookie(
          name: name,
          value: value,
          domain: domain,
          path: path,
          expires: expires,
          httpOnly: item['httpOnly'] == true,
          secure: item['secure'] == true,
          sameSite: sameSite,
        ),
      );
    }
    // Last occurrence of a name/domain/path wins (same as a real jar).
    final Map<String, GeminiWebCookie> byKey = <String, GeminiWebCookie>{};
    for (final GeminiWebCookie c in out) {
      byKey['${c.name}|${c.domain}|${c.path}'] = c;
    }
    return byKey.values.toList();
  }

  /// Accepts the three formats described at the top of this file.
  static GeminiWebSession parse(String raw) {
    final String text = raw.trim();
    if (text.isEmpty) {
      throw GeminiWebException('Paste your Gemini web session JSON first.');
    }
    dynamic parsed;
    try {
      parsed = jsonDecode(text);
    } catch (_) {
      throw GeminiWebException(
        'Gemini session is not valid JSON. Expected either a Playwright '
        'storageState {"cookies":[...]} or a browser-extension cookie '
        'array [{"name":"...","value":"...","domain":"..."}].',
      );
    }

    List<dynamic>? found;
    String format = '';

    if (parsed is Map && parsed['cookies'] is List) {
      found = parsed['cookies'] as List;
      format = 'Playwright storageState';
    } else if (parsed is List &&
        parsed.isNotEmpty &&
        parsed.first is Map &&
        (parsed.first as Map)['name'] != null) {
      found = parsed;
      format = 'browser-extension cookie array';
    } else if (parsed is Map) {
      for (final String k in <String>[
        'cookie',
        'Cookie',
        'cookieList',
        'cookieJar',
        'session',
      ]) {
        final dynamic v = parsed[k];
        if (v is List && v.isNotEmpty) {
          found = v;
          format = 'nested key "$k"';
          break;
        }
      }
      if (found == null) {
        for (final dynamic v in parsed.values) {
          if (v is Map &&
              v['cookies'] is List &&
              (v['cookies'] as List).isNotEmpty) {
            found = v['cookies'] as List;
            format = 'nested storageState';
            break;
          }
          if (v is List &&
              v.isNotEmpty &&
              v.first is Map &&
              (v.first as Map)['name'] != null) {
            found = v;
            format = 'nested cookie array';
            break;
          }
        }
      }
    }

    final List<GeminiWebCookie> cookies = found == null
        ? <GeminiWebCookie>[]
        : _normalize(found);
    if (cookies.isEmpty) {
      throw GeminiWebException(
        'No cookies found in the Gemini session JSON. Re-export it from '
        'your browser (Playwright storageState or a cookie-editor export).',
      );
    }
    if (cookies.every((GeminiWebCookie c) => !c.isGoogle)) {
      throw GeminiWebException(
        'The session has no google.com cookies, so gemini.google.com '
        'cannot be restored. Export the cookies while gemini.google.com '
        'is open.',
      );
    }
    final GeminiWebSession session = GeminiWebSession(cookies, format);
    if (!session.authCookies.any(
      (String n) => n == '__Secure-1PSID' || n == '__Secure-3PSID',
    )) {
      throw GeminiWebException(
        'Missing Gemini authentication cookies. Export your own signed-in session.',
      );
    }
    return session;
  }
}

/// Result of a session self-test (Settings -> Test session).
class GeminiWebTestResult {
  final bool ok;
  final int ms;
  final String message;
  final String summary;
  final bool expired;
  const GeminiWebTestResult({
    required this.ok,
    required this.ms,
    required this.message,
    required this.summary,
    this.expired = false,
  });
}

/// Talks to gemini.google.com with a cookie session.
class GeminiWebClient {
  GeminiWebClient(this.session);

  final GeminiWebSession session;

  String? _at; // SNlM0e token
  String _bl = '';
  String? _cid; // conversation id
  String? _rid; // response id
  String? _rcid; // chosen candidate id
  int _reqid = 100000 + Random().nextInt(800000);
  String _lastRaw = ''; // last raw reply, scanned for artwork URLs

  /// The exact CDN URL Gemini served the most recent artwork from. Only set
  /// once the download actually succeeded, so the UI can never show a URL
  /// that does not match the bytes on screen. Cleared at the start of every
  /// attempt, so an old URL never survives a new request.
  String? get lastArtUrl => _lastArtUrl;
  String? _lastArtUrl;
  HttpClient? _shared;

  /// Generated artwork is hosted on the same CDN the web app serves from.
  static final RegExp _imageUrls = RegExp(
    r'https://lh3\.googleusercontent\.com/[^"\s\\]+',
  );

  bool get ready => _at != null && _at!.isNotEmpty;

  HttpClient get _client {
    final HttpClient c = _shared ??= HttpClient()
      ..connectionTimeout = const Duration(seconds: 60);
    return c;
  }

  /// Always identify as desktop Chrome on Windows, on every platform. The
  /// phone variant of the endpoint responds differently, so the client
  /// hints are pinned so every build behaves the same.
  Map<String, String> _headers({bool form = false}) => <String, String>{
    HttpHeaders.userAgentHeader: geminiWebUserAgent,
    HttpHeaders.cookieHeader: session.cookieHeader,
    'origin': 'https://gemini.google.com',
    'referer': 'https://gemini.google.com/',
    'X-Same-Domain': '1',
    'accept-language': 'en-US,en;q=0.9',
    'sec-ch-ua':
        '"Chromium";v="124", "Google Chrome";v="124", "Not-A.Brand";v="99"',
    'sec-ch-ua-mobile': '?0',
    'sec-ch-ua-platform': '"Windows"',
    'Sec-Fetch-Site': 'same-origin',
    if (form)
      HttpHeaders.contentTypeHeader:
          'application/x-www-form-urlencoded;charset=UTF-8',
  };

  static bool _looksLoggedOut(String url, String body) {
    final String u = url.toLowerCase();
    if (u.contains('accounts.google.com') ||
        u.contains('servicelogin') ||
        u.contains('/signin') ||
        u.contains('/login')) {
      return true;
    }
    final String head = body.length > 4000 ? body.substring(0, 4000) : body;
    return head.contains('ServiceLogin') && !head.contains('SNlM0e');
  }

  /// Loads gemini.google.com/app, verifies the session is alive and picks up
  /// the `SNlM0e` token + boq build id.
  Future<void> init({Duration timeout = const Duration(seconds: 45)}) async {
    HttpClientResponse res;
    String body;
    try {
      final HttpClientRequest req = await _client.getUrl(
        Uri.parse('https://gemini.google.com/app'),
      );
      req.followRedirects = false;
      req.headers.set(HttpHeaders.userAgentHeader, geminiWebUserAgent);
      for (final MapEntry<String, String> h in _headers().entries) {
        req.headers.set(h.key, h.value);
      }
      res = await req.close().timeout(timeout);
      body = await res.transform(utf8.decoder).join().timeout(timeout);
    } on TimeoutException {
      throw GeminiWebException(
        'gemini.google.com did not respond within ${timeout.inSeconds}s.',
      );
    } on SocketException catch (e) {
      throw GeminiWebException('Could not reach gemini.google.com: $e');
    }

    final String finalUrl = res.redirects.isNotEmpty
        ? res.redirects.last.location.toString()
        : '';
    if ((res.statusCode >= 300 && res.statusCode < 400) ||
        res.statusCode == 401 ||
        res.statusCode == 403) {
      throw GeminiWebException(
        'Gemini rejected the session (HTTP ${res.statusCode}). '
        'Re-export fresh cookies.',
        expired: true,
      );
    }
    if (res.statusCode >= 400) {
      throw GeminiWebException(
        'gemini.google.com returned HTTP ${res.statusCode}.',
      );
    }
    if (_looksLoggedOut(finalUrl, body)) {
      throw GeminiWebException(
        'The Gemini session is signed out (redirected to the Google login '
        'page). Re-export fresh cookies while gemini.google.com is open.',
        expired: true,
      );
    }

    final String? at = RegExp(r'"SNlM0e":"(.*?)"').firstMatch(body)?.group(1);
    if (at == null || at.isEmpty) {
      throw GeminiWebException(
        'The Gemini session is expired or invalid (no auth token in the '
        'page). Re-export fresh cookies.',
        expired: true,
      );
    }
    _at = at;
    final String? bl = RegExp(r'"cfb2h":"(.*?)"').firstMatch(body)?.group(1);
    if (bl == null || bl.isEmpty)
      throw GeminiWebException(
        'Gemini web build token missing; protocol may have changed.',
      );
    _bl = bl;
    newChat();
  }

  /// Forget the conversation - the equivalent of opening /app/new.
  void newChat() {
    _cid = null;
    _rid = null;
    _rcid = null;
  }

  /// Sends [prompt] and returns Gemini's answer text.
  ///
  /// A reply is only accepted once it is non-empty and - when a
  /// [completeWhen] pattern is given - actually contains the closing marker;
  /// a partial reply is retried instead of being parsed.
  Future<String> ask(
    String prompt, {
    RegExp? completeWhen,
    Duration timeout = const Duration(seconds: 120),
    int attempts = 3,
    bool freshChat = true,
  }) async {
    if (!ready) await init();
    Object? lastErr;
    for (int i = 0; i < attempts; i++) {
      if (freshChat) newChat();
      try {
        final String text = await _send(prompt, timeout: timeout);
        if (text.trim().isEmpty) {
          lastErr = 'Gemini web returned an empty reply.';
        } else if (completeWhen != null && !completeWhen.hasMatch(text)) {
          lastErr = 'Gemini web reply was cut off before the closing marker.';
        } else {
          return text.trim();
        }
      } on GeminiWebException catch (e) {
        lastErr = e.message;
        if (e.expired) {
          // One re-handshake: the token can rotate mid-run.
          _at = null;
          if (i == attempts - 1) rethrow;
          try {
            await init();
          } on GeminiWebException {
            rethrow;
          }
        }
      } on TimeoutException {
        lastErr = 'Gemini web timed out after ${timeout.inSeconds}s.';
      } catch (e) {
        lastErr = e.toString();
      }
      if (i < attempts - 1) {
        await Future<void>.delayed(Duration(seconds: 2 * (i + 1)));
      }
    }
    throw GeminiWebException(
      'Gemini web failed after $attempts attempts. '
      'Last: $lastErr',
    );
  }

  Future<String> _send(String prompt, {required Duration timeout}) async {
    final String at = _at!;
    if (at.isEmpty) {
      throw GeminiWebException(
        'Gemini web session is not initialized.',
        expired: true,
      );
    }
    _lastRaw = '';
    final Uri url = Uri.parse(
      'https://gemini.google.com/_/BardChatUi/data/assistant.lamda.'
      'BardFrontendService/StreamGenerate'
      '?bl=${Uri.encodeQueryComponent(_bl)}&_reqid=$_reqid&rt=c',
    );
    final String inner = jsonEncode(<dynamic>[
      <String>[prompt],
      null,
      <String?>[_cid, _rid, _rcid],
    ]);
    final String freq = jsonEncode(<dynamic>[null, inner]);

    HttpClientResponse res;
    String body;
    try {
      final HttpClientRequest req = await _client.postUrl(url);
      req.followRedirects = false;
      for (final MapEntry<String, String> h in _headers(form: true).entries) {
        req.headers.set(h.key, h.value);
      }
      req.write(
        'f.req=${Uri.encodeQueryComponent(freq)}'
        '&at=${Uri.encodeQueryComponent(at)}',
      );
      res = await req.close().timeout(timeout);
      body = await res.transform(utf8.decoder).join().timeout(timeout);
    } on TimeoutException {
      throw GeminiWebException(
        'Gemini web timed out after ${timeout.inSeconds}s.',
      );
    }
    _reqid += 100000;

    if ((res.statusCode >= 300 && res.statusCode < 400) ||
        res.statusCode == 401 ||
        res.statusCode == 403) {
      throw GeminiWebException(
        'Gemini rejected the session (HTTP ${res.statusCode}). '
        'Re-export fresh cookies.',
        expired: true,
      );
    }
    if (res.statusCode == 429) {
      throw GeminiWebException(
        'Gemini web is rate limiting this account (HTTP 429). '
        'Wait a moment and retry.',
      );
    }
    if (res.statusCode != 200) {
      throw GeminiWebException('Gemini web HTTP ${res.statusCode}.');
    }
    _lastRaw = body;
    return _parseStream(body);
  }

  /// Asks the web app for an image and downloads the artwork it draws.
  ///
  /// The web reply carries the picture as a `lh3.googleusercontent.com` link
  /// rather than base64, so the raw reply is scanned and the first image is
  /// fetched. Text parsing failures are tolerated - artwork-only replies
  /// sometimes confuse the text parser.
  Future<Uint8List> generateImage(
    String prompt, {
    void Function(String)? log,
  }) async {
    if (!ready) await init();
    String lastErr = 'unknown error';
    for (int i = 0; i < 3; i++) {
      newChat();
      _lastArtUrl = null; // fail the flush: no stale URL may stay around
      try {
        await _send(prompt, timeout: const Duration(seconds: 180));
      } on GeminiWebException catch (e) {
        lastErr = e.message;
        if (e.expired) {
          _at = null; // one re-handshake: the token can rotate mid-run
          if (i == 2) rethrow;
          try {
            await init();
          } on GeminiWebException {
            rethrow;
          }
        }
      } on TimeoutException {
        lastErr = 'Gemini web timed out while generating the artwork.';
        continue;
      }
      final String raw = _lastRaw
          .replaceAll(r'\/', '/')
          .replaceAll(r'\u003d', '=')
          .replaceAll(r'\u0026', '&');
      // Single-final-image policy: the reply's FIRST artwork link is the
      // one final image we asked for. Extra links in the same reply are
      // drafts/variants and are never sampled; if the download fails we
      // regenerate from scratch instead of falling back to a secondary.
      final List<RegExpMatch> links = _imageUrls.allMatches(raw).toList();
      if (links.isNotEmpty) {
        final String url = links.first.group(0)!;
        log?.call('Fetching the cover artwork...');
        try {
          final Uint8List bytes = await _downloadArtwork(url);
          if (bytes.length > 1024) {
            // Publish the exact link only together with its bytes - the UI
            // reads this right after the bytes land, so it always shows the
            // URL of the artwork actually being displayed.
            _lastArtUrl = url;
            // Do not log signed artwork URLs.
            return bytes;
          }
          lastErr = 'The reply carried no usable artwork bytes.';
        } catch (e) {
          // Never fall back to a secondary link - regenerate instead.
          lastErr = 'The final artwork link failed to download ($e).';
        }
      }
      if (links.length > 1) {
        log?.call(
          'Ignored ${links.length - 1} extra image link(s) - the '
          'strict single-final-image policy applies.',
        );
      }
      lastErr =
          'Gemini web returned no artwork in the reply (the reply reached us '
          'but carried no image link).';
      if (i < 2) await Future<void>.delayed(const Duration(seconds: 3));
    }
    throw GeminiWebException(
      'Cover artwork failed after 3 attempts. '
      'Last: $lastErr',
    );
  }

  Future<Uint8List> _downloadArtwork(String url) async {
    final Uri uri = Uri.parse(url);
    if (uri.scheme != 'https' ||
        uri.host != 'lh3.googleusercontent.com' ||
        uri.userInfo.isNotEmpty ||
        uri.port != 443) {
      throw GeminiWebException('Unexpected artwork host.');
    }
    final HttpClientRequest req = await _client.getUrl(uri);
    req.followRedirects = false;
    req.headers.set(HttpHeaders.userAgentHeader, geminiWebUserAgent);
    final HttpClientResponse res = await req.close().timeout(
      const Duration(seconds: 60),
    );
    if (res.statusCode != 200) {
      throw GeminiWebException(
        'Artwork download returned HTTP ${res.statusCode}.',
      );
    }
    if (!(res.headers.contentType?.mimeType.startsWith('image/') ?? false)) {
      throw GeminiWebException('Artwork response is not an image.');
    }
    final List<int> chunks = <int>[];
    await for (final List<int> chunk in res.timeout(
      const Duration(seconds: 60),
    )) {
      if (chunks.length + chunk.length > 20 * 1024 * 1024)
        throw GeminiWebException('Artwork exceeds 20 MB.');
      chunks.addAll(chunk);
    }
    return Uint8List.fromList(chunks);
  }

  /// Parses the `)]}'`-prefixed chunked batchexecute stream and returns the
  /// answer text, capturing the conversation ids on the way.
  String _parseStream(String raw) {
    final List<String> payloads = <String>[];
    for (final String line in const LineSplitter().convert(raw)) {
      final String t = line.trim();
      if (!t.startsWith('[')) continue;
      dynamic chunk;
      try {
        chunk = jsonDecode(t);
      } catch (_) {
        continue;
      }
      if (chunk is! List) continue;
      for (final dynamic entry in chunk) {
        if (entry is List &&
            entry.length > 2 &&
            entry[0] == 'wrb.fr' &&
            entry[2] is String) {
          payloads.add(entry[2] as String);
        }
      }
    }

    String best = '';
    for (final String payload in payloads) {
      dynamic body;
      try {
        body = jsonDecode(payload);
      } catch (_) {
        continue;
      }
      final String? text = _extractAnswer(body);
      if (text != null && text.trim().length > best.trim().length) {
        best = text;
        _captureIds(body);
      }
    }

    if (best.trim().isEmpty) {
      if (raw.contains('accounts.google.com') || raw.contains('ServiceLogin')) {
        throw GeminiWebException(
          'The Gemini session expired mid-run. Re-export fresh cookies.',
          expired: true,
        );
      }
      throw GeminiWebException(
        'Gemini web returned no readable answer (the page layout or the '
        'session may have changed).',
      );
    }
    return best;
  }

  static String? _extractAnswer(dynamic body) {
    // Canonical shape: body[4][0][1][0]
    try {
      final dynamic cands = body[4];
      if (cands is List && cands.isNotEmpty) {
        final dynamic first = cands[0];
        if (first is List && first.length > 1) {
          final dynamic texts = first[1];
          if (texts is List && texts.isNotEmpty) {
            final dynamic t = texts[0];
            if (t is String && t.trim().isNotEmpty) return t;
          }
        }
      }
    } catch (_) {
      // fall through
    }
    return null;
  }

  void _captureIds(dynamic body) {
    try {
      final dynamic meta = body[1];
      if (meta is List && meta.length > 1) {
        _cid = meta[0]?.toString();
        _rid = meta[1]?.toString();
      }
      final dynamic cands = body[4];
      if (cands is List && cands.isNotEmpty && cands[0] is List) {
        _rcid = (cands[0] as List)[0]?.toString();
      }
    } catch (_) {
      // ids are optional
    }
  }

  /// Handshake + one tiny prompt, for the Settings test button.
  Future<GeminiWebTestResult> test() async {
    final Stopwatch sw = Stopwatch()..start();
    try {
      await init();
      final String reply = await ask(
        'Reply with the single word OK.',
        attempts: 2,
        timeout: const Duration(seconds: 90),
      );
      sw.stop();
      final String snippet = reply.replaceAll(RegExp(r'\s+'), ' ').trim();
      return GeminiWebTestResult(
        ok: true,
        ms: sw.elapsedMilliseconds,
        message:
            'Session alive - Gemini replied '
            '"${snippet.substring(0, clampInt(snippet.length, 0, 60))}"',
        summary: session.summary,
      );
    } on GeminiWebException catch (e) {
      sw.stop();
      return GeminiWebTestResult(
        ok: false,
        ms: sw.elapsedMilliseconds,
        message: e.message,
        summary: session.summary,
        expired: e.expired,
      );
    } catch (e) {
      sw.stop();
      return GeminiWebTestResult(
        ok: false,
        ms: sw.elapsedMilliseconds,
        message: 'Test failed: $e',
        summary: session.summary,
      );
    }
  }

  void dispose() {
    _shared?.close(force: true);
    _shared = null;
  }

  static int clampInt(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);
}

/// The cookie-session back end wired into the writer's [LlmClient] contract.
/// Text and cover artwork both flow through the session; with no Gemini API
/// keys around, the drawn procedural cover is the last resort.
class GeminiWeb implements LlmClient {
  GeminiWeb(String sessionJson)
    : raw = sessionJson,
      session = GeminiWebSession.parse(sessionJson);

  final String raw;
  final GeminiWebSession session;
  GeminiWebClient? _client;

  GeminiWebClient get _cli {
    final GeminiWebClient c = _client ??= GeminiWebClient(session);
    return c;
  }

  @override
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
    final List<String> head = <String>[
      if (system != null && system.trim().isNotEmpty)
        'Instructions: ${system.trim()}',
      if (asJson)
        'Reply with raw JSON only - no markdown fences, no prose around it, '
            'starting with the first brace.',
    ];
    try {
      return await _cli.ask(
        head.isEmpty ? prompt : '${head.join('\n\n')}\n\n$prompt',
        attempts: retries.clamp(1, 3).toInt(),
      );
    } finally {
      dispose();
    }
  }

  @override
  Future<Map<String, dynamic>> generateJson(
    String prompt, {
    String? system,
    double temperature = 0.9,
    int maxTokens = 16384,
    int thinking = 0,
    void Function(String)? log,
  }) async {
    final String rawOut = await generate(
      prompt,
      system: system,
      temperature: temperature,
      maxTokens: maxTokens,
      asJson: true,
      log: log,
    );
    try {
      return jsonDecode(rawOut) as Map<String, dynamic>;
    } on FormatException {
      final int s = rawOut.indexOf('{');
      final int e = rawOut.lastIndexOf('}');
      if (s >= 0 && e > s) {
        return jsonDecode(rawOut.substring(s, e + 1)) as Map<String, dynamic>;
      }
      throw GeminiWebException('Gemini web did not return valid JSON.');
    }
  }

  /// The public wrapper mirrors the client's latest-artwork link, so the
  /// writer can publish it without touching the client internals.
  String? get lastArtUrl => _cli.lastArtUrl;

  /// Asks the web session to draw [prompt] and returns the artwork bytes.
  Future<Uint8List> generateImage(
    String prompt, {
    void Function(String)? log,
  }) => _cli.generateImage(prompt, log: log);

  /// Handshake + tiny prompt, for the Settings test button.
  Future<GeminiWebTestResult> test() {
    final GeminiWebClient c = _client ??= GeminiWebClient(session);
    return c.test();
  }

  void dispose() {
    _client?.dispose();
    _client = null;
  }
}
