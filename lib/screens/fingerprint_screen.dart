import 'dart:io';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../models/studio_models.dart';
import '../services/profile_manager.dart';
import '../theme/app_theme.dart';

class FingerprintScreen extends StatefulWidget {
  final FingerprintProfile profile;
  final VoidCallback onRandomize;
  final ValueChanged<int>? onProfileSeedChanged;
  final ValueChanged<String>? onOsChanged;
  final ValueChanged<FingerprintProfile>? onProfileApplied;
  final VoidCallback? onProfilesUpdated;

  const FingerprintScreen({
    super.key,
    required this.profile,
    required this.onRandomize,
    this.onProfileSeedChanged,
    this.onOsChanged,
    this.onProfileApplied,
    this.onProfilesUpdated,
  });

  @override
  State<FingerprintScreen> createState() => _FingerprintScreenState();
}

class _FingerprintScreenState extends State<FingerprintScreen> {
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
    if (!mounted) return;
    setState(() {
      _profiles = list;
      _activeId = active;
      final cur = _profiles.where((e) => e.id == _activeId).firstOrNull;
      if (cur?.wgConfName != null) {
        _wgStatus = 'Loaded: ${cur!.wgConfName}';
      }
    });
  }

  FingerprintProfile _toFingerprint(AccountProfile acc) {
    final base = FingerprintProfile.defaultAndroid(acc.seed, osType: acc.osType);
    return base.copyWith(
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
  }

  Future<void> _switchProfile(AccountProfile target) async {
    if (target.id == _activeId) return;
    await ProfileManager.snapshotCookiesFor(_activeId);
    await ProfileManager.restoreCookiesFor(target.id);
    await ProfileManager.saveProfiles(_profiles, target.id);
    await ProfileManager.applyHttpProxy(target.proxyUrl);
    if (widget.onProfileApplied != null) {
      widget.onProfileApplied!(_toFingerprint(target));
    } else {
      widget.onProfileSeedChanged?.call(target.seed);
    }
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

  Future<void> _showAddAccountDialog() async {
    final nextNum = _profiles.length + 1;
    var osType = 'Android';
    var platform = 'All';
    var seed = Random.secure().nextInt(899999) + 100000;
    var preset = FingerprintProfile.defaultAndroid(seed, osType: osType);
    var canvasMode = 'Noise';
    var audioMode = 'Noise';

    final nameCtrl = TextEditingController(text: 'Account $nextNum');
    final seedCtrl = TextEditingController(text: '$seed');
    final uaCtrl = TextEditingController(text: preset.userAgent);
    final vendorCtrl = TextEditingController(text: preset.webglVendor);
    final rendererCtrl = TextEditingController(text: preset.webglRenderer);
    final tzCtrl = TextEditingController(text: preset.timezone);
    final dlgProxyCtrl = TextEditingController();

    final created = await showDialog<AccountProfile>(
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
            backgroundColor: AppColors.cardOf(ctx),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: AppColors.borderOf(ctx)),
            ),
            title: Row(
              children: [
                const Icon(Icons.person_add_alt_1_rounded, color: AppColors.primary, size: 22),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Add Account Profile', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
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
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Account / Profile Name',
                        hintText: 'e.g. Account 2 (US)',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text('Target Platform', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.mutedOf(ctx))),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: ['All', 'Adobe Stock', 'Shutterstock', 'Magnific', 'Colab', 'Gemini'].map((pl) {
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
                            decoration: const InputDecoration(labelText: 'Fingerprint Seed'),
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
                    TextField(
                      controller: uaCtrl,
                      maxLines: 2,
                      style: const TextStyle(fontSize: 12),
                      decoration: InputDecoration(
                        labelText: 'User-Agent',
                        suffixIcon: IconButton(
                          tooltip: 'Randomize User-Agent',
                          icon: const Icon(Icons.casino_outlined, size: 18),
                          onPressed: () {
                            final rSeed = Random.secure().nextInt(899999) + 100000;
                            final rp = FingerprintProfile.defaultAndroid(rSeed, osType: osType);
                            setDlgState(() => uaCtrl.text = rp.userAgent);
                          },
                        ),
                      ),
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
                      decoration: InputDecoration(
                        labelText: 'WebGL Renderer',
                        suffixIcon: IconButton(
                          tooltip: 'Randomize WebGL',
                          icon: const Icon(Icons.casino_outlined, size: 18),
                          onPressed: () {
                            final rSeed = Random.secure().nextInt(899999) + 100000;
                            final rp = FingerprintProfile.defaultAndroid(rSeed, osType: osType);
                            setDlgState(() {
                              vendorCtrl.text = rp.webglVendor;
                              rendererCtrl.text = rp.webglRenderer;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: dlgProxyCtrl,
                      style: const TextStyle(fontSize: 12),
                      decoration: const InputDecoration(
                        labelText: 'Profile Proxy (optional)',
                        hintText: 'http://user:pass@ip:port or socks5://ip:port',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Text('AudioContext:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.mutedOf(ctx))),
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
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  final finalSeed = int.tryParse(seedCtrl.text.trim()) ?? seed;
                  final finalName = nameCtrl.text.trim().isEmpty ? 'Account $nextNum' : nameCtrl.text.trim();
                  Navigator.of(ctx).pop(
                    AccountProfile(
                      id: 'p_${DateTime.now().millisecondsSinceEpoch}',
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
                      proxyUrl: dlgProxyCtrl.text.trim().isEmpty ? null : dlgProxyCtrl.text.trim(),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.check_rounded, size: 17),
                label: const Text('Confirm & Create'),
              ),
            ],
          );
        },
      ),
    );

    if (created != null) {
      _profiles.add(created);
      await ProfileManager.saveProfiles(_profiles, _activeId);
      await _switchProfile(created);
      widget.onProfilesUpdated?.call();
    }
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
        osType: old.osType,
        customUserAgent: old.customUserAgent,
        customWebglVendor: old.customWebglVendor,
        customWebglRenderer: old.customWebglRenderer,
        canvasMode: old.canvasMode,
        audioMode: old.audioMode,
        timezone: old.timezone,
        wgConfName: name,
        wgConfContent: content,
        proxyUrl: old.proxyUrl,
        lastEarnings: old.lastEarnings,
        lastDownloads: old.lastDownloads,
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
    final muted = AppColors.mutedOf(context);
    final activePill = AppColors.activePillOf(context);

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        // Hero Anti-Detect Shield Header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primary, AppColors.primarySecondary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.25),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.verified_user_rounded, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Anti-Detect Shield Active',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Seed #${p.seed} · ${p.osType} · Canvas ${p.canvasMode}',
                      style: const TextStyle(fontSize: 11.5, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: _showAddAccountDialog,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.primary,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  minimumSize: Size.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 15),
                label: const Text('Add Account', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),
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
                    ElevatedButton.icon(
                      onPressed: _showAddAccountDialog,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: const Icon(Icons.add, size: 15),
                      label: const Text('Add Account', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
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
                      label: Text('${prof.name} (${prof.platform})', style: const TextStyle(fontSize: 12)),
                      selected: active,
                      selectedColor: activePill,
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
                Text(_wgStatus, style: TextStyle(fontSize: 12, color: _wgConnected ? AppColors.success : muted)),
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
                  subtitle: Text('Prevents real IP leak + masks ClientRects & Geo', style: TextStyle(fontSize: 11, color: muted)),
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
                      selectedColor: activePill,
                      onSelected: (_) async {
                        final idx = _profiles.indexWhere((e) => e.id == _activeId);
                        if (idx != -1) {
                          final old = _profiles[idx];
                          _profiles[idx] = AccountProfile(
                            id: old.id,
                            name: old.name,
                            seed: old.seed,
                            osType: osName,
                            canvasMode: old.canvasMode,
                            audioMode: old.audioMode,
                            timezone: old.timezone,
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
                _row('OS / Platform', '${p.osType} (${p.navPlatform})', muted),
                _row('Profile Seed', '#${p.seed}', muted),
                _row('Canvas / Audio', '${p.canvasMode} · Audio ${p.audioMode}', muted),
                _row('WebGL', '${p.webglVendor} · ${p.webglRenderer}', muted),
                _row('Hardware', '${p.hardwareConcurrency} cores · ${p.deviceMemory} GB', muted),
                _row('User-Agent', p.userAgent, muted),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),

      ],
    );
  }

  Widget _row(String k, String v, Color muted) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 100, child: Text(k, style: TextStyle(color: muted, fontSize: 12))),
            Expanded(child: Text(v, style: const TextStyle(fontSize: 12))),
          ],
        ),
      );

}
