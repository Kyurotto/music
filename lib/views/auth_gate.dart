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
        if (!AuthService.instance.isInitialized &&
            AuthService.instance.currentUser == null) {
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
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isRegistering = false;
  bool _isBusy = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _toggleMode(bool isRegistering) {
    if (_isRegistering == isRegistering) return;
    setState(() {
      _isRegistering = isRegistering;
      _formKey.currentState?.reset();
      _confirmPasswordController.clear();
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isRegistering && _passwordController.text != _confirmPasswordController.text) {
      _showError('Passwords do not match.');
      return;
    }
    setState(() => _isBusy = true);
    try {
      if (_isRegistering) {
        await AuthService.instance.register(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      } else {
        await AuthService.instance.signInWithEmail(
          email: _emailController.text.trim(),
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

  void _showError(String message) {
    if (!mounted) return;
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
      case 'popup-closed-by-user':
      case 'cancelled-popup-request':
        return 'Sign-in was cancelled.';
      case 'operation-not-allowed':
        return 'Authentication failed. Please verify your credentials and try again.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      case 'app-not-authorized':
      case 'unauthorized-domain':
        return 'This app or domain is not authorized for social login. Check your Facebook and Firebase settings.';
      case 'configuration-not-found':
        return error.message ??
            'Authentication failed. Please verify your credentials and try again.';
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
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.graphic_eq_rounded,
                        size: 52, color: AppTheme.primary),
                    const SizedBox(height: 16),
                    Text(
                      _isRegistering ? 'Create account' : 'Welcome back',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _isRegistering
                          ? 'Enter your email and choose a password to get started.'
                          : 'Sign in to continue to Pulse Music.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 24),

                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Email address',
                        hintText: 'name@example.com',
                        prefixIcon: Icon(Icons.email_outlined, size: 20),
                      ),
                      validator: (value) {
                        final v = value?.trim() ?? '';
                        if (v.isEmpty) return 'Enter an email address.';
                        if (!v.contains('@') || !v.contains('.')) {
                          return 'Enter a valid email address.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      textInputAction: _isRegistering ? TextInputAction.next : TextInputAction.done,
                      onFieldSubmitted: _isRegistering ? null : (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline, size: 20),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            size: 20,
                            color: AppTheme.textSecondary,
                          ),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      validator: (value) => value != null && value.length >= 6
                          ? null
                          : 'Use at least 6 characters.',
                    ),
                    if (_isRegistering) ...[
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _confirmPasswordController,
                        obscureText: _obscureConfirmPassword,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: 'Confirm password',
                          prefixIcon: const Icon(Icons.lock_reset_outlined, size: 20),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureConfirmPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                              size: 20,
                              color: AppTheme.textSecondary,
                            ),
                            onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                          ),
                        ),
                        validator: (value) {
                          if (!_isRegistering) return null;
                          if (value == null || value.isEmpty) {
                            return 'Please confirm your password.';
                          }
                          if (value != _passwordController.text) {
                            return 'Passwords do not match.';
                          }
                          return null;
                        },
                      ),
                    ],
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _isBusy ? null : _submit,
                      child: Text(_isRegistering ? 'Create account' : 'Sign in'),
                    ),
                    if (_isBusy)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    const SizedBox(height: 16),
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          _isRegistering ? 'Already have an account? ' : "Don't have an account? ",
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        TextButton(
                          onPressed: _isBusy ? null : () => _toggleMode(!_isRegistering),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            _isRegistering ? 'Sign in' : 'Create account',
                            style: const TextStyle(
                              color: AppTheme.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text.rich(
                      TextSpan(
                        text: 'By continuing, you agree to Pulse Music\'s ',
                        children: [
                          TextSpan(
                            text: 'Terms of Service',
                            style: const TextStyle(
                              color: AppTheme.primary,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                          const TextSpan(text: ' and '),
                          TextSpan(
                            text: 'Privacy Policy',
                            style: const TextStyle(
                              color: AppTheme.primary,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                          const TextSpan(text: '.'),
                        ],
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                        height: 1.5,
                      ),
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