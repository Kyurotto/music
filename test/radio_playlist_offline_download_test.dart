import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music/auth/auth_service.dart';
import 'package:music/controllers/music_player_controller.dart';
import 'package:music/data/local_database.dart';
import 'package:music/models/song_model.dart';
import 'package:music/services/radio_discovery_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Database db;
  late Directory cacheDir;
  final createdFiles = <File>[];

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    LocalDatabase.setDatabaseForTesting(db);
    await LocalDatabase.instance.createAllTables(db);
    await LocalDatabase.instance.initialize();

    // path_provider is unavailable in widget tests, so the controller falls
    // back to this directory. Keeping test files here exercises the same
    // fallback lookup path used on a device without app-support access.
    cacheDir = Directory(
      p.join(Directory.systemTemp.path, 'pulse_music_offline'),
    );
    await cacheDir.create(recursive: true);
  });

  tearDown(() async {
    for (final file in createdFiles) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    await db.close();
    LocalDatabase.setDatabaseForTesting(null);
  });

  Song radioSong(
    String id,
    String title, {
    String audioUrl = '',
    bool isPreview = false,
  }) {
    return Song(
      id: id,
      title: title,
      artist: 'Test Artist',
      album: 'Test Album',
      duration: const Duration(minutes: 3),
      genre: 'Radio',
      imageUrl: 'https://example.com/art.jpg',
      gradientColors: const [],
      plays: '1.2M',
      lyrics: const [],
      audioUrl: audioUrl,
      isPreview: isPreview,
    );
  }

  test(
    'radio playlist download persists its songs and relinks audio offline',
    () async {
      const stationId = 'radio-test-artist';
      final downloaded = radioSong('radio-dyn-downloaded', 'Downloaded Track');
      final pending = radioSong(
        'radio-dyn-pending',
        'Pending Track',
        audioUrl: 'https://example.com/pending.mp3',
      );

      // A short full track (below the legacy 1.6MB preview cutoff) stored with
      // a WebM container, matching what YouTube usually returns.
      final audioFile = File(p.join(cacheDir.path, '${downloaded.id}.webm'));
      createdFiles.add(audioFile);
      await audioFile.writeAsBytes(List<int>.filled(60000, 7), flush: true);

      await LocalDatabase.instance.ensureImportedSong(
        id: downloaded.id,
        title: downloaded.title,
        artist: downloaded.artist,
        album: downloaded.album,
        durationMs: downloaded.duration.inMilliseconds,
        imageUrl: downloaded.imageUrl,
      );
      await LocalDatabase.instance.updateImportedSong(
        id: downloaded.id,
        audioUrl: audioFile.path,
        isPreview: false,
        isYouTubeAudio: false,
        durationMs: downloaded.duration.inMilliseconds,
        imageUrl: downloaded.imageUrl,
        lyrics: downloaded.lyrics,
      );

      final userId = AuthService.instance.currentUserId.isEmpty
          ? 'default_user'
          : AuthService.instance.currentUserId;

      final controller = MusicPlayerController();
      final playlist = MusicPlaylist(
        id: stationId,
        title: 'Test Artist Radio',
        subtitle: 'Popular tracks and recommendations',
        gradient: const [],
        songIds: [downloaded.id, pending.id],
      );

      final available = await controller.downloadPlaylistSong(
        downloaded,
        playlist: playlist,
        songs: [downloaded, pending],
      );

      expect(available, isTrue);
      expect(controller.isSongDownloaded(downloaded.id), isTrue);

      // saveImportedPlaylistOffline uses INSERT OR REPLACE, so the persisted
      // row must keep pointing at the downloaded file rather than the network
      // URL held by the in-memory song.
      final row = await LocalDatabase.instance.getImportedSong(downloaded.id);
      expect(row, isNotNull);
      expect(row!['audio_url'], audioFile.path);
      expect(row['is_preview'], 0);

      final savedPlaylists = await LocalDatabase.instance
          .getImportedPlaylistsForUser(userId);
      final saved = savedPlaylists.firstWhere((p) => p['id'] == stationId);
      final savedSongs = (saved['songs'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(
        savedSongs.map((s) => s['id']).toSet(),
        containsAll(<String>[downloaded.id, pending.id]),
      );
      final savedDownloaded = savedSongs.firstWhere(
        (s) => s['id'] == downloaded.id,
      );
      expect(savedDownloaded['audio_url'], audioFile.path);
      expect(savedDownloaded['is_preview'], isFalse);

      controller.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Simulate an app restart: a fresh controller restores the ephemeral
      // radio playlist from SQLite and finds the downloaded file on disk.
      final restarted = MusicPlayerController();
      await restarted.loadSavedPlaylists(userId: userId);

      final restored = restarted.playlistById(stationId);
      expect(restored, isNotNull);
      expect(
        restored!.songIds.toSet(),
        containsAll(<String>[downloaded.id, pending.id]),
      );

      final restoredSong = restarted.songById(downloaded.id);
      expect(restoredSong, isNotNull);
      expect(restoredSong!.audioUrl, audioFile.path);
      expect(restoredSong.isPreview, isFalse);
      expect(restarted.isSongDownloaded(downloaded.id), isTrue);

      restarted.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    },
  );

  test(
    'artist radio playlist download persists artist- prefixed playlist and songs',
    () async {
      const stationId = 'artist-sugarfree';
      final song1 = Song(
        id: 'artist-sugarfree-1',
        title: 'Hari ng Sablay',
        artist: 'Sugarfree',
        album: 'Sa Wakas',
        duration: const Duration(minutes: 4, seconds: 32),
        genre: 'OPM',
        imageUrl: 'https://example.com/art.jpg',
        gradientColors: const [],
        plays: '42.3M',
        lyrics: const [],
        isPreview: false,
      );
      final song2 = Song(
        id: 'artist-sugarfree-2',
        title: 'Burnout',
        artist: 'Sugarfree',
        album: 'Sa Wakas',
        duration: const Duration(minutes: 4, seconds: 15),
        genre: 'OPM',
        imageUrl: 'https://example.com/art.jpg',
        gradientColors: const [],
        plays: '78.5M',
        lyrics: const [],
        isPreview: false,
      );

      final audioFile1 = File(p.join(cacheDir.path, '${song1.id}.webm'));
      createdFiles.add(audioFile1);
      await audioFile1.writeAsBytes(List<int>.filled(50000, 1), flush: true);

      final audioFile2 = File(p.join(cacheDir.path, '${song2.id}.webm'));
      createdFiles.add(audioFile2);
      await audioFile2.writeAsBytes(List<int>.filled(55000, 2), flush: true);

      final userId = AuthService.instance.currentUserId.isEmpty
          ? 'default_user'
          : AuthService.instance.currentUserId;

      final controller = MusicPlayerController();
      final playlist = MusicPlaylist(
        id: stationId,
        title: 'Sugarfree Radio',
        subtitle: 'Popular tracks and recommendations',
        gradient: const [],
        songIds: [song1.id, song2.id],
      );

      await controller.downloadPlaylistSongs(
        [song1, song2],
        playlist: playlist,
        title: 'Sugarfree Radio',
        subtitle: 'Popular tracks and recommendations',
      );

      // Verify playlist was saved to local SQLite
      final savedPlaylists = await LocalDatabase.instance
          .getImportedPlaylistsForUser(userId);
      final saved = savedPlaylists.firstWhere(
        (p) => p['id'] == stationId,
        orElse: () => <String, dynamic>{},
      );
      expect(saved.isNotEmpty, isTrue);
      expect(saved['title'], 'Sugarfree Radio');

      final savedSongs = (saved['songs'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(savedSongs.length, 2);
      expect(savedSongs.map((s) => s['id']), containsAll([song1.id, song2.id]));

      // Both songs should be recognized as downloaded
      expect(controller.isSongDownloaded(song1.id), isTrue);
      expect(controller.isSongDownloaded(song2.id), isTrue);

      controller.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    },
  );

  test(
    'downloadPlaylistWithWorkers downloads songs using 3 workers and progressively saves to SQLite',
    () async {
      const stationId = 'worker-test-playlist';
      final songs = List.generate(
        6,
        (i) => Song(
          id: 'spotify-worker-track-$i',
          title: 'Worker Track $i',
          artist: 'Worker Artist',
          album: 'Worker Album',
          duration: const Duration(minutes: 3, seconds: 10),
          genre: 'Pop',
          imageUrl: 'https://example.com/art$i.jpg',
          gradientColors: const [],
          plays: '1.0M',
          lyrics: const [],
          isPreview: false,
        ),
      );

      // Pre-create the offline cached audio files for these tracks so downloadSong succeeds immediately
      for (final s in songs) {
        final audioFile = File(p.join(cacheDir.path, '${s.id}.webm'));
        createdFiles.add(audioFile);
        await audioFile.writeAsBytes(List<int>.filled(55000, 3), flush: true);

        await LocalDatabase.instance.ensureImportedSong(
          id: s.id,
          title: s.title,
          artist: s.artist,
          album: s.album,
          durationMs: s.duration.inMilliseconds,
          imageUrl: s.imageUrl,
        );
      }

      final controller = MusicPlayerController();
      final playlist = MusicPlaylist(
        id: stationId,
        title: '3-Worker Playlist',
        subtitle: 'Concurrent download test',
        gradient: const [],
        songIds: songs.map((s) => s.id).toList(),
      );

      final available = await controller.downloadPlaylistWithWorkers(
        songs,
        playlist: playlist,
        title: '3-Worker Playlist',
        subtitle: 'Concurrent download test',
        workerCount: 3,
      );

      expect(available, 6);
      for (final s in songs) {
        expect(controller.isSongDownloaded(s.id), isTrue);
      }

      // Verify that all songs and playlist are stored in SQLite
      final userId = AuthService.instance.currentUserId.isEmpty
          ? 'default_user'
          : AuthService.instance.currentUserId;
      final savedPlaylists = await LocalDatabase.instance
          .getImportedPlaylistsForUser(userId);
      final saved = savedPlaylists.firstWhere((p) => p['id'] == stationId);
      expect(saved, isNotNull);
      final savedSongs = (saved['songs'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(savedSongs.length, 6);
      for (final s in savedSongs) {
        expect(s['audio_url'], contains('.webm'));
        expect(s['is_preview'], isFalse);
      }

      controller.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    },
  );

  test(
    'fastImportRadioStation triggers auto-download and persists radio playlist for offline mode',
    () async {
      final radioSongs = [
        Song(
          id: 'radio-import-1',
          title: 'Import Song 1',
          artist: 'Radio Artist',
          album: 'Radio Album',
          duration: const Duration(minutes: 3),
          genre: 'Rock',
          imageUrl: '',
          gradientColors: const [],
          plays: '500K',
          lyrics: const [],
          isPreview: false,
        ),
        Song(
          id: 'radio-import-2',
          title: 'Import Song 2',
          artist: 'Radio Artist',
          album: 'Radio Album',
          duration: const Duration(minutes: 4),
          genre: 'Rock',
          imageUrl: '',
          gradientColors: const [],
          plays: '600K',
          lyrics: const [],
          isPreview: false,
        ),
      ];

      for (final s in radioSongs) {
        final audioFile = File(p.join(cacheDir.path, '${s.id}.webm'));
        createdFiles.add(audioFile);
        await audioFile.writeAsBytes(List<int>.filled(60000, 4), flush: true);
      }

      final station = RadioStation(
        id: 'station-fast-import',
        title: 'Fast Import Station',
        artistName: 'Radio Artist',
        subtitle: 'Station for import testing',
        backgroundColor: const Color(0xFF1E3A8A),
        gradientColors: const [Color(0xFF1E3A8A), Color(0xFF3B82F6)],
        songs: radioSongs,
      );

      final controller = MusicPlayerController();
      expect(controller.autoDownloadOnImport, isTrue);

      final importedPl = controller.fastImportRadioStation(station);
      expect(importedPl.title, 'Fast Import Station');

      // Wait a short moment for 3-worker download and SQLite persistence to complete
      await Future<void>.delayed(const Duration(milliseconds: 400));

      final userId = AuthService.instance.currentUserId.isEmpty
          ? 'default_user'
          : AuthService.instance.currentUserId;
      final savedPlaylists = await LocalDatabase.instance
          .getImportedPlaylistsForUser(userId);
      final saved = savedPlaylists.firstWhere(
        (p) => p['title'] == 'Fast Import Station',
        orElse: () => <String, dynamic>{},
      );
      expect(saved.isNotEmpty, isTrue);

      controller.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    },
  );

  test(
    'autoDownloadExploreRadios automatically queues and downloads Explore stations with 3 workers',
    () async {
      final songs1 = [
        Song(
          id: 'radio-explore-auto-1',
          title: 'Explore Song 1',
          artist: 'Explore Artist 1',
          album: 'Explore Album 1',
          duration: const Duration(minutes: 3),
          genre: 'Pop',
          imageUrl: '',
          gradientColors: const [],
          plays: '1M',
          lyrics: const [],
          isPreview: false,
        ),
      ];
      final songs2 = [
        Song(
          id: 'radio-explore-auto-2',
          title: 'Explore Song 2',
          artist: 'Explore Artist 2',
          album: 'Explore Album 2',
          duration: const Duration(minutes: 3),
          genre: 'Pop',
          imageUrl: '',
          gradientColors: const [],
          plays: '2M',
          lyrics: const [],
          isPreview: false,
        ),
      ];

      for (final s in [...songs1, ...songs2]) {
        final audioFile = File(p.join(cacheDir.path, '${s.id}.webm'));
        createdFiles.add(audioFile);
        await audioFile.writeAsBytes(List<int>.filled(52000, 5), flush: true);
      }

      final station1 = RadioStation(
        id: 'station-explore-1',
        title: 'Explore Station 1',
        artistName: 'Explore Artist 1',
        subtitle: 'Auto download test station 1',
        backgroundColor: const Color(0xFF1E3A8A),
        gradientColors: const [Color(0xFF1E3A8A), Color(0xFF3B82F6)],
        songs: songs1,
      );
      final station2 = RadioStation(
        id: 'station-explore-2',
        title: 'Explore Station 2',
        artistName: 'Explore Artist 2',
        subtitle: 'Auto download test station 2',
        backgroundColor: const Color(0xFF0F766E),
        gradientColors: const [Color(0xFF0F766E), Color(0xFF14B8A6)],
        songs: songs2,
      );

      final controller = MusicPlayerController();
      controller.autoDownloadExploreRadios([station1, station2]);

      // Give 3 workers a brief moment to process the downloads and persist SQLite
      await Future<void>.delayed(const Duration(milliseconds: 350));

      final userId = AuthService.instance.currentUserId.isEmpty
          ? 'default_user'
          : AuthService.instance.currentUserId;
      final savedPlaylists = await LocalDatabase.instance
          .getImportedPlaylistsForUser(userId);

      final saved1 = savedPlaylists.firstWhere(
        (p) => p['id'] == 'radio-station-explore-1',
        orElse: () => <String, dynamic>{},
      );
      final saved2 = savedPlaylists.firstWhere(
        (p) => p['id'] == 'radio-station-explore-2',
        orElse: () => <String, dynamic>{},
      );

      expect(saved1.isNotEmpty, isTrue);
      expect(saved2.isNotEmpty, isTrue);
      expect(controller.isSongDownloaded('radio-explore-auto-1'), isTrue);
      expect(controller.isSongDownloaded('radio-explore-auto-2'), isTrue);

      controller.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    },
  );

  test('RadioDiscoveryService fallback stations provide non-empty downloadable songs', () {
    final service = RadioDiscoveryService();
    final opmRadios = service.getOpmRadios();
    expect(opmRadios.isNotEmpty, isTrue);
    for (final radio in opmRadios) {
      expect(radio.songs.isNotEmpty, isTrue, reason: 'Station ${radio.id} should have fallback songs');
      for (final s in radio.songs) {
        expect(s.id.startsWith('radio-'), isTrue);
        expect(s.title.isNotEmpty, isTrue);
        expect(s.artist.isNotEmpty, isTrue);
      }
    }

    final globalRadios = service.getGlobalRadios();
    expect(globalRadios.isNotEmpty, isTrue);
    for (final radio in globalRadios) {
      expect(radio.songs.isNotEmpty, isTrue, reason: 'Station ${radio.id} should have fallback songs');
      for (final s in radio.songs) {
        expect(s.id.startsWith('radio-'), isTrue);
        expect(s.title.isNotEmpty, isTrue);
        expect(s.artist.isNotEmpty, isTrue);
      }
    }
  });

  test(
    'Explore radio stations stay strictly in Explored and do not display in Library',
    () async {
      final controller = MusicPlayerController();
      final initialLibraryCount = controller.libraryPlaylists.length;

      final radioStation = RadioDiscoveryService.instance.getPopularRadios().first;
      final radioPlaylist = radioStation.toPlaylist();
      expect(radioPlaylist.id.startsWith('radio-'), isTrue);

      // Pre-create offline cached files so download completes instantly in unit tests
      for (final s in radioStation.songs) {
        final audioFile = File(p.join(cacheDir.path, '${s.id}.webm'));
        createdFiles.add(audioFile);
        await audioFile.writeAsBytes(List<int>.filled(55000, 3), flush: true);

        await LocalDatabase.instance.ensureImportedSong(
          id: s.id,
          title: s.title,
          artist: s.artist,
          album: s.album,
          durationMs: s.duration.inMilliseconds,
          imageUrl: s.imageUrl,
        );
      }

      // Download songs for the Explore radio station
      await controller.downloadPlaylistSongs(
        radioStation.songs,
        playlist: radioPlaylist,
        title: radioStation.title,
        subtitle: radioStation.subtitle,
      );

      // Verify radio playlist is NOT in libraryPlaylists or controller.playlists
      expect(
        controller.libraryPlaylists.any((p) => p.id == radioPlaylist.id),
        isFalse,
      );
      expect(
        controller.playlists.any((p) => p.id == radioPlaylist.id),
        isFalse,
      );
      expect(controller.libraryPlaylists.length, initialLibraryCount);

      // Verify it is accessible via playlistById or exploreRadioPlaylists
      expect(controller.playlistById(radioPlaylist.id), isNotNull);
      expect(
        controller.exploreRadioPlaylists.any((p) => p.id == radioPlaylist.id),
        isTrue,
      );

      // Songs should still be added to allSongs and playable offline
      for (final s in radioStation.songs) {
        expect(controller.songById(s.id), isNotNull);
      }

      // Simulate restart
      final userId = AuthService.instance.currentUserId.isEmpty
          ? 'default_user'
          : AuthService.instance.currentUserId;
      final restarted = MusicPlayerController();
      await restarted.loadSavedPlaylists(userId: userId);

      expect(
        restarted.libraryPlaylists.any((p) => p.id == radioPlaylist.id),
        isFalse,
      );
      expect(
        restarted.playlists.any((p) => p.id == radioPlaylist.id),
        isFalse,
      );
      expect(restarted.playlistById(radioPlaylist.id), isNotNull);

      controller.dispose();
      restarted.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    },
  );
}
