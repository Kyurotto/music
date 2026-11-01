import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
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
  static const _databaseVersion = 6;

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
    if (kIsWeb) return;
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) return;
    try {
      final src = _databaseFilePath;
      final db = _database;
      if (src == null || db == null) return;
      if (!File(src).existsSync()) return;
      try {
        await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      } catch (_) {}
      final targetDirs = {
        Directory.current.path,
        r'c:\Users\johnl\All Codes\music',
      };
      for (final targetDir in targetDirs) {
        try {
          final dest = path.join(targetDir, _databaseName);
          if (src == dest) continue;
          await File(src).copy(dest);
          for (final suffix in ['-wal', '-shm']) {
            final sidecar = File('$src$suffix');
            if (await sidecar.exists()) {
              await sidecar.copy('$dest$suffix');
            }
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> syncToWorkspace() => _syncToWorkspace();

  FirebaseAuth? get _auth {
    try {
      if (Firebase.apps.isEmpty) return null;
      return FirebaseAuth.instance;
    } catch (_) {
      return null;
    }
  }

  FirebaseFirestore? get _firestore {
    try {
      if (Firebase.apps.isEmpty) return null;
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
    try {
      await db.execute('ALTER TABLE users ADD COLUMN backup_email TEXT');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE users ADD COLUMN phone_number TEXT');
    } catch (_) {}
    // No more default admin seed. New accounts (e.g. John Laurence) become
    // the active user instead of "System Administrator".
    await removeDefaultAdminIfSeeded();
    await removeGenericPlaceholderUsers();
    await seedEmployeeIfNeeded();
    await _cleanImportedPlaylistsAndPreviews(db);
    _syncToWorkspace();
  }

  Future<void> _cleanImportedPlaylistsAndPreviews(Database db) async {
    try {
      // 1. Delete preview audio files (< 1.6MB) from all offline_audio directories
      const previewSongIds = [
        'spotify-2Zi27tBhXnDQTz3porgaiw',
        'spotify-76isMmZJIukbhkoCGtej1F',
        'spotify-7EGhmltmWJHCHobd3g8Hnw',
        'spotify-5V7mTIcXVU9k2JNu0mE6vy',
        'spotify-2bWy4LdYwgsFHxbqb5GzD1',
        'spotify-itunes-1011384691',
        'spotify-4356Typ82hUiFAynbLYbPn',
        'spotify-61dCUoMCg28qEBzrW6htYM',
      ];
      try {
        final dirs = <Directory>[];
        try {
          final supp = await getApplicationSupportDirectory();
          dirs.add(Directory(path.join(supp.path, 'offline_audio')));
        } catch (_) {}
        try {
          final docs = await getApplicationDocumentsDirectory();
          dirs.add(Directory(path.join(docs.path, 'offline_audio')));
        } catch (_) {}
        try {
          final temp = await getTemporaryDirectory();
          dirs.add(Directory(path.join(temp.path, 'offline_audio')));
        } catch (_) {}

        for (final offlineDir in dirs) {
          if (await offlineDir.exists()) {
            final files = offlineDir.listSync().whereType<File>();
            for (final f in files) {
              final name = path.basenameWithoutExtension(f.path);
              if (previewSongIds.contains(name) || f.lengthSync() < 1600000) {
                try {
                  f.deleteSync();
                } catch (_) {}
              }
            }
          }
        }
      } catch (_) {}

      // 2. Clear preview flags, preview URLs, and any offline paths pointing to deleted/preview clips
      await db.rawUpdate('''
        UPDATE imported_songs
        SET audio_url = '', is_preview = 0, is_youtube_audio = 1
        WHERE is_preview = 1
           OR audio_url LIKE '%googlevideo.com%'
           OR audio_url LIKE '%apple.com%'
           OR audio_url LIKE '%itunes%'
           OR audio_url LIKE '%deezer%'
           OR audio_url LIKE '%dzcdn.net%'
      ''');

      for (final sid in previewSongIds) {
        await db.rawUpdate(
          "UPDATE imported_songs SET audio_url = '', is_preview = 0, is_youtube_audio = 1 WHERE id = ?",
          [sid],
        );
      }

      final offlineRows = await db.rawQuery(
        "SELECT id, audio_url, duration_ms FROM imported_songs WHERE audio_url LIKE '%offline_audio%'",
      );
      for (final row in offlineRows) {
        final sid = row['id'] as String;
        final aurl = row['audio_url'] as String;
        final f = File(aurl);
        if (!f.existsSync() || f.lengthSync() < 1600000) {
          try {
            if (f.existsSync()) f.deleteSync();
          } catch (_) {}
          await db.rawUpdate(
            "UPDATE imported_songs SET audio_url = '', is_preview = 0, is_youtube_audio = 1 WHERE id = ?",
            [sid],
          );
        }
      }

      // 3. Fix 2000's playlist (remove Ed Sheeran 'perfect' hijack, insert Simple Plan 'Perfect')
      const simplePlanId = 'spotify-4j3X4KX8rURekAVIFUhI23';
      await db.rawInsert('''
        INSERT OR REPLACE INTO imported_songs (id, title, artist, album, duration_ms, image_url, audio_url, lyrics, genre, is_preview, is_youtube_audio, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, '', '[]', 'Rock', 0, 1, ?)
      ''', [
        simplePlanId,
        'Perfect',
        'Simple Plan',
        'No Pads, No Helmets...Just Balls',
        277560,
        'https://i.scdn.co/image/ab67616d0000b2732a3fcce8877bc9eb8903cb64',
        DateTime.now().millisecondsSinceEpoch,
      ]);

      const hinderId = 'spotify-40LQiUUUKXVGyNs09lHVjW';
      final year2000Playlists = await db.rawQuery(
        "SELECT id FROM imported_playlists WHERE title LIKE '%2000%'",
      );
      for (final row in year2000Playlists) {
        final pid = row['id'] as String;
        await db.delete(
          'imported_playlist_songs',
          where: 'playlist_id = ? AND song_id = ?',
          whereArgs: [pid, 'perfect'],
        );
        await db.update(
          'imported_playlist_songs',
          {'position': 0},
          where: 'playlist_id = ? AND song_id = ?',
          whereArgs: [pid, hinderId],
        );
        await db.rawInsert(
          'INSERT OR REPLACE INTO imported_playlist_songs (playlist_id, song_id, position) VALUES (?, ?, 1)',
          [pid, simplePlanId],
        );
      }

      // 4. Fix Maroon 5 Radio (remove 'just-the-way-you-are' at pos 0, set 'Maps' at pos 0)
      const mapsId = 'spotify-4gbVRS8gloEluzf0GzDOFc';
      await db.rawInsert('''
        INSERT OR REPLACE INTO imported_songs (id, title, artist, album, duration_ms, image_url, audio_url, lyrics, genre, is_preview, is_youtube_audio, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, '', '[]', 'Pop', 0, 1, ?)
      ''', [
        mapsId,
        'Maps',
        'Maroon 5',
        'V',
        189960,
        'https://i.scdn.co/image/ab67616d0000b27393437d7a74ee21e05d045d47',
        DateTime.now().millisecondsSinceEpoch,
      ]);

      final maroonPlaylists = await db.rawQuery(
        "SELECT id FROM imported_playlists WHERE title LIKE '%Maroon%'",
      );
      for (final row in maroonPlaylists) {
        final pid = row['id'] as String;
        await db.delete(
          'imported_playlist_songs',
          where: 'playlist_id = ? AND song_id = ? AND position = 0',
          whereArgs: [pid, 'just-the-way-you-are'],
        );
        await db.rawInsert(
          'INSERT OR REPLACE INTO imported_playlist_songs (playlist_id, song_id, position) VALUES (?, ?, 0)',
          [pid, mapsId],
        );
      }

      // 5. Fix Bruno Mars Mix (remove 'just-the-way-you-are' at pos 0, set 'Locked out of Heaven' at pos 0)
      const lockedId = 'spotify-5g7sDjBhZ4I3gcFIpkrLuI';
      await db.rawInsert('''
        INSERT OR REPLACE INTO imported_songs (id, title, artist, album, duration_ms, image_url, audio_url, lyrics, genre, is_preview, is_youtube_audio, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, '', '[]', 'Pop', 0, 1, ?)
      ''', [
        lockedId,
        'Locked out of Heaven',
        'Bruno Mars',
        'Unorthodox Jukebox',
        233480,
        'https://i.scdn.co/image/ab67616d0000b2739e495fb707973f3390850eea',
        DateTime.now().millisecondsSinceEpoch,
      ]);

      final brunoPlaylists = await db.rawQuery(
        "SELECT id FROM imported_playlists WHERE title LIKE '%Bruno Mars%'",
      );
      for (final row in brunoPlaylists) {
        final pid = row['id'] as String;
        await db.delete(
          'imported_playlist_songs',
          where: 'playlist_id = ? AND song_id = ? AND position = 0',
          whereArgs: [pid, 'just-the-way-you-are'],
        );
        await db.rawInsert(
          'INSERT OR REPLACE INTO imported_playlist_songs (playlist_id, song_id, position) VALUES (?, ?, 0)',
          [pid, lockedId],
        );
      }

      // 6. Ensure john1@example.com (user 6), novi@example.com (user 5), and john@example.com (user 3) have all imported playlists
      final allUserPlaylists = await db.rawQuery(
        "SELECT * FROM imported_playlists WHERE user_id IN ('3', '5', '6') AND (is_deleted IS NULL OR is_deleted = 0)",
      );
      for (final uid in const ['3', '5', '6']) {
        final existingRows = await db.query(
          'imported_playlists',
          where: 'user_id = ? AND (is_deleted IS NULL OR is_deleted = 0)',
          whereArgs: [uid],
        );
        final existingTitles = existingRows.map((r) => (r['title'] as String).toLowerCase().trim()).toSet();

        for (final donor in allUserPlaylists) {
          final donorIsDeleted = (donor['is_deleted'] as int? ?? 0) == 1;
          if (donorIsDeleted) continue;

          final rawTitle = donor['title'] as String;
          final titleKey = rawTitle.toLowerCase().trim();
          if (existingTitles.contains(titleKey)) continue;

          final donorId = donor['id'] as String;
          final cleanId = donorId.replaceAll(RegExp(r'-[356]$'), '');

          if (await isPlaylistDeleted(donorId, title: rawTitle, userId: uid)) continue;
          if (await isPlaylistDeleted(cleanId, title: rawTitle, userId: uid)) continue;

          existingTitles.add(titleKey);
          final newId = '$cleanId-$uid';

          final map = Map<String, dynamic>.from(donor);
          map['id'] = newId;
          map['user_id'] = uid;
          map['is_deleted'] = 0;
          await db.insert('imported_playlists', map, conflictAlgorithm: ConflictAlgorithm.replace);

          final songs = await db.query(
            'imported_playlist_songs',
            where: 'playlist_id = ?',
            whereArgs: [donorId],
          );
          for (final s in songs) {
            final songId = s['song_id'] as String;
            if (await isSongDeleted(songId)) continue;
            await db.insert(
              'imported_playlist_songs',
              {
                'playlist_id': newId,
                'song_id': songId,
                'position': s['position'],
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[LocalDatabase] _cleanImportedPlaylistsAndPreviews error: $e');
    }
  }

  /// Removes any fake auto-generated placeholder rows like 'google.user...' or 'facebook.user...'
  /// so that only purely real accounts exist in SQLite.
  Future<void> removeGenericPlaceholderUsers() async {
    try {
      final db = await database;
      final placeholders = await db.query(
        'users',
        columns: ['id'],
        where:
            "LOWER(email) LIKE 'google.user%' OR LOWER(email) LIKE 'facebook.user%' OR LOWER(display_name) LIKE 'google.user%' OR LOWER(display_name) LIKE 'facebook.user%'",
      );
      for (final row in placeholders) {
        final id = row['id'] as String?;
        if (id != null) {
          await db.delete(
            'user_sessions',
            where: 'user_id = ?',
            whereArgs: [id],
          );
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
      final adminRows = await db.query(
        'users',
        where: 'LOWER(email) = ?',
        whereArgs: ['admin@pulsemusic.app'],
      );
      for (final row in adminRows) {
        final adminId = row['id'] as String;
        await db.delete(
          'user_sessions',
          where: 'user_id = ?',
          whereArgs: [adminId],
        );
        await db.delete('users', where: 'id = ?', whereArgs: [adminId]);
      }
    } catch (_) {}
  }

  Future<Database> get database async {
    final existingDatabase = _database;
    if (existingDatabase != null) return existingDatabase;

    if (kIsWeb) {
      throw UnsupportedError('SQLite is not available on web builds.');
    }

    try {
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
    } catch (e) {
      // In unit test environments without platform channels (e.g. MissingPluginException),
      // fall back gracefully to an in-memory database instance.
      debugPrint('[LocalDatabase] Headless test fallback to in-memory database: $e');
      sqfliteFfiInit();
      final openedDatabase = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: _databaseVersion,
          onCreate: _createDatabase,
          onUpgrade: _upgradeDatabase,
        ),
      );
      _database = openedDatabase;
      return openedDatabase;
    }
  }

  DatabaseFactory _databaseFactoryForPlatform() {
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return databaseFactoryFfi;
    }
    return databaseFactory;
  }

  @visibleForTesting
  Future<void> createAllTables(Database db) =>
      _createDatabase(db, _databaseVersion);

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

  Future<void> _upgradeDatabase(
    Database database,
    int oldVersion,
    int newVersion,
  ) async {
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
        await database.execute(
          'ALTER TABLE users ADD COLUMN password_hash TEXT',
        );
      } catch (_) {}
    }
    if (oldVersion < 6) {
      await _createRememberedAccountsTable(database);
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
        image_url TEXT,
        gradient_colors TEXT,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    try {
      await database.execute('ALTER TABLE imported_playlists ADD COLUMN image_url TEXT');
    } catch (_) {}
    try {
      await database.execute('ALTER TABLE imported_playlists ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0');
    } catch (_) {}
    try {
      await database.execute('ALTER TABLE imported_songs ADD COLUMN youtube_video_id TEXT');
    } catch (_) {}
    try {
      await database.execute('ALTER TABLE imported_songs ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0');
    } catch (_) {}
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
        youtube_video_id TEXT,
        is_deleted INTEGER NOT NULL DEFAULT 0,
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
        backup_email TEXT,
        phone_number TEXT,
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
    await _createRememberedAccountsTable(database);
  }

  /// Emails the user asked to remember on the sign-in screen.
  /// Only email + display name are stored — never passwords.
  Future<void> _createRememberedAccountsTable(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS remembered_accounts (
        email TEXT PRIMARY KEY,
        display_name TEXT NOT NULL,
        saved_at INTEGER NOT NULL
      )
    ''');
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
      await db.insert('employees', {
        'id': '1',
        'user_id': '1',
        'employee_code': 'EMP-001',
        'display_name': 'System Administrator',
        'email': 'admin@pulsemusic.app',
        'status': 'active',
        'created_at': now,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
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
      await db.insert('users', {
        'id': nextId,
        'email': 'johnlaurencenovicio@gmail.com',
        'display_name': 'John Laurence',
        'photo_url': null,
        'role': 'user',
        'auth_provider': 'password',
        'created_at': now,
        'last_login_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
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
    String? backupEmail,
    String? phoneNumber,
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
    String? resolvedBackupEmail = backupEmail?.trim();
    String? resolvedPhone = phoneNumber?.trim();
    try {
      final byId = await db.query(
        'users',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      final existing = byId.isNotEmpty
          ? byId.first
          : await _rowByEmail(db, cleanEmail);
      if (existing != null) {
        if (existing['created_at'] is int) {
          createdAt = existing['created_at'] as int;
        }
        resolvedHash ??= existing['password_hash'] as String?;
        resolvedBackupEmail ??= existing['backup_email'] as String?;
        resolvedPhone ??= existing['phone_number'] as String?;
      } else if (resolvedHash == null) {
        final byEmail = await _rowByEmail(db, cleanEmail);
        if (byEmail != null) {
          if (byEmail['created_at'] is int) {
            createdAt = byEmail['created_at'] as int;
          }
          resolvedHash ??= byEmail['password_hash'] as String?;
          resolvedBackupEmail ??= byEmail['backup_email'] as String?;
          resolvedPhone ??= byEmail['phone_number'] as String?;
        }
      }
    } catch (_) {}
    await db.insert('users', {
      'id': id,
      'email': cleanEmail,
      'display_name': resolvedDisplayName,
      'photo_url': photoUrl,
      'role': role,
      'auth_provider': authProvider,
      'password_hash': resolvedHash,
      'backup_email': resolvedBackupEmail,
      'phone_number': resolvedPhone,
      'created_at': createdAt,
      'last_login_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    try {
      await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {}
    try {
      final count = await db.rawQuery('SELECT COUNT(*) AS c FROM users');
      debugPrint(
        '[LocalDatabase] saveUser $cleanEmail ($authProvider) -> total users: ${count.first['c']}',
      );
    } catch (_) {}
    await _syncToWorkspace();
  }

  /// Updates an existing account's profile credentials and recovery information.
  /// If [newPassword] is provided, it is securely hashed with salted SHA-256 before saving.
  Future<void> updateUserProfile({
    required String id,
    required String email,
    String? backupEmail,
    String? phoneNumber,
    String? newPassword,
    String? displayName,
  }) async {
    final db = await database;
    final cleanEmail = email.trim().toLowerCase();
    if (cleanEmail.isEmpty || !cleanEmail.contains('@')) {
      throw ArgumentError('A valid primary email is required.');
    }
    final cleanBackup = backupEmail?.trim();
    final cleanPhone = phoneNumber?.trim();
    final cleanDisplayName = displayName?.trim();

    final updates = <String, Object?>{
      'email': cleanEmail,
      'backup_email': cleanBackup != null && cleanBackup.isNotEmpty ? cleanBackup : null,
      'phone_number': cleanPhone != null && cleanPhone.isNotEmpty ? cleanPhone : null,
      'last_login_at': DateTime.now().millisecondsSinceEpoch,
    };

    if (cleanDisplayName != null && cleanDisplayName.isNotEmpty) {
      updates['display_name'] = cleanDisplayName;
    }

    if (newPassword != null && newPassword.trim().isNotEmpty) {
      updates['password_hash'] = hashPassword(newPassword.trim());
    }

    await db.update(
      'users',
      updates,
      where: 'id = ?',
      whereArgs: [id],
    );

    // Keep remembered account synchronized
    try {
      await db.execute(
        'INSERT OR REPLACE INTO remembered_accounts (email, display_name, saved_at) VALUES (?, ?, ?)',
        [cleanEmail, cleanDisplayName ?? cleanEmail.split('@').first, DateTime.now().millisecondsSinceEpoch],
      );
    } catch (_) {}

    try {
      await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
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
    await db.insert('user_sessions', {
      'user_id': userId,
      'saved_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    try {
      await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {}
    await _syncToWorkspace();
  }

  Future<String?> getActiveSessionUserId() async {
    final db = await database;
    final results = await db.query(
      'user_sessions',
      orderBy: 'saved_at DESC',
      limit: 1,
    );
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

  /// Whether the last sign-in asked to persist across restarts
  /// ("Remember me"). Stored in app_settings so it survives restarts.
  /// Defaults to true for installs that signed in before the flag existed.
  static const _persistSessionKey = 'auth_persist_session';

  Future<void> setPersistSession(bool persist) =>
      saveSetting(_persistSessionKey, persist ? '1' : '0');

  Future<bool> getPersistSession() async {
    try {
      final v = await getSetting(_persistSessionKey);
      return v != '0';
    } catch (_) {
      return true;
    }
  }

  /// Remembers an account for the sign-in "Remember me" popup.
  /// Stores email + display name only — never a password.
  Future<void> saveRememberedAccount({
    required String email,
    required String displayName,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    if (cleanEmail.isEmpty || !cleanEmail.contains('@')) return;
    final cleanName = displayName.trim().isNotEmpty
        ? displayName.trim()
        : cleanEmail.split('@').first;
    final db = await database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS remembered_accounts (
        email TEXT PRIMARY KEY,
        display_name TEXT NOT NULL,
        saved_at INTEGER NOT NULL
      )
    ''');
    await db.insert('remembered_accounts', {
      'email': cleanEmail,
      'display_name': cleanName,
      'saved_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await _syncToWorkspace();
  }

  /// Saved accounts for the sign-in popup, most recent first.
  Future<List<Map<String, Object?>>> getRememberedAccounts() async {
    try {
      final db = await database;
      await db.execute('''
        CREATE TABLE IF NOT EXISTS remembered_accounts (
          email TEXT PRIMARY KEY,
          display_name TEXT NOT NULL,
          saved_at INTEGER NOT NULL
        )
      ''');
      return db.query('remembered_accounts', orderBy: 'saved_at DESC');
    } catch (_) {
      return [];
    }
  }

  Future<void> removeRememberedAccount(String email) async {
    try {
      final db = await database;
      await db.delete(
        'remembered_accounts',
        where: 'LOWER(email) = ?',
        whereArgs: [email.trim().toLowerCase()],
      );
      await _syncToWorkspace();
    } catch (_) {}
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
    await db.insert('employees', {
      'id': userId ?? 'employee-$now',
      'user_id': userId,
      'employee_code': employeeCode.trim(),
      'display_name': displayName.trim(),
      'email': email.trim().toLowerCase(),
      'updated_at': now,
      'created_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, Object?>>> getEmployees() async {
    final db = await database;
    return db.query('employees', orderBy: 'employee_code COLLATE NOCASE ASC');
  }

  Future<Map<String, Object?>?> getEmployeeByUserId(String userId) async {
    final db = await database;
    final results = await db.query(
      'employees',
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  Future<Map<String, Object?>?> getEmployeeByEmail(String email) async {
    final db = await database;
    final results = await db.query(
      'employees',
      where: 'LOWER(email) = ?',
      whereArgs: [email.trim().toLowerCase()],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// Source of truth for admin access: the `employees` table.
  ///
  /// To make a user an admin/employee, set the `user_id` column of the
  /// matching `employees` row to that user's id (e.g. in a SQLite viewer),
  /// and keep its status as active. No in-app switch exists.
  ///
  /// Returns 'admin' when the linked employee row looks like an admin
  /// (code starts with EMP-ADM, or legacy id '1' / code 'EMP-001'),
  /// 'employee' for any other active linked row, else 'user'.
  Future<String> resolveUserRole(String userId) async {
    if (userId.isEmpty) return 'user';
    try {
      final db = await database;
      final rows = await db.query(
        'employees',
        where: 'user_id = ?',
        whereArgs: [userId],
        limit: 1,
      );
      if (rows.isEmpty) return 'user';
      final row = rows.first;
      if ((row['status'] as String? ?? 'active').toLowerCase() != 'active') {
        return 'user';
      }
      final code = (row['employee_code'] as String? ?? '').toUpperCase();
      final empId = (row['id'] as String? ?? '');
      if (code.startsWith('EMP-ADM') || empId == '1' || code == 'EMP-001') {
        return 'admin';
      }
      return 'employee';
    } catch (_) {
      return 'user';
    }
  }

  /// True when [userId] has an active admin link in `employees`.
  Future<bool> isAdmin(String userId) async {
    return await resolveUserRole(userId) == 'admin';
  }

  /// Re-syncs `users.role` to match the `employees` table so the cached
  /// column never drifts from the source of truth. Returns the resolved role.
  Future<String> refreshUserRoleFromEmployees(String userId) async {
    final resolved = await resolveUserRole(userId);
    try {
      final db = await database;
      await db.update(
        'users',
        {'role': resolved},
        where: 'id = ?',
        whereArgs: [userId],
      );
      try {
        await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      } catch (_) {}
      await _syncToWorkspace();
    } catch (_) {}
    return resolved;
  }

  /// Updates user role and synchronizes it with the employees table.
  ///
  /// - 'admin': sets users.role='admin' and ensures an active employee row with admin code.
  /// - 'employee': sets users.role='employee' and ensures an active employee row.
  /// - 'user': sets users.role='user' and sets any linked employee row to 'inactive'.
  Future<void> updateUserRole({
    required String userId,
    required String role,
    String? email,
    String? displayName,
  }) async {
    if (userId.isEmpty) return;
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final normalizedRole = role.toLowerCase().trim();

    // 1. Update users table
    await db.update(
      'users',
      {
        'role': normalizedRole,
      },
      where: 'id = ?',
      whereArgs: [userId],
    );

    // 2. Sync with employees table
    final empRows = await db.query(
      'employees',
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );

    if (normalizedRole == 'admin' || normalizedRole == 'employee') {
      final isAdminRole = normalizedRole == 'admin';
      final cleanEmail = (email ?? '').trim().toLowerCase();
      final cleanName = (displayName ?? '').trim().isNotEmpty
          ? displayName!.trim()
          : (isAdminRole ? 'Administrator' : 'Employee');

      if (empRows.isNotEmpty) {
        final existingEmp = empRows.first;
        final currentCode =
            (existingEmp['employee_code'] as String? ?? '').toUpperCase();
        String targetCode = currentCode;
        if (isAdminRole &&
            !currentCode.startsWith('EMP-ADM') &&
            currentCode != 'EMP-001') {
          final suffix = userId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
          final codeSuffix = suffix.length >= 6
              ? suffix.substring(0, 6).toUpperCase()
              : (suffix.isNotEmpty ? suffix.toUpperCase() : '001');
          targetCode = 'EMP-ADM-$codeSuffix';
        } else if (!isAdminRole && currentCode.startsWith('EMP-ADM')) {
          final suffix = userId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
          final codeSuffix = suffix.length >= 6
              ? suffix.substring(0, 6).toUpperCase()
              : (suffix.isNotEmpty ? suffix.toUpperCase() : '001');
          targetCode = 'EMP-$codeSuffix';
        }

        await db.update(
          'employees',
          {
            'status': 'active',
            'employee_code': targetCode,
            'updated_at': now,
          },
          where: 'user_id = ?',
          whereArgs: [userId],
        );
      } else {
        // Check if an employee exists by email to link
        List<Map<String, Object?>> emailMatch = [];
        if (cleanEmail.isNotEmpty) {
          emailMatch = await db.query(
            'employees',
            where: 'LOWER(email) = ?',
            whereArgs: [cleanEmail],
            limit: 1,
          );
        }

        if (emailMatch.isNotEmpty) {
          final matched = emailMatch.first;
          final currentCode =
              (matched['employee_code'] as String? ?? '').toUpperCase();
          String targetCode = currentCode;
          if (isAdminRole &&
              !currentCode.startsWith('EMP-ADM') &&
              currentCode != 'EMP-001') {
            final suffix = userId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
            final codeSuffix = suffix.length >= 6
                ? suffix.substring(0, 6).toUpperCase()
                : (suffix.isNotEmpty ? suffix.toUpperCase() : '001');
            targetCode = 'EMP-ADM-$codeSuffix';
          }
          await db.update(
            'employees',
            {
              'user_id': userId,
              'status': 'active',
              'employee_code': targetCode,
              'updated_at': now,
            },
            where: 'id = ?',
            whereArgs: [matched['id']],
          );
        } else {
          final suffix = userId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
          final codeSuffix = suffix.length >= 6
              ? suffix.substring(0, 6).toUpperCase()
              : (suffix.isNotEmpty ? suffix.toUpperCase() : '001');
          final targetCode =
              isAdminRole ? 'EMP-ADM-$codeSuffix' : 'EMP-$codeSuffix';
          final effectiveEmail =
              cleanEmail.isNotEmpty ? cleanEmail : '$userId@pulsemusic.app';

          await db.insert(
            'employees',
            {
              'id': 'emp-$userId',
              'user_id': userId,
              'employee_code': targetCode,
              'display_name': cleanName,
              'email': effectiveEmail,
              'status': 'active',
              'created_at': now,
              'updated_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    } else {
      // Role is 'user': deactivate linked employee row if any
      if (empRows.isNotEmpty) {
        await db.update(
          'employees',
          {
            'status': 'inactive',
            'updated_at': now,
          },
          where: 'user_id = ?',
          whereArgs: [userId],
        );
      }
    }

    try {
      await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {}
    await _syncToWorkspace();
  }

  Future<void> saveSetting(String key, String value) async {
    final db = await database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    await db.insert('app_settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> setSetting(String key, String value) => saveSetting(key, value);

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

  Future<void> removeSetting(String key) async {
    final db = await database;
    await db.delete(
      'app_settings',
      where: 'key = ?',
      whereArgs: [key],
    );
  }

  /// Extracts the base artist name from an artist-based playlist title.
  static String extractArtistNameFromPlaylist(String title) {
    var res = title.toLowerCase().trim();
    res = res.replaceAll(RegExp(r'^(this is|best of|top songs of|top tracks of)\s+'), '');
    res = res.replaceAll(RegExp(r'\s*-\s*(top songs|top tracks|essentials|greatest hits)'), '');
    res = res.replaceAll(RegExp(r'\s+(top songs|top tracks|essentials|greatest hits)$'), '');
    return res.trim();
  }

  /// Checks whether a playlist has been deleted or marked as deleted in settings.
  Future<bool> isPlaylistDeleted(
    String playlistId, {
    String? title,
    String? userId,
  }) async {
    if (await getSetting('deleted_playlist_$playlistId') == 'true') return true;
    final cleanId = playlistId.replaceAll(RegExp(r'-[356]$'), '');
    if (cleanId != playlistId && await getSetting('deleted_playlist_$cleanId') == 'true') {
      return true;
    }
    if (title != null && title.isNotEmpty) {
      final titleKey = title.toLowerCase().trim();
      if (await getSetting('deleted_playlist_$titleKey') == 'true') return true;
      if (userId != null && await getSetting('deleted_playlist_${titleKey}_$userId') == 'true') {
        return true;
      }
      for (final uid in const ['default_user', '1', '3', '5', '6']) {
        if (await getSetting('deleted_playlist_${titleKey}_$uid') == 'true') return true;
      }
      final artistName = extractArtistNameFromPlaylist(title);
      if (artistName.isNotEmpty) {
        final artistKey = artistName.toLowerCase().trim();
        if (await getSetting('deleted_artist_playlist_$artistKey') == 'true') return true;
        for (final uid in const ['default_user', '1', '3', '5', '6']) {
          if (await getSetting('deleted_artist_playlist_${artistKey}_$uid') == 'true') return true;
        }
      }
    }
    final db = await database;
    try {
      final rows = await db.query(
        'imported_playlists',
        columns: ['is_deleted'],
        where: 'id = ?',
        whereArgs: [playlistId],
        limit: 1,
      );
      if (rows.isNotEmpty && (rows.first['is_deleted'] as int? ?? 0) == 1) {
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Checks whether a song has been soft-deleted or marked as deleted in settings.
  Future<bool> isSongDeleted(String songId, {String? title, String? artist}) async {
    if (await getSetting('deleted_song_$songId') == 'true') return true;
    if (title != null && artist != null) {
      final key = '${title.toLowerCase().trim()}_${artist.toLowerCase().trim()}';
      if (await getSetting('deleted_song_$key') == 'true') return true;
    }
    final db = await database;
    try {
      final rows = await db.query(
        'imported_songs',
        columns: ['is_deleted'],
        where: 'id = ?',
        whereArgs: [songId],
        limit: 1,
      );
      if (rows.isNotEmpty && (rows.first['is_deleted'] as int? ?? 0) == 1) {
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Restores a soft-deleted playlist and clears its deleted markers (e.g. on deliberate re-import).
  Future<void> unmarkPlaylistDeleted(String playlistId, {String? title}) async {
    final db = await database;
    try {
      await db.update(
        'imported_playlists',
        {'is_deleted': 0, 'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [playlistId],
      );
    } catch (_) {}
    await removeSetting('deleted_playlist_$playlistId');
    final cleanId = playlistId.replaceAll(RegExp(r'-[356]$'), '');
    await removeSetting('deleted_playlist_$cleanId');
    if (title != null && title.isNotEmpty) {
      final titleKey = title.toLowerCase().trim();
      await removeSetting('deleted_playlist_$titleKey');
      for (final uid in const ['default_user', '1', '3', '5', '6']) {
        await removeSetting('deleted_playlist_${titleKey}_$uid');
      }
      final artistName = extractArtistNameFromPlaylist(title);
      if (artistName.isNotEmpty) {
        final artistKey = artistName.toLowerCase().trim();
        await removeSetting('deleted_artist_playlist_$artistKey');
        for (final uid in const ['default_user', '1', '3', '5', '6']) {
          await removeSetting('deleted_artist_playlist_${artistKey}_$uid');
        }
      }
    }
  }

  /// Persists an imported Spotify playlist and its songs associated with [userId].
  /// Writes to local SQLite and syncs a copy to Firestore best-effort.
  Future<void> saveImportedPlaylist({
    required String id,
    required String userId,
    required String title,
    String? subtitle,
    String? spotifyUrl,
    String? imageUrl,
    List<int>? gradientColors,
    required List<Map<String, dynamic>> songs,
  }) async {
    await _writeImportedPlaylist(
      id: id,
      userId: userId,
      title: title,
      subtitle: subtitle,
      spotifyUrl: spotifyUrl,
      imageUrl: imageUrl,
      gradientColors: gradientColors,
      songs: songs,
    );
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

  /// Offline variant of [saveImportedPlaylist]: persists an imported Spotify
  /// playlist and its songs for [userId] to local SQLite only, never
  /// touching Firebase/Firestore. Every user — including local-only
  /// accounts with no Firebase UID — can save their Spotify imports with
  /// no connectivity. The same per-user ownership rules apply.
  Future<void> saveImportedPlaylistOffline({
    required String id,
    required String userId,
    required String title,
    String? subtitle,
    String? spotifyUrl,
    String? imageUrl,
    List<int>? gradientColors,
    required List<Map<String, dynamic>> songs,
  }) async {
    await _writeImportedPlaylist(
      id: id,
      userId: userId,
      title: title,
      subtitle: subtitle,
      spotifyUrl: spotifyUrl,
      imageUrl: imageUrl,
      gradientColors: gradientColors,
      songs: songs,
    );
    _syncToWorkspace();
  }

  /// Updates only the image_url of an imported playlist.
  Future<void> updateImportedPlaylistImageUrl(String playlistId, String imageUrl) async {
    try {
      final db = await database;
      await db.update(
        'imported_playlists',
        {'image_url': imageUrl, 'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [playlistId],
      );
    } catch (_) {}
  }

  /// Shared SQLite write for [saveImportedPlaylist] and
  /// [saveImportedPlaylistOffline]: ownership check + transaction.
  Future<void> _writeImportedPlaylist({
    required String id,
    required String userId,
    required String title,
    String? subtitle,
    String? spotifyUrl,
    String? imageUrl,
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
      await txn.insert('imported_playlists', {
        'id': id,
        'user_id': userId,
        'title': title,
        'subtitle': subtitle ?? 'Imported from Spotify',
        'spotify_url': spotifyUrl,
        'image_url': imageUrl ?? '',
        'gradient_colors': gradientColors != null
            ? jsonEncode(gradientColors)
            : null,
        'created_at': now,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

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

        await txn.insert('imported_songs', {
          'id': songId,
          'title': song['title'] as String? ?? 'Unknown Title',
          'artist': song['artist'] as String? ?? 'Unknown Artist',
          'album': song['album'] as String? ?? '',
          'duration_ms': song['duration_ms'] as int? ?? 180000,
          'image_url': song['image_url'] as String? ?? '',
          'audio_url': song['audio_url'] as String? ?? '',
          'lyrics': lyricsJson,
          'genre': song['genre'] as String? ?? 'Spotify',
          'is_preview': (song['is_preview'] == true || song['is_preview'] == 1)
              ? 1
              : 0,
          'is_youtube_audio':
              (song['is_youtube_audio'] == true ||
                  song['is_youtube_audio'] == 1)
              ? 1
              : 0,
          if (song['youtube_video_id'] != null)
            'youtube_video_id': song['youtube_video_id'] as String,
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);

        await txn.insert('imported_playlist_songs', {
          'playlist_id': id,
          'song_id': songId,
          'position': i,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });

    // End of the shared local write. Firestore sync (online only) is done
    // by saveImportedPlaylist; the offline variant stops here.
  }

  /// Updates an imported song when audio or lyrics enrichment finishes.
  Future<void> updateImportedSong({
    required String id,
    String? audioUrl,
    bool? isPreview,
    bool? isYouTubeAudio,
    String? youtubeVideoId,
    int? durationMs,
    String? imageUrl,
    List<String>? lyrics,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final values = <String, Object?>{'updated_at': now};
    if (audioUrl != null) values['audio_url'] = audioUrl;
    if (isPreview != null) values['is_preview'] = isPreview ? 1 : 0;
    if (isYouTubeAudio != null) {
      values['is_youtube_audio'] = isYouTubeAudio ? 1 : 0;
    }
    if (youtubeVideoId != null) {
      values['youtube_video_id'] = youtubeVideoId;
    }
    if (durationMs != null) values['duration_ms'] = durationMs;
    if (imageUrl != null) values['image_url'] = imageUrl;
    if (lyrics != null) values['lyrics'] = jsonEncode(lyrics);

    await db.update('imported_songs', values, where: 'id = ?', whereArgs: [id]);
  }

  /// Every imported song across ALL users and playlists that still needs
  /// a full track: silent rows plus 30s previews. Used by the one-by-one
  /// background backfill so no artist playlist or radio stays muted on
  /// LOCATING. Ordered oldest-playlist first for stable resume.
  Future<List<Map<String, Object?>>> getUnresolvedImportedSongs({
    int limit = 200,
  }) async {
    final db = await database;
    try {
      return await db.rawQuery(
        '''
        SELECT DISTINCT s.id AS id, s.title AS title, s.artist AS artist,
               s.album AS album, s.duration_ms AS duration_ms,
               s.audio_url AS audio_url, s.is_preview AS is_preview,
               s.is_youtube_audio AS is_youtube_audio,
               s.youtube_video_id AS youtube_video_id,
               s.lyrics AS lyrics
        FROM imported_songs s
        INNER JOIN imported_playlist_songs ps ON ps.song_id = s.id
        INNER JOIN imported_playlists p ON p.id = ps.playlist_id
        WHERE (s.audio_url IS NULL OR s.audio_url = '' OR s.is_preview = 1)
          AND s.id LIKE 'spotify-%'
        ORDER BY p.created_at ASC, ps.position ASC
        LIMIT ?
        ''',
        [limit],
      );
    } catch (_) {
      return const [];
    }
  }

  /// Retrieves all imported playlists and their tracks belonging to [userId].
  Future<List<Map<String, dynamic>>> getImportedPlaylistsForUser(
    String userId,
  ) async {
    final db = await database;
    final effectiveId = userId.isEmpty ? 'default_user' : userId;
    final isGuest = guestUserIds.contains(effectiveId);

    // Map known account emails or IDs to their effective user ID
    String targetId = effectiveId;
    if (effectiveId == 'john@example.com') targetId = '3';
    if (effectiveId == 'novi@example.com') targetId = '5';
    if (effectiveId == 'john1@example.com') targetId = '6';

    const notDel = '(is_deleted IS NULL OR is_deleted = 0)';
    var playlists = await db.query(
      'imported_playlists',
      where: isGuest
          ? '(user_id = ? OR user_id = ?) AND $notDel'
          : 'user_id = ? AND $notDel',
      whereArgs: isGuest ? ['default_user', '1'] : [targetId],
      orderBy: 'created_at ASC',
    );

    if (playlists.isEmpty && targetId != effectiveId) {
      playlists = await db.query(
        'imported_playlists',
        where: 'user_id = ? AND $notDel',
        whereArgs: [effectiveId],
        orderBy: 'created_at ASC',
      );
    }

    if (playlists.isEmpty && (targetId == '3' || targetId == '5' || targetId == '6')) {
      playlists = await db.query(
        'imported_playlists',
        where: '(user_id = ? OR user_id = ? OR user_id = ?) AND $notDel',
        whereArgs: ['3', '5', '6'],
        orderBy: 'created_at ASC',
      );
    }
    if (playlists.isEmpty && isGuest) {
      playlists = await db.query(
        'imported_playlists',
        where: notDel,
        orderBy: 'created_at ASC',
      );
    }

    final results = <Map<String, dynamic>>[];
    final titleIndexMap = <String, int>{};

    for (final playlist in playlists) {
      final playlistId = playlist['id'] as String;
      final rawTitle = playlist['title'] as String? ?? '';
      final titleKey = rawTitle.toLowerCase().trim();
      final isDel = (playlist['is_deleted'] as int? ?? 0) == 1;
      if (isDel) continue;

      if (await isPlaylistDeleted(playlistId, title: rawTitle, userId: targetId)) {
        continue;
      }

      final songRows = await db.rawQuery(
        '''
        SELECT s.*, ps.position
        FROM imported_songs s
        INNER JOIN imported_playlist_songs ps ON s.id = ps.song_id
        WHERE ps.playlist_id = ? AND (s.is_deleted IS NULL OR s.is_deleted = 0)
        ORDER BY ps.position ASC
      ''',
        [playlistId],
      );

      final songs = <Map<String, dynamic>>[];
      for (final row in songRows) {
        final songId = row['id'] as String;
        final songTitle = row['title'] as String? ?? '';
        final songArtist = row['artist'] as String? ?? '';
        if (await isSongDeleted(songId, title: songTitle, artist: songArtist)) {
          continue;
        }

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

        songs.add(<String, dynamic>{
          'id': songId,
          'title': songTitle,
          'artist': songArtist,
          'album': row['album'] as String? ?? '',
          'duration_ms': row['duration_ms'] as int? ?? 180000,
          'image_url': row['image_url'] as String? ?? '',
          'audio_url': row['audio_url'] as String? ?? '',
          'lyrics': lyricsList,
          'genre': row['genre'] as String? ?? 'Spotify',
          'is_preview': (row['is_preview'] as int? ?? 0) == 1,
          'is_youtube_audio': (row['is_youtube_audio'] as int? ?? 0) == 1,
          'youtube_video_id': row['youtube_video_id'] as String? ?? '',
        });
      }

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

      if (titleKey.isNotEmpty && titleIndexMap.containsKey(titleKey)) {
        final existingIdx = titleIndexMap[titleKey]!;
        final existingPlaylist = results[existingIdx];
        final existingSongs = existingPlaylist['songs'] as List<Map<String, dynamic>>;
        final existingSongIds = existingSongs.map((s) => s['id'] as String).toSet();
        for (final s in songs) {
          if (!existingSongIds.contains(s['id'])) {
            existingSongs.add(s);
            existingSongIds.add(s['id'] as String);
          }
        }
        continue;
      }

      final resMap = <String, dynamic>{
        'id': playlistId,
        'user_id': playlist['user_id'] as String,
        'title': rawTitle,
        'subtitle': playlist['subtitle'] as String? ?? 'Imported from Spotify',
        'spotify_url': playlist['spotify_url'] as String?,
        'gradient_colors': gradientColors,
        'created_at': playlist['created_at'] as int,
        'songs': songs,
      };
      if (titleKey.isNotEmpty) {
        titleIndexMap[titleKey] = results.length;
      }
      results.add(resMap);
    }

    return results;
  }

  /// Deletes an imported playlist and its track associations.
  /// Preserves all full tracks and audio in SQLite ("sa database hindi ma bubura").
  /// Marks deletion persistently across all user copies so it never resurrects.
  Future<void> deleteImportedPlaylist(
    String playlistId, {
    String? userId,
  }) async {
    final db = await database;
    final callerId = (userId ?? '').isEmpty ? 'default_user' : userId!;
    final callerIsGuest = guestUserIds.contains(callerId);

    final rows = await db.query(
      'imported_playlists',
      columns: ['id', 'user_id', 'title'],
      where: 'id = ?',
      whereArgs: [playlistId],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      final owner = rows.first['user_id'] as String;
      final rawTitle = rows.first['title'] as String? ?? '';
      final titleKey = rawTitle.toLowerCase().trim();
      final ownerIsGuest = guestUserIds.contains(owner);
      const allowedSystemAccounts = {'3', '5', '6', 'john@example.com', 'novi@example.com', 'john1@example.com'};
      final isCallerAllowed = owner == callerId ||
          ownerIsGuest ||
          callerIsGuest ||
          allowedSystemAccounts.contains(callerId) ||
          (allowedSystemAccounts.contains(owner) && callerId.isNotEmpty);

      if (!isCallerAllowed) {
        debugPrint(
          '[LocalDatabase] Refusing to delete playlist owned by $owner',
        );
        return;
      }

      final cleanId = playlistId.replaceAll(RegExp(r'-[356]$'), '');

      // 1. Mark is_deleted = 1 across matching records
      await db.update(
        'imported_playlists',
        {'is_deleted': 1, 'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ? OR id LIKE ? OR (? != \'\' AND LOWER(TRIM(title)) = ?)',
        whereArgs: [playlistId, '$cleanId-%', titleKey, titleKey],
      );

      // 2. Persist deleted settings so that this playlist NEVER resurrects across app restarts
      await setSetting('deleted_playlist_$playlistId', 'true');
      await setSetting('deleted_playlist_$cleanId', 'true');
      if (titleKey.isNotEmpty) {
        await setSetting('deleted_playlist_$titleKey', 'true');
        for (final uid in ['default_user', '1', '3', '5', '6', callerId, owner]) {
          if (uid.isNotEmpty) {
            await setSetting('deleted_playlist_${titleKey}_$uid', 'true');
          }
        }

        final artistName = extractArtistNameFromPlaylist(rawTitle);
        if (artistName.isNotEmpty) {
          final artistKey = artistName.toLowerCase().trim();
          await setSetting('deleted_artist_playlist_$artistKey', 'true');
          for (final uid in ['default_user', '1', '3', '5', '6', callerId, owner]) {
            if (uid.isNotEmpty) {
              await setSetting('deleted_artist_playlist_${artistKey}_$uid', 'true');
            }
          }
        }
      }

      // 3. Delete from active imported_playlists across all user copies (including donor copies)
      await db.delete(
        'imported_playlists',
        where: 'id = ? OR id LIKE ? OR (? != \'\' AND LOWER(TRIM(title)) = ?)',
        whereArgs: [playlistId, '$cleanId-%', titleKey, titleKey],
      );

      await db.delete(
        'imported_playlist_songs',
        where: 'playlist_id = ? OR playlist_id LIKE ?',
        whereArgs: [playlistId, '$cleanId-%'],
      );
    } else {
      final cleanId = playlistId.replaceAll(RegExp(r'-[356]$'), '');
      await setSetting('deleted_playlist_$playlistId', 'true');
      await setSetting('deleted_playlist_$cleanId', 'true');
      await db.delete(
        'imported_playlists',
        where: 'id = ? OR id LIKE ?',
        whereArgs: [playlistId, '$cleanId-%'],
      );
      await db.delete(
        'imported_playlist_songs',
        where: 'playlist_id = ? OR playlist_id LIKE ?',
        whereArgs: [playlistId, '$cleanId-%'],
      );
    }

    _syncToWorkspace();
  }

  /// Soft-deletes a playlist so it is hidden from the dashboard and library.
  Future<void> markImportedPlaylistDeleted(
    String playlistId, {
    String? userId,
  }) =>
      deleteImportedPlaylist(playlistId, userId: userId);

  /// Deletes an imported song association from a playlist.
  Future<void> deleteImportedSongFromPlaylist({
    required String playlistId,
    required String songId,
  }) async {
    final db = await database;
    await db.delete(
      'imported_playlist_songs',
      where: 'playlist_id = ? AND song_id = ?',
      whereArgs: [playlistId, songId],
    );
    _syncToWorkspace();
  }

  /// Soft-deletes an imported song so that it never appears on the dashboard or library,
  /// while keeping the song row and downloaded full tracks safe in the database ("sa database hindi ma bubura").
  Future<void> markImportedSongDeleted(String songId) async {
    final db = await database;
    try {
      final rows = await db.query(
        'imported_songs',
        columns: ['id', 'title', 'artist'],
        where: 'id = ?',
        whereArgs: [songId],
        limit: 1,
      );
      String? title;
      String? artist;
      if (rows.isNotEmpty) {
        title = rows.first['title'] as String?;
        artist = rows.first['artist'] as String?;
      }

      await db.update(
        'imported_songs',
        {
          'is_deleted': 1,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [songId],
      );

      await db.delete(
        'imported_playlist_songs',
        where: 'song_id = ?',
        whereArgs: [songId],
      );

      await setSetting('deleted_song_$songId', 'true');
      if (title != null && artist != null) {
        final key = '${title.toLowerCase().trim()}_${artist.toLowerCase().trim()}';
        await setSetting('deleted_song_$key', 'true');
      }
      _syncToWorkspace();
    } catch (e) {
      debugPrint('[LocalDatabase] markImportedSongDeleted error: $e');
    }
  }

  /// Backward-compatible alias for [markImportedSongDeleted].
  Future<void> deleteImportedSongCompletely(String songId) async {
    await markImportedSongDeleted(songId);
  }

  /// Retrieves a single imported song from SQLite by [id].
  Future<Map<String, dynamic>?> getImportedSong(String id) async {
    final db = await database;
    try {
      final rows = await db.query(
        'imported_songs',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return Map<String, dynamic>.from(rows.first);
    } catch (_) {
      return null;
    }
  }

  /// Returns all imported songs that have been located as full tracks.
  /// Preserves user tracks even if their parent playlist was deleted.
  Future<List<Map<String, dynamic>>> getSavedFullTrackSongs() async {
    final db = await database;
    try {
      final rows = await db.query(
        'imported_songs',
        where: "is_preview = 0 AND audio_url IS NOT NULL AND audio_url != '' AND audio_url NOT LIKE '%apple.com%' AND audio_url NOT LIKE '%itunes%'",
        orderBy: 'updated_at DESC',
      );
      return rows.map((r) => Map<String, dynamic>.from(r)).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> cleanOrphanImportedSongs([Database? databaseInstance]) async {
    try {
      final db = databaseInstance ?? await database;
      final orphanRows = await db.rawQuery('''
        SELECT id, audio_url, is_preview FROM imported_songs
        WHERE id NOT IN (SELECT DISTINCT song_id FROM imported_playlist_songs)
      ''');
      for (final row in orphanRows) {
        final sid = row['id'] as String?;
        if (sid == null) continue;
        final isPreview = (row['is_preview'] as int? ?? 0) == 1;
        final audioUrl = (row['audio_url'] as String? ?? '').trim();
        // NEVER delete songs that were located as full tracks:
        final isLocatedFullTrack = !isPreview &&
            audioUrl.isNotEmpty &&
            !audioUrl.contains('apple.com') &&
            !audioUrl.contains('itunes');
        if (!isLocatedFullTrack) {
          await db.delete('imported_songs', where: 'id = ?', whereArgs: [sid]);
          await _deleteCachedAudioFile(sid);
        }
      }
    } catch (_) {}
  }

  Future<void> _deleteCachedAudioFile(String songId) async {
    try {
      final supp = await getApplicationSupportDirectory();
      final offlineDir = Directory(path.join(supp.path, 'offline_audio'));
      if (await offlineDir.exists()) {
        for (final ext in const ['.mp3', '.m4a', '.mp4', '.aac', '.wav', '.ogg', '']) {
          final f = File(path.join(offlineDir.path, '$songId$ext'));
          if (await f.exists()) {
            try {
              await f.delete();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
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
            'tracks': songs
                .map(
                  (s) => {
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
                  },
                )
                .toList(),
          }, SetOptions(merge: true))
          .catchError((e) {
            debugPrint('[LocalDatabase] Firestore playlist sync skipped: $e');
          });
    } catch (_) {}
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
