
import 'dart:async';
import 'package:flutter/material.dart';
import '../models/studio_models.dart';
import '../services/profile_manager.dart';
import '../theme/app_theme.dart';

class HomeDashboardScreen extends StatefulWidget {
  final ServerInfo? serverInfo;
  final FingerprintProfile fingerprint;
  final String detectedTunnel;
  final ValueChanged<int> onNavigateTab;
  final void Function(int seed, String osType)? onSwitchProfile;

  const HomeDashboardScreen({
    super.key,
    required this.serverInfo,
    required this.fingerprint,
    required this.detectedTunnel,
    required this.onNavigateTab,
    this.onSwitchProfile,
  });

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen> {
  List<AccountProfile> _profiles = [];
  String _activeId = 'p1';
  DateTime _now = DateTime.now();
  String _liveIp = 'Checking IP...';
  String _liveCountry = '...';
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    _loadProfiles();
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadProfiles() async {
    final (list, active) = await ProfileManager.loadProfiles();
    if (mounted) {
      setState(() {
        _profiles = list;
        _activeId = active;
      });
    }
    final (ip, country) = await ProfileManager.fetchPublicIpInfo();
    await ProfileManager.updateActiveIpInfo(ip: ip, country: country);
    final (updated, _) = await ProfileManager.loadProfiles();
    if (mounted) {
      setState(() {
        _profiles = updated;
        _liveIp = ip;
        _liveCountry = country;
      });
    }
  }

  Future<void> _switchDashboardAccount(AccountProfile target) async {
    if (target.id == _activeId) return;
    setState(() {
      _liveIp = 'Switching IP...';
      _liveCountry = 'Checking...';
    });
    await ProfileManager.snapshotCookiesFor(_activeId);
    await ProfileManager.restoreCookiesFor(target.id);
    await ProfileManager.saveProfiles(_profiles, target.id);
    widget.onSwitchProfile?.call(target.seed, target.osType);
    await _loadProfiles();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Switched to ${target.name} · $_liveIp ($_liveCountry)')),
      );
    }
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final ap = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ap';
  }

  @override
  Widget build(BuildContext context) {
    final activeProf = _profiles.where((p) => p.id == _activeId).firstOrNull;
    final isLive = widget.serverInfo != null;

    return RefreshIndicator(
      onRefresh: _loadProfiles,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        children: [
          // Hero Gradient Status Card (inspired by layout, tailored for Adobe Stock Video Studio)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primary, AppColors.primarySecondary],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.28),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'TODAY · ${activeProf?.name ?? "Account 1"}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: Colors.white70,
                      ),
                    ),
                    Row(
                      children: [
                        Icon(Icons.circle, size: 7, color: isLive ? AppColors.success : Colors.white70),
                        const SizedBox(width: 5),
                        Text(
                          isLive ? 'T4 Live' : 'Standby',
                          style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isLive ? 'GPU Studio Ready' : 'Start Colab T4',
                            style: const TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'IP: $_liveIp · $_liveCountry',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      _formatTime(_now),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _heroBtn(Icons.movie_creation_rounded, 'Studio', () => widget.onNavigateTab(1)),
                    _heroBtn(Icons.cloud_upload_rounded, 'Upload', () => widget.onNavigateTab(2)),
                    _heroBtn(Icons.vpn_lock_rounded, 'VPN / Login', () => widget.onNavigateTab(4)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Multi-Account Overview Card (2-column sparkline grid)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.account_balance_wallet_rounded, color: AppColors.primary, size: 17),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Adobe Stock Accounts',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                      ),
                      TextButton(
                        onPressed: () => widget.onNavigateTab(3),
                        child: const Text('Open Earn Adobe >', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _profiles.isEmpty ? 1 : _profiles.length,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 1.25,
                    ),
                    itemBuilder: (_, i) {
                      final prof = _profiles.isEmpty
                          ? const AccountProfile(id: 'p1', name: 'Account 1', seed: 100001)
                          : _profiles[i];
                      final isCur = prof.id == _activeId;
                      return GestureDetector(
                        onTap: () => _switchDashboardAccount(prof),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Theme.of(context).brightness == Brightness.dark
                                ? AppColors.iconBoxBg
                                : AppColors.lightIconBox,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isCur ? AppColors.primary : AppColors.border.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      prof.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: (isCur ? AppColors.success : AppColors.primary).withValues(alpha: 0.16),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      isCur ? 'ACTIVE' : 'P${i + 1}',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                        color: isCur ? AppColors.success : AppColors.primaryLight,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                prof.lastEarnings,
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.success),
                              ),
                              SizedBox(
                                height: 22,
                                width: double.infinity,
                                child: CustomPaint(painter: _MiniSparkPainter(seed: prof.seed)),
                              ),
                              Text(
                                '${prof.lastIp} · ${prof.lastCountry}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('All Accounts Total', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                      Text(
                        '\$${_profiles.fold<double>(0.0, (sum, p) => sum + (double.tryParse(p.lastEarnings.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0)).toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.success),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // System & Anti-Detect Quick Strip
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  _miniInfo(Icons.fingerprint, 'Shield', '#${widget.fingerprint.seed}', AppColors.primary),
                  _miniInfo(Icons.public_rounded, _liveCountry, _liveIp, const Color(0xFF06B6D4)),
                  _miniInfo(
                    Icons.shield_rounded,
                    'Keep-Alive',
                    'Active',
                    AppColors.success,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroBtn(IconData icon, String label, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: Colors.white),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
            ],
          ),
        ),
      );

  Widget _miniInfo(IconData icon, String label, String val, Color c) => Expanded(
        child: Column(
          children: [
            Icon(icon, size: 18, color: c),
            const SizedBox(height: 4),
            Text(val, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
          ],
        ),
      );
}

class _MiniSparkPainter extends CustomPainter {
  final int seed;
  _MiniSparkPainter({required this.seed});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (int i = 0; i <= 10; i++) {
      final x = size.width * (i / 10);
      final v = (((seed * (i + 3) * 7919) % 100) / 100.0);
      final y = size.height * (0.2 + 0.65 * (1 - v));
      if (i == 0) path.moveTo(x, y);
      else path.lineTo(x, y);
    }
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant _MiniSparkPainter old) => old.seed != seed;
}
