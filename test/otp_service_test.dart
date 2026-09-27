import 'package:flutter_test/flutter_test.dart';
import 'package:music/auth/otp_service.dart';
import 'package:music/data/local_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('OtpService 6-Digit OTP Tests', () {
    const testEmail = 'tester@example.com';
    const testPhone = '+639123456789';

    test('generates and verifies 6-digit Email OTP correctly', () async {
      String? sentEmail;
      String? sentCode;
      OtpService.emailSenderForTesting = (email, code) async {
        sentEmail = email;
        sentCode = code;
      };

      final res = await OtpService.instance.sendEmailOtp(email: testEmail);
      expect(res.success, isTrue);
      expect(sentEmail, equals(testEmail));
      expect(sentCode, isNotNull);
      expect(sentCode!.length, equals(6));
      expect(int.tryParse(sentCode!), isNotNull);

      final activeCode = OtpService.instance.getActiveCodeForTesting(testEmail);
      expect(activeCode, equals(sentCode));

      // Verify wrong code fails
      final wrongRes = await OtpService.instance.verifyEmailOtp(
        email: testEmail,
        code: '000000',
      );
      expect(wrongRes, isFalse);

      // Verify correct code succeeds
      final correctRes = await OtpService.instance.verifyEmailOtp(
        email: testEmail,
        code: sentCode!,
      );
      expect(correctRes, isTrue);

      // Second verification should fail as code was consumed
      final replayRes = await OtpService.instance.verifyEmailOtp(
        email: testEmail,
        code: sentCode!,
      );
      expect(replayRes, isFalse);

      OtpService.emailSenderForTesting = null;
    });

    test('rejects invalid email formats', () async {
      final res = await OtpService.instance.sendEmailOtp(email: 'invalid-email');
      expect(res.success, isFalse);
      expect(res.message, contains('valid email'));
    });

    test('sends simulated/fallback SMS OTP and generates 6 digits', () async {
      String? verificationId;

      await OtpService.instance.sendSmsOtp(
        phoneNumber: testPhone,
        onCodeSent: (vId, _) {
          verificationId = vId;
        },
        onError: (err) {
          fail('SMS OTP send failed: $err');
        },
      );

      expect(verificationId, isNotNull);
      final activeCode = OtpService.instance.getActiveCodeForTesting(testPhone);
      expect(activeCode, isNotNull);
      expect(activeCode!.length, equals(6));
      expect(int.tryParse(activeCode), isNotNull);
    });

    test('LocalDatabase persists both email and phone_number without errors', () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      LocalDatabase.setDatabaseForTesting(db);
      await LocalDatabase.instance.createAllTables(db);
      await LocalDatabase.instance.initialize();

      const testId = 'user-phone-test-1';
      const email = 'user_phone@example.com';
      const phone = '+639123456789';
      const name = 'Phone & Email User';

      await LocalDatabase.instance.saveUser(
        id: testId,
        email: email,
        phoneNumber: phone,
        displayName: name,
        authProvider: 'phone',
      );

      // Verify saved by Email
      final userByEmail = await LocalDatabase.instance.getUserByEmail(email);
      expect(userByEmail, isNotNull);
      expect(userByEmail!['email'], equals(email));
      expect(userByEmail['phone_number'], equals(phone));
      expect(userByEmail['display_name'], equals(name));

      // Verify saved and queried by Phone Number
      final userByPhone = await LocalDatabase.instance.getUserByPhone(phone);
      expect(userByPhone, isNotNull);
      expect(userByPhone!['id'], equals(testId));
      expect(userByPhone['email'], equals(email));
      expect(userByPhone['phone_number'], equals(phone));

      await db.close();
      LocalDatabase.setDatabaseForTesting(null);
    });
  });
}
