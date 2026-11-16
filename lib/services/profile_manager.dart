import 'package:dio/dio.dart';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AccountProfile {
  final String id;
  final String name;
  final int seed;
  final String osType;
  final String platform;
  final String? customUserAgent;
  final String? customWebglVendor;
  final String? customWebglRenderer;
  final String canvasMode;
  final String audioMode;
  final String? timezone;
  final String? wgConfName;
  final String? wgConfContent;
  final String? proxyUrl;
  final String lastEarnings;
  final int lastDownloads;
  final String lastIp;
  final String lastCountry;

  const AccountProfile({
    required this.id,
    required this.name,
    required this.seed,
    this.osType = 'Android',
    this.platform = 'All',
    this.customUserAgent,
    this.customWebglVendor,
    this.customWebglRenderer,
    this.canvasMode = 'Noise',
    this.audioMode = 'Noise',
    this.timezone,
    this.wgConfName,
    this.wgConfContent,
    this.proxyUrl,
    this.lastEarnings = r'$0.00',
    this.lastDownloads = 0,
    this.lastIp = 'Checking...',
    this.lastCountry = 'Unknown',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'seed': seed,
        'osType': osType,
        'platform': platform,
        'customUserAgent': customUserAgent,
        'customWebglVendor': customWebglVendor,
        'customWebglRenderer': customWebglRenderer,
        'canvasMode': canvasMode,
        'audioMode': audioMode,
        'timezone': timezone,
        'wgConfName': wgConfName,
        'wgConfContent': wgConfContent,
        'proxyUrl': proxyUrl,
        'lastEarnings': lastEarnings,
        'lastDownloads': lastDownloads,
        'lastIp': lastIp,
        'lastCountry': lastCountry,
      };

  factory AccountProfile.fromJson(Map<String, dynamic> j) => AccountProfile(
        id: (j['id'] ?? 'p1').toString(),
        name: (j['name'] ?? 'Profile 1').toString(),
        seed: (j['seed'] as num?)?.toInt() ?? 100001,
        osType: (j['osType'] ?? 'Android').toString(),
        platform: (j['platform'] ?? 'All').toString(),
        customUserAgent: j['customUserAgent']?.toString(),
        customWebglVendor: j['customWebglVendor']?.toString(),
        customWebglRenderer: j['customWebglRenderer']?.toString(),
        canvasMode: (j['canvasMode'] ?? 'Noise').toString(),
        audioMode: (j['audioMode'] ?? 'Noise').toString(),
        timezone: j['timezone']?.toString(),
        wgConfName: j['wgConfName']?.toString(),
        wgConfContent: j['wgConfContent']?.toString(),
        proxyUrl: j['proxyUrl']?.toString(),
        lastEarnings: (j['lastEarnings'] ?? r'$0.00').toString(),
        lastDownloads: (j['lastDownloads'] as num?)?.toInt() ?? 0,
        lastIp: (j['lastIp'] ?? 'Checking...').toString(),
        lastCountry: (j['lastCountry'] ?? 'Unknown').toString(),
      );
}

class ProfileManager {
  static const _profilesKey = 'mh_account_profiles';
  static const _activeKey = 'mh_active_profile_id';
  static const _wgChannel = MethodChannel('com.mynxsoft.mhmotion/wireguard');

  static const _domains = [
    'https://accounts.google.com',
    'https://colab.research.google.com',
    'https://gemini.google.com',
    'https://contributor.stock.adobe.com',
  ];

  static Future<(List<AccountProfile>, String)> loadProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_profilesKey);
    List<AccountProfile> list = [];
    if (raw != null && raw.isNotEmpty) {
      final decoded = jsonDecode(raw) as List;
      list = decoded.map((e) => AccountProfile.fromJson(Map<String, dynamic>.from(e))).toList();
    }
    if (list.isEmpty) {
      final r = Random.secure();
      list = [
        AccountProfile(
          id: 'p_adobe',
          name: 'Adobe Stock #1',
          platform: 'Adobe Stock',
          seed: r.nextInt(899999) + 100000,
        ),
        AccountProfile(
          id: 'p_shutter',
          name: 'Shutterstock #1',
          platform: 'Shutterstock',
          seed: r.nextInt(899999) + 100000,
        ),
        AccountProfile(
          id: 'p_magnific',
          name: 'Magnific #1',
          platform: 'Magnific',
          seed: r.nextInt(899999) + 100000,
        ),
        AccountProfile(
          id: 'p_gemini',
          name: 'Gemini Web #1',
          platform: 'Gemini',
          seed: r.nextInt(899999) + 100000,
        ),
      ];
      await saveProfiles(list, 'p_adobe');
    }
    final activeId = prefs.getString(_activeKey) ?? list.first.id;
    return (list, activeId);
  }

  static Future<void> saveProfiles(List<AccountProfile> list, String activeId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profilesKey, jsonEncode(list.map((e) => e.toJson()).toList()));
    await prefs.setString(_activeKey, activeId);
  }

  static Future<void> snapshotCookiesFor(String profileId) async {
    final cm = CookieManager.instance();
    final map = <String, List<Map<String, dynamic>>>{};
    for (final d in _domains) {
      final cookies = await cm.getCookies(url: WebUri(d));
      map[d] = cookies
          .map((c) => {
                'name': c.name,
                'value': c.value,
                'domain': c.domain,
                'path': c.path ?? '/',
                'isSecure': c.isSecure ?? true,
                'isHttpOnly': c.isHttpOnly ?? false,
              })
          .toList();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mh_cookies_$profileId', jsonEncode(map));
  }

  static Future<void> restoreCookiesFor(String profileId) async {
    final cm = CookieManager.instance();
    await cm.deleteAllCookies();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('mh_cookies_$profileId');
    if (raw == null || raw.isEmpty) return;
    final map = Map<String, dynamic>.from(jsonDecode(raw));
    for (final entry in map.entries) {
      final url = WebUri(entry.key);
      for (final c in (entry.value as List)) {
        final m = Map<String, dynamic>.from(c);
        await cm.setCookie(
          url: url,
          name: m['name'],
          value: m['value'],
          domain: m['domain'],
          path: m['path'] ?? '/',
          isSecure: m['isSecure'] == true,
          isHttpOnly: m['isHttpOnly'] == true,
        );
      }
    }
  }


  static Future<void> updateActiveStats({required String earnings, required int downloads}) async {
    final (list, activeId) = await loadProfiles();
    final idx = list.indexWhere((e) => e.id == activeId);
    if (idx != -1) {
      final old = list[idx];
      list[idx] = AccountProfile(
        id: old.id,
        name: old.name,
        seed: old.seed,
        osType: old.osType,
        wgConfName: old.wgConfName,
        wgConfContent: old.wgConfContent,
        lastEarnings: earnings,
        lastDownloads: downloads,
        lastIp: old.lastIp,
        lastCountry: old.lastCountry,
      );
      await saveProfiles(list, activeId);
    }
  }


  static Future<void> applyHttpProxy(String? proxyUrl) async {
    try {
      final ctrl = ProxyController.instance();
      if (proxyUrl == null || proxyUrl.trim().isEmpty) {
        await ctrl.clearProxyOverride();
      } else {
        await ctrl.setProxyOverride(
          settings: ProxySettings(
            proxyRules: [ProxyRule(url: proxyUrl.trim())],
          ),
        );
      }
    } catch (_) {}
  }


  static Future<(String ip, String country)> fetchPublicIpInfo() async {
    final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 6), receiveTimeout: const Duration(seconds: 6)));
    try {
      final r = await dio.get('https://ipwho.is/');
      if (r.data is Map && r.data['success'] == true) {
        final ip = (r.data['ip'] ?? 'Unknown').toString();
        final country = (r.data['country'] ?? 'Unknown').toString();
        final code = (r.data['country_code'] ?? '').toString();
        return (ip, code.isNotEmpty ? '$country ($code)' : country);
      }
    } catch (_) {}
    try {
      final r = await dio.get('https://api.ipify.org?format=json');
      if (r.data is Map) {
        return ((r.data['ip'] ?? 'Unknown').toString(), 'Detected');
      }
    } catch (_) {}
    return ('Offline', 'No Network');
  }

  static Future<void> updateActiveIpInfo({required String ip, required String country}) async {
    final (list, activeId) = await loadProfiles();
    final idx = list.indexWhere((e) => e.id == activeId);
    if (idx != -1) {
      final old = list[idx];
      list[idx] = AccountProfile(
        id: old.id,
        name: old.name,
        seed: old.seed,
        osType: old.osType,
        wgConfName: old.wgConfName,
        wgConfContent: old.wgConfContent,
        lastEarnings: old.lastEarnings,
        lastDownloads: old.lastDownloads,
        lastIp: ip,
        lastCountry: country,
      );
      await saveProfiles(list, activeId);
    }
  }

  static Future<bool> connectWireGuard(String confContent) async {
    final ok = await _wgChannel.invokeMethod('connect', {'config': confContent});
    return ok == true;
  }

  static Future<bool> disconnectWireGuard() async {
    final ok = await _wgChannel.invokeMethod('disconnect');
    return ok == true;
  }
}
