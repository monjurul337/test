import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gemini_hd_studio/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('v64 header card is shorter: 32px action icons',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const GeminiHdStudioApp());
    await tester.pump(const Duration(milliseconds: 300));
    // All three header actions shrank from 34 to 32px.
    for (final tip in [
      'Import local set',
      'Panel upload settings',
      'Gemini Login',
    ]) {
      final btn = tester.widget<IconButton>(find.ancestor(
          of: find.byTooltip(tip), matching: find.byType(IconButton)));
      expect(btn.constraints!.maxWidth, 32);
      expect(btn.constraints!.maxHeight, 32);
      expect(btn.iconSize, 18);
    }
    expect(find.text('Version 2.5.06'), findsOneWidget);
    expect(find.text('Zedge Studio'), findsOneWidget);
    expect(find.text('Wallpaper Set Designer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
