import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gemini_hd_studio/main.dart';
import 'package:gemini_hd_studio/studio_constants.dart';

void main() {
  test('v58 foldable prompt lives in the backend, word for word', () {
    expect(
        kFoldableAdaptationPrompt,
        'make it landscape mode, re-frame the exact same artwork for a foldable screen without cropping the main subject');
  });

  testWidgets('v58 Studio shows no foldable prompt field', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const GeminiHdStudioApp());
    await tester.pump(const Duration(milliseconds: 300));
    // Switch to the mode that used to show the editable field.
    await tester.tap(find.text('9:16 + Foldable'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Foldable adaptation prompt'), findsNothing);
    expect(find.text('Reference image (optional)'), findsOneWidget);
  });
}
