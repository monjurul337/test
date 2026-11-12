// App login gate (v52): the user must log in with Firebase
// (r-final project) before using Zedge Studio on Android.
//
// Flow: AuthGate watches AppAuth.authStateChanges — signed in,
// the app (HomeScreen) shows; signed out, LoginGateScreen shows.
// Firebase Auth keeps the session, so login is once per install
// unless the user logs out. The Gemini login in the Login tab is
// untouched: image generation still needs the Gemini Google
// session cookies, and the gate screen says so.
import 'package:flutter/material.dart';

import 'app_auth.dart';

/// Wraps the app: shows [child] only when signed in (Android).
/// When [auth] is null (Firebase not available on this platform —
/// Windows has no Firebase Auth plugin) the app opens directly.
class AuthGate extends StatelessWidget {
  final AppAuth? auth;
  final Widget child;
  const AuthGate({super.key, required this.auth, required this.child});

  @override
  Widget build(BuildContext context) {
    final a = auth;
    if (a == null) return child;
    return StreamBuilder<AppUser?>(
      stream: a.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Zedge Studio'),
                ],
              ),
            ),
          );
        }
        if (snapshot.data != null) return child;
        return LoginGateScreen(auth: a);
      },
    );
  }
}

/// Shown when Firebase could not start on Android (bad config,
/// no network on first run). Retry re-attempts init; without a
/// working Firebase the gate cannot let anyone in, so there is
/// deliberately no bypass button here.
class FirebaseSetupErrorScreen extends StatelessWidget {
  final VoidCallback onRetry;
  const FirebaseSetupErrorScreen({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined, size: 48, color: scheme.error),
              const SizedBox(height: 16),
              const Text(
                'Login service start hoy nai',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Firebase connect korte pari nai. Internet check kore '
                'Retry tap korun. Na hole FIREBASE-SETUP-v52.txt er '
                'step gula check korun.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Login / Register / Google screen for the gate.
class LoginGateScreen extends StatefulWidget {
  final AppAuth auth;
  const LoginGateScreen({super.key, required this.auth});

  @override
  State<LoginGateScreen> createState() => _LoginGateScreenState();
}

class _LoginGateScreenState extends State<LoginGateScreen> {
  bool _register = false;
  bool _busy = false;
  bool _showPassword = false;
  String? _message;
  bool _messageIsError = false;

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _setMessage(String text, {required bool isError}) {
    setState(() {
      _message = text;
      _messageIsError = isError;
    });
  }

  void _setMode(bool register) {
    setState(() {
      _register = register;
      _message = null;
    });
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (!isValidEmail(email)) {
      _setMessage('Email address ta thik moto likhun.', isError: true);
      return;
    }
    if (password.length < 6) {
      _setMessage('Password kompokkhe 6 character hote hobe.',
          isError: true);
      return;
    }
    if (_register) {
      if (_nameCtrl.text.trim().length < 2) {
        _setMessage('Apnar naam ta likhun.', isError: true);
        return;
      }
      if (password != _confirmCtrl.text) {
        _setMessage('Confirm password milche na.', isError: true);
        return;
      }
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (_register) {
        await widget.auth.registerWithEmail(
          name: _nameCtrl.text.trim(),
          email: email,
          password: password,
        );
      } else {
        await widget.auth.signInWithEmail(email: email, password: password);
      }
      // Signed in: AuthGate's stream flips and opens the app.
    } catch (e) {
      _setMessage(friendlyAuthError(e), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _google() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.auth.signInWithGoogle();
    } catch (e) {
      _setMessage(friendlyAuthError(e), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgot() async {
    final email = _emailCtrl.text.trim();
    if (!isValidEmail(email)) {
      _setMessage(
          'Forgot password er jonno age email field e apnar email ta likhun.',
          isError: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.auth.sendPasswordReset(email);
      _setMessage(
          'Password reset link $email e pathano hoyeche. Inbox (ar Spam folder) check korun.',
          isError: false);
    } catch (e) {
      _setMessage(friendlyAuthError(e), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // v54: the real Zedge Studio logo (assets/logo.png,
                    // the v41 artwork — full white canvas, no crop or
                    // zoom, colours untouched), in a white tile like
                    // the dashboard header. BoxFit.contain so the
                    // artwork can never be cut.
                    const _LoginLogo(),
                    const SizedBox(height: 16),
                    Text(
                      _register ? 'Create account' : 'Welcome back',
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _register
                          ? 'Notun account khulun — 1 minute lagbe'
                          : 'Login kore Zedge Studio chalao',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: _ModeButton(
                            label: 'Login',
                            selected: !_register,
                            onTap: _busy ? null : () => _setMode(false),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _ModeButton(
                            label: 'Register',
                            selected: _register,
                            onTap: _busy ? null : () => _setMode(true),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_register)
                      TextField(
                        controller: _nameCtrl,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Full name',
                          hintText: 'Apnar naam',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    if (_register) const SizedBox(height: 12),
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        hintText: 'you@example.com',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordCtrl,
                      obscureText: !_showPassword,
                      textInputAction:
                          _register ? TextInputAction.next : TextInputAction.done,
                      onSubmitted: (_) => _busy ? null : _submit(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        hintText: 'Minimum 6 characters',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: _showPassword ? 'Hide' : 'Show',
                          icon: Icon(_showPassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined),
                          onPressed: () => setState(
                              () => _showPassword = !_showPassword),
                        ),
                      ),
                    ),
                    if (_register) const SizedBox(height: 12),
                    if (_register)
                      TextField(
                        controller: _confirmCtrl,
                        obscureText: !_showPassword,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _busy ? null : _submit(),
                        decoration: const InputDecoration(
                          labelText: 'Confirm password',
                          hintText: 'Password abar likhun',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _busy ? null : _forgot,
                        child: const Text('Forgot password?'),
                      ),
                    ),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2),
                            )
                          : Text(_register ? 'Register' : 'Login'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text('or',
                              style: TextStyle(
                                  color: scheme.onSurfaceVariant)),
                        ),
                        const Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _busy ? null : _google,
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('G',
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF4285F4))),
                          SizedBox(width: 10),
                          Text('Continue with Google'),
                        ],
                      ),
                    ),
                    if (_message != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _messageIsError
                              ? scheme.errorContainer
                              : scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _message!,
                          style: TextStyle(
                            color: _messageIsError
                                ? scheme.onErrorContainer
                                : scheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      'Ei login ta Zedge Studio account er jonno. Image '
                      'generate korte Login tab e Gemini teo sign in korte hobe.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The real Zedge Studio logo on the login screen (v54).
/// White tile, same treatment as the dashboard header tile.
/// If the asset ever fails to load, the old gradient 'Z' shows
/// instead of a broken image — the login screen never breaks.
class _LoginLogo extends StatelessWidget {
  const _LoginLogo();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.center,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white24),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(17),
          child: Image.asset(
            'assets/logo.png',
            width: 96,
            height: 96,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => Container(
              width: 96,
              height: 96,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [scheme.primary, scheme.secondary],
                ),
              ),
              child: Text(
                'Z',
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w800,
                  color: scheme.onPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  const _ModeButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor:
            selected ? scheme.primary : scheme.surfaceContainerHighest,
        foregroundColor:
            selected ? scheme.onPrimary : scheme.onSurface,
      ),
      onPressed: onTap,
      child: Text(label),
    );
  }
}
