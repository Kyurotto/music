import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../data/local_database.dart';
import '../theme/app_theme.dart';

/// Shows the signed-in account and accounts remembered on this device.
///
/// Choosing another account signs out and returns to the sign-in screen with
/// that email prefilled — no password is ever stored.
class AccountsView extends StatefulWidget {
  const AccountsView({super.key});

  static Route<void> route() {
    return MaterialPageRoute<void>(builder: (_) => const AccountsView());
  }

  @override
  State<AccountsView> createState() => _AccountsViewState();
}

class _AccountsViewState extends State<AccountsView> {
  List<Map<String, Object?>> _remembered = const [];
  bool _loading = true;
  bool _switching = false;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    final accounts = await LocalDatabase.instance.getRememberedAccounts();
    if (!mounted) return;
    setState(() {
      _remembered = accounts;
      _loading = false;
    });
  }

  Future<void> _switchTo(String email) async {
    if (_switching) return;
    final clean = email.trim().toLowerCase();
    if (clean.isEmpty) return;
    setState(() => _switching = true);
    try {
      await LocalDatabase.instance.saveSetting(
        AuthService.authPrefillEmailKey,
        clean,
      );
      await AuthService.instance.signOut();
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      setState(() => _switching = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not switch accounts: $e')));
    }
  }

  Future<void> _addAccount() async {
    final currentEmail = AuthService.instance.userEmail.trim().toLowerCase();
    if (currentEmail.isEmpty) {
      await _signOut();
      return;
    }
    await _switchTo(currentEmail);
  }

  Future<void> _signOut() async {
    if (_switching) return;
    setState(() => _switching = true);
    try {
      await AuthService.instance.signOut();
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      setState(() => _switching = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not sign out: $e')));
    }
  }

  Future<void> _forget(String email) async {
    await LocalDatabase.instance.removeRememberedAccount(email);
    await _loadAccounts();
  }

  @override
  Widget build(BuildContext context) {
    final currentEmail = AuthService.instance.userEmail.trim().toLowerCase();
    final currentName = AuthService.instance.userDisplayName;
    final initials = AuthService.instance.userInitials;
    final others = _remembered.where((row) {
      final email = (row['email'] as String? ?? '').trim().toLowerCase();
      return email.isNotEmpty && email != currentEmail;
    }).toList();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: AppTheme.textPrimary,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Accounts'),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppTheme.border),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _SectionLabel('CURRENT ACCOUNT'),
          const SizedBox(height: 10),
          _AccountCard(
            name: currentName,
            email: currentEmail.isEmpty ? 'No email on file' : currentEmail,
            initials: initials,
            isCurrent: true,
          ),
          const SizedBox(height: 26),
          _SectionLabel('SAVED ON THIS DEVICE'),
          const SizedBox(height: 10),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (others.isEmpty)
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.border),
              ),
              child: const Text(
                'No other accounts saved yet. Add an account to sign in with a '
                'different email — only the email and display name are stored.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: AppTheme.textSecondary,
                ),
              ),
            )
          else
            ...others.map((row) {
              final email = (row['email'] as String? ?? '').trim();
              final name = (row['display_name'] as String? ?? '').trim();
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _AccountCard(
                  name: name.isEmpty ? email.split('@').first : name,
                  email: email,
                  initials: _initialsFor(name, email),
                  trailing: IconButton(
                    tooltip: 'Forget account',
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: AppTheme.textMuted,
                    ),
                    onPressed: _switching ? null : () => _forget(email),
                  ),
                  onTap: _switching ? null : () => _switchTo(email),
                ),
              );
            }),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _switching ? null : _addAccount,
            icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
            label: const Text('+ Add another account'),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _switching ? null : _signOut,
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text('Sign out'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.textSecondary,
              side: const BorderSide(color: AppTheme.border),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
          if (_switching) ...[
            const SizedBox(height: 18),
            const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ],
          const SizedBox(height: 24),
          const Text(
            'Switching accounts signs you out and opens the sign-in screen '
            'with the selected email filled in. Your password and library '
            'stay on this device.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: AppTheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  static String _initialsFor(String name, String email) {
    final source = name.trim().isNotEmpty
        ? name.trim()
        : email.split('@').first;
    final parts = source
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final value = parts.first;
      return value.substring(0, value.length >= 2 ? 2 : 1).toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
        color: AppTheme.textMuted,
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.name,
    required this.email,
    required this.initials,
    this.isCurrent = false,
    this.trailing,
    this.onTap,
  });

  final String name;
  final String email;
  final String initials;
  final bool isCurrent;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCurrent
              ? AppTheme.accentGreen.withValues(alpha: 0.45)
              : AppTheme.border,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF8B5CF6), Color(0xFFEC4899)],
              ),
            ),
            child: Center(
              child: Text(
                initials,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  email,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (isCurrent)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.accentGreen.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppTheme.accentGreen.withValues(alpha: 0.4),
                ),
              ),
              child: const Text(
                'CURRENT',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: AppTheme.accentGreen,
                ),
              ),
            )
          else
            ?trailing,
        ],
      ),
    );

    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: content,
      ),
    );
  }
}
