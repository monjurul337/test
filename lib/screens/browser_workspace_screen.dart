import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../models/studio_models.dart';
import '../services/anti_detect_scripts.dart';
import '../services/colab_autopilot.dart';
import '../services/profile_manager.dart';
import '../theme/app_theme.dart';

class BrowserWorkspaceScreen extends StatefulWidget {
  final FingerprintProfile fingerprint;
  final ValueChanged<String> onColabTunnelDetected;
  final VoidCallback onRandomizeFingerprint;
  final ValueChanged<int>? onProfileSeedChanged;
  final ValueChanged<String>? onOsChanged;
  final ValueChanged<FingerprintProfile>? onProfileApplied;
  final bool isFullScreen;
  final ValueChanged<bool>? onFullScreenChanged;
  final int profilesVersion;
  final VoidCallback? onOpenProfiles;

  const BrowserWorkspaceScreen({
    super.key,
    required this.fingerprint,
    required this.onColabTunnelDetected,
    required this.onRandomizeFingerprint,
    this.onProfileSeedChanged,
    this.onOsChanged,
    this.onProfileApplied,
    this.isFullScreen = false,
    this.onFullScreenChanged,
    this.profilesVersion = 0,
    this.onOpenProfiles,
  });

  @override
  State<BrowserWorkspaceScreen> createState() => _BrowserWorkspaceScreenState();
}

class _BrowserWorkspaceScreenState extends State<BrowserWorkspaceScreen> {
  int _tabIndex = 0;
  String? _foundTunnel;
  bool _keepAlive = true;
  double _loadProgress = 0.0;
  Timer? _tunnelPollTimer;
  final List<InAppWebViewController?> _controllers = List.filled(5, null);
  List<AccountProfile> _accounts = [];
  String _activeAccountId = 'p1';

  static const _tabs = [
    ('Colab', 'https://colab.research.google.com/', Icons.terminal_rounded),
    ('Gemini', 'https://gemini.google.com/app', Icons.auto_awesome_rounded),
    ('Adobe', 'https://contributor.stock.adobe.com/en/uploads', Icons.camera_rounded),
    ('Shutterstock', 'https://submit.shutterstock.com/dashboard', Icons.collections_rounded),
    ('Magnific', 'https://contributor.magnific.com/', Icons.bolt_rounded),
  ];

  // Runs inside BOTH main Colab page and all cross-origin colab.googleusercontent.com output iframes
  static const String _colabFrameScannerScript = r'''
(function() {
  if (window.__mhColabScannerInstalled) return;
  window.__mhColabScannerInstalled = true;
  const re = /https:\/\/[a-z0-9-]+\.trycloudflare\.com/ig;

  function emitTunnel(url) {
    if (!url || window.__mhLastEmittedTunnel === url) return;
    window.__mhLastEmittedTunnel = url;
    try {
      if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
        window.flutter_inappwebview.callHandler('onColabTunnel', url);
      }
    } catch (e) {}
    try {
      if (window.top && window.top !== window) {
        window.top.postMessage({ type: 'MH_COLAB_TUNNEL', url: url }, '*');
      }
    } catch (e) {}
  }

  if (window === window.top) {
    window.addEventListener('message', function(ev) {
      try {
        if (ev && ev.data && ev.data.type === 'MH_COLAB_TUNNEL' && typeof ev.data.url === 'string') {
          emitTunnel(ev.data.url);
        }
      } catch (e) {}
    });
  }

  function scanFrame() {
    try {
      const links = document.querySelectorAll('a[href*="trycloudflare.com"]');
      if (links && links.length) {
        for (let i = links.length - 1; i >= 0; i--) {
          const m = (links[i].href || '').match(re);
          if (m && m.length) {
            emitTunnel(m[m.length - 1]);
            return;
          }
        }
      }
      const txt = (document.body && document.body.innerText) || (document.documentElement && document.documentElement.textContent) || '';
      const matches = txt.match(re);
      if (matches && matches.length) {
        emitTunnel(matches[matches.length - 1]);
      }
    } catch (e) {}
  }

  setInterval(scanFrame, 1500);
  if (document.readyState === 'complete' || document.readyState === 'interactive') {
    setTimeout(scanFrame, 500);
  } else {
    document.addEventListener('DOMContentLoaded', scanFrame);
  }
})();
''';

  @override
  void initState() {
    super.initState();
    _loadAccounts();
    _tunnelPollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _scanColabForTunnel());
  }

  @override
  void didUpdateWidget(covariant BrowserWorkspaceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.profilesVersion != oldWidget.profilesVersion) {
      _loadAccounts();
    }
  }

  Future<void> _loadAccounts() async {
    final (list, activeId) = await ProfileManager.loadProfiles();
    if (mounted) {
      setState(() {
        _accounts = list;
        _activeAccountId = activeId;
      });
    }
  }

  int _tabForPlatform(String platform) {
    switch (platform) {
      case 'Colab': return 0;
      case 'Gemini': return 1;
      case 'Adobe Stock': return 2;
      case 'Shutterstock': return 3;
      case 'Magnific': return 4;
      default: return _tabIndex < 5 ? _tabIndex : 2;
    }
  }

  Future<void> _selectAccount(AccountProfile acc) async {
    if (acc.id != _activeAccountId) {
      await ProfileManager.snapshotCookiesFor(_activeAccountId);
      await ProfileManager.restoreCookiesFor(acc.id);
      await ProfileManager.saveProfiles(_accounts, acc.id);
    }
    await ProfileManager.applyHttpProxy(acc.proxyUrl);
    final base = FingerprintProfile.defaultAndroid(acc.seed, osType: acc.osType);
    final fp = base.copyWith(
      userAgent: (acc.customUserAgent != null && acc.customUserAgent!.trim().isNotEmpty)
          ? acc.customUserAgent!.trim()
          : base.userAgent,
      webglVendor: (acc.customWebglVendor != null && acc.customWebglVendor!.trim().isNotEmpty)
          ? acc.customWebglVendor!.trim()
          : base.webglVendor,
      webglRenderer: (acc.customWebglRenderer != null && acc.customWebglRenderer!.trim().isNotEmpty)
          ? acc.customWebglRenderer!.trim()
          : base.webglRenderer,
      canvasMode: acc.canvasMode,
      audioMode: acc.audioMode,
      timezone: (acc.timezone != null && acc.timezone!.trim().isNotEmpty)
          ? acc.timezone!.trim()
          : base.timezone,
    );
    widget.onProfileApplied?.call(fp);
    final targetTab = _tabForPlatform(acc.platform);
    setState(() {
      _activeAccountId = acc.id;
      _tabIndex = targetTab;
    });
    _controllers[targetTab]?.reload();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Active: ${acc.name} (${acc.platform}) · Seed #${acc.seed}')),
      );
    }
  }

  @override
  void dispose() {
    _tunnelPollTimer?.cancel();
    super.dispose();
  }

  void _handleDetectedTunnel(String raw) {
    final clean = raw.trim().replaceAll(RegExp(r'/+$'), '');
    if (!clean.startsWith('https://') || !clean.contains('.trycloudflare.com')) return;
    if (clean != _foundTunnel) {
      if (mounted) setState(() => _foundTunnel = clean);
      widget.onColabTunnelDetected(clean);
    }
  }

  Future<void> _scanColabForTunnel() async {
    final c = _controllers[0];
    if (c == null) return;
    try {
      final res = await c.evaluateJavascript(source: r'''
(function() {
  const re = /https:\/\/[a-z0-9-]+\.trycloudflare\.com/ig;
  const links = document.querySelectorAll('a[href*="trycloudflare.com"]');
  if (links.length) {
    const m = links[links.length - 1].href.match(re);
    if (m && m.length) return m[m.length - 1];
  }
  const txt = document.body ? document.body.innerText : '';
  const m = txt.match(re);
  if (m && m.length) return m[m.length - 1];
  for (const fr of document.querySelectorAll('iframe')) {
    try {
      const t = fr.contentDocument && fr.contentDocument.body ? fr.contentDocument.body.innerText : '';
      const fm = t.match(re);
      if (fm && fm.length) return fm[fm.length - 1];
    } catch (e) {}
  }
  return '';
})();
''');
      if (res is String && res.startsWith('https://')) {
        _handleDetectedTunnel(res);
      }
    } catch (_) {}
  }

  InAppWebViewSettings get _settings => InAppWebViewSettings(
        userAgent: widget.fingerprint.userAgent,
        javaScriptEnabled: true,
        domStorageEnabled: true,
        databaseEnabled: true,
        thirdPartyCookiesEnabled: true,
        allowsInlineMediaPlayback: true,
        useHybridComposition: true,
        supportMultipleWindows: true,
        javaScriptCanOpenWindowsAutomatically: true,
        mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
        cacheEnabled: true,
        preferredContentMode: UserPreferredContentMode.MOBILE,
        useWideViewPort: true,
        loadWithOverviewMode: false,
        builtInZoomControls: false,
        displayZoomControls: false,
        textZoom: 100,
        layoutAlgorithm: LayoutAlgorithm.TEXT_AUTOSIZING,
      );

  static const String _strictMobileCss = r'''
(function() {
  let meta = document.querySelector('meta[name="viewport"]');
  if (!meta) {
    meta = document.createElement('meta');
    meta.name = 'viewport';
    document.head.appendChild(meta);
  }
  meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=3.0, user-scalable=yes';
  if (!document.getElementById('mh-strict-mobile')) {
    const style = document.createElement('style');
    style.id = 'mh-strict-mobile';
    style.textContent = 'html, body { max-width: 100% !important; overflow-x: auto !important; }';
    document.head.appendChild(style);
  }
})();
''';

  @override
  Widget build(BuildContext context) {
    final drawerColor = AppColors.drawerOf(context);
    final activePill = AppColors.activePillOf(context);
    final iconBox = AppColors.iconBoxOf(context);
    final borderColor = AppColors.borderOf(context);
    final accentText = AppColors.accentTextOf(context);
    final mutedText = AppColors.mutedOf(context);
    final fp = widget.fingerprint;

    final hideChrome = widget.isFullScreen;

    return Stack(
      children: [
        Column(
          children: [
            if (!hideChrome)
              // Top Professional Workspace Header & Shield Telemetry Strip
              Container(
          decoration: BoxDecoration(
            color: drawerColor,
            border: Border(bottom: BorderSide(color: borderColor)),
          ),
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          child: Column(
            children: [
              // Compact Shield Status Bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: iconBox,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Shield #${fp.seed} · ${fp.osType} · Canvas ${fp.canvasMode}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textOf(context)),
                      ),
                    ),
                    if (true) ...[
                      GestureDetector(
                        onTap: () => widget.onFullScreenChanged?.call(true),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: activePill,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.fullscreen_rounded, size: 15, color: accentText),
                        ),
                      ),
                    ],
                    GestureDetector(
                      onTap: widget.onRandomizeFingerprint,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: activePill,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.shuffle_rounded, size: 12, color: accentText),
                            const SizedBox(width: 4),
                            Text('New Seed', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: accentText)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // Saved Anti-Detect Accounts Strip (created in Settings)
              SizedBox(
                height: 36,
                child: Row(
                  children: [
                    Expanded(
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _accounts.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 6),
                        itemBuilder: (_, idx) {
                          final acc = _accounts[idx];
                          final isSel = acc.id == _activeAccountId;
                          return GestureDetector(
                            onTap: () => _selectAccount(acc),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: isSel ? AppColors.success.withValues(alpha: 0.18) : iconBox,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSel ? AppColors.success : borderColor,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isSel ? Icons.check_circle_rounded : Icons.person_outline_rounded,
                                    size: 13,
                                    color: isSel ? AppColors.success : mutedText,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    acc.platform == 'All' ? acc.name : '${acc.name} · ${acc.platform}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: isSel ? FontWeight.w700 : FontWeight.w600,
                                      color: isSel ? AppColors.success : AppColors.textOf(context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: widget.onOpenProfiles,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                        decoration: BoxDecoration(
                          color: activePill,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_rounded, size: 14, color: accentText),
                            const SizedBox(width: 2),
                            Text('Profiles', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: accentText)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // Modern Icon + Label Pill Tabs (Pond5 removed)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: List.generate(_tabs.length, (i) {
                    final active = _tabIndex == i;
                    final tab = _tabs[i];
                    return GestureDetector(
                      onTap: () => setState(() => _tabIndex = i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                        decoration: BoxDecoration(
                          gradient: active
                              ? const LinearGradient(
                                  colors: [AppColors.primary, AppColors.primarySecondary],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                )
                              : null,
                          color: active ? null : iconBox,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: active ? Colors.transparent : borderColor,
                          ),
                          boxShadow: active
                              ? [
                                  BoxShadow(
                                    color: AppColors.primary.withValues(alpha: 0.25),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ]
                              : null,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              tab.$3,
                              size: 14,
                              color: active ? Colors.white : mutedText,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              tab.$1,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                                color: active ? Colors.white : mutedText,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
        if (!hideChrome && _loadProgress > 0 && _loadProgress < 1.0)
          LinearProgressIndicator(
            value: _loadProgress,
            minHeight: 2,
            backgroundColor: Colors.transparent,
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        if (!hideChrome && _foundTunnel != null)
          InkWell(
            onTap: () => widget.onColabTunnelDetected(_foundTunnel!),
            child: Container(
              width: double.infinity,
              color: activePill,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Row(
                children: [
                  const Icon(Icons.bolt_rounded, size: 16, color: AppColors.success),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Colab Live: $_foundTunnel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: accentText),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('Open Studio →', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: IndexedStack(
            index: _tabIndex,
            children: List.generate(_tabs.length, (i) {
              return InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri(_tabs[i].$2)),
                initialSettings: _settings,
                initialUserScripts: UnmodifiableListView<UserScript>([
                  UserScript(
                    source: AntiDetectScripts.buildUserScript(widget.fingerprint),
                    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                    forMainFrameOnly: false,
                  ),
                  if (i == 0)
                    UserScript(
                      source: _colabFrameScannerScript,
                      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
                      forMainFrameOnly: false,
                    ),
                ]),
                onWebViewCreated: (c) {
                  _controllers[i] = c;
                  if (i == 0) {
                    c.addJavaScriptHandler(
                      handlerName: 'onColabTunnel',
                      callback: (args) {
                        if (args.isNotEmpty && args[0] is String) {
                          _handleDetectedTunnel(args[0] as String);
                        }
                      },
                    );
                  }
                },
                onCreateWindow: (c, createWindowAction) async {
                  final u = createWindowAction.request.url;
                  if (u != null) {
                    await c.loadUrl(urlRequest: URLRequest(url: u));
                  }
                  return false;
                },
                onProgressChanged: (c, p) {
                  if (i == _tabIndex && mounted) {
                    setState(() => _loadProgress = p / 100.0);
                  }
                },
                shouldOverrideUrlLoading: (c, navigationAction) async {
                  final urlStr = navigationAction.request.url?.toString() ?? '';
                  if (i == 0 && urlStr.contains('.trycloudflare.com')) {
                    final m = RegExp(r'https://[a-z0-9-]+\.trycloudflare\.com', caseSensitive: false)
                        .firstMatch(urlStr);
                    if (m != null) {
                      _handleDetectedTunnel(m.group(0)!);
                      return NavigationActionPolicy.CANCEL;
                    }
                  }
                  return NavigationActionPolicy.ALLOW;
                },
                onLoadStop: (c, url) async {
                  await c.evaluateJavascript(source: _strictMobileCss);
                  if (i == 0) {
                    await c.evaluateJavascript(source: _colabFrameScannerScript);
                    if (_keepAlive) {
                      await c.evaluateJavascript(source: ColabAutopilot.keepAliveScript);
                    }
                    await _scanColabForTunnel();
                  }
                },
              );
            }),
          ),
        ),
        if (!hideChrome)
          Container(
            decoration: BoxDecoration(
              color: drawerColor,
              border: Border(top: BorderSide(color: borderColor)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  _navBtn(Icons.arrow_back_ios_new_rounded, 'Back', iconBox, borderColor, () async {
                    if (await _controllers[_tabIndex]?.canGoBack() == true) {
                      _controllers[_tabIndex]?.goBack();
                    }
                  }),
                  const SizedBox(width: 6),
                  _navBtn(Icons.arrow_forward_ios_rounded, 'Forward', iconBox, borderColor, () async {
                    if (await _controllers[_tabIndex]?.canGoForward() == true) {
                      _controllers[_tabIndex]?.goForward();
                    }
                  }),
                  const SizedBox(width: 6),
                  _navBtn(Icons.refresh_rounded, 'Reload', iconBox, borderColor, () {
                    _controllers[_tabIndex]?.reload();
                  }),
                  const SizedBox(width: 6),
                  _navBtn(Icons.fullscreen_rounded, 'Full Screen', iconBox, borderColor, () {
                    widget.onFullScreenChanged?.call(true);
                  }),
                  const Spacer(),
                  if (_tabIndex == 0) ...[
                    ElevatedButton.icon(
                      onPressed: () async {
                        await _controllers[0]?.evaluateJavascript(
                          source: ColabAutopilot.autoRunCellScript,
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success.withValues(alpha: 0.16),
                        foregroundColor: AppColors.success,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        minimumSize: Size.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(color: AppColors.success.withValues(alpha: 0.4)),
                        ),
                      ),
                      icon: const Icon(Icons.play_arrow_rounded, size: 17),
                      label: const Text('Run Cell', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.only(left: 8, right: 2),
                      decoration: BoxDecoration(
                        color: iconBox,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: borderColor),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('30s', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: mutedText)),
                          SizedBox(
                            height: 30,
                            child: Switch(
                              value: _keepAlive,
                              activeThumbColor: AppColors.primary,
                              onChanged: (v) => setState(() => _keepAlive = v),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          ],
        ),
        if (hideChrome)
          Positioned(
            right: 12,
            bottom: 16,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(6),
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 15, color: Colors.white),
                      onPressed: () async {
                        if (await _controllers[_tabIndex]?.canGoBack() == true) {
                          _controllers[_tabIndex]?.goBack();
                        }
                      },
                    ),
                    IconButton(
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(6),
                      icon: const Icon(Icons.refresh_rounded, size: 16, color: Colors.white),
                      onPressed: () => _controllers[_tabIndex]?.reload(),
                    ),
                    IconButton(
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(6),
                      icon: const Icon(Icons.fullscreen_exit_rounded, size: 18, color: AppColors.primaryLight),
                      onPressed: () => widget.onFullScreenChanged?.call(false),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _navBtn(IconData icon, String tip, Color bg, Color border, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Tooltip(
        message: tip,
        child: Container(
          width: 36,
          height: 34,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border),
          ),
          child: Icon(icon, size: 16),
        ),
      ),
    );
  }
}
