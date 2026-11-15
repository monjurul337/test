import 'package:flutter/material.dart';
import '../models/studio_models.dart';
import '../services/adobe_stock_automation.dart';
import '../services/gemini_cookie_service.dart';
import '../theme/app_theme.dart';

class FingerprintScreen extends StatefulWidget {
  final FingerprintProfile profile;
  final VoidCallback onRandomize;

  const FingerprintScreen({
    super.key,
    required this.profile,
    required this.onRandomize,
  });

  @override
  State<FingerprintScreen> createState() => _FingerprintScreenState();
}

class _FingerprintScreenState extends State<FingerprintScreen> {
  bool _geminiActive = false;
  bool _adobeActive = false;

  @override
  void initState() {
    super.initState();
    _checkSessions();
  }

  Future<void> _checkSessions() async {
    final g = await GeminiCookieService.hasActiveSession();
    final a = await AdobeStockAutomation.hasActiveSession();
    if (mounted) {
      setState(() {
        _geminiActive = g;
        _adobeActive = a;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.fingerprint, color: AppColors.primary),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Active Anti-Detect Fingerprint',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: widget.onRandomize,
                      icon: const Icon(Icons.shuffle, size: 18),
                      label: const Text('New Seed'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _row('Profile Seed', '#${p.seed}'),
                _row('WebGL Vendor', p.webglVendor),
                _row('WebGL Renderer', p.webglRenderer),
                _row('CPU / RAM', '${p.hardwareConcurrency} cores · ${p.deviceMemory} GB'),
                _row('Timezone', p.timezone),
                _row('User-Agent', p.userAgent),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.cookie_outlined, color: AppColors.primary),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Persistent Cookie Sessions',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(onPressed: _checkSessions, icon: const Icon(Icons.refresh)),
                  ],
                ),
                const SizedBox(height: 8),
                _sessionTile('Gemini Web (__Secure-1PSID)', _geminiActive),
                const SizedBox(height: 6),
                _sessionTile('Adobe Stock Contributor', _adobeActive),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: Text(k, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ),
            Expanded(child: Text(v, style: const TextStyle(fontSize: 12))),
          ],
        ),
      );

  Widget _sessionTile(String title, bool ok) => Row(
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.radio_button_unchecked,
            color: ok ? AppColors.success : AppColors.textMuted,
            size: 18,
          ),
          const SizedBox(width: 10),
          Text(title, style: const TextStyle(fontSize: 13)),
        ],
      );
}
