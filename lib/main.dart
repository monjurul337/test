// Gemini HD Studio — Flutter port of the v2.5.3 Chrome extension.
// Wallpaper Set Designer, AI Metadata & Panel Uploader for Android
// (Kotlin) and Windows, built from one codebase.
import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'gemini_api.dart';
import 'image_search.dart';
import 'login_screen.dart';
import 'models.dart';
import 'panel_settings.dart';
import 'session_store.dart';
import 'studio_constants.dart';
import 'studio_engine.dart';

void main() {
  runApp(const GeminiHdStudioApp());
}

/// Dashboard colour palette: deep-space dark backgrounds with a
/// vibrant violet primary and cyan secondary accent. Every screen in
/// the app (Studio, Login, Search, Settings) draws from this scheme,
/// so the whole app stays cohesive.
const ColorScheme kDashboardScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFF7C6CFF),
  onPrimary: Colors.white,
  primaryContainer: Color(0xFF2A2160),
  onPrimaryContainer: Color(0xFFDCD4FF),
  secondary: Color(0xFF22D3EE),
  onSecondary: Color(0xFF04222B),
  secondaryContainer: Color(0xFF0E3A47),
  onSecondaryContainer: Color(0xFFB9F1FD),
  tertiary: Color(0xFFFF7AC6),
  onTertiary: Color(0xFF2B0A1E),
  error: Color(0xFFFF6B6B),
  onError: Colors.white,
  surface: Color(0xFF101527),
  onSurface: Color(0xFFF2F4FF),
  surfaceContainerLowest: Color(0xFF070A14),
  surfaceContainerLow: Color(0xFF0C1122),
  surfaceContainer: Color(0xFF121830),
  surfaceContainerHigh: Color(0xFF171F3D),
  surfaceContainerHighest: Color(0xFF1D2650),
  onSurfaceVariant: Color(0xFFB9C0D8),
  outline: Color(0xFF39406B),
  outlineVariant: Color(0xFF262D52),
  inverseSurface: Color(0xFFE8EBFF),
  onInverseSurface: Color(0xFF12172E),
  inversePrimary: Color(0xFF4B3FD1),
);

const LinearGradient kHeaderGradient = LinearGradient(
  colors: [Color(0xFF1B2A6B), Color(0xFF4B2E83), Color(0xFF0E4D5C)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

const LinearGradient kAccentGradient = LinearGradient(
  colors: [Color(0xFF7C6CFF), Color(0xFF22D3EE)],
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
);

/// Batch prompt parsing, shared by the designer prompt field, the
/// batch queue panel and the generator itself: in batch mode every
/// non-empty line is one set job, run in order.
List<String> parseBatchPrompts(String text) => text
    .split('\n')
    .map((e) => e.trim())
    .where((e) => e.isNotEmpty)
    .toList();

/// Gentle fade + slide used for every route change, so moving between
/// the dashboard, login, search and settings feels smooth.
class FadeSlideTransitionsBuilder extends PageTransitionsBuilder {
  const FadeSlideTransitionsBuilder();
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved =
        CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
                begin: const Offset(0.04, 0), end: Offset.zero)
            .animate(curved),
        child: child,
      ),
    );
  }
}

class GeminiHdStudioApp extends StatelessWidget {
  const GeminiHdStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gemini HD Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: kDashboardScheme,
        scaffoldBackgroundColor: const Color(0xFF070A14),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0C1122),
          elevation: 0,
          titleTextStyle: TextStyle(
              fontSize: 19, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        cardTheme: CardTheme(
          color: const Color(0xFF121830),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF262D52)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF0C1122),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF262D52)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF262D52)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                const BorderSide(color: Color(0xFF7C6CFF), width: 1.6),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            textStyle:
                const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),
        chipTheme: ChipThemeData(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFF0C1122),
          indicatorColor: const Color(0xFF2A2160),
          labelTextStyle: WidgetStateProperty.all(
              const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        ),
        navigationRailTheme: const NavigationRailThemeData(
          backgroundColor: Color(0xFF0B0F20),
          indicatorColor: Color(0xFF2A2160),
          selectedLabelTextStyle: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
          unselectedLabelTextStyle:
              TextStyle(fontSize: 12, color: Color(0xFFB9C0D8)),
        ),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: FadeSlideTransitionsBuilder(),
            TargetPlatform.windows: FadeSlideTransitionsBuilder(),
            TargetPlatform.linux: FadeSlideTransitionsBuilder(),
            TargetPlatform.macOS: FadeSlideTransitionsBuilder(),
          },
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final StudioEngine _engine;
  final List<String> _log = [];
  bool _busy = false;
  String _statusText = 'Ready';
  int _activeStep = 0;

  List<GeminiAccount> _accounts = [];
  String _accountMode = 'auto';
  String _sessionLabel = 'Not connected';
  List<SetEntry> _history = [];

  /// Dashboard tab: 0 = Studio (designer workbench), 1 = Showcase.
  /// Nav destinations 2-3 (Search / Login) open their screens as
  /// routes on top instead of switching the tab. (There is no separate
  /// Prompt destination — image-to-prompt lives inside Image Search
  /// and is also on the designer's Image to Prompt button.)
  int _tab = 0;

  String _mode = 'set_24h';
  final TextEditingController _promptCtrl = TextEditingController();
  final TextEditingController _negativeCtrl =
      TextEditingController(text: kDefaultNegativePrompt);
  final TextEditingController _landscapePromptCtrl = TextEditingController(
      text:
          'make it landscape mode, re-frame the exact same artwork for a foldable screen without cropping the main subject');
  final TextEditingController _subfolderCtrl =
      TextEditingController(text: 'Gemini_HD');
  bool _batchMode = false;

  /// Per-job batch states ('waiting' | 'running' | 'done' | 'failed'),
  /// index-aligned with parseBatchPrompts(_promptCtrl.text).
  List<String> _batchStatuses = const [];

  /// Set by the batch queue's Stop button: the running set finishes,
  /// the rest of the queue is skipped.
  bool _batchStop = false;
  String _storyArc = 'auto';
  String _variation = 'clear';
  String _displayTarget = 'any';
  String _colorBoost = 'off';
  bool _upscale = true;
  bool _autoMetadata = true;
  bool _foldableCompanion = false;
  bool _useHubFolders = true;
  bool _useExactNames = true;
  bool _aiDirector = false;
  bool _forcePrefix = true;
  int _portraitW = kPortraitWidth;
  int _portraitH = kPortraitHeight;
  int _landscapeW = kLandscapeWidth;
  int _landscapeH = kLandscapeHeight;
  ({Uint8List bytes, String name, String mime})? _reference;
  final Map<int, TextEditingController> _stageCtrls = {};

  /// Fires _silentRenew every 15 minutes while the app is open.
  Timer? _sessionKeepAlive;

  @override
  void initState() {
    super.initState();
    _engine = StudioEngine(onStatus: _onStatus);
    _bootstrap();
    // Keep the saved Gemini login alive: every 15 minutes the session
    // is silently re-fetched, which absorbs Google's rotated cookies
    // (__Secure-1PSIDTS) into the saved jar — the login stays saved
    // and renews itself while the app is open.
    _sessionKeepAlive =
        Timer.periodic(const Duration(minutes: 15), (_) => _silentRenew());
  }

  @override
  void dispose() {
    _sessionKeepAlive?.cancel();
    _promptCtrl.dispose();
    _negativeCtrl.dispose();
    _landscapePromptCtrl.dispose();
    _subfolderCtrl.dispose();
    for (final c in _stageCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _engine.loadCloudinaryConfig();
    _accountMode = await SessionStore.loadAccountMode();
    _accounts = await SessionStore.loadDiscoveredAccounts();
    _history = await _engine.loadHistory();
    final info = await SessionStore.loadActiveInfo();
    if (info != null && info['email'] != null) {
      _sessionLabel = 'u/${info['authUser']} - ${info['email']}';
    }
    if (mounted) setState(() {});
    // If a login was saved earlier, renew it right away (fresh session
    // token + rotated cookies) so the app opens already signed in.
    await _silentRenew();
  }

  /// Silent session renewal: re-fetches the Gemini session — which
  /// absorbs rotated cookies into the saved jar — without bothering
  /// the user. Runs once at startup when a saved login exists, then
  /// every 15 minutes while the app is open.
  Future<void> _silentRenew() async {
    if (_busy) return;
    try {
      final cookies = await SessionStore.loadCookiesByUser();
      if (cookies.isEmpty) return;
      final api = GeminiApi();
      // Renew EVERY saved account (scan probes u/0..u/5 and absorbs
      // each jar's rotated cookies), so accounts used only for
      // quota auto-switch stay alive too, not just the active one.
      final found = await api.scanAccounts();
      if (found.isNotEmpty && mounted) {
        setState(() => _accounts = found);
      }
      final explicit =
          _accountMode == 'auto' ? null : int.tryParse(_accountMode);
      final s = await api.getSession(
          forceRefresh: true, explicitAuthUser: explicit);
      if (mounted) {
        setState(() => _sessionLabel = 'u/${s.authUser} - ${s.email}');
      }
    } catch (_) {
      // Stay quiet: a failed silent renewal only means the user may
      // need to sign in again from the Gemini Login tab.
    }
  }

  void _onStatus(StatusEvent e) {
    if (!mounted) return;
    setState(() {
      _statusText = e.message;
      if (e.step > 0) _activeStep = e.step - 1;
      _log.insert(0, e.message);
      if (_log.length > 80) _log.removeLast();
    });
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _verifySession() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final api = GeminiApi(onStatus: _onStatus);
      final explicit =
          _accountMode == 'auto' ? null : int.tryParse(_accountMode);
      final s =
          await api.getSession(forceRefresh: true, explicitAuthUser: explicit);
      setState(() => _sessionLabel = 'u/${s.authUser} - ${s.email}');
      _snack('Gemini session active on u/${s.authUser} (${s.email})');
    } catch (e) {
      _snack('Session check failed: $e');
      _onStatus(StatusEvent('error', 1, 'Session check failed: $e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scanAccounts() async {
    if (_busy) return;
    setState(() => _busy = true);
    _onStatus(const StatusEvent('authenticating', 1,
        'Scanning saved logins for signed-in Gmail / Gemini accounts (u/0 to u/5)...'));
    try {
      final api = GeminiApi(onStatus: _onStatus);
      final found = await api.scanAccounts();
      setState(() => _accounts = found);
      if (found.isEmpty) {
        _snack(
            'No signed-in Gemini accounts detected. Use Gemini Login first.');
      } else {
        _snack(
            'Detected ${found.length} signed-in Gmail account(s): ${found.map((a) => 'u/${a.authUser} (${a.email})').join(', ')}');
      }
    } catch (e) {
      _snack('Scan failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _switchAccount(String mode) async {
    setState(() => _accountMode = mode);
    await SessionStore.saveAccountMode(mode);
    if (mode == 'auto') {
      _snack('Smart Auto-Switch enabled: will switch Gmail accounts on limit.');
      return;
    }
    await _verifySession();
  }

  Future<void> _openLogin({int authUser = 0}) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => LoginScreen(initialAuthUser: authUser),
    ));
    await _bootstrap();
    try {
      final api = GeminiApi();
      final found = await api.scanAccounts();
      if (mounted) setState(() => _accounts = found);
    } catch (_) {}
  }

  Future<void> _pickReference() async {
    final res = await FilePicker.platform
        .pickFiles(type: FileType.image, withData: true);
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    if (f.bytes == null) return;
    final lower = f.name.toLowerCase();
    final mime = lower.endsWith('.png')
        ? 'image/png'
        : lower.endsWith('.webp')
            ? 'image/webp'
            : 'image/jpeg';
    setState(() => _reference = (bytes: f.bytes!, name: f.name, mime: mime));
  }

  /// Image → Prompt now lives inside the Image Search screen
  /// (integrated flow: search/pick an image, generate its prompt in
  /// the actions sheet, send it here). The designer's Image to Prompt
  /// button lands on that integrated screen in prompt mode.
  Future<void> _openImageToPrompt() => _openImageSearch(promptMode: true);

  /// Image Search screen (Google Images / Pinterest in the built-in
  /// Chromium browser, mobile UA by default). The returned pick is
  /// applied by action: reference -> anchor image, prompt -> the
  /// prompt generated inside the search screen fills the designer
  /// field, save -> a copy under app documents /GeminiHDStudio/Search/.
  Future<void> _openImageSearch({bool promptMode = false}) async {
    final pick = await Navigator.of(context).push<ImageSearchPick>(
        MaterialPageRoute(
            builder: (_) => ImageSearchScreen(promptMode: promptMode)));
    if (pick == null || !mounted) return;
    switch (pick.action) {
      case 'reference':
        setState(() => _reference =
            (bytes: pick.bytes, name: pick.name, mime: pick.mime));
        _snack('Reference image set from Image Search.');
        break;
      case 'prompt':
        final generated = pick.generatedPrompt?.trim() ?? '';
        if (generated.isNotEmpty) {
          if (pick.appendPrompt) {
            // Auto-add to Prompts list: append as a new line so the
            // prompt joins the batch list instead of replacing it.
            final current = _promptCtrl.text.trim();
            setState(() => _promptCtrl.text =
                current.isEmpty ? generated : '$current\n$generated');
            _snack('Prompt added to the Prompts list.');
          } else {
            setState(() => _promptCtrl.text = generated);
            _snack('Prompt added to the Set Designer.');
          }
        } else {
          _snack('No prompt was generated.');
        }
        break;
      case 'prompts':
        // Multi-select batch generation: one prompt per selected
        // image — append them all as lines and switch Batch on so
        // they land straight in the Batch Sets queue.
        final list = pick.generatedPrompts
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        if (list.isEmpty) {
          _snack('No prompts were generated.');
          break;
        }
        final current = _promptCtrl.text.trim();
        setState(() {
          _promptCtrl.text =
              current.isEmpty ? list.join('\n') : '$current\n${list.join('\n')}';
          _batchMode = true;
        });
        _snack('${list.length} prompts added to the Batch Sets box.');
        break;
      case 'save':
        try {
          final docs = await getApplicationDocumentsDirectory();
          final dir = Directory(p.join(docs.path, 'GeminiHDStudio', 'Search'));
          await dir.create(recursive: true);
          final file = File(p.join(dir.path, pick.name));
          await file.writeAsBytes(pick.bytes);
          _snack('Saved image copy: ${file.path}');
        } catch (e) {
          _snack('Save failed: $e');
        }
        break;
    }
  }

  List<String?> _customStagesFor(int count) {
    return List.generate(count, (i) {
      final t = _stageCtrls[i]?.text.trim() ?? '';
      return t.isEmpty ? null : t;
    });
  }

  Future<void> _generate() async {
    if (_busy) return;
    final prompts = _batchMode
        ? parseBatchPrompts(_promptCtrl.text)
        : [_promptCtrl.text.trim()];
    if (prompts.isEmpty || prompts.first.isEmpty) {
      _snack('Write a prompt first.');
      return;
    }
    setState(() {
      _busy = true;
      _activeStep = 0;
    });
    final isSetMode =
        _mode == 'set_dual' || _mode == 'set_24h' || _mode == 'set_battery';
    final stageCount = isSetMode ? stagesForMode(_mode).length : 0;
    if (_batchMode) {
      setState(() {
        _batchStatuses = List.filled(prompts.length, 'waiting');
        _batchStop = false;
      });
    }
    var doneCount = 0;
    var failCount = 0;
    try {
      for (var i = 0; i < prompts.length; i++) {
        if (_batchMode && _batchStop) {
          _onStatus(StatusEvent('done', 4,
              'Batch stopped: $doneCount of ${prompts.length} sets done.'));
          break;
        }
        if (_batchMode) {
          setState(() => _batchStatuses[i] = 'running');
          _onStatus(StatusEvent('generating', 1,
              'Batch ${i + 1}/${prompts.length}: ${prompts[i]}'));
        }
        try {
          final entry = await _engine.generateSet(
          prompt: prompts[i],
          negativePrompt: _negativeCtrl.text,
          workflowMode: _mode,
          customStages: isSetMode ? _customStagesFor(stageCount) : const [],
          storyArc: _storyArc,
          variationStrength: _variation,
          displayTarget: _displayTarget,
          colorBoost: _colorBoost,
          aiDirectorEnabled: _aiDirector,
          autoWriteMetadata: _autoMetadata,
          includeFoldableCompanion: _foldableCompanion && isSetMode,
          landscapePrompt: _landscapePromptCtrl.text,
          referenceBytes: _reference?.bytes,
          referenceFilename: _reference?.name ?? 'reference_image.jpg',
          referenceMime: _reference?.mime ?? 'image/jpeg',
          forceImagePrefix: _forcePrefix,
          upscaleEnabled: _upscale,
          useExactZedgeNames: _useExactNames,
          subfolder: _subfolderCtrl.text.trim().isEmpty
              ? 'Gemini_HD'
              : _subfolderCtrl.text.trim(),
          portraitWidth: _portraitW,
          portraitHeight: _portraitH,
          landscapeWidth: _landscapeW,
          landscapeHeight: _landscapeH,
        );
          setState(() {
            _history = [entry, ..._history];
            if (_batchMode) _batchStatuses[i] = 'done';
          });
          doneCount++;
        } catch (e) {
          if (!_batchMode) rethrow;
          failCount++;
          setState(() => _batchStatuses[i] = 'failed');
          _onStatus(StatusEvent(
              'error', 1, 'Batch ${i + 1}/${prompts.length} failed: $e'));
        }
      }
      if (_batchMode && prompts.length > 1) {
        _snack(failCount == 0
            ? 'Batch finished: $doneCount sets generated.'
            : 'Batch finished: $doneCount done, $failCount failed.');
      }
    } catch (e) {
      _onStatus(StatusEvent('error', 1, 'Generation failed: $e'));
      _snack('Generation failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importSet() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;
    final files = res.files
        .where((f) => f.bytes != null)
        .map((f) => (bytes: f.bytes!, filename: f.name))
        .toList();
    if (files.isEmpty || !mounted) return;
    final mode =
        (_mode == 'single' || _mode == 'dual_single') ? 'set_24h' : _mode;
    final conceptCtrl = TextEditingController(text: _promptCtrl.text.trim());
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import set'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                '${files.length} image(s) selected. They are formatted to ${_portraitW}x$_portraitH JPG and land in the Showcase as a ${setTypeLabelFor(mode)}.'),
            const SizedBox(height: 12),
            TextField(
              controller: conceptCtrl,
              decoration: const InputDecoration(
                labelText: 'Set concept (for AI metadata)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Import')),
        ],
      ),
    );
    if (go != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final entry = await _engine.importLocalSet(
        files: files,
        workflowMode: mode,
        prompt: conceptCtrl.text.trim(),
        upscaleEnabled: _upscale,
        autoWriteMetadata: _autoMetadata,
        subfolder: _subfolderCtrl.text.trim().isEmpty
            ? 'Gemini_HD'
            : _subfolderCtrl.text.trim(),
        portraitWidth: _portraitW,
        portraitHeight: _portraitH,
      );
      setState(() => _history = [entry, ..._history]);
    } catch (e) {
      _snack('Import failed: $e');
      _onStatus(StatusEvent('error', 1, 'Import failed: $e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshHistory() async {
    final h = await _engine.loadHistory();
    if (mounted) setState(() => _history = h);
  }

  Future<void> _clearHistory() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Showcase?'),
        content: const Text(
            'This removes the set list from the app. Image files stay in the app documents folder.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Clear')),
        ],
      ),
    );
    if (go == true) {
      await _engine.saveHistory([]);
      setState(() => _history = []);
    }
  }

  void _showPathDialog(String title, String path) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SelectableText(path),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: path));
              Navigator.pop(ctx);
            },
            child: const Text('Copy path'),
          ),
          FilledButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _exportZip(List<SetEntry> entries) async {
    if (entries.isEmpty) {
      _snack('No sets to export.');
      return;
    }
    setState(() => _busy = true);
    try {
      final f = await _engine.buildReadyZip(entries,
          useHubSetFolders: _useHubFolders);
      _showPathDialog('Ready ZIP saved', f.path);
    } catch (e) {
      _snack('ZIP failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportMetadataJson(List<SetEntry> entries) async {
    if (entries.isEmpty) {
      _snack('No sets yet.');
      return;
    }
    try {
      final f = await _engine.buildStandaloneMetadataJson(entries);
      _showPathDialog('metadata.json saved', f.path);
    } catch (e) {
      _snack('metadata.json failed: $e');
    }
  }

  Future<void> _writeAllMetadata() async {
    if (_busy || _history.isEmpty) return;
    setState(() => _busy = true);
    try {
      for (final entry in _history) {
        if (entry.metadata == null || entry.metadata!.title.isEmpty) {
          await _engine.generateMetadataForEntry(entry);
        }
      }
      await _refreshHistory();
    } catch (e) {
      _snack('Metadata failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _uploadAllToPanel() async {
    if (_busy || _history.isEmpty) return;
    setState(() => _busy = true);
    try {
      for (final entry in _history) {
        await _engine.uploadSetToPanel(entry);
      }
      await _refreshHistory();
      _snack('All sets uploaded to Panel.');
    } catch (e) {
      _snack('Panel upload failed: $e');
      _onStatus(StatusEvent('error', 4, 'Panel upload failed: $e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // -------------------------------------------------------------------
  // Dashboard shell: gradient header + badge navigation + tab body
  // -------------------------------------------------------------------

  void _onNavSelected(int i) {
    if (i <= 1) {
      setState(() => _tab = i);
    } else if (i == 2) {
      _openImageSearch();
    } else if (i == 3) {
      _openLogin();
    }
  }

  Widget _navIcon(IconData icon, int badgeCount) {
    if (badgeCount <= 0) return Icon(icon);
    return Badge(
      label: Text('$badgeCount'),
      backgroundColor: kDashboardScheme.tertiary,
      textColor: Colors.white,
      child: Icon(icon),
    );
  }

  List<NavigationDestination> get _destinations => [
        const NavigationDestination(
          icon: Icon(Icons.dashboard_outlined),
          selectedIcon: Icon(Icons.dashboard),
          label: 'Studio',
        ),
        NavigationDestination(
          icon: _navIcon(Icons.grid_view_outlined, _history.length),
          selectedIcon: _navIcon(Icons.grid_view, _history.length),
          label: 'Showcase',
        ),
        const NavigationDestination(
          icon: Icon(Icons.image_search_outlined),
          selectedIcon: Icon(Icons.image_search),
          label: 'Search',
        ),
        NavigationDestination(
          icon: _navIcon(Icons.account_circle_outlined, _accounts.length),
          selectedIcon: _navIcon(Icons.account_circle, _accounts.length),
          label: 'Login',
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 900;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _dashboardHeader(wide),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (wide)
                    NavigationRail(
                      selectedIndex: _tab,
                      onDestinationSelected: _onNavSelected,
                      labelType: NavigationRailLabelType.all,
                      destinations: [
                        for (final d in _destinations)
                          NavigationRailDestination(
                            icon: d.icon,
                            selectedIcon: d.selectedIcon,
                            label: Text(d.label),
                          ),
                      ],
                    ),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                                  begin: const Offset(0.03, 0),
                                  end: Offset.zero)
                              .animate(animation),
                          child: child,
                        ),
                      ),
                      child: KeyedSubtree(
                        key: ValueKey(_tab),
                        child: _tabBody(wide),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: _onNavSelected,
              destinations: _destinations,
            ),
    );
  }

  Widget _tabBody(bool wide) {
    if (_tab == 1) return _showcasePanel();
    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 430, child: _designerPanel()),
          const VerticalDivider(width: 1),
          Expanded(child: _showcasePanel()),
        ],
      );
    }
    return _designerPanel();
  }

  /// Prominent dashboard header: gradient banner with the app title,
  /// quick actions, the account controls and live stat badges.
  Widget _dashboardHeader(bool wide) {
    return Container(
      decoration: const BoxDecoration(gradient: kHeaderGradient),
      padding: EdgeInsets.fromLTRB(16, wide ? 16 : 12, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/logo.png',
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Gemini HD Studio',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                    Text(
                      'Wallpaper Set Designer - AI Metadata - Panel Uploader',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Import local set',
                color: Colors.white,
                onPressed: _busy ? null : _importSet,
                icon: const Icon(Icons.folder_open_outlined),
              ),
              IconButton(
                tooltip: 'Panel upload settings',
                color: Colors.white,
                onPressed: () async {
                  await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => PanelSettingsScreen(engine: _engine)));
                },
                icon: const Icon(Icons.cloud_upload_outlined),
              ),
              IconButton(
                tooltip: 'Gemini Login',
                color: Colors.white,
                onPressed: () => _openLogin(),
                icon: const Icon(Icons.account_circle_outlined),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _accountBar(),
          if (wide) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _statChip(Icons.grid_view_outlined, '${_history.length} sets'),
                _statChip(Icons.alternate_email, '${_accounts.length} Gmail'),
                _statChip(Icons.photo_size_select_large_outlined,
                    '${_portraitW}x$_portraitH JPG'),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _statChip(IconData icon, String label) {
    return Chip(
      avatar: Icon(icon, size: 14, color: kDashboardScheme.secondary),
      label: Text(label,
          style: const TextStyle(fontSize: 11.5, color: Colors.white)),
      backgroundColor: Colors.white.withOpacity(0.13),
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _accountBar() {
    final lightBtn = OutlinedButton.styleFrom(
      foregroundColor: Colors.white,
      side: const BorderSide(color: Colors.white38),
      visualDensity: VisualDensity.compact,
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          DropdownButton<String>(
            value: _accountMode,
            underline: const SizedBox.shrink(),
            dropdownColor: const Color(0xFF171F3D),
            iconEnabledColor: Colors.white,
            style: const TextStyle(color: Colors.white, fontSize: 13.5),
            items: [
              DropdownMenuItem(
                value: 'auto',
                child: Text(_accounts.length > 1
                    ? 'Auto-switch on limit (${_accounts.length} Gmails)'
                    : 'Auto-switch on limit'),
              ),
              for (var u = 0; u < 6; u++)
                DropdownMenuItem(
                  value: '$u',
                  child: Text(_accounts.any((a) => a.authUser == u)
                      ? 'u/$u - ${_accounts.firstWhere((a) => a.authUser == u).email}'
                      : 'u/$u - Gmail Account #${u + 1}'),
                ),
            ],
            onChanged: (v) {
              if (v != null) _switchAccount(v);
            },
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            style: lightBtn,
            onPressed: _busy ? null : _scanAccounts,
            icon: const Icon(Icons.search, size: 16),
            label: const Text('Scan'),
          ),
          const SizedBox(width: 6),
          OutlinedButton.icon(
            style: lightBtn,
            onPressed: () => _openLogin(
                authUser: _accountMode == 'auto'
                    ? 0
                    : int.tryParse(_accountMode) ?? 0),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add Gmail'),
          ),
          const SizedBox(width: 6),
          OutlinedButton.icon(
            style: lightBtn,
            onPressed: _busy ? null : _verifySession,
            icon: const Icon(Icons.verified_outlined, size: 16),
            label: const Text('Verify'),
          ),
          const SizedBox(width: 10),
          Chip(
            avatar: Icon(Icons.bolt,
                size: 14, color: kDashboardScheme.secondary),
            label: Text(_sessionLabel,
                style: const TextStyle(fontSize: 12, color: Colors.white)),
            backgroundColor: Colors.white.withOpacity(0.13),
            side: BorderSide.none,
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------
  // Batch queue panel (batch mode): every prompt line is one job with
  // a live status — waiting / running / done / failed — plus a Stop
  // control that lets the current set finish and skips the rest.
  // -------------------------------------------------------------------

  Widget _batchQueuePanel() {
    final prompts = parseBatchPrompts(_promptCtrl.text);
    final scheme = Theme.of(context).colorScheme;
    if (prompts.isEmpty) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Batch mode: write one prompt per line — each line generates one full set, in order.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      );
    }
    final done = _batchStatuses.where((s) => s == 'done').length;
    final running = _busy && _batchMode;
    return Container(
      width: double.infinity,
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
              const Icon(Icons.queue_outlined,
                  size: 16, color: Color(0xFF7C6CFF)),
              const SizedBox(width: 6),
              const Text('Batch queue',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(width: 8),
              Chip(
                label: Text(_batchStatuses.isEmpty
                    ? '${prompts.length} set${prompts.length == 1 ? '' : 's'}'
                    : '$done/${prompts.length} done'),
                visualDensity: VisualDensity.compact,
                labelStyle: const TextStyle(fontSize: 11),
              ),
              const Spacer(),
              if (running)
                TextButton.icon(
                  onPressed: () => setState(() => _batchStop = true),
                  icon: const Icon(Icons.stop_circle_outlined, size: 16),
                  label: const Text('Stop after current',
                      style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 168),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: prompts.length,
              itemBuilder: (ctx, i) {
                final st = i < _batchStatuses.length
                    ? _batchStatuses[i]
                    : 'waiting';
                final (icon, color) = switch (st) {
                  'running' => (Icons.autorenew, scheme.primary),
                  'done' => (Icons.check_circle, Colors.green),
                  'failed' => (Icons.error, scheme.error),
                  _ => (Icons.schedule, Colors.grey),
                };
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 18,
                        child: Text('${i + 1}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey)),
                      ),
                      if (st == 'running')
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child:
                              CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Icon(icon, size: 16, color: color),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          prompts[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: st == 'waiting' ? Colors.grey : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(st,
                          style: TextStyle(fontSize: 11, color: color)),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------
  // Set Designer panel
  // -------------------------------------------------------------------

  Widget _designerPanel() {
    final isSetMode =
        _mode == 'set_dual' || _mode == 'set_24h' || _mode == 'set_battery';
    final stages = isSetMode ? stagesForMode(_mode) : const <StageDef>[];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Row(
            children: [
              const Icon(Icons.tune, size: 20, color: Color(0xFF7C6CFF)),
              const SizedBox(width: 8),
              const Text('Set Designer',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const Spacer(),
              Flexible(
                child: Text(
                  'JPG · ≤8MB · ${(_portraitW * _portraitH / 1000000).toStringAsFixed(2)} MP',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _modeChip('dual_single', '9:16 + Foldable'),
              _modeChip('single', 'Single 9:16'),
              _modeChip('set_dual', 'Dual Set (2)'),
              _modeChip('set_24h', '24-Hour Set (4)'),
              _modeChip('set_battery', 'Battery Set (6)'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _promptCtrl,
                  minLines: 3,
                  maxLines: _batchMode ? 8 : 4,
                  onChanged: (_) {
                    // Keep the batch queue panel in sync while typing;
                    // editing the list clears the last run's marks.
                    if (_batchMode) {
                      setState(() => _batchStatuses = const []);
                    }
                  },
                  decoration: InputDecoration(
                    labelText:
                        _batchMode ? 'Prompts (1 line = 1 set)' : 'Prompt',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Batch', style: TextStyle(fontSize: 13)),
                Switch(
                  value: _batchMode,
                  onChanged: (v) => setState(() {
                    _batchMode = v;
                    _batchStatuses = const [];
                  }),
                ),
              ],
            ),
          ),
          if (_batchMode) ...[
            _batchQueuePanel(),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: _pickReference,
            icon: const Icon(Icons.image_outlined, size: 18),
            label: Text(
              _reference == null
                  ? 'Reference image (optional)'
                  : 'Reference: ${_reference!.name.length > 26 ? '${_reference!.name.substring(0, 23)}...' : _reference!.name}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_reference != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => setState(() => _reference = null),
                child: const Text('Remove reference'),
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              OutlinedButton.icon(
                onPressed: () => _openImageToPrompt(),
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text('Image to Prompt'),
              ),
              OutlinedButton.icon(
                onPressed: _openImageSearch,
                icon: const Icon(Icons.image_search_outlined, size: 18),
                label: const Text('Search images'),
              ),
            ],
          ),
          if (_mode == 'dual_single' || _foldableCompanion) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _landscapePromptCtrl,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Foldable adaptation prompt',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 12),
          // High-contrast gradient call-to-action (violet -> cyan).
          Container(
            decoration: BoxDecoration(
              gradient: _busy ? null : kAccentGradient,
              color: _busy
                  ? Theme.of(context).colorScheme.surfaceContainerHighest
                  : null,
              borderRadius: BorderRadius.circular(12),
            ),
            child: FilledButton.icon(
              onPressed: _busy ? null : _generate,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome),
              label: Text(_busy ? 'Working...' : 'Generate set'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                minimumSize: const Size.fromHeight(52),
                textStyle: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _stepper(),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(right: 8, top: 2),
                    child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                Expanded(
                    child: Text(_statusText,
                        style: const TextStyle(fontSize: 13))),
              ],
            ),
          ),
          ExpansionTile(
            title: const Text('Advanced settings'),
            subtitle: const Text('Negative prompt - Style - Stages - Output',
                style: TextStyle(fontSize: 12)),
            children: [
              TextField(
                controller: _negativeCtrl,
                minLines: 2,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Negative prompt',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: 'Reset default',
                    icon: const Icon(Icons.restart_alt, size: 18),
                    onPressed: () => setState(
                        () => _negativeCtrl.text = kDefaultNegativePrompt),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (_mode == 'set_24h')
                _dropdownRow(
                    'Story arc',
                    _storyArc,
                    const {
                      'auto': 'Auto (Smart Pick)',
                      'light': 'Light Only',
                      'bloom': 'Bloom Cycle',
                      'rhythm': 'Daily Rhythm',
                    },
                    (v) => setState(() => _storyArc = v)),
              if (_mode == 'set_battery')
                _dropdownRow(
                    'Story arc',
                    _storyArc,
                    const {
                      'auto': 'Auto (Smart Pick)',
                      'energy': 'Energy Glow',
                      'growth': 'Growth',
                      'awaken': 'Awakening',
                    },
                    (v) => setState(() => _storyArc = v)),
              if (isSetMode)
                _dropdownRow(
                    'Variation',
                    _variation,
                    const {
                      'subtle': 'Subtle',
                      'clear': 'Clear',
                      'strong': 'Strong',
                    },
                    (v) => setState(() => _variation = v)),
              _dropdownRow(
                  'Display',
                  _displayTarget,
                  const {
                    'any': 'Any',
                    'amoled': 'AMOLED',
                    'ips': 'IPS',
                  },
                  (v) => setState(() => _displayTarget = v)),
              _dropdownRow(
                  'Colour',
                  _colorBoost,
                  const {
                    'off': 'Off',
                    'subtle': 'Subtle',
                    'vivid': 'Vivid',
                    'neon': 'Neon',
                  },
                  (v) => setState(() => _colorBoost = v)),
              if (isSetMode) ...[
                const SizedBox(height: 6),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Stages (leave empty = auto arc/director)',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                ),
                const SizedBox(height: 6),
                for (var i = 0; i < stages.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextField(
                      controller: _stageCtrls.putIfAbsent(
                          i, () => TextEditingController()),
                      decoration: InputDecoration(
                        labelText: stages[i].badge,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                      child: _sizeField('Phone W', _portraitW,
                          (v) => setState(() => _portraitW = v))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _sizeField('Phone H', _portraitH,
                          (v) => setState(() => _portraitH = v))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _sizeField('Foldable W', _landscapeW,
                          (v) => setState(() => _landscapeW = v))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _sizeField('Foldable H', _landscapeH,
                          (v) => setState(() => _landscapeH = v))),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _subfolderCtrl,
                decoration: const InputDecoration(
                  labelText: 'Folder name (inside app documents)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              _toggleRow('Cloudinary AI Upscale', _upscale,
                  (v) => setState(() => _upscale = v)),
              _toggleRow('Auto metadata', _autoMetadata,
                  (v) => setState(() => _autoMetadata = v)),
              if (isSetMode)
                _toggleRow('AI Set Director plan', _aiDirector,
                    (v) => setState(() => _aiDirector = v)),
              if (isSetMode)
                _toggleRow('+ Foldable companion', _foldableCompanion,
                    (v) => setState(() => _foldableCompanion = v)),
              _toggleRow('Ready Folder (set-01/)', _useHubFolders,
                  (v) => setState(() => _useHubFolders = v)),
              _toggleRow('Zedge file names', _useExactNames,
                  (v) => setState(() => _useExactNames = v)),
              _toggleRow('Auto-prefix image verb', _forcePrefix,
                  (v) => setState(() => _forcePrefix = v)),
              const SizedBox(height: 8),
            ],
          ),
          if (_log.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text('Log',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 4),
            Container(
              constraints: const BoxConstraints(maxHeight: 130),
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView(
                reverse: false,
                children: [
                  for (final line in _log)
                    Text(line,
                        style: const TextStyle(
                            fontSize: 11, color: Colors.white70)),
                ],
              ),
            ),
            ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _modeChip(String value, String label) {
    final selected = _mode == value;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: (_) => setState(() {
        _mode = value;
        _storyArc = 'auto';
      }),
    );
  }

  Widget _stepper() {
    const labels = ['Generate', 'Anchor Sync', 'Stages', 'Metadata'];
    return Row(
      children: [
        for (var i = 0; i < 4; i++) ...[
          Column(
            children: [
              CircleAvatar(
                radius: 13,
                backgroundColor: _busy && i == _activeStep
                    ? Theme.of(context).colorScheme.primary
                    : i < _activeStep ||
                            (!_busy && _statusText.startsWith('Ready in'))
                        ? Colors.green
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Text('${i + 1}',
                    style: const TextStyle(fontSize: 11, color: Colors.white)),
              ),
              const SizedBox(height: 3),
              SizedBox(
                width: 64,
                child: Text(labels[i],
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10)),
              ),
            ],
          ),
          if (i < 3)
            const Expanded(
                child: Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Divider(),
            )),
        ],
      ],
    );
  }

  Widget _dropdownRow(String label, String value, Map<String, String> options,
      ValueChanged<String> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
              width: 86,
              child: Text(label, style: const TextStyle(fontSize: 13))),
          Expanded(
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              value: value,
              isDense: true,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: options.entries
                  .map((e) =>
                      DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _sizeField(String label, int value, ValueChanged<int> onChanged) {
    return TextFormField(
      initialValue: '$value',
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
          labelText: label, border: const OutlineInputBorder(), isDense: true),
      onChanged: (t) {
        final v = int.tryParse(t);
        if (v != null && v > 0) onChanged(v);
      },
    );
  }

  Widget _toggleRow(String label, bool value, ValueChanged<bool> onChanged) {
    return Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }

  // -------------------------------------------------------------------
  // Showcase panel
  // -------------------------------------------------------------------

  Widget _showcasePanel() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.grid_view_outlined,
                      size: 20, color: Color(0xFF22D3EE)),
                  const SizedBox(width: 8),
                  const Text('Showcase',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  if (_history.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: kDashboardScheme.tertiary,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text('${_history.length}',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white)),
                    ),
                  ],
                  const Spacer(),
                  IconButton(
                    tooltip: 'Clear history',
                    onPressed: _history.isEmpty ? null : _clearHistory,
                    icon: const Icon(Icons.delete_outline, size: 18),
                  ),
                ],
              ),
              Wrap(
                spacing: 2,
                runSpacing: 0,
                children: [
                  TextButton.icon(
                    onPressed: _busy || _history.isEmpty ? null : _writeAllMetadata,
                    icon: const Icon(Icons.description_outlined, size: 16),
                    label: const Text('Metadata (all)'),
                  ),
                  TextButton.icon(
                    onPressed:
                        _history.isEmpty ? null : () => _exportZip(_history),
                    icon: const Icon(Icons.archive_outlined, size: 16),
                    label: const Text('Ready ZIP'),
                  ),
                  TextButton.icon(
                    onPressed: _history.isEmpty
                        ? null
                        : () => _exportMetadataJson(_history),
                    icon: const Icon(Icons.code, size: 16),
                    label: const Text('metadata.json'),
                  ),
                  TextButton.icon(
                    onPressed: _busy || _history.isEmpty ? null : _uploadAllToPanel,
                    icon: const Icon(Icons.cloud_upload_outlined, size: 16),
                    label: const Text('Upload to Panel'),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: _history.isEmpty
              ? const Center(
                  child: Text(
                      'No sets yet.\nSign in with Gemini, write a prompt and Generate.',
                      textAlign: TextAlign.center),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _history.length,
                  itemBuilder: (ctx, i) => SetCard(
                    entry: _history[i],
                    engine: _engine,
                    onChanged: _refreshHistory,
                    onExportZip: (e) => _exportZip([e]),
                    snack: _snack,
                  ),
                ),
        ),
      ],
    );
  }
}

/// One finished set in the Showcase.
class SetCard extends StatefulWidget {
  final SetEntry entry;
  final StudioEngine engine;
  final Future<void> Function() onChanged;
  final void Function(SetEntry) onExportZip;
  final void Function(String) snack;
  const SetCard({
    super.key,
    required this.entry,
    required this.engine,
    required this.onChanged,
    required this.onExportZip,
    required this.snack,
  });

  @override
  State<SetCard> createState() => _SetCardState();
}

class _SetCardState extends State<SetCard> {
  bool _working = false;
  String _uploadTarget = 'spread';

  Future<void> _run(Future<void> Function() fn, String failPrefix) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await fn();
      await widget.onChanged();
    } catch (e) {
      widget.snack('$failPrefix: $e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final meta = entry.metadata;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(entry.setTypeLabel,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                Text(entry.createdAtIso.replaceAll('T', ' ').split('.').first,
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 2),
            Text(entry.prompt,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            if (entry.uploadedToPanel != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Chip(
                  avatar: const Icon(Icons.check_circle_outline, size: 14),
                  label: Text(
                      'Queued on ${entry.uploadedToPanel!['accountName']}',
                      style: const TextStyle(fontSize: 11)),
                ),
              ),
            const SizedBox(height: 8),
            SizedBox(
              height: 150,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: entry.images.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (ctx, i) {
                  final img = entry.images[i];
                  final file = File(img.localPath);
                  return GestureDetector(
                    onTap: () => _openLightbox(img),
                    child: Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: file.existsSync()
                              ? Image.file(file,
                                  width: 84, height: 112, fit: BoxFit.cover)
                              : Container(
                                  width: 84,
                                  height: 112,
                                  color: Colors.black26,
                                  child:
                                      const Icon(Icons.broken_image_outlined),
                                ),
                        ),
                        const SizedBox(height: 3),
                        SizedBox(
                          width: 84,
                          child: Text(img.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 10)),
                        ),
                        Text(
                            '${(img.byteSize / 1048576).toStringAsFixed(2)} MB${img.zedgeCompliant ? ' - OK' : ''}',
                            style: const TextStyle(
                                fontSize: 9, color: Colors.grey)),
                      ],
                    ),
                  );
                },
              ),
            ),
            if (meta != null && meta.title.isNotEmpty) ...[
              const Divider(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(meta.title,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14)),
                        Text(meta.keywords,
                            style: const TextStyle(
                                fontSize: 11, color: Colors.grey)),
                        Text('${meta.category} - ${meta.description}',
                            style: const TextStyle(fontSize: 11)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy title',
                    icon: const Icon(Icons.copy, size: 16),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: meta.title));
                      widget.snack('Title copied');
                    },
                  ),
                  IconButton(
                    tooltip: 'Copy tags CSV',
                    icon: const Icon(Icons.tag, size: 16),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: meta.keywords));
                      widget.snack('Tags copied');
                    },
                  ),
                ],
              ),
            ],
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                OutlinedButton.icon(
                  onPressed: _working
                      ? null
                      : () => _run(() async {
                            await widget.engine.generateMetadataForEntry(entry);
                          }, 'Metadata failed'),
                  icon: const Icon(Icons.auto_awesome, size: 15),
                  label: Text(meta == null || meta.title.isEmpty
                      ? 'AI Metadata'
                      : 'Rewrite with AI'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _editMetadata(entry),
                  icon: const Icon(Icons.edit_outlined, size: 15),
                  label: const Text('Edit metadata'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _openSimulator(entry),
                  icon: const Icon(Icons.smartphone_outlined, size: 15),
                  label: const Text('Preview set'),
                ),
                OutlinedButton.icon(
                  onPressed: () => widget.onExportZip(entry),
                  icon: const Icon(Icons.archive_outlined, size: 15),
                  label: const Text('Ready ZIP'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            LayoutBuilder(
              builder: (ctx, constraints) {
                final targetDropdown = FutureBuilder<DistConfig>(
                  future: widget.engine.loadDistConfig(),
                  builder: (ctx, snap) {
                    final accounts =
                        snap.data?.accounts ?? const <DistAccount>[];
                    return DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: _uploadTarget,
                      isDense: true,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Panel target',
                      ),
                      items: [
                        const DropdownMenuItem(
                            value: 'spread',
                            child: Text('Spread (Auto-Rotate)')),
                        for (final a in accounts)
                          DropdownMenuItem(value: a.name, child: Text(a.name)),
                      ],
                      onChanged: (v) =>
                          setState(() => _uploadTarget = v ?? 'spread'),
                    );
                  },
                );
                final uploadButton = FilledButton.icon(
                  onPressed: _working
                      ? null
                      : () => _run(() async {
                            final r = await widget.engine.uploadSetToPanel(
                                entry,
                                targetAccount: _uploadTarget);
                            widget.snack(
                                'Uploaded to ${r.accountName} (key ${r.firebaseKey})');
                          }, 'Panel upload failed'),
                  icon: const Icon(Icons.cloud_upload_outlined, size: 16),
                  label: const Text('Upload to Panel'),
                );
                // Phones: stack the target dropdown and the upload
                // button full-width instead of squeezing them side by
                // side (which overflowed / became untappable < 430px).
                if (constraints.maxWidth < 430) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      targetDropdown,
                      const SizedBox(height: 8),
                      uploadButton,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: targetDropdown),
                    const SizedBox(width: 8),
                    uploadButton,
                  ],
                );
              },
            ),
            if (_working)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(),
              ),
          ],
        ),
      ),
    );
  }

  void _openLightbox(SetImage img) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                        '${img.badge} - ${img.width}x${img.height} JPG - ${(img.byteSize / 1048576).toStringAsFixed(2)} MB',
                        style: const TextStyle(fontSize: 13)),
                  ),
                  IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close)),
                ],
              ),
            ),
            Flexible(
              child: File(img.localPath).existsSync()
                  ? Image.file(File(img.localPath), fit: BoxFit.contain)
                  : const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('File missing on this device.'),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Wrap(
                spacing: 6,
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: img.localPath));
                      widget.snack('Image path copied');
                    },
                    icon: const Icon(Icons.copy, size: 15),
                    label: const Text('Copy path'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _run(() async {
                      await widget.engine.regenerateStage(widget.entry, img);
                      if (ctx.mounted) Navigator.pop(ctx);
                    }, 'Regenerate failed'),
                    icon: const Icon(Icons.refresh, size: 15),
                    label: const Text('Regenerate this stage'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openSimulator(SetEntry entry) {
    var index = 0;
    Timer? timer;
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final img = entry.images[index.clamp(0, entry.images.length - 1)];
          // Scale the phone preview down on short phone screens and let
          // the dialog scroll, so it never overflows small displays.
          final screenH = MediaQuery.of(ctx).size.height;
          final previewW = screenH < 640 ? 148.0 : 190.0;
          final previewH = previewW * 340 / 190;
          return Dialog(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                  Row(
                    children: [
                      const Expanded(
                          child: Text('Set preview',
                              style: TextStyle(fontWeight: FontWeight.w700))),
                      IconButton(
                        tooltip: 'Auto-cycle',
                        onPressed: () {
                          if (timer != null) {
                            timer!.cancel();
                            timer = null;
                          } else {
                            timer =
                                Timer.periodic(const Duration(seconds: 2), (_) {
                              setLocal(() =>
                                  index = (index + 1) % entry.images.length);
                            });
                          }
                          setLocal(() {});
                        },
                        icon: Icon(
                            timer != null ? Icons.pause : Icons.play_arrow),
                      ),
                      IconButton(
                          onPressed: () {
                            timer?.cancel();
                            Navigator.pop(ctx);
                          },
                          icon: const Icon(Icons.close)),
                    ],
                  ),
                  Container(
                    width: previewW,
                    height: previewH,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white24),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (File(img.localPath).existsSync())
                          Image.file(File(img.localPath), fit: BoxFit.cover),
                        const Positioned(
                          top: 26,
                          left: 0,
                          right: 0,
                          child: Column(
                            children: [
                              Text('09:41',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 34,
                                      fontWeight: FontWeight.w300,
                                      shadows: [
                                        Shadow(
                                            blurRadius: 8,
                                            color: Colors.black54)
                                      ])),
                              Text('Saturday, November 7',
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 11)),
                            ],
                          ),
                        ),
                        Positioned(
                          bottom: 12,
                          left: 0,
                          right: 0,
                          child: Text(img.exactFilename,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 9)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    alignment: WrapAlignment.center,
                    children: [
                      for (var i = 0; i < entry.images.length; i++)
                        ChoiceChip(
                          label: Text(entry.images[i].label,
                              style: const TextStyle(fontSize: 11)),
                          selected: i == index,
                          onSelected: (_) => setLocal(() => index = i),
                        ),
                    ],
                  ),
                  Text(
                      '${img.width}x${img.height} px - JPEG - ${img.megapixels.toStringAsFixed(2)} MP',
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ).then((_) => timer?.cancel());
  }

  Future<void> _editMetadata(SetEntry entry) async {
    final meta = entry.metadata ?? SetMetadata();
    final titleCtrl = TextEditingController(text: meta.title);
    final tagsCtrl = TextEditingController(text: meta.keywords);
    final descCtrl = TextEditingController(text: meta.description);
    var category = meta.category.isEmpty ? 'DESIGNS' : meta.category;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit metadata'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                maxLength: 30,
                decoration: const InputDecoration(
                    labelText: 'Title (max 30 chars)',
                    border: OutlineInputBorder()),
              ),
              DropdownButtonFormField<String>(
                isExpanded: true,
                value: category,
                decoration: const InputDecoration(
                    labelText: 'Zedge category', border: OutlineInputBorder()),
                items: kZedgeCategories
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => category = v ?? category,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: tagsCtrl,
                decoration: const InputDecoration(
                    labelText: 'Tags (comma-separated)',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descCtrl,
                maxLength: 200,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                    labelText: 'Description (max 200 chars)',
                    border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (saved == true) {
      final tags = tagsCtrl.text
          .split(',')
          .map((e) =>
              e.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), ''))
          .where((e) => e.isNotEmpty)
          .toSet()
          .take(12)
          .toList();
      entry.metadata = SetMetadata(
        file: meta.file,
        title: titleCtrl.text.trim(),
        tags: tags,
        category: category,
        description: descCtrl.text.trim(),
        generatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      final history = await widget.engine.loadHistory();
      final idx = history.indexWhere((h) => h.id == entry.id);
      if (idx >= 0) history[idx] = entry;
      await widget.engine.saveHistory(history);
      await widget.onChanged();
    }
  }
}
