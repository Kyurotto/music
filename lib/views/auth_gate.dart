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
      initialData: AuthService.instance.currentUser,
      builder: (context, snapshot) {
        if (!AuthService.instance.isInitialized && AuthService.instance.currentUser == null) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final user = snapshot.data ?? AuthService.instance.currentUser;
        return user != null ? const MusicDashboardView() : const AuthView();
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

  /// Authenticates using the official Google sign-in flow.
  Future<void> _handleGoogleSignIn() async {
    await _handleSocialSignIn(provider: 'google');
  }

  /// Authenticates using the official Facebook sign-in flow.
  Future<void> _handleFacebookSignIn() async {
    await _handleSocialSignIn(provider: 'facebook');
  }

  /// Handles Google or Facebook sign-in / sign-up through genuine provider authentication.
  Future<void> _handleSocialSignIn({required String provider}) async {
    if (_isBusy) return;

    setState(() => _isBusy = true);
    try {
      final success = provider == 'google'
          ? await AuthService.instance.signInWithGoogle(
              isCreatingNewAccount: _isRegistering,
            )
          : await AuthService.instance.signInWithFacebook(
              isCreatingNewAccount: _isRegistering,
            );
      if (!mounted || success) return;
    } on FirebaseAuthException catch (error) {
      _showError(_friendlyError(error));
    } catch (error) {
      _showError(
        'Could not sign in with ${provider == 'google' ? 'Google' : 'Facebook'}. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    // maybeOf: no crash when the Scaffold is already gone.
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(message)));
  }

  String _friendlyError(FirebaseAuthException error) {
    switch (error.code) {
      case 'email-already-in-use':
        return 'An account already uses that email address.';
      case 'account-exists-with-different-credential':
        return error.message ??
            'An account already exists with this email address using a different sign-in method.';
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'Incorrect email address or password.';
      case 'weak-password':
        return 'Use a password with at least 6 characters.';
      case 'invalid-email':
        return 'Enter a valid email address.';
      case 'login-cancelled':
        return 'Sign-in was cancelled.';
      case 'google-unavailable':
      case 'facebook-unavailable':
      case 'facebook-failed':
        return error.message ?? 'Social sign-in is unavailable. Please try again.';
      case 'configuration-not-found':
        return error.message ?? 'Authentication failed. Please verify your credentials and try again.';
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
                        decoration: const InputDecoration(
                          labelText: 'Display name',
                          hintText: 'Your name',
                        ),
                        validator: (value) => value == null || value.trim().length < 2 ? 'Enter your name.' : null,
                      ),
                      const SizedBox(height: 14),
                    ],
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email address',
                        hintText: 'name@example.com',
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
                    const SizedBox(height: 16),
                    const Row(children: [Expanded(child: Divider()), Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('OR')), Expanded(child: Divider())]),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _isBusy ? null : _handleGoogleSignIn,
                      icon: const Icon(Icons.g_mobiledata_rounded, size: 28),
                      label: const Text('Continue with Google'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _isBusy ? null : _handleFacebookSignIn,
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

