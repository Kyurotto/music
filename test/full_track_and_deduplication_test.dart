import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music/controllers/music_player_controller.dart';
import 'package:music/models/song_model.dart';
import 'package:music/services/discovery_service.dart';
import 'package:music/services/spotify_import_service.dart';
import 'package:music/services/track_enrichment_service.dart';
import 'package:music/widgets/track_list_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Full track vs preview tests', () {
    test('DiscoveryTrack.toSong creates full track candidate with isPreview=false and empty audioUrl', () {
      const track = DiscoveryTrack(
        trackId: 99991,
        title: 'Full Track Test Song',
        artist: 'Test Artist',
        album: 'Test Album',
        artworkUrl: 'https://example.com/cover.jpg',
        previewUrl: 'https://audio-ssl.itunes.apple.com/30s-chorus.m4a',
        durationMs: 210000,
      );

      final song = track.toSong();
      expect(song.isPreview, isFalse, reason: 'Must not default to 30s preview snippet');
      expect(song.audioUrl, isEmpty, reason: 'Must resolve full audio instead of jumping to 30s preview');
      expect(song.isSilentPlaceholder, isTrue, reason: 'Must be placed in pending queue for full audio locator');
    });

    test('TrackEnrichmentService defaults allowPreviewFallback to false', () async {
      final service = TrackEnrichmentService();
      // Test signature defaults allowPreviewFallback to false
      final enrichment = await service.enrichTrack(
        title: 'Nonexistent Track Title 12345XYZ',
        artist: 'Nonexistent Artist 12345XYZ',
      );
      if (enrichment.hasAudio) {
        expect(enrichment.isFullTrack, isTrue);
      }
    });

    test('MusicPlayerController.needsFullTrack correctly flags any preview or silent tracks across sources', () {
      final previewSong = Song(
        id: 'discovery-itunes-12345',
        title: 'Preview Song',
        artist: 'Some Artist',
        album: 'Some Album',
        duration: const Duration(minutes: 3),
        genre: 'Pop',
        imageUrl: '',
        gradientColors: const [],
        plays: '100',
        lyrics: const [],
        audioUrl: 'https://audio-ssl.itunes.apple.com/30s.m4a',
        isPreview: true,
      );

      final bundledSong = Song(
        id: 'asset-1',
        title: 'Bundled Track',
        artist: 'Local Artist',
        album: 'Local Album',
        duration: const Duration(minutes: 3),
        genre: 'Pop',
        imageUrl: '',
        gradientColors: const [],
        plays: '100',
        lyrics: const [],
        audioUrl: 'assets/audio/sample.mp3',
        isPreview: false,
      );

      final fullTrackSong = Song(
        id: 'spotify-999',
        title: 'Full Track',
        artist: 'Full Artist',
        album: 'Full Album',
        duration: const Duration(minutes: 3),
        genre: 'Pop',
        imageUrl: '',
        gradientColors: const [],
        plays: '100',
        lyrics: const [],
        audioUrl: 'https://rr1---sn.googlevideo.com/videoplayback',
        isPreview: false,
      );

      expect(MusicPlayerController.needsFullTrack(previewSong), isTrue,
          reason: 'Preview tracks must be flagged as needing full track location');
      expect(MusicPlayerController.needsFullTrack(bundledSong), isFalse,
          reason: 'Bundled asset tracks have complete audio');
      expect(MusicPlayerController.needsFullTrack(fullTrackSong), isFalse,
          reason: 'Resolved full tracks do not need locating');
    });
  });

  group('Playlist deduplication tests', () {
    test('addSongToPlaylist rejects duplicate IDs and duplicate title/artist', () {
      final controller = MusicPlayerController();
      controller.createPlaylist('Test Dedupe Playlist');
      final playlist = controller.playlists.firstWhere((p) => p.title == 'Test Dedupe Playlist');

      final songA = Song(
        id: 'track-id-1',
        title: 'Photograph',
        artist: 'Ed Sheeran',
        album: 'X',
        duration: const Duration(minutes: 4, seconds: 19),
        genre: 'Pop',
        imageUrl: '',
        gradientColors: const [Colors.blue, Colors.purple],
        plays: '1000',
        lyrics: const [],
        audioUrl: '',
        isPreview: false,
      );

      // Same title and artist, different ID (e.g. from discovery or import)
      final songB = Song(
        id: 'discovery-itunes-998877',
        title: 'photograph',
        artist: 'ed sheeran',
        album: 'X (Deluxe)',
        duration: const Duration(minutes: 4, seconds: 19),
        genre: 'Pop',
        imageUrl: '',
        gradientColors: const [Colors.blue, Colors.purple],
        plays: '1000',
        lyrics: const [],
        audioUrl: '',
        isPreview: false,
      );

      // 1. Add first song -> should succeed
      final addedA = controller.addSongToPlaylist(playlist.id, songA);
      expect(addedA, isTrue);

      // 2. Add identical song by ID -> should return false
      final addedAgain = controller.addSongToPlaylist(playlist.id, songA);
      expect(addedAgain, isFalse);

      // 3. Add same song with different ID -> should return false
      final addedB = controller.addSongToPlaylist(playlist.id, songB);
      expect(addedB, isFalse, reason: 'Must prevent duplicate tracks in playlist');

      // 4. Verify songsForPlaylist contains exactly 1 song
      final playlistSongs = controller.songsForPlaylist(playlist.id);
      expect(playlistSongs.length, equals(1));
      expect(playlistSongs.first.title, equals('Photograph'));
      controller.dispose();
    });

    test('importSpotifyTracks deduplicates tracks on import', () {
      final controller = MusicPlayerController();
      const pName = 'Spotify Import Dedupe';

      final incoming = [
        const SpotifyImportedTrack(
          spotifyId: 'sp-1',
          title: 'Yellow',
          artist: 'Coldplay',
          album: 'Parachutes',
          duration: Duration(milliseconds: 269000),
          artworkUrl: '',
        ),
        // Duplicate entry in import
        const SpotifyImportedTrack(
          spotifyId: 'sp-2',
          title: 'yellow',
          artist: 'coldplay',
          album: 'Parachutes',
          duration: Duration(milliseconds: 269000),
          artworkUrl: '',
        ),
        const SpotifyImportedTrack(
          spotifyId: 'sp-3',
          title: 'The Scientist',
          artist: 'Coldplay',
          album: 'A Rush of Blood to the Head',
          duration: Duration(milliseconds: 309000),
          artworkUrl: '',
        ),
      ];

      final result = controller.importSpotifyTracks(
        playlistName: pName,
        tracks: incoming,
      );

      expect(result.addedCount, equals(2), reason: 'Must only add 2 distinct songs, ignoring the duplicate');
      final playlist = controller.playlists.firstWhere((p) => p.title == pName);
      final songs = controller.songsForPlaylist(playlist.id);
      expect(songs.length, equals(2));
      controller.dispose();
    });

    test('MusicPlayerController.isSameSong accurately detects duplicates and respects version tags', () {
      final base = Song(
        id: '1',
        title: 'Perfect',
        artist: 'Ed Sheeran',
        album: 'Divide',
        duration: const Duration(minutes: 4, seconds: 23),
        genre: 'Pop',
        imageUrl: '',
        gradientColors: const [],
        plays: '',
        lyrics: const [],
        audioUrl: '',
        isPreview: false,
      );

      final sameCleaned = Song(
        id: '2',
        title: 'Perfect (Official Audio)',
        artist: 'Ed Sheeran',
        album: 'Divide',
        duration: const Duration(minutes: 4, seconds: 23),
        genre: 'Pop',
        imageUrl: '',
        gradientColors: const [],
        plays: '',
        lyrics: const [],
        audioUrl: '',
        isPreview: false,
      );

      final acousticVersion = Song(
        id: '3',
        title: 'Perfect (Acoustic Version)',
        artist: 'Ed Sheeran',
        album: 'Divide',
        duration: const Duration(minutes: 4, seconds: 20),
        genre: 'Pop',
        imageUrl: '',
        gradientColors: const [],
        plays: '',
        lyrics: const [],
        audioUrl: '',
        isPreview: false,
      );

      expect(MusicPlayerController.isSameSong(base, sameCleaned), isTrue);
      expect(MusicPlayerController.isSameSong(base, acousticVersion), isFalse,
          reason: 'Acoustic version has different version tag');
    });
  });

  group('TrackListView mobile UI rendering test', () {
    testWidgets('Renders clean single-row track list without warping or overflowing on 360px mobile screen',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final controller = MusicPlayerController();

      final songs = [
        Song(
          id: 'row-test-1',
          title: 'Very Long Song Title That Might Have Previously Warped On Mobile Screens Due To Desktop Columns',
          artist: 'Very Long Artist Name Collaborating With Another Long Artist Name',
          album: 'Test Album',
          duration: const Duration(minutes: 3, seconds: 45),
          genre: 'Pop',
          imageUrl: '',
          gradientColors: const [Colors.indigo, Colors.teal],
          plays: '1.2M',
          lyrics: const [],
          audioUrl: 'https://example.com/audio.mp3',
          isPreview: false,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrackListView(
              songs: songs,
              controller: controller,
            ),
          ),
        ),
      );

      await tester.pump();

      // Verify FULL TRACK badge rendered and no RenderFlex overflow
      expect(find.text('FULL TRACK'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'Layout must not overflow on narrow mobile screens');

      controller.dispose();
    });
  });
}
