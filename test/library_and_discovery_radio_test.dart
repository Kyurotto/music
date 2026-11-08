import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music/views/music_dashboard_view.dart';
import 'package:music/views/playlist_screen.dart';

Future<void> pumpDashboard(
  WidgetTester tester,
  Future<void> Function() interactions,
) async {
  final errors = <Object>[];
  await runZonedGuarded(
    () async {
      await tester.pumpWidget(const MaterialApp(home: MusicDashboardView()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await interactions();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    },
    (Object error, StackTrace stack) {
      if (error is MissingPluginException) return;
      errors.add(error);
    },
  );
  expect(errors, isEmpty);
}

void main() {
  testWidgets('Sidebar is clean and does not contain playlists, your library header, download icon, or plus icon', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await pumpDashboard(tester, () async {
      // Idle pump on Home screen
    });

    // Check menu navigation in sidebar
    expect(find.text('MENU'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Explore'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Favorites'), findsOneWidget);

    // Verify Library badge shows playlists count (0) instead of total music count (14)
    final libraryNavFinder = find.ancestor(
      of: find.text('Library'),
      matching: find.byType(InkWell),
    );
    expect(
      find.descendant(of: libraryNavFinder, matching: find.text('0')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: libraryNavFinder, matching: find.text('14')),
      findsNothing,
    );

    // Verify sidebar does NOT have "YOUR LIBRARY"
    expect(find.text('YOUR LIBRARY'), findsNothing);
  });

  testWidgets('Explore tab renders Daily Mixes, Popular radio, and Recents without imported playlist grid', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await pumpDashboard(tester, () async {
      // Tap Explore in Sidebar
      await tester.tap(find.text('Explore'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });

    // Check category pills
    expect(find.text('All'), findsWidgets);
    expect(find.text('Music'), findsOneWidget);
    expect(find.text('Podcasts'), findsOneWidget);
    expect(find.text('Audiobooks'), findsOneWidget);

    // Verify Made For You & Recents were removed per user requirement
    expect(find.text('Made For You'), findsNothing);
    expect(find.text('Daily Mix 01'), findsNothing);
    expect(find.text('Recents'), findsNothing);

    // Check Popular Radio and artist radio sections
    expect(find.text('Popular radio'), findsOneWidget);
    expect(find.text('Flow G'), findsWidgets);
    expect(find.text('Air Supply'), findsWidgets);
    expect(find.text('Sugarfree'), findsWidgets);
    expect(find.text('Maroon 5'), findsWidgets);

    // Verify imported playlist grid is NOT in Explore tab
    expect(find.text('Explore Playlists'), findsNothing);
    expect(find.text('All Available Catalog'), findsNothing);
  });

  testWidgets('Library tab does not display hardcoded default artists, 2000s, or radio indicators', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await pumpDashboard(tester, () async {
      // Tap Library in Sidebar
      await tester.tap(find.text('Library'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });

    // Header actions
    expect(find.text('Your Library'), findsOneWidget);
    expect(find.text('Import Spotify link'), findsWidgets);
    expect(find.text('Create playlist'), findsWidgets);

    // Filter pills
    expect(find.text('Playlists'), findsWidgets);
    expect(find.text('Albums'), findsOneWidget);

    // Verify hardcoded default artists from screenshot are removed from Library
    expect(find.text('Sugarfree'), findsNothing);
    expect(find.text('Bruno Mars'), findsNothing);
    expect(find.text('MATÉO'), findsNothing);
    expect(find.text('Adie'), findsNothing);
    expect(find.text('Tothapi'), findsNothing);

    // Verify indicator tags 'Playlist •' and 'Artist' and 'RADIO' are NOT displayed
    expect(find.text('Playlist • loser'), findsNothing);
    expect(find.text('Playlist • Made for you'), findsNothing);
    expect(find.text('Artist'), findsNothing);
    expect(find.text('RADIO'), findsNothing);

    // Verify raw flat tracklist is NOT displayed
    expect(find.text('All saved songs'), findsNothing);
  });

  testWidgets('Tapping on a created playlist in Library opens PlaylistScreen', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await pumpDashboard(tester, () async {
      await tester.tap(find.text('Library'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Tap Create playlist button
      await tester.tap(find.text('Create playlist').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Enter playlist name in dialog
      final dialogInput = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(dialogInput, 'My Chill Vibes');
      await tester.pump();

      // Submit dialog
      await tester.tap(find.text('Create'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Verify Library sidebar badge increments to 1 playlist
      final libraryNavFinder = find.ancestor(
        of: find.text('Library'),
        matching: find.byType(InkWell),
      );
      expect(
        find.descendant(of: libraryNavFinder, matching: find.text('1')),
        findsOneWidget,
      );

      // Tap on newly created playlist in Library
      expect(find.text('My Chill Vibes'), findsOneWidget);
      await tester.tap(find.text('My Chill Vibes').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    });

    // Verify PlaylistScreen was opened
    expect(find.byType(PlaylistScreen), findsOneWidget);
  });

  testWidgets('Tapping on a Popular Radio in Explore opens PlaylistScreen', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await pumpDashboard(tester, () async {
      await tester.tap(find.text('Explore'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Tap on Flow G Radio card
      await tester.tap(find.text('Flow G').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    });

    // Verify PlaylistScreen was opened
    expect(find.byType(PlaylistScreen), findsOneWidget);
  });
}
