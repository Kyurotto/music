import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../theme/app_theme.dart';
import 'music_dashboard_view.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Object?>(
      stream: AuthService.instance.authChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && AuthService.instance.currentUser == null) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final hasUser = (snapshot.hasData && snapshot.data != null) || AuthService.instance.currentUser != null;
        return hasUser ? const MusicDashboardView() : const AuthView();
      },
    );
  }
}

class AuthView extends StatefulWidget {
  const AuthView({super.key});

  @override
  State<AuthView> createState() => _AuthViewState();
}

class _AuthViewState extends State<AuthView> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isRegistering = false;
  bool _isBusy = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isBusy = true);
    try {
      if (_isRegistering) {
        await AuthService.instance.register(
          name: _nameController.text,
          email: _emailController.text,
          password: _passwordController.text,
        );
      } else {
        await AuthService.instance.signInWithEmail(
          email: _emailController.text,
          password: _passwordController.text,
        );
      }
    } on FirebaseAuthException catch (error) {
      _showError(_friendlyError(error));
    } catch (error) {
      _showError(error.toString());
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _signInAsAdmin() async {
    setState(() => _isBusy = true);
    try {
      await AuthService.instance.signInAsAdmin();
    } catch (error) {
      _showError('Unable to sign in as admin: $error');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _socialSignIn(Future<void> Function() action) async {
    setState(() => _isBusy = true);
    try {
      await action();
    } on FirebaseAuthException catch (error) {
      _showError(_friendlyError(error));
    } catch (_) {
      _showError('Sign-in was cancelled or is not configured yet.');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void _showError(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _friendlyError(FirebaseAuthException error) {
    switch (error.code) {
      case 'email-already-in-use':
        return 'An account already uses that email address.';
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'Incorrect email address or password.';
      case 'weak-password':
        return 'Use a password with at least 6 characters.';
      case 'invalid-email':
        return 'Enter a valid email address.';
      case 'configuration-not-found':
        return error.message ?? 'Firebase Auth is not configured. Tap "Continue as Admin" to proceed.';
      default:
        return error.message ?? 'Authentication failed. Please try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppTheme.border),
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.graphic_eq_rounded, size: 52, color: AppTheme.primary),
                    const SizedBox(height: 16),
                    Text(
                      _isRegistering ? 'Create your account' : 'Welcome back',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _isRegistering ? 'Save playlists and listen anywhere.' : 'Sign in to continue to Pulse Music.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 24),
                    if (_isRegistering) ...[
                      TextFormField(
                        controller: _nameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(labelText: 'Display name'),
                        validator: (value) => value == null || value.trim().length < 2 ? 'Enter your name.' : null,
                      ),
                      const SizedBox(height: 14),
                    ],
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email address',
                        hintText: 'admin@pulsemusic.app',
                      ),
                      validator: (value) => value != null && value.contains('@') ? null : 'Enter a valid email address.',
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Password'),
                      validator: (value) => value != null && value.length >= 6 ? null : 'Use at least 6 characters.',
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _isBusy ? null : _submit,
                      child: Text(_isRegistering ? 'Create account' : 'Sign in'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _isBusy ? null : _signInAsAdmin,
                      icon: const Icon(Icons.shield_rounded, color: AppTheme.primary),
                      label: const Text('Continue as Admin'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primary,
                        side: const BorderSide(color: AppTheme.primary),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Row(children: [Expanded(child: Divider()), Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('OR')), Expanded(child: Divider())]),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _isBusy ? null : () => _socialSignIn(AuthService.instance.signInWithGoogle),
                      icon: const Icon(Icons.g_mobiledata_rounded),
                      label: const Text('Continue with Google'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _isBusy ? null : () => _socialSignIn(AuthService.instance.signInWithFacebook),
                      icon: const Icon(Icons.facebook_rounded),
                      label: const Text('Continue with Facebook'),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _isBusy ? null : () => setState(() => _isRegistering = !_isRegistering),
                      child: Text(_isRegistering ? 'Already have an account? Sign in' : 'New to Pulse Music? Create an account'),
                    ),
                    if (_isBusy) const Padding(padding: EdgeInsets.only(top: 8), child: Center(child: CircularProgressIndicator())),
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
