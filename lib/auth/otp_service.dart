import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server/gmail.dart';
import 'auth_service.dart';
import 'email_config.dart';

/// Representation of an active OTP session
class OtpSession {
  final String target; // email or phone number
  final String type; // 'email' or 'sms'
  final String? verificationId; // For Firebase Phone Auth
  final DateTime createdAt;
  final DateTime expiresAt;
  final String? code; // Stored for email OTP or simulated SMS OTP

  OtpSession({
    required this.target,
    required this.type,
    this.verificationId,
    required this.createdAt,
    required this.expiresAt,
    this.code,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class OtpResult {
  final bool success;
  final String message;
  final String? debugCode; // Exposed in test/dev mode for seamless verification
  final String? verificationId;

  const OtpResult({
    required this.success,
    required this.message,
    this.debugCode,
    this.verificationId,
  });
}

/// Service managing 6-digit SMS and Email OTP verification
class OtpService {
  OtpService._();
  static final instance = OtpService._();

  FirebaseAuth? get _auth {
    try {
      return FirebaseAuth.instance;
    } catch (_) {
      return null;
    }
  }

  FirebaseFirestore? get _firestore {
    try {
      return FirebaseFirestore.instance;
    } catch (_) {
      return null;
    }
  }

  // Active email OTP sessions: email -> OtpSession
  final Map<String, OtpSession> _emailSessions = {};

  // Active SMS sessions: phoneNumber -> OtpSession
  final Map<String, OtpSession> _smsSessions = {};

  // Cooldown tracking: target -> last sent timestamp
  final Map<String, DateTime> _lastSentTimes = {};

  static const int otpLength = 6;
  static const Duration otpValidity = Duration(minutes: 10);
  static const Duration resendCooldown = Duration(seconds: 60);

  /// Returns remaining seconds before a new code can be requested for [target].
  int getRemainingCooldown(String target) {
    final clean = target.trim().toLowerCase();
    final lastSent = _lastSentTimes[clean];
    if (lastSent == null) return 0;
    final elapsed = DateTime.now().difference(lastSent);
    final remaining = resendCooldown.inSeconds - elapsed.inSeconds;
    return remaining > 0 ? remaining : 0;
  }

  /// Generate a secure random 6-digit OTP string
  String _generate6DigitOtp() {
    final rng = Random.secure();
    final code = 100000 + rng.nextInt(900000);
    return code.toString();
  }

  /// Hook for testing email OTP delivery in unit tests without live internet
  @visibleForTesting
  static Future<void> Function(String email, String code)? emailSenderForTesting;

  /// Hook for enabling simulated SMS OTP in unit tests without live cellular service
  @visibleForTesting
  static bool enableMockSmsForTesting = false;

  /// Returns active OTP code for unit testing or diagnostics
  @visibleForTesting
  String? getActiveCodeForTesting(String target) {
    final clean = target.trim().toLowerCase();
    return _emailSessions[clean]?.code ?? _smsSessions[clean]?.code;
  }

  // ===========================================================================
  // EMAIL OTP
  // ===========================================================================

  /// Sends a 6-digit OTP code to the specified [email].
  /// Stores code in-memory and in Firestore `email_otps` if available.
  Future<OtpResult> sendEmailOtp({required String email}) async {
    final cleanEmail = email.trim().toLowerCase();
    if (cleanEmail.isEmpty || !cleanEmail.contains('@')) {
      return const OtpResult(
        success: false,
        message: 'Please enter a valid email address.',
      );
    }

    final cooldown = getRemainingCooldown(cleanEmail);
    if (cooldown > 0) {
      return OtpResult(
        success: false,
        message: 'Please wait $cooldown seconds before requesting a new code.',
      );
    }

    final code = _generate6DigitOtp();
    final now = DateTime.now();
    final expiresAt = now.add(otpValidity);

    final session = OtpSession(
      target: cleanEmail,
      type: 'email',
      code: code,
      createdAt: now,
      expiresAt: expiresAt,
    );
    _emailSessions[cleanEmail] = session;
    _lastSentTimes[cleanEmail] = now;

    // Sync to Firestore if available (useful for verification lookup or Firebase extensions)
    try {
      final firestore = _firestore;
      if (firestore != null) {
        final otpHash = sha256.convert(utf8.encode(code)).toString();
        await firestore.collection('email_otps').doc(cleanEmail).set({
          'email': cleanEmail,
          'otp_hash': otpHash,
          'createdAt': FieldValue.serverTimestamp(),
          'expiresAt': Timestamp.fromDate(expiresAt),
        }, SetOptions(merge: true)).timeout(const Duration(seconds: 3));

        // Also write to mail collection for Firebase Trigger Email extension if installed
        try {
          await firestore.collection('mail').add({
            'to': [cleanEmail],
            'message': {
              'subject': 'Your Pulse Music Verification Code',
              'text': 'Your 6-digit verification code is: $code. This code is valid for 10 minutes.',
              'html': '''
                <div style="font-family: Arial, sans-serif; padding: 20px; color: #111;">
                  <h2>Pulse Music Verification</h2>
                  <p>Use the following 6-digit code to verify your account:</p>
                  <div style="font-size: 32px; font-weight: bold; letter-spacing: 6px; color: #8B5CF6; margin: 20px 0;">$code</div>
                  <p>This code will expire in 10 minutes.</p>
                  <p>If you did not request this code, you can safely ignore this email.</p>
                </div>
              ''',
            },
          }).timeout(const Duration(seconds: 3));
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[OtpService] Firestore email OTP sync note: $e');
    }

    // Hook for unit testing email OTP delivery
    if (emailSenderForTesting != null) {
      try {
        await emailSenderForTesting!(cleanEmail, code);
        return OtpResult(
          success: true,
          message: 'Verification code sent to $cleanEmail',
        );
      } catch (e) {
        return OtpResult(
          success: false,
          message: 'Failed to deliver OTP: $e',
        );
      }
    }

    // Load SMTP credentials dynamically from local database or Firestore
    await EmailConfig.loadSavedCredentials(_firestore);

    // Send real OTP email to the recipient's Gmail inbox via Gmail SMTP
    if (EmailConfig.isConfigured) {
      try {
        final smtpServer = gmail(
          EmailConfig.senderEmail.trim(),
          EmailConfig.cleanAppPassword,
        );

        final message = Message()
          ..from = Address(EmailConfig.senderEmail.trim(), EmailConfig.senderDisplayName)
          ..recipients.add(cleanEmail)
          ..subject = 'Pulse Music Verification Code: $code'
          ..text = 'Your 6-digit Pulse Music verification code is: $code. This code is valid for 10 minutes.'
          ..html = '''
            <div style="font-family: Arial, sans-serif; padding: 24px; color: #111; max-width: 500px; margin: 0 auto; border: 1px solid #e2e8f0; border-radius: 12px; background-color: #ffffff;">
              <h2 style="color: #8B5CF6; margin-top: 0; font-size: 22px;">Pulse Music Verification</h2>
              <p style="font-size: 15px; color: #334155; line-height: 1.5;">Use the following 6-digit code to verify your account:</p>
              <div style="font-size: 34px; font-weight: 800; letter-spacing: 8px; color: #8B5CF6; margin: 20px 0; padding: 16px; background-color: #f5f3ff; border-radius: 8px; text-align: center; border: 1px dashed #8B5CF6;">$code</div>
              <p style="font-size: 13px; color: #64748b; margin-bottom: 4px;">This code will expire in 10 minutes.</p>
              <p style="font-size: 12px; color: #94a3b8; margin-top: 20px; border-top: 1px solid #f1f5f9; padding-top: 12px;">If you did not request this verification code, you can safely ignore this email.</p>
            </div>
          ''';

        await send(message, smtpServer).timeout(const Duration(seconds: 15));
        debugPrint('[OtpService] Real Gmail SMTP OTP email successfully delivered to $cleanEmail');
      } on SmtpClientAuthenticationException catch (e) {
        debugPrint('[OtpService] Gmail SMTP authentication failed: $e');
        return const OtpResult(
          success: false,
          message: 'Gmail authentication failed. Please check the 16-character App Password in EmailConfig.',
        );
      } catch (e) {
        debugPrint('[OtpService] Gmail SMTP sending error: $e');
        return OtpResult(
          success: false,
          message: 'Failed to deliver OTP email to $cleanEmail ($e).',
        );
      }
    } else {
      debugPrint('[OtpService] Notice: Gmail App Password not yet configured in EmailConfig or Firestore app_config/smtp.');
      return const OtpResult(
        success: false,
        message: 'Gmail sending requires your 16-character Google App Password. Please configure it in EmailConfig to deliver real emails to your Gmail inbox.',
      );
    }

    return OtpResult(
      success: true,
      message: 'Verification code sent to $cleanEmail',
    );
  }

  /// Verifies the 6-digit [code] for the given [email].
  Future<bool> verifyEmailOtp({
    required String email,
    required String code,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final cleanCode = code.trim();

    if (cleanCode.length != otpLength) return false;

    void deleteFirestoreOtp() {
      try {
        _firestore?.collection('email_otps').doc(cleanEmail).delete().catchError((_) {});
      } catch (_) {}
    }

    // 1. Check local session
    final session = _emailSessions[cleanEmail];
    if (session != null) {
      if (!session.isExpired && session.code == cleanCode) {
        _emailSessions.remove(cleanEmail);
        deleteFirestoreOtp();
        return true;
      }
    }

    // 2. Check Firestore fallback if local state was reset
    try {
      final firestore = _firestore;
      if (firestore != null) {
        final doc = await firestore
            .collection('email_otps')
            .doc(cleanEmail)
            .get()
            .timeout(const Duration(seconds: 3));
        if (doc.exists) {
          final data = doc.data();
          final storedHash = data?['otp_hash']?.toString();
          final storedOtp = data?['otp']?.toString();
          final inputHash = sha256.convert(utf8.encode(cleanCode)).toString();
          final isMatch = (storedHash != null && storedHash == inputHash) ||
              (storedOtp != null && storedOtp == cleanCode);
          final expiresAt = (data?['expiresAt'] as Timestamp?)?.toDate();
          if (isMatch) {
            if (expiresAt == null || DateTime.now().isBefore(expiresAt)) {
              deleteFirestoreOtp();
              return true;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[OtpService] Firestore OTP verification note: $e');
    }

    return false;
  }

  // ===========================================================================
  // SMS OTP (Phone Number)
  // ===========================================================================

  /// Sends a 6-digit OTP code to the given [phoneNumber].
  /// Uses Firebase Phone Auth when available, with clean fallback for dev/testing.
  Future<void> sendSmsOtp({
    required String phoneNumber,
    required void Function(String verificationId, String? debugCode) onCodeSent,
    required void Function(String error) onError,
    void Function(PhoneAuthCredential credential)? onAutoVerified,
  }) async {
    final cleanPhone = phoneNumber.trim().replaceAll(' ', '');
    if (cleanPhone.isEmpty || cleanPhone.length < 7) {
      onError('Please enter a valid phone number with country code (e.g. +639...).');
      return;
    }

    final cooldown = getRemainingCooldown(cleanPhone);
    if (cooldown > 0) {
      onError('Please wait $cooldown seconds before requesting a new SMS.');
      return;
    }

    final auth = _auth;
    // On native mobile (Android/iOS) where Firebase Auth is initialized
    if (auth != null && !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
      try {
        bool callbackFired = false;
        Timer? timeoutTimer;

        void triggerFallback() {
          if (callbackFired) return;
          callbackFired = true;
          timeoutTimer?.cancel();
          if (enableMockSmsForTesting) {
            _sendFallbackSmsOtp(cleanPhone, onCodeSent);
          } else {
            onError('SMS verification timed out. Please try again or use email verification.');
          }
        }

        // Safety timer: if Firebase Phone Auth hangs on Play Integrity / SafetyNet or network,
        // fail gracefully after 15 seconds so the user is informed
        timeoutTimer = Timer(const Duration(seconds: 15), () {
          debugPrint('[OtpService] Firebase Phone Auth verification timed out after 15s.');
          triggerFallback();
        });

        await auth.verifyPhoneNumber(
          phoneNumber: cleanPhone,
          timeout: const Duration(seconds: 30),
          verificationCompleted: (PhoneAuthCredential credential) {
            callbackFired = true;
            timeoutTimer?.cancel();
            debugPrint('[OtpService] Phone auto-verification completed.');
            if (onAutoVerified != null) {
              onAutoVerified(credential);
            }
          },
          verificationFailed: (FirebaseAuthException e) {
            debugPrint('[OtpService] Firebase Phone Auth error: ${e.code} - ${e.message}');
            if (callbackFired) return;
            callbackFired = true;
            timeoutTimer?.cancel();
            if (e.code == 'invalid-phone-number') {
              onError(e.message ?? 'Invalid phone number format.');
              return;
            }
            if (enableMockSmsForTesting) {
              _sendFallbackSmsOtp(cleanPhone, onCodeSent);
              return;
            }
            onError(e.message ?? 'SMS delivery failed. Please use email verification.');
          },
          codeSent: (String verificationId, int? resendToken) {
            if (callbackFired) return;
            callbackFired = true;
            timeoutTimer?.cancel();

            final now = DateTime.now();
            _lastSentTimes[cleanPhone] = now;
            _smsSessions[cleanPhone] = OtpSession(
              target: cleanPhone,
              type: 'sms',
              verificationId: verificationId,
              createdAt: now,
              expiresAt: now.add(otpValidity),
            );
            debugPrint('[OtpService] Real Firebase SMS OTP sent to $cleanPhone (verificationId: $verificationId)');
            onCodeSent(verificationId, null);
          },
          codeAutoRetrievalTimeout: (String verificationId) {
            debugPrint('[OtpService] SMS auto-retrieval timed out for $verificationId');
          },
        );
        return;
      } catch (e) {
        debugPrint('[OtpService] verifyPhoneNumber exception: $e');
        if (enableMockSmsForTesting) {
          _sendFallbackSmsOtp(cleanPhone, onCodeSent);
          return;
        }
        onError('SMS verification error: $e');
        return;
      }
    }

    // In unit testing environment when mock is enabled
    if (enableMockSmsForTesting) {
      _sendFallbackSmsOtp(cleanPhone, onCodeSent);
      return;
    }

    onError('SMS verification is unavailable on this platform. Please use email verification.');
  }

  void _sendFallbackSmsOtp(
    String cleanPhone,
    void Function(String verificationId, String? debugCode) onCodeSent,
  ) {
    final now = DateTime.now();
    final code = _generate6DigitOtp();
    final mockVerificationId = 'sim_${DateTime.now().millisecondsSinceEpoch}';

    _lastSentTimes[cleanPhone] = now;
    _smsSessions[cleanPhone] = OtpSession(
      target: cleanPhone,
      type: 'sms',
      code: code,
      verificationId: mockVerificationId,
      createdAt: now,
      expiresAt: now.add(otpValidity),
    );

    onCodeSent(mockVerificationId, null);
  }

  /// Verifies the 6-digit SMS code and completes sign-in.
  /// If [autoSignIn] is true, automatically signs into a phone profile.
  /// If [autoSignIn] is false, validates the code without switching session.
  Future<bool> verifySmsOtp({
    required String verificationId,
    required String smsCode,
    required String phoneNumber,
    String? displayName,
    bool autoSignIn = true,
  }) async {
    final cleanPhone = phoneNumber.trim().replaceAll(' ', '');
    final cleanCode = smsCode.trim();

    if (cleanCode.length != otpLength) return false;

    // 1. If this was a simulated/test verification
    if (verificationId.startsWith('sim_')) {
      final session = _smsSessions[cleanPhone];
      if (session != null && !session.isExpired && session.code == cleanCode) {
        _smsSessions.remove(cleanPhone);
        if (autoSignIn) {
          await AuthService.instance.signInWithPhoneSuccess(
            phoneNumber: cleanPhone,
            displayName: displayName,
          );
        }
        return true;
      }
      return false;
    }

    // 2. Real Firebase Phone Auth
    final auth = _auth;
    if (auth != null) {
      try {
        final credential = PhoneAuthProvider.credential(
          verificationId: verificationId,
          smsCode: cleanCode,
        );
        final userCredential = await auth.signInWithCredential(credential);
        if (userCredential.user != null) {
          _smsSessions.remove(cleanPhone);
          if (autoSignIn) {
            await AuthService.instance.signInWithPhoneSuccess(
              phoneNumber: cleanPhone,
              displayName: displayName,
              firebaseUser: userCredential.user,
            );
          }
          return true;
        }
      } catch (e) {
        debugPrint('[OtpService] Phone credential sign-in error: $e');
        rethrow;
      }
    }

    return false;
  }
}
