import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../models/studio_models.dart';
import '../services/anti_detect_scripts.dart';
import '../services/gemini_cookie_service.dart';
import '../theme/app_theme.dart';

class GeminiSettingsScreen extends StatefulWidget {
  final FingerprintProfile fingerprint;

  const GeminiSettingsScreen({super.key, required this.fingerprint});

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
