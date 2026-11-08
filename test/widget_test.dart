import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';

import 'package:gemini_hd_studio/gemini_api.dart';
import 'package:gemini_hd_studio/image_search.dart';
import 'package:gemini_hd_studio/main.dart';
import 'package:gemini_hd_studio/models.dart';
import 'package:gemini_hd_studio/session_store.dart';
import 'package:gemini_hd_studio/studio_engine.dart';
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
    // 'Showcase' appears in the nav rail AND the panel header.
    expect(find.text('Showcase'), findsWidgets);
    // New feature entry points live in the Set Designer panel.
    expect(find.text('Image to Prompt'), findsOneWidget);
    expect(find.text('Search images'), findsOneWidget);
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

  // ---- Mobile responsiveness: no RenderFlex overflow on phones ----
  for (final size in const [Size(320, 568), Size(360, 640), Size(390, 844)]) {
    testWidgets('Home screen fits phone size $size', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const GeminiHdStudioApp());
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      // Open the Advanced settings (dropdowns, size fields, toggles)
      // inside the Studio tab's designer card.
      await tester.ensureVisible(find.text('Advanced settings'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('Advanced settings'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      // Switch to the Showcase tab via the bottom navigation bar and
      // make sure the gallery renders cleanly at this size too.
      await tester.tap(find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Showcase')));
      await tester.pump(const Duration(milliseconds: 450));
      expect(tester.takeException(), isNull);
      expect(find.text('Metadata (all)'), findsOneWidget);
    });
  }

  testWidgets('SetCard + set preview fit a 320px phone', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final entry = SetEntry(
      id: 't1',
      prompt: 'A very long prompt about neon mountains at dusk over a lake',
      workflowMode: 'set_dual',
      setTypeLabel: 'Dual Set (Lock + Home)',
      setFolderName: 'set-01',
      createdAtIso: '2026-11-08T01:00:00.000',
      metadata: SetMetadata(
        title: 'Neon Mountain Dusk',
        tags: ['neon', 'mountain', 'dusk', 'lake', 'amoled', 'dark'],
        category: 'NATURE',
        description: 'A neon mountain scene at dusk.',
      ),
      images: [
        SetImage(
          localPath: '/nonexistent/lock.jpg',
          exactFilename: 'lock.jpg',
          zipName: '01-lock.jpg',
          distSlot: 'lock',
          role: 'lock',
          label: 'Lock Screen',
          badge: 'LOCK',
          slotIndex: 0,
          stageKey: 'lock',
          width: 1620,
          height: 2880,
          byteSize: 3 * 1024 * 1024,
        ),
        SetImage(
          localPath: '/nonexistent/home.jpg',
          exactFilename: 'home.jpg',
          zipName: '02-home.jpg',
          distSlot: 'home',
          role: 'home',
          label: 'Home Screen',
          badge: 'HOME',
          slotIndex: 1,
          stageKey: 'home',
          width: 1620,
          height: 2880,
          byteSize: 3 * 1024 * 1024,
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SetCard(
            entry: entry,
            engine: StudioEngine(),
            onChanged: () async {},
            onExportZip: (_) {},
            snack: (_) {},
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.text('Upload to Panel'), findsOneWidget);
    // Open the phone set-preview simulator dialog.
    await tester.ensureVisible(find.text('Preview set'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Preview set'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.text('Set preview'), findsOneWidget);
  });

  test('Image search URL builders encode the query', () {
    expect(googleImagesSearchUrl('neon mountain'),
        contains('google.com/search?tbm=isch'));
    expect(googleImagesSearchUrl('neon mountain'),
        contains('q=neon%20mountain'));
    expect(pinterestSearchUrl('amoled wallpaper'),
        'https://www.pinterest.com/search/pins/?q=amoled%20wallpaper');
  });

  test('parseImageCandidates filters, dedupes and ranks biggest first', () {
    final raw = jsonEncode([
      {'url': 'https://example.com/og.jpg', 'w': 0, 'h': 0},
      {'url': 'https://example.com/big.jpg', 'w': 1200, 'h': 1600},
      {'url': 'https://example.com/icon.png', 'w': 64, 'h': 64},
      {'url': 'data:image/png;base64,AAAA', 'w': 800, 'h': 800},
      {'url': 'https://example.com/big.jpg', 'w': 1200, 'h': 1600},
      {'url': 'https://example.com/mid.jpg', 'w': 600, 'h': 800},
      {'url': 'https://example.com/thin.jpg', 'w': 120, 'h': 900},
    ]);
    final c = parseImageCandidates(raw);
    expect(c.length, 3);
    expect(c[0].url, 'https://example.com/big.jpg');
    expect(c[1].url, 'https://example.com/mid.jpg');
    expect(c[2].url, 'https://example.com/og.jpg');
    expect(parseImageCandidates('not json'), isEmpty);
    expect(parseImageCandidates(null), isEmpty);
  });

  test('cleanGeneratedPrompt strips labels, quotes and extra paragraphs',
      () {
    expect(
      GeminiApi.cleanGeneratedPrompt(
          'Prompt: "A neon mountain at dusk, ultra detailed"\n\nHope this helps!'),
      'A neon mountain at dusk, ultra detailed',
    );
    expect(
      GeminiApi.cleanGeneratedPrompt('```\nA calm lake at dawn\n```'),
      'A calm lake at dawn',
    );
    expect(GeminiApi.cleanGeneratedPrompt('   '), isEmpty);
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
