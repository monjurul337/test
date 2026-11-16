import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import '../models/studio_models.dart';
import '../services/adobe_stock_automation.dart';
import '../services/anti_detect_scripts.dart';
import '../services/gemini_cookie_service.dart';
import '../services/multi_marketplace_service.dart';
import '../services/stock_preflight_validator.dart';
import '../theme/app_theme.dart';

class UploadPanelScreen extends StatefulWidget {
  final FingerprintProfile fingerprint;
  final File? queuedVideo;
  final String queuedSceneName;
  final String queuedShaderCode;
  final List<(File, String)> queuedBatch;

  const UploadPanelScreen({
    super.key,
    required this.fingerprint,
    this.queuedVideo,
    this.queuedSceneName = '',
    this.queuedShaderCode = '',
    this.queuedBatch = const [],
  });

  @override
  State<UploadPanelScreen> createState() => _UploadPanelScreenState();
}

class _UploadPanelScreenState extends State<UploadPanelScreen> {
  final List<StockQueueItem> _queue = [];
  int _selectedIdx = -1;

  VideoPlayerController? _playerCtrl;
  final _titleCtrl = TextEditingController();
  final _newTagCtrl = TextEditingController();
  String _category = 'Abstract';
  List<String> _tags = [];
  bool _isAiGenerated = true;
  bool _noPropertyRelease = true;
  bool _generating = false;
  bool _submitting = false;
  bool _showStockWebView = false;
  final Set<StockMarketplace> _selectedMarkets = {StockMarketplace.adobeStock};
  final Map<StockMarketplace, InAppWebViewController?> _marketCtrls = {};
  String _status = 'Add rendered MP4s or pick videos from your phone to start.';
  StockDashboardStats _stats = const StockDashboardStats();
  bool _loadingStats = false;

  InAppWebViewController? _geminiCtrl;
  InAppWebViewController? _adobeCtrl;

  static const _categories = [
    'Abstract',
    'Backgrounds',
    'Technology',
    'Science',
    'Graphic Resources',
    'Nature',
    'Business',
  ];

  StockQueueItem? get _activeItem =>
      (_selectedIdx >= 0 && _selectedIdx < _queue.length) ? _queue[_selectedIdx] : null;

  @override
  void initState() {
    super.initState();
    if (widget.queuedVideo != null) {
      _enqueueFile(widget.queuedVideo!, widget.queuedSceneName, widget.queuedShaderCode);
    }
  }

  @override
  void didUpdateWidget(covariant UploadPanelScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.queuedBatch.isNotEmpty && widget.queuedBatch != oldWidget.queuedBatch) {
      for (final item in widget.queuedBatch) {
        if (!_queue.any((q) => q.file.path == item.$1.path)) {
          _enqueueFile(item.$1, item.$2, '');
        }
      }
    } else if (widget.queuedVideo != null &&
        widget.queuedVideo!.path != oldWidget.queuedVideo?.path) {
      _enqueueFile(widget.queuedVideo!, widget.queuedSceneName, widget.queuedShaderCode);
    }
  }

  @override
  void dispose() {
    _playerCtrl?.dispose();
    super.dispose();
  }


  Future<void> _refreshStockStats() async {
    setState(() => _loadingStats = true);
    try {
      final raw = await _adobeCtrl?.evaluateJavascript(
        source: AdobeStockAutomation.buildFetchStatsScript(),
      );
      if (raw is String) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic> && decoded['ok'] == true) {
          setState(() => _stats = StockDashboardStats.fromJson(decoded));
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingStats = false);
  }

  Future<void> _enqueueFile(File f, String scene, String code) async {
    final item = StockQueueItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      file: f,
      sceneName: scene.isEmpty ? f.path.split('/').last.replaceAll('.mp4', '') : scene,
      shaderCode: code,
    );
    setState(() {
      _queue.add(item);
      _selectedIdx = _queue.length - 1;
      _status = 'Added ${item.sceneName} to Batch Queue (${_queue.length} total).';
    });
    await _initPlayerFor(item);
  }

  Future<void> _initPlayerFor(StockQueueItem item) async {
    await _playerCtrl?.dispose();
    final ctrl = VideoPlayerController.file(item.file);
    await ctrl.initialize();
    await ctrl.setLooping(true);
    await ctrl.play();
    if (!mounted) return;
    setState(() {
      _playerCtrl = ctrl;
      if (item.metadata != null) {
        _titleCtrl.text = item.metadata!.title;
        _category = _categories.contains(item.metadata!.category)
            ? item.metadata!.category
            : 'Abstract';
        _tags = List.from(item.metadata!.keywords);
      } else {
        _titleCtrl.clear();
        _tags = [];
      }
    });
  }

  Future<void> _pickMultipleVideos() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: true,
    );
    if (res == null) return;
    for (final pf in res.files) {
      if (pf.path != null) {
        await _enqueueFile(File(pf.path!), '', '');
      }
    }
  }

  Future<void> _generateMetaForItem(StockQueueItem item) async {
    final hasSession = await GeminiCookieService.hasActiveSession();
    if (!hasSession) {
      setState(() => _status = 'Sign in on Browser -> Gemini tab first.');
      return;
    }
    final thumb = await VideoThumbnail.thumbnailData(
      video: item.file.path,
      imageFormat: ImageFormat.JPEG,
      maxWidth: 720,
      quality: 85,
    );
    if (thumb == null) return;

    final b64 = base64Encode(thumb);
    final prompt = GeminiCookieService.buildAdobeStockPrompt(
      item.sceneName,
      item.shaderCode.split('\n').take(6).join(' '),
    );
    await _geminiCtrl?.evaluateJavascript(
      source: GeminiCookieService.buildDomInjectionScript(prompt, b64),
    );

    for (int i = 0; i < 20; i++) {
      await Future.delayed(const Duration(seconds: 2));
      final txt = await _geminiCtrl?.evaluateJavascript(
        source: 'document.body ? document.body.innerText : ""',
      );
      if (txt is String) {
        final parsed = GeminiCookieService.parseJsonFromText(txt);
        if (parsed != null && parsed.title.isNotEmpty) {
          final cleanTags = StockPreflightValidator.sanitizeKeywords(parsed.keywords);
          item.metadata = AdobeMetadata(
            title: parsed.title,
            category: parsed.category,
            keywords: cleanTags,
            isAiGenerated: _isAiGenerated,
          );
          item.status = 'meta_ready';
          if (_activeItem?.id == item.id && mounted) {
            setState(() {
              _titleCtrl.text = item.metadata!.title;
              _category = _categories.contains(item.metadata!.category)
                  ? item.metadata!.category
                  : 'Abstract';
              _tags = List.from(cleanTags);
            });
          }
          return;
        }
      }
    }
  }

  Future<void> _generateAllQueueMeta() async {
    if (_queue.isEmpty) return;
    setState(() {
      _generating = true;
      _status = 'Generating Gemini metadata for ${_queue.length} queued videos...';
    });
    for (int i = 0; i < _queue.length; i++) {
      if (_queue[i].metadata == null) {
        setState(() => _status = 'Gemini Meta (${i + 1}/${_queue.length}): ${_queue[i].sceneName}');
        await _generateMetaForItem(_queue[i]);
      }
    }
    if (mounted) {
      setState(() {
        _generating = false;
        _status = 'Batch metadata generation complete!';
      });
    }
  }

  Future<void> _submitBatchToAdobeStock() async {
    if (_activeItem == null) return;
    // Save edits to active item
    _activeItem!.metadata = AdobeMetadata(
      title: _titleCtrl.text.trim(),
      category: _category,
      keywords: StockPreflightValidator.sanitizeKeywords(_tags),
      isAiGenerated: _isAiGenerated,
    );

    setState(() {
      _submitting = true;
      _showStockWebView = true;
      _status = 'Uploading & submitting to Adobe Stock Review...';
    });

    for (final item in _queue) {
      if (item.metadata == null) continue;
      item.status = 'uploading';
      setState(() => _status = 'Submitting ${item.sceneName}...');
      // Inject MP4 file into Adobe Stock file input + fill metadata + submit
      final bytes = await item.file.readAsBytes();
      final b64Video = base64Encode(bytes);
      final fileName = item.file.path.split('/').last;
      await _adobeCtrl?.evaluateJavascript(source: '''
(async function() {
  try {
    const res = await fetch("data:video/mp4;base64,$b64Video");
    const blob = await res.blob();
    const file = new File([blob], "$fileName", { type: "video/mp4" });
    const dt = new DataTransfer();
    dt.items.add(file);
    const input = document.querySelector('input[type="file"]');
    if (input) {
      input.files = dt.files;
      input.dispatchEvent(new Event('change', { bubbles: true }));
    }
  } catch (e) {}
})();
''');
      await Future.delayed(const Duration(seconds: 2));
      await _adobeCtrl?.evaluateJavascript(
        source: AdobeStockAutomation.buildFillAndSubmitScript(item.metadata!, autoSubmit: true),
      );
      for (final m in _selectedMarkets) {
        if (m == StockMarketplace.adobeStock) continue;
        final ctrl = _marketCtrls[m];
        if (ctrl != null) {
          await ctrl.evaluateJavascript(
            source: MultiMarketplaceService.buildUploadAndFillScript(
              m, item.metadata!, b64Video, fileName, autoSubmit: true,
            ),
          );
        }
      }
      item.status = 'submitted';
    }

    if (mounted) {
      setState(() {
        _submitting = false;
        _status = 'Batch submission finished! Check Adobe Stock Pending Review.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final preflight = StockPreflightValidator.validate(
      duration: _playerCtrl?.value.isInitialized == true ? _playerCtrl!.value.duration : null,
      resolution: _playerCtrl?.value.isInitialized == true ? _playerCtrl!.value.size : null,
      title: _titleCtrl.text,
      keywords: _tags,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
      children: [
        // Zero-API Adobe Stock Mini Dashboard
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.insights_rounded, size: 17, color: AppColors.primary),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Adobe Stock Live Stats (No API Key)',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                    ),
                    IconButton(
                      constraints: const BoxConstraints(),
                      padding: EdgeInsets.zero,
                      icon: _loadingStats
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh, size: 18),
                      onPressed: _loadingStats ? null : _refreshStockStats,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _statPill('Total Files', '${_stats.totalFiles}', AppColors.success),
                    const SizedBox(width: 6),
                    _statPill('In Review', '${_stats.inReview}', AppColors.accentTextOf(context)),
                    const SizedBox(width: 6),
                    _statPill('Sales/DL', '${_stats.downloads}', AppColors.primary),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _statPill('Balance', _stats.earnings, AppColors.success),
                    const SizedBox(width: 6),
                    _statPill('Withdraws', '${_stats.withdrawCount}x', AppColors.accentTextOf(context)),
                    const SizedBox(width: 6),
                    _statPill('Total Paid', _stats.totalWithdrawn, AppColors.success),
                  ],
                ),
                if (_stats.recentSales.isNotEmpty || _stats.payouts.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(
                      'Sales (${_stats.recentSales.length}) & Withdraw History (${_stats.payouts.length})',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    children: [
                      if (_stats.recentSales.isNotEmpty)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Recent Product Sales', style: TextStyle(fontSize: 11, color: AppColors.mutedOf(context))),
                        ),
                      ..._stats.recentSales.map((s) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                            subtitle: s.info.isNotEmpty ? Text(s.info, style: TextStyle(fontSize: 10, color: AppColors.mutedOf(context))) : null,
                            trailing: Text(s.amount, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.success)),
                          )),
                      if (_stats.payouts.isNotEmpty)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Withdrawals / Payouts', style: TextStyle(fontSize: 11, color: AppColors.mutedOf(context))),
                        ),
                      ..._stats.payouts.map((p) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text('${p.date} · ${p.status}', style: const TextStyle(fontSize: 12)),
                            trailing: Text(p.amount, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.accentTextOf(context))),
                          )),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Batch Queue Header & Strip
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Batch Queue (${_queue.length})',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _pickMultipleVideos,
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add MP4s'),
                    ),
                    ElevatedButton.icon(
                      onPressed: _generating ? null : _generateAllQueueMeta,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      ),
                      icon: const Icon(Icons.auto_awesome, size: 14),
                      label: const Text('All Meta', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
                if (_queue.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 38,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _queue.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final q = _queue[i];
                        final sel = i == _selectedIdx;
                        return ChoiceChip(
                          label: Text('${q.sceneName} (${q.status})', style: const TextStyle(fontSize: 11)),
                          selected: sel,
                          selectedColor: AppColors.activePillOf(context),
                          onSelected: (_) {
                            setState(() => _selectedIdx = i);
                            _initPlayerFor(q);
                          },
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(_status, style: TextStyle(fontSize: 11, color: AppColors.accentTextOf(context))),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Built-in MP4 Video Player Card
        if (_playerCtrl != null && _playerCtrl!.value.isInitialized)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AspectRatio(
                      aspectRatio: _playerCtrl!.value.aspectRatio,
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          VideoPlayer(_playerCtrl!),
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: IconButton.filled(
                              style: IconButton.styleFrom(backgroundColor: Colors.black54),
                              icon: Icon(
                                _playerCtrl!.value.isPlaying ? Icons.pause : Icons.play_arrow,
                                color: Colors.white,
                              ),
                              onPressed: () {
                                setState(() {
                                  _playerCtrl!.value.isPlaying
                                      ? _playerCtrl!.pause()
                                      : _playerCtrl!.play();
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${_playerCtrl!.value.size.width.toInt()}x${_playerCtrl!.value.size.height.toInt()} · ${_playerCtrl!.value.duration.inSeconds}s',
                        style: TextStyle(fontSize: 12, color: AppColors.mutedOf(context)),
                      ),
                      Text(
                        preflight.allPassed ? 'Stock Ready' : 'Check Pre-Flight',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: preflight.allPassed ? AppColors.success : AppColors.danger,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 10),

        // Pre-Flight Compliance Card
        if (_activeItem != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Adobe Stock Pre-Flight Check', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 10,
                    runSpacing: 4,
                    children: [
                      _checkPill('Duration 5s+', preflight.durationOk),
                      _checkPill('1080p+', preflight.resolutionOk),
                      _checkPill('Clean Tags', preflight.metadataClean),
                    ],
                  ),
                  for (final w in preflight.warnings)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('• $w', style: const TextStyle(fontSize: 11, color: AppColors.danger)),
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 10),

        // Metadata Editor + Batch Submit Button
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _titleCtrl,
                  maxLength: 70,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Adobe Stock Title'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _category,
                  dropdownColor: AppColors.cardOf(context),
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                  onChanged: (v) => setState(() => _category = v ?? 'Abstract'),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Keywords (${_tags.length}/49)', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    TextButton.icon(
                      onPressed: () => Clipboard.setData(ClipboardData(text: _tags.join(', '))),
                      icon: const Icon(Icons.copy, size: 15),
                      label: const Text('Copy Tags'),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _tags
                      .map((t) => Chip(
                            label: Text(t, style: const TextStyle(fontSize: 11)),
                            backgroundColor: AppColors.iconBoxOf(context),
                            deleteIcon: const Icon(Icons.close, size: 14),
                            onDeleted: () => setState(() => _tags.remove(t)),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _newTagCtrl,
                        decoration: const InputDecoration(hintText: 'Add keyword...'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      style: IconButton.styleFrom(backgroundColor: AppColors.primary),
                      onPressed: () {
                        final t = _newTagCtrl.text.trim().toLowerCase();
                        if (t.isNotEmpty && _tags.length < 49 && !_tags.contains(t)) {
                          setState(() {
                            _tags.add(t);
                            _newTagCtrl.clear();
                          });
                        }
                      },
                      icon: const Icon(Icons.add, color: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Created using Generative AI', style: TextStyle(fontSize: 13)),
                  value: _isAiGenerated,
                  activeColor: AppColors.primary,
                  onChanged: (v) => setState(() => _isAiGenerated = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('No Recognizable People / Property', style: TextStyle(fontSize: 13)),
                  value: _noPropertyRelease,
                  activeColor: AppColors.primary,
                  onChanged: (v) => setState(() => _noPropertyRelease = v),
                ),
                const SizedBox(height: 10),
                const Text('Target Marketplaces (Same Video -> All Selected)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: StockMarketplace.values.map((m) {
                    final sel = _selectedMarkets.contains(m);
                    return FilterChip(
                      label: Text(m.label, style: const TextStyle(fontSize: 11)),
                      selected: sel,
                      selectedColor: AppColors.activePillOf(context),
                      onSelected: (v) {
                        setState(() {
                          if (v) _selectedMarkets.add(m);
                          else if (_selectedMarkets.length > 1) _selectedMarkets.remove(m);
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _submitting ? null : _submitBatchToAdobeStock,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.send_rounded),
                    label: Text(
                      _queue.length > 1
                          ? 'Submit Review (${_queue.length} Videos)'
                          : 'Submit Review (${_selectedMarkets.length} Marketplaces)',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Toggleable Live Adobe Stock Panel
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.web, color: AppColors.primary),
                title: const Text('Adobe Stock Contributor Panel', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                trailing: Switch(
                  value: _showStockWebView,
                  activeColor: AppColors.primary,
                  onChanged: (v) => setState(() => _showStockWebView = v),
                ),
              ),
              SizedBox(
                height: _showStockWebView ? 380 : 1,
                child: InAppWebView(
                  initialUrlRequest: URLRequest(url: WebUri(AdobeStockAutomation.uploadUrl)),
                  initialSettings: InAppWebViewSettings(
                    userAgent: widget.fingerprint.userAgent,
                    thirdPartyCookiesEnabled: true,
                    domStorageEnabled: true,
                    preferredContentMode: UserPreferredContentMode.MOBILE,
                    useWideViewPort: true,
                    loadWithOverviewMode: false,
                  ),
                  initialUserScripts: UnmodifiableListView<UserScript>([UserScript(
                      source: AntiDetectScripts.buildUserScript(widget.fingerprint),
                      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                    ),]),
                  onWebViewCreated: (c) => _adobeCtrl = c,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 1,
          child: Opacity(
            opacity: 0.01,
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(GeminiCookieService.geminiUrl)),
              initialSettings: InAppWebViewSettings(
                userAgent: widget.fingerprint.userAgent,
                thirdPartyCookiesEnabled: true,
                domStorageEnabled: true,
              ),
              initialUserScripts: UnmodifiableListView<UserScript>([UserScript(
                  source: AntiDetectScripts.buildUserScript(widget.fingerprint),
                  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                ),]),
              onWebViewCreated: (c) => _geminiCtrl = c,
            ),
          ),
        ),
      ],
    );
  }


  Widget _statPill(String label, String val, Color color) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          decoration: BoxDecoration(
            color: AppColors.iconBoxOf(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.borderOf(context)),
          ),
          child: Column(
            children: [
              Text(val, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
              const SizedBox(height: 2),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: AppColors.mutedOf(context))),
            ],
          ),
        ),
      );

  Widget _checkPill(String label, bool ok) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ok ? Icons.check_circle : Icons.error_outline,
              size: 15, color: ok ? AppColors.success : AppColors.danger),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      );
}
