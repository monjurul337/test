import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../models/studio_models.dart';
import '../services/anti_detect_scripts.dart';
import '../services/colab_autopilot.dart';
import '../services/gemini_cookie_service.dart';
import '../theme/app_theme.dart';

class GeminiSettingsScreen extends StatefulWidget {
  final FingerprintProfile fingerprint;
  final ValueChanged<String>? onColabTunnelDetected;

  const GeminiSettingsScreen({super.key, required this.fingerprint, this.onColabTunnelDetected});

  @override
  State<GeminiSettingsScreen> createState() => _GeminiSettingsScreenState();
}

class _GeminiSettingsScreenState extends State<GeminiSettingsScreen> {
  bool _geminiActive = false;
  bool _checking = false;
  String _defaultCategory = 'Abstract';
  double _keywordCount = 45;
  bool _autoAiFlag = true;
  bool _autoSanitize = true;
  final _promptCtrl = TextEditingController();

  static const _categories = [
    'Abstract',
    'Technology',
    'Business',
    'Nature',
    'Science',
    '3D & Motion',
    'Graphic Resources',
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _promptCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _checking = true);
    final active = await GeminiCookieService.hasActiveSession();
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _geminiActive = active;
      _checking = false;
      _defaultCategory = prefs.getString('mh_meta_category') ?? 'Abstract';
      _keywordCount = (prefs.getInt('mh_meta_kw_count') ?? 45).toDouble();
      _autoAiFlag = prefs.getBool('mh_meta_ai_flag') ?? true;
      _autoSanitize = prefs.getBool('mh_meta_sanitize') ?? true;
      _promptCtrl.text = prefs.getString('mh_meta_custom_prompt') ?? '';
    });
  }

  Future<void> _saveMetadataDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mh_meta_category', _defaultCategory);
    await prefs.setInt('mh_meta_kw_count', _keywordCount.round());
    await prefs.setBool('mh_meta_ai_flag', _autoAiFlag);
    await prefs.setBool('mh_meta_sanitize', _autoSanitize);
    await prefs.setString('mh_meta_custom_prompt', _promptCtrl.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gemini & Metadata settings saved')),
      );
    }
  }

  Future<void> _openColabWebView() async {
    InAppWebViewController? colabCtrl;
    const scannerJs = r"""
(function() {
  if (window.__mhColabScannerInstalled) return;
  window.__mhColabScannerInstalled = true;
  const re = /https:\/\/[a-z0-9-]+\.trycloudflare\.com/ig;
  function emitTunnel(url) {
    if (!url || window.__mhLastEmittedTunnel === url) return;
    window.__mhLastEmittedTunnel = url;
    try { window.flutter_inappwebview?.callHandler('onColabTunnel', url); } catch (e) {}
    try { if (window.top && window.top !== window) window.top.postMessage({ type: 'MH_COLAB_TUNNEL', url: url }, '*'); } catch (e) {}
  }
  if (window === window.top) {
    window.addEventListener('message', function(ev) {
      if (ev?.data?.type === 'MH_COLAB_TUNNEL' && typeof ev.data.url === 'string') emitTunnel(ev.data.url);
    });
  }
  setInterval(() => {
    try {
      const links = document.querySelectorAll('a[href*="trycloudflare.com"]');
      if (links?.length) {
        const m = (links[links.length - 1].href || '').match(re);
        if (m?.length) return emitTunnel(m[m.length - 1]);
      }
      const txt = (document.body?.innerText || document.documentElement?.textContent || '');
      const m = txt.match(re);
      if (m?.length) emitTunnel(m[m.length - 1]);
    } catch (e) {}
  }, 1500);
})();
""";

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => Scaffold(
          appBar: AppBar(
            title: const Text('Google Colab T4 Session', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            actions: [
              IconButton(
                tooltip: 'Run Cell',
                icon: const Icon(Icons.play_arrow_rounded, color: AppColors.success),
                onPressed: () async {
                  await colabCtrl?.evaluateJavascript(source: ColabAutopilot.autoRunCellScript);
                },
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Done'),
              ),
            ],
          ),
          body: InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri('https://colab.research.google.com/')),
            initialSettings: InAppWebViewSettings(
              userAgent: widget.fingerprint.userAgent,
              javaScriptEnabled: true,
              domStorageEnabled: true,
              thirdPartyCookiesEnabled: true,
              supportMultipleWindows: true,
              javaScriptCanOpenWindowsAutomatically: true,
              preferredContentMode: UserPreferredContentMode.MOBILE,
              useWideViewPort: false,
              loadWithOverviewMode: true,
              initialScale: 100,
              textZoom: 100,
            ),
            initialUserScripts: UnmodifiableListView<UserScript>([
              UserScript(
                source: AntiDetectScripts.buildUserScript(widget.fingerprint),
                injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                forMainFrameOnly: false,
              ),
              UserScript(
                source: scannerJs,
                injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
                forMainFrameOnly: false,
              ),
            ]),
            onWebViewCreated: (c) {
              colabCtrl = c;
              c.addJavaScriptHandler(
                handlerName: 'onColabTunnel',
                callback: (args) {
                  if (args.isNotEmpty && args[0] is String) {
                    final u = (args[0] as String).trim();
                    if (u.startsWith('https://')) {
                      widget.onColabTunnelDetected?.call(u);
                      if (ctx.mounted) Navigator.of(ctx).pop();
                    }
                  }
                },
              );
            },
            onLoadStop: (c, url) async {
              await c.evaluateJavascript(source: ColabAutopilot.keepAliveScript);
              await c.evaluateJavascript(source: scannerJs);
            },
          ),
        ),
      ),
    );
  }

  Future<void> _openGeminiLoginWebView() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: const Text('Gemini Web Session Login', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ],
          ),
          body: InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(GeminiCookieService.geminiUrl)),
            initialSettings: InAppWebViewSettings(
              userAgent: widget.fingerprint.userAgent,
              javaScriptEnabled: true,
              domStorageEnabled: true,
              thirdPartyCookiesEnabled: true,
              supportMultipleWindows: true,
              javaScriptCanOpenWindowsAutomatically: true,
              preferredContentMode: UserPreferredContentMode.MOBILE,
              useWideViewPort: false,
              loadWithOverviewMode: true,
              initialScale: 100,
              textZoom: 100,
            ),
            initialUserScripts: UnmodifiableListView<UserScript>([
              UserScript(
                source: AntiDetectScripts.buildUserScript(widget.fingerprint),
                injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                forMainFrameOnly: false,
              ),
            ]),
          ),
        ),
      ),
    );
    await _loadSettings();
  }

  @override
  Widget build(BuildContext context) {
    final muted = AppColors.mutedOf(context);
    final isDark = themeModeNotifier.value == ThemeMode.dark;

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        // Gemini Web Session Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.auto_awesome_rounded, color: AppColors.primary, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Gemini Web Session', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                          Text(
                            _checking
                                ? 'Checking __Secure-1PSID cookie...'
                                : (_geminiActive ? 'Connected (__Secure-1PSID active)' : 'Not signed in — tap Sign In below'),
                            style: TextStyle(
                              fontSize: 11.5,
                              color: _geminiActive ? AppColors.success : muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _loadSettings,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _openGeminiLoginWebView,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.login_rounded, size: 18),
                    label: Text(_geminiActive ? 'Manage Gemini Web Session' : 'Sign in to Gemini Web'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        const SizedBox(height: 12),

        // Google Colab T4 Session Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.terminal_rounded, color: AppColors.success, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Google Colab T4 Session', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                          Text(
                            'Sign in & run notebook — auto-connects to Studio',
                            style: TextStyle(fontSize: 11.5, color: muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _openColabWebView,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.play_circle_outline_rounded, size: 18),
                    label: const Text('Sign in & Open Google Colab', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Metadata Generation Defaults Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.tune_rounded, color: AppColors.primary, size: 20),
                    SizedBox(width: 8),
                    Text('Metadata Generation Settings', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _defaultCategory,
                  dropdownColor: AppColors.cardOf(context),
                  decoration: const InputDecoration(labelText: 'Default Stock Category'),
                  items: _categories
                      .map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 13))))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _defaultCategory = v);
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Target Keywords Count', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    Text('${_keywordCount.round()} tags',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.accentTextOf(context))),
                  ],
                ),
                Slider(
                  value: _keywordCount,
                  min: 15,
                  max: 49,
                  divisions: 34,
                  activeColor: AppColors.primary,
                  onChanged: (v) => setState(() => _keywordCount = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Auto-mark AI-Generated Content', style: TextStyle(fontSize: 13)),
                  value: _autoAiFlag,
                  activeThumbColor: AppColors.primary,
                  onChanged: (v) => setState(() => _autoAiFlag = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Sanitize Trademark / Banned Words', style: TextStyle(fontSize: 13)),
                  value: _autoSanitize,
                  activeThumbColor: AppColors.primary,
                  onChanged: (v) => setState(() => _autoSanitize = v),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _promptCtrl,
                  maxLines: 3,
                  style: const TextStyle(fontSize: 12),
                  decoration: const InputDecoration(
                    labelText: 'Custom Metadata Prompt Style (optional)',
                    hintText: 'e.g. Focus on commercial 3D motion background keywords...',
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saveMetadataDefaults,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.save_rounded, size: 18),
                    label: const Text('Save Metadata Settings', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // App Theme Card
        Card(
          child: SwitchListTile(
            title: const Text('Dark Mode', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            subtitle: Text('Switch between Dark & Light studio themes', style: TextStyle(fontSize: 11.5, color: muted)),
            secondary: Icon(isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded, color: AppColors.primary),
            value: isDark,
            activeThumbColor: AppColors.primary,
            onChanged: (nextDark) async {
              themeModeNotifier.value = nextDark ? ThemeMode.dark : ThemeMode.light;
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('mh_dark_mode', nextDark);
              if (mounted) setState(() {});
            },
          ),
        ),
      ],
    );
  }
}
