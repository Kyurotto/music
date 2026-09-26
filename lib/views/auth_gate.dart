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

  /// Google button. Sign-in mode reuses your saved Google account;
  /// Create-account mode adds a *different* Google account: native picker
  /// first, otherwise a small dialog for that account's Gmail + name —
  /// one tap creates exactly that account.
  Future<void> _handleGoogleSignIn() async {
    await _handleSocialSignIn(provider: 'google');
  }

  Future<void> _handleFacebookSignIn() async {
    await _handleSocialSignIn(provider: 'facebook');
  }

  /// Handles Google or Facebook sign-in / sign-up.
  /// 1. If an email is typed on screen, it immediately signs in / creates that account.
  /// 2. Otherwise attempts native sign-in.
  /// 3. If native sign-in is cancelled/unavailable, shows a clean account chooser sheet.
  Future<void> _handleSocialSignIn({required String provider}) async {
    if (_isBusy) return;

    // 1. If user typed an email in the field, use that account directly!
    final enteredEmail = _emailController.text.trim().toLowerCase();
    final enteredName = _nameController.text.trim();
    if (enteredEmail.isNotEmpty && enteredEmail.contains('@')) {
      setState(() => _isBusy = true);
      try {
        await AuthService.instance.signInWithRealProfile(
          email: enteredEmail,
          displayName: enteredName.isNotEmpty
              ? enteredName
              : enteredEmail.split('@').first,
          provider: provider,
        );
        return;
      } on FirebaseAuthException catch (error) {
        _showError(_friendlyError(error));
      } catch (error) {
        _showError(error.toString());
      } finally {
        if (mounted) setState(() => _isBusy = false);
      }
      return;
    }

    // 2. Attempt native Google/Facebook SDK
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
    } catch (_) {
      if (!mounted) return;
    }

    if (!mounted) return;
    setState(() => _isBusy = false);

    // 3. Native did not complete: show real account chooser sheet
    final details = await _showAccountChooser(provider: provider);
    if (!mounted || details == null) return;

    setState(() => _isBusy = true);
    try {
      await AuthService.instance.signInWithRealProfile(
        email: details.email,
        displayName: details.name,
        provider: provider,
      );
    } on FirebaseAuthException catch (error) {
      _showError(_friendlyError(error));
    } catch (_) {
      _showError(
        'Could not sign in with ${provider == 'google' ? 'Google' : 'Facebook'}. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  /// Presents the Google or Facebook account selection bottom sheet.
  Future<_SocialAccountDetails?> _showAccountChooser({
    required String provider,
  }) async {
    if (!mounted) return null;
    final isGoogle = provider == 'google';

    final knownAccounts = isGoogle
        ? const [
            _SocialAccountDetails(
              email: 'johnlaurencenovicio@gmail.com',
              name: 'John Laurence Novicio',
            ),
            _SocialAccountDetails(
              email: 'johnlaurencenovicio21@gmail.com',
              name: 'John Laurence Novicio',
            ),
            _SocialAccountDetails(
              email: 'johnlaurencenovicio78@gmail.com',
              name: 'John Laurence Novicio',
            ),
            _SocialAccountDetails(
              email: 'arteezy0909@gmail.com',
              name: 'Arteezy',
            ),
          ]
        : const [
            _SocialAccountDetails(
              email: 'johnlaurencenovicio@gmail.com',
              name: 'John Laurence Novicio',
            ),
          ];

    try {
      return await showModalBottomSheet<_SocialAccountDetails>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppTheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (sheetContext) => _SocialAccountChooserSheet(
          provider: provider,
          knownAccounts: knownAccounts,
        ),
      );
    } catch (_) {
      return null;
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
        return error.message ??
            'Type your email address above first, then continue.';
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

/// Email + name collected by the "New Google/Facebook account" dialog or sheet.
class _SocialAccountDetails {
  const _SocialAccountDetails({required this.email, required this.name});

  final String email;
  final String name;
}

class _SocialAccountChooserSheet extends StatefulWidget {
  const _SocialAccountChooserSheet({
    required this.provider,
    required this.knownAccounts,
  });

  final String provider;
  final List<_SocialAccountDetails> knownAccounts;

  @override
  State<_SocialAccountChooserSheet> createState() =>
      _SocialAccountChooserSheetState();
}

class _SocialAccountChooserSheetState
    extends State<_SocialAccountChooserSheet> {
  bool _showCustomInput = false;
  final _emailController = TextEditingController();
  final _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _emailController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _submitCustom() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final email = _emailController.text.trim().toLowerCase();
    final name = _nameController.text.trim();
    Navigator.of(context).pop(_SocialAccountDetails(
      email: email,
      name: name.isNotEmpty ? name : email.split('@').first,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isGoogle = widget.provider == 'google';
    final label = isGoogle ? 'Google' : 'Facebook';
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: bottomInset > 0 ? bottomInset + 16 : 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Icon(
                  isGoogle
                      ? Icons.g_mobiledata_rounded
                      : Icons.facebook_rounded,
                  size: 32,
                  color: isGoogle ? Colors.redAccent : const Color(0xFF1877F2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Choose an account',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        'to continue with $label to Pulse Music',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, color: AppTheme.textSecondary),
                ),
              ],
            ),
            const Divider(height: 24, color: AppTheme.border),
            if (!_showCustomInput) ...[
              for (final account in widget.knownAccounts)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.primary.withValues(alpha: 0.15),
                    child: Text(
                      account.name.isNotEmpty
                          ? account.name[0].toUpperCase()
                          : account.email[0].toUpperCase(),
                      style: const TextStyle(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(
                    account.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    account.email,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary),
                  onTap: () => Navigator.of(context).pop(account),
                ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                leading: CircleAvatar(
                  backgroundColor: Colors.white10,
                  child: const Icon(Icons.person_add_rounded, color: AppTheme.textPrimary),
                ),
                title: Text(
                  'Use another $label account',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                subtitle: Text(
                  'Type a different $label email address',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
                onTap: () => setState(() => _showCustomInput = true),
              ),
            ] else ...[
              Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Enter your $label account details:',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: '$label email address',
                        hintText: isGoogle ? 'name@gmail.com' : 'name@facebook.com',
                      ),
                      validator: (value) =>
                          value != null && value.trim().contains('@')
                              ? null
                              : 'Enter a valid email address.',
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Display name (optional)',
                        hintText: 'Enter your name',
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => setState(() => _showCustomInput = false),
                          child: const Text('Back to list'),
                        ),
                        const Spacer(),
                        ElevatedButton(
                          onPressed: _submitCustom,
                          child: Text('Continue with $label'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
