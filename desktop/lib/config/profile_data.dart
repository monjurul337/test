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
// template (tamplate-vpn.zip) - 4 accounts, placeholders, fill via SETUP.md
// ---------------------------------------------------------------------------
const BuildProfile kProfileTemplate = BuildProfile(
  id: 'template',
  title: 'Template (fill your own Firebase config)',
  r2WorkerUrl: 'https://zedgemedia.monjurulgd2001.workers.dev',
  googleCalendarApiKey: '',
  defaultUploadWindows: {
    'zedge1': [10, 15, 20],
    'zedge2': [11, 16, 21],
    'zedge3': [5, 11, 17],
    'zedge4': [4, 9, 14],
  },
  accounts: [
    FirebaseAccountConfig(
      key: 'zedge1',
      apiKey: 'AIzaSyBsoxNIpAECkPaFOU0wUHY6q0NcvWbK4AI',
      authDomain: 'zedge-r2-edward-hermes.firebaseapp.com',
      databaseURL: 'https://zedge-r2-edward-hermes-default-rtdb.firebaseio.com',
      projectId: 'zedge-r2-edward-hermes',
      storageBucket: 'zedge-r2-edward-hermes.firebasestorage.app',
      messagingSenderId: '539346447692',
      appId: '1:539346447692:web:dc9d1f1b8f90ca5f7133e9',
    ),
    FirebaseAccountConfig(
      key: 'zedge2',
      apiKey: 'AIzaSyBW7Pm5Eegg90htCAcnMZXT5kLCQ2bSxEc',
      authDomain: 'zedge-r2-ryan-hermes.firebaseapp.com',
      databaseURL: 'https://zedge-r2-ryan-hermes-default-rtdb.firebaseio.com',
      projectId: 'zedge-r2-ryan-hermes',
      storageBucket: 'zedge-r2-ryan-hermes.firebasestorage.app',
      messagingSenderId: '347245367374',
      appId: '1:347245367374:web:1a2f6f9e956f263059331f',
    ),
    FirebaseAccountConfig(
      key: 'zedge3',
      apiKey: 'AIzaSyCgjmRx6pwEf5QJQxjOOy4TYGA6tZScD3Y',
      authDomain: 'zedge-r2-christian-hermes.firebaseapp.com',
      databaseURL: 'https://zedge-r2-christian-hermes-default-rtdb.firebaseio.com',
      projectId: 'zedge-r2-christian-hermes',
      storageBucket: 'zedge-r2-christian-hermes.firebasestorage.app',
      messagingSenderId: '927102645505',
      appId: '1:927102645505:web:44cf6feaaf6456716b1700',
    ),
    FirebaseAccountConfig(
      key: 'zedge4',
      apiKey: 'AIzaSyDTJDG9mfZ-y-GVBHFMxOADDc-HUov4GvA',
      authDomain: 'zedge-r2-elive-hermes.firebaseapp.com',
      databaseURL: 'https://zedge-r2-elive-hermes-default-rtdb.firebaseio.com',
      projectId: 'zedge-r2-elive-hermes',
      storageBucket: 'zedge-r2-elive-hermes.firebasestorage.app',
      messagingSenderId: '514156710479',
      appId: '1:514156710479:web:8d93d3822412e79876383a',
    ),
  ],
);
