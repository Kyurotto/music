import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music/controllers/music_player_controller.dart';
import 'package:music/models/song_model.dart';
import 'package:music/views/playlist_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Auto-refresh and Full Track indicator tests', () {
    test('Song.isFullTrack properly reports true when hasAudio and not preview', () {
      final locatingSong = Song(
        id: 'spotify-1',
        title: 'Locating Song',
        artist: 'Artist A',
        album: 'Album A',
        duration: const Duration(minutes: 3),
        genre: 'Pop',
        imageUrl: '',
        gradientColors: const [],
        plays: '10K',
        lyrics: const [],
        audioUrl: '', // No audio yet
        isPreview: false,
      );
      expect(locatingSong.hasAudio, isFalse);
      expect(locatingSong.isFullTrack, isFalse);

      final previewSong = Song(
        id: 'spotify-2',
        title: 'Preview Song',
        artist: 'Artist B',
        album: 'Album B',
        duration: const Duration(minutes: 3),
        genre: 'Pop',
        imageUrl: '',
        gradientColors: const [],
        plays: '10K',
        lyrics: const [],
        audioUrl: 'https://cdn.example.com/audio.mp3',
        isPreview: true,
      );
      expect(previewSong.hasAudio, isTrue);
      expect(previewSong.isFullTrack, isFalse);

      final fullSong = Song(
        id: 'spotify-3',
        title: 'Full Track Song',
        artist: 'Artist C',
        album: 'Album C',
        duration: const Duration(minutes: 3),
        genre: 'Pop',
        imageUrl: '',
        gradientColors: const [],
        plays: '10K',
        lyrics: const [],
        audioUrl: 'https://cdn.example.com/audio.mp3',
        isPreview: false,
      );
      expect(fullSong.hasAudio, isTrue);
      expect(fullSong.isFullTrack, isTrue);
    });

    test('MusicPlayerController locatingStatusVersion increments on bump', () {
      final controller = MusicPlayerController();
      final initialVersion = controller.locatingStatusVersion;
      var notified = false;
      controller.addListener(() {
        notified = true;
      });

      controller.bumpLocatingVersion();
      expect(controller.locatingStatusVersion, equals(initialVersion + 1));
      expect(notified, isTrue);
      controller.dispose();
    });
  });

  group('YouTube Music PlaylistScreen Widget Tests', () {
    testWidgets('Renders YouTube Music playlist UI elements correctly', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final controller = MusicPlayerController();

      final testSongs = <Song>[
        Song(
          id: 'test-1',
          title: 'Acoustic Morning',
          artist: 'Acoustic Vibe',
          album: 'Sunrise',
          duration: const Duration(minutes: 3, seconds: 20),
          genre: 'Acoustic',
          imageUrl: '',
          gradientColors: const [Colors.orange, Colors.deepOrange],
          plays: '50K',
          lyrics: const ['Line 1'],
          audioUrl: 'assets/audio/acoustic.mp3',
          isPreview: false,
        ),
        Song(
          id: 'test-2',
          title: 'Locating Track',
          artist: 'Night Owl',
          album: 'Midnight',
          duration: const Duration(minutes: 2, seconds: 45),
          genre: 'Lo-Fi',
          imageUrl: '',
          gradientColors: const [Colors.indigo, Colors.blueGrey],
          plays: '12K',
          lyrics: const [],
          audioUrl: '', // locating
          isPreview: false,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: PlaylistScreen(
            title: 'Pang relax',
            subtitle: 'Curated relaxing tunes for chill vibes',
            creatorName: 'YouTube Music',
            songs: testSongs,
            controller: controller,
          ),
        ),
      );

      // Verify Title & Creator
      expect(find.text('Pang relax'), findsOneWidget);
      expect(find.text('YouTube Music'), findsOneWidget);
      expect(find.text('• Playlist'), findsOneWidget);

      // Verify Cast action in transparent Top App Bar
      expect(find.byIcon(Icons.cast), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);

      // Verify 2x2 Collage, circular Play button, and sticky mini-player play button exist
      expect(find.byIcon(Icons.play_arrow_rounded), findsAtLeastNWidgets(1));
      expect(find.byIcon(Icons.download_outlined), findsOneWidget);
      expect(find.byIcon(Icons.share_outlined), findsOneWidget);
      expect(find.byIcon(Icons.bookmark_border_rounded), findsOneWidget);

      // Verify Songs list items
      expect(find.text('Acoustic Morning'), findsOneWidget);
      expect(find.text('Locating Track'), findsOneWidget);
      expect(find.text('FULL TRACK'), findsOneWidget);
      expect(find.text('LOCATING AUDIO'), findsOneWidget);

      // Verify Bottom Navigation items: Home, Samples, Explore, Library
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Samples'), findsOneWidget);
      expect(find.text('Explore'), findsOneWidget);
      expect(find.text('Library'), findsOneWidget);

      controller.dispose();
    });
  });
}
