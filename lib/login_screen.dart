// Gemini Login screen — the heart of the "Gemini login feature".
//
// Flow (same idea as the extension, adapted to a standalone app):
//  1. An in-app WebView (Android: Kotlin WebView via
//     flutter_inappwebview_android; Windows: WebView2) opens
//     https://gemini.google.com/app with a DESKTOP CHROME user-agent.
//     That UA matters: Google refuses sign-in to user-agents that look
//     like an embedded/app browser ("This browser or app may not be
//     secure" / disallowed_useragent), while a plain Chrome UA for a
//     cookie session (not OAuth) is the standard working route.
//  2. The user signs in on Google's own page. The app NEVER sees or
//     stores the password — only the resulting session cookies.
//  3. "Connect Gemini" reads the cookies from the WebView cookie
//     manager (__Secure-1PSID etc.), saves them as this app's cookie
//     jar for u/<n>, then verifies by fetching the Gemini app page and
//     extracting the SNlM0e token + account email (GeminiApi.getSession).
//  4. FALLBACK: if Google still blocks the WebView on a device, the
//     user signs in in Chrome instead and pastes __Secure-1PSID +
//     __Secure-1PSIDTS (or a full cookie header / cookies.txt) into
//     the fallback box. Same jar, same verification, same everything
//     afterwards.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'gemini_api.dart';
import 'session_store.dart';

class LoginScreen extends StatefulWidget {
  final int initialAuthUser;
  final VoidCallback? onConnected;
  const LoginScreen({super.key, this.initialAuthUser = 0, this.onConnected});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  InAppWebViewController? _web;
  double _progress = 0;
  bool _connecting = false;
  String _status = 'Sign in with Google below, then tap "Connect Gemini".';
  bool _statusIsError = false;
  final TextEditingController _cookieCtrl = TextEditingController();
  late int _authUser;

  static const _cookieDomains = [
    'https://gemini.google.com',
    'https://accounts.google.com',
    'https://www.google.com',
    'https://google.com',
  ];

  @override
  void initState() {
    super.initState();
    _authUser = widget.initialAuthUser;
  }

  @override
  void dispose() {
    _cookieCtrl.dispose();
    super.dispose();
  }

  void _say(String msg, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _status = msg;
      _statusIsError = error;
    });
  }

  String get _startUrl =>
      'https://gemini.google.com/u/$_authUser/app?authuser=$_authUser';

  Future<String> _collectCookieHeader() async {
    final manager = CookieManager.instance();
    final byName = <String, String>{};
    for (final url in _cookieDomains) {
      try {
        final cookies = await manager.getCookies(url: WebUri(url));
        for (final c in cookies) {
          if (c.value != null && c.value.toString().isNotEmpty) {
            byName[c.name] = c.value.toString();
          }
        }
      } catch (_) {}
    }
    return byName.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  Future<void> _connectFromWebView() async {
    if (_connecting) return;
    setState(() => _connecting = true);
    try {
      _say('Reading login cookies from the browser...');
      final header = await _collectCookieHeader();
      if (!SessionStore.cookieHeaderLooksLoggedIn(header)) {
        _say(
          'No Google login cookies found yet. Finish signing in inside the '
          'page above first (you should see the Gemini chat screen), then tap Connect again.',
          error: true,
        );
        return;
      }
      await SessionStore.saveCookieForUser(_authUser, header);
      await _verifyAndFinish();
    } catch (e) {
      _say('Connect failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _connectFromPaste() async {
    if (_connecting) return;
    final normalised = SessionStore.normalisePastedCookies(_cookieCtrl.text);
    if (normalised.isEmpty ||
        !SessionStore.cookieHeaderLooksLoggedIn(normalised)) {
      _say(
        'Paste did not contain a usable Gemini cookie. Paste the '
        '__Secure-1PSID value (and __Secure-1PSIDTS), a full Cookie header, '
        'or a cookies.txt export from your browser.',
        error: true,
      );
      return;
    }
    setState(() => _connecting = true);
    try {
      // Pasted cookies are stored on the u/0 slot (they carry no authuser).
      await SessionStore.saveCookieForUser(0, normalised);
      if (_authUser != 0) {
        _say('Pasted cookie saved as Account u/0 — verifying u/0...');
        _authUser = 0;
      }
      await _verifyAndFinish();
    } catch (e) {
      _say('Connect failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _verifyAndFinish() async {
    _say('Cookies saved. Verifying Gemini session (SNlM0e token)...');
    final api = GeminiApi();
    final session =
        await api.getSession(forceRefresh: true, explicitAuthUser: _authUser);
    _say('Connected! Gemini Account u/${session.authUser} — ${session.email}');
    widget.onConnected?.call();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gemini connected: ${session.email}')),
      );
    }
  }

  Future<void> _openAddAccount() async {
    final url =
        'https://accounts.google.com/AddSession?hl=en&continue=${Uri.encodeComponent('https://gemini.google.com/app')}';
    await _web?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  Future<void> _signOut() async {
    final manager = CookieManager.instance();
    try {
      await manager.deleteAllCookies();
    } catch (_) {}
    try {
      await WebStorageManager.instance().deleteAllData();
    } catch (_) {}
    await SessionStore.clearAllCookies();
    _say('Signed out. All saved Gemini cookies were removed from this app.');
    await _web?.loadUrl(
        urlRequest: URLRequest(url: WebUri('https://gemini.google.com/app')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gemini Login'),
        actions: [
          IconButton(
            tooltip: 'Reload page',
            onPressed: () => _web?.reload(),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Add another Gmail account',
            onPressed: _openAddAccount,
            icon: const Icon(Icons.person_add_alt_1_outlined),
          ),
          IconButton(
            tooltip: 'Sign out & clear saved cookies',
            onPressed: _signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_progress > 0 && _progress < 1)
            LinearProgressIndicator(value: _progress),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Row(
              children: [
                const Text('Account slot:'),
                const SizedBox(width: 8),
                DropdownButton<int>(
                  value: _authUser,
                  items: List.generate(
                    6,
                    (i) => DropdownMenuItem(
                      value: i,
                      child: Text(i == 0
                          ? 'u/0 (Default Gmail)'
                          : 'u/$i (Gmail #${i + 1})'),
                    ),
                  ),
                  onChanged: (v) async {
                    if (v == null) return;
                    setState(() => _authUser = v);
                    await _web?.loadUrl(
                        urlRequest: URLRequest(url: WebUri(_startUrl)));
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: InAppWebView(
                  initialUrlRequest: URLRequest(url: WebUri(_startUrl)),
                  initialSettings: InAppWebViewSettings(
                    // Desktop Chrome UA — the key setting that lets the
                    // Google cookie-session sign-in work in a WebView.
                    userAgent: GeminiApi.chromeUserAgent,
                    javaScriptEnabled: true,
                    domStorageEnabled: true,
                    databaseEnabled: true,
                    thirdPartyCookiesEnabled: true,
                    clearCache: false,
                    cacheEnabled: true,
                    supportZoom: false,
                    useWideViewPort: true,
                    loadWithOverviewMode: true,
                  ),
                  onWebViewCreated: (controller) => _web = controller,
                  onProgressChanged: (controller, progress) {
                    if (mounted) setState(() => _progress = progress / 100);
                  },
                  onLoadStop: (controller, url) async {
                    // If we landed back on the Gemini app after sign-in,
                    // quietly check whether login cookies already exist
                    // and tell the user they can connect.
                    final u = url?.toString() ?? '';
                    if (u.contains('gemini.google.com')) {
                      final header = await _collectCookieHeader();
                      if (SessionStore.cookieHeaderLooksLoggedIn(header) &&
                          !_connecting) {
                        _say(
                            'Login detected in the page. Tap "Connect Gemini" to finish.');
                      }
                    }
                  },
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              _status,
              style: TextStyle(
                color:
                    _statusIsError ? Theme.of(context).colorScheme.error : null,
                fontSize: 13,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _connecting ? null : _connectFromWebView,
                    icon: _connecting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.verified_user_outlined),
                    label: const Text('Connect Gemini'),
                  ),
                ),
              ],
            ),
          ),
          ExpansionTile(
            title: const Text(
              'Login blocked? Paste cookie instead',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              'If Google shows "This browser or app may not be secure", sign in at gemini.google.com in Chrome, then paste the cookie here.',
              style: TextStyle(fontSize: 12),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                child: TextField(
                  controller: _cookieCtrl,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText:
                        '__Secure-1PSID value...\n__Secure-1PSIDTS value...\n(or a full Cookie header / cookies.txt)',
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: _connecting ? null : _connectFromPaste,
                    icon: const Icon(Icons.paste_outlined, size: 18),
                    label: const Text('Connect with pasted cookie'),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Text(
                  'How to copy: Chrome > gemini.google.com > F12 > Application > '
                  'Cookies > https://gemini.google.com > copy __Secure-1PSID and '
                  '__Secure-1PSIDTS values. Cookies are stored only on this device '
                  'and are only sent to gemini.google.com.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
