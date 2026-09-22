import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music/main.dart';

void main() {
  testWidgets('Music Player Dashboard mounts with English music and playlists on desktop', (WidgetTester tester) async {
    // Set a wide screen size so desktop layout renders all panels
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const MusicApp(firebaseEnabled: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Verify brand title in sidebar
    expect(find.text('PULSE'), findsOneWidget);

    // Verify the Eminem and artist playlists are available
    expect(find.text('Lose Yourself'), findsAtLeastNWidgets(1));
    expect(find.text('This Is Eminem'), findsAtLeastNWidgets(1));
    expect(find.text('This Is Ed Sheeran'), findsAtLeastNWidgets(1));

    // Verify search bar accepts input cleanly
    final searchField = find.byType(TextField);
    expect(searchField, findsOneWidget);
    await tester.enterText(searchField, 'Eminem');
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

    // Ensure hero banner and title render without assertion errors
    expect(find.text('Lose Yourself'), findsAtLeastNWidgets(1));

    // Verify mobile hamburger menu icon is present
    expect(find.byIcon(Icons.menu_rounded), findsOneWidget);
  });

  testWidgets('Tapping a song enables playback and pops up Spotify lyrics sheet', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const MusicApp(firebaseEnabled: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Tap on 'Listen Now' button in the HeroBanner
    final playBtn = find.text('Listen Now');
    expect(playBtn, findsOneWidget);
    await tester.tap(playBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    // Verify Spotify lyrics sheet pops up
    expect(find.text('PLAYING WITH LYRICS'), findsOneWidget);
    expect(find.text('LYRICS'), findsOneWidget);

    // Dismiss lyrics sheet
    final closeBtn = find.byTooltip('Close lyrics');
    if (closeBtn.evaluate().isNotEmpty) {
      await tester.tap(closeBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
    }
  });
}
