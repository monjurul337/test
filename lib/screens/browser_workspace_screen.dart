import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../models/studio_models.dart';
import '../services/anti_detect_scripts.dart';
import '../services/colab_autopilot.dart';
import '../theme/app_theme.dart';
import 'fingerprint_screen.dart';

class BrowserWorkspaceScreen extends StatefulWidget {
  final FingerprintProfile fingerprint;
  final ValueChanged<String> onColabTunnelDetected;
  final VoidCallback onRandomizeFingerprint;
  final ValueChanged<int>? onProfileSeedChanged;
  final ValueChanged<String>? onOsChanged;

  const BrowserWorkspaceScreen({
    super.key,
    required this.fingerprint,
    required this.onColabTunnelDetected,
    required this.onRandomizeFingerprint,
    this.onProfileSeedChanged,
    this.onOsChanged,
  });

  @override
  State<BrowserWorkspaceScreen> createState() => _BrowserWorkspaceScreenState();
}

class _BrowserWorkspaceScreenState extends State<BrowserWorkspaceScreen> {
  int _tabIndex = 0;
  String? _foundTunnel;
  bool _keepAlive = true;
  Timer? _tunnelPollTimer;
  final List<InAppWebViewController?> _controllers = [null, null, null];


  @override
  void initState() {
    super.initState();
    _tunnelPollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _scanColabForTunnel());
  }

  @override
  void dispose() {
    _tunnelPollTimer?.cancel();
    super.dispose();
  }

  Future<void> _scanColabForTunnel() async {
    final c = _controllers[0];
    if (c == null) return;
    try {
      final res = await c.evaluateJavascript(source: '''
(function() {
  const re = /https:\/\/[a-z0-9-]+\.trycloudflare\.com/i;
  let m = (document.body ? document.body.innerText : '').match(re);
  if (m) return m[0];
  const links = document.querySelectorAll('a[href*="trycloudflare.com"]');
  if (links.length) {
    m = links[links.length - 1].href.match(re);
    if (m) return m[0];
  }
  for (const fr of document.querySelectorAll('iframe')) {
    try {
      const t = fr.contentDocument && fr.contentDocument.body ? fr.contentDocument.body.innerText : '';
      m = t.match(re);
      if (m) return m[0];
    } catch (e) {}
  }
  return '';
})();
''');
      if (res is String && res.startsWith('https://') && res != _foundTunnel) {
        if (mounted) setState(() => _foundTunnel = res);
        widget.onColabTunnelDetected(res);
      }
    } catch (_) {}
  }

  static const _tabs = [
    ('Colab', 'https://colab.research.google.com/'),
    ('Gemini', 'https://gemini.google.com/app'),
    ('Adobe Stock', 'https://contributor.stock.adobe.com/en/uploads'),
    ('Shield', ''),
  ];

  // Strictly mobile viewport & mobile Chrome UA (never desktop-sized)
  InAppWebViewSettings get _settings => InAppWebViewSettings(
        userAgent: widget.fingerprint.userAgent,
        javaScriptEnabled: true,
        domStorageEnabled: true,
        databaseEnabled: true,
        thirdPartyCookiesEnabled: true,
        allowsInlineMediaPlayback: true,
        useHybridComposition: true,
        supportMultipleWindows: false,
        preferredContentMode: UserPreferredContentMode.MOBILE,
        useWideViewPort: true,
        loadWithOverviewMode: false,
        builtInZoomControls: false,
        displayZoomControls: false,
        textZoom: 100,
        layoutAlgorithm: LayoutAlgorithm.TEXT_AUTOSIZING,
      );

  static const String _strictMobileCss = '''
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
    style.textContent = `
      html, body {
        max-width: 100% !important;
        overflow-x: auto !important;
      }
    `;
    document.head.appendChild(style);
  }
})();
''';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: AppColors.drawerBg,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: List.generate(_tabs.length, (i) {
              if (i == 3) {
                return FingerprintScreen(
                  profile: widget.fingerprint,
                  onRandomize: widget.onRandomizeFingerprint,
                  onOsChanged: (osName) {
                    widget.onOsChanged?.call(osName);
                    for (final c in _controllers) { c?.reload(); }
                  },
                  onProfileSeedChanged: (seed) {
                    widget.onProfileSeedChanged?.call(seed);
                    for (final c in _controllers) { c?.reload(); }
                  },
                );
              }
              final active = _tabIndex == i;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _tabIndex = i),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
                    decoration: BoxDecoration(
                      color: active ? AppColors.activePill : AppColors.iconBoxBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: active ? AppColors.primary : AppColors.border,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        _tabs[i].$1,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: active ? AppColors.primaryLight : AppColors.textMuted,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        if (_foundTunnel != null)
          Container(
            width: double.infinity,
            color: AppColors.activePill,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                const Icon(Icons.link, size: 16, color: AppColors.primaryLight),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Colab Live: $_foundTunnel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.primaryLight),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: IndexedStack(
            index: _tabIndex,
            children: List.generate(_tabs.length, (i) {
              if (i == 3) {
                return FingerprintScreen(
                  profile: widget.fingerprint,
                  onRandomize: widget.onRandomizeFingerprint,
                  onOsChanged: (osName) {
                    widget.onOsChanged?.call(osName);
                    for (final c in _controllers) { c?.reload(); }
                  },
                  onProfileSeedChanged: (seed) {
                    widget.onProfileSeedChanged?.call(seed);
                    for (final c in _controllers) { c?.reload(); }
                  },
                );
              }
              return InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri(_tabs[i].$2)),
                initialSettings: _settings,
                initialUserScripts: UnmodifiableListView<UserScript>([UserScript(
                    source: AntiDetectScripts.buildUserScript(widget.fingerprint),
                    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                  ),]),
                onWebViewCreated: (c) => _controllers[i] = c,
                onLoadStop: (c, url) async {
                  await c.evaluateJavascript(source: _strictMobileCss);
                  if (i == 0 && _keepAlive) {
                    await c.evaluateJavascript(source: ColabAutopilot.keepAliveScript);
                  }
                  if (i == 0) {
                    final txt = await c.evaluateJavascript(
                      source: 'document.body ? document.body.innerText : ""',
                    );
                    if (txt is String) {
                      final m = RegExp(r'https://[a-z0-9-]+\.trycloudflare\.com').firstMatch(txt);
                      if (m != null) {
                        final found = m.group(0)!;
                        if (mounted) setState(() => _foundTunnel = found);
                        widget.onColabTunnelDetected(found);
                      }
                    }
                  }
                },
              );
            }),
          ),
        ),
        Container(
          color: AppColors.drawerBg,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: SafeArea(
            top: false,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                  onPressed: () async {
                    if (await _controllers[_tabIndex]?.canGoBack() == true) {
                      _controllers[_tabIndex]?.goBack();
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_forward_ios, size: 18),
                  onPressed: () async {
                    if (await _controllers[_tabIndex]?.canGoForward() == true) {
                      _controllers[_tabIndex]?.goForward();
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: () => _controllers[_tabIndex]?.reload(),
                ),
                if (_tabIndex == 0)
                  TextButton.icon(
                    onPressed: () async {
                      await _controllers[0]?.evaluateJavascript(
                        source: ColabAutopilot.autoRunCellScript,
                      );
                    },
                    icon: const Icon(Icons.play_arrow_rounded, size: 18, color: AppColors.success),
                    label: const Text('Run Cell', style: TextStyle(fontSize: 12, color: AppColors.success)),
                  ),
                if (_tabIndex == 0)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('30s', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                      Switch(
                        value: _keepAlive,
                        activeColor: AppColors.primary,
                        onChanged: (v) => setState(() => _keepAlive = v),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
