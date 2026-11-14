import 'package:flutter_test/flutter_test.dart';
import 'package:music/controllers/music_player_controller.dart';
import 'package:music/data/local_database.dart';
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

  group('Listening history', () {
    test('records plays, aggregates stats, and keeps Recents unique', () async {
      const userId = 'listener-1';
      final firstStart = DateTime(2026, 11, 10, 19, 30);
      final secondStart = DateTime(2026, 11, 11, 8, 15);

      final firstId = await LocalDatabase.instance.recordListeningStart(
        userId: userId,
        songId: 'song-a',
        title: 'First Song',
        artist: 'Artist One',
        album: 'Album One',
        imageUrl: 'https://example.com/a.jpg',
        startedAt: firstStart,
      );
      await LocalDatabase.instance.finishListeningEntry(
        id: firstId,
        listenedSeconds: 180,
        completed: true,
      );

      final secondId = await LocalDatabase.instance.recordListeningStart(
        userId: userId,
        songId: 'song-a',
        title: 'First Song',
        artist: 'Artist One',
        album: 'Album One',
        imageUrl: 'https://example.com/a.jpg',
        startedAt: secondStart,
      );
      await LocalDatabase.instance.finishListeningEntry(
        id: secondId,
        listenedSeconds: 60,
        completed: false,
      );

      final thirdId = await LocalDatabase.instance.recordListeningStart(
        userId: userId,
        songId: 'song-b',
        title: 'Second Song',
        artist: 'Artist Two',
        startedAt: secondStart.add(const Duration(hours: 1)),
      );
      await LocalDatabase.instance.finishListeningEntry(
        id: thirdId,
        listenedSeconds: 90,
        completed: true,
      );

      // Another account must never see these plays.
      final otherId = await LocalDatabase.instance.recordListeningStart(
        userId: 'listener-2',
        songId: 'song-c',
        title: 'Other Song',
        artist: 'Other Artist',
      );
      await LocalDatabase.instance.finishListeningEntry(
        id: otherId,
        listenedSeconds: 30,
        completed: true,
      );

      final stats = await LocalDatabase.instance.getListeningStats(
        userId: userId,
      );
      expect(stats.totalPlays, 3);
      expect(stats.uniqueSongs, 2);
      expect(stats.uniqueArtists, 2);
      expect(stats.completedPlays, 2);
      expect(stats.totalListenedSeconds, 330);
      expect(stats.topSongs.first.title, 'First Song');
      expect(stats.topSongs.first.plays, 2);
      expect(stats.topSongs.first.listenedSeconds, 240);
      expect(stats.topArtists.length, 2);

      final recents = await LocalDatabase.instance.getRecentListening(
        userId: userId,
      );
      expect(recents.length, 2, reason: 'Recents shows one row per song');
      expect(recents.first.songId, 'song-b');
      expect(recents.last.songId, 'song-a');
      expect(recents.last.startedAt, secondStart);
      expect(recents.last.imageUrl, 'https://example.com/a.jpg');

      await LocalDatabase.instance.clearListeningHistory(userId: userId);
      final cleared = await LocalDatabase.instance.getListeningStats(
        userId: userId,
      );
      expect(cleared.totalPlays, 0);
      final otherStats = await LocalDatabase.instance.getListeningStats(
        userId: 'listener-2',
      );
      expect(otherStats.totalPlays, 1);
    });

    test('limits and orders Recents newest first', () async {
      const userId = 'listener-1';
      for (var i = 0; i < 5; i++) {
        final id = await LocalDatabase.instance.recordListeningStart(
          userId: userId,
          songId: 'song-$i',
          title: 'Song $i',
          artist: 'Artist',
          startedAt: DateTime(2026, 11, 10 + i, 12),
        );
        await LocalDatabase.instance.finishListeningEntry(
          id: id,
          listenedSeconds: 30,
          completed: false,
        );
      }

      final recents = await LocalDatabase.instance.getRecentListening(
        userId: userId,
        limit: 3,
      );
      expect(recents.map((entry) => entry.songId).toList(), [
        'song-4',
        'song-3',
        'song-2',
      ]);
    });
  });

  group('Data Saver Mode', () {
    test(
      'loads from settings and caps effective bitrates at 96 kbps',
      () async {
        await LocalDatabase.instance.saveSetting(
          MusicPlayerController.dataSaverModeSettingKey,
          'true',
        );
        final controller = MusicPlayerController();
        addTearDown(controller.dispose);

        await controller.loadSavedPlaylists(userId: 'listener-1');

        expect(controller.dataSaverMode, isTrue);
        expect(controller.effectiveStreamingQualityKbps, 96);
        expect(controller.effectiveDownloadQualityKbps, 96);

        controller.setDataSaverMode(false, save: false);
        expect(controller.dataSaverMode, isFalse);
        expect(controller.effectiveStreamingQualityKbps, isNotNull);
        expect(controller.effectiveStreamingQualityKbps, isNot(96));
      },
    );

    test('persists toggles to app_settings', () async {
      final controller = MusicPlayerController();
      addTearDown(controller.dispose);

      controller.setDataSaverMode(true);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        await LocalDatabase.instance.getSetting(
          MusicPlayerController.dataSaverModeSettingKey,
        ),
        'true',
      );

      controller.setDataSaverMode(false);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        await LocalDatabase.instance.getSetting(
          MusicPlayerController.dataSaverModeSettingKey,
        ),
        'false',
      );
    });
  });
}
