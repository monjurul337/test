import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import '../models/studio_models.dart';
import '../services/mh_motion_api.dart';
import '../theme/app_theme.dart';
import 'browser_workspace_screen.dart';
import 'fingerprint_screen.dart';
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

  int _navIndex = 0;
  FingerprintProfile _fp = FingerprintProfile.defaultAndroid(42);
  ServerInfo? _serverInfo;
  String _detectedTunnel = '';

  File? _queuedVideo;
  List<(File, String)> _queuedBatch = [];
  String _queuedScene = '';
  String _queuedShader = '';

  void _randomizeFp() {
    setState(() {
      _fp = FingerprintProfile.defaultAndroid(Random().nextInt(99999) + 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    const titles = [
      'MH Motion Studio',
      'Upload Panel (Adobe Stock)',
      'Anti-Detect Browser',
      'Fingerprint & Sessions',
    ];

    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(10),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: Text(
                'MH',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Colors.white),
              ),
            ),
          ),
        ),
        title: Text(
          titles[_navIndex],
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _serverInfo != null ? AppColors.activePill : AppColors.iconBoxBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _serverInfo != null ? AppColors.primary : AppColors.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.circle,
                  size: 8,
                  color: _serverInfo != null ? AppColors.success : AppColors.textMuted,
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
          StudioScreen(
            key: _studioKey,
            api: _api,
            fingerprint: _fp,
            initialTunnelUrl: _detectedTunnel,
            onConnected: (info) => setState(() => _serverInfo = info),
            onSendBatchToUploadPanel: (batch) {
              setState(() {
                _queuedBatch = batch;
                if (batch.isNotEmpty) {
                  _queuedVideo = batch.first.$1;
                  _queuedScene = batch.first.$2;
                }
                _navIndex = 1;
              });
            },
            onSendToUploadPanel: (file, scene, code) {
              setState(() {
                _queuedVideo = file;
                _queuedScene = scene;
                _queuedShader = code;
                _navIndex = 1; // Switch directly to Upload Panel tab
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
          BrowserWorkspaceScreen(
            fingerprint: _fp,
            onColabTunnelDetected: (url) {
              if (_detectedTunnel != url) {
                setState(() => _detectedTunnel = url);
              }
            },
          ),
          FingerprintScreen(
            profile: _fp,
            onRandomize: _randomizeFp,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: AppColors.drawerBg,
        indicatorColor: AppColors.activePill,
        selectedIndex: _navIndex,
        onDestinationSelected: (i) => setState(() => _navIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.movie_creation_outlined),
            selectedIcon: Icon(Icons.movie_creation, color: AppColors.primaryLight),
            label: 'Studio',
          ),
          NavigationDestination(
            icon: Icon(Icons.cloud_upload_outlined),
            selectedIcon: Icon(Icons.cloud_upload, color: AppColors.primaryLight),
            label: 'Upload',
          ),
          NavigationDestination(
            icon: Icon(Icons.public_outlined),
            selectedIcon: Icon(Icons.public, color: AppColors.primaryLight),
            label: 'Browser',
          ),
          NavigationDestination(
            icon: Icon(Icons.fingerprint_outlined),
            selectedIcon: Icon(Icons.fingerprint, color: AppColors.primaryLight),
            label: 'Security',
          ),
        ],
      ),
    );
  }
}
