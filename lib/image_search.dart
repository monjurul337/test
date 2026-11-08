// Image Search + Image-to-Prompt screen — find wallpaper ideas on
// Google Images / Pinterest / Unsplash / Lexica, then pull the
// chosen picture into the studio. Two browsing models, by platform:
//
//   * ANDROID — the built-in Firefox browser (GeckoView, the same
//     engine as the Gemini sign-in): an in-page overlay lets the
//     user tap pictures to select them ("basket"), generate prompts
//     for the whole selection, or prompt a single picture / capture;
//     selections and requests stream back over the gecko channel
//     (see gecko_browser.dart) and finished prompts land in the
//     Prompts card below.
//   * WINDOWS — the app's own Chrome / Edge window on its own
//     profile (see chromium_studio_browser.dart): a real browser
//     window driven over the DevTools protocol with the SAME
//     overlay and the same basket pipeline; nothing is embedded.
//   * ELSEWHERE — browsing runs in a DEDICATED EXTERNAL browser
//     process (Chrome / Firefox / default). Tapping a source tab or
//     "Open browser" fires an intent at the external browser (see
//     external_browser.dart), and the bridge back is the link panel
//     ([_BrowserScreen]): the user copies an image link in the
//     browser; the panel collects links via clipboard paste /
//     manual entry (device gallery too), each downloadable into
//     the image actions sheet (Use as Reference / Save copy / Image
//     to Prompt), and batch prompt generation (Similarity Target)
//     runs on the collected links in-app. An app cannot read
//     another browser's page, so on this model there is no in-page
//     picking — the link bridge is the transfer mechanism.
//
// UI follows the app's existing style: ChoiceChips like the Set
// Designer mode chips, FilledButton.icon for the main action,
// OutlinedButton.icon for secondary actions.
import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'chromium_studio_browser.dart';
import 'external_browser.dart';
import 'gecko_browser.dart';
import 'gecko_signin.dart';
import 'gemini_api.dart';
import 'login_screen.dart';
import 'models.dart';
import 'session_store.dart';

/// What the home screen receives when the user picks an image.
class ImageSearchPick {
  final Uint8List bytes;
  final String name;
  final String mime;

  /// 'reference' | 'prompt' | 'save'
  final String action;
  final String sourcePageUrl;

  /// For action 'prompt': the prompt generated inside this screen,
  /// ready to drop into the Set Designer prompt field.
  final String? generatedPrompt;

  /// For action 'prompt' with the sheet's "Auto-add to Prompts list"
  /// option on: append to the designer prompt field as a new line
  /// instead of replacing what is there.
  final bool appendPrompt;

  /// For action 'prompts' (multi-select batch generation): one
  /// generated prompt per selected image, in selection order. The
  /// home screen appends them to the Batch Sets prompt box.
  final List<String> generatedPrompts;
  const ImageSearchPick({
    required this.bytes,
    required this.name,
    required this.mime,
    required this.action,
    required this.sourcePageUrl,
    this.generatedPrompt,
    this.appendPrompt = false,
    this.generatedPrompts = const [],
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

String unsplashSearchUrl(String query) =>
    'https://unsplash.com/s/photos/${Uri.encodeComponent(query.trim())}';

String lexicaSearchUrl(String query) =>
    'https://lexica.art/?q=${Uri.encodeQueryComponent(query.trim())}';

/// Parse the selection bridge payload (a JSON array of image URLs
/// sent by the in-page selection script) into a clean ordered list:
/// http(s) only, de-duplicated, order preserved.
List<String> parseSelectionUrls(Object? raw) {
  Object? decoded = raw;
  if (decoded is String) {
    try {
      decoded = jsonDecode(decoded);
    } catch (_) {
      return const [];
    }
  }
  if (decoded is! List) return const [];
  final seen = <String>{};
  final out = <String>[];
  for (final item in decoded) {
    final url = item?.toString() ?? '';
    if (!url.startsWith('http://') && !url.startsWith('https://')) continue;
    if (seen.add(url)) out.add(url);
  }
  return out;
}

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

/// Image-to-prompt options, shared by the single-image actions sheet
/// and the multi-select batch sheet; persisted across sessions.
class PromptOptions {
  int similarity = 20;
  bool avoidRepeat = true;
  bool autoAdd = true;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    similarity = prefs.getInt('i2pSimilarity') ?? 20;
    avoidRepeat = prefs.getBool('i2pAvoidRepeat') ?? true;
    autoAdd = prefs.getBool('i2pAutoAdd') ?? true;
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('i2pSimilarity', similarity);
    await prefs.setBool('i2pAvoidRepeat', avoidRepeat);
    await prefs.setBool('i2pAutoAdd', autoAdd);
  }
}

/// Prompts already generated in this app session — the pool the
/// "avoid repeating earlier prompts" check compares against.
class GeneratedPromptPool {
  static final List<String> prompts = <String>[];

  static void add(String prompt) {
    prompts.add(prompt);
    if (prompts.length > 30) prompts.removeAt(0);
  }
}

/// Generate a prompt for one image with [options], applying the
/// avoid-repeat rule: when the result reads like an earlier prompt of
/// this session, it is rewritten ONCE with the clashing prompt named
/// in the instruction. [onRewriting] fires just before the rewrite so
/// the UI can say what is happening.
Future<String> generatePromptChecked({
  required Uint8List bytes,
  required String name,
  required String mime,
  required PromptOptions options,
  String styleNote = '',
  void Function()? onRewriting,
}) async {
  final api = GeminiApi();
  final fileName = name.isEmpty ? 'image.jpg' : name;
  var prompt = await api.generatePromptFromImage(
    bytes,
    fileName,
    mimeType: mime,
    styleNote: styleNote,
    similarity: options.similarity,
  );
  if (options.avoidRepeat) {
    String? clash;
    for (final old in GeneratedPromptPool.prompts) {
      if (GeminiApi.promptSimilarity(prompt, old) >= 0.6) {
        clash = old;
        break;
      }
    }
    if (clash != null) {
      onRewriting?.call();
      prompt = await api.generatePromptFromImage(
        bytes,
        fileName,
        mimeType: mime,
        styleNote: styleNote,
        similarity: options.similarity,
        extraInstruction: 'An earlier prompt in this session was very '
            'similar: "$clash" Write a clearly different prompt — '
            'different subject details, setting, composition and '
            'palette — while keeping the same similarity target.',
      );
    }
  }
  GeneratedPromptPool.add(prompt);
  return prompt;
}

/// The Options panel: Similarity target slider + preset chips, the
/// live Stays-the-same / Will-change aspect groups, the behaviour
/// toggles and a collapsible preview of the exact Gemini instruction.
/// Mutations update [options], persist them, then call [onChanged] so
/// the parent rebuilds.
class SimilarityOptionsPanel extends StatelessWidget {
  final PromptOptions options;
  final VoidCallback onChanged;
  final bool showAutoAdd;
  final String styleNote;
  const SimilarityOptionsPanel({
    super.key,
    required this.options,
    required this.onChanged,
    this.showAutoAdd = true,
    this.styleNote = '',
  });

  void _update(void Function() change) {
    change();
    options.save();
    onChanged();
  }

  Widget _aspectGroup(
      String title, IconData icon, Color color, List<String> aspects) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text('$title (${aspects.length})',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
        const SizedBox(height: 4),
        if (aspects.isEmpty)
          const Text('Nothing — everything stays',
              style: TextStyle(fontSize: 11, color: Colors.grey))
        else
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              for (final a in aspects)
                Chip(
                  label: Text(a, style: const TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                  side: BorderSide(color: color.withAlpha(140)),
                ),
            ],
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('Similarity target',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                  const Spacer(),
                  Text('${options.similarity}%',
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.green)),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Text(GeminiApi.similarityLabel(options.similarity),
                    style:
                        const TextStyle(fontSize: 11, color: Colors.green)),
              ),
              const Text('How close the new image stays to the reference',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
              Slider(
                value: options.similarity.toDouble(),
                min: 20,
                max: 90,
                divisions: 70,
                label: '${options.similarity}%',
                onChanged: (v) =>
                    _update(() => options.similarity = v.round()),
              ),
              const Row(
                children: [
                  Expanded(
                    child: Text('More original',
                        style: TextStyle(fontSize: 11, color: Colors.grey)),
                  ),
                  Expanded(
                    child: Text('Closer to reference',
                        textAlign: TextAlign.end,
                        style: TextStyle(fontSize: 11, color: Colors.grey)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final e in GeminiApi.kSimilarityPresets.entries)
                    ChoiceChip(
                      label:
                          Text(e.key, style: const TextStyle(fontSize: 11)),
                      selected: options.similarity == e.value,
                      onSelected: (_) =>
                          _update(() => options.similarity = e.value),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              _aspectGroup('Stays the same', Icons.lock_outline, Colors.green,
                  GeminiApi.staysForSimilarity(options.similarity)),
              const SizedBox(height: 6),
              _aspectGroup('Will change', Icons.shuffle, Colors.orange,
                  GeminiApi.changesForSimilarity(options.similarity)),
            ],
          ),
        ),
        if (showAutoAdd)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Auto-add to Prompts list',
                style: TextStyle(fontSize: 13)),
            subtitle: const Text(
                'The designer button adds the finished prompt to the prompt list instead of replacing it',
                style: TextStyle(fontSize: 11)),
            value: options.autoAdd,
            onChanged: (v) => _update(() => options.autoAdd = v),
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Avoid repeating earlier prompts',
              style: TextStyle(fontSize: 13)),
          subtitle: const Text(
              'Rewrites a prompt once if it reads like another one from this session',
              style: TextStyle(fontSize: 11)),
          value: options.avoidRepeat,
          onChanged: (v) => _update(() => options.avoidRepeat = v),
        ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Gemini instruction',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          subtitle: const Text('How the picture is described',
              style: TextStyle(fontSize: 11)),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: SelectableText(
                GeminiApi.buildImageToPromptInstruction(
                    similarity: options.similarity, styleNote: styleNote),
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ],
    );
  }
}

/// Image to Prompt home, in the reference layout: a **Browser**
/// card (engine + status pill, start URL, source chips, Open
/// browser / Sign in, How it works), a **Prompts** card (finished
/// prompts land here — with Auto-add on they go straight to Batch
/// Sets > Prompts) and an **Options** card (Gemini web cookies
/// account choice + the Similarity Target panel). Browsing itself
/// is external (Chrome / Firefox); [_BrowserScreen] is the pushed
/// link-collection + prompt panel, with no embedded web view.
class ImageSearchScreen extends StatefulWidget {
  /// Opened from the designer's Image to Prompt button (promptMode)
  /// or the Search navigation destination.
  final bool promptMode;
  const ImageSearchScreen({super.key, this.promptMode = false});

  @override
  State<ImageSearchScreen> createState() => _ImageSearchHomeState();
}

class _ImageSearchHomeState extends State<ImageSearchScreen> {
  final PromptOptions _options = PromptOptions();
  final List<String> _readyPrompts = [];
  String _promptsStatus = 'No prompts yet.';
  bool _browserOpen = false;
  String _source = 'pinterest';
  String _accountMode = 'auto';
  List<GeminiAccount> _accounts = [];

  // App-browser (Android Gecko / Windows Chromium): overlay
  // selection ("basket"), its byte cache, and the subscriptions.
  final List<String> _basket = [];
  final Map<String, String> _basketHi = {};
  final Map<String, String> _basketPage = {};
  final Map<String, String> _basketSession = {};
  final Map<String, Uint8List> _basketBytes = {};
  StreamSubscription<GeckoBrowserRequest>? _geckoReqSub;
  StreamSubscription<void>? _geckoChangeSub;
  StreamSubscription<GeckoBrowserRequest>? _winReqSub;
  StreamSubscription<void>? _winChangeSub;
  bool _geckoGenerating = false;

  bool get _gecko => GeckoSignIn.supported;
  bool get _win => ChromiumStudioBrowser.supported;
  bool get _appBrowser => _gecko || _win;
  bool get _anyBrowserOpen =>
      (_gecko && GeckoBrowser.instance.isOpen) ||
      (_win && ChromiumStudioBrowser.instance.isOpen);

  void _refreshPill() {
    if (mounted) setState(() => _browserOpen = _anyBrowserOpen);
  }

  @override
  void initState() {
    super.initState();
    _load();
    if (_gecko) {
      final gb = GeckoBrowser.instance;
      _geckoReqSub = gb.requests.listen(_onGeckoRequest);
      _geckoChangeSub = gb.changes.listen((_) => _refreshPill());
      gb.refreshIsOpen();
    }
    if (_win) {
      final cb = ChromiumStudioBrowser.instance;
      _winReqSub = cb.requests.listen(_onGeckoRequest);
      _winChangeSub = cb.changes.listen((_) => _refreshPill());
    }
  }

  @override
  void dispose() {
    _geckoReqSub?.cancel();
    _geckoChangeSub?.cancel();
    _winReqSub?.cancel();
    _winChangeSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    await _options.load();
    final mode = await SessionStore.loadAccountMode();
    final accounts = await SessionStore.loadDiscoveredAccounts();
    if (!mounted) return;
    setState(() {
      _accountMode = mode;
      _accounts = accounts;
    });
  }

  String get _startUrl => _startUrlFor(_source);

  static String _startUrlFor(String source) => switch (source) {
        'pinterest' => 'https://www.pinterest.com/',
        'unsplash' => 'https://unsplash.com/',
        'lexica' => 'https://lexica.art/',
        _ => 'https://www.google.com/search?tbm=isch&udm=2',
      };

  String get _engineLabel => _gecko
      ? 'Built-in Firefox browser'
      : _win
          ? 'App browser — Chrome / Edge window'
          : 'External browser — Chrome / Firefox';

  /// "Open browser" — Android: the built-in Firefox browser;
  /// Windows: the app's own Chrome / Edge window (the selected
  /// source loads in it; tick pictures there to select them).
  /// Elsewhere: a dedicated external browser process (Chrome /
  /// Firefox / default); nothing is embedded in the app.
  Future<void> _openExternalHome() async {
    if (_gecko) {
      await GeckoBrowser.instance.open(_startUrl);
      if (!mounted) return;
      setState(() => _promptsStatus = 'Built-in browser open — tap '
          '"Select pictures" there, tick pictures, then Generate '
          'prompts. Finished prompts land in the Prompts card.');
      return;
    }
    if (_win) {
      try {
        await ChromiumStudioBrowser.instance.open(_startUrl);
        if (!mounted) return;
        setState(() => _promptsStatus = 'App browser open — tick '
            'pictures there to select them, then Generate prompts. '
            'Finished prompts land in the Prompts card.');
      } catch (e) {
        if (!mounted) return;
        setState(() => _promptsStatus = 'Could not open the app '
            'browser: $e');
      }
      return;
    }
    final ok = await ExternalBrowser.open(_startUrl);
    if (!mounted) return;
    setState(() => _promptsStatus = ok
        ? 'Opened in your browser — copy an image link there, then '
            'collect it under "Image links & prompts".'
        : 'No browser could be opened on this device.');
  }

  // ------------- App browser (Gecko / Chromium) -------------

  /// One overlay request batch entry from the app browser.
  void _onGeckoRequest(GeckoBrowserRequest r) {
    switch (r.action) {
      case 'select':
        var changed = false;
        for (final ref in r.images) {
          if (_basket.contains(ref.src)) continue;
          _basket.add(ref.src);
          if (ref.hi.isNotEmpty) _basketHi[ref.src] = ref.hi;
          _basketPage[ref.src] = r.page;
          _basketSession[ref.src] = r.sessionId;
          changed = true;
          // Download now, while the picture is still on screen.
          _prefetchBasket(ref.src);
        }
        if (changed) _syncBasket();
      case 'unselect':
        final drop = r.images.map((i) => i.src).toSet();
        final before = _basket.length;
        _basket.removeWhere(drop.contains);
        for (final s in drop) {
          _basketHi.remove(s);
          _basketPage.remove(s);
          _basketSession.remove(s);
          _basketBytes.remove(s);
        }
        if (_basket.length != before) _syncBasket();
      case 'clear_basket':
        if (_basket.isNotEmpty) {
          _basket.clear();
          _basketHi.clear();
          _basketPage.clear();
          _basketSession.clear();
          _basketBytes.clear();
          _syncBasket();
        }
      case 'generate_basket':
        _generateBasketPrompts();
      case 'single':
        if (r.images.isNotEmpty) {
          _basketSession[r.images.first.src] = r.sessionId;
          _generateFromBrowser(r.images.first);
        }
      case 'capture':
        if (r.images.isNotEmpty) {
          _basketSession[r.images.first.src] = r.sessionId;
          _captureFromBrowser(r.images.first);
        }
    }
  }

  /// Pushes the selection into the page overlay and mirrors the
  /// count in the Prompts status line.
  void _syncBasket() {
    final pages = _basket.map((s) => _basketPage[s] ?? '').toSet().length;
    if (_gecko) GeckoBrowser.instance.setBasket(List.of(_basket), pages);
    if (_win) {
      ChromiumStudioBrowser.instance.setBasket(List.of(_basket), pages);
    }
    if (!mounted) return;
    setState(() => _promptsStatus = _basket.isEmpty
        ? 'No prompts yet.'
        : '${_basket.length} picture${_basket.length == 1 ? '' : 's'} '
            'selected in the browser — Generate prompts there or here.');
  }

  /// Per-picture overlay status, on whichever browser is active.
  Future<void> _notifyStatus(String src, String state,
      [String message = '']) async {
    if (_gecko) {
      await GeckoBrowser.instance.notifyStatus(src, state, message);
    }
    if (_win) {
      await ChromiumStudioBrowser.instance
          .notifyStatus(src, state, message);
    }
  }

  Future<void> _toast(String msg) async {
    if (_gecko) await GeckoBrowser.instance.toast(msg);
    if (_win) await ChromiumStudioBrowser.instance.toast(msg);
  }

  Future<void> _prefetchBasket(String src) async {
    try {
      final got = await _downloadForPrompt(src);
      if (got != null) _basketBytes[src] = got.$1;
    } catch (_) {}
  }

  /// Downloads a picture for prompt generation: the app's own HTTP
  /// first (browser UA + page referer), the engine's own download
  /// as the hot-link / CORS fallback. Returns (bytes, mime) or null.
  Future<(Uint8List, String)?> _downloadForPrompt(String src) async {
    final candidates = <String>[
      if ((_basketHi[src] ?? '').isNotEmpty) _basketHi[src]!,
      src,
    ];
    for (final url in candidates) {
      try {
        final resp = await http.get(Uri.parse(url), headers: {
          'User-Agent': GeminiApi.chromeUserAgent,
          if ((_basketPage[src] ?? '').isNotEmpty)
            'Referer': _basketPage[src]!,
        });
        if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
          final ct = resp.headers['content-type'] ?? '';
          final mime = ct.contains('png')
              ? 'image/png'
              : ct.contains('webp')
                  ? 'image/webp'
                  : ct.contains('gif')
                      ? 'image/gif'
                      : 'image/jpeg';
          return (resp.bodyBytes, mime);
        }
      } catch (_) {}
    }
    if (_gecko) {
      final dataUrl = await GeckoBrowser.instance.fetchDataUrl(src);
      if (dataUrl != null) {
        final comma = dataUrl.indexOf(',');
        if (comma > 0) {
          final head = dataUrl.substring(0, comma);
          try {
            final bytes = base64Decode(dataUrl.substring(comma + 1));
            final mime = head.startsWith('data:')
                ? head.substring(5).split(';').first
                : 'image/jpeg';
            return (bytes, mime.isEmpty ? 'image/jpeg' : mime);
          } catch (_) {}
        }
      }
    }
    if (_win) {
      final f = await ChromiumStudioBrowser.instance.fetchImage(
          src, _basketPage[src] ?? '', _basketSession[src] ?? '');
      if (f != null) return f;
    }
    return null;
  }

  /// Generates one prompt for a browser picture and lands it in the
  /// Prompts card; the page overlay hears queued/running/done/error.
  Future<void> _generateFromBrowser(GeckoImageRef ref,
      {Uint8List? bytes, String mime = 'image/png'}) async {
    await _notifyStatus(ref.src, 'queued');
    try {
      var b = bytes ?? _basketBytes[ref.src];
      var m = mime;
      if (b == null) {
        await _notifyStatus(ref.src, 'running');
        final got = await _downloadForPrompt(ref.src);
        if (got == null) {
          await _notifyStatus(
              ref.src, 'error', 'Could not download the picture');
          if (mounted) {
            setState(() => _promptsStatus =
                'A picture could not be downloaded for its prompt.');
          }
          return;
        }
        b = got.$1;
        m = got.$2;
      }
      final name = Uri.tryParse(ref.src)?.pathSegments.lastOrNull ?? '';
      final prompt = await generatePromptChecked(
        bytes: b,
        name: name.isEmpty ? 'image.jpg' : name,
        mime: m,
        options: _options,
      );
      await _notifyStatus(ref.src, 'done');
      if (!mounted) return;
      setState(() {
        _readyPrompts.add(prompt);
        _promptsStatus = '${_readyPrompts.length} prompt'
            '${_readyPrompts.length == 1 ? '' : 's'} ready.';
      });
      // No auto-send here (unlike the panel flow): generation runs
      // while the user is still browsing, so prompts pile up in
      // the Prompts card and "Send to Batch Sets" sends them.
    } catch (e) {
      await _notifyStatus(ref.src, 'error', '$e');
      if (mounted) {
        setState(() => _promptsStatus = 'Prompt failed: $e');
      }
    }
  }

  /// "Generate prompts" for the whole browser selection, one by
  /// one; the dock in the page and the Prompts card both fill up.
  Future<void> _generateBasketPrompts() async {
    if (_geckoGenerating || _basket.isEmpty) return;
    _geckoGenerating = true;
    final srcs = List<String>.of(_basket);
    final readyBefore = _readyPrompts.length;
    try {
      for (final src in srcs) {
        await _generateFromBrowser(GeckoImageRef(
          src: src,
          hi: _basketHi[src] ?? '',
        ));
      }
      final done = _readyPrompts.length - readyBefore;
      if (done > 0) {
        await _toast(done == 1
            ? '1 prompt ready in the app'
            : '$done prompts ready in the app');
      }
    } finally {
      _geckoGenerating = false;
    }
  }

  /// Video frame / canvas / snipped area: the browser screenshots
  /// the region and the shot is prompted like any other picture.
  /// (Android cuts by viewport share — meta.frac; Windows by
  /// document rect — meta.rect, inside the CDP capture.)
  Future<void> _captureFromBrowser(GeckoImageRef ref) async {
    await _notifyStatus(ref.src, 'running');
    Uint8List? png;
    if (_gecko) {
      final frac = ref.meta['frac'];
      png = frac is Map
          ? await GeckoBrowser.instance
              .captureRegion(frac.cast<String, dynamic>())
          : null;
    } else if (_win) {
      png = await ChromiumStudioBrowser.instance.captureRegion(
          _basketSession[ref.src] ?? '', ref.meta);
    }
    if (png == null || png.isEmpty) {
      await _notifyStatus(
          ref.src, 'error', 'Could not capture that area');
      if (mounted) {
        setState(() => _promptsStatus = 'Capture failed — scroll the '
            'picture fully into view and try again.');
      }
      return;
    }
    await _generateFromBrowser(ref, bytes: png);
  }

  Future<void> _openBrowser() async {
    setState(() {
      _browserOpen = true;
      _promptsStatus = 'Collecting image links...';
    });
    final pick = await Navigator.of(context).push<ImageSearchPick>(
      MaterialPageRoute(
        builder: (_) => _BrowserScreen(
          promptMode: widget.promptMode,
          initialSource: _source,
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _browserOpen =
        _anyBrowserOpen);
    if (pick == null) {
      setState(() => _promptsStatus = 'No new prompts.');
      return;
    }
    switch (pick.action) {
      case 'reference':
      case 'save':
        // The Set Designer handles both directly.
        Navigator.of(context).pop(pick);
      case 'prompt':
        final text = pick.generatedPrompt?.trim() ?? '';
        if (text.isEmpty) return;
        GeneratedPromptPool.add(text);
        setState(() {
          _readyPrompts.add(text);
          _promptsStatus = 'Prompt ready.';
        });
        if (_options.autoAdd) Navigator.of(context).pop(pick);
      case 'prompts':
        final prompts = pick.generatedPrompts;
        if (prompts.isEmpty) return;
        for (final p in prompts) {
          GeneratedPromptPool.add(p);
        }
        setState(() {
          _readyPrompts.addAll(prompts);
          _promptsStatus = prompts.length == 1
              ? '1 prompt ready.'
              : '${prompts.length} prompts ready.';
        });
        if (_options.autoAdd) Navigator.of(context).pop(pick);
    }
  }

  void _sendToDesigner() {
    if (_readyPrompts.isEmpty) return;
    Navigator.of(context).pop(ImageSearchPick(
      bytes: Uint8List(0),
      name: '',
      mime: '',
      action: 'prompts',
      sourcePageUrl: '',
      generatedPrompts: List.of(_readyPrompts),
      appendPrompt: true,
    ));
  }

  Future<void> _editPrompt(int index) async {
    final ctrl = TextEditingController(text: _readyPrompts[index]);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit prompt'),
        content: TextField(
          controller: ctrl,
          maxLines: 6,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty && mounted) {
      setState(() => _readyPrompts[index] = result);
    }
  }

  Widget _cardHeader(IconData icon, String title, String subtitle) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFF1B2242),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: const Color(0xFFB9AFFF)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 16)),
              Text(subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sourceChip(String source, String label, IconData icon) {
    return ChoiceChip(
      avatar: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: _source == source,
      // Tapping a source tab opens it in the browser: the app
      // browser on Android / Windows (navigating it when it is
      // already open), the external browser elsewhere.
      onSelected: (_) {
        setState(() => _source = source);
        if (_gecko) {
          final gb = GeckoBrowser.instance;
          if (gb.isOpen) gb.open(_startUrlFor(source));
        } else if (_win) {
          final cb = ChromiumStudioBrowser.instance;
          if (cb.isOpen) cb.open(_startUrlFor(source));
        } else {
          ExternalBrowser.open(_startUrlFor(source));
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final modeKnown =
        _accountMode == 'auto' ||
            _accounts.any((a) => '${a.authUser}' == _accountMode);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.promptMode ? 'Image to Prompt' : 'Image Search'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // ---------------- Browser card ----------------
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                          child: _cardHeader(
                              Icons.travel_explore, 'Browser', _engineLabel)),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: Theme.of(context).dividerColor),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _browserOpen
                                    ? const Color(0xFF4ADE80)
                                    : Colors.grey,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(_browserOpen ? 'Open' : 'Closed',
                                style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 11),
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: Theme.of(context).dividerColor),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.search, size: 18, color: Colors.grey),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _startUrl,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _sourceChip(
                          'pinterest', 'Pinterest', Icons.push_pin_outlined),
                      _sourceChip('unsplash', 'Unsplash', Icons.photo_outlined),
                      _sourceChip(
                          'google', 'Google Images', Icons.image_search),
                      _sourceChip('lexica', 'Lexica', Icons.auto_awesome_outlined),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _openExternalHome,
                          icon: const Icon(Icons.open_in_browser, size: 18),
                          label: const Text('Open browser'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    LoginScreen(onConnected: _load),
                              ),
                            );
                            await _load();
                          },
                          icon: const Icon(Icons.login, size: 18),
                          label: const Text('Sign in'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed:
                          _browserOpen && !_appBrowser ? null : _openBrowser,
                      icon: const Icon(Icons.link, size: 18),
                      label: const Text('Collect image links & prompts'),
                    ),
                  ),
                  if (_appBrowser && _basket.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(Icons.photo_library_outlined,
                            size: 16, color: Color(0xFF4ADE80)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${_basket.length} selected in the browser',
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ),
                        TextButton(
                          onPressed:
                              _geckoGenerating ? null : _generateBasketPrompts,
                          child: const Text('Generate prompts'),
                        ),
                        TextButton(
                          onPressed: () {
                            _basket.clear();
                            _basketHi.clear();
                            _basketPage.clear();
                            _basketSession.clear();
                            _basketBytes.clear();
                            _syncBasket();
                          },
                          child: const Text('Clear'),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 4),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    leading: const Icon(Icons.help_outline, size: 20),
                    title: const Text('How it works',
                        style: TextStyle(fontSize: 13.5)),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          _gecko
                              ? '1. Tap Open browser — the built-in '
                                  'Firefox browser opens on the source '
                                  'you picked.\n'
                                  '2. In the browser, tap "Select '
                                  'pictures", then tap pictures to tick '
                                  'them (the tick selection survives '
                                  'page changes). One picture? Use its '
                                  'Prompt button instead.\n'
                                  '3. Tap Generate prompts in the '
                                  'browser dock — prompts are made in '
                                  'the background and land in the '
                                  'Prompts card below.\n'
                                  '4. Send them to Batch Sets > Prompts '
                                  'in the Set Designer from the Prompts '
                                  'card.'
                              : _win
                                  ? '1. Tap Open browser — the app\'s '
                                      'own Chrome / Edge window opens '
                                      'on the source you picked.\n'
                                      '2. Hover a picture and tick it '
                                      '(or use its Prompt button for a '
                                      'single prompt); the tick '
                                      'selection survives page '
                                      'changes.\n'
                                      '3. Click Generate prompts in '
                                      'the dock at the bottom of the '
                                      'page — prompts are made in the '
                                      'background and land in the '
                                      'Prompts card below.\n'
                                      '4. Send them to Batch Sets > '
                                      'Prompts in the Set Designer '
                                      'from the Prompts card.'
                                  : '1. Tap a source (Pinterest, Unsplash, '
                                  'Google Images, Lexica) or Open '
                                  'browser — it opens in Chrome / '
                                  'Firefox, outside the app.\n'
                                  '2. In the browser, find a picture, '
                                  'long-press / right-click it and copy '
                                  'the image link.\n'
                                  '3. Come back, open "Collect image '
                                  'links & prompts", Paste link, then '
                                  'Generate prompts — finished prompts '
                                  'land in the Prompts card below.\n'
                                  '4. With Auto-add on, they go straight '
                                  'to Batch Sets > Prompts in the Set '
                                  'Designer.',
                          style: const TextStyle(fontSize: 12.5, height: 1.55),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // ---------------- Prompts card ----------------
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _cardHeader(Icons.auto_awesome, 'Prompts',
                      '${_readyPrompts.length} ready'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.check_circle_outline,
                          size: 14, color: Color(0xFF4ADE80)),
                      const SizedBox(width: 6),
                      Text(_promptsStatus,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_readyPrompts.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: Center(
                        child: Column(
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1B2242),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(Icons.add_photo_alternate_outlined,
                                  size: 26, color: Color(0xFFB9AFFF)),
                            ),
                            const SizedBox(height: 12),
                            const Text('No prompts yet',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 15)),
                            const SizedBox(height: 6),
                            const Text(
                              'Open the browser, tap "Select pictures" and '
                              'pick the images you like.',
                              textAlign: TextAlign.center,
                              style:
                                  TextStyle(fontSize: 12.5, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    )
                  else ...[
                    for (var i = 0; i < _readyPrompts.length; i++)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.fromLTRB(10, 6, 2, 6),
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: Theme.of(context).dividerColor),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 5),
                                child: Text(
                                  _readyPrompts[i],
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12.5),
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Edit',
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              onPressed: () => _editPrompt(i),
                            ),
                            IconButton(
                              tooltip: 'Copy',
                              icon: const Icon(Icons.copy_outlined, size: 18),
                              onPressed: () {
                                Clipboard.setData(
                                    ClipboardData(text: _readyPrompts[i]));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('Prompt copied')),
                                );
                              },
                            ),
                            IconButton(
                              tooltip: 'Remove',
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () => setState(
                                  () => _readyPrompts.removeAt(i)),
                            ),
                          ],
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _sendToDesigner,
                            icon: const Icon(Icons.send_outlined, size: 18),
                            label: Text(_readyPrompts.length == 1
                                ? 'Send 1 prompt to Batch Sets'
                                : 'Send ${_readyPrompts.length} prompts to Batch Sets'),
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              setState(() => _readyPrompts.clear()),
                          child: const Text('Clear'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // ---------------- Options card ----------------
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _cardHeader(Icons.tune, 'Options', 'Prompt generation'),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Auto-add to Prompts list',
                        style: TextStyle(fontSize: 14)),
                    subtitle: const Text(
                        'Finished prompts go straight to Batch Sets > Prompts.',
                        style: TextStyle(fontSize: 12)),
                    value: _options.autoAdd,
                    onChanged: (v) async {
                      setState(() => _options.autoAdd = v);
                      await _options.save();
                    },
                  ),
                  const Text(
                    'Gemini web cookies',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFB9AFFF),
                    ),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: modeKnown ? _accountMode : 'auto',
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: 'auto',
                        child: Text('Auto - browser sign-in, else saved',
                            style: TextStyle(fontSize: 13)),
                      ),
                      for (final a in _accounts)
                        DropdownMenuItem(
                          value: '${a.authUser}',
                          child: Text('Account u/${a.authUser} — ${a.email}',
                              style: const TextStyle(fontSize: 13)),
                        ),
                    ],
                    onChanged: (v) async {
                      if (v == null) return;
                      await SessionStore.saveAccountMode(v);
                      if (mounted) setState(() => _accountMode = v);
                    },
                  ),
                  const SizedBox(height: 6),
                  SimilarityOptionsPanel(
                    options: _options,
                    onChanged: () => setState(() {}),
                    showAutoAdd: false,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The external-browser panel: a full page pushed from the Image
/// to Prompt home. It launches searches in Chrome / Firefox (no
/// embedded web view), collects image links brought back from the
/// browser, and hosts the generation sheets; results pop back to
/// the home's Prompts card (or straight through to the Designer).
class _BrowserScreen extends StatefulWidget {
  final bool promptMode;
  final String? initialSource;
  const _BrowserScreen({this.promptMode = false, this.initialSource});

  @override
  State<_BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<_BrowserScreen> {
  final TextEditingController _queryCtrl = TextEditingController();
  final TextEditingController _linkCtrl = TextEditingController();
  String _source = 'google'; // google | pinterest | unsplash | lexica

  /// The bridge back from the external browser: image links the
  /// user copied there and pasted here. Nothing is embedded in this
  /// app — pages live in Chrome / Firefox; only links cross over.
  final List<String> _links = [];

  /// Last page opened in the external browser (result context).
  String _lastUrl = '';

  late String _status = widget.promptMode
      ? 'Search opens in Chrome / Firefox. Copy an image link there '
          'and paste it back here — prompts are made inside the app.'
      : 'Search opens in Chrome / Firefox. Copy an image link there '
          'and paste it back here to use the picture.';

  @override
  void initState() {
    super.initState();
    if (widget.initialSource != null) _source = widget.initialSource!;
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    _linkCtrl.dispose();
    super.dispose();
  }

  String get _homeUrl => switch (_source) {
        'pinterest' => 'https://www.pinterest.com/',
        'unsplash' => 'https://unsplash.com/',
        'lexica' => 'https://lexica.art/',
        _ => 'https://www.google.com/search?tbm=isch&udm=2',
      };

  String get _sourceLabel => switch (_source) {
        'pinterest' => 'Pinterest',
        'unsplash' => 'Unsplash',
        'lexica' => 'Lexica',
        _ => 'Google Images',
      };

  String _searchUrl() {
    final q = _queryCtrl.text.trim();
    if (q.isEmpty) return _homeUrl;
    return switch (_source) {
      'pinterest' => pinterestSearchUrl(q),
      'unsplash' => unsplashSearchUrl(q),
      'lexica' => lexicaSearchUrl(q),
      _ => googleImagesSearchUrl(q),
    };
  }

  /// Launch the dedicated external browser process (Chrome /
  /// Firefox / default) at [url]. The app never embeds the page.
  Future<void> _openExternal(String url) async {
    final ok = await ExternalBrowser.open(url);
    if (!mounted) return;
    setState(() {
      _lastUrl = url;
      _status = ok
          ? 'Opened in your browser: $url\n'
              'Found a picture? Long-press / right-click it, copy the '
              'image link, come back here and tap "Paste link".'
          : 'No browser could be opened on this device.';
    });
  }

  void _addLink(String raw) {
    final url = raw.trim();
    if (url.isEmpty) return;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      setState(() => _status =
          'That does not look like a web link — copy the image address '
          '(it starts with https://).');
      return;
    }
    if (_links.contains(url)) {
      setState(() => _status = 'That link is already in the list.');
      return;
    }
    setState(() {
      _links.add(url);
      _linkCtrl.clear();
      _status = _links.length == 1
          ? '1 image link collected. Add more, or use it below.'
          : '${_links.length} image links collected.';
    });
  }

  /// The clipboard bridge: read an image link copied in the
  /// external browser.
  Future<void> _pasteLink() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = (data?.text ?? '').trim();
      if (text.isEmpty) {
        setState(() => _status =
            'Clipboard is empty — copy an image link in the browser first.');
        return;
      }
      _addLink(text);
    } catch (_) {
      setState(() => _status =
          'Could not read the clipboard — paste the link into the box '
          'and tap Add.');
    }
  }

  /// Pick an image stored on the device and open the same actions
  /// sheet used for linked images (reference / save / image-to-prompt).
  Future<void> _pickFromDevice() async {
    final res = await FilePicker.platform
        .pickFiles(type: FileType.image, withData: true);
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    final bytes = f.bytes ??
        (f.path != null && File(f.path!).existsSync()
            ? await File(f.path!).readAsBytes()
            : null);
    if (bytes == null || !mounted) return;
    final lower = f.name.toLowerCase();
    final mime = lower.endsWith('.png')
        ? 'image/png'
        : lower.endsWith('.webp')
            ? 'image/webp'
            : 'image/jpeg';
    await _offerActions(bytes, f.name, mime);
  }

  /// The integrated actions sheet for a downloaded / picked image.
  Future<void> _offerActions(Uint8List bytes, String name, String mime) async {
    final pick = await showModalBottomSheet<ImageSearchPick>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _ImageActionSheet(
        bytes: bytes,
        name: name,
        mime: mime,
        sourcePageUrl: _lastUrl,
      ),
    );
    if (pick != null && mounted) {
      Navigator.of(context).pop(pick);
    }
  }

  /// Download a collected link and open the actions sheet for it.
  Future<void> _downloadAndOffer(String url) async {
    setState(() => _status = 'Downloading the image...');
    try {
      final resp = await http.get(Uri.parse(url),
          headers: {'User-Agent': GeminiApi.chromeUserAgent});
      if (!mounted) return;
      if (resp.statusCode != 200) {
        setState(() => _status =
            'Download failed (HTTP ${resp.statusCode}). The site may '
            'block direct downloads — try another link.');
        return;
      }
      final contentType = resp.headers['content-type'] ?? '';
      var mime = 'image/jpeg';
      if (contentType.contains('png')) {
        mime = 'image/png';
      } else if (contentType.contains('webp')) {
        mime = 'image/webp';
      }
      var name = Uri.tryParse(url)?.pathSegments.lastOrNull ?? '';
      if (name.isEmpty || !name.contains('.')) {
        name = mime == 'image/png'
            ? 'searched_image.png'
            : mime == 'image/webp'
                ? 'searched_image.webp'
                : 'searched_image.jpg';
      }
      if (!mounted) return;
      setState(
          () => _status = 'Image downloaded. Choose what to do with it below.');
      await _offerActions(resp.bodyBytes, name, mime);
    } catch (e) {
      if (mounted) setState(() => _status = 'Download failed: $e');
    }
  }

  /// Open the batch sheet: Similarity Target + Generate prompts for
  /// every collected link; on Send, pop back to the home screen with
  /// the finished prompts for the Batch Sets box.
  Future<void> _openBatchGenerate() async {
    if (_links.isEmpty) return;
    final prompts = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _BatchPromptSheet(
        urls: List<String>.of(_links),
        sourcePageUrl: _lastUrl,
        ua: GeminiApi.chromeUserAgent,
      ),
    );
    if (prompts != null && prompts.isNotEmpty && mounted) {
      Navigator.of(context).pop(ImageSearchPick(
        bytes: Uint8List(0),
        name: '',
        mime: '',
        action: 'prompts',
        sourcePageUrl: _lastUrl,
        generatedPrompts: prompts,
        appendPrompt: true,
      ));
    }
  }

  Widget _panelSourceChip(String source, String label, IconData icon) {
    return ChoiceChip(
      avatar: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: _source == source,
      onSelected: (_) {
        setState(() => _source = source);
        _openExternal(_homeUrlFor(source));
      },
    );
  }

  String _homeUrlFor(String source) => switch (source) {
        'pinterest' => 'https://www.pinterest.com/',
        'unsplash' => 'https://unsplash.com/',
        'lexica' => 'https://lexica.art/',
        _ => 'https://www.google.com/search?tbm=isch&udm=2',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('External browser'),
        actions: [
          IconButton(
            tooltip: 'Pick from device',
            onPressed: _pickFromDevice,
            icon: const Icon(Icons.photo_library_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.open_in_browser,
                      size: 22,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Pages open in a separate Chrome / Firefox window — '
                      'this app never embeds the page. Find a picture '
                      'there, copy its image link, and bring it back '
                      'with Paste link below.',
                      style: TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _queryCtrl,
                          decoration: const InputDecoration(
                            hintText: 'Search images...',
                            prefixIcon: Icon(Icons.search, size: 20),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onSubmitted: (_) => _openExternal(_searchUrl()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () => _openExternal(_searchUrl()),
                        child: const Text('Search'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _panelSourceChip(
                          'pinterest', 'Pinterest', Icons.push_pin_outlined),
                      _panelSourceChip(
                          'unsplash', 'Unsplash', Icons.photo_outlined),
                      _panelSourceChip(
                          'google', 'Google Images', Icons.image_search),
                      _panelSourceChip('lexica', 'Lexica',
                          Icons.auto_awesome_outlined),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Tapping a source opens it in your browser. Or type a '
                    'search and tap Search.',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(_status, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.link, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Image links (${_links.length})',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      if (_links.isNotEmpty)
                        TextButton(
                          onPressed: () => setState(() {
                            _links.clear();
                            _status = 'Link list cleared.';
                          }),
                          child: const Text('Clear'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _linkCtrl,
                          decoration: const InputDecoration(
                            hintText: 'Paste an image link (https://...)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onSubmitted: _addLink,
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () => _addLink(_linkCtrl.text),
                        child: const Text('Add'),
                      ),
                    ],
                  ),
                  if (_links.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        'No links yet. In the browser, long-press (or '
                        'right-click) a picture and choose "Copy image '
                        'link", then Paste link below.',
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    )
                  else
                    for (final url in _links)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.network(
                                url,
                                width: 46,
                                height: 46,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 46,
                                  height: 46,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                                  child: const Icon(Icons.broken_image_outlined,
                                      size: 20),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                url,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Use this image',
                              onPressed: () => _downloadAndOffer(url),
                              icon: const Icon(Icons.download_outlined,
                                  size: 20),
                            ),
                            IconButton(
                              tooltip: 'Remove',
                              onPressed: () => setState(() {
                                _links.remove(url);
                                _status = 'Link removed.';
                              }),
                              icon: const Icon(Icons.close, size: 18),
                            ),
                          ],
                        ),
                      ),
                ],
              ),
            ),
          ),
        ],
      ),
      // Docked bridge actions: always reachable while links collect.
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.promptMode && _links.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _openBatchGenerate,
                      icon: const Icon(Icons.auto_awesome, size: 18),
                      label: Text(_links.length == 1
                          ? 'Generate prompt for 1 image'
                          : 'Generate prompts for ${_links.length} images'),
                    ),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pasteLink,
                      icon: const Icon(Icons.content_paste, size: 18),
                      label: const Text('Paste link'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickFromDevice,
                      icon: const Icon(Icons.photo_library_outlined,
                          size: 18),
                      label: const Text('Gallery'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _openExternal(_homeUrl),
                      icon: const Icon(Icons.open_in_browser, size: 18),
                      label: Text(_sourceLabel),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
class _ImageActionSheet extends StatefulWidget {
  final Uint8List bytes;
  final String name;
  final String mime;
  final String sourcePageUrl;
  const _ImageActionSheet({
    required this.bytes,
    required this.name,
    required this.mime,
    required this.sourcePageUrl,
  });

  @override
  State<_ImageActionSheet> createState() => _ImageActionSheetState();
}

class _ImageActionSheetState extends State<_ImageActionSheet> {
  final TextEditingController _noteCtrl = TextEditingController();
  final TextEditingController _resultCtrl = TextEditingController();
  bool _busy = false;
  String _status = '';
  bool _statusIsError = false;

  // ---- Image-to-prompt options (shared, persisted) ----
  final PromptOptions _options = PromptOptions();

  @override
  void initState() {
    super.initState();
    _options.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    _resultCtrl.dispose();
    super.dispose();
  }

  void _pop(String action, {String? prompt}) {
    Navigator.of(context).pop(ImageSearchPick(
      bytes: widget.bytes,
      name: widget.name,
      mime: widget.mime,
      action: action,
      sourcePageUrl: widget.sourcePageUrl,
      generatedPrompt: prompt,
      appendPrompt: action == 'prompt' && _options.autoAdd,
    ));
  }

  bool get _looksLikeAuthError {
    final s = _status.toLowerCase();
    return s.contains('sign in') ||
        s.contains('session') ||
        s.contains('cookie') ||
        s.contains('401') ||
        s.contains('403');
  }

  Future<void> _generate() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = 'Uploading image to your Gemini session...';
      _statusIsError = false;
    });
    try {
      final prompt = await generatePromptChecked(
        bytes: widget.bytes,
        name: widget.name,
        mime: widget.mime,
        options: _options,
        styleNote: _noteCtrl.text,
        onRewriting: () {
          if (mounted) {
            setState(() => _status =
                'That prompt reads like an earlier one — rewriting it once...');
          }
        },
      );
      if (!mounted) return;
      setState(() {
        _resultCtrl.text = prompt;
        _status = 'Prompt ready — edit it, copy it, or send it to the Set Designer.';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = 'Image-to-prompt failed: $e';
          _statusIsError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasResult = _resultCtrl.text.trim().isNotEmpty;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 14,
          right: 14,
          top: 14,
          bottom: 14 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(widget.bytes,
                    height: 190, fit: BoxFit.contain),
              ),
              const SizedBox(height: 6),
              Text(widget.name,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _pop('reference'),
                      icon: const Icon(Icons.image_outlined, size: 18),
                      label: const Text('Use as Reference'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pop('save'),
                      icon: const Icon(Icons.save_alt_outlined, size: 18),
                      label: const Text('Save a copy'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Row(
                children: [
                  Icon(Icons.auto_awesome, size: 16, color: Color(0xFF7C6CFF)),
                  SizedBox(width: 6),
                  Text('Image to Prompt',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14)),
                ],
              ),
              const SizedBox(height: 8),
              SimilarityOptionsPanel(
                options: _options,
                styleNote: _noteCtrl.text,
                onChanged: () => setState(() {}),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _noteCtrl,
                onChanged: (_) => setState(() {}),
                minLines: 1,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Style note (optional)',
                  hintText: 'e.g. AMOLED dark, neon, minimal',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _generate,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_awesome, size: 18),
                label: Text(_busy ? 'Working...' : 'Generate prompt'),
              ),
              if (_status.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(_status,
                    style: TextStyle(
                        fontSize: 12,
                        color: _statusIsError ? scheme.error : null)),
              ],
              if (_statusIsError && _looksLikeAuthError) ...[
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const LoginScreen()));
                    if (mounted) {
                      setState(() => _status =
                          'Gemini connected. Tap "Generate prompt" again.');
                    }
                  },
                  icon: const Icon(Icons.login, size: 18),
                  label: const Text('Open Gemini Login'),
                ),
              ],
              if (hasResult) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _resultCtrl,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Generated prompt',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Clipboard.setData(
                              ClipboardData(text: _resultCtrl.text.trim()));
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Prompt copied')));
                        },
                        icon: const Icon(Icons.copy, size: 15),
                        label: const Text('Copy prompt'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () =>
                            _pop('prompt', prompt: _resultCtrl.text.trim()),
                        icon: const Icon(Icons.design_services_outlined,
                            size: 15),
                        label: Text(_options.autoAdd
                            ? 'Add to Prompts list'
                            : 'Use in Set Designer'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Batch prompt generation for the multi-selected images: pick the
/// Similarity Target first, then generate one prompt per image
/// (sequential, with a per-image status), edit any result, and send
/// them all into the Batch Sets prompt box.
class _BatchPromptSheet extends StatefulWidget {
  final List<String> urls;
  final String sourcePageUrl;
  final String ua;
  const _BatchPromptSheet({
    required this.urls,
    required this.sourcePageUrl,
    required this.ua,
  });

  @override
  State<_BatchPromptSheet> createState() => _BatchPromptSheetState();
}

class _BatchItem {
  final String url;
  String status = 'Waiting';
  String error = '';
  final TextEditingController promptCtrl = TextEditingController();
  _BatchItem(this.url);
  bool get done => status == 'Done';
  bool get active =>
      status == 'Downloading' || status == 'Generating' || status == 'Rewriting';
}

class _BatchPromptSheetState extends State<_BatchPromptSheet> {
  final PromptOptions _options = PromptOptions();
  late final List<_BatchItem> _items = [
    for (final u in widget.urls) _BatchItem(u),
  ];
  bool _running = false;
  bool _stopAfterCurrent = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _options.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    for (final it in _items) {
      it.promptCtrl.dispose();
    }
    super.dispose();
  }

  int get _doneCount => _items.where((e) => e.done).length;

  Future<void> _runAll() async {
    if (_running) return;
    setState(() {
      _running = true;
      _started = true;
      _stopAfterCurrent = false;
    });
    for (final item in _items) {
      if (item.done) continue;
      if (_stopAfterCurrent) break;
      try {
        setState(() => item.status = 'Downloading');
        final resp = await http.get(Uri.parse(item.url), headers: {
          'User-Agent': widget.ua,
          'Referer': widget.sourcePageUrl,
        });
        if (resp.statusCode != 200) {
          throw Exception('Download failed (HTTP ${resp.statusCode})');
        }
        final ct = resp.headers['content-type'] ?? '';
        final mime = ct.contains('png')
            ? 'image/png'
            : ct.contains('webp')
                ? 'image/webp'
                : 'image/jpeg';
        var name = Uri.tryParse(item.url)?.pathSegments.lastOrNull ?? '';
        if (name.isEmpty || !name.contains('.')) {
          name = mime == 'image/png'
              ? 'image.png'
              : mime == 'image/webp'
                  ? 'image.webp'
                  : 'image.jpg';
        }
        if (!mounted) return;
        setState(() => item.status = 'Generating');
        final prompt = await generatePromptChecked(
          bytes: resp.bodyBytes,
          name: name,
          mime: mime,
          options: _options,
          onRewriting: () {
            if (mounted) setState(() => item.status = 'Rewriting');
          },
        );
        if (!mounted) return;
        setState(() {
          item.status = 'Done';
          item.promptCtrl.text = prompt;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          item.status = 'Failed';
          item.error = '$e';
        });
      }
    }
    if (mounted) setState(() => _running = false);
  }

  Widget _itemRow(_BatchItem item) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.network(
              item.url,
              width: 40,
              height: 40,
              fit: BoxFit.cover,
              headers: {'User-Agent': widget.ua},
              errorBuilder: (_, __, ___) => const SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(Icons.broken_image_outlined, size: 18)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.status == 'Failed'
                      ? 'Failed — ${item.error}'
                      : item.status,
                  style: TextStyle(
                    fontSize: 12,
                    color: item.status == 'Failed'
                        ? scheme.error
                        : item.done
                            ? Colors.green
                            : null,
                    fontWeight: item.done ? FontWeight.w600 : null,
                  ),
                ),
                if (item.done) ...[
                  const SizedBox(height: 4),
                  TextField(
                    controller: item.promptCtrl,
                    minLines: 2,
                    maxLines: 4,
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (item.active)
            const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 14,
          bottom: 14 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome,
                      size: 18, color: Color(0xFF7C6CFF)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                        'Generate prompts (${_items.length} images)',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                  Chip(
                    label: Text('$_doneCount ready',
                        style: const TextStyle(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SimilarityOptionsPanel(
                options: _options,
                showAutoAdd: false,
                onChanged: () => setState(() {}),
              ),
              const SizedBox(height: 6),
              for (final item in _items) _itemRow(item),
              const SizedBox(height: 10),
              if (!_started || _running)
                FilledButton.icon(
                  onPressed: _running ? null : _runAll,
                  icon: _running
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_awesome, size: 18),
                  label: Text(_running
                      ? 'Generating...'
                      : 'Generate ${_items.length} prompts'),
                ),
              if (_running)
                TextButton(
                  onPressed: () => setState(() => _stopAfterCurrent = true),
                  child: const Text('Stop after current'),
                ),
              if (_started && !_running)
                Row(
                  children: [
                    if (_doneCount < _items.length)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _runAll,
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('Retry remaining'),
                        ),
                      ),
                    if (_doneCount < _items.length)
                      const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _doneCount == 0
                            ? null
                            : () {
                                final out = <String>[
                                  for (final it in _items)
                                    if (it.done &&
                                        it.promptCtrl.text
                                            .trim()
                                            .isNotEmpty)
                                      it.promptCtrl.text.trim(),
                                ];
                                Navigator.of(context).pop(out);
                              },
                        icon: const Icon(Icons.send_outlined, size: 16),
                        label:
                            Text('Send $_doneCount prompts to Batch Sets'),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
