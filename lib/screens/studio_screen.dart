import 'dart:collection';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:gal/gal.dart';
import '../models/studio_models.dart';
import '../services/anti_detect_scripts.dart';
import '../services/mh_motion_api.dart';
import '../theme/app_theme.dart';

class StudioScreen extends StatefulWidget {
  final MhMotionApi api;
  final FingerprintProfile fingerprint;
  final String initialTunnelUrl;
  final ValueChanged<ServerInfo> onConnected;
  final void Function(File videoFile, String sceneName, String shaderCode) onSendToUploadPanel;
  final void Function(List<(File, String)> batch)? onSendBatchToUploadPanel;
  final bool isFullScreen;
  final ValueChanged<bool>? onFullScreenChanged;

  const StudioScreen({
    super.key,
    required this.api,
    required this.fingerprint,
    required this.initialTunnelUrl,
    required this.onConnected,
    required this.onSendToUploadPanel,
    this.onSendBatchToUploadPanel,
    this.isFullScreen = false,
    this.onFullScreenChanged,
  });

  @override
  State<StudioScreen> createState() => StudioScreenState();
}

class StudioScreenState extends State<StudioScreen> {
  final _urlCtrl = TextEditingController();
  InAppWebViewController? _webCtrl;
  String? _loadedUrl;
  bool _busyAction = false;
  String? _statusMsg;

  static const String _mobileFitPanelCss = '''
(function() {
  let meta = document.querySelector('meta[name="viewport"]');
  if (!meta) {
    meta = document.createElement('meta');
    meta.name = 'viewport';
    document.head.appendChild(meta);
  }
  meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
  if (!document.getElementById('mh-panel-mobile')) {
    const s = document.createElement('style');
    s.id = 'mh-panel-mobile';
    s.textContent = 'html, body { max-width: 100vw !important; overflow-x: hidden !important; }';
    document.head.appendChild(s);
  }
})();
''';

  @override
  void initState() {
    super.initState();
    if (widget.initialTunnelUrl.isNotEmpty) {
      _urlCtrl.text = widget.initialTunnelUrl;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openStudioUrl(widget.initialTunnelUrl);
      });
    }
  }

  @override
  void didUpdateWidget(covariant StudioScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTunnelUrl.isNotEmpty &&
        widget.initialTunnelUrl != _loadedUrl) {
      _urlCtrl.text = widget.initialTunnelUrl;
      _openStudioUrl(widget.initialTunnelUrl);
    }
  }

  Future<void> _openStudioUrl(String rawUrl) async {
    final clean = rawUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (clean.isEmpty) return;
    setState(() {
      _loadedUrl = clean;
      _statusMsg = 'Opening MH Motion Studio...';
    });
    try {
      final info = await widget.api.connect(url: clean);
      widget.onConnected(info);
      setState(() => _statusMsg = 'Live on ${info.gpu}');
    } catch (_) {
      // Even if panel has password or is still booting, WebView still loads it
    }
    await _webCtrl?.loadUrl(urlRequest: URLRequest(url: WebUri(clean)));
  }

  Future<void> _sendLatestRenderToUploadPanel() async {
    if (_loadedUrl == null) return;
    setState(() {
      _busyAction = true;
      _statusMsg = 'Fetching latest rendered MP4 from Colab...';
    });
    try {
      widget.api.setBaseUrl(_loadedUrl!);
      final outputs = await widget.api.listOutputs();
      if (outputs.isEmpty) {
        setState(() {
          _busyAction = false;
          _statusMsg = 'No rendered MP4 found yet. Render a video in Studio first!';
        });
        return;
      }
      final latest = outputs.first;
      final file = await widget.api.downloadOutput(latest.name);
      setState(() {
        _busyAction = false;
        _statusMsg = 'Sent ${latest.name} to Upload Panel!';
      });
      widget.onSendToUploadPanel(file, latest.name.replaceAll('.mp4', ''), '');
    } catch (e) {
      setState(() {
        _busyAction = false;
        _statusMsg = 'Could not fetch MP4: $e';
      });
    }
  }


  Future<void> _sendAllOutputsToUploadPanel() async {
    if (_loadedUrl == null) return;
    setState(() {
      _busyAction = true;
      _statusMsg = 'Syncing v4 Bulk QC-passed MP4s to Upload Panel...';
    });
    try {
      widget.api.setBaseUrl(_loadedUrl!);
      final outputs = await widget.api.listOutputs();
      if (outputs.isEmpty) {
        setState(() {
          _busyAction = false;
          _statusMsg = 'No MP4 outputs found yet.';
        });
        return;
      }
      final batch = <(File, String)>[];
      for (final o in outputs.take(10)) {
        final f = await widget.api.downloadOutput(o.name);
        batch.add((f, o.name.replaceAll('.mp4', '')));
      }
      setState(() {
        _busyAction = false;
        _statusMsg = 'Queued ${batch.length} MP4s into Upload Panel!';
      });
      widget.onSendBatchToUploadPanel?.call(batch);
    } catch (e) {
      setState(() {
        _busyAction = false;
        _statusMsg = 'Batch sync error: $e';
      });
    }
  }

  Future<void> _downloadLatestToGallery() async {
    if (_loadedUrl == null) return;
    setState(() {
      _busyAction = true;
      _statusMsg = 'Downloading latest MP4 to Gallery...';
    });
    try {
      widget.api.setBaseUrl(_loadedUrl!);
      final outputs = await widget.api.listOutputs();
      if (outputs.isEmpty) throw Exception('No MP4 outputs found');
      final latest = outputs.first;
      final file = await widget.api.downloadOutput(latest.name);
      await Gal.putVideo(file.path);
      setState(() {
        _busyAction = false;
        _statusMsg = 'Saved ${latest.name} to Phone Gallery!';
      });
    } catch (e) {
      setState(() {
        _busyAction = false;
        _statusMsg = 'Download error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hideChrome = widget.isFullScreen && _loadedUrl != null;

    return Stack(
      children: [
        Column(
          children: [
            if (!hideChrome)
              // Top Tunnel URL Bar
              Container(
          color: AppColors.drawerOf(context),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _urlCtrl,
                  style: const TextStyle(fontSize: 12),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    hintText: 'Colab trycloudflare.com link (auto-detected)...',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => _openStudioUrl(_urlCtrl.text),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Open', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
              if (!hideChrome && _loadedUrl != null) ...[
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Full Screen',
                  onPressed: () => widget.onFullScreenChanged?.call(true),
                  icon: const Icon(Icons.fullscreen_rounded, size: 22),
                ),
              ],
            ],
          ),
        ),
        if (!hideChrome && _statusMsg != null)
          Container(
            width: double.infinity,
            color: AppColors.activePillOf(context),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            child: Text(
              _statusMsg!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: AppColors.accentTextOf(context)),
            ),
          ),
        // Exact Colab MH Motion Studio Web Interface (panel.html)
        Expanded(
          child: _loadedUrl == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.play_circle_outline, size: 52, color: AppColors.primary),
                        const SizedBox(height: 12),
                        const Text(
                          'Run Colab in the Browser tab',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Once Colab prints the trycloudflare.com link, the exact MH Motion Studio interface will load right here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: AppColors.mutedOf(context)),
                        ),
                      ],
                    ),
                  ),
                )
              : InAppWebView(
                  initialUrlRequest: URLRequest(url: WebUri(_loadedUrl!)),
                  initialSettings: InAppWebViewSettings(
                    userAgent: widget.fingerprint.userAgent,
                    javaScriptEnabled: true,
                    domStorageEnabled: true,
                    thirdPartyCookiesEnabled: true,
                    allowsInlineMediaPlayback: true,
                    useHybridComposition: true,
                    preferredContentMode: UserPreferredContentMode.MOBILE,
                    useWideViewPort: true,
                    loadWithOverviewMode: false,
                    initialScale: 100,
                    textZoom: 100,
                  ),
                  initialUserScripts: UnmodifiableListView<UserScript>([UserScript(
                      source: AntiDetectScripts.buildUserScript(widget.fingerprint),
                      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                    ),]),
                  onWebViewCreated: (c) => _webCtrl = c,
                  onLoadStop: (c, url) async {
                    // v5.6 panel.html has native mobile responsive UI
                  },
                ),
        ),
        // Quick Action Bar to Download or Send Rendered MP4 to Upload Panel
        if (!hideChrome && _loadedUrl != null)
          Container(
            color: AppColors.drawerOf(context),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busyAction ? null : _downloadLatestToGallery,
                    icon: const Icon(Icons.download, size: 16),
                    label: const Text('Save Latest MP4', style: TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _busyAction ? null : _sendLatestRenderToUploadPanel,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.cloud_upload_outlined, size: 16),
                    label: const Text('Send Latest', style: TextStyle(fontSize: 11)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _busyAction ? null : _sendAllOutputsToUploadPanel,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primarySecondary,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.layers, size: 16),
                    label: const Text('Sync Bulk v4', style: TextStyle(fontSize: 11)),
                  ),
                ),
              ],
            ),
          ),
          ],
        ),
        if (hideChrome)
          Positioned(
            right: 12,
            bottom: 16,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(6),
                      icon: const Icon(Icons.refresh_rounded, size: 16, color: Colors.white),
                      onPressed: () => _webCtrl?.reload(),
                    ),
                    IconButton(
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(6),
                      icon: const Icon(Icons.fullscreen_exit_rounded, size: 18, color: AppColors.primaryLight),
                      onPressed: () => widget.onFullScreenChanged?.call(false),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
