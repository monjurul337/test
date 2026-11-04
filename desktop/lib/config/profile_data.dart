// Build profiles available in this copy of the app.
//
// This bundle ships with its own profile only (values mirror the top of index.html).
// Add more profiles here and pick one with `--dart-define=BUILD=<id>`.

import 'build_config.dart';

/// Profile used when the app is built without `--dart-define=BUILD=...`.
const String kDefaultProfileId = 'template';

/// Every profile compiled into this executable.
const List<BuildProfile> kProfiles = [
  kProfileTemplate,
];

// ---------------------------------------------------------------------------
// template - SINGLE account (Firebase project zedge2-e8d78 on the zedge1 slot)
// ---------------------------------------------------------------------------
const BuildProfile kProfileTemplate = BuildProfile(
  id: 'template',
  title: 'Template (fill your own Firebase config)',
  r2WorkerUrl: 'https://zedgenew.edwardbales56.workers.dev',
  googleCalendarApiKey: '',
  defaultUploadWindows: {
    'zedge1': [10, 15, 20],
  },
  accounts: [
    FirebaseAccountConfig(
      key: 'zedge1',
      apiKey: 'AIzaSyAQYN9QyVJl6GO4HqCDHS7u75fViqNNXAg',
      authDomain: 'zedge2-e8d78.firebaseapp.com',
      databaseURL: 'https://zedge2-e8d78-default-rtdb.firebaseio.com',
      projectId: 'zedge2-e8d78',
      storageBucket: 'zedge2-e8d78.firebasestorage.app',
      messagingSenderId: '541024338424',
      appId: '1:541024338424:web:37ba73503fb1bf4983160d',
    ),
  ],
);
