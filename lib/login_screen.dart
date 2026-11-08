// Gemini Login screen — the heart of the "Gemini login feature".
//
// The login runs in a CHROMIUM browser built into the app:
//  - Android: the system WebView IS Chromium (the same engine Chrome
//    itself uses), hosted by flutter_inappwebview's Kotlin side.
//  - Windows: WebView2, which is also Chromium (Edge's engine).
// An app cannot embed the separate Chrome app or read its cookies —
// Android/Windows sandboxing forbids any app from touching another
// app's cookie store — so a Chromium-engine browser inside the app is
// the only route that both (a) signs in like Chrome and (b) lets the
// app capture the session cookie afterwards. This screen therefore
// behaves like a small Chrome window: back / forward / reload, a URL
// bar, and popup-window support (Google's sign-in and "Add account"
// flows open popup windows; without onCreateWindow they stall).
//
// Flow (same idea as the extension, adapted to a standalone app):
//  1. The Chromium browser opens https://gemini.google.com/app with a
//     DESKTOP CHROME user-agent. That UA matters: Google refuses
//     sign-in to user-agents that look like an embedded/app browser
//     ("This browser or app may not be secure" /
//     disallowed_useragent), while a plain Chrome UA for a cookie
//     session (not OAuth) is the standard working route.
//  2. The user signs in on Google's own page. The app NEVER sees or
//     stores the password — only the resulting session cookies.
//  3. "Connect Gemini" reads the cookies from the Chromium cookie
//     manager (__Secure-1PSID etc.), saves them as this app's cookie
//     jar for u/<n>, then verifies by fetching the Gemini app page and
//     extracting the SNlM0e token + account email (GeminiApi.getSession).
//  4. FALLBACK: if Google still blocks the in-app browser on a device,
//     the user signs in in Chrome instead and pastes __Secure-1PSID +
//     __Secure-1PSIDTS (or a full cookie header / cookies.txt) into
//     the fallback box. Same jar, same verification, same everything
//     afterwards.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'external_browser.dart';
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

  // Chromium browser chrome (toolbar) state.
  String _currentUrl = '';
  bool _canGoBack = false;
  bool _canGoForward = false;
  bool _loading = false;

  static const _cookieDomains = [
    'https://gemini.google.com',
    'https://accounts.google.com',
    'https://www.google.com',
    'https://google.com',
  ];

  /// Settings shared by the main browser and any sign-in popup window.
  /// Desktop Chrome UA + popup support + third-party cookies are what
  /// make the Google cookie-session sign-in complete like in Chrome.
  static InAppWebViewSettings get _browserSettings => InAppWebViewSettings(
        userAgent: GeminiApi.chromeUserAgent,
        javaScriptEnabled: true,
        domStorageEnabled: true,
        databaseEnabled: true,
        thirdPartyCookiesEnabled: true,
        supportMultipleWindows: true,
        javaScriptCanOpenWindowsAutomatically: true,
        useHybridComposition: true,
        clearCache: false,
        cacheEnabled: true,
        supportZoom: false,
        useWideViewPort: true,
        loadWithOverviewMode: true,
        allowsBackForwardNavigationGestures: true,
      );

  @override
  void initState() {
    super.initState();
    _authUser = widget.initialAuthUser;
    _currentUrl = _startUrl;
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
      _say('Reading login cookies from the Chromium browser...');
      final header = await _collectCookieHeader();
      if (!SessionStore.cookieHeaderLooksLoggedIn(header)) {
        _say(
          'No Google login cookies found yet. Finish signing in inside the '
          'browser above first (you should see the Gemini chat screen), then tap Connect again.',
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

  Future<void> _refreshNavState(InAppWebViewController controller) async {
    try {
      final back = await controller.canGoBack();
      final fwd = await controller.canGoForward();
      final url = await controller.getUrl();
      if (!mounted) return;
      setState(() {
        _canGoBack = back;
        _canGoForward = fwd;
        if (url != null) _currentUrl = url.toString();
      });
    } catch (_) {}
  }

  /// Google sign-in / AddSession opens popup windows. Show them as a
  /// full-screen Chromium window sharing the same cookie jar, exactly
  /// like a Chrome popup, so the sign-in flow can complete.
  Future<bool> _handleCreateWindow(
      InAppWebViewController controller, CreateWindowAction action) async {
    final windowId = action.windowId;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Google sign-in window'),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ),
          body: InAppWebView(
            windowId: windowId,
            initialSettings: _browserSettings,
            onCloseWindow: (_) {
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
          ),
        ),
      ),
    );
    // After a popup sign-in, cookies may already be in the jar.
    final header = await _collectCookieHeader();
    if (SessionStore.cookieHeaderLooksLoggedIn(header) && !_connecting) {
      _say('Login detected. Tap "Connect Gemini" to finish.');
    }
    return true;
  }

  /// Dedicated browser intent: continue this page in a separate real
  /// Chrome window (the user's own Chrome session). This is also the
  /// documented fallback route: if Google blocks the in-app browser,
  /// sign in in Chrome, then bring the session back with the cookie
  /// paste box below. The in-app browser keeps its page and state.
  Future<void> _openInChromeExternal() async {
    final url = _currentUrl.isEmpty ? _startUrl : _currentUrl;
    final ok = await ExternalBrowser.openInChrome(url);
    _say(
      ok
          ? 'Opened in Chrome (separate window). If you sign in there, paste the cookies below to connect that session here.'
          : 'Could not open Chrome on this device.',
      error: !ok,
    );
  }

  Widget _browserToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
            bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            visualDensity: VisualDensity.compact,
            onPressed: _canGoBack ? () => _web?.goBack() : null,
            icon: const Icon(Icons.arrow_back, size: 20),
          ),
          IconButton(
            tooltip: 'Forward',
            visualDensity: VisualDensity.compact,
            onPressed: _canGoForward ? () => _web?.goForward() : null,
            icon: const Icon(Icons.arrow_forward, size: 20),
          ),
          IconButton(
            tooltip: _loading ? 'Stop' : 'Reload',
            visualDensity: VisualDensity.compact,
            onPressed: () => _loading ? _web?.stopLoading() : _web?.reload(),
            icon: Icon(_loading ? Icons.close : Icons.refresh, size: 20),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock_outline, size: 13),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _currentUrl.isEmpty ? _startUrl : _currentUrl,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Open this page in Chrome (separate window)',
            visualDensity: VisualDensity.compact,
            onPressed: _openInChromeExternal,
            icon: const Icon(Icons.open_in_browser, size: 20),
          ),
          const Chip(
            avatar: Icon(Icons.language, size: 14),
            label: Text('Chromium', style: TextStyle(fontSize: 11)),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gemini Login'),
        actions: [
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
          _browserToolbar(),
          if (_progress > 0 && _progress < 1)
            LinearProgressIndicator(value: _progress),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
            child: Row(
              children: [
                const Text('Account slot:'),
                const SizedBox(width: 8),
                Flexible(
                  child: DropdownButton<int>(
                    value: _authUser,
                    isExpanded: true,
                    items: List.generate(
                      6,
                      (i) => DropdownMenuItem(
                        value: i,
                        child: Text(
                          i == 0
                              ? 'u/0 (Default Gmail)'
                              : 'u/$i (Gmail #${i + 1})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    onChanged: (v) async {
                      if (v == null) return;
                      setState(() => _authUser = v);
                      await _web?.loadUrl(
                          urlRequest: URLRequest(url: WebUri(_startUrl)));
                    },
                  ),
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
                  initialSettings: _browserSettings,
                  onWebViewCreated: (controller) => _web = controller,
                  onCreateWindow: _handleCreateWindow,
                  onLoadStart: (controller, url) {
                    if (!mounted) return;
                    setState(() {
                      _loading = true;
                      if (url != null) _currentUrl = url.toString();
                    });
                  },
                  onProgressChanged: (controller, progress) {
                    if (mounted) setState(() => _progress = progress / 100);
                  },
                  onLoadStop: (controller, url) async {
                    if (mounted) setState(() => _loading = false);
                    await _refreshNavState(controller);
                    // If we landed back on the Gemini app after sign-in,
                    // quietly check whether login cookies already exist
                    // and tell the user they can connect.
                    final u = url?.toString() ?? '';
                    // Google's "browser or app may not be secure" block
                    // lands on a /signin/rejected page: point the user
                    // straight at the cookie-paste card below.
                    if (u.contains('accounts.google.com') &&
                        u.contains('rejected')) {
                      _say(
                          'Google blocked the embedded sign-in. Use the '
                          '"Paste a cookie" card below instead — sign in in '
                          'Chrome, paste the cookie, and you are connected.',
                          error: true);
                    }
                    if (u.contains('gemini.google.com')) {
                      final header = await _collectCookieHeader();
                      if (SessionStore.cookieHeaderLooksLoggedIn(header) &&
                          !_connecting) {
                        _say(
                            'Login detected in the browser. Tap "Connect Gemini" to finish.');
                      }
                    }
                  },
                  onUpdateVisitedHistory: (controller, url, isReload) {
                    if (url != null && mounted) {
                      setState(() => _currentUrl = url.toString());
                    }
                  },
                  onReceivedError: (controller, request, error) {
                    if (mounted && (request.isForMainFrame ?? true)) {
                      setState(() => _loading = false);
                    }
                  },
                ),
              ),
            ),
          ),
          // Bottom area is flex-bounded + scrollable: on small phones
          // (or with the keyboard open / the paste tile expanded) it
          // shrinks and scrolls instead of overflowing the screen.
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      _status,
                      style: TextStyle(
                        color: _statusIsError
                            ? Theme.of(context).colorScheme.error
                            : null,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
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
                  const Padding(
                    padding: EdgeInsets.fromLTRB(12, 0, 12, 6),
                    child: Text(
                      'Your login stays saved on this device — you will not '
                      'be asked to sign in again. While you use the app, the '
                      'Google session cookies renew themselves automatically.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                  // Cookie paste is a first-class, always-visible card
                  // (not hidden in a collapsed tile): when Google blocks
                  // the embedded sign-in, this is the way in.
                  Card(
                    margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.key_outlined,
                                  size: 18, color: Color(0xFF7C6CFF)),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Google blocked the sign-in? Paste a cookie',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'If Google shows "This browser or app may not be secure", '
                            'sign in at gemini.google.com in your normal Chrome, copy '
                            'the session cookie, and paste it here — the app connects '
                            'with it directly, no browser sign-in needed.',
                            style:
                                TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _cookieCtrl,
                            minLines: 3,
                            maxLines: 5,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              hintText:
                                  '__Secure-1PSID value...\n__Secure-1PSIDTS value...\n(or a full Cookie header / cookies.txt)',
                            ),
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: OutlinedButton.icon(
                              onPressed:
                                  _connecting ? null : _connectFromPaste,
                              icon: const Icon(Icons.paste_outlined, size: 18),
                              label:
                                  const Text('Connect with pasted cookie'),
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'How to copy: Chrome > gemini.google.com > F12 > Application > '
                            'Cookies > https://gemini.google.com > copy __Secure-1PSID and '
                            '__Secure-1PSIDTS values. Cookies are stored only on this device '
                            'and are only sent to gemini.google.com.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
