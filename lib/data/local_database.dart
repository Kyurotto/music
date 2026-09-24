import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Stores the music library, playlists, and user accounts on the device.
///
/// Audio files remain on disk; this database stores their metadata and paths.
class LocalDatabase {
  LocalDatabase._();

  static final LocalDatabase instance = LocalDatabase._();
  static const _databaseName = 'pulse_music.db';
  static const _databaseVersion = 4;

  Database? _database;

  @visibleForTesting
  static void setDatabaseForTesting(Database? db) {
    instance._database = db;
  }

  FirebaseAuth? get _auth {
    try {
      return FirebaseAuth.instance;
    } catch (_) {
      return null;
    }
  }

  FirebaseFirestore? get _firestore {
    try {
      return FirebaseFirestore.instance;
    } catch (_) {
      return null;
    }
  }

  Future<void> initialize() async {
    final db = await database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    await _createImportedPlaylistTables(db);
    await seedAdminUserIfNeeded();
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
        onUpgrade: _upgradeDatabase,
      ),
    );
    _database = openedDatabase;
    return openedDatabase;
  }

  DatabaseFactory _databaseFactoryForPlatform() {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return databaseFactoryFfi;
    }
    return databaseFactory;
  }

  @visibleForTesting
  Future<void> createAllTables(Database db) => _createDatabase(db, _databaseVersion);

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
    await _createAccountTables(database);
    await _createImportedPlaylistTables(database);
  }

  Future<void> _upgradeDatabase(Database database, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createAccountTables(database);
    }
    if (oldVersion < 3) {
      await _createEmployeeTable(database);
    }
    if (oldVersion < 4) {
      await _createImportedPlaylistTables(database);
    }
  }

  Future<void> _createImportedPlaylistTables(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS imported_playlists (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        title TEXT NOT NULL,
        subtitle TEXT,
        spotify_url TEXT,
        gradient_colors TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS imported_songs (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        artist TEXT NOT NULL,
        album TEXT,
        duration_ms INTEGER NOT NULL,
        image_url TEXT,
        audio_url TEXT,
        lyrics TEXT,
        genre TEXT,
        is_preview INTEGER NOT NULL DEFAULT 0,
        is_youtube_audio INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS imported_playlist_songs (
        playlist_id TEXT NOT NULL,
        song_id TEXT NOT NULL,
        position INTEGER NOT NULL,
        PRIMARY KEY (playlist_id, song_id),
        FOREIGN KEY (playlist_id) REFERENCES imported_playlists(id) ON DELETE CASCADE,
        FOREIGN KEY (song_id) REFERENCES imported_songs(id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _createAccountTables(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id TEXT PRIMARY KEY,
        email TEXT NOT NULL UNIQUE,
        display_name TEXT NOT NULL,
        photo_url TEXT,
        role TEXT NOT NULL DEFAULT 'user',
        auth_provider TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        last_login_at INTEGER NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS user_sessions (
        user_id TEXT PRIMARY KEY,
        saved_at INTEGER NOT NULL,
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS user_activity (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT NOT NULL,
        screen TEXT NOT NULL,
        track_title TEXT,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
      )
    ''');
    await _createEmployeeTable(database);
  }

  Future<void> _createEmployeeTable(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS employees (
        id TEXT PRIMARY KEY,
        user_id TEXT UNIQUE,
        employee_code TEXT NOT NULL UNIQUE,
        display_name TEXT NOT NULL,
        email TEXT NOT NULL UNIQUE,
        status TEXT NOT NULL DEFAULT 'active',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
      )
    ''');
  }

  Future<void> seedAdminUserIfNeeded() async {
    final db = await database;
    // Check if admin user with id 1 or email admin@pulsemusic.app exists
    final existingUsers = await db.query(
      'users',
      where: 'id = ? OR LOWER(email) = ?',
      whereArgs: ['1', 'admin@pulsemusic.app'],
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    if (existingUsers.isEmpty) {
      await db.insert(
        'users',
        {
          'id': '1',
          'email': 'admin@pulsemusic.app',
          'display_name': 'System Administrator',
          'photo_url': null,
          'role': 'admin',
          'auth_provider': 'password',
          'created_at': now,
          'last_login_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    final existingEmp = await db.query(
      'employees',
      where: 'id = ? OR user_id = ? OR employee_code = ?',
      whereArgs: ['1', '1', 'EMP-001'],
    );
    if (existingEmp.isEmpty) {
      await db.insert(
        'employees',
        {
          'id': '1',
          'user_id': '1',
          'employee_code': 'EMP-001',
          'display_name': 'System Administrator',
          'email': 'admin@pulsemusic.app',
          'status': 'active',
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<Map<String, Object?>?> getUserByEmail(String email) async {
    final db = await database;
    final results = await db.query(
      'users',
      where: 'LOWER(email) = ?',
      whereArgs: [email.trim().toLowerCase()],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  Future<Map<String, Object?>?> getUserById(String id) async {
    final db = await database;
    final results = await db.query(
      'users',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  Future<void> saveUser({
    required String id,
    required String email,
    required String displayName,
    String? photoUrl,
    String role = 'user',
    String authProvider = 'password',
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert(
      'users',
      {
        'id': id,
        'email': email.trim().toLowerCase(),
        'display_name': displayName.trim(),
        'photo_url': photoUrl,
        'role': role,
        'auth_provider': authProvider,
        'created_at': now,
        'last_login_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, Object?>>> getUsersByProvider(String provider) async {
    final db = await database;
    return db.query(
      'users',
      where: 'auth_provider = ?',
      whereArgs: [provider],
      orderBy: 'last_login_at DESC',
    );
  }

  /// Deletes one user row plus any session pointing at it. Best-effort.
  Future<void> deleteUser(String id) async {
    final db = await database;
    await db.delete('user_sessions', where: 'user_id = ?', whereArgs: [id]);
    await db.delete('users', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> saveActiveSession(String userId) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert(
      'user_sessions',
      {'user_id': userId, 'saved_at': now},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getActiveSessionUserId() async {
    final db = await database;
    final results = await db.query('user_sessions', orderBy: 'saved_at DESC', limit: 1);
    if (results.isNotEmpty) {
      return results.first['user_id'] as String?;
    }
    return null;
  }

  Future<void> clearActiveSession() async {
    final db = await database;
    await db.delete('user_sessions');
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

  Future<void> saveEmployee({
    required String employeeCode,
    required String displayName,
    required String email,
    String? userId,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert(
      'employees',
      {
        'id': userId ?? 'employee-$now',
        'user_id': userId,
        'employee_code': employeeCode.trim(),
        'display_name': displayName.trim(),
        'email': email.trim().toLowerCase(),
        'updated_at': now,
        'created_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, Object?>>> getEmployees() async {
    final db = await database;
    return db.query('employees', orderBy: 'employee_code COLLATE NOCASE ASC');
  }

  Future<void> saveSetting(String key, String value) async {
    final db = await database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    await db.insert(
      'app_settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getSetting(String key) async {
    final db = await database;
    final results = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (results.isNotEmpty) {
      return results.first['value'] as String?;
    }
    return null;
  }

  Future<Map<String, String>> getAllSettings() async {
    final db = await database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    final results = await db.query('app_settings');
    final map = <String, String>{};
    for (final row in results) {
      map[row['key'] as String] = row['value'] as String;
    }
    return map;
  }

  /// Persists an imported Spotify playlist and its songs associated with [userId].
  Future<void> saveImportedPlaylist({
    required String id,
    required String userId,
    required String title,
    String? subtitle,
    String? spotifyUrl,
    List<int>? gradientColors,
    required List<Map<String, dynamic>> songs,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      await txn.insert(
        'imported_playlists',
        {
          'id': id,
          'user_id': userId,
          'title': title,
          'subtitle': subtitle ?? 'Imported from Spotify',
          'spotify_url': spotifyUrl,
          'gradient_colors': gradientColors != null ? jsonEncode(gradientColors) : null,
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      for (var i = 0; i < songs.length; i++) {
        final song = songs[i];
        final songId = song['id'] as String;
        final lyrics = song['lyrics'];
        final String lyricsJson;
        if (lyrics is List) {
          lyricsJson = jsonEncode(lyrics);
        } else if (lyrics is String) {
          lyricsJson = lyrics;
        } else {
          lyricsJson = jsonEncode(<String>[]);
        }

        await txn.insert(
          'imported_songs',
          {
            'id': songId,
            'title': song['title'] as String? ?? 'Unknown Title',
            'artist': song['artist'] as String? ?? 'Unknown Artist',
            'album': song['album'] as String? ?? '',
            'duration_ms': song['duration_ms'] as int? ?? 180000,
            'image_url': song['image_url'] as String? ?? '',
            'audio_url': song['audio_url'] as String? ?? '',
            'lyrics': lyricsJson,
            'genre': song['genre'] as String? ?? 'Spotify',
            'is_preview': (song['is_preview'] == true || song['is_preview'] == 1) ? 1 : 0,
            'is_youtube_audio': (song['is_youtube_audio'] == true || song['is_youtube_audio'] == 1) ? 1 : 0,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        await txn.insert(
          'imported_playlist_songs',
          {
            'playlist_id': id,
            'song_id': songId,
            'position': i,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });

    _syncImportedPlaylistToFirestore(
      userId: userId,
      playlistId: id,
      title: title,
      subtitle: subtitle,
      spotifyUrl: spotifyUrl,
      songs: songs,
    );
  }

  /// Updates an imported song when audio or lyrics enrichment finishes.
  Future<void> updateImportedSong({
    required String id,
    String? audioUrl,
    bool? isPreview,
    bool? isYouTubeAudio,
    int? durationMs,
    String? imageUrl,
    List<String>? lyrics,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final values = <String, Object?>{
      'updated_at': now,
    };
    if (audioUrl != null) values['audio_url'] = audioUrl;
    if (isPreview != null) values['is_preview'] = isPreview ? 1 : 0;
    if (isYouTubeAudio != null) values['is_youtube_audio'] = isYouTubeAudio ? 1 : 0;
    if (durationMs != null) values['duration_ms'] = durationMs;
    if (imageUrl != null) values['image_url'] = imageUrl;
    if (lyrics != null) values['lyrics'] = jsonEncode(lyrics);

    await db.update(
      'imported_songs',
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Retrieves all imported playlists and their tracks belonging to [userId].
  Future<List<Map<String, dynamic>>> getImportedPlaylistsForUser(String userId) async {
    final db = await database;
    final isDefaultUser = userId == '1' || userId == 'default_user';
    final playlists = await db.query(
      'imported_playlists',
      where: isDefaultUser ? 'user_id = ? OR user_id = ?' : 'user_id = ?',
      whereArgs: isDefaultUser ? [userId, 'default_user'] : [userId],
      orderBy: 'created_at ASC',
    );

    final results = <Map<String, dynamic>>[];
    for (final playlist in playlists) {
      final playlistId = playlist['id'] as String;
      final songRows = await db.rawQuery('''
        SELECT s.*, ps.position
        FROM imported_songs s
        INNER JOIN imported_playlist_songs ps ON s.id = ps.song_id
        WHERE ps.playlist_id = ?
        ORDER BY ps.position ASC
      ''', [playlistId]);

      final songs = songRows.map((row) {
        List<String> lyricsList = [];
        final rawLyrics = row['lyrics'] as String?;
        if (rawLyrics != null && rawLyrics.isNotEmpty) {
          try {
            final decoded = jsonDecode(rawLyrics);
            if (decoded is List) {
              lyricsList = decoded.map((e) => e.toString()).toList();
            }
          } catch (_) {
            lyricsList = rawLyrics.split('\n');
          }
        }

        return <String, dynamic>{
          'id': row['id'] as String,
          'title': row['title'] as String,
          'artist': row['artist'] as String,
          'album': row['album'] as String? ?? '',
          'duration_ms': row['duration_ms'] as int? ?? 180000,
          'image_url': row['image_url'] as String? ?? '',
          'audio_url': row['audio_url'] as String? ?? '',
          'lyrics': lyricsList,
          'genre': row['genre'] as String? ?? 'Spotify',
          'is_preview': (row['is_preview'] as int? ?? 0) == 1,
          'is_youtube_audio': (row['is_youtube_audio'] as int? ?? 0) == 1,
        };
      }).toList();

      List<int>? gradientColors;
      final rawColors = playlist['gradient_colors'] as String?;
      if (rawColors != null && rawColors.isNotEmpty) {
        try {
          final decoded = jsonDecode(rawColors);
          if (decoded is List) {
            gradientColors = decoded.map((e) => (e as num).toInt()).toList();
          }
        } catch (_) {}
      }

      results.add({
        'id': playlistId,
        'user_id': playlist['user_id'] as String,
        'title': playlist['title'] as String,
        'subtitle': playlist['subtitle'] as String? ?? 'Imported from Spotify',
        'spotify_url': playlist['spotify_url'] as String?,
        'gradient_colors': gradientColors,
        'created_at': playlist['created_at'] as int,
        'songs': songs,
      });
    }

    return results;
  }

  /// Deletes an imported playlist and its track associations.
  Future<void> deleteImportedPlaylist(String playlistId) async {
    final db = await database;
    await db.delete(
      'imported_playlist_songs',
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
    );
    await db.delete(
      'imported_playlists',
      where: 'id = ?',
      whereArgs: [playlistId],
    );
  }

  /// Reassigns any playlists imported anonymously to the newly signed-in user.
  Future<void> claimAnonymousPlaylists(String newUserId) async {
    if (newUserId.isEmpty || newUserId == '1' || newUserId == 'default_user') return;
    try {
      final db = await database;
      await db.update(
        'imported_playlists',
        {'user_id': newUserId},
        where: 'user_id = ? OR user_id = ?',
        whereArgs: ['1', 'default_user'],
      );
    } catch (_) {}
  }

  void _syncImportedPlaylistToFirestore({
    required String userId,
    required String playlistId,
    required String title,
    String? subtitle,
    String? spotifyUrl,
    required List<Map<String, dynamic>> songs,
  }) {
    try {
      final firestore = _firestore;
      final auth = _auth;
      if (firestore == null || auth == null) return;
      final user = auth.currentUser;
      if (user == null || user.uid != userId) return;

      firestore
          .collection('users')
          .doc(userId)
          .collection('imported_playlists')
          .doc(playlistId)
          .set({
        'id': playlistId,
        'title': title,
        'subtitle': subtitle ?? 'Imported from Spotify',
        'spotify_url': spotifyUrl,
        'updated_at': FieldValue.serverTimestamp(),
        'tracks': songs.map((s) => {
          'id': s['id'],
          'title': s['title'],
          'artist': s['artist'],
          'album': s['album'],
          'duration_ms': s['duration_ms'],
          'image_url': s['image_url'],
          'audio_url': s['audio_url'],
          'lyrics': s['lyrics'],
          'genre': s['genre'],
          'is_preview': s['is_preview'],
          'is_youtube_audio': s['is_youtube_audio'],
        }).toList(),
      }, SetOptions(merge: true)).catchError((e) {
        debugPrint('[LocalDatabase] Firestore playlist sync skipped: $e');
      });
    } catch (_) {}
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
