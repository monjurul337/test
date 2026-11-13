import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gemini_hd_studio/main.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('v61 header shows the new reference-violet logo icon',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const GeminiHdStudioApp());
    await tester.pump(const Duration(milliseconds: 300));
    // The header tile now renders the new icon asset (32x32 since v62).
    expect(find.image(const AssetImage('assets/logo.png')), findsOneWidget);
    // Chip tracks the current build (v62 compacted the header).
    expect(find.text('Version 2.5.03'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('v61 launcher icon files exist on disk', () {
    for (final d in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
      expect(
          File('android/app/src/main/res/mipmap-$d/ic_launcher.png')
              .existsSync(),
          isTrue,
          reason: 'legacy $d launcher icon missing');
      expect(
          File('android/app/src/main/res/mipmap-$d/ic_launcher_foreground.png')
              .existsSync(),
          isTrue,
          reason: 'adaptive foreground $d missing');
    }
    // Adaptive background is the reference violet, not white.
    final bg = File(
            'android/app/src/main/res/drawable/ic_launcher_background.xml')
        .readAsStringSync();
    expect(bg.contains('#4328CD'), isTrue);
    expect(bg.contains('#FFFFFF'), isFalse);
    // Windows icon.
    expect(File('windows/runner/resources/app_icon.ico').existsSync(), isTrue);
    // The in-app logo is the 512 violet tile with the white mark.
    final logoBytes = File('assets/logo.png').readAsBytesSync();
    final logo = img.decodePng(logoBytes)!;
    expect(logo.width, 512);
    expect(logo.height, 512);
    // Rounded tile: corner is transparent, top-centre is reference violet.
    expect(logo.getPixel(0, 0).a, 0);
    final top = logo.getPixel(256, 8);
    expect(top.r, 67);
    expect(top.g, 40);
    expect(top.b, 205);
  });
}
