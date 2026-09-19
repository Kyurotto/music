import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music/main.dart';

void main() {
  testWidgets('Music Player Dashboard mounts and displays clean state on desktop', (WidgetTester tester) async {
    // Set a wide screen size so desktop layout renders all panels
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const MusicApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Verify brand title in sidebar
    expect(find.text('PULSE'), findsOneWidget);

    // Verify clean welcome hero banner without hardcoded dummy songs
    expect(find.text('Welcome to Pulse Music'), findsOneWidget);
    expect(find.text('No tracks found'), findsOneWidget);

    // Verify search bar accepts input cleanly
    final searchField = find.byType(TextField);
    expect(searchField, findsOneWidget);
    await tester.enterText(searchField, 'My Track');
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('Music Player Dashboard renders cleanly on mobile screen without overflows', (WidgetTester tester) async {
    // Set narrow mobile viewport
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const MusicApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Ensure hero banner and title render without assertion errors
    expect(find.text('Welcome to Pulse Music'), findsOneWidget);

    // Verify mobile hamburger menu icon is present
    expect(find.byIcon(Icons.menu_rounded), findsOneWidget);
  });
}
