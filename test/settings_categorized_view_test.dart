import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music/controllers/music_player_controller.dart';
import 'package:music/views/settings_view.dart';

void main() {
  testWidgets(
    'SettingsView renders 5 Spotify-style categories and excludes unwanted sections',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(380, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final controller = MusicPlayerController();

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsView(controller: controller),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 1. Verify Top Bar
      expect(find.text('Settings'), findsOneWidget);
      expect(find.byIcon(Icons.search_rounded), findsOneWidget);

      // 2. Verify the 5 Included Categories exist
      expect(find.text('Account'), findsOneWidget);
      expect(find.text('Content and display'), findsOneWidget);
      expect(find.text('Playback'), findsOneWidget);
      expect(find.text('Data-saving and offline'), findsOneWidget);
      expect(find.text('Media quality'), findsOneWidget);

      // 3. Verify Subtitles
      expect(find.text('Username • Close account'), findsOneWidget);
      expect(
        find.text('Reduce animations • Canvas • Allow explicit content'),
        findsOneWidget,
      );
      expect(find.text('Gapless playback • Autoplay • Equalizer'), findsOneWidget);
      expect(
        find.text('Data saver mode • Downloads over cellular'),
        findsOneWidget,
      );
      expect(
        find.text('Wi-Fi streaming quality • Audio download quality'),
        findsOneWidget,
      );

      // 4. Verify Excluded Categories are NOT present
      expect(find.text('Advertising'), findsNothing);
      expect(find.text('About and support'), findsNothing);
      expect(find.text('Apps and devices'), findsNothing);
      expect(find.text('Notifications'), findsNothing);
      expect(find.text('Privacy and social'), findsNothing);
      expect(find.text('Go Premium'), findsNothing);
      expect(find.text('Free account'), findsNothing);

      // 5. Open Content and display category
      await tester.tap(find.text('Content and display'));
      await tester.pumpAndSettle();

      // Verify Reduce animations switch is present
      expect(find.text('Reduce animations'), findsOneWidget);
      expect(find.text('Canvas'), findsOneWidget);
      expect(find.text('Allow explicit content'), findsOneWidget);
      expect(find.text('Show lyrics automatically'), findsOneWidget);

      // Verify toggling Reduce animations
      expect(controller.reduceAnimations, isFalse);
      final reduceAnimSwitch = find.ancestor(
        of: find.text('Reduce animations'),
        matching: find.byType(SwitchListTile),
      );
      expect(reduceAnimSwitch, findsOneWidget);
      await tester.tap(reduceAnimSwitch);
      await tester.pumpAndSettle();

      expect(controller.reduceAnimations, isTrue);

      // Pop subpage back to main settings
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();

      // 6. Test Search Bar
      final searchIcon = find.byIcon(Icons.search_rounded);
      expect(searchIcon, findsOneWidget);
      await tester.tap(searchIcon);
      await tester.pumpAndSettle();

      // Enter search query "animations"
      await tester.enterText(find.byType(TextField), 'animations');
      await tester.pumpAndSettle();

      // Verify that Reduce animations appears in search results
      expect(find.text('Reduce animations'), findsOneWidget);

      // Clean up controller
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      controller.dispose();
    },
  );

  testWidgets(
    'SettingsView navigates to Account, Playback, Data-saving, and Media quality subpages',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(380, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final controller = MusicPlayerController();

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsView(controller: controller),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Test Account subpage
      await tester.tap(find.text('Account'));
      await tester.pumpAndSettle();
      expect(find.text('Log out'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();

      // Test Playback subpage
      await tester.tap(find.text('Playback'));
      await tester.pumpAndSettle();
      expect(find.text('Crossfade'), findsOneWidget);
      expect(find.text('Gapless Playback'), findsOneWidget);
      expect(find.text('Equalizer'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();

      // Test Data-saving subpage
      await tester.tap(find.text('Data-saving and offline'));
      await tester.pumpAndSettle();
      expect(find.text('Data Saver Mode'), findsOneWidget);
      expect(find.text('Downloads over cellular'), findsOneWidget);
      expect(find.text('Local Audio Cache'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();

      // Test Media quality subpage
      await tester.tap(find.text('Media quality'));
      await tester.pumpAndSettle();
      expect(find.text('Wi-Fi streaming quality'), findsOneWidget);
      expect(find.text('Audio download quality'), findsOneWidget);

      // Clean up
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      controller.dispose();
    },
  );
}
