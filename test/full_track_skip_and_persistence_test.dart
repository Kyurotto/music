import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music/controllers/music_player_controller.dart';
import 'package:music/data/local_database.dart';
import 'package:music/models/song_model.dart';
import 'package:music/services/playlist_persistence_service.dart';
import 'package:music/services/spotify_import_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    LocalDatabase.setDatabaseForTesting(db);
    await LocalDatabase.instance.createAllTables(db);
    await LocalDatabase.instance.initialize();
  });

  tearDown(() async {
    await db.close();
    LocalDatabase.setDatabaseForTesting(null);
  });

  group('Bug 1: Full track skip tests', () {
    test(
      'Song model getters correctly identify locating, preview, and full track statuses',
      () {
        final locatingSong = Song(
          id: 'spot-locating-1',
          title: 'Locating Track',
          artist: 'Artist',
          album: 'Album',
          duration: const Duration(minutes: 3),
          genre: 'Pop',
          imageUrl: '',
          gradientColors: const [],
          plays: '100',
          lyrics: const [],
          audioUrl: '',
          isPreview: false,
        );

        final previewSong = Song(
          id: 'spot-preview-1',
          title: 'Preview Track',
          artist: 'Artist',
          album: 'Album',
          duration: const Duration(seconds: 30),
          genre: 'Pop',
          imageUrl: '',
          gradientColors: const [],
          plays: '100',
          lyrics: const [],
          audioUrl: 'https://audio-ssl.itunes.apple.com/preview.m4a',
          isPreview: true,
        );

        final fullTrackSong = Song(
          id: 'spot-full-1',
          title: 'Full Track',
          artist: 'Artist',
          album: 'Album',
          duration: const Duration(minutes: 3, seconds: 45),
          genre: 'Pop',
          imageUrl: '',
          gradientColors: const [],
          plays: '100',
          lyrics: const [],
          audioUrl: 'https://example.com/stream.mp4',
          isPreview: false,
        );

        // Verify statuses
        expect(locatingSong.isLocating, isTrue);
        expect(locatingSong.hasAudio, isFalse);
        expect(locatingSong.isFullTrack, isFalse);
        expect(locatingSong.isPreview, isFalse);

        expect(previewSong.isLocating, isFalse);
        expect(previewSong.hasAudio, isTrue);
        expect(previewSong.isFullTrack, isFalse);
        expect(previewSong.isPreview, isTrue);

        expect(fullTrackSong.isLocating, isFalse);
        expect(fullTrackSong.hasAudio, isTrue);
        expect(fullTrackSong.isFullTrack, isTrue);
        expect(fullTrackSong.isPreview, isFalse);
      },
    );

    test(
      'MusicPlayerController.needsFullTrack returns false for any full track and true only for locating/preview',
      () {
        final fullTrackSong = Song(
          id: 'spot-full-1',
          title: 'Full Track',
          artist: 'Artist',
          album: 'Album',
          duration: const Duration(minutes: 3, seconds: 45),
          genre: 'Pop',
          imageUrl: '',
          gradientColors: const [],
          plays: '100',
          lyrics: const [],
          audioUrl: 'https://example.com/stream.mp4',
          isPreview: false,
        );

        final locatingSong = Song(
          id: 'spot-locating-1',
          title: 'Locating Track',
          artist: 'Artist',
          album: 'Album',
          duration: const Duration(minutes: 3),
          genre: 'Pop',
          imageUrl: '',
          gradientColors: const [],
          plays: '100',
          lyrics: const [],
          audioUrl: '',
          isPreview: false,
        );

        final previewSong = Song(
          id: 'spot-preview-1',
          title: 'Preview Track',
          artist: 'Artist',
          album: 'Album',
          duration: const Duration(seconds: 30),
          genre: 'Pop',
          imageUrl: '',
          gradientColors: const [],
          plays: '100',
          lyrics: const [],
          audioUrl: 'https://audio-ssl.itunes.apple.com/preview.m4a',
          isPreview: true,
        );

        expect(
          MusicPlayerController.needsFullTrack(fullTrackSong),
          isFalse,
          reason: 'Full tracks must NEVER be flagged as needing full track',
        );
        expect(
          MusicPlayerController.needsFullTrack(locatingSong),
          isTrue,
          reason: 'Locating tracks without audio need full track',
        );
        expect(
          MusicPlayerController.needsFullTrack(previewSong),
          isTrue,
          reason: '30s previews need full track upgrade',
        );
      },
    );

    test(
      'Queue navigation skips locating and preview tracks but NEVER skips full tracks',
      () {
        final song1 = Song(
          id: 'song-1',
          title: 'Full Track 1',
          artist: 'Artist 1',
          album: 'Album 1',
          duration: const Duration(minutes: 3),
          genre: 'Pop',
          imageUrl: '',
          gradientColors: const [],
          plays: '100',
          lyrics: const [],
          audioUrl: 'https://example.com/audio1.mp3',
          isPreview: false,
        );

        final song2 = Song(
          id: 'song-2',
          title: 'Locating Track',
          artist: 'Artist 2',
          album: 'Album 2',
          duration: const Duration(minutes: 3),
          genre: 'Pop',
          imageUrl: '',
          gradientColors: const [],
          plays: '100',
          lyrics: const [],
          audioUrl: '', // locating
          isPreview: false,
        );

        final song3 = Song(
          id: 'song-3',
          title: 'Preview Track',
          artist: 'Artist 3',
          album: 'Album 3',
          duration: const Duration(seconds: 30),
          genre: 'Pop',
          imageUrl: '',
          gradientColors: const [],
          plays: '100',
          lyrics: const [],
          audioUrl: 'https://example.com/preview3.mp3',
          isPreview: true, // preview
        );

        final song4 = Song(
          id: 'song-4',
          title: 'Full Track 2',
          artist: 'Artist 4',
          album: 'Album 4',
          duration: const Duration(minutes: 4),
          genre: 'Pop',
          imageUrl: '',
          gradientColors: const [],
          plays: '100',
          lyrics: const [],
          audioUrl: 'https://example.com/audio4.mp3',
          isPreview: false,
        );

        final queue = [song1, song2, song3, song4];

        // nextFullTrackIndex from index 0 should jump over song2 and song3, landing on song4 (index 3)
        final nextIndex = MusicPlayerController.nextFullTrackIndex(
          queue,
          0,
          false,
        );
        expect(
          nextIndex,
          3,
          reason: 'Must skip locating and preview to land on Full Track 2',
        );

        // nextFullTrackIndex from index 1 (locating) should return index 3
        final fromLocating = MusicPlayerController.nextFullTrackIndex(
          queue,
          1,
          false,
        );
        expect(fromLocating, 3);

        // nextFullTrackIndex from index 2 (preview) should return index 3
        final fromPreview = MusicPlayerController.nextFullTrackIndex(
          queue,
          2,
          false,
        );
        expect(fromPreview, 3);

        // nextFullTrackIndex when two full tracks are adjacent: song1 -> song4 directly without skip
        final adjacentQueue = [song1, song4];
        final adjacentNext = MusicPlayerController.nextFullTrackIndex(
          adjacentQueue,
          0,
          false,
        );
        expect(
          adjacentNext,
          1,
          reason: 'Adjacent full track must never be skipped',
        );
      },
    );

    test(
      'Controller next() strictly advances sequentially to adjacent track (Lil Kasalanan Shortie -> Babaero, not skipping to Burgis)',
      () async {
        final controller = MusicPlayerController();

        final lilKasalanan = Song(
          id: 'hev-0',
          title: 'Lil Kasalanan Shortie',
          artist: 'Hev Abi',
          album: 'Album',
          duration: const Duration(minutes: 2, seconds: 43),
          genre: 'Hip-Hop',
          imageUrl: '',
          gradientColors: const [],
          plays: '100K',
          lyrics: const [],
          audioUrl: 'assets/audio/sample1.mp3', // Full track
          isPreview: false,
        );

        final babaero = Song(
          id: 'hev-1',
          title: 'Babaero',
          artist: 'gins&melodies, Hev Abi',
          album: 'Album',
          duration: const Duration(minutes: 3, seconds: 28),
          genre: 'Hip-Hop',
          imageUrl: '',
          gradientColors: const [],
          plays: '92.4M',
          lyrics: const [],
          audioUrl: 'https://rr.googlevideo.com/stream1', // Full track
          isPreview: false,
        );

        final pakundangan = Song(
          id: 'hev-2',
          title: 'Pakundangan (feat. Hev Abi)',
          artist: 'DEMI, Hev Abi',
          album: 'Album',
          duration: const Duration(minutes: 3, seconds: 17),
          genre: 'Hip-Hop',
          imageUrl: '',
          gradientColors: const [],
          plays: '50M',
          lyrics: const [],
          audioUrl: '', // Locating
          isPreview: false,
        );

        final makasarili = Song(
          id: 'hev-3',
          title: 'Makasarili Malambing',
          artist: 'Kristina Dawn, Hev Abi',
          album: 'Album',
          duration: const Duration(minutes: 3, seconds: 44),
          genre: 'Hip-Hop',
          imageUrl: '',
          gradientColors: const [],
          plays: '68M',
          lyrics: const [],
          audioUrl: '', // Locating
          isPreview: false,
        );

        final burgis = Song(
          id: 'hev-4',
          title: 'Burgis',
          artist: 'Flow G, Hev Abi',
          album: 'Album',
          duration: const Duration(minutes: 3, seconds: 29),
          genre: 'Hip-Hop',
          imageUrl: '',
          gradientColors: const [],
          plays: '100M',
          lyrics: const [],
          audioUrl: 'https://rr.googlevideo.com/stream4', // Full track
          isPreview: false,
        );

        final hevQueue = [
          lilKasalanan,
          babaero,
          pakundangan,
          makasarili,
          burgis,
        ];

        // Start by playing the list at index 0 (Lil Kasalanan Shortie)
        controller.playSongList(hevQueue, startIndex: 0);
        expect(controller.currentIndex, 0);
        expect(controller.currentSong?.title, 'Lil Kasalanan Shortie');

        // Call next() -> MUST play index 1 (Babaero) strictly in sequence, NOT jump to Burgis (index 4)
        controller.next();
        expect(
          controller.currentIndex,
          1,
          reason:
              'Next track must strictly be Babaero (index 1) since it has full track audio',
        );
        expect(controller.currentSong?.title, 'Babaero');
        expect(controller.currentSong?.isFullTrack, isTrue);

        // Call next() again from Babaero (index 1):
        // Pakundangan (index 2) and Makasarili (index 3) have "LOCATING" status (audioUrl: '').
        // Sequential playback MUST skip the locating tracks and proceed to Burgis (index 4).
        controller.next();
        expect(
          controller.currentIndex,
          4,
          reason:
              'Must skip locating tracks (Pakundangan & Makasarili) and advance to next playable track (Burgis)',
        );
        expect(controller.currentSong?.title, 'Burgis');

        controller.pause();
        controller.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      },
    );

    test(
      'Duplicate completion signals advance only one track (Lil Kasalanan -> Babaero, never Burgis)',
      () async {
        final controller = MusicPlayerController();

        Song fullTrack(String id, String title, String audioUrl) => Song(
          id: id,
          title: title,
          artist: 'Hev Abi',
          album: 'Album',
          duration: const Duration(minutes: 3),
          genre: 'Hip-Hop',
          imageUrl: '',
          gradientColors: const [],
          plays: '1M',
          lyrics: const [],
          audioUrl: audioUrl,
          isPreview: false,
        );

        Song locating(String id, String title) => Song(
          id: id,
          title: title,
          artist: 'Hev Abi',
          album: 'Album',
          duration: const Duration(minutes: 3),
          genre: 'Hip-Hop',
          imageUrl: '',
          gradientColors: const [],
          plays: '1M',
          lyrics: const [],
          audioUrl: '',
          isPreview: false,
        );

        controller.setSongs([
          fullTrack(
            'dup-0',
            'Lil Kasalanan Shortie',
            'assets/audio/sample1.mp3',
          ),
          fullTrack('dup-1', 'Babaero', 'https://rr.googlevideo.com/stream1'),
          locating('dup-2', 'Pakundangan (feat. Hev Abi)'),
          locating('dup-3', 'Makasarili Malambing (feat. Hev Abi)'),
          fullTrack('dup-4', 'Burgis', 'https://rr.googlevideo.com/stream4'),
        ]);

        expect(controller.currentIndex, 0);
        expect(controller.currentSong?.title, 'Lil Kasalanan Shortie');

        // First completion signal (from either the heartbeat timer or the native
        // player-state stream): the finished track advances to Babaero.
        controller.handleSongCompleteForTesting();
        expect(
          controller.currentIndex,
          1,
          reason:
              'First completion must advance to the adjacent full track Babaero',
        );
        expect(controller.currentSong?.title, 'Babaero');

        // Second signal for the same completion: must be ignored. Previously it
        // advanced again, skipped Babaero and landed on Burgis.
        controller.handleSongCompleteForTesting();
        expect(
          controller.currentIndex,
          1,
          reason: 'Duplicate completion signal must not skip Babaero',
        );
        expect(controller.currentSong?.title, 'Babaero');

        controller.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      },
    );

    test(
      'Full tracks are never classified as locating, even with expired or missing sources',
      () {
        final expiredYouTube = Song(
          id: 'expired-full-1',
          title: 'Expired Stream',
          artist: 'Artist',
          album: 'Album',
          duration: const Duration(minutes: 3),
          genre: 'Pop',
          imageUrl: '',
          gradientColors: const [],
          plays: '1M',
          lyrics: const [],
          audioUrl: 'https://rr.googlevideo.com/videoplayback?expire=1',
          isPreview: false,
        );

        final missingLocal = Song(
          id: 'missing-local-1',
          title: 'Missing Local File',
          artist: 'Artist',
          album: 'Album',
          duration: const Duration(minutes: 3),
          genre: 'Pop',
          imageUrl: '',
          gradientColors: const [],
          plays: '1M',
          lyrics: const [],
          audioUrl: '/nonexistent/path/missing-local-1.m4a',
          isPreview: false,
        );

        expect(
          MusicPlayerController.isLocatingStatus(expiredYouTube),
          isFalse,
          reason: 'An expired URL is a playback-recovery problem, not LOCATING',
        );
        expect(
          MusicPlayerController.isLocatingStatus(missingLocal),
          isFalse,
          reason:
              'A missing cached file is a playback-recovery problem, not LOCATING',
        );
      },
    );

    test(
      'Skip strictly applies to LOCATING or PREVIEW tracks, never skipping full tracks',
      () async {
        final controller = MusicPlayerController();

        final lilKasalanan = Song(
          id: 'skip-0',
          title: 'Lil Kasalanan Shortie',
          artist: 'Hev Abi',
          album: 'Album',
          duration: const Duration(minutes: 2, seconds: 43),
          genre: 'Hip-Hop',
          imageUrl: '',
          gradientColors: const [],
          plays: '100K',
          lyrics: const [],
          audioUrl: 'assets/audio/sample1.mp3', // Full track
          isPreview: false,
        );

        final babaero = Song(
          id: 'skip-1',
          title: 'Babaero',
          artist: 'gins&melodies, Hev Abi',
          album: 'Album',
          duration: const Duration(minutes: 3, seconds: 28),
          genre: 'Hip-Hop',
          imageUrl: '',
          gradientColors: const [],
          plays: '92.4M',
          lyrics: const [],
          audioUrl: 'https://rr.googlevideo.com/stream1', // Full track
          isPreview: false,
        );

        final previewTrack = Song(
          id: 'skip-2',
          title: 'Preview Track',
          artist: 'Preview Artist',
          album: 'Album',
          duration: const Duration(seconds: 30),
          genre: 'Pop',
          imageUrl: '',
          gradientColors: const [],
          plays: '10K',
          lyrics: const [],
          audioUrl:
              'https://audio-ssl.itunes.apple.com/preview.m4a', // Preview status
          isPreview: true,
        );

        final locatingTrack = Song(
          id: 'skip-3',
          title: 'Locating Track',
          artist: 'Locating Artist',
          album: 'Album',
          duration: const Duration(minutes: 3),
          genre: 'Hip-Hop',
          imageUrl: '',
          gradientColors: const [],
          plays: '50M',
          lyrics: const [],
          audioUrl: '', // Locating status
          isPreview: false,
        );

        final burgis = Song(
          id: 'skip-4',
          title: 'Burgis',
          artist: 'Flow G, Hev Abi',
          album: 'Album',
          duration: const Duration(minutes: 3, seconds: 29),
          genre: 'Hip-Hop',
          imageUrl: '',
          gradientColors: const [],
          plays: '100M',
          lyrics: const [],
          audioUrl: 'https://rr.googlevideo.com/stream4', // Full track
          isPreview: false,
        );

        final queue = [
          lilKasalanan,
          babaero,
          previewTrack,
          locatingTrack,
          burgis,
        ];

        // Start by playing Lil Kasalanan Shortie (index 0)
        controller.playSongList(queue, startIndex: 0);
        expect(controller.currentIndex, 0);
        expect(controller.currentSong?.title, 'Lil Kasalanan Shortie');

        // Next track is Babaero (index 1, Full Track) -> MUST play Babaero, NOT skip it
        controller.next();
        expect(
          controller.currentIndex,
          1,
          reason:
              'Next track must strictly be Babaero because it is a full track',
        );
        expect(controller.currentSong?.title, 'Babaero');

        // Calling next() from Babaero:
        // skip-2 is PREVIEW -> skipped!
        // skip-3 is LOCATING -> skipped!
        // skip-4 is Burgis (Full Track) -> MUST land on Burgis (index 4)
        controller.next();
        expect(
          controller.currentIndex,
          4,
          reason:
              'Must skip preview track and locating track, advancing directly to Burgis',
        );
        expect(controller.currentSong?.title, 'Burgis');

        controller.pause();
        controller.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      },
    );

    test(
      'User bug scenario: Kanto -> Pakundangan (locating) -> Babaero skips locating Pakundangan and plays Babaero',
      () async {
        final controller = MusicPlayerController();

        final lilKasalanan = Song(
          id: 'user-0',
          title: 'Lil Kasalanan Shortie',
          artist: 'Hev Abi',
          album: 'Album',
          duration: const Duration(minutes: 2, seconds: 43),
          genre: 'Hip-Hop',
          imageUrl: '',
          gradientColors: const [],
          plays: '100K',
          lyrics: const [],
          audioUrl: 'assets/audio/sample1.mp3',
          isPreview: false,
        );

        final kanto = Song(
          id: 'user-1',
          title: 'Kanto',
          artist: 'Hev Abi',
          album: 'Album',
          duration: const Duration(minutes: 3, seconds: 12),
          genre: 'Hip-Hop',
          imageUrl: '',
          gradientColors: const [],
          plays: '80K',
          lyrics: const [],
          audioUrl: 'assets/audio/sample2.mp3',
          isPreview: false,
        );

        final pakundangan = Song(
          id: 'user-2',
          title: 'Pakundangan (feat. Hev Abi)',
          artist: 'DEMI, Hev Abi',
          album: 'Album',
          duration: const Duration(minutes: 3, seconds: 17),
          genre: 'Hip-Hop',
          imageUrl: '',
          gradientColors: const [],
          plays: '50M',
          lyrics: const [],
          audioUrl: '', // Locating status
          isPreview: false,
        );

        final babaero = Song(
          id: 'user-3',
          title: 'Babaero',
          artist: 'gins&melodies, Hev Abi',
          album: 'Album',
          duration: const Duration(minutes: 3, seconds: 28),
          genre: 'Hip-Hop',
          imageUrl: '',
          gradientColors: const [],
          plays: '92.4M',
          lyrics: const [],
          audioUrl: 'https://rr.googlevideo.com/stream1', // Playable
          isPreview: false,
        );

        final userQueue = [lilKasalanan, kanto, pakundangan, babaero];

        // Play starting at Kanto (index 1)
        controller.playSongList(userQueue, startIndex: 1);
        expect(controller.currentIndex, 1);
        expect(controller.currentSong?.title, 'Kanto');

        // Track completion or next() after Kanto:
        // Pakundangan (index 2) is LOCATING, so sequential playback must skip it and play Babaero (index 3)
        controller.next();
        expect(
          controller.currentIndex,
          3,
          reason:
              'Must skip Pakundangan because it is locating, and proceed sequentially to Babaero',
        );
        expect(controller.currentSong?.title, 'Babaero');

        controller.pause();
        controller.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      },
    );

    test(
      'Skip strictly applies to LOCATING or PREVIEW tracks, never skipping full tracks',
      () async {
        final controller = MusicPlayerController();

        final lilKasalanan = Song(
          id: 'skip-0',
          title: 'Lil Kasalanan Shortie',
          artist: 'Hev Abi',
          album: 'Album',
          duration: const Duration(minutes: 2, seconds: 43),
          genre: 'Hip-Hop',
          imageUrl: '',
          gradientColors: const [],
          plays: '100K',
          lyrics: const [],
          audioUrl: 'assets/audio/sample1.mp3', // Full track
          isPreview: false,
        );

        final babaero = Song(
          id: 'skip-1',
          title: 'Babaero',
          artist: 'gins&melodies, Hev Abi',
          album: 'Album',
          duration: const Duration(minutes: 3, seconds: 28),
          genre: 'Hip-Hop',
          imageUrl: '',
          gradientColors: const [],
          plays: '92.4M',
          lyrics: const [],
          audioUrl: 'https://rr.googlevideo.com/stream1', // Full track
          isPreview: false,
        );

        final previewTrack = Song(
          id: 'skip-2',
          title: 'Preview Track',
          artist: 'Preview Artist',
          album: 'Album',
          duration: const Duration(seconds: 30),
          genre: 'Pop',
          imageUrl: '',
          gradientColors: const [],
          plays: '10K',
          lyrics: const [],
          audioUrl:
              'https://audio-ssl.itunes.apple.com/preview.m4a', // Preview status
          isPreview: true,
        );

        final locatingTrack = Song(
          id: 'skip-3',
          title: 'Locating Track',
          artist: 'Locating Artist',
          album: 'Album',
          duration: const Duration(minutes: 3),
          genre: 'Hip-Hop',
          imageUrl: '',
          gradientColors: const [],
          plays: '50M',
          lyrics: const [],
          audioUrl: '', // Locating status
          isPreview: false,
        );

        final burgis = Song(
          id: 'skip-4',
          title: 'Burgis',
          artist: 'Flow G, Hev Abi',
          album: 'Album',
          duration: const Duration(minutes: 3, seconds: 29),
          genre: 'Hip-Hop',
          imageUrl: '',
          gradientColors: const [],
          plays: '100M',
          lyrics: const [],
          audioUrl: 'https://rr.googlevideo.com/stream4', // Full track
          isPreview: false,
        );

        final queue = [
          lilKasalanan,
          babaero,
          previewTrack,
          locatingTrack,
          burgis,
        ];

        // Start by playing Lil Kasalanan Shortie (index 0)
        controller.playSongList(queue, startIndex: 0);
        expect(controller.currentIndex, 0);
        expect(controller.currentSong?.title, 'Lil Kasalanan Shortie');

        // Next track is Babaero (index 1, Full Track) -> MUST play Babaero, NOT skip it
        controller.next();
        expect(
          controller.currentIndex,
          1,
          reason:
              'Next track must strictly be Babaero because it is a full track',
        );
        expect(controller.currentSong?.title, 'Babaero');

        // Calling next() from Babaero:
        // skip-2 is PREVIEW -> skipped!
        // skip-3 is LOCATING -> skipped!
        // skip-4 is Burgis (Full Track) -> MUST land on Burgis (index 4)
        controller.next();
        expect(
          controller.currentIndex,
          4,
          reason:
              'Must skip preview track and locating track, advancing directly to Burgis',
        );
        expect(controller.currentSong?.title, 'Burgis');

        controller.pause();
        controller.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      },
    );
  });

  group('Bug 2: Spotify playlist persistence tests', () {
    test(
      'PlaylistPersistenceService persists and restores imported playlist and songs',
      () async {
        final playlist = MusicPlaylist(
          id: 'test-spotify-playlist-1',
          title: 'My Spotify Hits',
          subtitle: 'Imported from Spotify',
          gradient: const [Color(0xFF1DB954), Color(0xFF191414)],
          songIds: ['spot-t1', 'spot-t2'],
        );

        final songs = [
          Song(
            id: 'spot-t1',
            title: 'Hit Track 1',
            artist: 'Famous Artist',
            album: 'Album 1',
            duration: const Duration(minutes: 3, seconds: 20),
            genre: 'Pop',
            imageUrl: 'https://i.scdn.co/image/art1',
            gradientColors: const [],
            plays: '',
            lyrics: const ['Line 1', 'Line 2'],
            audioUrl: 'https://example.com/audio1.mp3',
            isPreview: false,
          ),
          Song(
            id: 'spot-t2',
            title: 'Hit Track 2',
            artist: 'Famous Artist 2',
            album: 'Album 2',
            duration: const Duration(minutes: 2, seconds: 50),
            genre: 'Pop',
            imageUrl: 'https://i.scdn.co/image/art2',
            gradientColors: const [],
            plays: '',
            lyrics: const [],
            audioUrl: '',
            isPreview: false,
          ),
        ];

        await PlaylistPersistenceService.instance.persistPlaylist(
          playlist: playlist,
          songs: songs,
          spotifyUrl:
              'https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M',
          userId: 'default_user',
        );

        // Verify retrieval for default_user
        final guestPlaylists = await LocalDatabase.instance
            .getImportedPlaylistsForUser('default_user');
        expect(guestPlaylists, hasLength(1));
        expect(guestPlaylists.first['title'], 'My Spotify Hits');
        expect((guestPlaylists.first['songs'] as List), hasLength(2));

        // Verify retrieval for authenticated user ID '3' (seamless access across user boundaries)
        final user3Playlists = await LocalDatabase.instance
            .getImportedPlaylistsForUser('3');
        expect(
          user3Playlists,
          hasLength(1),
          reason:
              'Playlists saved anonymously must be visible to logged in users',
        );
        expect(user3Playlists.first['title'], 'My Spotify Hits');
      },
    );

    test(
      'MusicPlayerController.importSpotifyTracksAsync persists and restores across new controller instance',
      () async {
        final controller1 = MusicPlayerController();

        const link = 'https://open.spotify.com/playlist/persistent123';
        final importResult = await controller1.importSpotifyTracksAsync(
          playlistName: 'Persistent Playlist',
          spotifyUrl: link,
          tracks: [
            SpotifyImportedTrack(
              spotifyId: 'track-pers-1',
              title: 'Track One',
              artist: 'Artist One',
              album: 'Album One',
              duration: const Duration(minutes: 3, seconds: 30),
              artworkUrl: 'https://example.com/cover.jpg',
              previewUrl: 'https://example.com/preview.mp3',
            ),
            SpotifyImportedTrack(
              spotifyId: 'track-pers-2',
              title: 'Track Two',
              artist: 'Artist Two',
              album: 'Album Two',
              duration: const Duration(minutes: 4),
              artworkUrl: 'https://example.com/cover2.jpg',
            ),
          ],
        );

        expect(importResult.addedCount, 2);
        expect(
          controller1.playlists.any((p) => p.title == 'Persistent Playlist'),
          isTrue,
        );
        controller1.dispose();

        // Simulate app restart by creating a new MusicPlayerController and calling loadSavedPlaylists
        final controller2 = MusicPlayerController();
        await controller2.loadSavedPlaylists();

        final reloadedPlaylist = controller2.playlistById(
          importResult.playlistId,
        );
        expect(
          reloadedPlaylist,
          isNotNull,
          reason: 'Imported playlist must persist across controller recreation',
        );
        expect(reloadedPlaylist!.title, 'Persistent Playlist');
        expect(reloadedPlaylist.songIds, hasLength(2));

        final song1 = controller2.allSongs.firstWhere(
          (s) => s.id == 'spotify-track-pers-1',
        );
        expect(song1.title, 'Track One');
        expect(song1.artist, 'Artist One');

        final song2 = controller2.allSongs.firstWhere(
          (s) => s.id == 'spotify-track-pers-2',
        );
        expect(song2.title, 'Track Two');
        expect(song2.isLocating, isTrue);

        controller2.dispose();
      },
    );

    test(
      'Re-importing a playlist whose title was previously deleted unmasks and displays it properly',
      () async {
        // 1. Mark a playlist title as deleted in settings
        await LocalDatabase.instance.setSetting(
          'deleted_playlist_rock hits',
          'true',
        );
        await LocalDatabase.instance.setSetting(
          'deleted_playlist_rock hits_default_user',
          'true',
        );
        await LocalDatabase.instance.setSetting(
          'deleted_playlist_rock hits_3',
          'true',
        );

        // 2. Import a new playlist with that title
        final controller = MusicPlayerController();
        final outcome = await controller.importSpotifyTracksAsync(
          playlistName: 'Rock Hits',
          tracks: [
            SpotifyImportedTrack(
              spotifyId: 'rock-track-1',
              title: 'Rock Anthem',
              artist: 'Rock Band',
              album: 'Rock Album',
              duration: const Duration(minutes: 3, seconds: 15),
            ),
          ],
        );

        expect(outcome.addedCount, 1);
        controller.dispose();

        // 3. Re-open app
        final newController = MusicPlayerController();
        await newController.loadSavedPlaylists();

        final restored = newController.playlistById(outcome.playlistId);
        expect(
          restored,
          isNotNull,
          reason:
              'Re-imported playlist must not be masked by past title deletion flags',
        );
        expect(restored!.title, 'Rock Hits');

        newController.dispose();
      },
    );
  });
}
