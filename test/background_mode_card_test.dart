// v77: the Background generation card — one in-app switch
// instead of hunting through Settings.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gemini_hd_studio/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Background generation card shows a switch, ON by default',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const GeminiHdStudioApp());
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Background generation'), findsOneWidget);
    final sw =
        tester.widget<Switch>(find.byKey(const ValueKey('bgModeSwitch')));
    expect(sw.value, isTrue);
    // Turning it OFF sticks and shows the OFF status line.
    await tester.tap(find.byKey(const ValueKey('bgModeSwitch')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('OFF — phone lock korle generation thambe.'),
        findsOneWidget);
  });
}
