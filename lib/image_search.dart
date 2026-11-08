// Image Search screen — find wallpaper ideas on Google Images and
// Pinterest inside the app's built-in Chromium browser, then pull the
// chosen picture straight into the studio:
//
//   1. Type a query, pick a source (Google Images / Pinterest), Search.
//   2. Browse in the Chromium view; open the picture you like.
//   3. Tap "Pick image from this page" — the app reads the page's
//      images (og:image + <img> tags), shows the biggest candidates,
//      and downloads the one you tap.
//   4. Choose what to do with it: Use as Reference / Image to Prompt /
//      Save copy. The result is handed back to the home screen.
//
// UI follows the app's existing style: same browser toolbar as the
// Gemini Login screen, ChoiceChips like the Set Designer mode chips,
// FilledButton.icon for the main action, OutlinedButton.icon for
// secondary actions.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;

import 'gemini_api.dart';

/// What the home screen receives when the user picks an image.
class ImageSearchPick {
  final Uint8List bytes;
  final String name;
  final String mime;

  /// 'reference' | 'prompt' | 'save'
  final String action;
  final String sourcePageUrl;
  const ImageSearchPick({
    required this.bytes,
    required this.name,
    required this.mime,
    required this.action,
    required this.sourcePageUrl,
  });
}

class SearchImageCandidate {
  final String url;
  final int width;
  final int height;
  const SearchImageCandidate(this.url, this.width, this.height);
  int get area => width * height;
  @override
  String toString() => '$url (${width}x$height)';
}

String googleImagesSearchUrl(String query) =>
    'https://www.google.com/search?tbm=isch&udm=2&q=${Uri.encodeComponent(query.trim())}';

String pinterestSearchUrl(String query) =>
    'https://www.pinterest.com/search/pins/?q=${Uri.encodeComponent(query.trim())}';

/// Parse the result of the candidate-extraction JavaScript (a JSON
/// string of [{url,w,h}, ...]) into clean, de-duplicated candidates:
/// http(s) only, no data: URLs, images with a known size under 150px
/// on either side dropped, biggest first.
List<SearchImageCandidate> parseImageCandidates(Object? jsResult) {
  Object? decoded = jsResult;
  if (decoded is String) {
    var s = decoded.trim();
    // evaluateJavascript can hand back a JSON string wrapped in quotes.
    try {
      decoded = jsonDecode(s);
    } catch (_) {
      return const [];
    }
    if (decoded is String) {
      try {
        decoded = jsonDecode(decoded);
      } catch (_) {
        return const [];
      }
    }
  }
  if (decoded is! List) return const [];
  final seen = <String>{};
  final out = <SearchImageCandidate>[];
  for (final item in decoded) {
    if (item is! Map) continue;
    final url = item['url']?.toString() ?? '';
    if (!url.startsWith('http://') && !url.startsWith('https://')) continue;
    if (!seen.add(url)) continue;
    final w = (item['w'] as num?)?.toInt() ?? 0;
    final h = (item['h'] as num?)?.toInt() ?? 0;
    if ((w > 0 && w < 150) || (h > 0 && h < 150)) continue;
    out.add(SearchImageCandidate(url, w, h));
  }
  out.sort((a, b) => b.area.compareTo(a.area));
  return out;
}

const String _extractImagesJs = r'''
(function () {
  var out = [];
  var og = document.querySelector('meta[property="og:image"]');
  if (og && og.content) out.push({url: og.content, w: 0, h: 0});
  var imgs = Array.prototype.slice.call(document.images || []);
  var mapped = imgs.map(function (im) {
    return {url: im.currentSrc || im.src || '', w: im.naturalWidth || 0, h: im.naturalHeight || 0};
  }).filter(function (x) { return x.url && x.w >= 200 && x.h >= 200; });
  mapped.sort(function (a, b) { return (b.w * b.h) - (a.w * a.h); });
  for (var i = 0; i < mapped.length && i < 12; i++) out.push(mapped[i]);
  return JSON.stringify(out);
})()
''';

class ImageSearchScreen extends StatefulWidget {
  const ImageSearchScreen({super.key});

  @override
  State<ImageSearchScreen> createState() => _ImageSearchScreenState();
}

class _ImageSearchScreenState extends State<ImageSearchScreen> {
  InAppWebViewController? _web;
  final TextEditingController _queryCtrl = TextEditingController();
  String _source = 'google'; // google | pinterest
  String _currentUrl = '';
  bool _canGoBack = false;
  bool _canGoForward = false;
  bool _loading = false;
  double _progress = 0;
  bool _picking = false;
  String _status =
      'Search Google Images or Pinterest, open a picture you like, then tap "Pick image from this page".';

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  String get _homeUrl => _source == 'google'
      ? 'https://www.google.com/search?tbm=isch&udm=2'
      : 'https://www.pinterest.com/';

  Future<void> _runSearch() async {
    final q = _queryCtrl.text.trim();
    final url = q.isEmpty
        ? _homeUrl
        : (_source == 'google'
            ? googleImagesSearchUrl(q)
            : pinterestSearchUrl(q));
    await _web?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  Future<void> _refreshNavState(InAppWebViewController controller) async {
    try {
      final back = await controller.canGoBack();
      final fwd = await controller.canGoForward();
      final url = await controller.getUrl();
      if (!mounted) return;
      setState(() {
        _canGoBack = back;
        _canGoForward = fwd;
        if (url != null) _currentUrl = url.toString();
      });
    } catch (_) {}
  }

  Future<void> _pickFromPage() async {
    if (_picking || _web == null) return;
    setState(() => _picking = true);
    try {
      final raw = await _web!.evaluateJavascript(source: _extractImagesJs);
      final candidates = parseImageCandidates(raw);
      if (!mounted) return;
      if (candidates.isEmpty) {
        setState(() => _status =
            'No usable image found on this page yet. Open one picture fully (tap it until it is large), then try again.');
        return;
      }
      final chosen = await showModalBottomSheet<SearchImageCandidate>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(14),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Pick an image from this page',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: candidates.length,
                  itemBuilder: (ctx, i) {
                    final c = candidates[i];
                    return ListTile(
                      leading: Image.network(
                        c.url,
                        width: 46,
                        height: 46,
                        fit: BoxFit.cover,
                        headers: const {'User-Agent': GeminiApi.chromeUserAgent},
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.broken_image_outlined),
                      ),
                      title: Text(
                        c.width > 0 ? '${c.width} x ${c.height}' : 'Page image',
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(c.url,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11)),
                      onTap: () => Navigator.of(ctx).pop(c),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
      if (chosen == null || !mounted) return;
      await _downloadAndOffer(chosen);
    } catch (e) {
      if (mounted) {
        setState(() => _status = 'Could not read images from this page: $e');
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _downloadAndOffer(SearchImageCandidate c) async {
    setState(() => _status = 'Downloading the selected image...');
    final resp = await http.get(Uri.parse(c.url),
        headers: {'User-Agent': GeminiApi.chromeUserAgent});
    if (resp.statusCode != 200) {
      setState(() =>
          _status = 'Download failed (HTTP ${resp.statusCode}). Try another image.');
      return;
    }
    final contentType = resp.headers['content-type'] ?? '';
    var mime = 'image/jpeg';
    if (contentType.contains('png')) {
      mime = 'image/png';
    } else if (contentType.contains('webp')) {
      mime = 'image/webp';
    }
    var name = Uri.tryParse(c.url)?.pathSegments.lastOrNull ?? '';
    if (name.isEmpty || !name.contains('.')) {
      name = mime == 'image/png'
          ? 'searched_image.png'
          : mime == 'image/webp'
              ? 'searched_image.webp'
              : 'searched_image.jpg';
    }
    if (!mounted) return;
    setState(() => _status = 'Image downloaded. What do you want to do with it?');
    // Preview + action choice, in the app's usual button styles.
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(resp.bodyBytes,
                    height: 200, fit: BoxFit.contain),
              ),
              const SizedBox(height: 6),
              Text(name,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).pop(ImageSearchPick(
                    bytes: resp.bodyBytes,
                    name: name,
                    mime: mime,
                    action: 'reference',
                    sourcePageUrl: _currentUrl,
                  ));
                },
                icon: const Icon(Icons.image_outlined, size: 18),
                label: const Text('Use as Reference image'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).pop(ImageSearchPick(
                    bytes: resp.bodyBytes,
                    name: name,
                    mime: mime,
                    action: 'prompt',
                    sourcePageUrl: _currentUrl,
                  ));
                },
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text('Image to Prompt'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).pop(ImageSearchPick(
                    bytes: resp.bodyBytes,
                    name: name,
                    mime: mime,
                    action: 'save',
                    sourcePageUrl: _currentUrl,
                  ));
                },
                icon: const Icon(Icons.save_alt_outlined, size: 18),
                label: const Text('Save a copy'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _browserToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
            bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            visualDensity: VisualDensity.compact,
            onPressed: _canGoBack ? () => _web?.goBack() : null,
            icon: const Icon(Icons.arrow_back, size: 20),
          ),
          IconButton(
            tooltip: 'Forward',
            visualDensity: VisualDensity.compact,
            onPressed: _canGoForward ? () => _web?.goForward() : null,
            icon: const Icon(Icons.arrow_forward, size: 20),
          ),
          IconButton(
            tooltip: _loading ? 'Stop' : 'Reload',
            visualDensity: VisualDensity.compact,
            onPressed: () => _loading ? _web?.stopLoading() : _web?.reload(),
            icon: Icon(_loading ? Icons.close : Icons.refresh, size: 20),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                _currentUrl.isEmpty ? _homeUrl : _currentUrl,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Image Search')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _queryCtrl,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _runSearch(),
                    decoration: const InputDecoration(
                      labelText: 'Search images',
                      hintText: 'e.g. neon mountain wallpaper',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _runSearch,
                  icon: const Icon(Icons.search, size: 18),
                  label: const Text('Search'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 6,
                children: [
                  ChoiceChip(
                    label: const Text('Google Images',
                        style: TextStyle(fontSize: 12)),
                    selected: _source == 'google',
                    onSelected: (_) {
                      setState(() => _source = 'google');
                      _runSearch();
                    },
                  ),
                  ChoiceChip(
                    label:
                        const Text('Pinterest', style: TextStyle(fontSize: 12)),
                    selected: _source == 'pinterest',
                    onSelected: (_) {
                      setState(() => _source = 'pinterest');
                      _runSearch();
                    },
                  ),
                ],
              ),
            ),
          ),
          _browserToolbar(),
          if (_progress > 0 && _progress < 1)
            LinearProgressIndicator(value: _progress),
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: InAppWebView(
                  initialUrlRequest: URLRequest(url: WebUri(_homeUrl)),
                  initialSettings: InAppWebViewSettings(
                    userAgent: GeminiApi.chromeUserAgent,
                    javaScriptEnabled: true,
                    domStorageEnabled: true,
                    thirdPartyCookiesEnabled: true,
                    supportMultipleWindows: true,
                    javaScriptCanOpenWindowsAutomatically: true,
                    useHybridComposition: true,
                    cacheEnabled: true,
                  ),
                  onWebViewCreated: (controller) => _web = controller,
                  onLoadStart: (controller, url) {
                    if (!mounted) return;
                    setState(() {
                      _loading = true;
                      if (url != null) _currentUrl = url.toString();
                    });
                  },
                  onProgressChanged: (controller, progress) {
                    if (mounted) setState(() => _progress = progress / 100);
                  },
                  onLoadStop: (controller, url) async {
                    if (mounted) setState(() => _loading = false);
                    await _refreshNavState(controller);
                  },
                  onUpdateVisitedHistory: (controller, url, isReload) {
                    if (url != null && mounted) {
                      setState(() => _currentUrl = url.toString());
                    }
                  },
                  onReceivedError: (controller, request, error) {
                    if (mounted && (request.isForMainFrame ?? true)) {
                      setState(() => _loading = false);
                    }
                  },
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(_status, style: const TextStyle(fontSize: 12)),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton.icon(
              onPressed: _picking ? null : _pickFromPage,
              icon: _picking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Pick image from this page'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
