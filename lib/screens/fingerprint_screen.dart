import 'dart:io';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../models/studio_models.dart';
import '../services/adobe_stock_automation.dart';
import '../services/gemini_cookie_service.dart';
import '../services/profile_manager.dart';
import '../theme/app_theme.dart';

class FingerprintScreen extends StatefulWidget {
  final FingerprintProfile profile;
  final VoidCallback onRandomize;
  final ValueChanged<int>? onProfileSeedChanged;
  final ValueChanged<String>? onOsChanged;

  const FingerprintScreen({
    super.key,
    required this.profile,
    required this.onRandomize,
    this.onProfileSeedChanged,
    this.onOsChanged,
  });

  @override
  State<FingerprintScreen> createState() => _FingerprintScreenState();
}

class _FingerprintScreenState extends State<FingerprintScreen> {
  bool _geminiActive = false;
  bool _adobeActive = false;
  List<AccountProfile> _profiles = [];
  String _activeId = 'p1';
  bool _wgConnected = false;
  String _wgStatus = 'No WireGuard .conf loaded';
  final _proxyCtrl = TextEditingController();
  bool _webrtcBlocked = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final (list, active) = await ProfileManager.loadProfiles();
    final g = await GeminiCookieService.hasActiveSession();
    final a = await AdobeStockAutomation.hasActiveSession();
    if (!mounted) return;
    setState(() {
      _profiles = list;
      _activeId = active;
      _geminiActive = g;
      _adobeActive = a;
      final cur = _profiles.where((e) => e.id == _activeId).firstOrNull;
      if (cur?.wgConfName != null) {
        _wgStatus = 'Loaded: ${cur!.wgConfName}';
      }
    });
  }

  Future<void> _switchProfile(AccountProfile target) async {
    if (target.id == _activeId) return;
    await ProfileManager.snapshotCookiesFor(_activeId);
    await ProfileManager.restoreCookiesFor(target.id);
    await ProfileManager.saveProfiles(_profiles, target.id);
    widget.onProfileSeedChanged?.call(target.seed);
    setState(() {
      _activeId = target.id;
      _wgStatus = target.wgConfName != null
          ? 'Loaded: ${target.wgConfName}'
          : 'No WireGuard .conf loaded';
    });
    await _loadAll();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Switched to ${target.name} (Cookies + Fingerprint isolated)')),
      );
    }
  }

  Future<void> _addProfile() async {
    final nextNum = _profiles.length + 1;
    final created = AccountProfile(
      id: 'p_${DateTime.now().millisecondsSinceEpoch}',
      name: 'Account $nextNum',
      seed: Random.secure().nextInt(899999) + 100000,
    );
    _profiles.add(created);
    await ProfileManager.saveProfiles(_profiles, _activeId);
    await _switchProfile(created);
  }

  Future<void> _importWireGuardConf() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.any);
    if (res == null || res.files.single.path == null) return;
    final file = File(res.files.single.path!);
    final content = await file.readAsString();
    final name = res.files.single.name;
    final idx = _profiles.indexWhere((e) => e.id == _activeId);
    if (idx != -1) {
      final old = _profiles[idx];
      _profiles[idx] = AccountProfile(
        id: old.id,
        name: old.name,
        seed: old.seed,
        wgConfName: name,
        wgConfContent: content,
      );
      await ProfileManager.saveProfiles(_profiles, _activeId);
      setState(() => _wgStatus = 'Loaded: $name');
    }
  }

  Future<void> _toggleWireGuard(bool connect) async {
    final cur = _profiles.where((e) => e.id == _activeId).firstOrNull;
    if (connect) {
      if (cur?.wgConfContent == null || cur!.wgConfContent!.isEmpty) {
        setState(() => _wgStatus = 'Please import a WireGuard .conf file first.');
        return;
      }
      try {
        await ProfileManager.connectWireGuard(cur.wgConfContent!);
        setState(() {
          _wgConnected = true;
          _wgStatus = 'VPN Active (${cur.wgConfName})';
        });
      } catch (e) {
        setState(() {
          _wgConnected = false;
          _wgStatus = 'VPN Error: $e';
        });
      }
    } else {
      await ProfileManager.disconnectWireGuard();
      setState(() {
        _wgConnected = false;
        _wgStatus = 'Disconnected (${cur?.wgConfName ?? "none"})';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        // Multiple Accounts Switcher Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.switch_account_rounded, color: AppColors.primary),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('Multi-Account Profiles', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                    TextButton.icon(
                      onPressed: _addProfile,
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: _profiles.map((prof) {
                    final active = prof.id == _activeId;
                    return ChoiceChip(
                      label: Text(prof.name, style: const TextStyle(fontSize: 12)),
                      selected: active,
                      selectedColor: AppColors.activePill,
                      onSelected: (_) => _switchProfile(prof),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),

        // WireGuard VPN (.conf) Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.vpn_lock_rounded, color: _wgConnected ? AppColors.success : AppColors.primary),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('WireGuard VPN (.conf)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                    Switch(
                      value: _wgConnected,
                      activeThumbColor: AppColors.success,
                      onChanged: _toggleWireGuard,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(_wgStatus, style: TextStyle(fontSize: 12, color: _wgConnected ? AppColors.success : AppColors.textMuted)),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _importWireGuardConf,
                  icon: const Icon(Icons.file_upload_outlined, size: 16),
                  label: const Text('Import WireGuard .conf'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),

        // GoLogin-style Proxy + WebRTC Shield Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.security_rounded, color: AppColors.success),
                    SizedBox(width: 8),
                    Text('GoLogin Proxy & Leak Shield', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _proxyCtrl,
                  decoration: const InputDecoration(
                    labelText: 'HTTP / SOCKS5 Proxy (optional)',
                    hintText: 'http://ip:port',
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          await ProfileManager.applyHttpProxy(null);
                          _proxyCtrl.clear();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Proxy cleared (Direct/VPN)')),
                            );
                          }
                        },
                        child: const Text('Clear Proxy'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          await ProfileManager.applyHttpProxy(_proxyCtrl.text);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Proxy applied: ${_proxyCtrl.text}')),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                        child: const Text('Apply Proxy'),
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Block WebRTC IP Leaks', style: TextStyle(fontSize: 13)),
                  subtitle: const Text('Prevents real IP leak + masks ClientRects & Geo', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                  value: _webrtcBlocked,
                  activeThumbColor: AppColors.success,
                  onChanged: (v) => setState(() => _webrtcBlocked = v),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Anti-Detect Fingerprint Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.fingerprint, color: AppColors.primary),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('Active Anti-Detect Fingerprint', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                    TextButton.icon(
                      onPressed: widget.onRandomize,
                      icon: const Icon(Icons.shuffle, size: 16),
                      label: const Text('New Seed'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: ['Android', 'Windows', 'Linux', 'macOS'].map((osName) {
                    final sel = p.osType == osName;
                    return ChoiceChip(
                      label: Text(osName, style: const TextStyle(fontSize: 11)),
                      selected: sel,
                      selectedColor: AppColors.activePill,
                      onSelected: (_) async {
                        final idx = _profiles.indexWhere((e) => e.id == _activeId);
                        if (idx != -1) {
                          final old = _profiles[idx];
                          _profiles[idx] = AccountProfile(
                            id: old.id,
                            name: old.name,
                            seed: old.seed,
                            osType: osName,
                            wgConfName: old.wgConfName,
                            wgConfContent: old.wgConfContent,
                            lastEarnings: old.lastEarnings,
                            lastDownloads: old.lastDownloads,
                          );
                          await ProfileManager.saveProfiles(_profiles, _activeId);
                        }
                        widget.onOsChanged?.call(osName);
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                _row('OS / Platform', '${p.osType} (${p.navPlatform})'),
                _row('Profile Seed', '#${p.seed}'),
                _row('WebGL', '${p.webglVendor} · ${p.webglRenderer}'),
                _row('Hardware', '${p.hardwareConcurrency} cores · ${p.deviceMemory} GB'),
                _row('User-Agent', p.userAgent),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Cookie Sessions Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.cookie_outlined, color: AppColors.primary),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('Active Cookie Sessions', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                    IconButton(onPressed: _loadAll, icon: const Icon(Icons.refresh)),
                  ],
                ),
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
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 100, child: Text(k, style: const TextStyle(color: AppColors.textMuted, fontSize: 12))),
            Expanded(child: Text(v, style: const TextStyle(fontSize: 12))),
          ],
        ),
      );

  Widget _sessionTile(String title, bool ok) => Row(
        children: [
          Icon(ok ? Icons.check_circle : Icons.radio_button_unchecked,
              color: ok ? AppColors.success : AppColors.textMuted, size: 18),
          const SizedBox(width: 10),
          Text(title, style: const TextStyle(fontSize: 13)),
        ],
      );
}
