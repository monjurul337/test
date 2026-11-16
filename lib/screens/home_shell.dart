import '../main.dart';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/studio_models.dart';
import '../services/mh_motion_api.dart';
import '../theme/app_theme.dart';
import 'browser_workspace_screen.dart';
import 'fingerprint_screen.dart';
import 'gemini_settings_screen.dart';
import 'earn_adobe_screen.dart';
import 'home_dashboard_screen.dart';
import 'studio_screen.dart';
import 'upload_panel_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final _studioKey = GlobalKey<StudioScreenState>();
  final _api = MhMotionApi();

  int _navIndex = 1;
  bool _isFullScreen = false;
  int _profilesVersion = 0;
  FingerprintProfile _fp = FingerprintProfile.defaultAndroid(42);
  ServerInfo? _serverInfo;
  String _detectedTunnel = '';

  File? _queuedVideo;
  String _queuedScene = '';
  String _queuedShader = '';
  List<(File, String)> _queuedBatch = [];

  static const _bgChannel = MethodChannel('com.mynxsoft.mhmotion/background');

  @override
  void initState() {
    super.initState();
    _initBackgroundService();
  }

  Future<void> _initBackgroundService() async {
    try {
      await _bgChannel.invokeMethod('startKeepAlive');
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    var seed = prefs.getInt('mh_fp_seed');
    if (seed == null) {
      seed = Random.secure().nextInt(899999) + 100000;
      await prefs.setInt('mh_fp_seed', seed);
    }
    if (mounted) {
      setState(() => _fp = FingerprintProfile.defaultAndroid(seed!));
    }
  }

  void _setFullScreen(bool full) {
    setState(() => _isFullScreen = full);
    SystemChrome.setEnabledSystemUIMode(
      full ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  void _openAntiDetectProfiles() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Anti-Detect Profiles & Proxy', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
          body: FingerprintScreen(
            profile: _fp,
            onRandomize: _randomizeFp,
            onOsChanged: (osName) => setState(() => _fp = FingerprintProfile.defaultAndroid(_fp.seed, osType: osName)),
            onProfileSeedChanged: (seed) => setState(() => _fp = FingerprintProfile.defaultAndroid(seed, osType: _fp.osType)),
            onProfileApplied: (fp) => setState(() => _fp = fp),
            onProfilesUpdated: () => setState(() => _profilesVersion++),
          ),
        ),
      ),
    );
  }

  void _openGeminiSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Gemini & Metadata Settings', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
          body: GeminiSettingsScreen(fingerprint: _fp),
        ),
      ),
    );
  }

  Future<void> _randomizeFp() async {
    final seed = Random.secure().nextInt(899999) + 100000;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('mh_fp_seed', seed);
    if (mounted) {
      setState(() => _fp = FingerprintProfile.defaultAndroid(seed));
    }
  }

  @override
  Widget build(BuildContext context) {
    const titles = [
      'Dashboard',
      'Adobe Stock Video Studio',
      'Upload Panel (Adobe Stock)',
      'All Earnings',
      'Accounts & Browser',
    ];

    final hideChrome = _isFullScreen && (_navIndex == 1 || _navIndex == 4);

    return Scaffold(
      appBar: hideChrome
          ? null
          : AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(10),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: Text(
                'AS',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Colors.white),
              ),
            ),
          ),
        ),
        title: Text(
          titles[_navIndex],
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        actions: [
          if (_navIndex == 1 || _navIndex == 4)
            IconButton(
              tooltip: 'Full Screen Browser',
              icon: const Icon(Icons.fullscreen_rounded, size: 22),
              onPressed: () => _setFullScreen(true),
            ),
          IconButton(
            tooltip: 'Anti-Detect Profiles & Proxy',
            icon: const Icon(Icons.verified_user_rounded, size: 20),
            onPressed: _openAntiDetectProfiles,
          ),
          IconButton(
            tooltip: 'Gemini & Metadata Settings',
            icon: const Icon(Icons.settings_rounded, size: 20),
            onPressed: _openGeminiSettings,
          ),
          IconButton(
            tooltip: 'Toggle Dark / Light Theme',
            icon: Icon(
              themeModeNotifier.value == ThemeMode.dark
                  ? Icons.light_mode_rounded
                  : Icons.dark_mode_rounded,
              size: 20,
            ),
            onPressed: () async {
              final nextDark = themeModeNotifier.value != ThemeMode.dark;
              themeModeNotifier.value = nextDark ? ThemeMode.dark : ThemeMode.light;
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('mh_dark_mode', nextDark);
              if (mounted) setState(() {});
            },
          ),
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _serverInfo != null ? AppColors.activePillOf(context) : AppColors.iconBoxOf(context),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _serverInfo != null ? AppColors.primary : AppColors.borderOf(context),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.circle,
                  size: 8,
                  color: _serverInfo != null ? AppColors.success : AppColors.mutedOf(context),
                ),
                const SizedBox(width: 6),
                Text(
                  _serverInfo != null ? 'T4 ON' : 'OFFLINE',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _navIndex,
        children: [
          HomeDashboardScreen(
            serverInfo: _serverInfo,
            fingerprint: _fp,
            detectedTunnel: _detectedTunnel,
            onNavigateTab: (idx) => setState(() => _navIndex = idx),
            onSwitchProfile: (seed, osType) => setState(() => _fp = FingerprintProfile.defaultAndroid(seed, osType: osType)),
          ),
          StudioScreen(
            key: _studioKey,
            api: _api,
            fingerprint: _fp,
            initialTunnelUrl: _detectedTunnel,
            isFullScreen: _isFullScreen,
            onFullScreenChanged: _setFullScreen,
            onConnected: (info) => setState(() => _serverInfo = info),
            onSendBatchToUploadPanel: (batch) {
              setState(() {
                _queuedBatch = batch;
                if (batch.isNotEmpty) {
                  _queuedVideo = batch.first.$1;
                  _queuedScene = batch.first.$2;
                }
                _navIndex = 2;
              });
            },
            onSendToUploadPanel: (file, scene, code) {
              setState(() {
                _queuedVideo = file;
                _queuedScene = scene;
                _queuedShader = code;
                _navIndex = 2;
              });
            },
          ),
          UploadPanelScreen(
            fingerprint: _fp,
            queuedVideo: _queuedVideo,
            queuedSceneName: _queuedScene,
            queuedShaderCode: _queuedShader,
            queuedBatch: _queuedBatch,
          ),
          EarnAdobeScreen(fingerprint: _fp),
          BrowserWorkspaceScreen(
            fingerprint: _fp,
            profilesVersion: _profilesVersion,
            onOpenProfiles: _openAntiDetectProfiles,
            isFullScreen: _isFullScreen,
            onFullScreenChanged: _setFullScreen,
            onRandomizeFingerprint: _randomizeFp,
            onOsChanged: (osName) => setState(() => _fp = FingerprintProfile.defaultAndroid(_fp.seed, osType: osName)),
            onProfileSeedChanged: (seed) => setState(() => _fp = FingerprintProfile.defaultAndroid(seed, osType: _fp.osType)),
            onProfileApplied: (fp) => setState(() => _fp = fp),
            onColabTunnelDetected: (url) {
              final isNew = _detectedTunnel != url;
              if (isNew) {
                HapticFeedback.heavyImpact();
                _bgChannel.invokeMethod('notifyColabLive', {'url': url}).catchError((_) {});
              }
              setState(() {
                _detectedTunnel = url;
                _navIndex = 1;
              });
              if (isNew && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Colab T4 Live: $url')),
                );
              }
            },
          ),
        ],
      ),
      bottomNavigationBar: hideChrome
          ? null
          : NavigationBar(
        backgroundColor: Theme.of(context).navigationBarTheme.backgroundColor,
        indicatorColor: AppColors.activePillOf(context),
        selectedIndex: _navIndex,
        onDestinationSelected: (i) => setState(() => _navIndex = i),
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.dashboard_rounded),
            selectedIcon: Icon(Icons.dashboard_rounded, color: AppColors.accentTextOf(context)),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.movie_creation_outlined),
            selectedIcon: Icon(Icons.movie_creation, color: AppColors.accentTextOf(context)),
            label: 'Studio',
          ),
          NavigationDestination(
            icon: Icon(Icons.cloud_upload_outlined),
            selectedIcon: Icon(Icons.cloud_upload, color: AppColors.accentTextOf(context)),
            label: 'Upload',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_rounded),
            selectedIcon: Icon(Icons.bar_chart_rounded, color: AppColors.accentTextOf(context)),
            label: 'All Earnings',
          ),
          NavigationDestination(
            icon: Icon(Icons.switch_account_rounded),
            selectedIcon: Icon(Icons.switch_account_rounded, color: AppColors.accentTextOf(context)),
            label: 'Accounts',
          ),
        ],
      ),
    );
  }
}
