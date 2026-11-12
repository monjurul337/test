// App login gate (v52): Firebase Auth for the r-final project.
//
// Why this exists: the user wants Zedge Studio usable only after
// login — "apps ta user jeno login kore calaite pare". The gate
// is enforced on Android, where Firebase Auth runs. Windows has
// no Firebase Auth plugin, so there the gate is skipped and the
// app opens as before (see shouldEnforceGate + AuthGate).
//
// This is NOT a replacement for the Gemini login: generating
// images still needs the Gemini Google session cookies from the
// Login tab. Firebase login only proves who the app user is.
//
// The service is an interface (AppAuth) so widget tests can use
// a fake instead of touching Firebase channels.
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'firebase_options.dart';

/// A signed-in app user, in the app's own words.
class AppUser {
  final String uid;
  final String? email;
  final String? displayName;
  const AppUser({required this.uid, this.email, this.displayName});

  factory AppUser.fromFirebase(User user) => AppUser(
        uid: user.uid,
        email: user.email,
        displayName: user.displayName,
      );
}

/// Thrown when the user cancels the Google sign-in flow.
class AppAuthCancelled implements Exception {
  const AppAuthCancelled();
}

/// The login operations the gate screen needs.
abstract class AppAuth {
  Stream<AppUser?> get authStateChanges;
  AppUser? get currentUser;

  Future<AppUser> signInWithEmail({
    required String email,
    required String password,
  });
  Future<AppUser> registerWithEmail({
    required String name,
    required String email,
    required String password,
  });
  Future<AppUser> signInWithGoogle();
  Future<void> sendPasswordReset(String email);
  Future<void> signOut();

  /// Firebase ID token for the signed-in user, for authenticated
  /// Realtime Database REST calls (v53 panel-settings cloud sync).
  /// Null when signed out.
  Future<String?> getIdToken();
}

/// Firebase-backed implementation of [AppAuth].
class FirebaseAppAuth implements AppAuth {
  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;

  FirebaseAppAuth._(this._auth) : _googleSignIn = GoogleSignIn();

  /// Initializes Firebase (Android, manual options) and returns the
  /// service. Throws when Firebase cannot start — main() catches
  /// that and shows the setup-error screen instead of the gate.
  static Future<FirebaseAppAuth> initialize() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.android,
    );
    return FirebaseAppAuth._(FirebaseAuth.instance);
  }

  @override
  Stream<AppUser?> get authStateChanges =>
      _auth.authStateChanges().map((u) => u == null ? null : AppUser.fromFirebase(u));

  @override
  AppUser? get currentUser {
    final u = _auth.currentUser;
    return u == null ? null : AppUser.fromFirebase(u);
  }

  @override
  Future<AppUser> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final cred = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    return AppUser.fromFirebase(cred.user!);
  }

  @override
  Future<AppUser> registerWithEmail({
    required String name,
    required String email,
    required String password,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final user = cred.user!;
    await user.updateDisplayName(name);
    return AppUser.fromFirebase(user);
  }

  @override
  Future<AppUser> signInWithGoogle() async {
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) throw const AppAuthCancelled();
    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    final cred = await _auth.signInWithCredential(credential);
    return AppUser.fromFirebase(cred.user!);
  }

  @override
  Future<void> sendPasswordReset(String email) =>
      _auth.sendPasswordResetEmail(email: email);

  @override
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  @override
  Future<String?> getIdToken() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    return user.getIdToken();
  }
}

/// The gate is enforced only where Firebase Auth actually runs:
/// Android, once Firebase has initialized. Everywhere else (and
/// while init is still failing) the app opens as before — a hard
/// lockout on a platform without Auth would brick the Windows
/// build, which has no Firebase Auth plugin.
bool shouldEnforceGate({
  required bool isAndroid,
  required bool firebaseReady,
}) =>
    isAndroid && firebaseReady;

/// Plain-language email check for the gate form.
bool isValidEmail(String email) {
  final trimmed = email.trim();
  if (trimmed.isEmpty || trimmed.contains(' ')) return false;
  final parts = trimmed.split('@');
  if (parts.length != 2) return false;
  if (parts[0].isEmpty || parts[1].isEmpty) return false;
  return parts[1].contains('.');
}

/// Turns an auth failure into a message the user can act on.
String friendlyAuthError(Object error) {
  if (error is AppAuthCancelled) {
    return 'Google login cancel kora hoyeche.';
  }
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'email-already-in-use':
        return 'Ei email diye agei account khola ache. Login korun, ba onno email use korun.';
      case 'invalid-email':
        return 'Email address ta thik moto likhun.';
      case 'weak-password':
        return 'Password kompokkhe 6 character hote hobe.';
      case 'invalid-credential':
        return 'Email ba password vul. Abar check kore try korun.';
      case 'user-not-found':
        return 'Ei email e kono account pai nai. Age Register korun.';
      case 'wrong-password':
        return 'Password vul hoyeche.';
      case 'user-disabled':
        return 'Ei account ta disable kora ache.';
      case 'too-many-requests':
        return 'Onek bar vul try hoyeche. Kichukkhon pore abar try korun.';
      case 'network-request-failed':
        return 'Internet connection check korun, tarpor abar try korun.';
      case 'operation-not-allowed':
        return 'Firebase Console e ei sign-in method ta ON kora nai. FIREBASE-SETUP-v52.txt er Step 1 dekhun.';
      case 'account-exists-with-different-credential':
        return 'Ei email diye age onno vabe (email ba Google) account khola ache. Sei vabe login korun.';
    }
  }
  final text = error.toString();
  if (text.contains('ApiException: 10') || text.contains('sign_in_failed')) {
    return 'Google login setup incomplete: Firebase project e google-services.json + SHA-1 add korte hobe. FIREBASE-SETUP-v52.txt er Step 3 dekhun.';
  }
  if (text.contains('MissingPluginException')) {
    return 'Firebase Auth ei device e available na.';
  }
  return 'Kichu ekta vul hoyeche. Abar try korun.';
}
