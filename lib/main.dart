import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'screens/home_screen.dart';
import 'secure_store.dart';
import 'gemini_web.dart';
import 'dola_api.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final p = await AppPrefs.prefs();
    GeminiWebClient.allowAppRotation =
        p.getBool('gemini_app_rotation') ?? false;
  } catch (_) {}
  try {
    await DolaPool.instance.loadFromStore();
  } catch (_) {}
  runApp(const AiImageStudioMhApp());
}

class AiImageStudioMhApp extends StatefulWidget {
  const AiImageStudioMhApp({super.key});

  @override
  State<AiImageStudioMhApp> createState() => _AiImageStudioMhAppState();
}

class _AiImageStudioMhAppState extends State<AiImageStudioMhApp> {
  ThemeMode _mode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    String saved;
    try {
      saved = await AppPrefs.themeMode();
    } catch (_) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _mode = switch (saved) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    });
  }

  Future<void> _setMode(ThemeMode mode) async {
    setState(() => _mode = mode);
    try {
      await AppPrefs.setThemeMode(switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Image Studio MH',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: _mode,
      home: HomeScreen(mode: _mode, onThemeChanged: _setMode),
    );
  }
}
