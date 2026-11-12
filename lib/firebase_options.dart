// Firebase options for the app login gate (v52).
//
// Project: r-final — the config the user supplied for the login
// panel. These values are the public client identifiers for the
// Firebase project (the same values that live in any web
// firebaseConfig); they are NOT a password and cannot by
// themselves sign in to anything. Real security is the Firebase
// Console settings (sign-in methods ON, authorized domains,
// Realtime Database rules) — see FIREBASE-SETUP-v52.txt.
//
// Manual init on purpose: the app has no google-services.json in
// the repo, so Firebase is initialized with these options in
// main() instead of reading a platform file. Email login works
// with this alone. Google sign-in on Android ALSO needs
// google-services.json + the debug SHA-1 registered in the
// Firebase project — without them Google login fails with a
// clear setup message (see friendlyAuthError in app_auth.dart).
import 'package:firebase_core/firebase_core.dart';

class DefaultFirebaseOptions {
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyA2fleTrPVIBz3plQcqg8gwCjYTeC8uSNc',
    appId: '1:998934859675:web:ee31e5c014c55bbc85db3e',
    messagingSenderId: '998934859675',
    projectId: 'r-final-f0c62',
    authDomain: 'r-final-f0c62.firebaseapp.com',
    databaseURL: 'https://r-final-f0c62-default-rtdb.firebaseio.com',
    storageBucket: 'r-final-f0c62.firebasestorage.app',
  );
}
