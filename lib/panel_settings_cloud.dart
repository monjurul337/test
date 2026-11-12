// Panel settings cloud sync (v53): the databases entered in
// Panel Upload Settings are saved in Firebase (r-final project),
// under the signed-in user's own node, so they survive reinstalls
// and come back on any device with the same login.
//
// Storage: Realtime Database
//   users/{uid}/panelSettings = { ...DistConfig, updatedAtMillis }
// Auth: the user's Firebase ID token (?auth=...) — the RTDB rules
// (users/$uid readable/writable only by that uid, see
// FIREBASE-SETUP-v52.txt) allow exactly this and nothing else.
// Local SharedPreferences stays the offline cache and the source
// the uploader reads; the cloud copy is the backup + sync.
//
// Last-write-wins by updatedAtMillis: on the settings screen,
// a cloud copy NEWER than the local one replaces it; a local
// save always pushes to the cloud afterwards. Nothing is ever
// merged field-by-field — one side wins whole.
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'firebase_options.dart';
import 'models.dart';

/// Thrown when the cloud read/write fails; [message] is written
/// for the settings screen, in plain language.
class PanelSettingsCloudException implements Exception {
  final String message;
  const PanelSettingsCloudException(this.message);
  @override
  String toString() => message;
}

/// REST URL for one user's panel-settings node. The ID token goes
/// in the query so the RTDB rules can check auth.uid.
String panelSettingsCloudUrl({
  required String uid,
  required String idToken,
}) {
  final base = Uri.parse(DefaultFirebaseOptions.android.databaseURL!);
  return base
      .replace(
        path: 'users/$uid/panelSettings.json',
        queryParameters: {'auth': idToken},
      )
      .toString();
}

/// Cloud document: the whole DistConfig plus its write time.
Map<String, dynamic> panelSettingsToCloudJson(
  DistConfig cfg, {
  required int updatedAtMillis,
}) => {
      ...cfg.toJson(),
      'updatedAtMillis': updatedAtMillis,
    };

/// Parses a cloud document. Null when there is nothing saved yet
/// (RTDB returns the JSON literal `null`) or the document is not
/// a JSON object.
({DistConfig config, int updatedAtMillis})? panelSettingsFromCloudJson(
  Object? json,
) {
  if (json is! Map) return null;
  final map = Map<String, dynamic>.from(json);
  return (
    config: DistConfig.fromJson(map),
    updatedAtMillis: map['updatedAtMillis'] is num
        ? (map['updatedAtMillis'] as num).toInt()
        : 0,
  );
}

/// Last-write-wins: the cloud copy replaces the local one only
/// when it was written later.
bool cloudIsNewer({
  required int cloudUpdatedAtMillis,
  required int localUpdatedAtMillis,
}) =>
    cloudUpdatedAtMillis > localUpdatedAtMillis;

/// Thin REST client for the panel-settings node. The http client
/// is injectable so tests can use a MockClient.
class PanelSettingsCloud {
  final http.Client _client;
  PanelSettingsCloud({http.Client? client})
      : _client = client ?? http.Client();

  Future<({DistConfig config, int updatedAtMillis})?> fetch({
    required String uid,
    required String idToken,
  }) async {
    final res = await _client.get(
      Uri.parse(panelSettingsCloudUrl(uid: uid, idToken: idToken)),
    );
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw const PanelSettingsCloudException(
        'Firebase Rules allow korche na — Realtime Database Rules e '
        'users/\$uid rule ta bosano ache kina check korun '
        '(FIREBASE-SETUP-v52.txt).',
      );
    }
    if (res.statusCode != 200) {
      throw PanelSettingsCloudException(
        'Firebase theke settings ana jay nai (HTTP ${res.statusCode}).',
      );
    }
    return panelSettingsFromCloudJson(jsonDecode(res.body));
  }

  Future<void> save({
    required String uid,
    required String idToken,
    required DistConfig config,
    int? updatedAtMillis,
  }) async {
    final res = await _client.put(
      Uri.parse(panelSettingsCloudUrl(uid: uid, idToken: idToken)),
      body: jsonEncode(panelSettingsToCloudJson(
        config,
        updatedAtMillis:
            updatedAtMillis ?? DateTime.now().millisecondsSinceEpoch,
      )),
    );
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw const PanelSettingsCloudException(
        'Firebase Rules allow korche na — Realtime Database Rules e '
        'users/\$uid rule ta bosano ache kina check korun '
        '(FIREBASE-SETUP-v52.txt).',
      );
    }
    if (res.statusCode != 200) {
      throw PanelSettingsCloudException(
        'Firebase e settings save hoy nai (HTTP ${res.statusCode}).',
      );
    }
  }
}
