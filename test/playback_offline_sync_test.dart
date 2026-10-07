import 'package:flutter_test/flutter_test.dart';
import 'package:music/controllers/music_player_controller.dart';
import 'package:music/models/song_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Lyrics & Progress Synchronization Tests', () {
    test('lyricsLineIndexForProgress handles plain lyrics with advancing position', () {
      final lyrics = [
        'Line 1 of song',
        'Line 2 of song',
        'Line 3 of song',
        'Line 4 of song',
      ];
      final total = const Duration(minutes: 2); // 120 seconds

      expect(Song.lyricsLineIndexForProgress(lyrics, Duration.zero, total), 0);
      expect(Song.lyricsLineIndexForProgress(lyrics, const Duration(seconds: 35), total), 1);
      expect(Song.lyricsLineIndexForProgress(lyrics, const Duration(seconds: 65), total), 2);
      expect(Song.lyricsLineIndexForProgress(lyrics, const Duration(seconds: 95), total), 3);
      expect(Song.lyricsLineIndexForProgress(lyrics, const Duration(seconds: 120), total), 3);
    });

    test('lyricsLineIndexForProgress falls back to sane duration when total <= Duration.zero', () {
      final lyrics = ['First line', 'Second line', 'Third line'];
      // Should not divide by zero or get stuck at 0 forever
      final indexAt40s = Song.lyricsLineIndexForProgress(lyrics, const Duration(seconds: 70), Duration.zero);
      expect(indexAt40s, greaterThanOrEqualTo(1));
    });

    test('lyricsLineIndexForProgress parses synced timestamped lyrics accurately', () {
      final lyrics = [
        '[00:00.00] Intro line',
        '[00:15.00] Verse 1',
        '[00:45.00] Chorus',
        '[01:30.00] Outro',
      ];
      final total = const Duration(minutes: 2);

      expect(Song.lyricsLineIndexForProgress(lyrics, const Duration(seconds: 5), total), 0);
      expect(Song.lyricsLineIndexForProgress(lyrics, const Duration(seconds: 16), total), 1);
      expect(Song.lyricsLineIndexForProgress(lyrics, const Duration(seconds: 50), total), 2);
      expect(Song.lyricsLineIndexForProgress(lyrics, const Duration(seconds: 100), total), 3);
    });

    test('positionForLyricsLine inverts line index back to seek duration', () {
      final lyrics = [
        '[00:00.00] Intro',
        '[00:30.00] Verse',
        '[01:00.00] Chorus',
      ];
      final total = const Duration(minutes: 2);

      expect(Song.positionForLyricsLine(lyrics, 0, total), Duration.zero);
      expect(Song.positionForLyricsLine(lyrics, 1, total), const Duration(seconds: 30));
      expect(Song.positionForLyricsLine(lyrics, 2, total), const Duration(seconds: 60));
    });
  });

  group('MusicPlayerController Playback & Heartbeat Timer Tests', () {
    late MusicPlayerController controller;

    setUp(() {
      controller = MusicPlayerController();
    });

    tearDown(() {
      controller.dispose();
    });

    test('starting playback guarantees un-muted state and audible volume', () {
      controller.toggleMute();
      expect(controller.isMuted, isTrue);

      final sample = controller.allSongs.isNotEmpty
          ? controller.allSongs.first
          : Song(
              id: 'test-sample',
              title: 'Test Sample',
              artist: 'Test Artist',
              album: 'Test Album',
              duration: const Duration(minutes: 3),
              genre: 'Pop',
              imageUrl: '',
              gradientColors: const [],
              plays: '',
              lyrics: const [],
            );
      controller.playSong(sample);

      expect(controller.isMuted, isFalse);
      expect(controller.volume, greaterThanOrEqualTo(0.5));
      expect(controller.isPlaying, isTrue);
    });

    test('offline asset fallback is selected for imported tracks matching bundled audio titles', () {
      final matchingSong = Song(
        id: 'spotify-test-expired',
        title: 'Just the Way You Are',
        artist: 'Bruno Mars',
        album: 'Doo-Wops',
        duration: const Duration(minutes: 3),
        genre: 'Pop',
        imageUrl: '',
        gradientColors: const [],
        plays: '',
        lyrics: const [],
        audioUrl: 'https://rr1---sn-googlevideo.com/videoplayback?expire=123',
      );

      final fallbackAsset = controller.getOfflineAssetFallbackForTesting(matchingSong);
      expect(fallbackAsset, isNotEmpty);
      expect(fallbackAsset.endsWith('.m4a'), isTrue);

      // Verify that an unrelated song by the same artist does NOT falsely play a different song
      final nonMatchingSong = Song(
        id: 'spotify-test-unrelated',
        title: 'Grenade',
        artist: 'Bruno Mars',
        album: 'Doo-Wops',
        duration: const Duration(minutes: 3),
        genre: 'Pop',
        imageUrl: '',
        gradientColors: const [],
        plays: '',
        lyrics: const [],
      );
      expect(controller.getOfflineAssetFallbackForTesting(nonMatchingSong), isEmpty);

      final offlineLyrics = controller.ensureOfflineLyricsForTesting(matchingSong);
      expect(offlineLyrics, isNotEmpty);
      expect(offlineLyrics.any((l) => l.contains('♫')), isTrue);
    });

    test('displayDurationFor matches song duration when audio stream duration is not yet available', () {
      final testSong = Song(
        id: 'test-song-duration',
        title: 'Test Song',
        artist: 'Artist',
        album: 'Album',
        duration: const Duration(seconds: 215),
        genre: 'Pop',
        imageUrl: '',
        gradientColors: const [],
        plays: '',
        lyrics: const [],
      );

      expect(controller.displayDurationFor(testSong), const Duration(seconds: 215));
    });
  });
}
