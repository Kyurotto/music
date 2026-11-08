import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music/controllers/music_player_controller.dart';
import 'package:music/models/song_model.dart';
import 'package:music/services/radio_discovery_service.dart';
import 'package:music/views/music_dashboard_view.dart';
import 'package:music/views/playlist_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Explore Tab Native Radio Overhaul Tests', () {
    testWidgets('Explore tab renders Popular Radio, OPM Radio, Global Radio and removes Made For You & Recents', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MusicDashboardView(),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 300));

      // Switch to Explore tab
      final exploreNav = find.text('Explore');
      expect(exploreNav, findsWidgets);
      await tester.tap(exploreNav.first);
      await tester.pump(const Duration(milliseconds: 300));

      // Verify "Made For You" and "Recents" are completely removed
      expect(find.text('Made For You'), findsNothing);
      expect(find.text('Daily Mix 01'), findsNothing);
      expect(find.text('Recents'), findsNothing);

      // Verify Spotify radio sections exist
      expect(find.text('Popular radio'), findsOneWidget);
      expect(find.text('Sugarfree'), findsWidgets); // "More like Sugarfree"
      expect(find.text('Maroon 5'), findsWidgets);  // "More like Maroon 5"

      // Verify Category pills
      expect(find.text('All'), findsWidgets);
      expect(find.text('Music'), findsWidgets);

      // Verify dynamic radio search bar
      expect(find.textContaining('Search any Spotify radio or artist'), findsOneWidget);
    });

    test('fastImportRadioStation imports radio playlist and songs into Library', () {
      final controller = MusicPlayerController();

      final radioStation = RadioStation(
        id: 'test-flow-g',
        title: 'Flow G Radio',
        artistName: 'Flow G',
        subtitle: 'With SUPAFLY, Lo ki, Hev Abi and more',
        backgroundColor: const Color(0xFF8BB7F0),
        gradientColors: const [Color(0xFF8BB7F0), Color(0xFF60A5FA)],
        avatarUrls: const [
          'https://example.com/flowg.jpg',
          'https://example.com/supafly.jpg',
          'https://example.com/loki.jpg',
        ],
        songs: [
          Song(
            id: 'test-song-rapstar',
            title: 'Rapstar',
            artist: 'Flow G',
            album: 'Rapstar Single',
            duration: const Duration(minutes: 4, seconds: 12),
            genre: 'Hip-Hop',
            imageUrl: 'https://example.com/flowg.jpg',
            gradientColors: const [Color(0xFF8BB7F0), Color(0xFF60A5FA)],
            plays: '45.2M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'test-song-since-day-one',
            title: 'Since Day One',
            artist: 'Skusta Clee, Flow G',
            album: 'Since Day One',
            duration: const Duration(minutes: 3, seconds: 34),
            genre: 'Hip-Hop',
            imageUrl: 'https://example.com/skusta.jpg',
            gradientColors: const [Color(0xFF8BB7F0), Color(0xFF60A5FA)],
            plays: '38.1M',
            lyrics: const [],
            isPreview: false,
          ),
        ],
      );

      final imported = controller.fastImportRadioStation(radioStation);

      expect(imported.title, 'Flow G Radio');
      expect(imported.subtitle, 'With SUPAFLY, Lo ki, Hev Abi and more');
      expect(imported.songIds.length, 2);
      expect(imported.songIds, contains('test-song-rapstar'));
      expect(imported.songIds, contains('test-song-since-day-one'));

      // Verify songs added to controller's library
      expect(controller.allSongs.any((s) => s.id == 'test-song-rapstar'), isTrue);
      expect(controller.playlists.any((p) => p.title == 'Flow G Radio'), isTrue);

      controller.dispose();
    });
  });

  group('PlaylistScreen 19-Pixel Overflow Fix & Fast Import Tests', () {
    testWidgets('PlaylistScreen does not overflow on narrow screens when displaying radio playlist with long subtitle', (tester) async {
      // Set to very narrow phone width where 19-pixel overflow previously occurred
      await tester.binding.setSurfaceSize(const Size(320, 900));

      final controller = MusicPlayerController();

      final radioStation = RadioStation(
        id: 'flow-g-radio',
        title: 'Flow G Radio',
        artistName: 'Flow G',
        subtitle: 'With SUPAFLY, Lo ki, Hev Abi and more',
        backgroundColor: const Color(0xFF8BB7F0),
        gradientColors: const [Color(0xFF8BB7F0), Color(0xFF60A5FA)],
        avatarUrls: const [
          'https://example.com/flowg.jpg',
        ],
        songs: [
          Song(
            id: 'test-flowg-1',
            title: 'Ebeb',
            artist: 'Flow G',
            album: 'Ebeb',
            duration: const Duration(minutes: 4, seconds: 21),
            genre: 'Hip-Hop',
            imageUrl: '',
            gradientColors: const [Color(0xFF8BB7F0), Color(0xFF60A5FA)],
            plays: '45.2M',
            lyrics: const [],
            isPreview: false,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlaylistScreen(
              playlist: radioStation.toPlaylist(),
              songs: radioStation.songs,
              controller: controller,
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 300));

      // Verify NO RenderFlex overflow exception
      expect(tester.takeException(), isNull);

      // Verify title is rendered
      expect(find.text('Flow G Radio'), findsOneWidget);

      // Verify creator displays "Spotify Radio" without overflow
      expect(find.text('Spotify Radio'), findsOneWidget);

      // Verify Fast Import icon button exists in the action row
      expect(find.byTooltip('Fast Import to Library'), findsOneWidget);

      // Verify Download all icon button exists
      expect(find.byTooltip('Download all'), findsOneWidget);

      // Scroll to Fast Import button and tap it to verify it triggers import cleanly
      final fastImportFinder = find.byTooltip('Fast Import to Library');
      await tester.ensureVisible(fastImportFinder);
      await tester.tap(fastImportFinder);
      await tester.pump(const Duration(milliseconds: 300));

      expect(controller.playlists.any((p) => p.title == 'Flow G Radio'), isTrue);

      controller.dispose();
    });
  });
}
