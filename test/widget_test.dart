import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';

import 'package:gemini_hd_studio/gemini_api.dart';
import 'package:gemini_hd_studio/main.dart';
import 'package:gemini_hd_studio/session_store.dart';
import 'package:gemini_hd_studio/studio_constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('App boots to the Studio home screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    // Wide surface -> the two-panel desktop layout, both panels visible.
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const GeminiHdStudioApp());
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Gemini HD Studio'), findsWidgets);
    expect(find.text('Set Designer'), findsOneWidget);
    expect(find.text('Showcase'), findsOneWidget);
  });

  test('Cookie paste normalisation handles header + bare values', () {
    final header = SessionStore.normalisePastedCookies(
        '__Secure-1PSID=abc123; __Secure-1PSIDTS=xyz789');
    expect(header, contains('__Secure-1PSID=abc123'));
    expect(header, contains('__Secure-1PSIDTS=xyz789'));
    final bare = SessionStore.normalisePastedCookies('abc123\nxyz789');
    expect(bare, contains('__Secure-1PSID=abc123'));
    expect(SessionStore.cookieHeaderLooksLoggedIn(header), isTrue);
    expect(SessionStore.cookieHeaderLooksLoggedIn('foo=bar'), isFalse);
  });

  test('Zedge dimension rules enforce the 1620x2880 minimum', () {
    final d = normalizeZedgeDimensions(1080, 1920);
    expect(d.width, greaterThanOrEqualTo(1620));
    expect(d.height, greaterThanOrEqualTo(2880));
    final ok = normalizeZedgeDimensions(1620, 2880);
    expect(ok.width, 1620);
    expect(ok.height, 2880);
  });

  test('parseStreamGenerateResponse extracts image url + text', () {
    final api = GeminiApi();
    final inner = jsonEncode([
      null,
      ['conv1', 'resp1'],
      null,
      null,
      [
        ['choice1', ['Hello world answer'], null, null,
          ['https://lh3.googleusercontent.com/gg-dl/AbCdEfGhIjKlMnOpQrStUvWxYz0123456789abcd=s1024']]
      ]
    ]);
    final line = jsonEncode([
      ['wrb.fr', null, inner]
    ]);
    final raw = ")]}'\n123\n$line\n";
    final parsed = api.parseStreamGenerateResponse(raw);
    expect(parsed.assistantText, 'Hello world answer');
    expect(parsed.urls.length, 1);
    expect(parsed.urls.first, startsWith('https://lh3.googleusercontent.com/gg-dl/'));
    // excluded urls are filtered by base key
    final parsed2 = api.parseStreamGenerateResponse(raw, excludeUrls: parsed.urls);
    expect(parsed2.urls, isEmpty);
  });

  test('extractJsonMapFromReply finds balanced JSON in prose', () {
    final api = GeminiApi();
    final m = api.extractJsonMapFromReply(
        'Sure! {"title": "Alpine Lake", "tags": ["lake"], "category": "NATURE", "description": "Nice."} done');
    expect(m?['title'], 'Alpine Lake');
    expect(m?['category'], 'NATURE');
  });

  test('session html parsing finds email + token presence', () {
    expect(
        GeminiApi.extractEmailFromHtml('"oPEP7c":"user.name@gmail.com"'),
        'user.name@gmail.com');
    expect(GeminiApi.isQuotaOrLimitFailure(429, ''), isTrue);
    expect(GeminiApi.isQuotaOrLimitFailure(200, 'You reached your limit'), isTrue);
    expect(GeminiApi.isQuotaOrLimitFailure(200, 'all good'), isFalse);
  });
}
