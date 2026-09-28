import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../auth/email_config.dart';
import '../auth/otp_service.dart';
import '../theme/app_theme.dart';
import '../widgets/otp_verification_dialog.dart';
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
  final _phoneController = TextEditingController(text: '+63 ');
  final _passwordController = TextEditingController();
  String _otpMethod = 'email'; // 'email' or 'sms'
  bool _isRegistering = false;
  bool _isBusy = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();
    final name = _nameController.text.trim();
    final password = _passwordController.text;

    if (_isRegistering) {
      if (_otpMethod == 'email') {
        // Send 6-digit Email OTP to user's chosen email
        if (!EmailConfig.isConfigured) {
          await EmailConfig.loadSavedCredentials();
          if (!mounted) return;
          if (!EmailConfig.isConfigured) {
            final configured = await _showGmailSetupSheet(email);
            if (!configured || !EmailConfig.isConfigured) return;
          }
        }

        setState(() => _isBusy = true);
        final otpResult = await OtpService.instance.sendEmailOtp(email: email);
        setState(() => _isBusy = false);

        if (!otpResult.success) {
          _showError(otpResult.message);
          return;
        }

        if (!mounted) return;
        final verified = await OtpVerificationDialog.show(
          context: context,
          title: 'Verify Email OTP',
          destination: email,
          type: 'email',
          onVerify: (code) =>
              OtpService.instance.verifyEmailOtp(email: email, code: code),
          onResend: () async {
            await OtpService.instance.sendEmailOtp(email: email);
          },
          onSwitchMethod: () {
            setState(() => _otpMethod = 'sms');
          },
          switchMethodLabel: 'Send code via SMS instead',
        );

        if (verified != true) return;

        setState(() => _isBusy = true);
        try {
          await AuthService.instance.register(
            name: name,
            email: email,
            phoneNumber: phone.length > 5 ? phone : null,
            password: password,
          );
        } on FirebaseAuthException catch (error) {
          _showError(_friendlyError(error));
        } catch (error) {
          _showError(error.toString());
        } finally {
          if (mounted) setState(() => _isBusy = false);
        }
      } else {
        // Send 6-digit SMS OTP to user's chosen phone number
        setState(() => _isBusy = true);
        String? verificationId;
        String? sendError;

        final completer = Completer<bool>();
        await OtpService.instance.sendSmsOtp(
          phoneNumber: phone,
          onCodeSent: (vId, _) {
            verificationId = vId;
            if (!completer.isCompleted) completer.complete(true);
          },
          onError: (err) {
            sendError = err;
            if (!completer.isCompleted) completer.complete(false);
          },
        );

        final sent = await completer.future.timeout(
          const Duration(seconds: 15),
          onTimeout: () => false,
        );
        if (!mounted) return;
        setState(() => _isBusy = false);

        if (!sent || verificationId == null) {
          _showError(sendError ?? 'Could not send SMS verification code.');
          return;
        }

        final verified = await OtpVerificationDialog.show(
          context: context,
          title: 'Verify SMS OTP',
          destination: phone,
          type: 'sms',
          onVerify: (smsCode) async {
            return await OtpService.instance.verifySmsOtp(
              verificationId: verificationId!,
              smsCode: smsCode,
              phoneNumber: phone,
              displayName: name,
              autoSignIn: false,
            );
          },
          onResend: () async {
            final resendCompleter = Completer<void>();
            await OtpService.instance.sendSmsOtp(
              phoneNumber: phone,
              onCodeSent: (newVId, _) {
                verificationId = newVId;
                if (!resendCompleter.isCompleted) resendCompleter.complete();
              },
              onError: (err) {
                if (!resendCompleter.isCompleted) resendCompleter.complete();
              },
            );
            await resendCompleter.future.timeout(
              const Duration(seconds: 15),
              onTimeout: () {},
            );
          },
          onSwitchMethod: () {
            setState(() => _otpMethod = 'email');
          },
          switchMethodLabel: 'Send code via Email instead',
        );

        if (verified != true) return;

        setState(() => _isBusy = true);
        try {
          await AuthService.instance.registerWithPhone(
            name: name,
            phoneNumber: phone,
            email: email.isNotEmpty ? email : null,
            password: password,
          );
        } on FirebaseAuthException catch (error) {
          _showError(_friendlyError(error));
        } catch (error) {
          _showError(error.toString());
        } finally {
          if (mounted) setState(() => _isBusy = false);
        }
      }
    } else {
      setState(() => _isBusy = true);
      try {
        await AuthService.instance.signInWithEmail(
          email: email,
          password: password,
        );
      } on FirebaseAuthException catch (error) {
        _showError(_friendlyError(error));
      } catch (error) {
        _showError(error.toString());
      } finally {
        if (mounted) setState(() => _isBusy = false);
      }
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
  /// In both modes, OTP verification happens before proceeding.
  /// Sign-in mode: verifies then signs in. Create-account mode: verifies then creates.
  Future<void> _handleSocialSignIn({required String provider}) async {
    if (_isBusy) return;

    // 1. If user typed an email in the field, use that account directly!
    final enteredEmail = _emailController.text.trim().toLowerCase();
    final enteredName = _nameController.text.trim();
    if (enteredEmail.isNotEmpty && enteredEmail.contains('@')) {
      if (_isRegistering) {
        final created = await _verifyOtpAndCreateAccount(
          email: enteredEmail,
          name: enteredName.isNotEmpty
              ? enteredName
              : enteredEmail.split('@').first,
          provider: provider,
        );
        if (!created) return;
        return;
      }
      final signedIn = await _verifyOtpAndSignIn(
        email: enteredEmail,
        name: enteredName.isNotEmpty
            ? enteredName
            : enteredEmail.split('@').first,
        provider: provider,
      );
      if (!signedIn) return;
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

    if (_isRegistering) {
      final created = await _verifyOtpAndCreateAccount(
        email: details.email,
        name: details.name,
        provider: provider,
      );
      if (!created) return;
      return;
    }

    final signedIn = await _verifyOtpAndSignIn(
      email: details.email,
      name: details.name,
      provider: provider,
    );
    if (!signedIn) return;
  }

  /// Sign-in mode: verifies the 6-digit code sent to the account's email,
  /// then signs in with the Google/Facebook profile.
  Future<bool> _verifyOtpAndSignIn({
    required String email,
    required String name,
    required String provider,
  }) async {
    return await _runEmailOtpFlow(
      email: email,
      name: name,
      provider: provider,
      isCreatingAccount: false,
    );
  }

  /// In create-account mode: verifies the 6-digit code sent to the account's email,
  /// then creates/signs in the account with the Google/Facebook profile.
  Future<bool> _verifyOtpAndCreateAccount({
    required String email,
    required String name,
    required String provider,
  }) async {
    return await _runEmailOtpFlow(
      email: email,
      name: name,
      provider: provider,
      isCreatingAccount: true,
    );
  }

  /// Sends a 6-digit OTP code to the Gmail/email address and verifies it.
  Future<bool> _runEmailOtpFlow({
    required String email,
    required String name,
    required String provider,
    required bool isCreatingAccount,
  }) async {
    if (!EmailConfig.isConfigured) {
      await EmailConfig.loadSavedCredentials();
      if (!mounted) return false;
      if (!EmailConfig.isConfigured) {
        final configured = await _showGmailSetupSheet(email);
        if (!configured || !EmailConfig.isConfigured) return false;
      }
    }

    setState(() => _isBusy = true);
    final otpResult = await OtpService.instance.sendEmailOtp(email: email);
    if (!mounted) return false;
    setState(() => _isBusy = false);

    if (!otpResult.success) {
      _showError(otpResult.message);
      return false;
    }

    final providerLabel = provider == 'google'
        ? 'Google'
        : (provider == 'facebook' ? 'Facebook' : 'Account');
    final verified = await OtpVerificationDialog.show(
      context: context,
      title: 'Verify $providerLabel OTP',
      destination: email,
      type: 'email',
      onVerify: (code) =>
          OtpService.instance.verifyEmailOtp(email: email, code: code),
      onResend: () async {
        await OtpService.instance.sendEmailOtp(email: email);
      },
    );

    if (verified != true) return false;

    setState(() => _isBusy = true);
    try {
      await AuthService.instance.signInWithRealProfile(
        email: email,
        displayName: name,
        provider: provider,
      );
      return true;
    } on FirebaseAuthException catch (error) {
      _showError(_friendlyError(error));
      return false;
    } catch (error) {
      _showError(error.toString());
      return false;
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

  Future<bool> _showGmailSetupSheet(String targetEmail) async {
    if (!mounted) return false;
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => _GmailSetupSheet(targetEmail: targetEmail),
    );
    return result ?? false;
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
                      const SizedBox(height: 16),
                      const SizedBox(height: 14),
                    ],
                    if (_isRegistering && _otpMethod == 'sms') ...[
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Phone number (receives 6-digit SMS)',
                          hintText: '+63 912 345 6789',
                          prefixIcon: Icon(Icons.phone_rounded, color: AppTheme.textSecondary),
                        ),
                        validator: (value) {
                          final clean = (value ?? '').trim().replaceAll(' ', '');
                          if (clean.length < 8) return 'Enter a valid phone number with country code.';
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Email address (optional)',
                          hintText: 'name@example.com',
                          prefixIcon: Icon(Icons.email_outlined, color: AppTheme.textSecondary),
                        ),
                      ),
                    ] else ...[
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: _isRegistering
                              ? 'Email address'
                              : 'Email address',
                          hintText: 'name@example.com',
                          prefixIcon: const Icon(Icons.email_outlined, color: AppTheme.textSecondary),
                        ),
                        validator: (value) =>
                            value != null && value.contains('@') ? null : 'Enter a valid email address.',
                      ),
                    ],
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
                    const SizedBox(height: 14),
                    const Row(children: [Expanded(child: Divider()), Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('OR')), Expanded(child: Divider())]),
                    const SizedBox(height: 14),
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


class _GmailSetupSheet extends StatefulWidget {
  final String targetEmail;

  const _GmailSetupSheet({required this.targetEmail});

  @override
  State<_GmailSetupSheet> createState() => _GmailSetupSheetState();
}

class _GmailSetupSheetState extends State<_GmailSetupSheet> {
  final _senderController =
      TextEditingController(text: EmailConfig.senderEmail);
  final _passwordController =
      TextEditingController(text: EmailConfig.cleanAppPassword);
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _senderController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final sender = _senderController.text.trim();
    final pass = _passwordController.text.trim();
    await EmailConfig.saveCredentials(sender: sender, password: pass);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 20,
        bottom: bottomInset > 0 ? bottomInset + 20 : 32,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.mark_email_read_rounded,
                    color: AppTheme.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Connect Gmail for OTP',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'One-time setup to deliver real OTP emails',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Enter your 16-character Google App Password so Pulse Music can send real verification codes to ${widget.targetEmail}:',
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _senderController,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Sender Gmail Address',
                hintText: 'yourname@gmail.com',
                prefixIcon: Icon(Icons.email_outlined, color: AppTheme.textSecondary),
              ),
              validator: (val) {
                final clean = (val ?? '').trim();
                if (clean.isEmpty || !clean.contains('@')) {
                  return 'Enter a valid Gmail address.';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontFamily: 'monospace',
                letterSpacing: 2,
              ),
              decoration: InputDecoration(
                labelText: '16-Character App Password',
                hintText: 'xxxx xxxx xxxx xxxx',
                prefixIcon: const Icon(Icons.key_rounded, color: AppTheme.textSecondary),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                    color: AppTheme.textSecondary,
                  ),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: (val) {
                final clean = (val ?? '').replaceAll(' ', '').trim();
                if (clean.length < 16) {
                  return 'Enter your 16-character Google App Password.';
                }
                return null;
              },
            ),
            const SizedBox(height: 8),
            const Text(
              'To generate: myaccount.google.com -> Security -> 2-Step Verification -> App Passwords',
              style: TextStyle(
                fontSize: 11,
                color: AppTheme.textMuted,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.send_rounded, size: 18),
              label: const Text('Save & Send OTP Code'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


