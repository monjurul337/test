import 'dart:io';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

enum AppRole { controller, bridge, pcAgent }

class AppConfig {
  static const defaultDatabaseUrl =
      'https://extention-a5961-default-rtdb.firebaseio.com';
  static const defaultPairingCode = 'assistant-key-7788';

  String databaseUrl;
  String pairingCode;
  String pcMac;
  String broadcastIp;
  String geminiApiKey;
  AppRole role;

  AppConfig({
    this.databaseUrl = defaultDatabaseUrl,
    this.pairingCode = defaultPairingCode,
    this.pcMac = '',
    this.broadcastIp = '192.168.1.255',
    this.geminiApiKey = '',
    AppRole? role,
  }) : role = role ?? (Platform.isWindows ? AppRole.pcAgent : AppRole.controller);

  bool get isComplete =>
      databaseUrl.trim().isNotEmpty && pairingCode.trim().isNotEmpty;

  String get cleanDatabaseUrl {
    var u = databaseUrl.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  static String generatePairingCode() {
    const chars = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    return List.generate(20, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  static Future<AppConfig> load() async {
    final p = await SharedPreferences.getInstance();
    final dbUrl = p.getString('databaseUrl');
    final code = p.getString('pairingCode');
    return AppConfig(
      databaseUrl: (dbUrl != null && dbUrl.isNotEmpty) ? dbUrl : defaultDatabaseUrl,
      pairingCode: (code != null && code.isNotEmpty) ? code : defaultPairingCode,
      pcMac: p.getString('pcMac') ?? '',
      broadcastIp: p.getString('broadcastIp') ?? '192.168.1.255',
      geminiApiKey: p.getString('geminiApiKey') ?? '',
      role: AppRole.values.firstWhere(
        (r) =>
            r.name ==
            (p.getString('role') ??
                (Platform.isWindows ? 'pcAgent' : 'controller')),
        orElse: () =>
            Platform.isWindows ? AppRole.pcAgent : AppRole.controller,
      ),
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('databaseUrl', databaseUrl.trim());
    await p.setString('pairingCode', pairingCode.trim());
    await p.setString('pcMac', pcMac.trim());
    await p.setString('broadcastIp', broadcastIp.trim());
    await p.setString('geminiApiKey', geminiApiKey.trim());
    await p.setString('role', role.name);
  }
}
