import 'dart:collection';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../models/studio_models.dart';
import '../services/adobe_stock_automation.dart';
import '../services/anti_detect_scripts.dart';
import '../services/profile_manager.dart';
import '../theme/app_theme.dart';

class EarnAdobeScreen extends StatefulWidget {
  final FingerprintProfile fingerprint;

  const EarnAdobeScreen({super.key, required this.fingerprint});

  @override
  State<EarnAdobeScreen> createState() => _EarnAdobeScreenState();
}

class _EarnAdobeScreenState extends State<EarnAdobeScreen> {
  StockDashboardStats _stats = const StockDashboardStats();
  bool _loading = false;
  String _range = '7D';
  String _status = 'Tap Sync to load live Adobe Stock earnings & sold products.';
  InAppWebViewController? _adobeCtrl;

  static const Color _amber = Color(0xFFF59E0B);
  static const Color _cyan = Color(0xFF06B6D4);
  static const Color _violet = Color(0xFFA855F7);

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _status = 'Syncing portfolio, sales graph & payouts...';
    });
    try {
      final raw = await _adobeCtrl?.evaluateJavascript(
        source: AdobeStockAutomation.buildFetchStatsScript(),
      );
      if (raw is String) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic> && decoded['ok'] == true) {
          setState(() {
            _stats = StockDashboardStats.fromJson(decoded);
            ProfileManager.updateActiveStats(earnings: _stats.earnings, downloads: _stats.downloads);
            _status = 'Synced (${_stats.recentSales.length} sales, ${_stats.withdrawCount} payouts)';
          });
        } else {
          setState(() => _status = 'Sign in on Login -> Adobe Stock first.');
        }
      }
    } catch (e) {
      setState(() => _status = 'Sync error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
      children: [
        // Top Gradient Summary Banner + Sync Button
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.primary.withValues(alpha: 0.22),
                _violet.withValues(alpha: 0.16),
              ],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              const Icon(Icons.auto_graph_rounded, color: _cyan, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _status,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _loading ? null : _refresh,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: _loading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.sync_rounded, size: 16),
                label: const Text('Sync', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 2x3 Colorful KPI Cards with Icons
        Row(
          children: [
            _kpi('Total Files', '${_stats.totalFiles}', Icons.video_library_rounded, AppColors.success),
            const SizedBox(width: 8),
            _kpi('In Review', '${_stats.inReview}', Icons.hourglass_top_rounded, _amber),
            const SizedBox(width: 8),
            _kpi('Sales / DL', '${_stats.downloads}', Icons.trending_up_rounded, _cyan),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _kpi('Balance', _stats.earnings, Icons.account_balance_wallet_rounded, AppColors.primary),
            const SizedBox(width: 8),
            _kpi('Withdraws', '${_stats.withdrawCount}x', Icons.swap_horiz_rounded, _violet),
            const SizedBox(width: 8),
            _kpi('Total Paid', _stats.totalWithdrawn, Icons.verified_rounded, AppColors.success),
          ],
        ),
        const SizedBox(height: 12),

        // Adobe Stock-Style Colorful Earnings Graph Card
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
                        color: _cyan.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.show_chart_rounded, color: _cyan, size: 18),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Earnings & Sales Graph',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                    ),
                    for (final r in ['7D', '30D', 'All'])
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: ChoiceChip(
                          label: Text(r, style: const TextStyle(fontSize: 11)),
                          selected: _range == r,
                          selectedColor: AppColors.activePill,
                          onSelected: (_) => setState(() => _range = r),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 155,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _AdobeGraphPainter(
                      points: _stats.chartPoints.isEmpty
                          ? const [0, 0, 0, 0, 0, 0, 0]
                          : _stats.chartPoints,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Sold Products Card with Colorful Header Icon & Badges
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
                        color: AppColors.success.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.sell_rounded, color: AppColors.success, size: 17),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Sold Products (${_stats.recentSales.length})',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_stats.recentSales.isEmpty)
                  const Text(
                    'No recent sales synced yet. Tap Sync after logging into Adobe Stock.',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  )
                else
                  ..._stats.recentSales.map(
                    (s) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: s.thumbUrl.isNotEmpty
                                ? Image.network(
                                    s.thumbUrl,
                                    width: 56,
                                    height: 38,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => _thumbFallback(),
                                  )
                                : _thumbFallback(),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                                if (s.info.isNotEmpty)
                                  Text(
                                    s.info,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                                  ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '+${s.amount}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: AppColors.success,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Withdrawal History Card with Colorful Header Icon
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
                        color: _violet.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.payments_rounded, color: _violet, size: 17),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Withdraw History (${_stats.payouts.length})',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_stats.payouts.isEmpty)
                  const Text(
                    'No payout records synced yet.',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  )
                else
                  ..._stats.payouts.map(
                    (p) {
                      final isPending = p.status.toLowerCase().contains('pending');
                      final badgeColor = isPending ? _amber : AppColors.success;
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: badgeColor.withValues(alpha: 0.15),
                          child: Icon(
                            isPending ? Icons.schedule_rounded : Icons.check_circle_rounded,
                            color: badgeColor,
                            size: 17,
                          ),
                        ),
                        title: Text(p.date, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        subtitle: Text(p.status, style: TextStyle(fontSize: 11, color: badgeColor)),
                        trailing: Text(
                          p.amount,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.primaryLight),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),

        // Hidden Adobe Stock Cookie WebView bridge
        SizedBox(
          height: 1,
          child: Opacity(
            opacity: 0.01,
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(AdobeStockAutomation.uploadUrl)),
              initialSettings: InAppWebViewSettings(
                userAgent: widget.fingerprint.userAgent,
                thirdPartyCookiesEnabled: true,
                domStorageEnabled: true,
              ),
              initialUserScripts: UnmodifiableListView<UserScript>([
                UserScript(
                  source: AntiDetectScripts.buildUserScript(widget.fingerprint),
                  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                ),
              ]),
              onWebViewCreated: (c) => _adobeCtrl = c,
            ),
          ),
        ),
      ],
    );
  }

  Widget _thumbFallback() => Container(
        width: 56,
        height: 38,
        color: AppColors.iconBoxBg,
        child: const Icon(Icons.movie_outlined, size: 18, color: AppColors.textMuted),
      );

  Widget _kpi(String label, String val, IconData icon, Color color) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: AppColors.cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.28)),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(height: 6),
              Text(val, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color)),
              const SizedBox(height: 2),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
            ],
          ),
        ),
      );
}

class _AdobeGraphPainter extends CustomPainter {
  final List<double> points;
  _AdobeGraphPainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    for (int i = 1; i <= 3; i++) {
      final y = size.height * (i / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final maxVal = points.fold<double>(1.0, (m, v) => v > m ? v : m);
    final coords = <Offset>[];
    final n = points.length;
    for (int i = 0; i < n; i++) {
      final x = n == 1 ? size.width / 2 : size.width * (i / (n - 1));
      final y = size.height - 14 - ((points[i] / maxVal) * (size.height - 28));
      coords.add(Offset(x, y));
    }

    final linePath = Path()..moveTo(coords.first.dx, coords.first.dy);
    for (int i = 1; i < coords.length; i++) {
      final prev = coords[i - 1];
      final cur = coords[i];
      final cx = (prev.dx + cur.dx) / 2;
      linePath.cubicTo(cx, prev.dy, cx, cur.dy, cur.dx, cur.dy);
    }

    final fillPath = Path.from(linePath)
      ..lineTo(coords.last.dx, size.height)
      ..lineTo(coords.first.dx, size.height)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF06B6D4).withValues(alpha: 0.35),
          const Color(0xFFA855F7).withValues(alpha: 0.12),
          AppColors.primary.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, fillPaint);

    final strokePaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF06B6D4), AppColors.primary, AppColors.success],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..strokeWidth = 2.8
      ..style = PaintingStyle.stroke;
    canvas.drawPath(linePath, strokePaint);

    final dotPaint = Paint()..color = AppColors.success;
    for (final c in coords) {
      canvas.drawCircle(c, 4.0, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _AdobeGraphPainter old) => old.points != points;
}
