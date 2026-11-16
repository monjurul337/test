import 'dart:collection';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../models/studio_models.dart';
import '../services/adobe_stock_automation.dart';
import '../services/anti_detect_scripts.dart';
import '../services/multi_marketplace_service.dart';
import '../services/profile_manager.dart';
import '../theme/app_theme.dart';

class EarnAdobeScreen extends StatefulWidget {
  final FingerprintProfile fingerprint;

  const EarnAdobeScreen({super.key, required this.fingerprint});

  @override
  State<EarnAdobeScreen> createState() => _EarnAdobeScreenState();
}

class _EarnAdobeScreenState extends State<EarnAdobeScreen> {
  // 0 = All, 1 = Adobe Stock, 2 = Shutterstock, 3 = Magnific
  int _platformIndex = 0;
  String _range = '7D';
  bool _loading = false;
  String _status = 'Tap Sync to load live earnings across all platforms.';

  final Map<String, StockDashboardStats> _statsByPlatform = {
    'Adobe Stock': const StockDashboardStats(),
    'Shutterstock': const StockDashboardStats(),
    'Magnific': const StockDashboardStats(),
  };

  final Map<String, bool> _syncedMap = {
    'Adobe Stock': false,
    'Shutterstock': false,
    'Magnific': false,
  };

  InAppWebViewController? _adobeCtrl;
  InAppWebViewController? _shutterCtrl;
  InAppWebViewController? _magnificCtrl;

  static const Color _amber = Color(0xFFF59E0B);
  static const Color _cyan = Color(0xFF06B6D4);
  static const Color _violet = Color(0xFFA855F7);

  static const _platforms = [
    ('All', Icons.public_rounded),
    ('Adobe Stock', Icons.camera_rounded),
    ('Shutterstock', Icons.collections_rounded),
    ('Magnific', Icons.bolt_rounded),
  ];

  double _parseUsd(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^0-9.]'), '');
    return double.tryParse(cleaned) ?? 0.0;
  }

  StockDashboardStats get _activeStats {
    if (_platformIndex == 1) return _statsByPlatform['Adobe Stock']!;
    if (_platformIndex == 2) return _statsByPlatform['Shutterstock']!;
    if (_platformIndex == 3) return _statsByPlatform['Magnific']!;

    // Aggregate all platforms
    var totalFiles = 0;
    var inReview = 0;
    var downloads = 0;
    var withdrawCount = 0;
    var earnSum = 0.0;
    var paidSum = 0.0;
    final sales = <StockSaleItem>[];
    final payouts = <StockPayoutItem>[];
    final chart = List<double>.filled(7, 0.0);

    for (final st in _statsByPlatform.values) {
      totalFiles += st.totalFiles;
      inReview += st.inReview;
      downloads += st.downloads;
      withdrawCount += st.withdrawCount;
      earnSum += _parseUsd(st.earnings);
      paidSum += _parseUsd(st.totalWithdrawn);
      sales.addAll(st.recentSales);
      payouts.addAll(st.payouts);
      for (var i = 0; i < 7 && i < st.chartPoints.length; i++) {
        chart[i] += st.chartPoints[i];
      }
    }

    return StockDashboardStats(
      totalFiles: totalFiles,
      inReview: inReview,
      downloads: downloads,
      earnings: '\$${earnSum.toStringAsFixed(2)}',
      withdrawCount: withdrawCount,
      totalWithdrawn: '\$${paidSum.toStringAsFixed(2)}',
      recentSales: sales,
      payouts: payouts,
      chartPoints: chart,
    );
  }

  Future<bool> _syncOne(String name, InAppWebViewController? ctrl, String script) async {
    if (ctrl == null) return false;
    try {
      final raw = await ctrl.evaluateJavascript(source: script);
      if (raw is String) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic> && decoded['ok'] == true) {
          final parsed = StockDashboardStats.fromJson(decoded);
          _statsByPlatform[name] = parsed;
          _syncedMap[name] = true;
          if (name == 'Adobe Stock') {
            ProfileManager.updateActiveStats(earnings: parsed.earnings, downloads: parsed.downloads);
          }
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _status = _platformIndex == 0
          ? 'Syncing Adobe Stock, Shutterstock & Magnific...'
          : 'Syncing ${_platforms[_platformIndex].$1}...';
    });

    try {
      int okCount = 0;
      if (_platformIndex == 0 || _platformIndex == 1) {
        if (await _syncOne('Adobe Stock', _adobeCtrl, AdobeStockAutomation.buildFetchStatsScript())) {
          okCount++;
        }
      }
      if (_platformIndex == 0 || _platformIndex == 2) {
        if (await _syncOne('Shutterstock', _shutterCtrl, MultiMarketplaceService.buildShutterstockStatsScript())) {
          okCount++;
        }
      }
      if (_platformIndex == 0 || _platformIndex == 3) {
        if (await _syncOne('Magnific', _magnificCtrl, MultiMarketplaceService.buildMagnificStatsScript())) {
          okCount++;
        }
      }

      if (!mounted) return;
      if (okCount > 0) {
        setState(() => _status = 'Synced $okCount platform(s) · Total ${_activeStats.earnings}');
      } else {
        setState(() => _status = 'Sign in on the Login tab first to sync live earnings.');
      }
    } catch (e) {
      if (mounted) setState(() => _status = 'Sync error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stats = _activeStats;
    final iconBox = AppColors.iconBoxOf(context);
    final borderColor = AppColors.borderOf(context);
    final muted = AppColors.mutedOf(context);
    final activePill = AppColors.activePillOf(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
      children: [
        // Platform Selector Pill Strip
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List.generate(_platforms.length, (i) {
              final active = _platformIndex == i;
              final item = _platforms[i];
              return GestureDetector(
                onTap: () => setState(() => _platformIndex = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                    border: Border.all(color: active ? Colors.transparent : borderColor),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(item.$2, size: 14, color: active ? Colors.white : muted),
                      const SizedBox(width: 6),
                      Text(
                        item.$1,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                          color: active ? Colors.white : muted,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 10),

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
                  style: TextStyle(fontSize: 12, color: AppColors.textOf(context)),
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
                label: Text(_platformIndex == 0 ? 'Sync All' : 'Sync',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 2x3 Colorful KPI Cards with Icons
        Row(
          children: [
            _kpi('Total Files', '${stats.totalFiles}', Icons.video_library_rounded, AppColors.success),
            const SizedBox(width: 8),
            _kpi('In Review', '${stats.inReview}', Icons.hourglass_top_rounded, _amber),
            const SizedBox(width: 8),
            _kpi('Sales / DL', '${stats.downloads}', Icons.trending_up_rounded, _cyan),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _kpi('Balance', stats.earnings, Icons.account_balance_wallet_rounded, AppColors.primary),
            const SizedBox(width: 8),
            _kpi('Withdraws', '${stats.withdrawCount}x', Icons.swap_horiz_rounded, _violet),
            const SizedBox(width: 8),
            _kpi('Total Paid', stats.totalWithdrawn, Icons.verified_rounded, AppColors.success),
          ],
        ),
        const SizedBox(height: 12),

        // Platform Breakdown Card (visible in All mode)
        if (_platformIndex == 0) ...[
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
                        child: const Icon(Icons.hub_rounded, color: AppColors.primary, size: 17),
                      ),
                      const SizedBox(width: 8),
                      const Text('Platform Breakdown', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _platformRow('Adobe Stock', 1, Icons.camera_rounded, AppColors.primary),
                  const Divider(height: 14),
                  _platformRow('Shutterstock', 2, Icons.collections_rounded, _amber),
                  const Divider(height: 14),
                  _platformRow('Magnific', 3, Icons.bolt_rounded, _violet),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Colorful Earnings & Sales Graph Card
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
                          selectedColor: activePill,
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
                    painter: _SalesChartPainter(
                      values: stats.chartPoints.isEmpty ? const [0, 0, 0, 0, 0, 0, 0] : stats.chartPoints,
                      gridColor: borderColor,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Range: $_range', style: TextStyle(fontSize: 10, color: muted)),
                    Text('Live synced data', style: TextStyle(fontSize: 10, color: muted)),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Sold Products Card
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
                    const Text('Sold Products', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 10),
                if (stats.recentSales.isEmpty)
                  Text(
                    'No sold items synced yet. Sign in on Login tab and tap Sync.',
                    style: TextStyle(fontSize: 12, color: muted),
                  )
                else
                  ...stats.recentSales.map(
                    (s) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          _thumbBox(s.thumbUrl, iconBox, muted),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                                ),
                                if (s.info.isNotEmpty)
                                  Text(
                                    s.info,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 11, color: muted),
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

        // Withdraw History Card
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
                    const Text('Withdraw History', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 10),
                if (stats.payouts.isEmpty)
                  Text(
                    'No payout records synced yet.',
                    style: TextStyle(fontSize: 12, color: muted),
                  )
                else
                  ...stats.payouts.map((p) {
                    final isPending = p.status.toLowerCase().contains('pend');
                    final badgeColor = isPending ? _amber : AppColors.success;
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor: badgeColor.withValues(alpha: 0.15),
                        child: Icon(
                          isPending ? Icons.schedule_rounded : Icons.check_rounded,
                          size: 16,
                          color: badgeColor,
                        ),
                      ),
                      title: Text(p.date, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                      subtitle: Text(p.status, style: TextStyle(fontSize: 11, color: badgeColor)),
                      trailing: Text(
                        p.amount,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.accentTextOf(context)),
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),

        // Hidden WebViews for zero-API live cookie sync across Adobe Stock, Shutterstock & Magnific
        SizedBox(
          height: 1,
          width: 1,
          child: Opacity(
            opacity: 0.01,
            child: Stack(
              children: [
                _hiddenSyncWebView(
                  'https://contributor.stock.adobe.com/en/uploads',
                  (c) => _adobeCtrl = c,
                ),
                _hiddenSyncWebView(
                  'https://submit.shutterstock.com/earnings',
                  (c) => _shutterCtrl = c,
                ),
                _hiddenSyncWebView(
                  'https://contributor.magnific.com/',
                  (c) => _magnificCtrl = c,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _hiddenSyncWebView(String url, ValueChanged<InAppWebViewController> onReady) {
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(url)),
      initialSettings: InAppWebViewSettings(
        userAgent: widget.fingerprint.userAgent,
        javaScriptEnabled: true,
        domStorageEnabled: true,
        thirdPartyCookiesEnabled: true,
      ),
      initialUserScripts: UnmodifiableListView<UserScript>([
        UserScript(
          source: AntiDetectScripts.buildUserScript(widget.fingerprint),
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          forMainFrameOnly: false,
        ),
      ]),
      onWebViewCreated: onReady,
    );
  }

  Widget _platformRow(String name, int tabTarget, IconData icon, Color accent) {
    final st = _statsByPlatform[name]!;
    final synced = _syncedMap[name] == true;
    final muted = AppColors.mutedOf(context);
    return InkWell(
      onTap: () => setState(() => _platformIndex = tabTarget),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 17, color: accent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  Text(
                    synced ? '${st.downloads} sales · ${st.totalFiles} files' : 'Tap Sync All to fetch',
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  st.earnings,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.success),
                ),
                Text(
                  synced ? 'Live' : 'Offline',
                  style: TextStyle(fontSize: 10, color: synced ? AppColors.success : muted),
                ),
              ],
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, size: 18, color: muted),
          ],
        ),
      ),
    );
  }

  Widget _thumbBox(String url, Color bg, Color muted) {
    if (url.isEmpty) {
      return Container(
        width: 44,
        height: 36,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.movie_outlined, size: 18, color: muted),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        width: 44,
        height: 36,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: 44,
          height: 36,
          color: bg,
          child: Icon(Icons.movie_outlined, size: 18, color: muted),
        ),
      ),
    );
  }

  Widget _kpi(String label, String val, IconData icon, Color accent) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: AppColors.cardOf(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(label, style: TextStyle(fontSize: 10, color: AppColors.mutedOf(context))),
                  Icon(icon, size: 14, color: accent),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                val,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: accent),
              ),
            ],
          ),
        ),
      );
}

class _SalesChartPainter extends CustomPainter {
  final List<double> values;
  final Color gridColor;
  _SalesChartPainter({required this.values, required this.gridColor});

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (int i = 1; i <= 3; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final pts = values.length < 2 ? [0.0, ...values] : values;
    final maxV = pts.reduce((a, b) => a > b ? a : b);
    final normMax = maxV <= 0 ? 1.0 : maxV * 1.15;

    final path = Path();
    final fillPath = Path();
    final offsets = <Offset>[];

    for (int i = 0; i < pts.length; i++) {
      final x = (i / (pts.length - 1)) * size.width;
      final y = size.height - ((pts[i] / normMax) * (size.height - 16)) - 8;
      offsets.add(Offset(x, y));
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        final prev = offsets[i - 1];
        final cx = (prev.dx + x) / 2;
        path.cubicTo(cx, prev.dy, cx, y, x, y);
        fillPath.cubicTo(cx, prev.dy, cx, y, x, y);
      }
    }
    fillPath.lineTo(size.width, size.height);
    fillPath.close();

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

    final linePaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF06B6D4), AppColors.primary, AppColors.success],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, linePaint);

    final dotPaint = Paint()..color = AppColors.success;
    for (final o in offsets) {
      canvas.drawCircle(o, 3.2, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SalesChartPainter oldDelegate) => true;
}
