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
import 'package:shared_preferences/shared_preferences.dart';

import 'foreground_keep_alive.dart';
import 'gemini_api.dart';
import 'image_search.dart';
import 'login_screen.dart';
import 'models.dart';
import 'originality.dart';
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
  primary: Color(0xFF8B7CFF),
  onPrimary: Colors.white,
  primaryContainer: Color(0xFF37298F),
  onPrimaryContainer: Color(0xFFE6E0FF),
  secondary: Color(0xFF22D3EE),
  onSecondary: Color(0xFF04222B),
  secondaryContainer: Color(0xFF0E3A47),
  onSecondaryContainer: Color(0xFFB9F1FD),
  tertiary: Color(0xFFFF7AC6),
  onTertiary: Color(0xFF2B0A1E),
  error: Color(0xFFFF6B6B),
  onError: Colors.white,
  surface: Color(0xFF111A33),
  onSurface: Color(0xFFF2F4FF),
  surfaceContainerLowest: Color(0xFF070A14),
  surfaceContainerLow: Color(0xFF0C1122),
  surfaceContainer: Color(0xFF141E3C),
  surfaceContainerHigh: Color(0xFF1A2650),
  surfaceContainerHighest: Color(0xFF22305F),
  onSurfaceVariant: Color(0xFFB9C0D8),
  outline: Color(0xFF414C7E),
  outlineVariant: Color(0xFF2A3560),
  inverseSurface: Color(0xFFE8EBFF),
  onInverseSurface: Color(0xFF12172E),
  inversePrimary: Color(0xFF4B3FD1),
);

const LinearGradient kHeaderGradient = LinearGradient(
  colors: [Color(0xFF2B3A8C), Color(0xFF5E2FA6), Color(0xFF0B5A70)],
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

/// Aurora backdrop (v34 redesign): deep-space base with soft
/// violet / cyan / pink glows behind the dashboard, so the whole
/// home screen reads as one designed surface. Pushed screens keep
/// the solid base colour from the theme.
class AuroraBackdrop extends StatelessWidget {
  const AuroraBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return const Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: Color(0xFF070A14)),
        Positioned(
          top: -130,
          left: -90,
          child: _Glow(color: Color(0xFF7C6CFF), size: 320, alpha: 0.20),
        ),
        Positioned(
          top: 190,
          right: -120,
          child: _Glow(color: Color(0xFFFF7AC6), size: 240, alpha: 0.08),
        ),
        Positioned(
          bottom: -150,
          right: -70,
          child: _Glow(color: Color(0xFF22D3EE), size: 340, alpha: 0.14),
        ),
      ],
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size, required this.alpha});
  final Color color;
  final double size;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [
            color.withValues(alpha: alpha),
            color.withValues(alpha: 0),
          ]),
        ),
      ),
    );
  }
}

/// The app-wide theme (v34 Aurora Glass redesign), shared by
/// the app shell and design previews.
ThemeData buildStudioTheme() {
  return ThemeData(
        colorScheme: kDashboardScheme,
        scaffoldBackgroundColor: const Color(0xFF070A14),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0A0F22),
          elevation: 0,
          titleTextStyle: TextStyle(
              fontSize: 19, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        // CardThemeData (was CardTheme): Flutter 3.32+ split the
        // theme widget from its data class; ThemeData.cardTheme
        // takes the data class on the 3.35 toolchain.
        cardTheme: CardThemeData(
          color: const Color(0xFF131B36),
          elevation: 0,
          shadowColor: Colors.black54,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFF2A3560)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF0B1126),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF2A3560)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF2A3560)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide:
                const BorderSide(color: Color(0xFF8B7CFF), width: 1.6),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            textStyle:
                const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Color(0xFF414C7E)),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: const Color(0xFF151D3D),
          selectedColor: const Color(0xFF37298F),
          side: const BorderSide(color: Color(0xFF2A3560)),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999)),
          labelStyle:
              const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          secondaryLabelStyle: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: Colors.white),
        ),
        expansionTileTheme: const ExpansionTileThemeData(
          shape: Border(),
          collapsedShape: Border(),
          iconColor: Color(0xFF8B7CFF),
          textColor: Colors.white,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.transparent,
          elevation: 0,
          indicatorColor: const Color(0xFF37298F),
          labelTextStyle: WidgetStateProperty.all(
              const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        ),
        navigationRailTheme: const NavigationRailThemeData(
          backgroundColor: Color(0xFF0A0F22),
          indicatorColor: Color(0xFF37298F),
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
      );
}

class GeminiHdStudioApp extends StatelessWidget {
  const GeminiHdStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zedge Studio',
      debugShowCheckedModeBanner: false,
      theme: buildStudioTheme(),
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
  /// Prompt destination — image-to-prompt lives inside Image Search.)
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
    // "Renew cookies from the app" setting (Gemini Login screen):
    // OFF means the app never refreshes sessions in the background.
    if (!await SessionStore.loadAutoRenew()) return;
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

  /// Image Search screen (sources open in the external browser;
  /// image links come back through its collection panel). The
  /// returned pick is applied by action: reference -> anchor image,
  /// prompt -> the prompt generated inside the search screen fills
  /// the designer field, save -> a copy under app documents
  /// /GeminiHDStudio/Search/.
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
    // Keep the whole run (single or batch) alive in the
    // background — screen off / other apps must not kill it (v33).
    await ForegroundKeepAlive.acquire(
        'Generating in the background — safe to switch apps');
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
      await ForegroundKeepAlive.release();
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
      backgroundColor: const Color(0xFF070A14),
      body: Stack(
        children: [
          const AuroraBackdrop(),
          SafeArea(
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
        ],
      ),
      // Floating pill navigation (v34 redesign).
      bottomNavigationBar: wide
          ? null
          : Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1330).withValues(alpha: 0.97),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: const Color(0xFF2A3560)),
                  boxShadow: const [
                    BoxShadow(
                        color: Colors.black54,
                        blurRadius: 18,
                        offset: Offset(0, 6)),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(26),
                  child: NavigationBar(
                    height: 62,
                    selectedIndex: _tab,
                    onDestinationSelected: _onNavSelected,
                    destinations: _destinations,
                  ),
                ),
              ),
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
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      decoration: BoxDecoration(
        gradient: kHeaderGradient,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white12),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 18, offset: Offset(0, 6)),
        ],
      ),
      padding: EdgeInsets.fromLTRB(12, wide ? 16 : 14, 4, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white24),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: Image.asset(
                    'assets/logo.png',
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Zedge Studio',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Wallpaper Set Designer - AI Metadata - Panel Uploader',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                TextStyle(fontSize: 11, color: Colors.white70),
                          ),
                        ),
                        SizedBox(width: 4),
                        // Visible build tag: every user screenshot now
                        // identifies WHICH build is on the phone (the
                        // v20/v22 mix-up of 2026-11-09 was invisible
                        // because all builds looked identical).
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius:
                                BorderRadius.all(Radius.circular(6)),
                          ),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: 4, vertical: 2),
                            child: Text('BUILD v42',
                                style: TextStyle(
                                    fontSize: 7.5,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Import local set',
                constraints:
                    const BoxConstraints(maxWidth: 38, maxHeight: 38),
                padding: EdgeInsets.zero,
                iconSize: 21,
                color: Colors.white,
                onPressed: _busy ? null : _importSet,
                icon: const Icon(Icons.folder_open_outlined),
              ),
              IconButton(
                tooltip: 'Panel upload settings',
                constraints:
                    const BoxConstraints(maxWidth: 38, maxHeight: 38),
                padding: EdgeInsets.zero,
                iconSize: 21,
                color: Colors.white,
                onPressed: () async {
                  await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => PanelSettingsScreen(engine: _engine)));
                },
                icon: const Icon(Icons.cloud_upload_outlined),
              ),
              IconButton(
                tooltip: 'Gemini Login',
                constraints:
                    const BoxConstraints(maxWidth: 38, maxHeight: 38),
                padding: EdgeInsets.zero,
                iconSize: 21,
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
      backgroundColor: Colors.white.withValues(alpha: 0.13),
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
            backgroundColor: Colors.white.withValues(alpha: 0.13),
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
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2A52),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: const Color(0xFF2A3560)),
                ),
                child: const Icon(Icons.tune,
                    size: 19, color: Color(0xFFC0B4FF)),
              ),
              const SizedBox(width: 10),
              const Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Set Designer',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 16.5, fontWeight: FontWeight.w800)),
                    Text('Modes · prompt · tuning',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                flex: 2,
                child: Text(
                  'JPG · ≤8MB · ${(_portraitW * _portraitH / 1000000).toStringAsFixed(2)} MP',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Mode picker (v37 design, v38 labels): roomy squircle
          // chips with a violet icon each, in the style of the
          // user's reference image — but with OUR OWN mode names
          // and order restored (v38, his correction: "amader
          // kintu ei koyekta cilo"). The picked chip fills in and
          // its icon swaps to a check.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _modeChip(
                  'dual_single', '9:16 + Foldable', Icons.devices_outlined),
              _modeChip('single', 'Single 9:16', Icons.image_outlined),
              _modeChip(
                  'set_dual', 'Dual Set (2)', Icons.view_column_outlined),
              _modeChip(
                  'set_24h', '24-Hour Set (4)', Icons.schedule_outlined),
              _modeChip('set_battery', 'Battery Set (6)',
                  Icons.battery_charging_full),
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
          const SizedBox(height: 10),
          _tuningRow(isSetMode),
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

  Widget _modeChip(String value, String label, IconData icon) {
    final selected = _mode == value;
    return ChoiceChip(
      avatar: Icon(icon, size: 18, color: const Color(0xFFB9AFFF)),
      label: Text(label, style: const TextStyle(fontSize: 13.5)),
      labelPadding: const EdgeInsets.only(left: 2, right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14)),
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

  /// Variation / Display / Colour in ONE compact line above the
  /// Generate button (user order 2026-11-11 — they used to sit
  /// inside Advanced settings). Same state fields and options as
  /// before; only the placement and density changed.
  Widget _tuningRow(bool isSetMode) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isSetMode) ...[
          Expanded(
            child: _miniDropdown(
                'Variation',
                _variation,
                const {
                  'subtle': 'Subtle',
                  'clear': 'Clear',
                  'strong': 'Strong',
                },
                (v) => setState(() => _variation = v)),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: _miniDropdown(
              'Display',
              _displayTarget,
              const {
                'any': 'Any',
                'amoled': 'AMOLED',
                'ips': 'IPS',
              },
              (v) => setState(() => _displayTarget = v)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _miniDropdown(
              'Colour',
              _colorBoost,
              const {
                'off': 'Off',
                'subtle': 'Subtle',
                'vivid': 'Vivid',
                'neon': 'Neon',
              },
              (v) => setState(() => _colorBoost = v)),
        ),
      ],
    );
  }

  /// Compact dropdown with the label inside the field, for the
  /// one-line tuning row.
  Widget _miniDropdown(String label, String value,
      Map<String, String> options, ValueChanged<String> onChanged) {
    return DropdownButtonFormField<String>(
      isExpanded: true,
      value: value,
      isDense: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
      items: options.entries
          .map((e) => DropdownMenuItem(
              value: e.key,
              child: Text(e.value, overflow: TextOverflow.ellipsis)))
          .toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
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
  final void Function(String) snack;
  const SetCard({
    super.key,
    required this.entry,
    required this.engine,
    required this.onChanged,
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

  Future<void> _regenerateAll() async {
    await _run(() async {
      for (final img in widget.entry.images) {
        await widget.engine.regenerateStage(widget.entry, img);
      }
    }, 'Regenerate failed');
  }

  Future<void> _uploadToPanel() async {
    // v42: the card no longer carries a permanent Panel target row;
    // the target is picked here, on the cloud tap, and remembered.
    var target = _uploadTarget;
    final cfg = await widget.engine.loadDistConfig();
    if (!mounted) return;
    if (cfg.accounts.isNotEmpty) {
      final picked = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Upload to Panel'),
          children: [
            for (final t in [
              'spread',
              ...cfg.accounts.map((a) => a.name),
            ])
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, t),
                child: Row(
                  children: [
                    Icon(
                      t == target
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 18,
                      color: const Color(0xFF8B7CFF),
                    ),
                    const SizedBox(width: 10),
                    Text(t == 'spread' ? 'Spread (Auto-Rotate)' : t),
                  ],
                ),
              ),
          ],
        ),
      );
      if (picked == null) return;
      target = picked;
      if (mounted) setState(() => _uploadTarget = target);
    }
    await _run(() async {
      final r = await widget.engine
          .uploadSetToPanel(widget.entry, targetAccount: target);
      widget.snack('Uploaded to ${r.accountName} (key ${r.firebaseKey})');
    }, 'Panel upload failed');
  }

  Future<void> _confirmDelete() async {
    final entry = widget.entry;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this set?'),
        content: Text(
            'The set is removed from the Showcase and its ${entry.images.length} image files are deleted from this device. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      final history = await widget.engine.loadHistory();
      history.removeWhere((h) => h.id == entry.id);
      await widget.engine.saveHistory(history);
      for (final img in entry.images) {
        final f = File(img.localPath);
        if (await f.exists()) {
          try {
            await f.delete();
          } catch (_) {}
        }
      }
    }, 'Delete failed');
  }

  /// Inner metadata card in the reference showcase design: title +
  /// category pill + AI sparkle, the model line, the description and
  /// the hashtag chips.
  Widget _metaCard(SetEntry entry, SetMetadata? meta) {
    if (meta == null ||
        (meta.title.isEmpty && meta.description.isEmpty && meta.tags.isEmpty)) {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF191924),
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Expanded(
              child: Text('No metadata yet',
                  style: TextStyle(color: Colors.grey, fontSize: 13.5)),
            ),
            FilledButton.tonalIcon(
              onPressed: _working
                  ? null
                  : () => _run(() async {
                        await widget.engine.generateMetadataForEntry(entry);
                      }, 'Metadata failed'),
              icon: const Icon(Icons.auto_awesome, size: 15),
              label: const Text('AI Metadata'),
            ),
          ],
        ),
      );
    }
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF191924),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(meta.title,
                    style: const TextStyle(
                        fontSize: 19, fontWeight: FontWeight.w700)),
              ),
              if (meta.category.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF5B3BE0),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(meta.category.toUpperCase(),
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: Colors.white)),
                ),
              ],
              IconButton(
                tooltip: 'Rewrite with AI',
                visualDensity: VisualDensity.compact,
                onPressed: _working
                    ? null
                    : () => _run(() async {
                          await widget.engine.generateMetadataForEntry(entry);
                        }, 'Metadata failed'),
                icon: const Icon(Icons.auto_awesome,
                    size: 20, color: Colors.white70),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text('gemini-web (cookie)',
              style: TextStyle(fontSize: 13.5, color: Colors.grey)),
          if (meta.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(meta.description,
                style: const TextStyle(
                    fontSize: 15, height: 1.35, color: Color(0xFFD8D8DE))),
          ],
          if (meta.tags.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in meta.tags)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF12121B),
                      border: Border.all(color: Colors.white12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('#$tag',
                        style: const TextStyle(
                            fontSize: 13, color: Color(0xFFC9C9D2))),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Reference-design image grid: equal columns of stage thumbnails
  /// with circular overlay actions (preview / regenerate / view) and
  /// the stage label underneath.
  Widget _imageGrid(SetEntry entry) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final count = entry.images.length.clamp(1, 4);
        final cellW = (constraints.maxWidth - (count - 1) * 10) / count;
        final imgH = cellW / 0.71;
        final btn = cellW < 80 ? 27.0 : 34.0;
        final iconSize = cellW < 80 ? 14.0 : 17.0;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: entry.images.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: count,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: cellW / (imgH + 28),
          ),
          itemBuilder: (ctx, i) {
            final img = entry.images[i];
            final file = File(img.localPath);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => _openLightbox(img),
                  child: SizedBox(
                    height: imgH,
                    width: cellW,
                    child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: file.existsSync()
                            ? Image.file(file, fit: BoxFit.cover)
                            : Container(
                                color: Colors.black26,
                                child:
                                    const Icon(Icons.broken_image_outlined),
                              ),
                      ),
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Row(
                          children: [
                            _overlayButton(
                              Icons.smartphone_outlined,
                              btn,
                              iconSize,
                              () => _openSimulator(entry, initialIndex: i),
                            ),
                            const SizedBox(width: 5),
                            _overlayButton(
                              Icons.refresh,
                              btn,
                              iconSize,
                              _working
                                  ? null
                                  : () => _run(() async {
                                        await widget.engine
                                            .regenerateStage(entry, img);
                                      }, 'Regenerate failed'),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        bottom: 6,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: _overlayButton(
                            Icons.fact_check_outlined,
                            btn,
                            iconSize,
                            () => _openOriginality(entry, img),
                          ),
                        ),
                      ),
                    ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (img.hdUrl != null) ...[
                      const Icon(Icons.link, size: 13, color: Colors.grey),
                      const SizedBox(width: 3),
                    ],
                    Expanded(
                      child: Text(img.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13)),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _overlayButton(
      IconData icon, double size, double iconSize, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: Color(0x8C000000),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: iconSize, color: Colors.white),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final meta = entry.metadata;
    return Card(
      color: const Color(0xFF101830),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFF2A3560)),
      ),
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header (reference showcase design): the prompt as the
            // title, then regenerate / upload / delete icon actions
            // and the finished-stage count (e.g. 4/4).
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      entry.prompt.isEmpty ? entry.setTypeLabel : entry.prompt,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w700,
                          height: 1.25),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Regenerate whole set',
                  visualDensity: VisualDensity.compact,
                  onPressed: _working ? null : _regenerateAll,
                  icon: const Icon(Icons.refresh,
                      size: 21, color: Color(0xFF9A9AA5)),
                ),
                IconButton(
                  tooltip: 'Upload to Panel',
                  visualDensity: VisualDensity.compact,
                  onPressed: _working ? null : _uploadToPanel,
                  icon: const Icon(Icons.cloud_upload_outlined,
                      size: 21, color: Color(0xFF9A9AA5)),
                ),
                IconButton(
                  tooltip: 'Delete set',
                  visualDensity: VisualDensity.compact,
                  onPressed: _working ? null : _confirmDelete,
                  icon: const Icon(Icons.delete_outline,
                      size: 21, color: Color(0xFFE5534B)),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 9),
                  child: Text(
                      '${entry.images.length}/${entry.images.length}',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            if (entry.uploadedToPanel != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Chip(
                  avatar: const Icon(Icons.check_circle_outline, size: 14),
                  label: Text(
                      'Queued on ${entry.uploadedToPanel!['accountName']}',
                      style: const TextStyle(fontSize: 11)),
                ),
              ),
            const SizedBox(height: 12),
            _metaCard(entry, meta),
            const SizedBox(height: 14),
            _imageGrid(entry),
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

  Future<void> _openOriginality(SetEntry entry, SetImage img) async {
    final prefs = await SharedPreferences.getInstance();
    final target = prefs.getInt('i2pSimilarity') ?? 20;
    final ref = ReferenceStore.lookup(entry.prompt);
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => OriginalityCheckScreen(
        generatedFile: File(img.localPath),
        generatedLabel: img.label,
        referenceBytes: ref?.bytes,
        referenceLabel: ref?.label,
        targetSimilarity: target,
        onLessSimilar: (bytes, reduced) async {
          final options = PromptOptions()..similarity = reduced;
          return generatePromptChecked(
            bytes: bytes,
            name: 'reference.jpg',
            mime: 'image/jpeg',
            options: options,
          );
        },
      ),
    ));
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
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _openOriginality(widget.entry, img);
                    },
                    icon: const Icon(Icons.fact_check_outlined, size: 15),
                    label: const Text('Originality check'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openSimulator(SetEntry entry, {int initialIndex = 0}) {
    var index = initialIndex;
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

}
