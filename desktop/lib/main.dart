import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/cover.dart';
import 'src/gemini.dart';
import 'src/writer.dart';

/// Build profile baked in by CI: --dart-define=BUILD=<profile>
const String kBuildProfile = String.fromEnvironment('BUILD', defaultValue: 'dev');
const String kAppName = 'Book Generator';
const String kTagline = 'Meta Hawladar Team';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BookGeneratorApp());
}

class BookGeneratorApp extends StatelessWidget {
  const BookGeneratorApp({super.key});

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF4F46E5),
      brightness: Brightness.dark,
    );
    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFF111827),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          isDense: true,
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
  final TextEditingController _note = TextEditingController();
  final ScrollController _logScroll = ScrollController();

  String _apiKey = '';
  String _model = Gemini.models.first;
  String _theme = 'auto';
  bool _fiction = true;
  String _outputRoot = '';
  bool _busy = false;
  double _progress = 0;
  final List<String> _log = <String>[];
  BookResult? _result;
  BookWriter? _writer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _topic.dispose();
    _author.dispose();
    _chapters.dispose();
    _words.dispose();
    _note.dispose();
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
      _model = p.getString('model') ?? Gemini.models.first;
      _author.text = p.getString('author') ?? _author.text;
      _outputRoot = root;
    });
  }

  Future<void> _save() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.setString('apiKey', _apiKey);
    await p.setString('model', _model);
    await p.setString('author', _author.text.trim());
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
    final TextEditingController c = TextEditingController(text: _apiKey);
    final String? value = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Gemini API key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Create a free key at aistudio.google.com/apikey and paste it here. '
              'It is stored only on this device.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: c,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'API key'),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (value != null) {
      setState(() => _apiKey = value);
      await _save();
    }
  }

  Future<void> _generate() async {
    final String topic = _topic.text.trim();
    if (topic.isEmpty) {
      _snack('Type a topic first.');
      return;
    }
    if (_apiKey.isEmpty) {
      await _editKey();
      if (_apiKey.isEmpty) return;
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
    });

    final BookWriter writer =
        BookWriter(apiKey: _apiKey, outputRoot: _outputRoot);
    _writer = writer;
    try {
      final BookResult r = await writer.run(
        BookRequest(
          topic: topic,
          author: _author.text.trim().isEmpty
              ? 'Anonymous'
              : _author.text.trim(),
          fiction: _fiction,
          chapters: chapters,
          totalWords: words,
          model: _model,
          themeOverride: _theme == 'auto' ? null : _theme,
          note: _note.text.trim(),
        ),
        (double f, String m) {
          if (!mounted) return;
          setState(() => _progress = f);
          _addLog(m);
        },
      );
      if (!mounted) return;
      setState(() => _result = r);
    } catch (e) {
      _addLog('ERROR: $e');
      if (mounted) _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
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
            const Text(kAppName,
                style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: .5)),
            Text(kTagline,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.primary)),
          ],
        ),
        actions: <Widget>[
          IconButton(
            tooltip: _apiKey.isEmpty ? 'Add your Gemini API key' : 'Change API key',
            onPressed: _busy ? null : _editKey,
            icon: Icon(_apiKey.isEmpty ? Icons.key_off : Icons.key),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(
        builder: (BuildContext ctx, BoxConstraints c) {
          final bool wide = c.maxWidth > 900;
          final Widget form = _buildForm(theme);
          final Widget output = _buildOutput(theme);
          if (!wide) {
            return ListView(
              padding: const EdgeInsets.all(20),
              children: <Widget>[form, const SizedBox(height: 20), output],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SizedBox(
                width: 460,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
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

  Widget _buildForm(ThemeData theme) {
    final List<String> themes = <String>['auto', ...CoverTheme.all.keys];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextField(
          controller: _topic,
          maxLines: 3,
          enabled: !_busy,
          decoration: const InputDecoration(
            labelText: 'Book topic',
            hintText: 'a cozy mystery set in a Cornish fishing village',
          ),
        ),
        const SizedBox(height: 16),
        SegmentedButton<bool>(
          segments: const <ButtonSegment<bool>>[
            ButtonSegment<bool>(value: true, label: Text('Fiction')),
            ButtonSegment<bool>(value: false, label: Text('Non-fiction')),
          ],
          selected: <bool>{_fiction},
          onSelectionChanged:
              _busy ? null : (Set<bool> s) => setState(() => _fiction = s.first),
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
                  FilteringTextInputFormatter.digitsOnly
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
                  FilteringTextInputFormatter.digitsOnly
                ],
                decoration: const InputDecoration(labelText: 'Total words'),
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
        Row(
          children: <Widget>[
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _model,
                decoration: const InputDecoration(labelText: 'Model'),
                items: Gemini.models
                    .map((String m) => DropdownMenuItem<String>(
                        value: m, child: Text(m, overflow: TextOverflow.ellipsis)))
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
                    .map((String t) => DropdownMenuItem<String>(
                        value: t, child: Text(t)))
                    .toList(),
                onChanged: _busy
                    ? null
                    : (String? v) => setState(() => _theme = v ?? _theme),
              ),
            ),
          ],
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
        const SizedBox(height: 16),
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
            child: Text(_busy ? 'Writing...' : 'Generate book'),
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
    );
  }

  Widget _buildOutput(ThemeData theme) {
    final BookResult? r = _result;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (_busy || _progress > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: LinearProgressIndicator(value: _busy ? _progress : 1),
          ),
        if (r != null) _resultCard(theme, r),
        if (r != null) const SizedBox(height: 16),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.dividerColor),
            ),
            padding: const EdgeInsets.all(12),
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
                OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                        ClipboardData(text: r.plan.description));
                    _snack('Store description copied.');
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy description'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
