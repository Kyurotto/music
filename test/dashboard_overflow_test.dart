import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music/views/music_dashboard_view.dart';

/// Regression tests for the dashboard header rows (Library / Favorites):
/// action buttons must never overflow, on narrow or wide screens.
///
/// The dashboard owns a real [just_audio] player, which has no platform
/// plugin in tests. Those [MissingPluginException]s are swallowed; every
/// other error (including RenderFlex overflows) fails the test.
Future<void> pumpDashboardWithoutPluginNoise(
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
  testWidgets('Library header does not overflow on a narrow phone screen', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await pumpDashboardWithoutPluginNoise(tester, () async {
      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Library'));
    });

    expect(find.text('Your Library'), findsOneWidget);
    expect(find.text('Import Spotify link'), findsOneWidget);
    expect(find.text('Create playlist'), findsOneWidget);
  });

  testWidgets('Library header does not overflow on a wide desktop screen', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await pumpDashboardWithoutPluginNoise(tester, () async {
      await tester.tap(find.text('Library'));
    });

    expect(find.text('Your Library'), findsOneWidget);
    expect(find.text('Import Spotify link'), findsOneWidget);
    expect(find.text('Create playlist'), findsOneWidget);
  });

  testWidgets('Favorites header does not overflow on a narrow phone screen', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await pumpDashboardWithoutPluginNoise(tester, () async {
      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Favorites'));
    });

    expect(find.text('Favorite Songs'), findsOneWidget);
  });
}
