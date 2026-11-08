// Standalone Chrome engine (Windows) — the app drives a REAL,
// separate Chrome window through the Chrome DevTools Protocol
// (CDP), the same mechanism the reference desktop tool used with a
// configurable browser path:
//
// * Chrome is launched once with a persistent, app-managed profile
//   (--user-data-dir under the app documents folder) and
//   --remote-debugging-port=0; the chosen port is read back from the
//   profile's DevToolsActivePort file. The profile persists, so a
//   sign-in in that Chrome window survives restarts.
// * Cookie sharing is real in BOTH directions, because the app owns
//   the profile's debugging channel: the app jar can be pushed into
//   Chrome (Storage.setCookies) and Chrome's cookies pulled back
//   into the app jar (Storage.getCookies) — signing in inside the
//   Chrome window therefore logs the app itself in.
// * Page data comes back through CDP callbacks: Runtime.evaluate
//   for extraction, and a Runtime binding ("geminiBridge") that page
//   scripts call to push events (image selections) into the app
//   live — the automatic transfer channel.
//
// This file is pure Dart (dart:io / dart:convert / dart:async) so the
// engine core can be exercised outside Flutter. ANDROID NOTE: none
// of this is possible there — Android gives an app no debugging
// channel into the separate Chrome app and no access to its cookie
// store (OS sandbox), so Android keeps the embedded browser for
// sign-in and picking, plus the plain external-Chrome intent.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

// ---------------------------------------------------------------------
// CDP wire helpers (pure — unit tested)
// ---------------------------------------------------------------------

/// Encode one CDP request frame.
String encodeCdpRequest(
  int id,
  String method, {
  Map<String, dynamic>? params,
  String? sessionId,
}) {
  return jsonEncode({
    'id': id,
    'method': method,
    if (params != null) 'params': params,
    if (sessionId != null) 'sessionId': sessionId,
  });
}

/// A decoded CDP frame: either a response (has an id) or an event.
class CdpFrame {
  final int? id;
  final String? method;
  final Map<String, dynamic> params;
  final Map<String, dynamic>? result;
  final Map<String, dynamic>? error;
  final String? sessionId;
  const CdpFrame({
    this.id,
    this.method,
    this.params = const {},
    this.result,
    this.error,
    this.sessionId,
  });
  bool get isEvent => method != null;
}

/// Decode one raw WebSocket text frame; null when it is not a CDP
/// object.
CdpFrame? decodeCdpFrame(String raw) {
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    return null;
  }
  if (decoded is! Map<String, dynamic>) return null;
  final params = decoded['params'];
  final result = decoded['result'];
  final error = decoded['error'];
  return CdpFrame(
    id: (decoded['id'] as num?)?.toInt(),
    method: decoded['method']?.toString(),
    params: params is Map<String, dynamic> ? params : const {},
    result: result is Map<String, dynamic> ? result : null,
    error: error is Map<String, dynamic> ? error : null,
    sessionId: decoded['sessionId']?.toString(),
  );
}

// ---------------------------------------------------------------------
// Cookies
// ---------------------------------------------------------------------

/// One cookie as CDP reports it (Storage.getCookies) or accepts it
/// (Storage.setCookies).
class CdpCookie {
  final String name;
  final String value;
  final String domain;
  final String path;
  final bool secure;
  final bool httpOnly;

  /// Seconds since epoch; -1 for a session cookie.
  final num expires;
  const CdpCookie({
    required this.name,
    required this.value,
    required this.domain,
    this.path = '/',
    this.secure = true,
    this.httpOnly = false,
    this.expires = -1,
  });

  factory CdpCookie.fromJson(Map<String, dynamic> j) => CdpCookie(
        name: j['name']?.toString() ?? '',
        value: j['value']?.toString() ?? '',
        domain: j['domain']?.toString() ?? '',
        path: j['path']?.toString() ?? '/',
        secure: j['secure'] == true,
        httpOnly: j['httpOnly'] == true,
        expires: (j['expires'] as num?) ?? -1,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'value': value,
        'domain': domain,
        'path': path,
        'secure': secure,
        'httpOnly': httpOnly,
        if (expires > 0) 'expires': expires,
      };
}

/// Build a Cookie header ("a=1; b=2") from CDP cookies whose domain
/// ends with one of [domainSuffixes] (e.g. ['google.com'] matches
/// .google.com and accounts.google.com). When a name repeats, the
/// LAST cookie wins — CDP lists more specific paths later.
String cookieHeaderFromCdp(List<CdpCookie> cookies, List<String> domainSuffixes) {
  final byName = <String, String>{};
  for (final c in cookies) {
    if (c.name.isEmpty) continue;
    final domain = c.domain.toLowerCase();
    final matches = domainSuffixes.any(
        (s) => domain == s.toLowerCase() || domain.endsWith('.${s.toLowerCase()}'));
    if (!matches) continue;
    byName[c.name] = c.value;
  }
  return byName.entries.map((e) => '${e.key}=${e.value}').join('; ');
}

/// Parse a Cookie header into CDP cookies for [domain], so the app
/// jar can be pushed into the Chrome profile.
List<CdpCookie> cdpCookiesFromHeader(String header, {String domain = '.google.com'}) {
  final out = <CdpCookie>[];
  for (final part in header.split(';')) {
    final t = part.trim();
    final eq = t.indexOf('=');
    if (eq <= 0) continue;
    out.add(CdpCookie(
      name: t.substring(0, eq).trim(),
      value: t.substring(eq + 1).trim(),
      domain: domain,
      secure: true,
      httpOnly: t.startsWith('__Secure-') || t.startsWith('__Host-'),
    ));
  }
  return out;
}

// ---------------------------------------------------------------------
// CDP connection
// ---------------------------------------------------------------------

class CdpConnection {
  final WebSocket _ws;
  int _nextId = 1;
  final Map<int, Completer<CdpFrame>> _pending = {};
  final StreamController<CdpFrame> _events =
      StreamController<CdpFrame>.broadcast();

  CdpConnection._(this._ws) {
    _ws.listen(
      (data) {
        if (data is! String) return;
        final frame = decodeCdpFrame(data);
        if (frame == null) return;
        if (frame.isEvent) {
          _events.add(frame);
        } else if (frame.id != null) {
          _pending.remove(frame.id!)?.complete(frame);
        }
      },
      onDone: () {
        for (final c in _pending.values) {
          if (!c.isCompleted) {
            c.completeError(StateError('CDP connection closed'));
          }
        }
        _pending.clear();
      },
    );
  }

  static Future<CdpConnection> connect(String webSocketUrl) async {
    final ws = await WebSocket.connect(webSocketUrl);
    return CdpConnection._(ws);
  }

  /// All CDP events (Page.*, Runtime.*, Target.*, ...).
  Stream<CdpFrame> get events => _events.stream;

  /// Events for one method name only.
  Stream<CdpFrame> on(String method) =>
      _events.stream.where((f) => f.method == method);

  Future<CdpFrame> send(
    String method, {
    Map<String, dynamic>? params,
    String? sessionId,
  }) {
    final id = _nextId++;
    final completer = Completer<CdpFrame>();
    _pending[id] = completer;
    _ws.add(encodeCdpRequest(id, method, params: params, sessionId: sessionId));
    return completer.future;
  }

  Future<void> close() async {
    try {
      await _ws.close();
    } catch (_) {}
  }
}

// ---------------------------------------------------------------------
// Standalone Chrome process
// ---------------------------------------------------------------------

class ChromeStandalone {
  Process? _process;
  int? debugPort;
  String? browserWsUrl;
  String profileDir = '';

  bool get isRunning => debugPort != null && browserWsUrl != null;

  /// Chrome first (the usual install paths), then Edge — both are
  /// Chromium and speak CDP. POSIX paths are included so the engine
  /// core stays testable off Windows; the app UI enables the engine
  /// on Windows.
  static Future<String?> findBrowserExe() async {
    final local = Platform.environment['LOCALAPPDATA'] ?? '';
    final candidates = <String>[
      r'C:\Program Files\Google\Chrome\Application\chrome.exe',
      r'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe',
      if (local.isNotEmpty) '$local\\Google\\Chrome\\Application\\chrome.exe',
      r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
      r'C:\Program Files\Microsoft\Edge\Application\msedge.exe',
      '/usr/bin/google-chrome',
      '/usr/bin/google-chrome-stable',
      '/usr/bin/chromium',
      '/usr/bin/chromium-browser',
      '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    ];
    for (final exe in candidates) {
      if (await File(exe).exists()) return exe;
    }
    return null;
  }

  /// Launch the standalone window with its persistent profile.
  /// [extraArgs] exists for headless smoke tests.
  Future<bool> launch({
    required String profileDirPath,
    int width = 1400,
    int height = 920,
    List<String> extraArgs = const [],
  }) async {
    if (isRunning) return true;
    final exe = await findBrowserExe();
    if (exe == null) return false;
    profileDir = profileDirPath;
    await Directory(profileDir).create(recursive: true);
    final portFile = File('$profileDir${Platform.pathSeparator}DevToolsActivePort');
    if (await portFile.exists()) {
      try {
        await portFile.delete();
      } catch (_) {}
    }
    _process = await Process.start(exe, [
      '--remote-debugging-port=0',
      '--user-data-dir=$profileDir',
      '--no-first-run',
      '--no-default-browser-check',
      '--window-size=$width,$height',
      '--new-window',
      ...extraArgs,
      'about:blank',
    ]);
    // Chrome writes the port + browser ws path into DevToolsActivePort.
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      try {
        if (await portFile.exists()) {
          final lines = (await portFile.readAsString())
              .split('\n')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();
          if (lines.length >= 2) {
            debugPort = int.tryParse(lines[0]);
            if (debugPort != null) {
              browserWsUrl = 'ws://127.0.0.1:$debugPort${lines[1]}';
              return true;
            }
          }
        }
      } catch (_) {}
    }
    return false;
  }

  Future<void> shutdown(CdpConnection? cdp) async {
    if (cdp != null) {
      try {
        await cdp
            .send('Browser.close')
            .timeout(const Duration(seconds: 2));
      } catch (_) {}
      await cdp.close();
    }
    try {
      _process?.kill();
    } catch (_) {}
    _process = null;
    debugPort = null;
    browserWsUrl = null;
  }
}

// ---------------------------------------------------------------------
// A page session inside the standalone Chrome
// ---------------------------------------------------------------------

class ChromePage {
  final CdpConnection cdp;
  final String targetId;
  final String sessionId;
  const ChromePage(this.cdp, this.targetId, this.sessionId);

  Future<void> enable() async {
    await cdp.send('Page.enable', sessionId: sessionId);
    await cdp.send('Runtime.enable', sessionId: sessionId);
    await cdp.send('Network.enable', sessionId: sessionId);
  }

  Future<void> navigate(String url) async {
    await cdp.send('Page.navigate',
        params: {'url': url}, sessionId: sessionId);
  }

  /// Evaluate JS and return its value (returnByValue). Throws a
  /// StateError with the page's exception text on a JS error.
  Future<Object?> evaluate(String expression) async {
    final frame = await cdp.send('Runtime.evaluate', params: {
      'expression': expression,
      'returnByValue': true,
      'awaitPromise': true,
    }, sessionId: sessionId);
    final result = frame.result?['result'] as Map<String, dynamic>?;
    if (frame.result?['exceptionDetails'] != null || result == null) {
      throw StateError(
          'Page JS failed: ${frame.result?['exceptionDetails'] ?? frame.error ?? 'no result'}');
    }
    return result['value'];
  }

  Future<String?> currentUrl() async {
    final v = await evaluate('location.href');
    return v?.toString();
  }

  /// Register a callback name the page can call:
  /// `window.<name>(stringPayload)` — delivered on
  /// [CdpConnection.on]('Runtime.bindingCalled').
  Future<void> addBinding(String name) async {
    await cdp.send('Runtime.addBinding',
        params: {'name': name}, sessionId: sessionId);
  }
}

/// The shared standalone-Chrome control point: one window, one CDP
/// connection, created lazily and reused by every screen.
class ChromeControl {
  ChromeControl._();
  static final ChromeControl shared = ChromeControl._();

  final ChromeStandalone chrome = ChromeStandalone();
  CdpConnection? cdp;
  bool _connecting = false;

  bool get isLive => chrome.isRunning && cdp != null;

  /// Launch (once) and connect. [profileDir] is resolved by the
  /// caller (app documents / GeminiHDStudio / ChromeProfile).
  Future<bool> ensure({
    required String profileDir,
    int width = 1400,
    int height = 920,
    List<String> extraArgs = const [],
  }) async {
    if (isLive) return true;
    if (_connecting) return false;
    _connecting = true;
    try {
      final ok = await chrome.launch(
          profileDirPath: profileDir,
          width: width,
          height: height,
          extraArgs: extraArgs);
      if (!ok) return false;
      cdp = await CdpConnection.connect(chrome.browserWsUrl!);
      return true;
    } catch (_) {
      return false;
    } finally {
      _connecting = false;
    }
  }

  /// Open (or reuse) a page target and attach to it.
  Future<ChromePage?> openPage(String url) async {
    final conn = cdp;
    if (conn == null) return null;
    final created = await conn.send('Target.createTarget', params: {'url': url});
    final targetId = created.result?['targetId']?.toString();
    if (targetId == null) return null;
    final attached = await conn.send('Target.attachToTarget',
        params: {'targetId': targetId, 'flatten': true});
    final sessionId = attached.result?['sessionId']?.toString();
    if (sessionId == null) return null;
    final page = ChromePage(conn, targetId, sessionId);
    await page.enable();
    return page;
  }

  /// All cookies in the profile (browser-level command).
  Future<List<CdpCookie>> allCookies() async {
    final conn = cdp;
    if (conn == null) return const [];
    final frame = await conn.send('Storage.getCookies');
    final list = frame.result?['cookies'];
    if (list is! List) return const [];
    return [
      for (final c in list)
        if (c is Map<String, dynamic>) CdpCookie.fromJson(c),
    ];
  }

  /// Write cookies into the profile (browser-level command).
  Future<void> setCookies(List<CdpCookie> cookies) async {
    final conn = cdp;
    if (conn == null || cookies.isEmpty) return;
    await conn.send('Storage.setCookies',
        params: {'cookies': [for (final c in cookies) c.toJson()]});
  }
}
