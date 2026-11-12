// Background generation keep-alive (v33, user order: generation
// must continue "screen off & onno apps a gelo tao background a
// cole" — with the screen off and other apps in front).
//
// On Android a native foreground service (GenerationService.kt)
// plus a partial wake lock hold the process while any long
// generation is in flight; Android shows a small ongoing
// notification while it runs. Reference-counted so nested users
// (designer batch loop -> engine generateSet -> stage work, or a
// basket loop -> per-picture prompts) share one service period.
// No-op on every other platform.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ForegroundKeepAlive {
  static const MethodChannel _channel =
      MethodChannel('com.geminihd.studio/foreground');
  static int _count = 0;
  static bool _exemptionChecked = false;

  static bool get _android {
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  /// Start (or extend) a keep-alive period with the given
  /// notification label. Pair every acquire with a release.
  static Future<void> acquire(String label) async {
    if (!_android) return;
    _count++;
    try {
      await _channel.invokeMethod('start', {'label': label});
    } catch (_) {}
    if (_count == 1) _maybeAskBatteryExemption();
  }

  /// End one keep-alive period; the service stops when the last
  /// holder releases.
  static Future<void> release() async {
    if (!_android) return;
    if (_count > 0) _count--;
    if (_count != 0) return;
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {}
  }

  /// Post a one-off completion notification (Android only) — the
  /// overnight queue uses it when it finishes while the user is
  /// away from the phone (v47).
  static Future<void> notifyDone(String title, String body) async {
    if (!_android) return;
    try {
      await _channel.invokeMethod('notifyDone', {
        'title': title,
        'body': body,
      });
    } catch (_) {}
  }

  /// One time per install: if the phone's battery manager may
  /// kill the app, ask Android for the exemption — budget phones
  /// (itel / Transsion and friends) kill background apps
  /// aggressively, sometimes even with a foreground service.
  static Future<void> _maybeAskBatteryExemption() async {
    if (_exemptionChecked) return;
    _exemptionChecked = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('bgExemptionAskedV33') ?? false) return;
      await prefs.setBool('bgExemptionAskedV33', true);
      final exempt =
          await _channel.invokeMethod<bool>('isBatteryExempt') ?? false;
      if (!exempt) {
        await _channel.invokeMethod('requestBatteryExemption');
      }
    } catch (_) {}
  }
}
