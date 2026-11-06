import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
      title: 'Maliha - AI Assistant',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF05070F),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00F0FF),
          secondary: Color(0xFF3B82F6),
          surface: Color(0xFF0F172A),
        ),
        cardTheme: const CardTheme(
          color: Color(0xFF0F172A),
          elevation: 2,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: Color(0xFF1E293B)),
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF080C18),
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
        ),
      ),
      home: _cfg == null
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _showSetup
              ? SetupScreen(
                  cfg: _cfg!,
                  onDone: () => setState(() => _showSetup = false))
              : _homeForRole(),
    );
  }

  Widget _homeForRole() {
    final cfg = _cfg!;
    final openSetup = () => setState(() => _showSetup = true);
    switch (cfg.role) {
      case AppRole.controller:
        return ControllerScreen(cfg: cfg, onOpenSetup: openSetup);
      case AppRole.bridge:
        return BridgeScreen(cfg: cfg, onOpenSetup: openSetup);
      case AppRole.pcAgent:
        return AgentScreen(cfg: cfg, onOpenSetup: openSetup);
    }
  }
}

// ---------------------------------------------------------------- SETUP
class SetupScreen extends StatefulWidget {
  final AppConfig cfg;
  final VoidCallback onDone;
  const SetupScreen({super.key, required this.cfg, required this.onDone});
  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  late final _db = TextEditingController(text: widget.cfg.databaseUrl);
  late final _code = TextEditingController(text: widget.cfg.pairingCode);
  late final _mac = TextEditingController(text: widget.cfg.pcMac);
  late final _bcast = TextEditingController(text: widget.cfg.broadcastIp);
  late final _gemini = TextEditingController(text: widget.cfg.geminiApiKey);
  late AppRole _role = widget.cfg.role;

  Future<void> _save() async {
    widget.cfg
      ..databaseUrl = _db.text
      ..pairingCode = _code.text
      ..pcMac = _mac.text
      ..broadcastIp = _bcast.text
      ..geminiApiKey = _gemini.text
      ..role = _role;
    await widget.cfg.save();
    if (Platform.isAndroid) {
      try {
        await NativeBridge.saveBridgeConfig(widget.cfg);
      } catch (_) {}
    }
    if (mounted) widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PC Assistant - Setup')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
              'One app, three roles. Give every device the SAME cloud settings below and they will find each other.',
              style: TextStyle(fontSize: 15)),
          const SizedBox(height: 16),
          TextField(
              controller: _db,
              decoration: const InputDecoration(
                  labelText: 'Firebase Realtime Database URL',
                  hintText: 'https://your-project-default-rtdb.firebaseio.com',
                  border: OutlineInputBorder())),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: TextField(
                    controller: _code,
                    decoration: const InputDecoration(
                        labelText: 'Pairing code (shared secret)',
                        border: OutlineInputBorder()))),
            const SizedBox(width: 8),
            OutlinedButton(
                onPressed: () =>
                    setState(() => _code.text = AppConfig.generatePairingCode()),
                child: const Text('Generate')),
          ]),
          const SizedBox(height: 12),
          TextField(
              controller: _mac,
              decoration: const InputDecoration(
                  labelText: 'PC MAC address (wired Ethernet)',
                  hintText: 'AA:BB:CC:DD:EE:FF',
                  border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(
              controller: _bcast,
              decoration: const InputDecoration(
                  labelText: 'Home broadcast IP',
                  hintText: '192.168.1.255',
                  border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(
              controller: _gemini,
              decoration: const InputDecoration(
                  labelText: 'Gemini API Key (Optional - for advanced AI)',
                  hintText: 'AIzaSy...',
                  border: OutlineInputBorder())),
          const SizedBox(height: 16),
          DropdownButtonFormField<AppRole>(
            value: _role,
            decoration: const InputDecoration(
                labelText: 'This device is the...', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(
                  value: AppRole.controller,
                  child: Text('Controller - my phone, I give commands')),
              DropdownMenuItem(
                  value: AppRole.bridge,
                  child: Text('Bridge - old phone at home, wakes the PC')),
              DropdownMenuItem(
                  value: AppRole.pcAgent,
                  child: Text('PC Agent - the Windows PC itself')),
            ],
            onChanged: (v) => setState(() => _role = v ?? AppRole.controller),
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: _save, child: const Text('Save and continue')),
          const SizedBox(height: 12),
          const Text(
              'Keep the pairing code private - anyone with it and the database URL can send commands to your PC.',
              style: TextStyle(color: Colors.orangeAccent)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- CONTROLLER
class ControllerScreen extends StatefulWidget {
  final AppConfig cfg;
  final VoidCallback onOpenSetup;
  const ControllerScreen({super.key, required this.cfg, required this.onOpenSetup});
  @override
  State<ControllerScreen> createState() => _ControllerScreenState();
}

class _ControllerScreenState extends State<ControllerScreen> {
  late final RelayClient _relay = RelayClient(widget.cfg);
  final _input = TextEditingController();
  bool _online = false;
  List<Map<String, dynamic>> _results = [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final online = await _relay.isPcOnline();
      final raw = await _relay.getNode('results');
      final list = <Map<String, dynamic>>[];
      if (raw is Map) {
        raw.forEach((k, v) {
          if (v is Map) list.add(Map<String, dynamic>.from(v));
        });
      }
      list.sort((a, b) =>
          ((b['ts'] as num?)?.toInt() ?? 0).compareTo((a['ts'] as num?)?.toInt() ?? 0));
      if (mounted) {
        setState(() {
          _online = online;
          _results = list.take(20).toList();
        });
      }
    } catch (_) {}
  }

  Future<void> _send(String text) async {
    if (text.trim().isEmpty) return;
    final parsed = await parseCommandWithAi(text, geminiApiKey: widget.cfg.geminiApiKey);
    try {
      await _relay.queueCommand(parsed[0], parsed[1]);
      if (!_online) {
        await _relay.requestWake();
        _snack('PC is offline - wake request sent, command queued.');
      } else {
        _snack('Command sent: ' + text);
      }
      _input.clear();
      _refresh();
    } catch (e) {
      _snack('Send failed: ' + e.toString());
    }
  }

  Future<void> _mic(String locale) async {
    final text = await NativeBridge.startSpeech(locale);
    if (text != null && text.trim().isNotEmpty) {
      _input.text = text;
      _send(text);
    } else {
      _snack('Voice দিয়ে কিছু শোনা যায়নি - আবার চেষ্টা করো।');
    }
  }

  void _snack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Widget _buildChip(String label, String command) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () async {
          if (command == '__wake__') {
            await _relay.requestWake();
            _snack('Wake request sent to the bridge.');
          } else {
            _send(command);
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF1E293B)),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFFCBD5E1),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05070F),
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF00F0FF), Color(0xFF3B82F6)],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.bolt, size: 18, color: Color(0xFF05070F)),
            ),
            const SizedBox(width: 10),
            const Text(
              'Maliha // AI Core',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Color(0xFF94A3B8)),
            onPressed: widget.onOpenSetup,
          ),
        ],
      ),
      body: Column(
        children: [
          // Glowing status banner
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _online ? const Color(0x1A10B981) : const Color(0x1AEF4444),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _online ? const Color(0x4D10B981) : const Color(0x4DEF4444),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _online ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _online ? const Color(0x8010B981) : const Color(0x80EF4444),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _online ? 'PC ONLINE • READY' : 'PC OFFLINE • BRIDGE STANDBY',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _online ? const Color(0xFF34D399) : const Color(0xFFF87171),
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        _online
                            ? 'Gemini 1.5 Neural Core & Remote Agent Active'
                            : 'Commands will queue; bridge will wake PC.',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                      ),
                    ],
                  ),
                ),
                if (_online)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0x3338BDF8),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'AI READY',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF38BDF8),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Smart Quick Action Pills
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _buildChip('📸 স্ক্রিনশট', 'screenshot'),
                _buildChip('📊 PC Status', 'pc status'),
                _buildChip('▶️ YouTube', 'open youtube'),
                _buildChip('🌐 Chrome', 'open chrome'),
                _buildChip('📝 Notepad', 'open notepad'),
                _buildChip('🔒 Lock PC', 'lock my pc'),
                _buildChip('⚡ Wake PC', '__wake__'),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Header for Results Stream
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'EXECUTION STREAM & RESULTS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                    color: Color(0xFF64748B),
                  ),
                ),
                Text(
                  '${_results.length} events',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),

          // Stream / Results List
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.terminal, size: 48, color: Colors.blue.withOpacity(0.3)),
                        const SizedBox(height: 12),
                        const Text(
                          'No command executions yet.',
                          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Send a message or tap any action above.',
                          style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    itemCount: _results.length,
                    itemBuilder: (_, i) {
                      final r = _results[i];
                      final shot = r['screenshotB64'] as String?;
                      final text = r['text']?.toString() ?? '';
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFF1E293B)),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x20000000),
                              blurRadius: 8,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0x3300F0FF),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      'RESULT',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF00F0FF),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      text,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: Color(0xFFF1F5F9),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (shot != null && shot.length > 100)
                                Container(
                                  margin: const EdgeInsets.only(top: 10),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: const Color(0xFF334155)),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: Image.memory(
                                    base64Decode(shot),
                                    errorBuilder: (_, __, ___) => Container(
                                      height: 120,
                                      color: Colors.black26,
                                      alignment: Alignment.center,
                                      child: const Text(
                                        '[Screenshot preview unavailable]',
                                        style: TextStyle(
                                            color: Color(0xFF64748B), fontSize: 12),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // Futuristic Floating Bottom Input Bar
          Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
            decoration: const BoxDecoration(
              color: Color(0xFF080C18),
              border: Border(top: BorderSide(color: Color(0xFF1E293B))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: TextField(
                      controller: _input,
                      style: const TextStyle(fontSize: 13, color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Maliha-কে বলুন (যেমন: ইউটিউব চালাও, স্ক্রিনশট)...',
                        hintStyle: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                        border: InputBorder.none,
                      ),
                      onSubmitted: _send,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Bangla Voice
                InkWell(
                  onTap: () => _mic('bn-BD'),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.4)),
                    ),
                    child: const Text(
                      '🎙️ BN',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF38BDF8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // English Voice
                InkWell(
                  onTap: () => _mic('en-US'),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF475569)),
                    ),
                    child: const Text(
                      '🎙️ EN',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Send
                InkWell(
                  onTap: () => _send(_input.text),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF00F0FF), Color(0xFF3B82F6)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x6600F0FF),
                          blurRadius: 8,
                        ),
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
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- PC AGENT
class AgentScreen extends StatefulWidget {
  final AppConfig cfg;
  final VoidCallback onOpenSetup;
  const AgentScreen({super.key, required this.cfg, required this.onOpenSetup});
  @override
  State<AgentScreen> createState() => _AgentScreenState();
}

class _AgentScreenState extends State<AgentScreen> {
  late final RelayClient _relay = RelayClient(widget.cfg);
  final PcExecutor _executor = PcExecutor();
  final List<String> _log = [];
  bool _running = false;
  Timer? _pollTimer;
  Timer? _heartbeatTimer;

  @override
  void initState() {
    super.initState();
    if (widget.cfg.isComplete && Platform.isWindows) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _start();
      });
    }
  }

  void _addLog(String line) {
    if (mounted) {
      setState(() => _log.insert(0,
          DateTime.now().toString().substring(11, 19) + '  ' + line));
    }
  }

  void _start() {
    if (_running) return;
    _running = true;
    _addLog('Agent started. Listening for commands...');
    _heartbeat();
    _heartbeatTimer =
        Timer.periodic(const Duration(seconds: 10), (_) => _heartbeat());
    _poll();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _poll());
    setState(() {});
  }

  void _stop() {
    _running = false;
    _pollTimer?.cancel();
    _heartbeatTimer?.cancel();
    _addLog('Agent stopped.');
    setState(() {});
  }

  Future<void> _heartbeat() async {
    try {
      await _relay.sendHeartbeat(Platform.operatingSystem);
    } catch (_) {}
  }

  Future<void> _poll() async {
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
        await _relay.patchNode('commands/' + id, {'status': 'running'});
        _addLog('Running: ' + type + ' ' + payload);
        final result = await _executor.execute(type, payload);
        await _relay.patchNode('commands/' + id, {'status': 'done'});
        await _relay.postNode('results', {
          'commandId': id,
          'text': result.text,
          'screenshotB64': result.screenshotB64,
          'ts': DateTime.now().millisecondsSinceEpoch,
        });
        _addLog('Done: ' + result.text);
      }
    } catch (e) {
      _addLog('Poll error: ' + e.toString());
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _heartbeatTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05070F),
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF38BDF8), Color(0xFF818CF8)],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.computer, size: 18, color: Color(0xFF05070F)),
            ),
            const SizedBox(width: 10),
            const Text(
              'Maliha PC Agent // Windows Hub',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Color(0xFF94A3B8)),
            onPressed: widget.onOpenSetup,
          )
        ],
      ),
      body: Column(
        children: [
          if (!Platform.isWindows)
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0x33EF4444),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFEF4444)),
              ),
              child: const Text(
                'Note: PC Agent mode runs on the Windows PC. On phone, select Controller or Bridge mode.',
                style: TextStyle(color: Color(0xFFFCA5A5), fontSize: 12),
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF0A0F1D),
              border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
            ),
            child: Row(
              children: [
                InkWell(
                  onTap: _running ? null : _start,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: _running
                          ? null
                          : const LinearGradient(
                              colors: [Color(0xFF00F0FF), Color(0xFF3B82F6)]),
                      color: _running ? const Color(0xFF1E293B) : null,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _running ? const Color(0xFF10B981) : Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _running ? 'Agent Running' : 'Start Agent',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _running
                                ? const Color(0xFF34D399)
                                : const Color(0xFF05070F),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (_running)
                  OutlinedButton(
                    onPressed: _stop,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFF87171),
                      side: const BorderSide(color: Color(0xFFEF4444)),
                    ),
                    child: const Text('Stop'),
                  ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () async {
                    final ok = await _executor.enableAutostart();
                    _addLog(ok
                        ? 'Autostart enabled (Startup folder shortcut).'
                        : 'Autostart failed.');
                  },
                  child: const Text('✓ Enable Autostart'),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: const Color(0xFF04060C),
            child: const Row(
              children: [
                Icon(Icons.terminal, size: 14, color: Color(0xFF38BDF8)),
                SizedBox(width: 8),
                Text(
                  'TERMINAL ACTIVITY LOG (REAL-TIME AUDIT)',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              color: const Color(0xFF04060C),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: _log.length,
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(
                    _log[i],
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: _log[i].contains('Done')
                          ? const Color(0xFF34D399)
                          : _log[i].contains('Running')
                              ? const Color(0xFF38BDF8)
                              : const Color(0xFFCBD5E1),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- BRIDGE
class BridgeScreen extends StatefulWidget {
  final AppConfig cfg;
  final VoidCallback onOpenSetup;
  const BridgeScreen({super.key, required this.cfg, required this.onOpenSetup});
  @override
  State<BridgeScreen> createState() => _BridgeScreenState();
}

class _BridgeScreenState extends State<BridgeScreen> {
  String _status = 'Bridge service is not started yet.';

  Future<void> _call(Future<bool> Function() fn, String okMsg) async {
    try {
      await NativeBridge.saveBridgeConfig(widget.cfg);
      final ok = await fn();
      setState(() => _status = ok ? okMsg : 'The phone did not confirm - check again.');
    } on MissingPluginException {
      setState(() => _status = 'Bridge mode only works on the Android app.');
    } catch (e) {
      setState(() => _status = 'Error: ' + e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PC Assistant - Bridge'),
        actions: [
          IconButton(icon: const Icon(Icons.settings), onPressed: widget.onOpenSetup)
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text(
            'Keep this old phone plugged in, on the same home Wi-Fi/LAN as the PC. It listens for wake requests and turns the PC on with Wake-on-LAN.',
            style: TextStyle(fontSize: 15)),
        const SizedBox(height: 8),
        const Text(
            'Tip: turn OFF battery optimisation for this app in Android settings, otherwise the phone may kill the bridge.'),
        const SizedBox(height: 16),
        Text(_status, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        FilledButton(
            onPressed: () => _call(NativeBridge.startBridgeService,
                'Bridge service started. It will poll every 5 seconds.'),
            child: const Text('Start bridge')),
        const SizedBox(height: 8),
        OutlinedButton(
            onPressed: () => _call(
                NativeBridge.stopBridgeService, 'Bridge service stopped.'),
            child: const Text('Stop bridge')),
        const SizedBox(height: 8),
        OutlinedButton(
            onPressed: () => _call(() => NativeBridge.sendWakeNow(widget.cfg),
                'Wake packet sent now - the PC should turn on.'),
            child: const Text('Test: wake the PC now')),
      ]),
    );
  }
}
