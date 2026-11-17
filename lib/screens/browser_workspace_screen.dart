import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  State<BrowserWorkspaceScreen> createState() => BrowserWorkspaceScreenState();
}

class BrowserWorkspaceScreenState extends State<BrowserWorkspaceScreen> {
  Future<bool> handleBack() async {
    if (!_showProfileList) {
      final c = _controllers[_tabIndex];
      if (c != null && await c.canGoBack()) {
        await c.goBack();
        return true;
      }
      widget.onFullScreenChanged?.call(false);
      if (mounted) setState(() => _showProfileList = true);
      return true;
    }
    return false;
  }
  int _tabIndex = 0;
  bool _showProfileList = true;
  String? _foundTunnel;
  bool _keepAlive = true;
  double _loadProgress = 0.0;
  final _urlCtrl = TextEditingController();
  Timer? _tunnelPollTimer;
  final List<InAppWebViewController?> _controllers = List.filled(4, null);
  List<AccountProfile> _accounts = [];
  String _activeAccountId = 'p_adobe';
  String? _testingIpId;

  static const _tabs = [
    ('Colab', 'https://colab.research.google.com/', Icons.terminal_rounded),
    ('Adobe', 'https://contributor.stock.adobe.com', Icons.camera_rounded),
    ('Shutterstock', 'https://submit.shutterstock.com/login', Icons.collections_rounded),
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
      case 'Colab':
        return 0;
      case 'Adobe Stock':
        return 1;
      case 'Shutterstock':
        return 2;
      case 'Magnific':
        return 3;
      default:
        return _tabIndex;
    }
  }

  (IconData, Color) _platformVisual(String platform) {
    switch (platform) {
      case 'Adobe Stock':
        return (Icons.camera_rounded, AppColors.primary);
      case 'Shutterstock':
        return (Icons.collections_rounded, const Color(0xFFF59E0B));
      case 'Magnific':
        return (Icons.bolt_rounded, const Color(0xFFA855F7));
      case 'Gemini':
        return (Icons.auto_awesome_rounded, const Color(0xFF06B6D4));
      case 'Colab':
        return (Icons.terminal_rounded, AppColors.success);
      default:
        return (Icons.public_rounded, AppColors.primarySecondary);
    }
  }

  Future<void> _testAccountIp(AccountProfile acc) async {
    setState(() => _testingIpId = acc.id);
    if (acc.wgConfContent != null && acc.wgConfContent!.isNotEmpty) {
      try { await ProfileManager.connectWireGuard(acc.wgConfContent!); } catch (_) {}
    }
    final (ip, country) = await ProfileManager.testProfileIp(acc);
    final idx = _accounts.indexWhere((e) => e.id == acc.id);
    if (idx != -1) {
      final old = _accounts[idx];
      _accounts[idx] = AccountProfile(
        id: old.id,
        name: old.name,
        seed: old.seed,
        osType: old.osType,
        platform: old.platform,
        customUserAgent: old.customUserAgent,
        customWebglVendor: old.customWebglVendor,
        customWebglRenderer: old.customWebglRenderer,
        canvasMode: old.canvasMode,
        audioMode: old.audioMode,
        timezone: old.timezone,
        wgConfName: old.wgConfName,
        wgConfContent: old.wgConfContent,
        proxyUrl: old.proxyUrl,
        lastEarnings: old.lastEarnings,
        lastDownloads: old.lastDownloads,
        lastIp: ip,
        lastCountry: country,
      );
      await ProfileManager.saveProfiles(_accounts, _activeAccountId);
    }
    if (mounted) {
      setState(() => _testingIpId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${acc.name}: $ip ($country)')),
      );
    }
  }

  Future<void> _runProfileBrowser(AccountProfile acc) async {
    if (acc.id != _activeAccountId) {
      await ProfileManager.snapshotCookiesFor(_activeAccountId);
      await ProfileManager.restoreCookiesFor(acc.id);
      await ProfileManager.saveProfiles(_accounts, acc.id);
    }
    await ProfileManager.applyHttpProxy(acc.proxyUrl);
    if (acc.wgConfContent != null && acc.wgConfContent!.isNotEmpty) {
      try { await ProfileManager.connectWireGuard(acc.wgConfContent!); } catch (_) {}
    } else {
      try { await ProfileManager.disconnectWireGuard(); } catch (_) {}
    }
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
      _showProfileList = false;
      _urlCtrl.text = _tabs[targetTab].$2;
    });
    widget.onFullScreenChanged?.call(true);
    _controllers[targetTab]?.reload();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Running ${acc.name} (${acc.platform}) · Seed #${acc.seed}')),
      );
    }
  }

  Future<void> _openProfileAntiDetectEditor({AccountProfile? existing}) async {
    final isNew = existing == null;
    final nextNum = _accounts.length + 1;
    var osType = existing?.osType ?? 'Android';
    var platform = existing?.platform ?? 'Adobe Stock';
    var seed = existing?.seed ?? (Random.secure().nextInt(899999) + 100000);
    final preset = FingerprintProfile.defaultAndroid(seed, osType: osType);
    var canvasMode = existing?.canvasMode ?? 'Noise';
    var audioMode = existing?.audioMode ?? 'Noise';

    final nameCtrl = TextEditingController(text: existing?.name ?? 'Account $nextNum');
    final seedCtrl = TextEditingController(text: '$seed');
    final uaCtrl = TextEditingController(
      text: (existing?.customUserAgent?.isNotEmpty == true) ? existing!.customUserAgent! : preset.userAgent,
    );
    final vendorCtrl = TextEditingController(
      text: (existing?.customWebglVendor?.isNotEmpty == true) ? existing!.customWebglVendor! : preset.webglVendor,
    );
    final rendererCtrl = TextEditingController(
      text: (existing?.customWebglRenderer?.isNotEmpty == true) ? existing!.customWebglRenderer! : preset.webglRenderer,
    );
    final tzCtrl = TextEditingController(text: existing?.timezone ?? preset.timezone);
    final rawExistingProxy = existing?.proxyUrl?.trim() ?? '';
    var proxyType = rawExistingProxy.startsWith('socks5://')
        ? 'socks5'
        : (rawExistingProxy.isNotEmpty ? 'http' : 'direct');
    final proxyCtrl = TextEditingController(
      text: rawExistingProxy.replaceFirst(RegExp(r'^(https?|socks5?)://'), ''),
    );
    var wgName = existing?.wgConfName;
    var wgContent = existing?.wgConfContent;

    final saved = await showDialog<AccountProfile>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          void applyPreset(int newSeed, String newOs) {
            final p = FingerprintProfile.defaultAndroid(newSeed, osType: newOs);
            setDlgState(() {
              seed = newSeed;
              osType = newOs;
              seedCtrl.text = '$newSeed';
              uaCtrl.text = p.userAgent;
              vendorCtrl.text = p.webglVendor;
              rendererCtrl.text = p.webglRenderer;
            });
          }

          return AlertDialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
            titlePadding: const EdgeInsets.fromLTRB(16, 16, 12, 6),
            contentPadding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            backgroundColor: AppColors.cardOf(ctx),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: AppColors.borderOf(ctx)),
            ),
            title: Row(
              children: [
                const Icon(Icons.verified_user_rounded, color: AppColors.primary, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isNew ? 'New Account Profile' : 'Anti-Detect Settings',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    final rSeed = Random.secure().nextInt(899999) + 100000;
                    applyPreset(rSeed, osType);
                  },
                  icon: const Icon(Icons.shuffle_rounded, size: 16),
                  label: const Text('Randomize', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            content: SizedBox(
              width: MediaQuery.of(ctx).size.width - 24,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Account Profile Name'),
                    ),
                    const SizedBox(height: 10),
                    Text('Platform', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.mutedOf(ctx))),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: ['Adobe Stock', 'Shutterstock', 'Magnific', 'Colab'].map((pl) {
                        return ChoiceChip(
                          label: Text(pl, style: const TextStyle(fontSize: 11)),
                          selected: platform == pl,
                          selectedColor: AppColors.activePillOf(ctx),
                          onSelected: (_) => setDlgState(() => platform = pl),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 10),
                    Text('OS Platform', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.mutedOf(ctx))),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: ['Android', 'Windows', 'Linux', 'macOS'].map((os) {
                        return ChoiceChip(
                          label: Text(os, style: const TextStyle(fontSize: 11)),
                          selected: osType == os,
                          selectedColor: AppColors.activePillOf(ctx),
                          onSelected: (_) => applyPreset(seed, os),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: seedCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Seed'),
                            onChanged: (v) {
                              final parsed = int.tryParse(v);
                              if (parsed != null) seed = parsed;
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: tzCtrl,
                            decoration: const InputDecoration(labelText: 'Timezone'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text('Proxy Protocol', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.mutedOf(ctx))),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      children: [('direct', 'Direct'), ('http', 'HTTP'), ('socks5', 'SOCKS5')].map((pt) {
                        return ChoiceChip(
                          label: Text(pt.$2, style: const TextStyle(fontSize: 11)),
                          selected: proxyType == pt.$1,
                          selectedColor: AppColors.activePillOf(ctx),
                          onSelected: (_) => setDlgState(() => proxyType = pt.$1),
                        );
                      }).toList(),
                    ),
                    if (proxyType != 'direct') ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: proxyCtrl,
                        style: const TextStyle(fontSize: 12),
                        decoration: InputDecoration(
                          labelText: '${proxyType.toUpperCase()} Proxy',
                          hintText: 'ip:port or ip:port:user:pass or user:pass@ip:port',
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.iconBoxOf(ctx),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.borderOf(ctx)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.vpn_lock_rounded,
                            size: 18,
                            color: wgName != null ? AppColors.success : AppColors.mutedOf(ctx),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              wgName != null ? 'WireGuard: $wgName' : 'No WireGuard .conf attached',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: wgName != null ? AppColors.success : AppColors.mutedOf(ctx),
                              ),
                            ),
                          ),
                          if (wgName != null)
                            IconButton(
                              constraints: const BoxConstraints(),
                              padding: const EdgeInsets.all(4),
                              icon: const Icon(Icons.close_rounded, size: 16),
                              onPressed: () => setDlgState(() {
                                wgName = null;
                                wgContent = null;
                              }),
                            ),
                          TextButton(
                            onPressed: () async {
                              final res = await FilePicker.platform.pickFiles(type: FileType.any);
                              if (res != null && res.files.single.path != null) {
                                final f = File(res.files.single.path!);
                                final txt = await f.readAsString();
                                setDlgState(() {
                                  wgName = res.files.single.name;
                                  wgContent = txt;
                                });
                              }
                            },
                            child: const Text('Add .conf', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: uaCtrl,
                      maxLines: 2,
                      style: const TextStyle(fontSize: 12),
                      decoration: const InputDecoration(labelText: 'User-Agent'),
                    ),
                    const SizedBox(height: 10),
                    Text('Canvas Fingerprint', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.mutedOf(ctx))),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      children: ['Noise', 'Off', 'Block'].map((mode) {
                        return ChoiceChip(
                          label: Text(mode, style: const TextStyle(fontSize: 11)),
                          selected: canvasMode == mode,
                          selectedColor: AppColors.activePillOf(ctx),
                          onSelected: (_) => setDlgState(() => canvasMode = mode),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: vendorCtrl,
                      style: const TextStyle(fontSize: 12),
                      decoration: const InputDecoration(labelText: 'WebGL Vendor'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: rendererCtrl,
                      maxLines: 2,
                      style: const TextStyle(fontSize: 12),
                      decoration: const InputDecoration(labelText: 'WebGL Renderer'),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text('Audio:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.mutedOf(ctx))),
                        const SizedBox(width: 8),
                        ...['Noise', 'Off'].map((m) => Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                label: Text(m, style: const TextStyle(fontSize: 11)),
                                selected: audioMode == m,
                                selectedColor: AppColors.activePillOf(ctx),
                                onSelected: (_) => setDlgState(() => audioMode = m),
                              ),
                            )),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
              ElevatedButton.icon(
                onPressed: () {
                  final finalSeed = int.tryParse(seedCtrl.text.trim()) ?? seed;
                  final finalName = nameCtrl.text.trim().isEmpty ? 'Account $nextNum' : nameCtrl.text.trim();
                  Navigator.of(ctx).pop(
                    AccountProfile(
                      id: existing?.id ?? 'p_${DateTime.now().millisecondsSinceEpoch}',
                      name: finalName,
                      seed: finalSeed,
                      osType: osType,
                      platform: platform,
                      customUserAgent: uaCtrl.text.trim(),
                      customWebglVendor: vendorCtrl.text.trim(),
                      customWebglRenderer: rendererCtrl.text.trim(),
                      canvasMode: canvasMode,
                      audioMode: audioMode,
                      timezone: tzCtrl.text.trim().isEmpty ? 'Asia/Dhaka' : tzCtrl.text.trim(),
                      proxyUrl: ProfileManager.normalizeProxy(proxyType, proxyCtrl.text),
                      wgConfName: wgName,
                      wgConfContent: wgContent,
                      lastEarnings: existing?.lastEarnings ?? r'$0.00',
                      lastDownloads: existing?.lastDownloads ?? 0,
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                icon: const Icon(Icons.check_rounded, size: 17),
                label: Text(isNew ? 'Create Profile' : 'Save'),
              ),
            ],
          );
        },
      ),
    );

    if (saved != null) {
      final idx = _accounts.indexWhere((e) => e.id == saved.id);
      if (idx != -1) {
        _accounts[idx] = saved;
      } else {
        _accounts.add(saved);
      }
      await ProfileManager.saveProfiles(_accounts, _activeAccountId);
      setState(() {});
      if (saved.id == _activeAccountId) {
        await ProfileManager.applyHttpProxy(saved.proxyUrl);
      }
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
        useWideViewPort: false,
        loadWithOverviewMode: true,
        initialScale: 100,
        builtInZoomControls: false,
        displayZoomControls: false,
        textZoom: 100,
        layoutAlgorithm: LayoutAlgorithm.TEXT_AUTOSIZING,
      );

  static const String _strictMobileCss = r'''
(function() {
  const TARGET_VP = 'width=device-width, initial-scale=1.0, maximum-scale=2.0, user-scalable=yes';
  function enforceViewport() {
    const head = document.head || document.documentElement;
    if (!head) return;
    let meta = document.querySelector('meta[name="viewport"]');
    if (!meta) {
      meta = document.createElement('meta');
      meta.name = 'viewport';
      head.appendChild(meta);
    }
    if (meta.content !== TARGET_VP) meta.content = TARGET_VP;
    if (!document.getElementById('mh-strict-mobile')) {
      const style = document.createElement('style');
      style.id = 'mh-strict-mobile';
      style.textContent = `
        html, body {
          width: 100% !important;
          max-width: 100vw !important;
          overflow-x: hidden !important;
        }
        body > div, main, header, nav, section, article, form {
          max-width: 100vw !important;
          box-sizing: border-box !important;
        }
        img, video, svg, canvas, iframe {
          max-width: 100% !important;
        }
      `;
      head.appendChild(style);
    }
  }
  enforceViewport();
  document.addEventListener('DOMContentLoaded', enforceViewport);
  try {
    new MutationObserver(enforceViewport).observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ['content'] });
  } catch (e) {}
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
    return Column(
      children: [
        // Minimalist Custom-Tab Style Browser Bar (shown when Profile Browser is running)
        if (!_showProfileList)
          Container(
            color: drawerColor,
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
            child: SafeArea(
              bottom: false,
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Close Browser',
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(8),
                    icon: const Icon(Icons.close_rounded, size: 22),
                    onPressed: () {
                      widget.onFullScreenChanged?.call(false);
                      setState(() => _showProfileList = true);
                    },
                  ),
                  Expanded(
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: iconBox,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: borderColor),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 12),
                          Icon(Icons.search_rounded, size: 17, color: mutedText),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _urlCtrl,
                              style: TextStyle(fontSize: 13, color: AppColors.textOf(context)),
                              textInputAction: TextInputAction.go,
                              decoration: InputDecoration(
                                isDense: true,
                                filled: false,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                                hintText: 'Search or enter URL',
                                hintStyle: TextStyle(fontSize: 13, color: mutedText),
                              ),
                              onSubmitted: (val) {
                                var u = val.trim();
                                if (u.isEmpty) return;
                                if (!u.startsWith('http://') && !u.startsWith('https://')) {
                                  u = u.contains('.') ? 'https://$u' : 'https://www.google.com/search?q=${Uri.encodeComponent(u)}';
                                }
                                _controllers[_tabIndex]?.loadUrl(urlRequest: URLRequest(url: WebUri(u)));
                              },
                            ),
                          ),
                          if (_tabIndex == 0)
                            IconButton(
                              tooltip: 'Run Colab Cell',
                              constraints: const BoxConstraints(),
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              icon: const Icon(Icons.play_arrow_rounded, size: 20, color: AppColors.success),
                              onPressed: () async {
                                await _controllers[0]?.evaluateJavascript(
                                  source: ColabAutopilot.autoRunCellScript,
                                );
                              },
                            ),
                          const SizedBox(width: 4),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Reload',
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(8),
                    icon: const Icon(Icons.refresh_rounded, size: 21),
                    onPressed: () => _controllers[_tabIndex]?.reload(),
                  ),
                ],
              ),
            ),
          ),
        if (!_showProfileList && _loadProgress > 0 && _loadProgress < 1.0)
          LinearProgressIndicator(
            value: _loadProgress,
            minHeight: 2,
            backgroundColor: Colors.transparent,
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        if (!_showProfileList && _foundTunnel != null)
          InkWell(
            onTap: () {
              widget.onFullScreenChanged?.call(false);
              widget.onColabTunnelDetected(_foundTunnel!);
            },
            child: Container(
              width: double.infinity,
              color: activePill,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                    decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(8)),
                    child: const Text('Open Studio →', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                ],
              ),
            ),
          ),

        // Main Body: Always keep IndexedStack mounted (for Colab background scan)
        Expanded(
          child: IndexedStack(
            index: _showProfileList ? 0 : 1,
            children: [
              // 0: Dedicated Stock & Gemini Account Profiles List
              ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Account Profiles',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: widget.onOpenProfiles,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          minimumSize: Size.zero,
                        ),
                        icon: const Icon(Icons.vpn_lock_rounded, size: 15),
                        label: const Text('VPN / Shield', style: TextStyle(fontSize: 11.5)),
                      ),
                      const SizedBox(width: 6),
                      ElevatedButton.icon(
                        onPressed: () => _openProfileAntiDetectEditor(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          minimumSize: Size.zero,
                        ),
                        icon: const Icon(Icons.add_rounded, size: 15),
                        label: const Text('Add Profile', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ..._accounts.map((acc) {
                    final isCur = acc.id == _activeAccountId;
                    final (pIcon, pColor) = _platformVisual(acc.platform);
                    final hasProxy = acc.proxyUrl != null && acc.proxyUrl!.trim().isNotEmpty;
                    final hasWg = acc.wgConfName != null && acc.wgConfName!.isNotEmpty;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.cardOf(context),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: isCur ? AppColors.primary : borderColor,
                          width: isCur ? 1.4 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: pColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(pIcon, color: pColor, size: 21),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        acc.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: pColor.withValues(alpha: 0.14),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        acc.platform,
                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: pColor),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${acc.osType} · #${acc.seed} · ${hasWg ? 'WG' : (hasProxy ? (acc.proxyUrl!.startsWith('socks5') ? 'SOCKS5' : 'HTTP') : 'Direct')} · ${acc.lastIp} (${acc.lastCountry})',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 11, color: mutedText),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            tooltip: 'Test Proxy / VPN IP',
                            onPressed: _testingIpId == acc.id ? null : () => _testAccountIp(acc),
                            style: IconButton.styleFrom(
                              backgroundColor: iconBox,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: _testingIpId == acc.id
                                ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.public_rounded, size: 17, color: Color(0xFF06B6D4)),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            tooltip: 'Anti-Detect Settings',
                            onPressed: () => _openProfileAntiDetectEditor(existing: acc),
                            style: IconButton.styleFrom(
                              backgroundColor: iconBox,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: Icon(Icons.shield_outlined, size: 17, color: accentText),
                          ),
                          const SizedBox(width: 6),
                          ElevatedButton(
                            onPressed: () => _runProfileBrowser(acc),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.success,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              minimumSize: Size.zero,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Icon(Icons.play_arrow_rounded, size: 20),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),

              // 1: Full-Height Embedded Anti-Detect Browser
              IndexedStack(
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
                      UserScript(
                        source: _strictMobileCss,
                        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                        forMainFrameOnly: true,
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
                          handlerName: 'onColabDisconnected',
                          callback: (args) {
                            HapticFeedback.heavyImpact();
                            final reason = (args.isNotEmpty && args[0] is String)
                                ? args[0] as String
                                : 'Colab disconnected — auto-reconnecting';
                            const MethodChannel('com.mynxsoft.mhmotion/background')
                                .invokeMethod('notifyColabDisconnected', {'reason': reason})
                                .catchError((_) {});
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(reason), backgroundColor: AppColors.danger),
                              );
                            }
                          },
                        );
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
                    onUpdateVisitedHistory: (c, url, isReload) {
                      if (i == _tabIndex && url != null && mounted) {
                        _urlCtrl.text = url.toString();
                      }
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
                      if (i == _tabIndex && url != null && mounted) {
                        _urlCtrl.text = url.toString();
                      }
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
            ],
          ),
        ),
      ],
    );
  }
}
