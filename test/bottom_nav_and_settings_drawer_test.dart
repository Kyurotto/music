import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music/main.dart';

void main() {
  testWidgets(
    'Bottom navigation layer renders Home, Explore, and Library with icons and labels on mobile',
    (WidgetTester tester) async {
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
        (w) =>
            w is Icon &&
            w.icon == Icons.library_music_rounded &&
            w.size == 22.0,
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
    },
  );

  testWidgets(
    'Top header contains full-width single-line search bar without redundant notifications or settings icons',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(const MusicApp(firebaseEnabled: false));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Verify search input is present in the top header
      final searchField = find.byType(TextField);
      expect(searchField, findsOneWidget);

      // Verify notifications and settings icons are removed from top bar
      expect(find.byTooltip('Notifications'), findsNothing);
      expect(find.byTooltip('Settings'), findsNothing);
    },
  );

  testWidgets('Left hamburger opens the drawer with account shortcuts', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const MusicApp(firebaseEnabled: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final menuButton = find.byTooltip('Open menu');
    expect(menuButton, findsOneWidget);
    expect(
      find.descendant(
        of: menuButton,
        matching: find.byIcon(Icons.menu_rounded),
      ),
      findsOneWidget,
    );

    await tester.tap(menuButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('View profile'), findsOneWidget);
    expect(find.text('Add account'), findsOneWidget);
    expect(find.text('Listening stats'), findsOneWidget);
    expect(find.text('Recents'), findsOneWidget);
    expect(find.text('Your Updates'), findsOneWidget);
    expect(find.text('Settings and privacy'), findsOneWidget);
  });
}
