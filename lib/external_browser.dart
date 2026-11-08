// Dedicated "browser intent": open a URL in a SEPARATE real Chrome
// window — the user's own Chrome, with their Chrome profile session —
// instead of the app's built-in browser.
//
// * Android: a Kotlin intent hosted by MainActivity, targeted at the
//   Chrome package and falling back to the default browser. Chrome
//   manages its own full-screen window and session state; the in-app
//   browser keeps its page, history and selection untouched in the
//   meantime, and the URL handed over is the page currently open, so
//   the user continues exactly where they were.
// * Windows: launches chrome.exe (then Edge, then the default
//   browser) with --new-window and an explicit --window-size, so the
//   external window opens at a deliberate size — desktop size, or a
//   phone size when the caller is working in the mobile layout, so
//   responsive pages render the same way they do in-app.
// * Other platforms: returns false and the caller says so.
//
// Session note: the external Chrome uses the user's own Chrome
// profile. It cannot share the app browser's cookie jar (OS
// sandbox) — which is often exactly the point, since the user is
// usually already signed in there.
import 'dart:io';

import 'package:flutter/services.dart';

class ExternalBrowser {
  static const MethodChannel _channel =
      MethodChannel('com.geminihd.studio/browser');

  /// Open [url] in a separate Chrome window. [windowWidth] and
  /// [windowHeight] size the window on Windows; Android ignores
  /// them because Chrome opens full-screen there.
  static Future<bool> openInChrome(
    String url, {
    int windowWidth = 1400,
    int windowHeight = 920,
  }) async {
    if (url.trim().isEmpty) return false;
    try {
      if (Platform.isAndroid) {
        final ok = await _channel.invokeMethod<bool>(
          'openInChrome',
          {'url': url},
        );
        return ok ?? false;
      }
      if (Platform.isWindows) {
        return await _openWindows(url, windowWidth, windowHeight);
      }
    } catch (_) {
      return false;
    }
    return false;
  }

  static Future<bool> _openWindows(String url, int w, int h) async {
    final local = Platform.environment['LOCALAPPDATA'] ?? '';
    final browsers = <String>[
      r'C:\Program Files\Google\Chrome\Application\chrome.exe',
      r'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe',
      if (local.isNotEmpty)
        '$local\\Google\\Chrome\\Application\\chrome.exe',
      r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
      r'C:\Program Files\Microsoft\Edge\Application\msedge.exe',
    ];
    for (final exe in browsers) {
      if (await File(exe).exists()) {
        await Process.start(
          exe,
          ['--new-window', '--window-size=$w,$h', url],
          mode: ProcessStartMode.detached,
        );
        return true;
      }
    }
    // No Chrome/Edge found: hand the URL to the default browser.
    final res = await Process.run('cmd', ['/c', 'start', '', '"$url"']);
    return res.exitCode == 0;
  }
}
