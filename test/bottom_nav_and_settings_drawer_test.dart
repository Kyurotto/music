import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music/main.dart';

void main() {
  testWidgets('Bottom navigation layer renders Home, Explore, and Library with icons and labels on mobile', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const MusicApp(firebaseEnabled: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Verify bottom navigation icons exist with size 22 in bottom bar
    final homeFinder = find.byWidgetPredicate(
      (w) => w is Icon && w.icon == Icons.home_rounded && w.size == 22.0,
    );
    final exploreFinder = find.byWidgetPredicate(
      (w) => w is Icon && w.icon == Icons.explore_rounded && w.size == 22.0,
    );
    final libraryFinder = find.byWidgetPredicate(
      (w) => w is Icon && w.icon == Icons.library_music_rounded && w.size == 22.0,
    );

    expect(homeFinder, findsOneWidget);
    expect(exploreFinder, findsOneWidget);
    expect(libraryFinder, findsOneWidget);

    // Verify bottom layer items labels exist
    expect(find.textContaining('Home'), findsWidgets);
    expect(find.textContaining('Explore'), findsWidgets);
    expect(find.textContaining('Library'), findsWidgets);

    // Tap Library in bottom layer
    await tester.tap(libraryFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Tap Home in bottom layer
    await tester.tap(homeFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('Settings button exists in top header with settings icon', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const MusicApp(firebaseEnabled: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Find settings button in top header
    final settingsFinder = find.byTooltip('Settings');
    expect(settingsFinder, findsOneWidget);
    expect(
      find.descendant(
        of: settingsFinder,
        matching: find.byIcon(Icons.settings_outlined),
      ),
      findsOneWidget,
    );
  });
}
