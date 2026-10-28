import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music/theme/app_theme.dart';
import 'package:music/views/auth_gate.dart';

void main() {
  Widget buildTestWidget() {
    return MaterialApp(
      theme: AppTheme.darkTheme,
      home: const AuthView(),
    );
  }

  testWidgets('AuthView starts in Sign In mode and switches to Create Account mode via footer button', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    // Verify Sign In mode elements
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Sign in to continue to Pulse Studio.'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Sign in'), findsOneWidget);
    expect(find.text('Confirm password'), findsNothing);

    // Switch to Create Account mode via footer button
    final createAccountBtn = find.widgetWithText(TextButton, 'Create account');
    expect(createAccountBtn, findsOneWidget);
    await tester.tap(createAccountBtn);
    await tester.pumpAndSettle();

    // Verify Create Account mode elements
    expect(find.text('Create account'), findsAtLeastNWidgets(1));
    expect(find.text('Enter your email and choose a password to get started.'), findsOneWidget);
    expect(find.text('Confirm password'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Create account'), findsOneWidget);

    // Switch back to Sign In mode
    final signInBtn = find.widgetWithText(TextButton, 'Sign in');
    expect(signInBtn, findsOneWidget);
    await tester.tap(signInBtn);
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Confirm password'), findsNothing);
  });

  testWidgets('Create Account mode validates email, password length, and password match', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    // Switch to Create Account mode via footer button
    final createAccountBtn = find.widgetWithText(TextButton, 'Create account');
    await tester.ensureVisible(createAccountBtn);
    await tester.tap(createAccountBtn);
    await tester.pumpAndSettle();

    final textFields = find.byType(TextFormField);
    expect(textFields, findsNWidgets(3)); // Email, Password, Confirm password

    final submitButton = find.widgetWithText(ElevatedButton, 'Create account');
    await tester.ensureVisible(submitButton);

    // 1. Submit empty form
    await tester.tap(submitButton);
    await tester.pumpAndSettle();
    expect(find.text('Enter an email address.'), findsOneWidget);
    expect(find.text('Use at least 6 characters.'), findsOneWidget);
    expect(find.text('Please confirm your password.'), findsOneWidget);

    // 2. Enter invalid email
    await tester.enterText(textFields.at(0), 'invalidemail');
    await tester.tap(submitButton);
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid email address.'), findsOneWidget);

    // 3. Enter valid email, short password
    await tester.enterText(textFields.at(0), 'user@example.com');
    await tester.enterText(textFields.at(1), '123');
    await tester.enterText(textFields.at(2), '123');
    await tester.tap(submitButton);
    await tester.pumpAndSettle();
    expect(find.text('Use at least 6 characters.'), findsOneWidget);

    // 4. Enter valid email, valid password, mismatched confirm password
    await tester.enterText(textFields.at(1), 'password123');
    await tester.enterText(textFields.at(2), 'mismatchPass');
    await tester.tap(submitButton);
    await tester.pumpAndSettle();
    expect(find.text('Passwords do not match.'), findsOneWidget);

    // 5. Enter matching passwords
    await tester.enterText(textFields.at(2), 'password123');
    await tester.pumpAndSettle();
    expect(find.text('Passwords do not match.'), findsNothing);
  });

  testWidgets('Password visibility toggle toggles obscureText', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    // Switch to Create Account mode via footer button
    final createAccountBtn = find.widgetWithText(TextButton, 'Create account');
    await tester.ensureVisible(createAccountBtn);
    await tester.tap(createAccountBtn);
    await tester.pumpAndSettle();

    // Find visibility icons
    final visibilityIcons = find.byIcon(Icons.visibility_off_outlined);
    expect(visibilityIcons, findsNWidgets(2)); // Password and Confirm Password

    // Tap first visibility icon (password field)
    await tester.tap(visibilityIcons.at(0));
    await tester.pumpAndSettle();

    // Now one is visible (visibility_outlined) and one is still hidden (visibility_off_outlined)
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);

    // Tap the second visibility icon (confirm password field)
    await tester.tap(find.byIcon(Icons.visibility_off_outlined));
    await tester.pumpAndSettle();

    // Now both are visible
    expect(find.byIcon(Icons.visibility_outlined), findsNWidgets(2));
  });
}
