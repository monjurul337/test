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
//     the user can paste __Secure-1PSID + __Secure-1PSIDTS (or a full
//     cookie header / cookies.txt exported from a signed-in session)
//     into the fallback box. Same jar, same verification, same
//     everything afterwards. All browsing stays inside the app.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  // "Gemini web session" settings card state.
  bool _autoRenew = true;
  bool _cookiesVisible = false;

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
    _loadSessionSettings();
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

  // ---- "Gemini web session" settings card ----

  Future<void> _loadSessionSettings() async {
    final renew = await SessionStore.loadAutoRenew();
    final saved = await SessionStore.cookieForUser(_authUser);
    if (!mounted) return;
    setState(() {
      _autoRenew = renew;
      if (saved != null && saved.isNotEmpty) _cookieCtrl.text = saved;
    });
  }

  /// When the account slot changes, the session-cookies box follows
  /// it (that slot's saved header, hidden again).
  Future<void> _prefillCookiesForSlot() async {
    final saved = await SessionStore.cookieForUser(_authUser);
    if (!mounted) return;
    setState(() {
      _cookieCtrl.text = saved ?? '';
      _cookiesVisible = false;
    });
  }

  /// "Sign in" — point the built-in browser at this slot's Gemini
  /// page; Google shows its sign-in flow there when needed.
  Future<void> _openSignInPage() async {
    _say('Sign in with Google in the browser above — after that it '
        'stays saved here, no login again.');
    await _web?.loadUrl(urlRequest: URLRequest(url: WebUri(_startUrl)));
  }

  /// "Refresh" — re-check this slot's session right now: verify the
  /// saved cookies against Gemini, or notice a browser-side login.
  Future<void> _refreshSession() async {
    if (_connecting) return;
    setState(() => _connecting = true);
    try {
      final saved = await SessionStore.cookieForUser(_authUser);
      if (saved != null && SessionStore.cookieHeaderLooksLoggedIn(saved)) {
        final api = GeminiApi();
        final s = await api.getSession(
            forceRefresh: true, explicitAuthUser: _authUser);
        _say('Session OK — Account u/${s.authUser}: ${s.email}');
        final fresh = await SessionStore.cookieForUser(_authUser);
        if (fresh != null && mounted) {
          setState(() => _cookieCtrl.text = fresh);
        }
      } else {
        final header = await _collectCookieHeader();
        if (SessionStore.cookieHeaderLooksLoggedIn(header)) {
          _say('You are signed in inside the browser above — tap '
              '"Connect Gemini" to save this session.');
        } else {
          _say('No saved session for Account u/$_authUser yet. Sign in '
              'in the browser above first.', error: true);
        }
      }
    } catch (e) {
      _say('Refresh failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _setAutoRenew(bool value) async {
    setState(() => _autoRenew = value);
    await SessionStore.saveAutoRenew(value);
    _say(value
        ? 'Cookie auto-renew ON — saved sessions refresh in the background.'
        : 'Cookie auto-renew OFF — sessions are only read when you generate.');
  }

  /// Save the session-cookies box content to the selected slot.
  /// Returns false (with a status message) when the content is not
  /// a usable Gemini cookie.
  Future<bool> _saveSessionCookies({bool quiet = false}) async {
    final normalised = SessionStore.normalisePastedCookies(_cookieCtrl.text);
    if (normalised.isEmpty ||
        !SessionStore.cookieHeaderLooksLoggedIn(normalised)) {
      if (!quiet) {
        _say(
          'That is not a usable Gemini cookie. Paste the '
          '__Secure-1PSID value (and __Secure-1PSIDTS), a full Cookie '
          'header, or a cookies.txt export.',
          error: true,
        );
      }
      return false;
    }
    await SessionStore.saveCookieForUser(_authUser, normalised);
    if (mounted) setState(() => _cookieCtrl.text = normalised);
    if (!quiet) _say('Session cookies saved for Account u/$_authUser.');
    return true;
  }

  /// "Test" — save first when the box changed, then verify the
  /// session against Gemini (same finish as Connect).
  Future<void> _testSessionCookies() async {
    if (_connecting) return;
    final saved = await SessionStore.cookieForUser(_authUser) ?? '';
    if (_cookieCtrl.text.trim() != saved.trim()) {
      if (!await _saveSessionCookies(quiet: true)) {
        _say(
          'That is not a usable Gemini cookie. Paste the '
          '__Secure-1PSID value (and __Secure-1PSIDTS), a full Cookie '
          'header, or a cookies.txt export.',
          error: true,
        );
        return;
      }
    } else if (saved.isEmpty) {
      _say('Nothing to test yet — paste a cookie below, or sign in '
          'in the browser above.', error: true);
      return;
    }
    setState(() => _connecting = true);
    try {
      await _verifyAndFinish();
    } catch (e) {
      _say('Test failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _copySessionCookies() async {
    var text = _cookieCtrl.text.trim();
    if (text.isEmpty) {
      text = await SessionStore.cookieForUser(_authUser) ?? '';
    }
    if (text.isEmpty) {
      _say('No session cookies to copy for Account u/$_authUser.',
          error: true);
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    _say('Session cookies copied. Keep them private — they ARE your '
        'Gemini login.');
  }

  Future<void> _removeSessionCookies() async {
    await SessionStore.saveCookieForUser(_authUser, '');
    if (!mounted) return;
    setState(() {
      _cookieCtrl.clear();
      _cookiesVisible = false;
    });
    _say('Saved session for Account u/$_authUser removed. Sign in '
        'above to add it again.');
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

  /// The "Gemini web session" settings card under the browser:
  /// sign-in / refresh, the cookie auto-renew switch, and this
  /// slot's saved session cookies (masked, with Save / Test / Copy /
  /// Remove). All session management lives here now — including the
  /// cookie-paste fallback for a Google-blocked sign-in.
  Widget _sessionCard() {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.cookie_outlined,
                      size: 20, color: scheme.onPrimaryContainer),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Gemini web session',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                      Text(
                          'Generation, metadata + AI Set Director — no API key',
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 15, color: Colors.grey),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Sign in once in the built-in browser above. Your '
                    'login is saved on this device and stays renewed — '
                    'no login again.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _status,
              style: TextStyle(
                fontSize: 13,
                color: _statusIsError ? scheme.error : null,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _connecting ? null : _openSignInPage,
                    icon: const Icon(Icons.login, size: 18),
                    label: const Text('Sign in'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _connecting ? null : _refreshSession,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Refresh'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: _connecting ? null : _connectFromWebView,
              icon: _connecting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.verified_user_outlined, size: 18),
              label: const Text('Connect Gemini (from the browser above)'),
            ),
            const Divider(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(Icons.autorenew,
                      size: 20, color: scheme.primary),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Renew cookies from the app',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                      SizedBox(height: 2),
                      Text(
                        'On (recommended): the app quietly refreshes '
                        'saved sessions in the background, so a pasted '
                        'or idle login does not expire. Off: cookies '
                        'are only read when you generate — the signed-in '
                        'browser renews its own session while you use it.',
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                Switch(value: _autoRenew, onChanged: _setAutoRenew),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Session cookies (Account u/$_authUser)',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: scheme.primary),
            ),
            const SizedBox(height: 6),
            if (!_cookiesVisible)
              InkWell(
                onTap: () => setState(() => _cookiesVisible = true),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    border: Border.all(color: scheme.outline),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.lock_outline,
                          size: 18, color: scheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _cookieCtrl.text.isEmpty
                              ? 'No cookies saved yet — tap to paste'
                              : '••••••••••••••••••••••••••••',
                          style: const TextStyle(
                              fontSize: 13, letterSpacing: 2),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(Icons.visibility_outlined, size: 18),
                    ],
                  ),
                ),
              )
            else
              TextField(
                controller: _cookieCtrl,
                minLines: 3,
                maxLines: 5,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: '__Secure-1PSID value...\n'
                      '__Secure-1PSIDTS value...\n'
                      '(or a full Cookie header / cookies.txt)',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.visibility_off_outlined),
                    onPressed: () =>
                        setState(() => _cookiesVisible = false),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        _connecting ? null : () => _saveSessionCookies(),
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: const Text('Save'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _connecting ? null : _testSessionCookies,
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('Test'),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _copySessionCookies,
                  icon: const Icon(Icons.copy_outlined, size: 16),
                  label: const Text('Copy'),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _connecting ? null : _removeSessionCookies,
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Remove'),
                  style:
                      TextButton.styleFrom(foregroundColor: scheme.error),
                ),
              ],
            ),
            const Text(
              'Paste a cookie for the account selected above. To copy '
              'one: Chrome > gemini.google.com > F12 > Application > '
              'Cookies > copy the __Secure-1PSID and __Secure-1PSIDTS '
              'values. Stored only on this device, sent only to '
              'gemini.google.com.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ),
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
                      await _prefillCookiesForSlot();
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
                          '"Session cookies" box below instead — paste a '
                          'saved session cookie there (Save, then Test).',
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
                  _sessionCard(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
