import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gemini_hd_studio/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

Finder _headerCard() => find.byWidgetPredicate((w) =>
    w is Container &&
    w.decoration is BoxDecoration &&
    (w.decoration as BoxDecoration).gradient != null &&
    (w.decoration as BoxDecoration).borderRadius ==
        BorderRadius.circular(24));

void main() {
  testWidgets('v68 desktop header is about half its old height',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const GeminiHdStudioApp());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    // v67 measured 218px; v68 merges rows (chips into the title
    // row, status inline in the account row) to about half that.
    expect(_headerCard(), findsOneWidget);
    expect(tester.getSize(_headerCard()).height, lessThanOrEqualTo(120));

    // Everything still there, just merged: chips, subtitle, status.
    expect(find.text('0 sets'), findsOneWidget);
    expect(find.text('Wallpaper Set Designer'), findsOneWidget);
    expect(find.text('Not connected'), findsOneWidget);
    expect(find.text('Version 2.5.09'), findsOneWidget);

    // Subtitle still sits directly under the title text (v63).
    final titleLeft = tester.getTopLeft(find.text('Zedge Studio')).dx;
    final subtitleLeft =
        tester.getTopLeft(find.text('Wallpaper Set Designer')).dx;
    expect(subtitleLeft, moreOrLessEquals(titleLeft, epsilon: 1.0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('v68 phone header is unchanged', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const GeminiHdStudioApp());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Version 2.5.09'), findsOneWidget);
    expect(find.text('Wallpaper Set Designer'), findsOneWidget);
    expect(find.text('Not connected'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
