import 'dart:convert';
import 'package:http/http.dart' as http;
import 'app_config.dart';

/// Talks to Firebase Realtime Database over its REST API.
/// Data layout: {databaseUrl}/pcassistant/{pairingCode}/<node>.json
/// The pairing code acts as the shared secret between your own devices.
class RelayClient {
  final AppConfig cfg;
  RelayClient(this.cfg);

  Uri _uri(String node) =>
      Uri.parse('${cfg.cleanDatabaseUrl}/pcassistant/${cfg.pairingCode.trim()}/$node.json');

  Future<dynamic> getNode(String node) async {
    final res = await http.get(_uri(node)).timeout(const Duration(seconds: 15));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Cloud read failed (${res.statusCode})');
    }
    if (res.body == 'null') return null;
    return jsonDecode(res.body);
  }

  Future<void> putNode(String node, Object body) async {
    final res = await http
        .put(_uri(node), body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Cloud write failed (${res.statusCode})');
    }
  }

  Future<void> patchNode(String node, Map<String, dynamic> body) async {
    final res = await http
        .patch(_uri(node), body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Cloud update failed (${res.statusCode})');
    }
  }

  Future<String?> postNode(String node, Map<String, dynamic> body) async {
    final res = await http
        .post(_uri(node), body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Cloud send failed (${res.statusCode})');
    }
    final decoded = jsonDecode(res.body);
    return decoded is Map ? decoded['name'] as String? : null;
  }

  Future<void> sendHeartbeat(String platform) => putNode('heartbeat', {
        'ts': DateTime.now().millisecondsSinceEpoch,
        'platform': platform,
      });

  Future<void> requestWake() => putNode('wake', {
        'requested': true,
        'mac': cfg.pcMac.trim(),
        'broadcast': cfg.broadcastIp.trim(),
        'ts': DateTime.now().millisecondsSinceEpoch,
      });

  Future<String?> queueCommand(String type, String payload) => postNode('commands', {
        'type': type,
        'payload': payload,
        'status': 'queued',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });

  Future<bool> isPcOnline() async {
    final hb = await getNode('heartbeat');
    if (hb is! Map) return false;
    final ts = (hb['ts'] as num?)?.toInt() ?? 0;
    return DateTime.now().millisecondsSinceEpoch - ts < 30000;
  }
}
