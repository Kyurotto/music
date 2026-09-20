import 'dart:io';

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
  static const _databaseVersion = 3;

  Database? _database;

  Future<void> initialize() async {
    await database;
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
  }

  Future<void> _upgradeDatabase(Database database, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createAccountTables(database);
    }
    if (oldVersion < 3) {
      await _createEmployeeTable(database);
    }
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

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
