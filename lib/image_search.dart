// Image Search + Image-to-Prompt screen — find wallpaper ideas on
// Google Images and Pinterest inside the app's built-in Chromium
// browser, then pull the chosen picture straight into the studio:
//
//   1. Type a query, pick a source (Google Images / Pinterest), Search.
//   2. Browse in the Chromium view. Mobile UA is the default, so the
//      sites serve their responsive phone layouts; a Desktop UA chip
//      switches back any time.
//   3. Tap "Pick image from this page" — the app reads the page's
//      images (og:image + <img> tags), shows the biggest candidates,
//      and downloads the one you tap. An app-bar button does the same
//      for an image already on the device.
//   4. The image actions sheet opens right there: Use as Reference /
//      Save copy, and — integrated, no separate screen — Image to
//      Prompt: generate a prompt from the image with the signed-in
//      Gemini session, edit it, and send it to the Set Designer.
//   5. Or flip on selection mode (app-bar checkbox): tap images
//      right on the page — they highlight and stay selected in a
//      tray while you browse — then choose a Similarity Target,
//      generate prompts for all of them at once, and send the
//      results into the Batch Sets prompt box.
//
// This screen replaces the old standalone Image-to-Prompt screen and
// its separate input field: searching, picking and prompt generation
// now happen in one place.
//
// UI follows the app's existing style: same browser toolbar as the
// Gemini Login screen, ChoiceChips like the Set Designer mode chips,
// FilledButton.icon for the main action, OutlinedButton.icon for
// secondary actions.
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'external_browser.dart';
import 'gemini_api.dart';
import 'login_screen.dart';

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

/// In-page multi-select script (the reference tool's selection
/// gallery flow): while selection mode is on, tapping an image on the
/// page toggles it — violet outline + "✓ Selected" badge — instead of
/// navigating. The selected URLs live in window.__geminiSel and are
/// reported to Dart through the 'onImageSelection' JS handler after
/// every change. The Dart side is the source of truth across page
/// navigations: it re-seeds __geminiSel and calls __gselPaint after
/// each page load, so the selection is kept while browsing.
const String _selectionJs = r'''
(function () {
  if (window.__geminiSelectInstalled) { return 'already'; }
  window.__geminiSelectInstalled = true;
  window.__geminiSel = [];
  window.__geminiSelEnabled = false;
  var style = document.createElement('style');
  style.textContent =
    'img.__gsel_on{cursor:pointer!important}' +
    'img.__gsel_picked{outline:4px solid #7C6CFF!important;outline-offset:-4px}' +
    '.__gsel_badge{position:absolute;z-index:2147483647;background:#7C6CFF;color:#fff;' +
    'font:600 11px/1.4 sans-serif;padding:2px 8px;border-radius:999px;pointer-events:none}';
  document.head.appendChild(style);
  function bestSrc(img) {
    var s = img.currentSrc || img.src || '';
    try {
      var ss = img.getAttribute('srcset');
      if (ss) {
        var best = '', bw = -1;
        ss.split(',').forEach(function (p) {
          var parts = p.trim().split(/\s+/);
          var w = parts[1] ? parseInt(parts[1]) : 0;
          if (parts[0] && w >= bw) { bw = w; best = parts[0]; }
        });
        if (best) s = best;
      }
    } catch (e) {}
    return s;
  }
  function badge(img, on) {
    var id = img.__gselId || (img.__gselId = 'g' + Math.random().toString(36).slice(2));
    var old = document.querySelector('[data-gsel-for="' + id + '"]');
    if (old) old.remove();
    if (!on) return;
    var r = img.getBoundingClientRect();
    if (r.width === 0 || r.height === 0) return;
    var b = document.createElement('div');
    b.className = '__gsel_badge';
    b.setAttribute('data-gsel-for', id);
    b.textContent = '\u2713 Selected';
    b.style.left = (r.left + window.scrollX + 6) + 'px';
    b.style.top = (r.top + window.scrollY + 6) + 'px';
    document.body.appendChild(b);
  }
  window.__gselPaint = function () {
    document.querySelectorAll('.__gsel_badge').forEach(function (b) { b.remove(); });
    document.querySelectorAll('img.__gsel_picked').forEach(function (i) {
      i.classList.remove('__gsel_picked');
    });
    if (!window.__geminiSelEnabled) return;
    document.querySelectorAll('img').forEach(function (img) {
      var u = bestSrc(img);
      if (u && window.__geminiSel.indexOf(u) >= 0) {
        img.classList.add('__gsel_picked');
        badge(img, true);
      }
    });
  };
  function notify() {
    try {
      window.flutter_inappwebview.callHandler(
          'onImageSelection', JSON.stringify(window.__geminiSel));
    } catch (e) {}
  }
  function arm(img) {
    if (img.__gselArmed) return;
    img.__gselArmed = true;
    img.addEventListener('click', function (ev) {
      if (!window.__geminiSelEnabled) return;
      var url = bestSrc(img);
      if (!url || url.indexOf('data:') === 0) return;
      ev.preventDefault();
      ev.stopPropagation();
      var i = window.__geminiSel.indexOf(url);
      if (i >= 0) { window.__geminiSel.splice(i, 1); }
      else { window.__geminiSel.push(url); }
      window.__gselPaint();
      notify();
    }, true);
  }
  function armAll() { document.querySelectorAll('img').forEach(arm); }
  armAll();
  new MutationObserver(armAll).observe(
      document.documentElement, { childList: true, subtree: true });
  var scrollTick = false;
  window.addEventListener('scroll', function () {
    if (scrollTick || !window.__geminiSelEnabled) return;
    scrollTick = true;
    setTimeout(function () { scrollTick = false; window.__gselPaint(); }, 250);
  }, true);
  window.__geminiSelectSetEnabled = function (on) {
    window.__geminiSelEnabled = !!on;
    document.querySelectorAll('img').forEach(function (i) {
      i.classList.toggle('__gsel_on', !!on);
    });
    if (!on) {
      document.querySelectorAll('.__gsel_badge').forEach(function (b) { b.remove(); });
      document.querySelectorAll('img.__gsel_picked').forEach(function (i) {
        i.classList.remove('__gsel_picked');
      });
    } else {
      window.__gselPaint();
    }
  };
  window.__geminiSelectAll = function () {
    document.querySelectorAll('img').forEach(function (img) {
      var r = img.getBoundingClientRect();
      var url = bestSrc(img);
      if (!url || url.indexOf('data:') === 0) return;
      if (!((r.width >= 60 && r.height >= 60) || (img.naturalWidth >= 200))) return;
      if (window.__geminiSel.indexOf(url) < 0) window.__geminiSel.push(url);
    });
    window.__gselPaint();
    notify();
    return window.__geminiSel.length;
  };
  window.__geminiSelectClearPage = function () {
    window.__geminiSel = [];
    window.__gselPaint();
    notify();
  };
  return 'installed';
})()
''';

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
                  Text('More original',
                      style: TextStyle(fontSize: 11, color: Colors.grey)),
                  Spacer(),
                  Text('Closer to reference',
                      style: TextStyle(fontSize: 11, color: Colors.grey)),
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

class ImageSearchScreen extends StatefulWidget {
  /// Opened from the "Prompt" navigation destination / the designer's
  /// Image to Prompt button: same screen, but the help text leads with
  /// the integrated image-to-prompt flow.
  final bool promptMode;
  const ImageSearchScreen({super.key, this.promptMode = false});

  @override
  State<ImageSearchScreen> createState() => _ImageSearchScreenState();
}

class _ImageSearchScreenState extends State<ImageSearchScreen> {
  InAppWebViewController? _web;
  final TextEditingController _queryCtrl = TextEditingController();
  String _source = 'google'; // google | pinterest

  /// Mobile UA by default: Google Images / Pinterest then serve their
  /// responsive phone layouts inside the built-in browser.
  bool _mobileUa = true;
  String _currentUrl = '';
  bool _canGoBack = false;
  bool _canGoForward = false;
  bool _loading = false;
  double _progress = 0;
  bool _picking = false;

  // ---- In-page multi-select (selection gallery flow) ----
  bool _selectMode = false;
  List<String> _selectedUrls = [];
  late String _status = widget.promptMode
      ? 'Find an image (or use the gallery button above), open it, then tap "Pick image from this page" — you can generate its prompt right here.'
      : 'Search Google Images or Pinterest, open a picture you like, then tap "Pick image from this page".';

  String get _ua =>
      _mobileUa ? GeminiApi.mobileUserAgent : GeminiApi.chromeUserAgent;

  /// One settings set for the main browser AND its popup windows, so
  /// a new window behaves exactly like the window that opened it
  /// (same user agent, cookies, multiple-window support).
  InAppWebViewSettings get _browserSettings => InAppWebViewSettings(
        userAgent: _ua,
        javaScriptEnabled: true,
        domStorageEnabled: true,
        thirdPartyCookiesEnabled: true,
        supportMultipleWindows: true,
        javaScriptCanOpenWindowsAutomatically: true,
        useHybridComposition: true,
        cacheEnabled: true,
      );

  Future<void> _setMobileUa(bool mobile) async {
    if (mobile == _mobileUa) return;
    setState(() => _mobileUa = mobile);
    try {
      await _web?.setSettings(
          settings: InAppWebViewSettings(userAgent: _ua));
      await _web?.reload();
    } catch (_) {}
    setState(() => _status = mobile
        ? 'Mobile layout on: pages reload in their responsive phone view.'
        : 'Desktop layout on: pages reload as in a desktop browser.');
  }

  /// Pick an image stored on the device and open the same actions
  /// sheet used for browser picks (reference / save / image-to-prompt).
  Future<void> _pickFromDevice() async {
    final res = await FilePicker.platform
        .pickFiles(type: FileType.image, withData: true);
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    if (f.bytes == null || !mounted) return;
    final lower = f.name.toLowerCase();
    final mime = lower.endsWith('.png')
        ? 'image/png'
        : lower.endsWith('.webp')
            ? 'image/webp'
            : 'image/jpeg';
    await _offerActions(f.bytes!, f.name, mime);
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
        sourcePageUrl: _currentUrl,
      ),
    );
    if (pick != null && mounted) {
      Navigator.of(context).pop(pick);
    }
  }

  // -----------------------------------------------------------------
  // In-page multi-select: the page runs _selectionJs; Dart keeps the
  // master selection list and re-seeds the page after navigations.
  // -----------------------------------------------------------------

  Future<void> _setSelectMode(bool on) async {
    setState(() {
      _selectMode = on;
      _status = on
          ? 'Selection mode ON: tap images on the page — selected ones get a violet outline and stay in the tray while you browse.'
          : 'Selection mode off.';
    });
    if (on) {
      await _injectSelection();
    } else {
      try {
        await _web?.evaluateJavascript(
            source:
                'if (window.__geminiSelectSetEnabled) window.__geminiSelectSetEnabled(false);');
      } catch (_) {}
    }
  }

  /// Install (once) + enable the in-page selection script, then seed
  /// it with the Dart-side selection so picks survive navigation.
  Future<void> _injectSelection() async {
    final web = _web;
    if (web == null) return;
    await _injectSelectionInto(web);
  }

  Future<void> _injectSelectionInto(InAppWebViewController web) async {
    try {
      await web.evaluateJavascript(source: _selectionJs);
      await web.evaluateJavascript(
          source: 'window.__geminiSel = ${jsonEncode(_selectedUrls)};'
              'if (window.__geminiSelectSetEnabled) window.__geminiSelectSetEnabled(true);'
              'if (window.__gselPaint) window.__gselPaint();');
    } catch (_) {}
  }

  /// Links that open a new window (target=_blank / window.open —
  /// Pinterest, Unsplash and Lexica sign-ins, "open in new tab") get
  /// a real full-screen Chromium window sharing the same session and
  /// cookies, like a Chrome popup. Without this handler they
  /// silently do nothing. Selection mode works inside the popup too.
  Future<bool> _handleCreateWindow(
      InAppWebViewController controller, CreateWindowAction action) async {
    final windowId = action.windowId;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: const Text('New window'),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ),
          body: InAppWebView(
            windowId: windowId,
            initialSettings: _browserSettings,
            onWebViewCreated: (popup) {
              popup.addJavaScriptHandler(
                handlerName: 'onImageSelection',
                callback: (args) {
                  if (args.isNotEmpty) {
                    _applySelectionFromPage(parseSelectionUrls(args.first));
                  }
                },
              );
            },
            onLoadStop: (popup, url) async {
              if (_selectMode) await _injectSelectionInto(popup);
            },
            onCreateWindow: _handleCreateWindow,
            onCloseWindow: (_) {
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
          ),
        ),
      ),
    );
    if (_web != null) await _refreshNavState(_web!);
    return true;
  }

  void _applySelectionFromPage(List<String> urls) {
    if (!mounted) return;
    setState(() => _selectedUrls = urls);
  }

  Future<void> _removeSelected(String url) async {
    setState(
        () => _selectedUrls = _selectedUrls.where((u) => u != url).toList());
    try {
      await _web?.evaluateJavascript(
          source:
              'if (window.__geminiSel) { window.__geminiSel = window.__geminiSel.filter(function(u){ return u !== ${jsonEncode(url)}; }); if (window.__gselPaint) window.__gselPaint(); }');
    } catch (_) {}
  }

  Future<void> _clearSelected() async {
    setState(() => _selectedUrls = []);
    try {
      await _web?.evaluateJavascript(
          source:
              'if (window.__geminiSelectClearPage) window.__geminiSelectClearPage();');
    } catch (_) {}
  }

  Future<void> _selectAllOnPage() async {
    try {
      await _web?.evaluateJavascript(
          source: 'if (window.__geminiSelectAll) window.__geminiSelectAll();');
    } catch (_) {}
  }

  /// Open the batch sheet: Similarity Target + Generate prompts for
  /// every selected image; on Send, pop back to the home screen with
  /// the finished prompts for the Batch Sets box.
  Future<void> _openBatchGenerate() async {
    if (_selectedUrls.isEmpty) return;
    final prompts = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _BatchPromptSheet(
        urls: List<String>.of(_selectedUrls),
        sourcePageUrl: _currentUrl,
        ua: _ua,
      ),
    );
    if (prompts != null && prompts.isNotEmpty && mounted) {
      Navigator.of(context).pop(ImageSearchPick(
        bytes: Uint8List(0),
        name: '',
        mime: '',
        action: 'prompts',
        sourcePageUrl: _currentUrl,
        generatedPrompts: prompts,
        appendPrompt: true,
      ));
    }
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  String get _homeUrl => switch (_source) {
        'pinterest' => 'https://www.pinterest.com/',
        'unsplash' => 'https://unsplash.com/',
        'lexica' => 'https://lexica.art/',
        _ => 'https://www.google.com/search?tbm=isch&udm=2',
      };

  Future<void> _runSearch() async {
    final q = _queryCtrl.text.trim();
    final url = q.isEmpty
        ? _homeUrl
        : switch (_source) {
            'pinterest' => pinterestSearchUrl(q),
            'unsplash' => unsplashSearchUrl(q),
            'lexica' => lexicaSearchUrl(q),
            _ => googleImagesSearchUrl(q),
          };
    await _web?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  /// Dedicated browser intent: continue this page in a separate real
  /// Chrome window (the user's Chrome session). On Windows the
  /// window size follows the layout mode — phone-sized in Mobile UA
  /// mode, desktop-sized otherwise. The in-app browser keeps its
  /// page, history and selection untouched.
  Future<void> _openInChromeExternal() async {
    final url = _currentUrl.isEmpty ? _homeUrl : _currentUrl;
    final ok = await ExternalBrowser.openInChrome(
      url,
      windowWidth: _mobileUa ? 430 : 1400,
      windowHeight: _mobileUa ? 932 : 920,
    );
    if (!mounted) return;
    setState(() => _status = ok
        ? 'Opened in Chrome — a separate window with your Chrome session. This in-app page and your selection stay as they are.'
        : 'Could not open Chrome on this device.');
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
                        headers: {'User-Agent': _ua},
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
    final resp =
        await http.get(Uri.parse(c.url), headers: {'User-Agent': _ua});
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
    setState(() => _status = 'Image downloaded. Choose what to do with it below.');
    await _offerActions(resp.bodyBytes, name, mime);
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
          IconButton(
            tooltip: 'Open this page in Chrome (separate window)',
            visualDensity: VisualDensity.compact,
            onPressed: _openInChromeExternal,
            icon: const Icon(Icons.open_in_browser, size: 20),
          ),
        ],
      ),
    );
  }

  /// The selection tray (the circled card in the reference): kept
  /// picks with per-image remove, Generate prompts and Clear.
  Widget _selectionTray() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 2, 12, 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, size: 18, color: scheme.primary),
              const SizedBox(width: 6),
              Text('${_selectedUrls.length} selected',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              TextButton(
                onPressed: _selectAllOnPage,
                child: const Text('Select all on page'),
              ),
            ],
          ),
          const Text(
              'Kept while you browse — pick a Similarity Target, then generate.',
              style: TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 8),
          SizedBox(
            height: 56,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _selectedUrls.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (ctx, i) {
                final url = _selectedUrls[i];
                return Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        url,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        headers: {'User-Agent': _ua},
                        errorBuilder: (_, __, ___) => Container(
                          width: 56,
                          height: 56,
                          color: scheme.surface,
                          child: const Icon(Icons.broken_image_outlined,
                              size: 20),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: InkWell(
                        onTap: () => _removeSelected(url),
                        child: Container(
                          decoration: const BoxDecoration(
                              color: Colors.black54, shape: BoxShape.circle),
                          padding: const EdgeInsets.all(2),
                          child: const Icon(Icons.close,
                              size: 13, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _openBatchGenerate,
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: const Text('Generate prompts'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _clearSelected,
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Clear'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.promptMode ? 'Image to Prompt' : 'Image Search'),
        actions: [
          IconButton(
            tooltip: _selectMode
                ? 'Selection mode ON — tap images on the page to select them'
                : 'Select multiple images on the page',
            onPressed: () => _setSelectMode(!_selectMode),
            icon: Icon(
              _selectMode
                  ? Icons.check_box
                  : Icons.check_box_outline_blank,
              color: _selectMode
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
          ),
          IconButton(
            tooltip: 'Use an image from this device',
            onPressed: _pickFromDevice,
            icon: const Icon(Icons.add_photo_alternate_outlined),
          ),
        ],
      ),
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
                    label:
                        const Text('Pinterest', style: TextStyle(fontSize: 12)),
                    selected: _source == 'pinterest',
                    onSelected: (_) {
                      setState(() => _source = 'pinterest');
                      _runSearch();
                    },
                  ),
                  ChoiceChip(
                    label:
                        const Text('Unsplash', style: TextStyle(fontSize: 12)),
                    selected: _source == 'unsplash',
                    onSelected: (_) {
                      setState(() => _source = 'unsplash');
                      _runSearch();
                    },
                  ),
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
                        const Text('Lexica', style: TextStyle(fontSize: 12)),
                    selected: _source == 'lexica',
                    onSelected: (_) {
                      setState(() => _source = 'lexica');
                      _runSearch();
                    },
                  ),
                  const SizedBox(width: 10),
                  ChoiceChip(
                    avatar: const Icon(Icons.smartphone_outlined, size: 14),
                    label:
                        const Text('Mobile', style: TextStyle(fontSize: 12)),
                    selected: _mobileUa,
                    onSelected: (_) => _setMobileUa(true),
                  ),
                  ChoiceChip(
                    avatar: const Icon(Icons.desktop_windows_outlined,
                        size: 14),
                    label:
                        const Text('Desktop', style: TextStyle(fontSize: 12)),
                    selected: !_mobileUa,
                    onSelected: (_) => _setMobileUa(false),
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
                  initialSettings: _browserSettings,
                  onCreateWindow: _handleCreateWindow,
                  onWebViewCreated: (controller) {
                    _web = controller;
                    controller.addJavaScriptHandler(
                      handlerName: 'onImageSelection',
                      callback: (args) {
                        if (args.isNotEmpty) {
                          _applySelectionFromPage(
                              parseSelectionUrls(args.first));
                        }
                      },
                    );
                  },
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
                    if (_selectMode) await _injectSelection();
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
          if (_selectedUrls.isNotEmpty) _selectionTray(),
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

/// Integrated actions for one picked image: use it as the designer
/// reference, save a copy — or generate a prompt from it right here
/// with the signed-in Gemini session (the flow that used to live on
/// the standalone Image-to-Prompt screen).
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
