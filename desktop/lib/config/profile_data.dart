// Build profiles available in this copy of the app.
//
// This bundle ships with its own profile only (values mirror the top of index.html).
// Add more profiles here and pick one with `--dart-define=BUILD=<id>`.

import 'build_config.dart';

/// Profile used when the app is built without `--dart-define=BUILD=...`.
const String kDefaultProfileId = 'monjurul';

/// Every profile compiled into this executable.
const List<BuildProfile> kProfiles = [
  kProfileMonjurul,
];

// ---------------------------------------------------------------------------
// monjurul - 4 accounts
// ---------------------------------------------------------------------------
const BuildProfile kProfileMonjurul = BuildProfile(
  id: 'monjurul',
  title: 'Monjurul (4 accounts)',
  r2WorkerUrl: 'https://zedgenew.edwardbales56.workers.dev',
  googleCalendarApiKey: 'AIzaSyAnNeYfEYF6Z41r-QBo2q8eWKaP-CBPlnc',
  defaultUploadWindows: {
    'zedge1': [4, 10, 16],
    'zedge2': [5, 11, 17],
    'zedge3': [10, 16, 20],
    'zedge4': [11, 17, 21],
  },
  accounts: [
    FirebaseAccountConfig(
      key: 'zedge1',
      apiKey: 'AIzaSyBJ8wtZVBsNsOljScwtWyaQGMZuvBeYKEQ',
      authDomain: 'zedge1-e30a0.firebaseapp.com',
      databaseURL: 'https://zedge1-e30a0-default-rtdb.firebaseio.com',
      projectId: 'zedge1-e30a0',
      storageBucket: 'zedge1-e30a0.firebasestorage.app',
      messagingSenderId: '619069366478',
      appId: '1:619069366478:web:7b4df317ca2a08ae61709f',
    ),
    FirebaseAccountConfig(
      key: 'zedge2',
      apiKey: 'AIzaSyAQYN9QyVJl6GO4HqCDHS7u75fViqNNXAg',
      authDomain: 'zedge2-e8d78.firebaseapp.com',
      databaseURL: 'https://zedge2-e8d78-default-rtdb.firebaseio.com',
      projectId: 'zedge2-e8d78',
      storageBucket: 'zedge2-e8d78.firebasestorage.app',
      messagingSenderId: '541024338424',
      appId: '1:541024338424:web:37ba73503fb1bf4983160d',
    ),
    FirebaseAccountConfig(
      key: 'zedge3',
      apiKey: 'AIzaSyBbuLqdA9CRc_dosrngiu2RDIUilLRmLbE',
      authDomain: 'zedge3-8a6ff.firebaseapp.com',
      databaseURL: 'https://zedge3-8a6ff-default-rtdb.firebaseio.com',
      projectId: 'zedge3-8a6ff',
      storageBucket: 'zedge3-8a6ff.firebasestorage.app',
      messagingSenderId: '577838404413',
      appId: '1:577838404413:web:55f73f7079062be762eb54',
    ),
    FirebaseAccountConfig(
      key: 'zedge4',
      apiKey: 'AIzaSyCr-wz__oMpqfhX6sOj0xD2G22xrogNMnI',
      authDomain: 'zedge4-36efb.firebaseapp.com',
      databaseURL: 'https://zedge4-36efb-default-rtdb.firebaseio.com',
      projectId: 'zedge4-36efb',
      storageBucket: 'zedge4-36efb.firebasestorage.app',
      messagingSenderId: '480666928530',
      appId: '1:480666928530:web:47c95186c9aa446b7ded4b',
    ),
  ],
);
