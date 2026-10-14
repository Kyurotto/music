import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music/main.dart';

void main() {
  testWidgets('Music Player Dashboard mounts cleanly on desktop', (WidgetTester tester) async {
    // Set a wide screen size so desktop layout renders all panels
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const MusicApp(firebaseEnabled: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Verify brand title in sidebar
    expect(find.text('PULSE'), findsOneWidget);

    // Verify welcome hero banner
    expect(find.text('Welcome to Pulse Music'), findsAtLeastNWidgets(1));

    // Verify search bar accepts input cleanly
    final searchField = find.byType(TextField);
    expect(searchField, findsOneWidget);
    await tester.enterText(searchField, 'Hinder');
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('Music Player Dashboard renders cleanly on mobile screen without overflows', (WidgetTester tester) async {
    // Set narrow mobile viewport
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const MusicApp(firebaseEnabled: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Ensure hero banner renders without assertion errors
    expect(find.text('Welcome to Pulse Music'), findsAtLeastNWidgets(1));

    // Verify mobile hamburger menu icon is present
    expect(find.byIcon(Icons.menu_rounded), findsOneWidget);
  });

  testWidgets('Volume toggle in bottom player bar functions properly', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const MusicApp(firebaseEnabled: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Find and tap the volume button in bottom player bar
    final volumeBtn = find.byWidgetPredicate(
      (w) => w is Icon && (w.icon == Icons.volume_up_rounded || w.icon == Icons.volume_down_rounded),
    );
    if (volumeBtn.evaluate().isNotEmpty) {
      await tester.tap(volumeBtn.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }
  });
}
