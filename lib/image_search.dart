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
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chrome_cdp.dart';
import 'external_browser.dart';
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
    var payload = JSON.stringify(window.__geminiSel);
    // Standalone Chrome engine: a CDP binding is the callback home.
    try {
      if (typeof window.geminiBridge === 'function') {
        window.geminiBridge(payload);
        return;
      }
    } catch (e) {}
    try {
      window.flutter_inappwebview.callHandler('onImageSelection', payload);
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
/// account choice + the Similarity Target panel). The browser
/// itself is a pushed page ([_BrowserScreen]).
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
  String _promptsStatus = 'Browser closed.';
  bool _browserOpen = false;
  String _source = 'pinterest';
  String _accountMode = 'auto';
  List<GeminiAccount> _accounts = [];
  bool _chromeEnginePref = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _options.load();
    final mode = await SessionStore.loadAccountMode();
    final accounts = await SessionStore.loadDiscoveredAccounts();
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _accountMode = mode;
      _accounts = accounts;
      _chromeEnginePref = prefs.getBool('searchChromeEngine') == true;
    });
  }

  String get _startUrl => switch (_source) {
        'pinterest' => 'https://www.pinterest.com/',
        'unsplash' => 'https://unsplash.com/',
        'lexica' => 'https://lexica.art/',
        _ => 'https://www.google.com/search?tbm=isch&udm=2',
      };

  String get _engineLabel => (Platform.isWindows && _chromeEnginePref)
      ? 'Standalone Chrome window engine'
      : 'Built-in Chromium engine';

  Future<void> _openBrowser() async {
    setState(() {
      _browserOpen = true;
      _promptsStatus = 'Browser open.';
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
    setState(() => _browserOpen = false);
    if (pick == null) {
      setState(() => _promptsStatus = 'Browser closed.');
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
      onSelected: (_) => setState(() => _source = source),
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
                          onPressed: _browserOpen ? null : _openBrowser,
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
                  const SizedBox(height: 4),
                  const ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    leading: Icon(Icons.help_outline, size: 20),
                    title: Text('How it works',
                        style: TextStyle(fontSize: 13.5)),
                    children: [
                      Padding(
                        padding: EdgeInsets.only(bottom: 10),
                        child: Text(
                          '1. Tap Open browser and search Pinterest, Unsplash, '
                          'Google Images or Lexica.\n'
                          '2. In the browser, turn on Select pictures and tap '
                          'the images you like — they collect in the tray.\n'
                          '3. Tap Generate prompts there; finished prompts '
                          'land in the Prompts card below.\n'
                          '4. With Auto-add on, they go straight to Batch '
                          'Sets > Prompts in the Set Designer.',
                          style: TextStyle(fontSize: 12.5, height: 1.55),
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

/// The browser itself: a full page pushed from the Image to Prompt
/// home. Search, pick, selection tray and the generation sheets all
/// live here; results pop back to the home's Prompts card (or
/// straight through to the Set Designer).
class _BrowserScreen extends StatefulWidget {
  final bool promptMode;
  final String? initialSource;
  const _BrowserScreen({this.promptMode = false, this.initialSource});

  @override
  State<_BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<_BrowserScreen> {
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

  // ---- Standalone Chrome engine (Windows, CDP) ----
  // When on, THIS screen's browsing tasks run in a real standalone
  // Chrome window driven over the DevTools protocol instead of the
  // embedded viewer: navigation, image extraction and the selection
  // overlay all execute in that window, and selections stream back
  // live through a CDP binding callback. Windows-only (Android gives
  // apps no channel into the separate Chrome app).
  bool _chromeEngine = false;
  ChromePage? _chromePage;
  StreamSubscription<CdpFrame>? _bindingSub;

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
      if (_chromeEngine) {
        await _ensureChromePage();
        await _cdpInjectSelection();
      } else {
        await _injectSelection();
      }
    } else {
      await _evalInPage(
          'if (window.__geminiSelectSetEnabled) window.__geminiSelectSetEnabled(false);');
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
    await _evalInPage(
        'if (window.__geminiSel) { window.__geminiSel = window.__geminiSel.filter(function(u){ return u !== ${jsonEncode(url)}; }); if (window.__gselPaint) window.__gselPaint(); }');
  }

  Future<void> _clearSelected() async {
    setState(() => _selectedUrls = []);
    await _evalInPage(
        'if (window.__geminiSelectClearPage) window.__geminiSelectClearPage();');
  }

  Future<void> _selectAllOnPage() async {
    await _evalInPage(
        'if (window.__geminiSelectAll) window.__geminiSelectAll();');
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
  void initState() {
    super.initState();
    if (widget.initialSource != null) _source = widget.initialSource!;
    _loadEnginePref();
  }

  Future<void> _loadEnginePref() async {
    if (!Platform.isWindows) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('searchChromeEngine') == true && mounted) {
      setState(() => _chromeEngine = true);
      await _ensureChromePage();
    }
  }

  @override
  void dispose() {
    _bindingSub?.cancel();
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
    if (_chromeEngine) {
      final page = await _ensureChromePage();
      if (page == null) return;
      try {
        await page.navigate(url);
        if (mounted) {
          setState(() {
            _currentUrl = url;
            _status = 'Chrome window: $url';
          });
        }
      } catch (e) {
        if (mounted) setState(() => _status = 'Chrome navigation failed: $e');
      }
      return;
    }
    await _web?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  // ---- Standalone Chrome engine plumbing ----

  Future<void> _setEngine(bool chrome) async {
    if (!Platform.isWindows) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('searchChromeEngine', chrome);
    setState(() => _chromeEngine = chrome);
    if (chrome) {
      final page = await _ensureChromePage();
      if (page != null && mounted) {
        setState(() => _status =
            'Chrome window engine ON: searches, picking and selection now run in the standalone Chrome window. Selections stream back here automatically.');
      }
    } else if (mounted) {
      setState(() => _status = 'Built-in browser engine ON.');
    }
  }

  /// Launch (once) the standalone Chrome window and attach a page;
  /// also pushes the app cookie jar into its profile and subscribes
  /// to the selection binding callback.
  Future<ChromePage?> _ensureChromePage() async {
    if (!Platform.isWindows) return null;
    if (_chromePage != null && ChromeControl.shared.isLive) {
      return _chromePage;
    }
    final docs = await getApplicationDocumentsDirectory();
    final profile = '${docs.path}${Platform.pathSeparator}GeminiHDStudio'
        '${Platform.pathSeparator}ChromeProfile';
    final ok = await ChromeControl.shared.ensure(
      profileDir: profile,
      width: _mobileUa ? 430 : 1400,
      height: _mobileUa ? 932 : 920,
    );
    if (!ok) {
      if (mounted) {
        setState(() {
          _chromeEngine = false;
          _status =
              'Standalone Chrome could not be started (Chrome/Edge not found) — using the built-in browser.';
        });
      }
      return null;
    }
    _chromePage = await ChromeControl.shared.openPage(_homeUrl);
    final page = _chromePage;
    if (page == null) return null;
    try {
      await page.addBinding('geminiBridge');
    } catch (_) {}
    _bindingSub ??=
        ChromeControl.shared.cdp!.on('Runtime.bindingCalled').listen((frame) {
      if (frame.params['name'] == 'geminiBridge') {
        _applySelectionFromPage(
            parseSelectionUrls(frame.params['payload']));
      }
    });
    // Share the app jar with the Chrome profile (opens signed-in).
    try {
      final jar = await SessionStore.allCookiesHeader();
      if (jar.isNotEmpty) {
        await ChromeControl.shared.setCookies(cdpCookiesFromHeader(jar));
      }
    } catch (_) {}
    return page;
  }

  /// Run JS in whichever browser engine is active.
  Future<void> _evalInPage(String js) async {
    try {
      if (_chromeEngine) {
        await _chromePage?.evaluate(js);
      } else {
        await _web?.evaluateJavascript(source: js);
      }
    } catch (_) {}
  }

  /// Mirror of [_injectSelectionInto] for the Chrome window.
  Future<void> _cdpInjectSelection() async {
    final page = _chromePage;
    if (page == null) return;
    try {
      await page.evaluate(_selectionJs);
      await page.evaluate('window.__geminiSel = ${jsonEncode(_selectedUrls)};'
          'if (window.__geminiSelectSetEnabled) window.__geminiSelectSetEnabled(true);'
          'if (window.__gselPaint) window.__gselPaint();');
    } catch (_) {}
  }

  /// Pull the Chrome profile's Google cookies into the app jar —
  /// signing in inside the Chrome window logs the app in too.
  Future<void> _syncLoginFromChrome() async {
    if (!ChromeControl.shared.isLive) {
      setState(
          () => _status = 'Chrome window is not running yet — search first.');
      return;
    }
    try {
      final cookies = await ChromeControl.shared.allCookies();
      final header = cookieHeaderFromCdp(cookies, ['google.com']);
      if (SessionStore.cookieHeaderLooksLoggedIn(header)) {
        await SessionStore.saveCookieForUser(0, header);
        if (mounted) {
          setState(() => _status =
              'Gemini session synced from the Chrome window into the app. The Studio tab can generate now.');
        }
      } else if (mounted) {
        setState(() => _status =
            'No Google login found in the Chrome window yet. Sign in at gemini.google.com there, then sync again.');
      }
    } catch (e) {
      if (mounted) setState(() => _status = 'Cookie sync failed: $e');
    }
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
    if (_picking) return;
    if (!_chromeEngine && _web == null) return;
    setState(() => _picking = true);
    try {
      Object? raw;
      if (_chromeEngine) {
        final page = await _ensureChromePage();
        if (page == null) {
          if (mounted) {
            setState(() => _status = 'Chrome window is not ready yet.');
          }
          return;
        }
        raw = await page.evaluate(_extractImagesJs);
      } else {
        raw = await _web!.evaluateJavascript(source: _extractImagesJs);
      }
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

  /// Shown in place of the embedded view while the standalone
  /// Chrome engine drives browsing: the page lives in the Chrome
  /// window; this panel is the control + status surface.
  Widget _chromePanel() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.open_in_browser, size: 44),
              const SizedBox(height: 10),
              const Text(
                'The standalone Chrome window is the browser now.',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              const SizedBox(height: 6),
              Text(
                _currentUrl.isEmpty
                    ? 'Use Search above — pages open in the Chrome window.'
                    : 'Current page: $_currentUrl',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              const Text(
                'Pick image, selection mode and the tray all work from '
                'here — selections in the Chrome window appear in the '
                'tray automatically. Sign-ins in that window persist '
                'in its profile, and its Google session can be synced '
                'into the app:',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      final page = await _ensureChromePage();
                      await page?.navigate(
                          'https://gemini.google.com/app');
                      if (mounted) {
                        setState(() => _currentUrl =
                            'https://gemini.google.com/app');
                      }
                    },
                    icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                    label: const Text('Open Gemini in Chrome'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _syncLoginFromChrome,
                    icon: const Icon(Icons.sync_outlined, size: 18),
                    label: const Text('Sync login from Chrome'),
                  ),
                ],
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
        title: const Text('Browser'),
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
                  if (Platform.isWindows) ...[
                    const SizedBox(width: 10),
                    ChoiceChip(
                      avatar: const Icon(Icons.web_asset_outlined, size: 14),
                      label: const Text('App browser',
                          style: TextStyle(fontSize: 12)),
                      selected: !_chromeEngine,
                      onSelected: (_) => _setEngine(false),
                    ),
                    ChoiceChip(
                      avatar: const Icon(Icons.open_in_browser, size: 14),
                      label: const Text('Chrome window',
                          style: TextStyle(fontSize: 12)),
                      selected: _chromeEngine,
                      onSelected: (_) => _setEngine(true),
                    ),
                  ],
                ],
              ),
            ),
          ),
          _browserToolbar(),
          if (_progress > 0 && _progress < 1)
            LinearProgressIndicator(value: _progress),
          Expanded(
            child: _chromeEngine ? _chromePanel() : Container(
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
