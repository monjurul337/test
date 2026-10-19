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
import 'src/gemini.dart' show KeyPool;
import 'src/gemini_web.dart';
import 'src/imagegen.dart';
import 'src/llm.dart';
import 'src/studio.dart';
import 'src/writer.dart';

/// Build profile baked in by CI: --dart-define=BUILD=<profile>
const String kBuildProfile = String.fromEnvironment(
  'BUILD',
  defaultValue: 'dev',
);
const String kAppName = 'Book Generator';

/// LitPal-style light house style: white cards on a faint violet wash.
const LinearGradient kAppGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: <Color>[Color(0xFFFBF8FF), Color(0xFFF7F1FF), Color(0xFFFFFFFF)],
  stops: <double>[0.0, 0.35, 1.0],
);

/// The palette, lifted from the same shadcn violet scale.
const Color kViolet = Color(0xFF7C3AED);
const Color kVioletDark = Color(0xFF6D28D9);
const Color kVioletWash = Color(0xFFF5F0FF);
const Color kInk = Color(0xFF0C0A09);
const Color kMutedInk = Color(0xFF78716C);
const Color kLine = Color(0xFFE7E5E4);
const Color kMuted = Color(0xFFF5F5F4);

/// Small helper so the card shape is declared once.
class RoundedCornerShape12 {
  static const RoundedRectangleBorder shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(12)),
    side: BorderSide(color: kLine),
  );
}

const String kTagline = 'Meta Hawladar Team';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BookGeneratorApp());
}

class BookGeneratorApp extends StatelessWidget {
  const BookGeneratorApp({super.key});

  @override
  Widget build(BuildContext context) {
    const ColorScheme scheme = ColorScheme.light(
      primary: kViolet,
      onPrimary: Colors.white,
      primaryContainer: kVioletWash,
      onPrimaryContainer: kVioletDark,
      secondary: kVioletDark,
      onSecondary: Colors.white,
      secondaryContainer: kMuted,
      onSecondaryContainer: kInk,
      surface: Colors.white,
      onSurface: kInk,
      surfaceContainerHighest: kMuted,
      onSurfaceVariant: kMutedInk,
      outline: kLine,
      outlineVariant: kLine,
      error: Color(0xFFEF4444),
      onError: Colors.white,
    );
    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: Colors.transparent,
        dividerColor: kLine,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          foregroundColor: kInk,
          elevation: 0,
        ),
        cardTheme: const CardThemeData(
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedCornerShape12.shape,
        ),
        textTheme: const TextTheme(
          headlineSmall: TextStyle(
            color: kInk,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
          titleLarge: TextStyle(color: kInk, fontWeight: FontWeight.w700),
          titleMedium: TextStyle(color: kInk, fontWeight: FontWeight.w700),
          titleSmall: TextStyle(color: kInk, fontWeight: FontWeight.w700),
          bodyMedium: TextStyle(color: kInk),
          bodySmall: TextStyle(color: kMutedInk),
          labelSmall: TextStyle(color: kMutedInk),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: kLine),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: kLine),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: kViolet, width: 2),
          ),
          labelStyle: const TextStyle(color: kMutedInk),
          helperStyle: const TextStyle(color: kMutedInk, fontSize: 11),
          hintStyle: const TextStyle(color: Color(0xFFA8A29E)),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: kViolet,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: kInk,
            side: const BorderSide(color: kLine),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: kViolet),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: Colors.white,
          selectedColor: kVioletWash,
          side: const BorderSide(color: kLine),
          labelStyle: const TextStyle(color: kInk, fontWeight: FontWeight.w500),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: kInk,
          contentTextStyle: const TextStyle(color: Colors.white),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: kViolet,
          linearTrackColor: kMuted,
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith<Color>(
            (Set<WidgetState> s) =>
                s.contains(WidgetState.selected) ? Colors.white : Colors.white,
          ),
          trackColor: WidgetStateProperty.resolveWith<Color>(
            (Set<WidgetState> s) =>
                s.contains(WidgetState.selected) ? kViolet : kLine,
          ),
        ),
      ),
      builder: (BuildContext context, Widget? child) => DecoratedBox(
        decoration: const BoxDecoration(gradient: kAppGradient),
        child: child ?? const SizedBox.shrink(),
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
  final TextEditingController _author = TextEditingController(
    text: 'Md Monjurul Islam',
  );
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
  String _provider = Providers.gemini;

  /// The keys that belong to the provider in use right now.
  String get _activeKeys => _provider == Providers.nvidia ? _nvKey : _apiKey;

  int get _keyCount => _provider == Providers.gemini
      ? (_apiKey.isEmpty ? 0 : 1)
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
  String _model = Providers.defaultModel(Providers.gemini);
  String _coverArt = ImageGen.off;
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
      _apiKey =
          ''; // Cookies are memory-only; never persist to SharedPreferences.
      _nvKey = p.getString('nvKey') ?? '';
      _provider = p.getString('provider') ?? Providers.gemini;
      _model = Providers.fixModel(
        _provider,
        p.getString('model') ?? Providers.defaultModel(_provider),
      );
      _coverArt = ImageGen.fixModel(
        _provider,
        p.getString('coverArt') ?? ImageGen.off,
      );
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
    await p.remove('apiKey'); // Remove legacy Gemini API key.
    await p.setString('nvKey', _nvKey);
    await p.setString('provider', _provider);
    await p.setString('model', _model);
    await p.setString('coverArt', _coverArt);
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
    String testStatus = '';
    bool testing = false;
    final List<String>? value = await showDialog<List<String>>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Gemini session & NVIDIA keys'),
        content: SizedBox(
          width: 520,
          child: StatefulBuilder(
            builder: (BuildContext _, void Function(void Function()) setLocal) {
              final int gc = GeminiWebSession.countCookies(g.text);
              final int nc = KeyPool.parse(n.text).length;
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'Gemini: paste your own cookie JSON. Cookies grant account access; '
                      'they stay in memory and are cleared when the app closes. '
                      'Sessions can expire. NVIDIA still uses API keys.',
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: g,
                      enableSuggestions: false,
                      autocorrect: false,
                      autofocus: _provider == Providers.gemini,
                      maxLines: 5,
                      minLines: 2,
                      onChanged: (_) => setLocal(() {}),
                      decoration: InputDecoration(
                        labelText: 'Gemini cookie session JSON',
                        helperText: gc == 0
                            ? 'Playwright storageState or cookie-export JSON'
                            : '$gc cookies detected (not yet verified)',
                      ),
                    ),
                    TextButton(
                      onPressed: testing
                          ? null
                          : () async {
                              setLocal(() {
                                testing = true;
                                testStatus = 'Testing session...';
                              });
                              GeminiWeb? client;
                              String message;
                              try {
                                client = GeminiWeb(g.text);
                                final GeminiWebTestResult result = await client
                                    .test();
                                message = result.message;
                              } catch (_) {
                                message = 'Invalid session JSON or connection failed. Check your export.';
                              } finally {
                                client?.dispose();
                              }
                              if (ctx.mounted)
                                setLocal(() {
                                  testing = false;
                                  testStatus = message;
                                });
                            },
                      child: const Text('Test Gemini session'),
                    ),
                    if (testStatus.isNotEmpty) Text(testStatus),
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
                  ],
                ),
              );
            },
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              try {
                if (g.text.trim().isNotEmpty) GeminiWebSession.parse(g.text);
                Navigator.pop(ctx, <String>[
                  g.text.trim(),
                  KeyPool.parse(n.text).join('\n'),
                ]);
              } catch (_) {
                _snack(
                  'Invalid Gemini cookie JSON. Check your signed-in session export.',
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value != null) {
      setState(() {
        _apiKey = value[0];
        _nvKey = value[1];
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
      apiKey: _activeKeys,
      outputRoot: _outputRoot,
    );
    _writer = writer;
    _addLog(
      _provider == Providers.gemini
          ? 'Using Gemini cookie session (web-selected model).'
          : 'Using $_keyCount NVIDIA keys, model $_model.',
    );
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
              coverArtModel: _coverArt,
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
        _snack(
          'Batch done: ${_results.length} written'
          '${failed > 0 ? ', $failed failed' : ''}.',
        );
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

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

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

  /// Sidebar views. Everything else in the sidebar is a direct action.
  String _view = 'create';

  Widget _navItem(
    ThemeData theme, {
    required IconData icon,
    required String label,
    bool active = false,
    String badge = '',
    VoidCallback? onTap,
  }) {
    final Color fg = active ? kVioletDark : const Color(0xFF44403C);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: active ? kVioletWash : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: <Widget>[
                Icon(icon, size: 17, color: active ? kViolet : kMutedInk),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: fg,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (badge.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: kVioletWash,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      badge,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: kVioletDark,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _navSection(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 14, 8, 7),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 10,
        letterSpacing: 1.4,
        fontWeight: FontWeight.w700,
        color: Color(0xFFA8A29E),
      ),
    ),
  );

  Widget _sidebar(ThemeData theme) => Container(
    width: 256,
    color: Colors.white,
    padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[kViolet, Color(0xFFA855F7)],
                  ),
                ),
              ),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  kAppName,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: kInk,
                  ),
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(left: 35, top: 2, bottom: 16),
            child: Text(
              kTagline,
              style: TextStyle(fontSize: 10.5, color: kMutedInk),
            ),
          ),
          FilledButton.icon(
            onPressed: _busy
                ? null
                : () => setState(() {
                    _view = 'create';
                    _result = null;
                  }),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Create book'),
          ),
          _navSection('WORKSPACE'),
          _navItem(
            theme,
            icon: Icons.edit_note,
            label: 'Create',
            active: _view == 'create',
            onTap: () => setState(() => _view = 'create'),
          ),
          _navItem(
            theme,
            icon: Icons.menu_book,
            label: 'My books',
            active: _view == 'books',
            badge: _results.isEmpty ? '' : '${_results.length}',
            onTap: () => setState(() => _view = 'books'),
          ),
          _navItem(
            theme,
            icon: Icons.palette_outlined,
            label: 'Cover studio',
            onTap: _busy || _result == null
                ? null
                : () => _openCoverStudio(_result!),
          ),
          _navSection('PUBLISH'),
          _navItem(
            theme,
            icon: Icons.checklist,
            label: 'Play Books checklist',
            active: _view == 'checklist',
            onTap: _result == null
                ? null
                : () => setState(() => _view = 'checklist'),
          ),
          _navItem(
            theme,
            icon: Icons.description_outlined,
            label: 'Metadata sheet',
            onTap: _result == null
                ? null
                : () => _openFolder(_result!.directory),
          ),
          _navSection('SETTINGS'),
          _navItem(
            theme,
            icon: _activeKeys.isEmpty ? Icons.key_off : Icons.key,
            label: 'Session & API keys',
            badge: _keyCount == 0 ? '' : '$_keyCount',
            onTap: _busy ? null : _editKey,
          ),
          _navItem(
            theme,
            icon: Icons.folder_outlined,
            label: 'Output folder',
            onTap: _busy ? null : _pickFolder,
          ),
        ],
      ),
    ),
  );

  /// Page heading above the working area.
  Widget _pageHead(ThemeData theme) {
    final (String title, String sub) = switch (_view) {
      'books' => (
        'My books',
        'Everything written in this session. Open a folder or download the kit.',
      ),
      'checklist' => (
        'Play Books checklist',
        'Every field Partner Center asks for, with the reason behind each value.',
      ),
      _ => (
        'Create a book',
        'Plan, chapters, cover, EPUB and the Google Play Books upload sheet - in one run.',
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: theme.textTheme.headlineSmall?.copyWith(fontSize: 27),
        ),
        const SizedBox(height: 3),
        Text(sub, style: theme.textTheme.bodySmall?.copyWith(fontSize: 13)),
      ],
    );
  }

  Widget _booksView(ThemeData theme) {
    if (_results.isEmpty) {
      return Center(
        child: Text(
          'No books yet. Write one from Create.',
          style: theme.textTheme.bodyMedium?.copyWith(color: kMutedInk),
        ),
      );
    }
    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (BuildContext _, int __) => const SizedBox(height: 14),
      itemBuilder: (BuildContext _, int i) =>
          _resultCard(theme, _results[_results.length - 1 - i]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      body: LayoutBuilder(
        builder: (BuildContext ctx, BoxConstraints c) {
          final bool wide = c.maxWidth > 1100;
          final Widget form = _buildForm(theme);
          final Widget output = _buildOutput(theme, expand: wide);

          Widget working;
          if (_view == 'books') {
            working = _booksView(theme);
          } else if (_view == 'checklist' && _result != null) {
            working = SingleChildScrollView(
              child: _buildOutput(theme, expand: false),
            );
          } else if (!wide) {
            working = ListView(
              children: <Widget>[form, const SizedBox(height: 20), output],
            );
          } else {
            working = Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SizedBox(width: 470, child: SingleChildScrollView(child: form)),
                const SizedBox(width: 18),
                Expanded(child: output),
              ],
            );
          }

          final Widget main = Padding(
            padding: const EdgeInsets.fromLTRB(26, 22, 26, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _pageHead(theme),
                const SizedBox(height: 18),
                Expanded(child: working),
              ],
            ),
          );

          if (c.maxWidth < 820) {
            return Scaffold(
              backgroundColor: Colors.transparent,
              appBar: AppBar(
                title: const Text(
                  kAppName,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                actions: <Widget>[
                  IconButton(
                    tooltip: 'Session & API keys',
                    onPressed: _busy ? null : _editKey,
                    icon: Icon(_activeKeys.isEmpty ? Icons.key_off : Icons.key),
                  ),
                  const SizedBox(width: 6),
                ],
              ),
              drawer: Drawer(child: _sidebar(theme)),
              body: main,
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _sidebar(theme),
              const VerticalDivider(width: 1, color: kLine),
              Expanded(child: main),
            ],
          );
        },
      ),
    );
  }

  Widget _buildForm(ThemeData theme) {
    final List<String> themes = <String>['auto', ...CoverTheme.all.keys];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              controller: _topic,
              minLines: 3,
              maxLines: 8,
              enabled: !_busy,
              decoration: InputDecoration(
                labelText: _topics.length > 1
                    ? 'Book topics (${_topics.length} books queued)'
                    : 'Book topic',
                hintText: 'a cozy mystery set in a Cornish fishing village',
                helperText:
                    'One topic per line - every line becomes its own full book',
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: const <ButtonSegment<bool>>[
                ButtonSegment<bool>(value: true, label: Text('Fiction')),
                ButtonSegment<bool>(value: false, label: Text('Non-fiction')),
              ],
              selected: <bool>{_fiction},
              onSelectionChanged: _busy
                  ? null
                  : (Set<bool> s) => setState(() => _fiction = s.first),
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _chapters,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: const InputDecoration(labelText: 'Chapters'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _words,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Total words',
                      helperText: 'Linked to pages',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _pages,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Pages (approx.)',
                      helperText: '~250 words per page',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _author,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Author name',
                helperText: 'Keep this identical across all your books',
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _provider,
              decoration: const InputDecoration(
                labelText: 'Provider',
                helperText: 'Gemini uses cookies; NVIDIA uses API keys',
              ),
              items: Providers.all
                  .map(
                    (String p) => DropdownMenuItem<String>(
                      value: p,
                      child: Text(Providers.label(p)),
                    ),
                  )
                  .toList(),
              onChanged: _busy
                  ? null
                  : (String? v) => setState(() {
                      _provider = v ?? _provider;
                      _model = Providers.fixModel(_provider, _model);
                      _coverArt = ImageGen.fixModel(_provider, _coverArt);
                    }),
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: Providers.fixModel(_provider, _model),
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Model'),
                    items: Providers.models(_provider)
                        .map(
                          (String m) => DropdownMenuItem<String>(
                            value: m,
                            child: Text(m, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: _busy
                        ? null
                        : (String? v) => setState(() => _model = v ?? _model),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _theme,
                    decoration: const InputDecoration(labelText: 'Cover theme'),
                    items: themes
                        .map(
                          (String t) => DropdownMenuItem<String>(
                            value: t,
                            child: Text(t),
                          ),
                        )
                        .toList(),
                    onChanged: _busy
                        ? null
                        : (String? v) => setState(() => _theme = v ?? _theme),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: ImageGen.fixModel(_provider, _coverArt),
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Cover art (AI image)',
                helperText: 'Off = geometric cover. Uses the selected provider authentication',
              ),
              items: ImageGen.modelsFor(_provider)
                  .map(
                    (String m) => DropdownMenuItem<String>(
                      value: m,
                      child: Text(
                        m == ImageGen.off ? 'Off - geometric cover' : m,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _busy
                  ? null
                  : (String? v) => setState(() => _coverArt = v ?? _coverArt),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _note,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Extra instructions (optional)',
                hintText: 'set in 1920s Dhaka, first person',
              ),
            ),
            const SizedBox(height: 8),
            Theme(
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                title: Text(
                  'Front & back matter',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
                subtitle: Text(
                  'Copyright page, bio, also-by list and the review request',
                  style: theme.textTheme.labelSmall,
                ),
                children: <Widget>[
                  TextField(
                    controller: _bio,
                    enabled: !_busy,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'About the author',
                      helperText:
                          'Leave empty to use the bio the planner writes',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _alsoBy,
                    enabled: !_busy,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Also by you',
                      helperText:
                          'One title per line - sells your back catalogue',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _publisher,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      labelText: 'Publisher / imprint (optional)',
                      helperText: 'Defaults to your author name',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _newsletter,
                    enabled: !_busy,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Stay in touch page (optional)',
                      hintText: 'Follow me on Google Play, or email ...',
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
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _generate,
              icon: const Icon(Icons.auto_stories),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _busy
                      ? (_bookTotal > 1
                            ? 'Writing book $_bookIndex of $_bookTotal...'
                            : 'Writing...')
                      : (_topics.length > 1
                            ? 'Generate ${_topics.length} books'
                            : 'Generate book'),
                ),
              ),
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
        ),
      ),
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
                publisher: r.request.extras.publisher,
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
              color: kMuted,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kLine),
            ),
            padding: const EdgeInsets.all(12),
            child: _log.isEmpty
                ? Center(
                    child: Text(
                      'Type a topic and press Generate book.\n'
                      'Plan, chapters, cover, EPUB and the upload sheet are '
                      'produced in one run.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.hintColor,
                      ),
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
                          fontFamily: 'monospace',
                          fontSize: 12.5,
                        ),
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
      apiKey: _activeKeys,
      outputRoot: _outputRoot,
    );
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
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('Rewrite'),
          ),
        ],
      ),
    );
    if (instruction == null) return;

    final BookWriter w = BookWriter(
      apiKey: _activeKeys,
      outputRoot: _outputRoot,
    );
    setState(() {
      _busy = true;
      _progress = 0;
    });
    _writer = w;
    try {
      final BookResult out = await w.regenerateChapter(r, index, instruction, (
        double f,
        String m,
      ) {
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
      apiKey: _activeKeys,
      outputRoot: _outputRoot,
    );
    final ChosenCover? chosen = await showCoverStudio(
      context: context,
      writer: w,
      result: r,
    );
    if (chosen == null || !mounted) return;
    setState(() {
      _busy = true;
      _progress = 0;
    });
    try {
      final BookResult out = await w.applyCoverStyle(r, chosen.style, (
        double f,
        String m,
      ) {
        if (!mounted) return;
        setState(() => _progress = f);
        _addLog(m);
      }, png: chosen.png);
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

  Future<void> _newArtwork(BookResult r) async {
    final BookWriter w = BookWriter(
      apiKey: _activeKeys,
      outputRoot: _outputRoot,
    );
    setState(() {
      _busy = true;
      _progress = 0;
    });
    try {
      final BookResult out = await w.regenerateArtwork(r, (double f, String m) {
        if (!mounted) return;
        setState(() => _progress = f);
        _addLog(m);
      });
      if (!mounted) return;
      _replaceResult(r, out);
      _snack('New cover artwork applied.');
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
                    child: Image.file(
                      File(r.coverPath),
                      width: 90,
                      height: 144,
                      fit: BoxFit.cover,
                    ),
                  ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        r.plan.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (r.plan.series.isNotEmpty)
                        Text(r.plan.series, style: theme.textTheme.labelSmall),
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
                      ClipboardData(text: r.plan.description),
                    );
                    _snack('Store description copied.');
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy description'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _openCoverStudio(r),
                  icon: const Icon(Icons.palette_outlined),
                  label: const Text('Cover studio'),
                ),
                if (r.request.coverArtModel != ImageGen.off)
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _newArtwork(r),
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('New artwork'),
                  ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _runEditorPass(r),
                  icon: const Icon(Icons.fact_check_outlined),
                  label: Text(
                    r.report == null ? 'Editor pass' : 'Run editor again',
                  ),
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
                title: Text(
                  'Chapters (${r.chapters.length})',
                  style: theme.textTheme.labelLarge,
                ),
                children: <Widget>[
                  for (int i = 0; i < r.chapters.length; i++)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${i + 1}. ${r.chapters[i].title}',
                        style: theme.textTheme.bodySmall,
                      ),
                      subtitle: Text(
                        '${r.chapters[i].words} words',
                        style: theme.textTheme.labelSmall,
                      ),
                      trailing: IconButton(
                        tooltip: 'Rewrite this chapter',
                        icon: const Icon(Icons.autorenew, size: 18),
                        onPressed: _busy
                            ? null
                            : () => _rewriteChapter(r, i, ''),
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
