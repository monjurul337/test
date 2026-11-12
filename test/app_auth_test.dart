// App login gate (v52): the pure helpers and the gate widget are
// tested here with a fake auth service. Real Firebase (channels,
// the phone's Google account) cannot run in a widget test.
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gemini_hd_studio/app_auth.dart';
import 'package:gemini_hd_studio/login_gate.dart';

class FakeAppAuth implements AppAuth {
  final _controller = StreamController<AppUser?>.broadcast();
  AppUser? _user;

  void emit(AppUser? user) {
    _user = user;
    _controller.add(user);
  }

  @override
  Stream<AppUser?> get authStateChanges => _controller.stream;

  @override
  AppUser? get currentUser => _user;

  @override
  Future<AppUser> signInWithEmail(
          {required String email, required String password}) =>
      throw UnimplementedError();

  @override
  Future<AppUser> registerWithEmail(
          {required String name,
          required String email,
          required String password}) =>
      throw UnimplementedError();

  @override
  Future<AppUser> signInWithGoogle() => throw UnimplementedError();

  @override
  Future<void> sendPasswordReset(String email) =>
      throw UnimplementedError();

  @override
  Future<void> signOut() async {
    emit(null);
  }

  @override
  Future<String?> getIdToken() async => 'fake-id-token';
}

void main() {
  test('isValidEmail accepts real addresses and rejects junk', () {
    expect(isValidEmail('a@b.com'), isTrue);
    expect(isValidEmail('monjurul.islam+1@example.co.uk'), isTrue);
    expect(isValidEmail('plainaddress'), isFalse);
    expect(isValidEmail('a@b'), isFalse);
    expect(isValidEmail('@b.com'), isFalse);
    expect(isValidEmail('a @b.com'), isFalse);
    expect(isValidEmail(''), isFalse);
  });

  test('shouldEnforceGate is Android-only and needs Firebase ready', () {
    expect(
        shouldEnforceGate(isAndroid: true, firebaseReady: true), isTrue);
    expect(
        shouldEnforceGate(isAndroid: true, firebaseReady: false),
        isFalse);
    expect(
        shouldEnforceGate(isAndroid: false, firebaseReady: true),
        isFalse);
    expect(
        shouldEnforceGate(isAndroid: false, firebaseReady: false),
        isFalse);
  });

  test('friendlyAuthError explains common codes in plain language', () {
    expect(
        friendlyAuthError(
            FirebaseAuthException(code: 'email-already-in-use')),
        contains('agei account'));
    expect(
        friendlyAuthError(FirebaseAuthException(code: 'weak-password')),
        contains('6 character'));
    expect(
        friendlyAuthError(
            FirebaseAuthException(code: 'invalid-credential')),
        contains('vul'));
    expect(
        friendlyAuthError(
            FirebaseAuthException(code: 'operation-not-allowed')),
        contains('FIREBASE-SETUP-v52'));
    expect(friendlyAuthError(const AppAuthCancelled()),
        contains('cancel'));
    expect(
        friendlyAuthError(Exception('ApiException: 10')),
        contains('google-services.json'));
  });

  testWidgets('AuthGate without auth opens the app directly (Windows)',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AuthGate(auth: null, child: Text('inside the app')),
      ),
    );
    expect(find.text('inside the app'), findsOneWidget);
    expect(find.text('Welcome back'), findsNothing);
  });

  testWidgets('AuthGate shows the app once the fake user signs in',
      (tester) async {
    final fake = FakeAppAuth();
    await tester.pumpWidget(
      MaterialApp(
        home: AuthGate(auth: fake, child: const Text('inside the app')),
      ),
    );
    fake.emit(const AppUser(uid: 'u1', email: 'a@b.com'));
    await tester.pump();
    expect(find.text('inside the app'), findsOneWidget);
  });

  testWidgets('AuthGate shows the login screen when signed out',
      (tester) async {
    final fake = FakeAppAuth();
    await tester.pumpWidget(
      MaterialApp(
        home: AuthGate(auth: fake, child: const Text('inside the app')),
      ),
    );
    fake.emit(null);
    await tester.pump();
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('inside the app'), findsNothing);
  });

  testWidgets('Login screen shows the real Zedge Studio logo (v54)',
      (tester) async {
    final fake = FakeAppAuth();
    await tester.pumpWidget(
      MaterialApp(home: LoginGateScreen(auth: fake)),
    );
    expect(
      find.byWidgetPredicate((w) =>
          w is Image &&
          w.image is AssetImage &&
          (w.image as AssetImage).assetName == 'assets/logo.png'),
      findsOneWidget,
    );
  });

  testWidgets('Login screen switches to Register and shows the name field',
      (tester) async {
    final fake = FakeAppAuth();
    await tester.pumpWidget(
      MaterialApp(home: LoginGateScreen(auth: fake)),
    );
    expect(find.text('Full name'), findsNothing);
    await tester.tap(find.text('Register'));
    await tester.pump();
    expect(find.text('Full name'), findsOneWidget);
    expect(find.text('Confirm password'), findsOneWidget);
    await tester.tap(find.text('Login'));
    await tester.pump();
    expect(find.text('Full name'), findsNothing);
  });
}
