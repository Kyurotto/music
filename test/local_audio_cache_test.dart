import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music/data/local_database.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Local audio cache accounting', () {
    late Directory root;
    late Directory audioDir;
    late Directory artworkDir;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('pulse_cache_test_');
      audioDir = Directory(p.join(root.path, 'offline_audio'));
      artworkDir = Directory(
        p.join(root.path, 'legacy', 'pulse_music_offline'),
      );
      await audioDir.create(recursive: true);
      await artworkDir.create(recursive: true);
    });

    tearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    Future<File> writeFile(Directory dir, String name, int bytes) async {
      final file = File(p.join(dir.path, name));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(List<int>.filled(bytes, 0));
      return file;
    }

    test(
      'counts nested audio and artwork files across cache directories',
      () async {
        await writeFile(audioDir, 'track-a.m4a', 2048);
        await writeFile(audioDir, 'track-b.mp3', 1024);
        await writeFile(audioDir, 'track-a.jpg', 256);
        await writeFile(
          Directory(p.join(audioDir.path, 'nested')),
          'track-c.m4a',
          512,
        );
        await writeFile(artworkDir, 'legacy-track.m4a', 4096);

        final bytes = await LocalDatabase.getLocalAudioCacheSizeBytes(
          dirs: [audioDir, artworkDir],
        );

        expect(bytes, 2048 + 1024 + 256 + 512 + 4096);
      },
    );

    test('does not double count directories listed twice', () async {
      await writeFile(audioDir, 'track.m4a', 1000);

      final bytes = await LocalDatabase.getLocalAudioCacheSizeBytes(
        dirs: [audioDir, audioDir],
      );

      expect(bytes, 1000);
    });

    test('missing cache directory contributes zero bytes', () async {
      final missing = Directory(p.join(root.path, 'missing', 'offline_audio'));
      await writeFile(audioDir, 'track.m4a', 750);

      final bytes = await LocalDatabase.getLocalAudioCacheSizeBytes(
        dirs: [missing, audioDir],
      );

      expect(bytes, 750);
      expect(await missing.exists(), isFalse);
    });

    test(
      'clear deletes cached files, reports freed bytes, and bumps revision',
      () async {
        await writeFile(audioDir, 'track-a.m4a', 2048);
        await writeFile(audioDir, 'track-a.jpg', 256);
        await writeFile(
          Directory(p.join(audioDir.path, 'nested')),
          'track-b.mp3',
          1024,
        );
        await writeFile(artworkDir, 'legacy-track.m4a', 4096);
        final untouched = await writeFile(
          Directory(p.join(root.path, 'library')),
          'library.db',
          9999,
        );

        final before = LocalDatabase.audioCacheRevision.value;
        final freed = await LocalDatabase.clearLocalAudioCache(
          dirs: [audioDir, artworkDir],
        );

        expect(freed, 2048 + 256 + 1024 + 4096);
        expect(LocalDatabase.audioCacheRevision.value, before + 1);
        expect(
          await LocalDatabase.getLocalAudioCacheSizeBytes(
            dirs: [audioDir, artworkDir],
          ),
          0,
        );
        expect(await untouched.exists(), isTrue);
        expect(await untouched.length(), 9999);
        expect(await audioDir.exists(), isTrue);
        expect(await artworkDir.exists(), isTrue);
      },
    );
  });
}
