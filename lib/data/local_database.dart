import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Stores the music library and playlists on the device.
///
/// Audio files remain on disk; this database stores their metadata and paths.
class LocalDatabase {
  LocalDatabase._();

  static final LocalDatabase instance = LocalDatabase._();
  static const _databaseName = 'pulse_music.db';
  static const _databaseVersion = 1;

  Database? _database;

  Future<void> initialize() async {
    await database;
  }

  Future<Database> get database async {
    final existingDatabase = _database;
    if (existingDatabase != null) return existingDatabase;

    if (kIsWeb) {
      throw UnsupportedError('SQLite is not available on web builds.');
    }

    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);

    final factory = _databaseFactoryForPlatform();
    final openedDatabase = await factory.openDatabase(
      path.join(directory.path, _databaseName),
      options: OpenDatabaseOptions(
        version: _databaseVersion,
        onCreate: _createDatabase,
      ),
    );
    _database = openedDatabase;
    return openedDatabase;
  }

  DatabaseFactory _databaseFactoryForPlatform() {
    // On desktop, main() already called sqfliteFfiInit() and set
    // databaseFactory = databaseFactoryFfi, so we can always use databaseFactory.
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return databaseFactoryFfi;
    }
    return databaseFactory;
  }

  Future<void> _createDatabase(Database database, int version) async {
    await database.execute('''
      CREATE TABLE tracks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        artist TEXT,
        album TEXT,
        duration_ms INTEGER,
        file_path TEXT NOT NULL UNIQUE,
        artwork_path TEXT,
        added_at INTEGER NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE playlists (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        created_at INTEGER NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE playlist_tracks (
        playlist_id INTEGER NOT NULL,
        track_id INTEGER NOT NULL,
        position INTEGER NOT NULL,
        PRIMARY KEY (playlist_id, track_id),
        FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE,
        FOREIGN KEY (track_id) REFERENCES tracks(id) ON DELETE CASCADE
      )
    ''');
  }

  Future<int> saveTrack({
    required String title,
    required String filePath,
    String? artist,
    String? album,
    int? durationMs,
    String? artworkPath,
  }) async {
    final db = await database;
    return db.insert('tracks', {
      'title': title,
      'artist': artist,
      'album': album,
      'duration_ms': durationMs,
      'file_path': filePath,
      'artwork_path': artworkPath,
      'added_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, Object?>>> getTracks() async {
    final db = await database;
    return db.query('tracks', orderBy: 'title COLLATE NOCASE ASC');
  }

  Future<int> createPlaylist(String name) async {
    final db = await database;
    return db.insert('playlists', {
      'name': name,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> addTrackToPlaylist({
    required int playlistId,
    required int trackId,
  }) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COALESCE(MAX(position), -1) + 1 AS next_position '
      'FROM playlist_tracks WHERE playlist_id = ?',
      [playlistId],
    );
    await db.insert('playlist_tracks', {
      'playlist_id': playlistId,
      'track_id': trackId,
      'position': result.first['next_position'] as int,
    });
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
