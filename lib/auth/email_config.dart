import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../data/local_database.dart';

/// Configuration for sending real OTP emails via Gmail SMTP to any Gmail or Facebook account.
///
/// Setup instructions:
/// 1. Sender Gmail: [senderEmail] is the Gmail account sending the verification emails.
/// 2. Google App Password: [appPassword] is the 16-character App Password generated from:
///    https://myaccount.google.com/apppasswords
///    (Select 'Mail' or custom name 'Pulse Music' -> generate 16 characters).
/// 3. You can also enter it directly through the in-app popup dialog, in Firestore ('app_config/smtp'),
///    or right here in this file.
class EmailConfig {
  EmailConfig._();

  /// The sender Gmail address (e.g., your app's Gmail or your personal Gmail).
  static String senderEmail = 'johnlaurencenovicio@gmail.com';

  /// The 16-character Google App Password (e.g., "abcd efgh ijkl mnop").
  /// Spaces will be automatically stripped before connecting to Gmail SMTP.
  static String appPassword = 'edvx tkph khnc soyc';

  /// Sender display name that appears in the recipient's inbox.
  static String senderDisplayName = 'Pulse Music';

  static bool _hasSyncedFromFirestore = false;
  static bool _hasLoadedLocal = false;

  /// Loads credentials from LocalDatabase app_settings or Firestore.
  static Future<void> loadSavedCredentials([FirebaseFirestore? firestore]) async {
    if (!_hasLoadedLocal) {
      try {
        final savedPass = await LocalDatabase.instance.getSetting('smtp_app_password');
        final savedSender = await LocalDatabase.instance.getSetting('smtp_sender_email');
        if (savedPass != null && savedPass.trim().isNotEmpty) {
          appPassword = savedPass.trim();
        }
        if (savedSender != null && savedSender.trim().isNotEmpty) {
          senderEmail = savedSender.trim();
        }
        _hasLoadedLocal = true;
      } catch (_) {}
    }
    if (firestore != null) {
      await syncFromFirestore(firestore);
    }
  }

  /// Saves credentials to LocalDatabase and in memory so it is remembered permanently.
  static Future<void> saveCredentials({
    required String sender,
    required String password,
  }) async {
    senderEmail = sender.trim();
    appPassword = password.trim();
    try {
      await LocalDatabase.instance.saveSetting('smtp_sender_email', senderEmail);
      await LocalDatabase.instance.saveSetting('smtp_app_password', appPassword);
    } catch (_) {}
  }

  /// Attempts to read SMTP credentials from Firestore 'app_config/smtp' document.
  static Future<void> syncFromFirestore(FirebaseFirestore? firestore) async {
    if (firestore == null || _hasSyncedFromFirestore) return;
    try {
      final doc = await firestore
          .collection('app_config')
          .doc('smtp')
          .get()
          .timeout(const Duration(seconds: 4));

      if (doc.exists) {
        final data = doc.data();
        if (data != null) {
          final sEmail = data['senderEmail']?.toString().trim();
          final sPass = data['appPassword']?.toString().trim();
          if (sEmail != null && sEmail.isNotEmpty) {
            senderEmail = sEmail;
          }
          if (sPass != null && sPass.isNotEmpty) {
            appPassword = sPass;
          }
        }
      }
      _hasSyncedFromFirestore = true;
    } catch (e) {
      debugPrint('[EmailConfig] Firestore SMTP config sync note: $e');
    }
  }

  /// Returns clean 16-character App Password with spaces removed.
  static String get cleanAppPassword => appPassword.replaceAll(' ', '').trim();

  /// Whether SMTP credentials have been provided.
  static bool get isConfigured =>
      senderEmail.isNotEmpty &&
      senderEmail.contains('@') &&
      cleanAppPassword.isNotEmpty;
}
