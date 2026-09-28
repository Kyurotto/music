import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
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
  static const _databaseVersion = 5;

  /// Sentinel user IDs that represent anonymous / guest ownership.
  /// Real user IDs must never collide with these values.
  static const guestUserIds = {'default_user', '1'};

  Database? _database;
  String? _databaseFilePath;
  String? get databaseFilePath => _databaseFilePath;

  @visibleForTesting
  static void setDatabaseForTesting(Database? db) {
    instance._database = db;
  }

  Future<void> _syncToWorkspace() async {
    // Synchronization of database files to external/workspace destinations or cleartext HTTP
    // has been removed for security: database files containing password hashes and sessions
    // must remain strictly isolated within the app's sandboxed storage.
  }

  Future<void> syncToWorkspace() => _syncToWorkspace();

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
    // No more default admin seed. New accounts (e.g. John Laurence) become
    // the active user instead of "System Administrator".
    await removeDefaultAdminIfSeeded();
    await removeGenericPlaceholderUsers();
    await seedEmployeeIfNeeded();
    _syncToWorkspace();
  }

  /// Removes any fake auto-generated placeholder rows like 'google.user...' or 'facebook.user...'
  /// so that only purely real accounts exist in SQLite.
  Future<void> removeGenericPlaceholderUsers() async {
    try {
      final db = await database;
      final placeholders = await db.query(
        'users',
        columns: ['id'],
        where: "LOWER(email) LIKE 'google.user%' OR LOWER(email) LIKE 'facebook.user%' OR LOWER(display_name) LIKE 'google.user%' OR LOWER(display_name) LIKE 'facebook.user%'",
      );
      for (final row in placeholders) {
        final id = row['id'] as String?;
        if (id != null) {
          await db.delete('user_sessions', where: 'user_id = ?', whereArgs: [id]);
          await db.delete('users', where: 'id = ?', whereArgs: [id]);
        }
      }
    } catch (_) {}
  }

  /// Deletes the legacy seeded default admin from users and sessions so the
  /// users table only shows real created accounts, but preserves the employees table.
  Future<void> removeDefaultAdminIfSeeded() async {
    try {
      final db = await database;
      // Only delete by email — id '1' is now a valid sequential user ID.
      final adminRows = await db.query('users',
          where: 'LOWER(email) = ?', whereArgs: ['admin@pulsemusic.app']);
      for (final row in adminRows) {
        final adminId = row['id'] as String;
        await db.delete('user_sessions',
            where: 'user_id = ?', whereArgs: [adminId]);
        await db.delete('users',
            where: 'id = ?', whereArgs: [adminId]);
      }
    } catch (_) {}
  }

  Future<Database> get database async {
    final existingDatabase = _database;
    if (existingDatabase != null) return existingDatabase;

    if (kIsWeb) {
      throw UnsupportedError('SQLite is not available on web builds.');
    }

    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);

    final dbPath = path.join(directory.path, _databaseName);
    _databaseFilePath = dbPath;
    debugPrint('[LocalDatabase] SQLite file: $dbPath');

    final factory = _databaseFactoryForPlatform();
    final openedDatabase = await factory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: _databaseVersion,
        onCreate: _createDatabase,
        onUpgrade: _upgradeDatabase,
      ),
    );
    _database = openedDatabase;
    _syncToWorkspace();
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
    if (oldVersion < 5) {
      // Password hashes: never store plaintext passwords in SQLite.
      try {
        await database.execute('ALTER TABLE users ADD COLUMN password_hash TEXT');
      } catch (_) {}
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
        password_hash TEXT,
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
    await seedDefaultUserIfNeeded();
    await seedEmployeeIfNeeded();
  }

  Future<void> seedEmployeeIfNeeded() async {
    final db = await database;
    final existing = await db.query(
      'employees',
      where: 'id = ? OR employee_code = ?',
      whereArgs: ['1', 'EMP-001'],
    );
    if (existing.isEmpty) {
      final now = DateTime.now().millisecondsSinceEpoch;
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
    _syncToWorkspace();
  }

  Future<void> seedDefaultUserIfNeeded() async {
    final db = await database;
    await removeDefaultAdminIfSeeded();

    final existing = await db.query(
      'users',
      where: 'LOWER(email) = ?',
      whereArgs: ['johnlaurencenovicio@gmail.com'],
    );
    if (existing.isEmpty) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final nextId = await getNextUserId();
      await db.insert(
        'users',
        {
          'id': nextId,
          'email': 'johnlaurencenovicio@gmail.com',
          'display_name': 'John Laurence',
          'photo_url': null,
          'role': 'user',
          'auth_provider': 'password',
          'created_at': now,
          'last_login_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    _syncToWorkspace();
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

  /// Returns the next sequential integer user ID as a String (e.g. '2', '3', '4').
  /// Starts at 2 so that '1' is never assigned — '1' is reserved as a guest
  /// sentinel alongside 'default_user' (see [guestUserIds]).
  Future<String> getNextUserId() async {
    final db = await database;
    final result = await db.rawQuery(
      "SELECT MAX(CAST(id AS INTEGER)) AS max_id FROM users WHERE id GLOB '[0-9]*'",
    );
    final maxId = result.first['max_id'];
    if (maxId == null) return '2';
    final next = (maxId as int) + 1;
    return '${next < 2 ? 2 : next}';
  }

  // ---------------------------------------------------------------------------
  // Password hashing (salted SHA-256). Plaintext passwords are NEVER stored.
  // Format: "saltHex$hashHex" where hash = SHA256(salt + password).
  // Every query in this file uses bound parameters (whereArgs / insert maps),
  // never string-interpolated SQL, so user input cannot break out into
  // SQL injection.
  // ---------------------------------------------------------------------------

  /// Creates a salted hash for [password]. Returns e.g. "a1b2...$c3d4...".
  static String hashPassword(String password, {String? saltHex}) {
    final salt = saltHex ?? _randomSaltHex();
    final digest = sha256.convert(utf8.encode('$salt:$password'));
    return '$salt:$digest';
  }

  static String _randomSaltHex() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Verifies [password] against a stored "salt:hash" value.
  static bool verifyPasswordHash(String password, String? stored) {
    if (stored == null || stored.isEmpty) return false;
    final sep = stored.indexOf(':');
    if (sep <= 0) return false;
    final salt = stored.substring(0, sep);
    final expected = hashPassword(password, saltHex: salt);
    return _constantTimeEquals(expected, stored);
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  /// Checks [password] for the user with [email]. Returns the user row on
  /// success, null when the account or password is wrong. Social accounts
  /// (google/facebook, null hash) always return null — they have no password.
  Future<Map<String, Object?>?> verifyLocalPassword(
    String email,
    String password,
  ) async {
    final user = await getUserByEmail(email);
    if (user == null) return null;
    if (!verifyPasswordHash(password, user['password_hash'] as String?)) {
      return null;
    }
    return user;
  }

  Future<void> saveUser({
    required String id,
    required String email,
    required String displayName,
    String? photoUrl,
    String role = 'user',
    String authProvider = 'password',
    String? passwordHash,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final cleanEmail = email.trim().toLowerCase();
    var resolvedDisplayName = displayName.trim();

    // Storage-layer guard: refuse placeholder/invalid emails instead of
    // silently mapping them onto a different real account. Every caller
    // validates first; this is defense in depth.
    if (cleanEmail.isEmpty ||
        !cleanEmail.contains('@') ||
        cleanEmail.startsWith('google.user') ||
        cleanEmail.startsWith('facebook.user') ||
        cleanEmail.startsWith('fb-')) {
      throw ArgumentError('saveUser requires a real email address');
    }
    if (resolvedDisplayName.isEmpty) {
      resolvedDisplayName = cleanEmail.split('@').first;
    }

    // Preserve original created_at AND existing password hash on updates so
    // SQLite viewer history stays stable; only bump last_login_at.
    // A null [passwordHash] never wipes a stored hash (social sign-ins).
    int createdAt = now;
    String? resolvedHash = passwordHash;
    try {
      final byId = await db.query('users',
          where: 'id = ?', whereArgs: [id], limit: 1);
      final existing =
          byId.isNotEmpty ? byId.first : await _rowByEmail(db, cleanEmail);
      if (existing != null) {
        if (existing['created_at'] is int) {
          createdAt = existing['created_at'] as int;
        }
        resolvedHash ??= existing['password_hash'] as String?;
      } else if (resolvedHash == null) {
        final byEmail = await _rowByEmail(db, cleanEmail);
        if (byEmail != null) {
          if (byEmail['created_at'] is int) {
            createdAt = byEmail['created_at'] as int;
          }
          resolvedHash ??= byEmail['password_hash'] as String?;
        }
      }
    } catch (_) {}
    await db.insert(
      'users',
      {
        'id': id,
        'email': cleanEmail,
        'display_name': resolvedDisplayName,
        'photo_url': photoUrl,
        'role': role,
        'auth_provider': authProvider,
        'password_hash': resolvedHash,
        'created_at': createdAt,
        'last_login_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    try {
      await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {}
    try {
      final count =
          await db.rawQuery('SELECT COUNT(*) AS c FROM users');
      debugPrint(
          '[LocalDatabase] saveUser $cleanEmail ($authProvider) -> total users: ${count.first['c']}');
    } catch (_) {}
    await _syncToWorkspace();
  }

  Future<Map<String, Object?>?> _rowByEmail(
    Database db,
    String cleanEmail,
  ) async {
    final rows = await db.query(
      'users',
      where: 'LOWER(email) = ?',
      whereArgs: [cleanEmail],
      limit: 1,
    );
    return rows.isNotEmpty ? rows.first : null;
  }

  /// Returns every local user — handy to verify SQLite viewer contents.
  Future<List<Map<String, Object?>>> getAllUsers() async {
    final db = await database;
    return db.query('users', orderBy: 'created_at ASC');
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
    try {
      await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {}
    await _syncToWorkspace();
  }

  Future<void> saveActiveSession(String userId) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert(
      'user_sessions',
      {'user_id': userId, 'saved_at': now},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    try {
      await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {}
    await _syncToWorkspace();
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
    try {
      await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {}
    await _syncToWorkspace();
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

    // Verify existing playlist ownership before modifying
    final existingPlaylists = await db.query(
      'imported_playlists',
      columns: ['id', 'user_id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (existingPlaylists.isNotEmpty) {
      final existingOwner = existingPlaylists.first['user_id'] as String;
      final isGuestOwner = guestUserIds.contains(existingOwner);
      if (!isGuestOwner && existingOwner != userId) {
        throw StateError('Cannot modify playlist owned by another user');
      }
    }

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
    _syncToWorkspace();
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
    final effectiveId = userId.isEmpty ? 'default_user' : userId;
    final isGuest = guestUserIds.contains(effectiveId);
    final playlists = await db.query(
      'imported_playlists',
      where: isGuest
          ? 'user_id = ? OR user_id = ?'
          : 'user_id = ?',
      whereArgs: isGuest
          ? ['default_user', '1']
          : [effectiveId],
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
  /// Always verifies ownership: a guest caller may only delete guest-owned
  /// playlists; a signed-in caller may only delete their own.
  Future<void> deleteImportedPlaylist(String playlistId, {String? userId}) async {
    final db = await database;
    final callerId = (userId ?? '').isEmpty ? 'default_user' : userId!;
    final callerIsGuest = guestUserIds.contains(callerId);

    final rows = await db.query(
      'imported_playlists',
      columns: ['id', 'user_id'],
      where: 'id = ?',
      whereArgs: [playlistId],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      final owner = rows.first['user_id'] as String;
      final ownerIsGuest = guestUserIds.contains(owner);
      // Guest callers may only delete guest-owned playlists.
      // Signed-in callers may only delete playlists they own.
      if (callerIsGuest && !ownerIsGuest) {
        debugPrint('[LocalDatabase] Guest cannot delete playlist owned by $owner');
        return;
      }
      if (!callerIsGuest && !ownerIsGuest && owner != callerId) {
        debugPrint('[LocalDatabase] Refusing to delete playlist owned by $owner');
        return;
      }
    }

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

  /// Reassigns anonymous playlists created during the *current* anonymous
  /// session to the newly signed-in user. Only playlists created after the
  /// most recent session-clear are adopted — this prevents Person B from
  /// inheriting Person A's anonymous playlists on a shared device.
  Future<void> claimAnonymousPlaylists(String newUserId) async {
    if (newUserId.isEmpty || guestUserIds.contains(newUserId)) return;
    final db = await database;

    // Determine the boundary: only claim playlists created after the
    // last time sessions were cleared (i.e. last sign-out). Playlists
    // from earlier anonymous sessions are left as 'default_user'.
    int sessionBoundary = 0;
    try {
      final sessions = await db.query(
        'user_sessions',
        columns: ['saved_at'],
        orderBy: 'saved_at DESC',
        limit: 1,
      );
      if (sessions.isNotEmpty) {
        sessionBoundary = sessions.first['saved_at'] as int? ?? 0;
      }
    } catch (_) {}

    await db.update(
      'imported_playlists',
      {'user_id': newUserId},
      where: '(user_id = ? OR user_id = ?) AND created_at >= ?',
      whereArgs: ['1', 'default_user', sessionBoundary],
    );
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
