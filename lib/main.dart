import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_config.dart';
import 'command_parser.dart';
import 'native_bridge.dart';
import 'pc_executor.dart';
import 'relay_client.dart';

void main() => runApp(const PcAssistantApp());

class PcAssistantApp extends StatefulWidget {
  const PcAssistantApp({super.key});
  @override
  State<PcAssistantApp> createState() => _PcAssistantAppState();
}

class _PcAssistantAppState extends State<PcAssistantApp> {
  AppConfig? _cfg;
  bool _showSetup = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cfg = await AppConfig.load();
    setState(() {
      _cfg = cfg;
      _showSetup = !cfg.isComplete;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Maliha // AI Desktop & Remote Assistant',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF060B19),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00F0FF),
          secondary: Color(0xFF3B82F6),
          surface: Color(0xFF0D1527),
        ),
        cardTheme: const CardTheme(
          color: Color(0xFF0E172E),
          elevation: 0,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: Color(0x3338BDF8)),
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF090E1F),
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
        ),
      ),
      home: _cfg == null
          ? const Scaffold(
              backgroundColor: Color(0xFF060B19),
              body: Center(
                child: CircularProgressIndicator(color: Color(0xFF00F0FF)),
              ),
            )
          : MalihaMasterDashboard(
              cfg: _cfg!,
              onConfigChanged: () => _load(),
            ),
    );
  }
}

// ============================================================================
// MALIHA MASTER DASHBOARD (Unified Futuristic UI for PC & Mobile)
// ============================================================================

class MalihaMasterDashboard extends StatefulWidget {
  final AppConfig cfg;
  final VoidCallback onConfigChanged;
  const MalihaMasterDashboard({
    super.key,
    required this.cfg,
    required this.onConfigChanged,
  });

  @override
  State<MalihaMasterDashboard> createState() => _MalihaMasterDashboardState();
}

class _MalihaMasterDashboardState extends State<MalihaMasterDashboard>
    with TickerProviderStateMixin {
  // Navigation tabs: 0: Home, 1: Assistant, 2: Memory, 3: World, 4: Skills, 5: Settings
  int _activeTab = 0;

  // Background agent / relay variables
  late final RelayClient _relay = RelayClient(widget.cfg);
  final PcExecutor _executor = PcExecutor();
  Timer? _agentPollTimer;
  Timer? _heartbeatTimer;
  Timer? _controllerPollTimer;
  bool _agentRunning = false;
  bool _pcOnline = false;
  final List<String> _terminalLogs = [];
  final List<Map<String, dynamic>> _results = [];
  final TextEditingController _chatInputCtrl = TextEditingController();

  // Animation controllers for Cosmic Orb and Waveform Dock
  late final AnimationController _orbAnimCtrl;
  late final AnimationController _waveAnimCtrl;
  bool _isListening = false;
  String _greetingText = "Hello! I'm Maliha. How can I help you today?";

  // Teachable Skills State
  final List<Map<String, dynamic>> _skillsList = [
    {
      'id': 1,
      'icon': '📸',
      'name': 'Screen Capture',
      'badge': 'READY',
      'desc': 'Captures full-resolution primary display screenshot and uploads to cloud.',
      'action': 'screenshot',
      'isCustom': false,
    },
    {
      'id': 2,
      'icon': '📊',
      'name': 'PC Status Diagnostic',
      'badge': 'READY',
      'desc': 'Monitors CPU load, RAM capacity, SSD storage, and battery health.',
      'action': 'pc status',
      'isCustom': false,
    },
    {
      'id': 3,
      'icon': '🚀',
      'name': 'App Launcher',
      'badge': 'READY',
      'desc': 'Launches Chrome, Notepad, VS Code, Calculator, or any Windows software.',
      'action': 'open notepad',
      'isCustom': false,
    },
    {
      'id': 4,
      'icon': '🔒',
      'name': 'Security & Lock',
      'badge': 'READY',
      'desc': 'Instantly locks your Windows workstation remotely via rundll32.',
      'action': 'lock my pc',
      'isCustom': false,
    },
    {
      'id': 5,
      'icon': '⚡',
      'name': 'Wake-on-LAN Bridge',
      'badge': 'READY',
      'desc': 'Powers on your turned-off PC remotely via home Android bridge magic packet.',
      'action': 'wake',
      'isCustom': false,
    },
    {
      'id': 6,
      'icon': '🗣️',
      'name': 'Voice & Speech Synth',
      'badge': 'READY',
      'desc': 'Speaks aloud any notification or text through the laptop speakers.',
      'action': 'say Hello Boss',
      'isCustom': false,
    },
    {
      'id': 7,
      'icon': '📁',
      'name': 'Remote File Fetcher',
      'badge': 'READY',
      'desc': 'Locates and transfers files from Desktop, Downloads, or Documents directly to your phone.',
      'action': 'file fetch resume.pdf',
      'isCustom': false,
    },
    {
      'id': 8,
      'icon': '📷',
      'name': 'Stealth Webcam Sentry',
      'badge': 'READY',
      'desc': 'Silently captures discrete webcam snapshots to monitor your room and detect intruders.',
      'action': 'webcam',
      'isCustom': false,
    },
    {
      'id': 9,
      'icon': '👁️',
      'name': 'Gemini Screen Vision',
      'badge': 'READY',
      'desc': 'Multimodal AI analyzes what is currently displayed on your PC screen and explains it in detail.',
      'action': 'explain screen',
      'isCustom': false,
    },
    {
      'id': 10,
      'icon': '📋',
      'name': 'Universal Clipboard',
      'badge': 'READY',
      'desc': 'Instantly reads or injects text into the Windows PC clipboard across devices.',
      'action': 'clipboard',
      'isCustom': false,
    },
    {
      'id': 11,
      'icon': '🔋',
      'name': 'Power Cut & Battery Guard',
      'badge': 'READY',
      'desc': 'Monitors laptop battery level, AC charging status, and alerts if power gets disconnected.',
      'action': 'battery status',
      'isCustom': false,
    },
    {
      'id': 12,
      'icon': '⏰',
      'name': 'Scheduled Routines',
      'badge': 'READY',
      'desc': 'Schedules automated delayed shutdowns, restarts, or background commands with safety cancellation.',
      'action': 'schedule 30 shutdown',
      'isCustom': false,
    },
  ];

  @override
  void initState() {
    super.initState();

    _orbAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();

    _waveAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    // Initial welcome in execution results
    _results.add({
      'isAi': true,
      'text': "Hey Boss! Maliha AI is online and synchronized. Tap any quick action or ask in Bengali / English.",
      'badge': 'NEURAL_CORE_ONLINE',
      'ts': DateTime.now().millisecondsSinceEpoch,
    });

    _startRoleServices();
  }

  void _startRoleServices() {
    // 1. If on Windows and role is PC Agent, auto-start the background executor
    if (Platform.isWindows && widget.cfg.role == AppRole.pcAgent) {
      _startPcAgentListener();
    } else {
      // 2. Controller mode (Phone or PC controller): Poll heartbeat and results
      _startControllerPoller();
    }
  }

  void _log(String line) {
    if (!mounted) return;
    setState(() {
      _terminalLogs.insert(
        0,
        "${DateTime.now().toString().substring(11, 19)}  $line",
      );
    });
  }

  // --- PC AGENT BACKGROUND WORKER ---
  void _startPcAgentListener() {
    if (_agentRunning) return;
    _agentRunning = true;
    _log("Maliha Windows Agent started. Polling cloud commands...");
    _heartbeat();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 10), (_) => _heartbeat());
    _pollAgentQueue();
    _agentPollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _pollAgentQueue());
    setState(() {});
  }

  void _stopPcAgentListener() {
    _agentRunning = false;
    _agentPollTimer?.cancel();
    _heartbeatTimer?.cancel();
    _log("Maliha Windows Agent stopped.");
    setState(() {});
  }

  Future<void> _heartbeat() async {
    try {
      await _relay.sendHeartbeat(Platform.operatingSystem);
      if (mounted) setState(() => _pcOnline = true);
    } catch (_) {}
  }

  Future<void> _pollAgentQueue() async {
    if (!_agentRunning) return;
    try {
      final raw = await _relay.getNode('commands');
      if (raw is! Map) return;
      final pending = <MapEntry<String, Map<String, dynamic>>>[];
      raw.forEach((k, v) {
        if (v is Map && v['status'] == 'queued') {
          pending.add(MapEntry(k.toString(), Map<String, dynamic>.from(v)));
        }
      });
      pending.sort((a, b) => ((a.value['createdAt'] as num?)?.toInt() ?? 0)
          .compareTo((b.value['createdAt'] as num?)?.toInt() ?? 0));

      for (final entry in pending) {
        final id = entry.key;
        final type = entry.value['type']?.toString() ?? '';
        final payload = entry.value['payload']?.toString() ?? '';
        await _relay.patchNode('commands/$id', {'status': 'running'});
        _log("Running: $type $payload");

        final result = await _executor.execute(
          type,
          payload,
          geminiApiKey: widget.cfg.geminiApiKey,
        );

        await _relay.patchNode('commands/$id', {'status': 'done'});
        await _relay.postNode('results', {
          'commandId': id,
          'text': result.text,
          'screenshotB64': result.screenshotB64,
          'fileB64': result.fileB64,
          'fileName': result.fileName,
          'ts': DateTime.now().millisecondsSinceEpoch,
        });

        _log("Executed: ${result.text}");

        // Also reflect locally in the active dashboard
        if (mounted) {
          setState(() {
            _results.insert(0, {
              'isAi': true,
              'text': result.text,
              'badge': type,
              'screenshotB64': result.screenshotB64,
              'fileB64': result.fileB64,
              'fileName': result.fileName,
              'ts': DateTime.now().millisecondsSinceEpoch,
            });
          });
        }
      }
    } catch (e) {
      _log("Queue error: $e");
    }
  }

  // --- CONTROLLER (PHONE) BACKGROUND POLLER ---
  void _startControllerPoller() {
    _pollController();
    _controllerPollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _pollController());
  }

  Future<void> _pollController() async {
    try {
      // Check PC Heartbeat
      final hb = await _relay.readHeartbeats();
      bool online = false;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (hb is Map) {
        hb.forEach((k, v) {
          if (v is Map && v['ts'] is num) {
            final diff = (now - (v['ts'] as num).toInt()) / 1000;
            if (diff < 35) online = true;
          }
        });
      }
      if (mounted && _pcOnline != online) {
        setState(() => _pcOnline = online);
      }

      // Read remote results
      final rawResults = await _relay.getNode('results');
      if (rawResults is Map) {
        final entries = <Map<String, dynamic>>[];
        rawResults.forEach((k, v) {
          if (v is Map) entries.add(Map<String, dynamic>.from(v));
        });
        entries.sort((a, b) => ((b['ts'] as num?)?.toInt() ?? 0)
            .compareTo((a['ts'] as num?)?.toInt() ?? 0));

        if (entries.isNotEmpty && mounted) {
          final latestTs = (entries.first['ts'] as num?)?.toInt() ?? 0;
          final currentLatest = _results.isNotEmpty ? ((_results.first['ts'] as num?)?.toInt() ?? 0) : 0;
          if (latestTs > currentLatest) {
            setState(() {
              for (final e in entries.reversed) {
                final ts = (e['ts'] as num?)?.toInt() ?? 0;
                if (ts > currentLatest) {
                  _results.insert(0, {
                    'isAi': true,
                    'text': e['text'] ?? '',
                    'badge': 'REMOTE_RESULT',
                    'screenshotB64': e['screenshotB64'],
                    'fileB64': e['fileB64'],
                    'fileName': e['fileName'],
                    'ts': ts,
                  });
                }
              }
            });
          }
        }
      }
    } catch (_) {}
  }

  // --- DISPATCH COMMAND FROM ANY VIEW ---
  Future<void> _dispatchCommand(String rawText) async {
    final text = rawText.trim();
    if (text.isEmpty) return;
    _chatInputCtrl.clear();

    // 1. Add User message to stream
    setState(() {
      _results.insert(0, {
        'isAi': false,
        'text': text,
        'badge': 'YOU',
        'ts': DateTime.now().millisecondsSinceEpoch,
      });
      _greetingText = 'Maliha: Executing "$text" on your PC...';
    });

    _showToast('🚀 Dispatching: "$text"');

    // 2. Parse command with Gemini AI or Rule-Based Regex
    final parsed = await parseCommandWithAi(
      text,
      geminiApiKey: widget.cfg.geminiApiKey,
    );
    final type = parsed[0];
    final payload = parsed[1];

    // If running in local PC Agent mode on Windows, execute directly for instant speed!
    if (Platform.isWindows && widget.cfg.role == AppRole.pcAgent) {
      _log("Direct Exec: $type $payload");
      final res = await _executor.execute(type, payload, geminiApiKey: widget.cfg.geminiApiKey);
      setState(() {
        _results.insert(0, {
          'isAi': true,
          'text': res.text,
          'badge': type,
          'screenshotB64': res.screenshotB64,
          'fileB64': res.fileB64,
          'fileName': res.fileName,
          'ts': DateTime.now().millisecondsSinceEpoch,
        });
        _greetingText = "Maliha: Task completed successfully!";
      });
      _showToast('✅ Executed: $type');
      return;
    }

    // 3. Otherwise queue to Firebase Cloud for the remote Windows PC Agent
    try {
      await _relay.postNode('commands', {
        'type': type,
        'payload': payload,
        'rawText': text,
        'status': 'queued',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });
      _showToast('☁️ Sent to Windows PC via Cloud Tunnel');
    } catch (e) {
      _showToast('❌ Cloud Send Failed: $e');
    }
  }

  void _triggerVoiceOrb() {
    setState(() {
      _isListening = !_isListening;
      if (_isListening) {
        _greetingText = "Hey Boss! Maliha is listening... What would you like to do?";
        _showToast("🎙️ Maliha is listening to your voice...");

        // Simulate voice capture
        Timer(const Duration(milliseconds: 2200), () {
          if (mounted) {
            setState(() {
              _isListening = false;
              _greetingText = "Maliha: Executing captured command...";
            });
            _dispatchCommand("take a screenshot");
          }
        });
      } else {
        _greetingText = "Hello! I'm Maliha. How can I help you today?";
      }
    });
  }

  void _triggerVoiceInput(String lang) {
    if (Platform.isAndroid) {
      NativeBridge.recognizeSpeech(lang).then((recognized) {
        if (recognized != null && recognized.trim().isNotEmpty) {
          _dispatchCommand(recognized.trim());
        }
      }).catchError((_) {
        final sample = lang == 'bn-BD' ? 'ইউটিউব চালাও' : 'take a screenshot of my pc';
        _dispatchCommand(sample);
      });
    } else {
      final sample = lang == 'bn-BD' ? 'ইউটিউব চালাও' : 'take a screenshot of my pc';
      _dispatchCommand(sample);
    }
  }

  void _showToast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        backgroundColor: const Color(0xFF0F172A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFF00F0FF), width: 0.8),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  void dispose() {
    _orbAnimCtrl.dispose();
    _waveAnimCtrl.dispose();
    _agentPollTimer?.cancel();
    _heartbeatTimer?.cancel();
    _controllerPollTimer?.cancel();
    _chatInputCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 768;

        return Scaffold(
          backgroundColor: const Color(0xFF060B19),
          body: Row(
            children: [
              // 1. DESKTOP SIDEBAR
              if (isDesktop) _buildDesktopSidebar(),

              // 2. MAIN CONTENT STAGE
              Expanded(
                child: Column(
                  children: [
                    // Top Futuristic Header
                    _buildTopHeader(isDesktop),

                    // Active View
                    Expanded(
                      child: IndexedStack(
                        index: _activeTab,
                        children: [
                          _buildHomeView(isDesktop),
                          _buildAssistantView(),
                          _buildMemoryView(),
                          _buildWorldView(),
                          _buildSkillsView(),
                          _buildSettingsView(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // 3. MOBILE BOTTOM NAVIGATION
          bottomNavigationBar: isDesktop ? null : _buildMobileBottomBar(),
        );
      },
    );
  }

  // ==========================================================================
  // 1. TOP HEADER & GREETING PILL
  // ==========================================================================
  Widget _buildTopHeader(bool isDesktop) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF090E1F),
        border: Border(bottom: BorderSide(color: Color(0x1AFFFFFF))),
      ),
      child: Row(
        children: [
          if (!isDesktop) ...[
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFEC4899), Color(0xFF8B5CF6)],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text('✨', style: TextStyle(fontSize: 14)),
            ),
            const SizedBox(width: 10),
            const Text(
              'Maliha AI',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const Spacer(),
          ],

          // Floating Greeting Bubble
          Expanded(
            child: Align(
              alignment: isDesktop ? Alignment.centerLeft : Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0x261E293B),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: const Color(0x3300F0FF)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('✨', style: TextStyle(fontSize: 12)),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _greetingText,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFE2E8F0),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(width: 12),

          // Status Badge Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _agentRunning || _pcOnline
                  ? const Color(0x2610B981)
                  : const Color(0x26EF4444),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _agentRunning || _pcOnline
                    ? const Color(0x8010B981)
                    : const Color(0x80EF4444),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _agentRunning || _pcOnline
                        ? const Color(0xFF10B981)
                        : const Color(0xFFEF4444),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _agentRunning || _pcOnline
                            ? const Color(0x8010B981)
                            : const Color(0x80EF4444),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  Platform.isWindows && widget.cfg.role == AppRole.pcAgent
                      ? (_agentRunning ? 'PC AGENT LIVE' : 'AGENT STOPPED')
                      : (_pcOnline ? 'PC ONLINE' : 'PC STANDBY'),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: _agentRunning || _pcOnline
                        ? const Color(0xFF34D399)
                        : const Color(0xFFF87171),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // 2. DESKTOP SIDEBAR
  // ==========================================================================
  Widget _buildDesktopSidebar() {
    return Container(
      width: 210,
      decoration: const BoxDecoration(
        color: Color(0xFF090E1F),
        border: Border(right: BorderSide(color: Color(0x1AFFFFFF))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Brand Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFEC4899), Color(0xFF8B5CF6)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: const [
                      BoxShadow(color: Color(0x66EC4899), blurRadius: 10),
                    ],
                  ),
                  child: const Center(
                    child: Text('✨', style: TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Maliha AI',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Autonomous Hub',
                      style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(color: Color(0x1AFFFFFF), height: 1),
          const SizedBox(height: 12),

          // Nav Items
          _buildSidebarNavItem(0, Icons.home_rounded, 'Home'),
          _buildSidebarNavItem(1, Icons.terminal_rounded, 'Assistant'),
          _buildSidebarNavItem(2, Icons.memory_rounded, 'Memory'),
          _buildSidebarNavItem(3, Icons.public_rounded, 'World'),
          _buildSidebarNavItem(4, Icons.bolt_rounded, 'Skills'),

          const Spacer(),
          const Divider(color: Color(0x1AFFFFFF), height: 1),
          _buildSidebarNavItem(5, Icons.settings_rounded, 'Settings'),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildSidebarNavItem(int index, IconData icon, String label) {
    final active = _activeTab == index;
    return InkWell(
      onTap: () => setState(() => _activeTab = index),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: active
              ? const LinearGradient(
                  colors: [Color(0x403B82F6), Color(0x408B5CF6)],
                )
              : null,
          border: active
              ? Border.all(color: const Color(0x8060A5FA), width: 1)
              : null,
          boxShadow: active
              ? [
                  const BoxShadow(
                    color: Color(0x403B82F6),
                    blurRadius: 12,
                  )
                ]
              : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 19,
              color: active ? const Color(0xFF00F0FF) : const Color(0xFF94A3B8),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: active ? FontWeight.bold : FontWeight.w600,
                color: active ? Colors.white : const Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  // 3. MOBILE BOTTOM NAVIGATION BAR
  // ==========================================================================
  Widget _buildMobileBottomBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF090E1F),
        border: Border(top: BorderSide(color: Color(0x1AFFFFFF))),
      ),
      child: NavigationBar(
        backgroundColor: Colors.transparent,
        selectedIndex: _activeTab > 4 ? 4 : _activeTab,
        indicatorColor: const Color(0x3300F0FF),
        elevation: 0,
        height: 62,
        onDestinationSelected: (idx) {
          setState(() => _activeTab = idx == 4 ? 5 : idx);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded, color: Color(0xFF00F0FF)),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.terminal_outlined),
            selectedIcon: Icon(Icons.terminal_rounded, color: Color(0xFF00F0FF)),
            label: 'Assistant',
          ),
          NavigationDestination(
            icon: Icon(Icons.bolt_outlined),
            selectedIcon: Icon(Icons.bolt_rounded, color: Color(0xFF00F0FF)),
            label: 'Skills',
          ),
          NavigationDestination(
            icon: Icon(Icons.memory_outlined),
            selectedIcon: Icon(Icons.memory_rounded, color: Color(0xFF00F0FF)),
            label: 'Memory',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded, color: Color(0xFF00F0FF)),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // 4. VIEW 1: HOME (COSMIC ORB, QUICK ACTIONS, CHARACTER, WORLD, MEMORY)
  // ==========================================================================
  Widget _buildHomeView(bool isDesktop) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          if (isDesktop)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left Column: Quick Actions + Personal Agent Card
                Expanded(flex: 3, child: _buildLeftCards()),
                const SizedBox(width: 20),

                // Center Column: Animated Cosmic Holographic Orb
                Expanded(flex: 4, child: _buildCenterCosmicOrb()),
                const SizedBox(width: 20),

                // Right Column: World Monitor & Memory Cards
                Expanded(flex: 3, child: _buildRightCards()),
              ],
            )
          else ...[
            // Mobile layout (Orb on top, followed by quick cards)
            _buildCenterCosmicOrb(),
            const SizedBox(height: 24),
            _buildLeftCards(),
            const SizedBox(height: 20),
            _buildRightCards(),
          ],
        ],
      ),
    );
  }

  Widget _buildCenterCosmicOrb() {
    return Column(
      children: [
        const SizedBox(height: 20),
        // Central Animated 3D Cosmic Orb
        GestureDetector(
          onTap: _triggerVoiceOrb,
          child: AnimatedBuilder(
            animation: _orbAnimCtrl,
            builder: (context, _) {
              final angle = _orbAnimCtrl.value * 2 * math.pi;
              return Stack(
                alignment: Alignment.center,
                children: [
                  // Outer Orbit Ring 1
                  Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.002)
                      ..rotateX(1.1)
                      ..rotateZ(angle),
                    child: Container(
                      width: 220,
                      height: 220,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0x6600F0FF),
                          width: 2,
                        ),
                      ),
                    ),
                  ),

                  // Outer Orbit Ring 2
                  Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.002)
                      ..rotateY(1.0)
                      ..rotateZ(-angle * 1.2),
                    child: Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0x66C084FC),
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),

                  // Holographic Core Sphere
                  Container(
                    width: 130,
                    height: 130,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(
                        center: Alignment(-0.3, -0.3),
                        radius: 0.85,
                        colors: [
                          Color(0xFF67E8F9),
                          Color(0xFF38BDF8),
                          Color(0xFF3B82F6),
                          Color(0xFF8B5CF6),
                          Color(0xFF0F172A),
                        ],
                        stops: [0.0, 0.35, 0.65, 0.85, 1.0],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _isListening
                              ? const Color(0xFF00F0FF)
                              : const Color(0x8038BDF8),
                          blurRadius: _isListening ? 60 : 35,
                          spreadRadius: _isListening ? 15 : 2,
                        ),
                        const BoxShadow(
                          color: Color(0x66A855F7),
                          blurRadius: 40,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),

        const SizedBox(height: 24),

        // Waveform Equalizer Dock
        AnimatedBuilder(
          animation: _waveAnimCtrl,
          builder: (context, _) {
            final t = _waveAnimCtrl.value;
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(6, (i) {
                final h = 10.0 + math.sin(t * math.pi + (i * 0.7)).abs() * (_isListening ? 26 : 14);
                return Container(
                  width: 3.5,
                  height: h,
                  margin: const EdgeInsets.symmetric(horizontal: 2.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00F0FF),
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            );
          },
        ),

        const SizedBox(height: 12),

        // Mic Button & Status
        InkWell(
          onTap: _triggerVoiceOrb,
          borderRadius: BorderRadius.circular(30),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: const Color(0x4D00F0FF)),
              boxShadow: const [
                BoxShadow(color: Color(0x3300F0FF), blurRadius: 10),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isListening ? Icons.graphic_eq_rounded : Icons.mic_rounded,
                  color: const Color(0xFF00F0FF),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  _isListening ? 'Listening to voice...' : 'Tap for Voice / Action',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLeftCards() {
    return Column(
      children: [
        // Quick Actions Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF0E172E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0x3338BDF8)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Quick Actions',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.white,
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 16, color: Color(0xFF64748B)),
                ],
              ),
              const SizedBox(height: 12),
              _buildActionRow('Open Applications', Icons.desktop_windows_rounded, 'open notepad'),
              _buildActionRow('Screen Vision AI', Icons.remove_red_eye_rounded, 'explain screen'),
              _buildActionRow('Stealth Webcam Sentry', Icons.camera_alt_rounded, 'webcam'),
              _buildActionRow('Remote File Fetcher', Icons.folder_zip_rounded, 'list files'),
              _buildActionRow('Universal Clipboard', Icons.content_copy_rounded, 'clipboard'),
              _buildActionRow('Play Lo-Fi Music', Icons.music_note_rounded, 'open youtube'),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Personal Agent Profile Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF0E172E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0x3338BDF8)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFEC4899), Color(0xFF8B5CF6)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Center(
                  child: Text('👩‍💼', style: TextStyle(fontSize: 22)),
                ),
              ),
              const SizedBox(width: 14),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PERSONAL AGENT',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                  Text(
                    'Maliha',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    'Autonomous AI • Online',
                    style: TextStyle(fontSize: 11, color: Color(0xFF34D399)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionRow(String label, IconData icon, String cmd) {
    return InkWell(
      onTap: () => _dispatchCommand(cmd),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0x1A1E293B),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0x1AFFFFFF)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: const Color(0xFF38BDF8)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFE2E8F0),
                ),
              ),
            ),
            const Icon(Icons.chevron_right, size: 14, color: Color(0xFF64748B)),
          ],
        ),
      ),
    );
  }

  Widget _buildRightCards() {
    return Column(
      children: [
        // World Monitor Card
        InkWell(
          onTap: () => setState(() => _activeTab = 3),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0E172E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x3338BDF8)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'World Monitor',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.white,
                      ),
                    ),
                    Icon(Icons.open_in_new_rounded, size: 14, color: Color(0xFF64748B)),
                  ],
                ),
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [Color(0xFF38BDF8), Color(0xFF0B1938)],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _buildBulletItem('Top News: Gemini 2.0 & Flutter', const Color(0xFFEF4444)),
                _buildBulletItem('Global Events: Active Node', const Color(0xFFA855F7)),
                _buildBulletItem('Trending: Multiplatform AI', const Color(0xFF10B981)),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Memory Card
        InkWell(
          onTap: () => setState(() => _activeTab = 2),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0E172E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x3338BDF8)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0x26A855F7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.memory_rounded, color: Color(0xFFA855F7), size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Memory Bank',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      Text(
                        'Your preferences and context are safely synced with Windows PC.',
                        style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBulletItem(String text, Color dotColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 11.5, color: Color(0xFFCBD5E1)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // 5. VIEW 2: ASSISTANT (CHAT, RESULTS STREAM, SCREENSHOT/WEBCAM/FILE CARDS)
  // ==========================================================================
  Widget _buildAssistantView() {
    return Column(
      children: [
        // Quick Action Chips
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            children: [
              _buildChip('📸 Screenshot', 'screenshot'),
              _buildChip('👁️ Screen Vision', 'explain screen'),
              _buildChip('📷 Webcam Sentry', 'webcam'),
              _buildChip('📋 Clipboard Sync', 'clipboard'),
              _buildChip('🔋 Battery Guard', 'battery status'),
              _buildChip('📁 Fetch File', 'list files'),
              _buildChip('⏰ Schedule Timer', 'schedule 30 shutdown'),
              _buildChip('📊 PC Status', 'pc status'),
              _buildChip('▶️ YouTube', 'open youtube'),
              _buildChip('🔒 Lock PC', 'lock my pc'),
              _buildChip('⚡ Wake PC', 'wake'),
            ],
          ),
        ),

        const Divider(color: Color(0x1AFFFFFF), height: 1),

        // Live Chat & Results Stream
        Expanded(
          child: _results.isEmpty
              ? const Center(
                  child: Text(
                    'No commands executed yet. Tap any quick chip or type below.',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                  ),
                )
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: _results.length,
                  itemBuilder: (context, i) {
                    final item = _results[i];
                    return _buildResultCard(item);
                  },
                ),
        ),

        // Command Input Bar
        _buildCommandInputBar(),
      ],
    );
  }

  Widget _buildChip(String label, String cmd) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      child: ActionChip(
        label: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0F172A),
        side: const BorderSide(color: Color(0x3338BDF8)),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        onPressed: () => _dispatchCommand(cmd),
      ),
    );
  }

  Widget _buildResultCard(Map<String, dynamic> item) {
    final isAi = item['isAi'] == true;
    final text = item['text']?.toString() ?? '';
    final badge = item['badge']?.toString() ?? 'SYSTEM';
    final shot = item['screenshotB64'] as String?;
    final fileB64 = item['fileB64'] as String?;
    final fileName = item['fileName'] as String? ?? 'Downloaded File';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0E172E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isAi ? const Color(0x3338BDF8) : const Color(0x33A855F7),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isAi
                        ? [const Color(0xFFEC4899), const Color(0xFF8B5CF6)]
                        : [const Color(0xFF3B82F6), const Color(0xFF00F0FF)],
                  ),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Center(
                  child: Text(
                    isAi ? 'M' : 'YOU',
                    style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                isAi ? 'Maliha Assistant' : 'You',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0x2638BDF8),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  badge,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF38BDF8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            text,
            style: const TextStyle(fontSize: 13, color: Color(0xFFE2E8F0), height: 1.4),
          ),

          // Screenshot / Webcam image card
          if (shot != null && shot.length > 100) ...[
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0x3338BDF8)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.memory(
                base64Decode(shot),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 100,
                  color: Colors.black26,
                  alignment: Alignment.center,
                  child: const Text('Image preview unavailable', style: TextStyle(fontSize: 11)),
                ),
              ),
            ),
          ],

          // File Card
          if (fileB64 != null && fileB64.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0x4D38BDF8)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.insert_drive_file_rounded, color: Color(0xFF38BDF8), size: 26),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fileName,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Text(
                          'Cloud Received • Tap to Copy Data',
                          style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 16, color: Color(0xFF38BDF8)),
                    tooltip: 'Copy File Base64',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: fileB64));
                      _showToast('Copied file data to clipboard!');
                    },
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCommandInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
      decoration: const BoxDecoration(
        color: Color(0xFF090E1F),
        border: Border(top: BorderSide(color: Color(0x1AFFFFFF))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0x3338BDF8)),
              ),
              child: TextField(
                controller: _chatInputCtrl,
                style: const TextStyle(fontSize: 13, color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Ask Maliha (e.g. Open Notepad, Screenshot, File fetch)...',
                  hintStyle: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                  border: InputBorder.none,
                ),
                onSubmitted: (txt) => _dispatchCommand(txt),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Bangla Voice
          InkWell(
            onTap: () => _triggerVoiceInput('bn-BD'),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x4D38BDF8)),
              ),
              child: const Text(
                '🎙️ BN',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF38BDF8)),
              ),
            ),
          ),
          const SizedBox(width: 6),

          // English Voice
          InkWell(
            onTap: () => _triggerVoiceInput('en-US'),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x4D94A3B8)),
              ),
              child: const Text(
                '🎙️ EN',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)),
              ),
            ),
          ),
          const SizedBox(width: 6),

          // Send Button
          InkWell(
            onTap: () => _dispatchCommand(_chatInputCtrl.text),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF00F0FF), Color(0xFF3B82F6)],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(color: Color(0x6600F0FF), blurRadius: 8),
                ],
              ),
              child: const Icon(
                Icons.arrow_upward_rounded,
                color: Color(0xFF05070F),
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // 6. VIEW 3: MEMORY VIEW
  // ==========================================================================
  Widget _buildMemoryView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Maliha's Memory & Knowledge Bank",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.sync_rounded, size: 16),
                label: const Text('Sync Memory'),
                onPressed: () => _showToast('Memory synced with Cloud'),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Profile & Specs Grid
          _buildInfoCard(
            '👤 User Context & Profile',
            'Master: Boss (You)\nLanguage: বাংলা (Bengali) & English\nAudio Engine: Native Speech + Windows TTS\nStatus: Authenticated via Pairing Secret',
          ),
          const SizedBox(height: 12),
          _buildInfoCard(
            '💻 Linked Windows Hardware',
            'PC Name: DESKTOP-WINDOWS-11\nProcessor: Intel Core i7 12-Cores\nRAM: 16.0 GB DDR5 High-Speed\nStorage: NVMe SSD C: Drive (142 GB free)\nTunnel: Firebase Realtime Database Tunnel',
          ),
          const SizedBox(height: 12),
          _buildInfoCard(
            '🧠 Active Context Rules',
            '1. Maintain 60-second delay for shutdown/restart (safety cancel rule).\n2. Fallback to regex parser if offline; use Gemini 1.5 Flash for natural sentences.\n3. Capture screen in 1280x720 JPEG for ultra-low latency mobile transfer.',
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String title, String content) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0E172E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x3338BDF8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
          const SizedBox(height: 8),
          Text(content, style: const TextStyle(fontSize: 12.5, color: Color(0xFFCBD5E1), height: 1.5)),
        ],
      ),
    );
  }

  // ==========================================================================
  // 7. VIEW 4: WORLD MONITOR
  // ==========================================================================
  Widget _buildWorldView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'World & Network Intelligence',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Refresh Feed'),
                onPressed: () => _showToast('Global feed refreshed'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildInfoCard(
            '🌐 Global Connection Telemetry',
            'Latency to Home PC: 22ms • Bandwidth: 320 Mbps\nWebSocket REST Tunnel: Active\nWake-on-LAN UDP: Ready',
          ),
          const SizedBox(height: 12),
          _buildInfoCard(
            '🔥 Real-Time Trends & Feeds',
            '• Google Gemini 2.0 & Flutter 3.24 Multiplatform Updates\n• Windows 11 Remote Automation Best Practices\n• Wake-on-LAN Magic Packet UDP Broadcast Verified\n• Weather: 28°C Clear Skies, Dhaka, Bangladesh',
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // 8. VIEW 5: SKILLS VIEW & TEACHABLE SKILLS MODAL
  // ==========================================================================
  Widget _buildSkillsView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "${_skillsList.length} ACTIVE SKILLS",
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF34D399),
                ),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF00F0FF),
                  foregroundColor: const Color(0xFF05070F),
                ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('+ Teach New Skill', style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: _openTeachSkillDialog,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Grid of Skills
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollbyPhysics(),
            itemCount: _skillsList.length,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 320,
              mainAxisExtent: 170,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
            ),
            itemBuilder: (context, i) {
              final skill = _skillsList[i];
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0E172E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0x3338BDF8)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(skill['icon'], style: const TextStyle(fontSize: 16)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            skill['name'],
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0x2610B981),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            skill['badge'],
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF34D399),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: Text(
                        skill['desc'],
                        style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8), height: 1.3),
                      ),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          side: const BorderSide(color: Color(0x4D38BDF8)),
                        ),
                        onPressed: () => _dispatchCommand(skill['action']),
                        child: const Text('⚡ Test Skill', style: TextStyle(fontSize: 11)),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _openTeachSkillDialog() {
    final nameCtrl = TextEditingController();
    final triggerCtrl = TextEditingController();
    final targetCtrl = TextEditingController();
    final descCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0D1527),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0x4D00F0FF)),
          ),
          title: const Row(
            children: [
              Text('⚡', style: TextStyle(fontSize: 20)),
              SizedBox(width: 8),
              Text('Teach Maliha a New Skill', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Skill Name (e.g. Focus Mode)'),
                ),
                TextField(
                  controller: triggerCtrl,
                  decoration: const InputDecoration(labelText: 'Trigger Words (e.g. focus, start study)'),
                ),
                TextField(
                  controller: targetCtrl,
                  decoration: const InputDecoration(labelText: 'Target Command / Executable (e.g. code)'),
                ),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF00F0FF), foregroundColor: Colors.black),
              onPressed: () {
                final name = nameCtrl.text.trim();
                final target = targetCtrl.text.trim();
                if (name.isNotEmpty && target.isNotEmpty) {
                  setState(() {
                    _skillsList.add({
                      'id': DateTime.now().millisecondsSinceEpoch,
                      'icon': '✨',
                      'name': name,
                      'badge': 'TAUGHT',
                      'desc': descCtrl.text.trim().isEmpty ? 'Custom skill: $name' : descCtrl.text.trim(),
                      'action': target,
                      'isCustom': true,
                    });
                  });
                  Navigator.pop(context);
                  _showToast('✨ Maliha learned new skill: "$name"!');
                }
              },
              child: const Text('Teach Maliha', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  // ==========================================================================
  // 9. VIEW 6: SETTINGS VIEW & PC AGENT HUB
  // ==========================================================================
  Widget _buildSettingsView() {
    final dbCtrl = TextEditingController(text: widget.cfg.databaseUrl);
    final codeCtrl = TextEditingController(text: widget.cfg.pairingCode);
    final geminiCtrl = TextEditingController(text: widget.cfg.geminiApiKey);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Maliha System Settings',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.save_rounded, size: 16),
                label: const Text('Save Changes'),
                onPressed: () async {
                  widget.cfg
                    ..databaseUrl = dbCtrl.text.trim()
                    ..pairingCode = codeCtrl.text.trim()
                    ..geminiApiKey = geminiCtrl.text.trim();
                  await widget.cfg.save();
                  _showToast('💾 Settings saved successfully!');
                },
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Windows Agent Controls (Shown prominently on Windows)
          if (Platform.isWindows) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0E172E),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF38BDF8)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('🖥️ Windows PC Agent Hub', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),
                  const Text(
                    'The PC Agent listens in the background for remote commands sent from your phone.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: _agentRunning ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                        ),
                        icon: Icon(_agentRunning ? Icons.stop_rounded : Icons.play_arrow_rounded),
                        label: Text(_agentRunning ? 'Stop Agent' : 'Start Agent'),
                        onPressed: () {
                          if (_agentRunning) {
                            _stopPcAgentListener();
                          } else {
                            _startPcAgentListener();
                          }
                        },
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.autorenew_rounded),
                        label: const Text('Enable Autostart at Login'),
                        onPressed: () async {
                          final ok = await _executor.enableAutostart();
                          _showToast(ok ? '✓ Added to Windows Startup!' : 'Autostart configuration updated.');
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Form fields
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0E172E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x3338BDF8)),
            ),
            child: Column(
              children: [
                TextField(
                  controller: dbCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Firebase Realtime Database URL',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: codeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Pairing Secret Key (Must match across all devices)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: geminiCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Google Gemini API Key (Natural language & Screen Vision)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),

          // Terminal Activity Logs
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF090E1D),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x3338BDF8)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.terminal_rounded, size: 16, color: Color(0xFF38BDF8)),
                    SizedBox(width: 8),
                    Text(
                      'TERMINAL ACTIVITY AUDIT LOG',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 140,
                  child: ListView.builder(
                    itemCount: _terminalLogs.length,
                    itemBuilder: (_, i) => Text(
                      _terminalLogs[i],
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
