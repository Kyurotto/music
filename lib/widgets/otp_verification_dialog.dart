import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

/// Modal dialog or bottom sheet for entering a 6-digit OTP code (SMS or Email).
class OtpVerificationDialog extends StatefulWidget {
  final String title;
  final String destination;
  final String type; // 'email' or 'sms'
  final Future<bool> Function(String code) onVerify;
  final Future<void> Function() onResend;
  final VoidCallback? onSwitchMethod;
  final String? switchMethodLabel;
  final bool methodSelectionMode;
  final Future<void> Function(String method)? onSelectMethod;

  const OtpVerificationDialog({
    super.key,
    required this.title,
    required this.destination,
    required this.type,
    required this.onVerify,
    required this.onResend,
    this.onSwitchMethod,
    this.switchMethodLabel,
    this.methodSelectionMode = false,
    this.onSelectMethod,
  });

  /// Displays the OTP verification bottom sheet.
  static Future<bool?> show({
    required BuildContext context,
    required String title,
    required String destination,
    required String type,
    required Future<bool> Function(String code) onVerify,
    required Future<void> Function() onResend,
    VoidCallback? onSwitchMethod,
    String? switchMethodLabel,
    bool methodSelectionMode = false,
    Future<void> Function(String method)? onSelectMethod,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => OtpVerificationDialog(
        title: title,
        destination: destination,
        type: type,
        onVerify: onVerify,
        onResend: onResend,
        onSwitchMethod: onSwitchMethod,
        switchMethodLabel: switchMethodLabel,
        methodSelectionMode: methodSelectionMode,
        onSelectMethod: onSelectMethod,
      ),
    );
  }

  @override
  State<OtpVerificationDialog> createState() => _OtpVerificationDialogState();
}

class _OtpVerificationDialogState extends State<OtpVerificationDialog> {
  static const int _digitsCount = 6;
  final List<TextEditingController> _controllers =
      List.generate(_digitsCount, (_) => TextEditingController());
  final List<FocusNode> _focusNodes =
      List.generate(_digitsCount, (_) => FocusNode());

  int _resendCooldown = 60;
  Timer? _countdownTimer;
  bool _isVerifying = false;
  bool _isResending = false;
  bool _methodSelectionMode = false;
  bool _isSendingCode = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _methodSelectionMode = widget.methodSelectionMode;
    _startCooldownTimer();

    // Auto-focus first input box after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _focusNodes.isNotEmpty) {
        _focusNodes[0].requestFocus();
      }
    });
  }

  Future<void> _handleSelectMethod(String method) async {
    if (_isSendingCode || widget.onSelectMethod == null) return;
    setState(() {
      _isSendingCode = true;
      _errorMessage = null;
    });
    try {
      await widget.onSelectMethod!(method);
      if (!mounted) return;
      setState(() {
        _methodSelectionMode = false;
        _isSendingCode = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSendingCode = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _startCooldownTimer() {
    _countdownTimer?.cancel();
    _resendCooldown = 60;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendCooldown > 0) {
        setState(() => _resendCooldown--);
      } else {
        timer.cancel();
      }
    });
  }

  String get _currentCode => _controllers.map((c) => c.text).join();

  void _onDigitChanged(int index, String value) {
    setState(() => _errorMessage = null);

    // If user pasted a string longer than 1 character
    if (value.length > 1) {
      final digits = value.replaceAll(RegExp(r'\D'), '');
      if (digits.isNotEmpty) {
        for (var i = 0; i < _digitsCount; i++) {
          if (i < digits.length) {
            _controllers[i].text = digits[i];
          }
        }
        final targetIndex = digits.length >= _digitsCount ? _digitsCount - 1 : digits.length;
        _focusNodes[targetIndex].requestFocus();

        if (digits.length >= _digitsCount) {
          _handleVerify();
        }
      }
      return;
    }

    if (value.isNotEmpty) {
      // Advance to next field
      if (index < _digitsCount - 1) {
        _focusNodes[index + 1].requestFocus();
      } else {
        // Last digit entered, unfocus and trigger verify
        _focusNodes[index].unfocus();
        if (_currentCode.length == _digitsCount) {
          _handleVerify();
        }
      }
    }
  }


  Future<void> _handleVerify() async {
    final code = _currentCode;
    if (code.length != _digitsCount) {
      setState(() => _errorMessage = 'Please enter all 6 digits.');
      return;
    }

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    try {
      final success = await widget.onVerify(code);
      if (!mounted) return;
      if (success) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _isVerifying = false;
          _errorMessage = 'Invalid or expired 6-digit code. Please try again.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isVerifying = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _handleResend() async {
    if (_resendCooldown > 0 || _isResending) return;

    setState(() {
      _isResending = true;
      _errorMessage = null;
    });

    try {
      await widget.onResend();
      if (!mounted) return;
      setState(() {
        _isResending = false;
      });
      _startCooldownTimer();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('A new 6-digit code was sent to ${widget.destination}.'),
          backgroundColor: AppTheme.surface,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isResending = false;
        _errorMessage = 'Failed to resend: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEmail = widget.type == 'email';
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 20,
        bottom: bottomInset > 0 ? bottomInset + 20 : 32,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle bar
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

            // Icon + Title
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                  ),
                  child: Icon(
                    isEmail ? Icons.mark_email_read_rounded : Icons.sms_rounded,
                    color: AppTheme.primary,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Code sent to ${widget.destination}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.close_rounded, color: AppTheme.textSecondary),
                ),
              ],
            ),

            const SizedBox(height: 18),



            // 6-digit Input Boxes
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(_digitsCount, (index) {
                return SizedBox(
                  width: 46,
                  height: 56,
                  child: KeyboardListener(
                    focusNode: FocusNode(),
                    onKeyEvent: (event) {
                      if (event is KeyDownEvent &&
                          event.logicalKey == LogicalKeyboardKey.backspace &&
                          _controllers[index].text.isEmpty &&
                          index > 0) {
                        _focusNodes[index - 1].requestFocus();
                      }
                    },
                    child: TextFormField(
                      controller: _controllers[index],
                      focusNode: _focusNodes[index],
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6), // Allows paste
                      ],
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                      decoration: InputDecoration(
                        contentPadding: EdgeInsets.zero,
                        fillColor: AppTheme.cardSurface,
                        filled: true,
                        counterText: '',
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppTheme.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: AppTheme.primary,
                            width: 2,
                          ),
                        ),
                      ),
                      onChanged: (val) => _onDigitChanged(index, val),
                    ),
                  ),
                );
              }),
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],

            const SizedBox(height: 24),

            if (_methodSelectionMode) ...[
              const Text(
                'Choose where to send your code:',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isSendingCode ? null : () => _handleSelectMethod('email'),
                      icon: _isSendingCode
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.email_rounded, size: 18),
                      label: const Text('Send to Email'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isSendingCode ? null : () => _handleSelectMethod('sms'),
                      icon: _isSendingCode
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sms_rounded, size: 18),
                      label: const Text('Send to SMS'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              // Verify Button
              ElevatedButton(
                onPressed: _isVerifying ? null : _handleVerify,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _isVerifying
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        'Verify & Continue',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),

              const SizedBox(height: 12),

              // Resend row
              Center(
                child: _resendCooldown > 0
                    ? Text(
                        'Resend code in 0:${_resendCooldown.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 13,
                        ),
                      )
                    : TextButton.icon(
                        onPressed: _isResending ? null : _handleResend,
                        icon: _isResending
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Resend Code'),
                      ),
              ),
            ],
            if (widget.onSwitchMethod != null) ...[
              const SizedBox(height: 6),
              Center(
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop(false);
                    widget.onSwitchMethod!();
                  },
                  icon: Icon(
                    isEmail ? Icons.phone_android_rounded : Icons.email_outlined,
                    size: 16,
                    color: AppTheme.secondary,
                  ),
                  label: Text(
                    widget.switchMethodLabel ??
                        (isEmail ? 'Send code via SMS instead' : 'Send code via Email instead'),
                    style: const TextStyle(
                      color: AppTheme.secondary,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
