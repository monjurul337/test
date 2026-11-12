// Panel settings cloud sync (v53): URL building, JSON
// round-trip, last-write-wins and the REST fetch/save against a
// MockClient. No real Firebase is touched.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gemini_hd_studio/models.dart';
import 'package:gemini_hd_studio/panel_settings_cloud.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

DistConfig _sampleConfig() => DistConfig(
      r2WorkerUrl: 'https://demo.workers.dev',
      queuePath: 'wallpaperQueue',
      accounts: [
        DistAccount(
            name: 'zedge_1',
            dbUrl: 'https://zedge1-default-rtdb.firebaseio.com',
            secret: 's3cr3t'),
        DistAccount(
            name: 'zedge_2',
            dbUrl: 'https://zedge2-default-rtdb.firebaseio.com'),
      ],
      defaultTarget: 'spread',
    );

void main() {
  test('panelSettingsCloudUrl points at the user node with the token',
      () {
    final url = panelSettingsCloudUrl(uid: 'uid-1', idToken: 'tok en/x');
    expect(url, contains('r-final-f0c62-default-rtdb.firebaseio.com'));
    expect(url, contains('users/uid-1/panelSettings.json'));
    // Dart encodes the space as '+' in the query; parsing the URL
    // back must give the exact token. (Real ID tokens are JWTs —
    // base64url only — so this edge never occurs in practice.)
    expect(Uri.parse(url).queryParameters['auth'], 'tok en/x');
  });

  test('cloud JSON round-trips the whole config incl. secrets', () {
    final cfg = _sampleConfig();
    final parsed =
        panelSettingsFromCloudJson(panelSettingsToCloudJson(cfg, updatedAtMillis: 123456));
    expect(parsed, isNotNull);
    expect(parsed!.config.r2WorkerUrl, 'https://demo.workers.dev');
    expect(parsed.config.queuePath, 'wallpaperQueue');
    expect(parsed.config.defaultTarget, 'spread');
    expect(parsed.config.accounts.length, 2);
    expect(parsed.config.accounts[0].name, 'zedge_1');
    expect(parsed.config.accounts[0].dbUrl,
        'https://zedge1-default-rtdb.firebaseio.com');
    expect(parsed.config.accounts[0].secret, 's3cr3t');
    expect(parsed.config.accounts[1].secret, '');
    expect(parsed.updatedAtMillis, 123456);
  });

  test('panelSettingsFromCloudJson returns null for nothing/garbage', () {
    expect(panelSettingsFromCloudJson(null), isNull);
    expect(panelSettingsFromCloudJson('nope'), isNull);
    expect(panelSettingsFromCloudJson(42), isNull);
    final empty = panelSettingsFromCloudJson({});
    expect(empty, isNotNull);
    expect(empty!.config.accounts, isEmpty);
    expect(empty.updatedAtMillis, 0);
  });

  test('cloudIsNewer is strict last-write-wins', () {
    expect(
        cloudIsNewer(
            cloudUpdatedAtMillis: 2000, localUpdatedAtMillis: 1000),
        isTrue);
    expect(
        cloudIsNewer(
            cloudUpdatedAtMillis: 1000, localUpdatedAtMillis: 1000),
        isFalse);
    expect(
        cloudIsNewer(
            cloudUpdatedAtMillis: 500, localUpdatedAtMillis: 1000),
        isFalse);
  });

  test('fetch returns the saved config', () async {
    final cloud = PanelSettingsCloud(
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, contains('panelSettings.json'));
        return http.Response(
            jsonEncode(panelSettingsToCloudJson(_sampleConfig(),
                updatedAtMillis: 777)),
            200);
      }),
    );
    final got = await cloud.fetch(uid: 'uid-1', idToken: 'tok');
    expect(got, isNotNull);
    expect(got!.config.accounts.length, 2);
    expect(got.updatedAtMillis, 777);
  });

  test('fetch returns null when Firebase has nothing saved', () async {
    final cloud = PanelSettingsCloud(
      client: MockClient((_) async => http.Response('null', 200)),
    );
    expect(await cloud.fetch(uid: 'uid-1', idToken: 'tok'), isNull);
  });

  test('fetch 401 explains the Rules fix', () async {
    final cloud = PanelSettingsCloud(
      client: MockClient((_) async => http.Response('denied', 401)),
    );
    expect(
      () => cloud.fetch(uid: 'uid-1', idToken: 'tok'),
      throwsA(isA<PanelSettingsCloudException>().having(
          (e) => e.message, 'message', contains('Rules'))),
    );
  });

  test('save PUTs the config with the given timestamp', () async {
    http.Request? seen;
    String? seenBody;
    final cloud = PanelSettingsCloud(
      client: MockClient((request) async {
        seen = request;
        seenBody = request.body;
        return http.Response('{}', 200);
      }),
    );
    await cloud.save(
        uid: 'uid-1',
        idToken: 'tok',
        config: _sampleConfig(),
        updatedAtMillis: 999);
    expect(seen!.method, 'PUT');
    expect(seen!.url.path, contains('users/uid-1/panelSettings.json'));
    final body = jsonDecode(seenBody!) as Map<String, dynamic>;
    expect(body['r2WorkerUrl'], 'https://demo.workers.dev');
    expect((body['accounts'] as List).length, 2);
    expect(body['updatedAtMillis'], 999);
  });

  test('save 403 explains the Rules fix', () async {
    final cloud = PanelSettingsCloud(
      client: MockClient((_) async => http.Response('denied', 403)),
    );
    expect(
      () => cloud.save(
          uid: 'uid-1', idToken: 'tok', config: _sampleConfig()),
      throwsA(isA<PanelSettingsCloudException>().having(
          (e) => e.message, 'message', contains('Rules'))),
    );
  });
}
