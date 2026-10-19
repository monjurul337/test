import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/cover.dart';
import 'src/checklist.dart';
import 'src/metadata.dart';
import 'src/epub.dart';
import 'src/gemini.dart';
import 'src/gemini_web.dart';
import 'src/llm.dart';
import 'src/preview.dart';
import 'src/studio.dart';
import 'src/writer.dart';

/// Build profile baked in by CI: `--dart-define=BUILD=<profile>`
const String kBuildProfile = String.fromEnvironment('BUILD', defaultValue: 'dev');
const String kAppName = 'Book Generator';

/// Yellow-on-black house style. The background is true black with only a
/// breath of warmth in the corners, so the gold reads as the only colour.
const Color kGold = Color(0xFFFFC83D);
const Color kGoldSoft = Color(0xFFFFE08A);
const Color kInk = Color(0xFF000000);
const Color kPanel = Color(0xFF0C0C0C);
const Color kField = Color(0xFF070707);

const LinearGradient kAppGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: <Color>[
    Color(0xFF080705),
    Color(0xFF000000),
    Color(0xFF0A0804),
    Color(0xFF000000),
  ],
  stops: <double>[0.0, 0.38, 0.72, 1.0],
);

/// Small helper so the card shape is declared once.
class RoundedCornerShape12 {
  static final RoundedRectangleBorder shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
    side: BorderSide(color: kGold.withValues(alpha: 0.14)),
  );
}
const String kTagline = 'Meta Hawladar Team';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BookGeneratorApp());
}

class BookGeneratorApp extends StatelessWidget {
  const BookGeneratorApp({super.key});

  OutlineInputBorder _border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c, width: w),
      );

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: kGold,
      brightness: Brightness.dark,
    ).copyWith(
      primary: kGold,
      secondary: kGoldSoft,
      surface: kPanel,
      onSurface: const Color(0xFFF3ECDC),
      outline: const Color(0xFF3A3630),
    );
    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: Colors.transparent,
        dividerTheme: DividerThemeData(
          color: kGold.withValues(alpha: 0.12),
          space: 24,
          thickness: 1,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: kPanel,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedCornerShape12.shape,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: const Color(0xFF0A0A0A),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: kGold.withValues(alpha: 0.16)),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xFF151310),
          contentTextStyle: const TextStyle(color: Color(0xFFF3ECDC)),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: kGold.withValues(alpha: 0.2)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: kField,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: _border(const Color(0xFF2A2724)),
          enabledBorder: _border(const Color(0xFF2A2724)),
          focusedBorder: _border(kGold, 1.6),
          disabledBorder: _border(const Color(0xFF1C1A18)),
          labelStyle: const TextStyle(color: Color(0xFFBCB09A)),
          floatingLabelStyle: const TextStyle(color: kGold),
          helperStyle: const TextStyle(color: Color(0xFF8A8172), fontSize: 11.5),
          hintStyle: const TextStyle(color: Color(0xFF6A6358)),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            textStyle:
                const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: kGoldSoft,
            side: BorderSide(color: kGold.withValues(alpha: 0.28)),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: kGold),
        ),
        segmentedButtonTheme: SegmentedButtonThemeData(
          style: ButtonStyle(
            shape: WidgetStatePropertyAll<OutlinedBorder>(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            side: WidgetStatePropertyAll<BorderSide>(
              BorderSide(color: kGold.withValues(alpha: 0.24)),
            ),
            padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
              EdgeInsets.symmetric(vertical: 13),
            ),
          ),
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: kGold,
          linearMinHeight: 6,
        ),
        listTileTheme: const ListTileThemeData(
          iconColor: kGold,
          textColor: Color(0xFFE6DCC6),
        ),
        expansionTileTheme: ExpansionTileThemeData(
          iconColor: kGold,
          collapsedIconColor: kGold.withValues(alpha: 0.7),
          shape: const Border(),
          collapsedShape: const Border(),
        ),
      ),
      builder: (BuildContext context, Widget? child) => ColoredBox(
        color: kInk,
        child: DecoratedBox(
          decoration: const BoxDecoration(gradient: kAppGradient),
          child: child ?? const SizedBox.shrink(),
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _topic = TextEditingController();
  final TextEditingController _author =
      TextEditingController(text: 'Md Monjurul Islam');
  final TextEditingController _chapters = TextEditingController(text: '16');
  final TextEditingController _words = TextEditingController(text: '15000');
  final TextEditingController _pages = TextEditingController(text: '60');
  final TextEditingController _note = TextEditingController();
  final TextEditingController _bio = TextEditingController();
  final TextEditingController _alsoBy = TextEditingController();
  final TextEditingController _publisher = TextEditingController();
  final TextEditingController _newsletter = TextEditingController();
  final ScrollController _logScroll = ScrollController();

  String _apiKey = '';
  String _nvKey = '';
  String _webSession = '';
  String _provider = Providers.gemini;

  /// The keys that belong to the provider in use right now. The web
  /// provider's "key" is the exported Gemini session JSON.
  String get _activeKeys =>
      _provider == Providers.nvidia
          ? _nvKey
          : _provider == Providers.web
              ? _webSession
              : _apiKey;

  int get _keyCount => _provider == Providers.web
      ? GeminiWebSession.countCookies(_activeKeys)
      : KeyPool.parse(_activeKeys).length;

  BookExtras get _extras => BookExtras(
        authorBio: _bio.text.trim(),
        alsoBy: _alsoBy.text
            .split('\n')
            .map((String t) => t.trim())
            .where((String t) => t.isNotEmpty)
            .toList(),
        publisher: _publisher.text.trim(),
        newsletter: _newsletter.text.trim(),
      );

  /// One book per non-empty line, so a whole batch can be queued at once.
  List<String> get _topics => _topic.text
      .split('\n')
      .map((String t) => t.trim())
      .where((String t) => t.isNotEmpty)
      .toList();
  String _model = Gemini.models.first;
  String _theme = 'auto';
  bool _fiction = true;
  String _outputRoot = '';
  bool _busy = false;
  double _progress = 0;
  final List<String> _log = <String>[];
  BookResult? _result;
  final List<BookResult> _results = <BookResult>[];
  String? _batchZip;
  int _bookIndex = 0;
  int _bookTotal = 1;
  BookWriter? _writer;

  /// Guards the two-way pages <-> words sync from looping.
  bool _syncing = false;

  /// Google Play Books counts roughly this many words per printed page.
  static const int wordsPerPage = 250;

  @override
  void initState() {
    super.initState();
    _topic.addListener(() => setState(() {}));
    _words.addListener(_wordsChanged);
    _pages.addListener(_pagesChanged);
    _load();
  }

  void _wordsChanged() {
    if (_syncing) return;
    final int w = int.tryParse(_words.text.trim()) ?? 0;
    if (w <= 0) return;
    _syncing = true;
    _pages.text = (w / wordsPerPage).round().clamp(1, 100000).toString();
    _syncing = false;
  }

  void _pagesChanged() {
    if (_syncing) return;
    final int pages = int.tryParse(_pages.text.trim()) ?? 0;
    if (pages <= 0) return;
    _syncing = true;
    _words.text = (pages * wordsPerPage).toString();
    _syncing = false;
  }

  @override
  void dispose() {
    _topic.dispose();
    _author.dispose();
    _chapters.dispose();
    _words.removeListener(_wordsChanged);
    _words.dispose();
    _pages.removeListener(_pagesChanged);
    _pages.dispose();
    _note.dispose();
    _bio.dispose();
    _alsoBy.dispose();
    _publisher.dispose();
    _newsletter.dispose();
    _logScroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    String root = p.getString('outputRoot') ?? '';
    if (root.isEmpty) {
      final Directory docs = await getApplicationDocumentsDirectory();
      root = '${docs.path}${Platform.pathSeparator}BookGenerator';
    }
    if (!mounted) return;
    setState(() {
      _apiKey = p.getString('apiKey') ?? '';
      _nvKey = p.getString('nvKey') ?? '';
      _webSession = p.getString('webSession') ?? '';
      _provider = p.getString('provider') ?? Providers.gemini;
      _model = Providers.fixModel(
          _provider, p.getString('model') ?? Providers.defaultModel(_provider));
      _author.text = p.getString('author') ?? _author.text;
      _bio.text = p.getString('bio') ?? '';
      _alsoBy.text = p.getString('alsoBy') ?? '';
      _publisher.text = p.getString('publisher') ?? '';
      _newsletter.text = p.getString('newsletter') ?? '';
      _outputRoot = root;
    });
  }

  Future<void> _save() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.setString('apiKey', _apiKey);
    await p.setString('nvKey', _nvKey);
    await p.setString('webSession', _webSession);
    await p.setString('provider', _provider);
    await p.setString('model', _model);
    await p.setString('author', _author.text.trim());
    await p.setString('bio', _bio.text.trim());
    await p.setString('alsoBy', _alsoBy.text.trim());
    await p.setString('publisher', _publisher.text.trim());
    await p.setString('newsletter', _newsletter.text.trim());
    await p.setString('outputRoot', _outputRoot);
  }

  void _addLog(String message) {
    setState(() {
      _log.add(message);
      if (_log.length > 400) _log.removeAt(0);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScroll.hasClients) {
        _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _pickFolder() async {
    final String? dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Where should finished books be saved?',
    );
    if (dir != null) {
      setState(() => _outputRoot = dir);
      await _save();
    }
  }

  Future<void> _editKey() async {
    final TextEditingController g = TextEditingController(text: _apiKey);
    final TextEditingController n = TextEditingController(text: _nvKey);
    final TextEditingController w = TextEditingController(text: _webSession);
    bool testing = false;
    String testMsg = '';
    final List<String>? value = await showDialog<List<String>>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('API keys & session'),
        content: SizedBox(
          width: 540,
          child: StatefulBuilder(
            builder: (BuildContext _, void Function(void Function()) setLocal) {
              final int gc = KeyPool.parse(g.text).length;
              final int nc = KeyPool.parse(n.text).length;
              final int wc = GeminiWebSession.countCookies(w.text);
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'Paste as many keys as you like - one per line. The app '
                      'rotates through them and parks any key that hits its '
                      'rate limit, so a long book keeps writing. Keys are '
                      'stored only on this device.',
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: g,
                      autofocus: _provider == Providers.gemini,
                      maxLines: 5,
                      minLines: 2,
                      onChanged: (_) => setLocal(() {}),
                      decoration: InputDecoration(
                        labelText: 'Google Gemini keys',
                        helperText: gc == 0
                            ? 'From aistudio.google.com/apikey'
                            : '$gc key${gc == 1 ? '' : 's'} detected',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: n,
                      autofocus: _provider == Providers.nvidia,
                      maxLines: 5,
                      minLines: 2,
                      onChanged: (_) => setLocal(() {}),
                      decoration: InputDecoration(
                        labelText: 'NVIDIA keys (nvapi-...)',
                        helperText: nc == 0
                            ? 'From build.nvidia.com'
                            : '$nc key${nc == 1 ? '' : 's'} detected',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: w,
                      autofocus: _provider == Providers.web,
                      maxLines: 6,
                      minLines: 3,
                      onChanged: (_) => setLocal(() {}),
                      decoration: InputDecoration(
                        labelText: 'Gemini web session JSON',
                        helperText: wc == 0
                            ? 'Export the cookies of gemini.google.com with a '
                                'cookie editor - Playwright storageState or a '
                                'browser-extension cookie array'
                            : '$wc cookie${wc == 1 ? '' : 's'} detected',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: <Widget>[
                        TextButton.icon(
                          onPressed: testing
                              ? null
                              : () async {
                                  void update(String msg, {bool done = false}) {
                                    if (ctx.mounted) {
                                      setLocal(() {
                                        testing = !done;
                                        testMsg = msg;
                                      });
                                    }
                                  }

                                  update('Connecting to gemini.google.com...');
                                  GeminiWeb? web;
                                  try {
                                    web = GeminiWeb(w.text);
                                    final GeminiWebTestResult r = await web
                                        .test()
                                        .timeout(const Duration(seconds: 150));
                                    update(r.message, done: true);
                                  } on GeminiWebException catch (e) {
                                    update(e.message, done: true);
                                  } catch (e) {
                                    update('Test failed: $e', done: true);
                                  } finally {
                                    web?.dispose();
                                  }
                                },
                          icon: testing
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))
                              : const Icon(Icons.wifi, size: 18),
                          label: const Text('Test session'),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            testMsg,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(ctx).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, <String>[
              KeyPool.parse(g.text).join('\n'),
              KeyPool.parse(n.text).join('\n'),
              w.text,
            ]),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value != null) {
      setState(() {
        _apiKey = value[0];
        _nvKey = value[1];
        _webSession = value[2];
      });
      await _save();
    }
  }

  Future<void> _generate() async {
    final List<String> topics = _topics;
    if (topics.isEmpty) {
      _snack('Type a topic first.');
      return;
    }
    if (_activeKeys.isEmpty) {
      await _editKey();
      if (_activeKeys.isEmpty) return;
    }
    final int chapters = int.tryParse(_chapters.text.trim()) ?? 16;
    final int words = int.tryParse(_words.text.trim()) ?? 15000;
    if (chapters < 1 || chapters > 60) {
      _snack('Chapters must be between 1 and 60.');
      return;
    }
    if (words < 2000 || words > 150000) {
      _snack('Total words must be between 2,000 and 150,000.');
      return;
    }

    await _save();
    setState(() {
      _busy = true;
      _progress = 0;
      _log.clear();
      _result = null;
      _results.clear();
      _batchZip = null;
      _bookTotal = topics.length;
      _bookIndex = 0;
    });

    final BookWriter writer = BookWriter(
        apiKey: _activeKeys, outputRoot: _outputRoot, geminiKeys: _apiKey);
    _writer = writer;
    _addLog(_provider == Providers.web
        ? 'Using the ${Providers.label(_provider)} back end '
            '($_keyCount cookie${_keyCount == 1 ? '' : 's'} detected).'
        : 'Using $_keyCount ${Providers.label(_provider)} '
            'key${_keyCount == 1 ? '' : 's'}, model $_model.');
    if (topics.length > 1) {
      _addLog('Batch: ${topics.length} books queued.');
    }

    int failed = 0;
    try {
      for (int i = 0; i < topics.length; i++) {
        if (!mounted) return;
        setState(() => _bookIndex = i + 1);
        if (topics.length > 1) {
          _addLog('');
          _addLog('=== Book ${i + 1}/${topics.length}: ${topics[i]}');
        }
        try {
          final BookResult r = await writer.run(
            BookRequest(
              topic: topics[i],
              author: _author.text.trim().isEmpty
                  ? 'Anonymous'
                  : _author.text.trim(),
              fiction: _fiction,
              chapters: chapters,
              totalWords: words,
              model: _model,
              provider: _provider,
              themeOverride: _theme == 'auto' ? null : _theme,
              note: _note.text.trim(),
              extras: _extras,
            ),
            (double f, String m) {
              if (!mounted) return;
              setState(() => _progress = (i + f) / topics.length);
              _addLog(m);
            },
          );
          if (!mounted) return;
          setState(() {
            _result = r;
            _results.add(r);
          });
        } on BookCancelled {
          _addLog('Batch stopped by you.');
          break;
        } catch (e) {
          failed++;
          _addLog('ERROR on book ${i + 1}: $e');
          if (topics.length == 1) {
            if (mounted) _snack('$e');
          }
        }
      }

      if (_results.length > 1) {
        _addLog('Packing all ${_results.length} books into one ZIP...');
        final String zip = await packBatch(_results, _outputRoot);
        if (!mounted) return;
        setState(() => _batchZip = zip);
        _addLog('Batch ZIP ready.');
      }
      if (topics.length > 1) {
        _snack('Batch done: ${_results.length} written'
            '${failed > 0 ? ', $failed failed' : ''}.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = _results.isEmpty ? 0 : 1;
        });
      }
      _writer = null;
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m)));

  Future<void> _openFolder(String path) async {
    try {
      if (Platform.isWindows) {
        await Process.run('explorer', <String>[path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', <String>[path]);
      } else {
        await Process.run('xdg-open', <String>[path]);
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: path));
      _snack('Path copied to clipboard.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ShaderMask(
              shaderCallback: (Rect r) => const LinearGradient(
                colors: <Color>[Color(0xFFFFE9A8), Color(0xFFFFB31F)],
              ).createShader(r),
              child: const Text(
                kAppName,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  letterSpacing: .5,
                  color: Colors.white,
                ),
              ),
            ),
            Text(kTagline,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.primary)),
          ],
        ),
        actions: <Widget>[
          if (_keyCount > 1)
            Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: kGold.withValues(alpha: 0.3)),
                ),
                child: Text(_provider == Providers.web
                    ? '$_keyCount cookies'
                    : '$_keyCount keys',
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: kGold, fontWeight: FontWeight.w700)),
              ),
            ),
          IconButton(
            tooltip: _activeKeys.isEmpty
                ? (_provider == Providers.web
                    ? 'Add your Gemini web session'
                    : 'Add your API keys')
                : (_provider == Providers.web
                    ? 'Session with $_keyCount cookie${_keyCount == 1 ? '' : 's'} - tap to edit'
                    : '$_keyCount key${_keyCount == 1 ? '' : 's'} saved - tap to edit'),
            onPressed: _busy ? null : _editKey,
            icon: Icon(_activeKeys.isEmpty ? Icons.key_off : Icons.key),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(
        builder: (BuildContext ctx, BoxConstraints c) {
          final bool wide = c.maxWidth > 900;
          final Widget form = _buildForm(theme);
          final Widget output = _buildOutput(theme, expand: wide);
          if (!wide) {
            return ListView(
              padding: const EdgeInsets.all(18),
              children: <Widget>[form, const SizedBox(height: 20), output],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SizedBox(
                width: 470,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(26, 20, 20, 26),
                  child: form,
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: output,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Small gold caps label shown above a field, like the Play listing cards.
  Widget _sectionLabel(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 6),
        child: Text(
          text.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.primary,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w700,
          ),
        ),
      );

  /// Small grey helper line shown under a field.
  Widget _helperLine(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.only(left: 2, top: 6),
        child: Text(text, style: theme.textTheme.labelSmall),
      );

  /// A field with the label floating above it instead of inside it.
  Widget _topField(ThemeData theme, String label, TextField field) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[_sectionLabel(theme, label), field],
      );

  /// The big gold gradient call-to-action at the bottom of the form.
  Widget _generateButton(String text, VoidCallback? onTap) {
    final Color ink = const Color(0xFF221A05);
    return Opacity(
      opacity: onTap == null ? 0.6 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Ink(
            height: 54,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(
                colors: <Color>[Color(0xFFF7D774), Color(0xFFE9A63A)],
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: kGold.withValues(alpha: 0.28),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.auto_stories, color: ink),
                  const SizedBox(width: 10),
                  Text(
                    text,
                    style: TextStyle(
                      color: ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(ThemeData theme) {
    final List<String> themes = <String>['auto', ...CoverTheme.all.keys];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _topField(
          theme,
          _topics.length > 1
              ? 'Book topics (${_topics.length} books queued)'
              : 'Book topic',
          TextField(
            controller: _topic,
            minLines: 3,
            maxLines: 8,
            enabled: !_busy,
            decoration: InputDecoration(
              hintText:
                  'a cozy mystery set in a Cornish fishing village\n'
                  'a practical guide to freelancing with AI',
            ),
          ),
        ),
        _helperLine(theme,
            'One topic per line - every line becomes its own full book'),
        const SizedBox(height: 18),
        SegmentedButton<bool>(
          segments: const <ButtonSegment<bool>>[
            ButtonSegment<bool>(value: true, label: Text('Fiction')),
            ButtonSegment<bool>(value: false, label: Text('Non-fiction')),
          ],
          selected: <bool>{_fiction},
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
          onSelectionChanged:
              _busy ? null : (Set<bool> s) => setState(() => _fiction = s.first),
        ),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: _topField(
                theme,
                'Chapters',
                TextField(
                  controller: _chapters,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _topField(
                theme,
                'Total words',
                TextField(
                  controller: _words,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _topField(
                theme,
                'Pages (approx.)',
                TextField(
                  controller: _pages,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly
                  ],
                ),
              ),
            ),
          ],
        ),
        _helperLine(theme, '~250 words per page - chapters and words stay linked'),
        const SizedBox(height: 18),
        _topField(
          theme,
          'Author name',
          TextField(
            controller: _author,
            enabled: !_busy,
            decoration: const InputDecoration(
              hintText: 'Md Monjurul Islam',
            ),
          ),
        ),
        _helperLine(theme, 'Keep this identical across all your books'),
        const SizedBox(height: 18),
        _topField(
          theme,
          'Provider',
          DropdownButtonFormField<String>(
            value: _provider,
            decoration: const InputDecoration(hintText: ''),
            items: Providers.all
                .map((String p) => DropdownMenuItem<String>(
                    value: p, child: Text(Providers.label(p))))
                .toList(),
            onChanged: _busy
                ? null
                : (String? v) => setState(() {
                      _provider = v ?? _provider;
                      _model = Providers.fixModel(_provider, _model);
                    }),
          ),
        ),
        _helperLine(theme, 'Each provider keeps its own keys and model list'),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: _topField(
                theme,
                'Model',
                DropdownButtonFormField<String>(
                  value: Providers.fixModel(_provider, _model),
                  isExpanded: true,
                  items: Providers.models(_provider)
                      .map((String m) => DropdownMenuItem<String>(
                          value: m, child: Text(m, overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: _busy
                      ? null
                      : (String? v) => setState(() => _model = v ?? _model),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _topField(
                theme,
                'Cover theme',
                DropdownButtonFormField<String>(
                  value: _theme,
                  items: themes
                      .map((String t) => DropdownMenuItem<String>(
                          value: t, child: Text(t)))
                      .toList(),
                  onChanged: _busy
                      ? null
                      : (String? v) => setState(() => _theme = v ?? _theme),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _topField(
          theme,
          'Extra instructions (optional)',
          TextField(
            controller: _note,
            enabled: !_busy,
            decoration: const InputDecoration(
              hintText: 'set in 1920s Dhaka, first person',
            ),
          ),
        ),
        const SizedBox(height: 8),
        Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            title: Text('Front & back matter (copyright, bio, also-by)',
                style: theme.textTheme.titleSmall
                    ?.copyWith(color: theme.colorScheme.primary)),
            subtitle: Text(
              'Copyright page, bio, also-by list and the review request',
              style: theme.textTheme.labelSmall,
            ),
            children: <Widget>[
              _topField(
                theme,
                'About the author',
                TextField(
                  controller: _bio,
                  enabled: !_busy,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(hintText: ''),
                ),
              ),
              _helperLine(theme, 'Leave empty to use the bio the planner writes'),
              const SizedBox(height: 14),
              _topField(
                theme,
                'Also by you',
                TextField(
                  controller: _alsoBy,
                  enabled: !_busy,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(hintText: ''),
                ),
              ),
              _helperLine(theme, 'One title per line - sells your back catalogue'),
              const SizedBox(height: 14),
              _topField(
                theme,
                'Publisher / imprint (optional)',
                TextField(
                  controller: _publisher,
                  enabled: !_busy,
                ),
              ),
              _helperLine(theme, 'Defaults to your author name'),
              const SizedBox(height: 14),
              _topField(
                theme,
                'Stay in touch page (optional)',
                TextField(
                  controller: _newsletter,
                  enabled: !_busy,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'Follow me on Google Play, or email ...',
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy ? null : _pickFolder,
          icon: const Icon(Icons.folder_open),
          label: Text(
            _outputRoot.isEmpty ? 'Choose output folder' : _outputRoot,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 24),
        _generateButton(
          _busy
              ? (_bookTotal > 1
                  ? 'Writing book $_bookIndex of $_bookTotal...'
                  : 'Writing...')
              : (_topics.length > 1
                  ? 'Generate ${_topics.length} books'
                  : 'Generate book'),
          _busy ? null : _generate,
        ),
        if (_busy) ...<Widget>[
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: () {
              _writer?.cancel();
              _addLog('Cancelling after the current step...');
            },
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('Cancel'),
          ),
        ],
      ],
    );
  }

  Widget _buildOutput(ThemeData theme, {required bool expand}) {
    final BookResult? r = _result;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (_busy || _progress > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: LinearProgressIndicator(value: _busy ? _progress : 1),
          ),
        if (_batchZip != null) ...<Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '${_results.length} books finished - one archive with '
                      'every EPUB, cover and upload sheet.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: () => _saveFile(_batchZip!, 'zip'),
                    icon: const Icon(Icons.download),
                    label: const Text('Download all'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        for (final BookResult b in _results.reversed) ...<Widget>[
          _resultCard(theme, b),
          const SizedBox(height: 12),
        ],
        if (r != null)
          _maybeFlexible(
            expand,
            PublishChecklist(
              fields: PublishFields.build(
                plan: r.plan,
                words: r.words,
                chapterCount: r.plan.chapters.length,
                epubName: r.epubPath.split(Platform.pathSeparator).last,
              ),
              onCopied: (String label) => _snack('$label copied.'),
            ),
          ),
        if (r != null) const SizedBox(height: 12),
        _maybeExpanded(
          expand,
          Container(
            constraints: expand ? null : const BoxConstraints(maxHeight: 280),
            decoration: BoxDecoration(
              color: const Color(0xFF060606),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: kGold.withValues(alpha: 0.12)),
            ),
            padding: const EdgeInsets.all(14),
            child: _log.isEmpty
                ? Center(
                    child: Text(
                      'Type a topic and press Generate book.\n'
                      'Plan, chapters, cover, EPUB and the upload sheet are '
                      'produced in one run.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.hintColor),
                    ),
                  )
                : ListView.builder(
                    controller: _logScroll,
                    itemCount: _log.length,
                    itemBuilder: (BuildContext ctx, int i) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: SelectableText(
                        _log[i],
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 12.5),
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _maybeExpanded(bool expand, Widget child) =>
      expand ? Expanded(child: child) : child;

  Widget _maybeFlexible(bool expand, Widget child) =>
      expand ? Flexible(child: child) : child;

  /// Swaps a finished book for its rebuilt version everywhere it is shown.
  void _replaceResult(BookResult oldR, BookResult newR) {
    setState(() {
      final int i = _results.indexOf(oldR);
      if (i >= 0) {
        _results[i] = newR;
      } else {
        _results.add(newR);
      }
      if (_result == oldR) _result = newR;
    });
  }

  Future<void> _runEditorPass(BookResult r) async {
    final BookWriter w = BookWriter(
        apiKey: _activeKeys, outputRoot: _outputRoot, geminiKeys: _apiKey);
    setState(() {
      _busy = true;
      _progress = 0;
    });
    _writer = w;
    try {
      final BookResult out = await w.qualityPass(r, (double f, String m) {
        if (!mounted) return;
        setState(() => _progress = f);
        _addLog(m);
      });
      if (!mounted) return;
      _replaceResult(r, out);
      _snack('Editor report ready: ${out.report!.score}/100.');
    } catch (e) {
      _addLog('ERROR: $e');
      if (mounted) _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
      _writer = null;
    }
  }

  Future<void> _rewriteChapter(BookResult r, int index, String note) async {
    final TextEditingController c = TextEditingController(text: note);
    final String? instruction = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text('Rewrite chapter ${index + 1}'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(r.chapters[index].title),
              const SizedBox(height: 12),
              TextField(
                controller: c,
                autofocus: true,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'What should change?',
                  hintText: 'Too slow, cut the flashback, raise the stakes',
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('Rewrite')),
        ],
      ),
    );
    if (instruction == null) return;

    final BookWriter w = BookWriter(
        apiKey: _activeKeys, outputRoot: _outputRoot, geminiKeys: _apiKey);
    setState(() {
      _busy = true;
      _progress = 0;
    });
    _writer = w;
    try {
      final BookResult out =
          await w.regenerateChapter(r, index, instruction, (double f, String m) {
        if (!mounted) return;
        setState(() => _progress = f);
        _addLog(m);
      });
      if (!mounted) return;
      _replaceResult(r, out);
      _snack('Chapter ${index + 1} rewritten and the book rebuilt.');
    } catch (e) {
      _addLog('ERROR: $e');
      if (mounted) _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
      _writer = null;
    }
  }

  Future<void> _openCoverStudio(BookResult r) async {
    final BookWriter w = BookWriter(
        apiKey: _activeKeys, outputRoot: _outputRoot, geminiKeys: _apiKey);
    final ChosenCover? chosen =
        await showCoverStudio(context: context, writer: w, result: r);
    if (chosen == null || !mounted) return;
    setState(() {
      _busy = true;
      _progress = 0;
    });
    try {
      final BookResult out = await w.applyCoverStyle(
        r,
        chosen.style,
        (double f, String m) {
          if (!mounted) return;
          setState(() => _progress = f);
          _addLog(m);
        },
        png: chosen.png,
      );
      if (!mounted) return;
      _replaceResult(r, out);
      _snack('New cover applied to the EPUB and the ZIP.');
    } catch (e) {
      _addLog('ERROR: $e');
      if (mounted) _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveZip(BookResult r) => _saveFile(r.zipPath, 'zip');

  Future<void> _saveFile(String path, String ext) async {
    final File src = File(path);
    if (!src.existsSync()) {
      _snack('The publishing kit ZIP is missing.');
      return;
    }
    try {
      final String? target = await FilePicker.platform.saveFile(
        dialogTitle: 'Save the publishing kit',
        fileName: src.uri.pathSegments.last,
        type: FileType.custom,
        allowedExtensions: <String>[ext],
        bytes: await src.readAsBytes(),
      );
      if (target == null) return;
      final File out = File(target);
      if (!out.existsSync() || out.lengthSync() == 0) {
        await src.copy(target);
      }
      _snack('Saved to $target');
    } catch (e) {
      _snack('Could not save the ZIP: $e');
    }
  }

  Widget _resultCard(ThemeData theme, BookResult r) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                if (File(r.coverPath).existsSync())
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.file(File(r.coverPath),
                        width: 90, height: 144, fit: BoxFit.cover),
                  ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(r.plan.title,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      if (r.plan.series.isNotEmpty)
                        Text(r.plan.series,
                            style: theme.textTheme.labelSmall),
                      const SizedBox(height: 6),
                      Text(
                        '${r.words} words  -  ${r.plan.chapters.length} chapters  -  '
                        'USD ${r.plan.priceUsd.toStringAsFixed(2)}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton.tonalIcon(
                  onPressed: () => _openFolder(r.directory),
                  icon: const Icon(Icons.folder),
                  label: const Text('Open folder'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _saveZip(r),
                  icon: const Icon(Icons.download),
                  label: const Text('Download ZIP'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                        ClipboardData(text: r.plan.description));
                    _snack('Store description copied.');
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy description'),
                ),
                OutlinedButton.icon(
                  onPressed: () => showBookPreview(
                    context,
                    r,
                    onOpenFolder: _openFolder,
                  ),
                  icon: const Icon(Icons.menu_book_outlined),
                  label: const Text('Preview book'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _openCoverStudio(r),
                  icon: const Icon(Icons.palette_outlined),
                  label: const Text('Cover studio'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _runEditorPass(r),
                  icon: const Icon(Icons.fact_check_outlined),
                  label: Text(
                      r.report == null ? 'Editor pass' : 'Run editor again'),
                ),
              ],
            ),
            if (r.report != null) ...<Widget>[
              const SizedBox(height: 12),
              QualityCard(
                report: r.report!,
                busy: _busy,
                onFix: (int i, String note) => _rewriteChapter(r, i, note),
              ),
            ],
            const SizedBox(height: 4),
            Theme(
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('Chapters (${r.chapters.length})',
                    style: theme.textTheme.labelLarge),
                children: <Widget>[
                  for (int i = 0; i < r.chapters.length; i++)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('${i + 1}. ${r.chapters[i].title}',
                          style: theme.textTheme.bodySmall),
                      subtitle: Text('${r.chapters[i].words} words',
                          style: theme.textTheme.labelSmall),
                      trailing: IconButton(
                        tooltip: 'Rewrite this chapter',
                        icon: const Icon(Icons.autorenew, size: 18),
                        onPressed: _busy ? null : () => _rewriteChapter(r, i, ''),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
