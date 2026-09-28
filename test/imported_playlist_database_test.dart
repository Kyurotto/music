import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music/auth/auth_service.dart';
import 'package:music/controllers/music_player_controller.dart';
import 'package:music/data/local_database.dart';
import 'package:music/services/spotify_import_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Database db;

  setUp(() async {
    AuthService.setMockVerifiedProfile(null);
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    LocalDatabase.setDatabaseForTesting(db);
    await LocalDatabase.instance.createAllTables(db);
    await LocalDatabase.instance.initialize();
  });

  tearDown(() async {
    AuthService.setMockVerifiedProfile(null);
    await db.close();
    LocalDatabase.setDatabaseForTesting(null);
  });

  test('LocalDatabase persists and retrieves imported playlists per user', () async {
    const userId = 'user-123';
    const playlistId = 'playlist-spot-1';
    const spotifyUrl = 'https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M';

    final songs = [
      {
        'id': 'spotify-track-1',
        'title': 'Track One',
        'artist': 'Artist One',
        'album': 'Album One',
        'duration_ms': 210000,
        'image_url': 'https://example.com/art1.jpg',
        'audio_url': 'https://example.com/audio1.mp3',
        'lyrics': ['Line 1', 'Line 2'],
        'genre': 'Pop',
        'is_preview': 0,
        'is_youtube_audio': 0,
      },
      {
        'id': 'spotify-track-2',
        'title': 'Track Two',
        'artist': 'Artist Two',
        'album': 'Album Two',
        'duration_ms': 185000,
        'image_url': 'https://example.com/art2.jpg',
        'audio_url': 'https://example.com/preview2.mp3',
        'lyrics': ['Another line'],
        'genre': 'Rock',
        'is_preview': 1,
        'is_youtube_audio': 0,
      },
    ];

    await LocalDatabase.instance.saveImportedPlaylist(
      id: playlistId,
      userId: userId,
      title: 'My Top Hits',
      subtitle: 'Imported from Spotify',
      spotifyUrl: spotifyUrl,
      gradientColors: [0xFF112233, 0xFF445566],
      songs: songs,
    );

    final retrieved = await LocalDatabase.instance.getImportedPlaylistsForUser(userId);
    expect(retrieved, hasLength(1));

    final playlist = retrieved.first;
    expect(playlist['id'], playlistId);
    expect(playlist['title'], 'My Top Hits');
    expect(playlist['spotify_url'], spotifyUrl);
    expect(playlist['user_id'], userId);

    final retrievedSongs = playlist['songs'] as List<dynamic>;
    expect(retrievedSongs, hasLength(2));
    expect(retrievedSongs[0]['title'], 'Track One');
    expect(retrievedSongs[0]['lyrics'], ['Line 1', 'Line 2']);
    expect(retrievedSongs[0]['is_preview'], isFalse);

    expect(retrievedSongs[1]['title'], 'Track Two');
    expect(retrievedSongs[1]['is_preview'], isTrue);
  });

  test('Every user has their own imported playlists (user separation)', () async {
    await LocalDatabase.instance.saveImportedPlaylist(
      id: 'pl-alice',
      userId: 'user-alice',
      title: 'Alice Playlist',
      songs: [
        {
          'id': 'sp-1',
          'title': 'Alice Song',
          'artist': 'Singer A',
          'duration_ms': 120000,
        }
      ],
    );

    await LocalDatabase.instance.saveImportedPlaylist(
      id: 'pl-bob',
      userId: 'user-bob',
      title: 'Bob Playlist',
      songs: [
        {
          'id': 'sp-2',
          'title': 'Bob Song',
          'artist': 'Singer B',
          'duration_ms': 130000,
        }
      ],
    );

    final alicePlaylists = await LocalDatabase.instance.getImportedPlaylistsForUser('user-alice');
    expect(alicePlaylists, hasLength(1));
    expect(alicePlaylists.first['title'], 'Alice Playlist');

    final bobPlaylists = await LocalDatabase.instance.getImportedPlaylistsForUser('user-bob');
    expect(bobPlaylists, hasLength(1));
    expect(bobPlaylists.first['title'], 'Bob Playlist');
  });

  test('LocalDatabase updateImportedSong updates audioUrl, preview flag, and lyrics', () async {
    const userId = 'user-test';
    await LocalDatabase.instance.saveImportedPlaylist(
      id: 'pl-upgrade',
      userId: userId,
      title: 'Upgrade Test',
      songs: [
        {
          'id': 'spotify-track-upgrade',
          'title': 'Slow Down',
          'artist': 'Singer',
          'duration_ms': 30000,
          'audio_url': 'https://example.com/30s.mp3',
          'is_preview': 1,
          'lyrics': <String>[],
        }
      ],
    );

    // Update with resolved full-length track and lyrics
    await LocalDatabase.instance.updateImportedSong(
      id: 'spotify-track-upgrade',
      audioUrl: 'https://example.com/full_length.mp4',
      isPreview: false,
      isYouTubeAudio: true,
      durationMs: 245000,
      lyrics: ['Resolved line 1', 'Resolved line 2'],
    );

    final retrieved = await LocalDatabase.instance.getImportedPlaylistsForUser(userId);
    final song = (retrieved.first['songs'] as List<dynamic>).first;
    expect(song['audio_url'], 'https://example.com/full_length.mp4');
    expect(song['is_preview'], isFalse);
    expect(song['is_youtube_audio'], isTrue);
    expect(song['duration_ms'], 245000);
    expect(song['lyrics'], ['Resolved line 1', 'Resolved line 2']);
  });

  test('claimAnonymousPlaylists reassigns anonymous playlists to new user on sign-in', () async {
    // Save playlist anonymously (id '1' or 'default_user')
    await LocalDatabase.instance.saveImportedPlaylist(
      id: 'anon-playlist',
      userId: 'default_user',
      title: 'Guest Playlist',
      songs: [
        {
          'id': 'sp-anon',
          'title': 'Guest Track',
          'artist': 'Guest Artist',
          'duration_ms': 180000,
        }
      ],
    );

    // Claim for user after logging in
    await LocalDatabase.instance.claimAnonymousPlaylists('user-logged-in-456');

    final userPlaylists = await LocalDatabase.instance.getImportedPlaylistsForUser('user-logged-in-456');
    expect(userPlaylists, hasLength(1));
    expect(userPlaylists.first['title'], 'Guest Playlist');
  });

  test('MusicPlayerController loads saved playlists and restores songs', () async {
    const userId = 'controller-user';
    await LocalDatabase.instance.saveImportedPlaylist(
      id: 'ctrl-playlist-1',
      userId: userId,
      title: 'Rock Classics',
      spotifyUrl: 'https://open.spotify.com/playlist/rock123',
      songs: [
        {
          'id': 'spotify-rock-1',
          'title': 'Sweet Child O Mine',
          'artist': 'Guns N Roses',
          'album': 'Appetite for Destruction',
          'duration_ms': 356000,
          'audio_url': 'https://example.com/guns.mp3',
          'lyrics': ['She has a smile that it seems to me'],
          'is_preview': 0,
        }
      ],
    );

    final controller = MusicPlayerController();
    await controller.loadSavedPlaylists(userId: userId);

    final playlist = controller.playlistById('ctrl-playlist-1');
    expect(playlist, isNotNull);
    expect(playlist!.title, 'Rock Classics');
    expect(playlist.songIds, contains('spotify-rock-1'));

    final song = controller.allSongs.firstWhere((s) => s.id == 'spotify-rock-1');
    expect(song.title, 'Sweet Child O Mine');
    expect(song.artist, 'Guns N Roses');
    expect(song.lyrics, ['She has a smile that it seems to me']);
    expect(song.audioUrl, 'https://example.com/guns.mp3');
    expect(song.isPreview, isFalse);

    controller.dispose();
  });

  test('MusicPlayerController.importSpotifyTracks saves to database with spotifyUrl', () async {
    final controller = MusicPlayerController();
    const link = 'https://open.spotify.com/playlist/test12345';

    final result = controller.importSpotifyTracks(
      playlistName: 'Auto Saved Playlist',
      spotifyUrl: link,
      tracks: [
        SpotifyImportedTrack(
          spotifyId: 'track-auto-1',
          title: 'Auto Saved Track',
          artist: 'Auto Artist',
          album: 'Auto Album',
          duration: const Duration(minutes: 3, seconds: 15),
          previewUrl: 'https://example.com/auto.mp3',
        ),
      ],
    );

    expect(result.addedCount, 1);

    // Give async database save a moment to complete
    await Future.delayed(const Duration(milliseconds: 100));

    final userPlaylists = await LocalDatabase.instance.getImportedPlaylistsForUser('default_user');
    expect(userPlaylists, isNotEmpty);
    final saved = userPlaylists.firstWhere((p) => p['id'] == result.playlistId);
    expect(saved['title'], 'Auto Saved Playlist');
    expect(saved['spotify_url'], link);
    expect(saved['songs'], hasLength(1));
    expect((saved['songs'] as List).first['title'], 'Auto Saved Track');

    controller.dispose();
  });


  test('signInWithProviderAuto creates and saves Google user in SQLite users table', () async {
    AuthService.setMockVerifiedProfile(
      const VerifiedSocialProfile(
        email: 'john.smith@gmail.com',
        displayName: 'John Smith',
        provider: 'google',
      ),
    );
    await AuthService.instance.signInWithProviderAuto(
      provider: 'google',
    );

    final user = await LocalDatabase.instance.getUserByEmail('john.smith@gmail.com');
    expect(user, isNotNull);
    expect(user!['email'], 'john.smith@gmail.com');
    expect(user['display_name'], 'John Smith');
    expect(user['auth_provider'], 'google');
    expect(user['role'], 'user');

    final googleUsers = await LocalDatabase.instance.getUsersByProvider('google');
    expect(googleUsers, isNotEmpty);
    expect(googleUsers.any((u) => u['email'] == 'john.smith@gmail.com'), isTrue);
  });

  test('signInWithProviderAuto creates and saves Facebook user in SQLite users table', () async {
    AuthService.setMockVerifiedProfile(
      const VerifiedSocialProfile(
        email: 'sarah.connor@facebook.com',
        displayName: 'Sarah Connor',
        provider: 'facebook',
      ),
    );
    await AuthService.instance.signInWithProviderAuto(
      provider: 'facebook',
    );

    final user = await LocalDatabase.instance.getUserByEmail('sarah.connor@facebook.com');
    expect(user, isNotNull);
    expect(user!['email'], 'sarah.connor@facebook.com');
    expect(user['display_name'], 'Sarah Connor');
    expect(user['auth_provider'], 'facebook');

    final fbUsers = await LocalDatabase.instance.getUsersByProvider('facebook');
    expect(fbUsers, isNotEmpty);
    expect(fbUsers.any((u) => u['email'] == 'sarah.connor@facebook.com'), isTrue);
  });

  test('register saves user to SQLite users table and sets active session', () async {
    await AuthService.instance.register(
      name: 'Elena Gilbert',
      email: 'elena@gmail.com',
      password: 'password123',
    );

    final user = await LocalDatabase.instance.getUserByEmail('elena@gmail.com');
    expect(user, isNotNull);
    expect(user!['email'], 'elena@gmail.com');
    expect(user['display_name'], 'Elena Gilbert');
    expect(user['auth_provider'], 'password');

    final sessionUserId = await LocalDatabase.instance.getActiveSessionUserId();
    expect(sessionUserId, user['id']);
  });

  test('register saves John Laurence to SQLite users table and removes default admin', () async {
    await AuthService.instance.register(
      name: 'John Laurence',
      email: 'johnlaurencenovicio@gmail.com',
      password: 'password123',
    );

    final user = await LocalDatabase.instance.getUserByEmail('johnlaurencenovicio@gmail.com');
    expect(user, isNotNull);
    expect(user!['email'], 'johnlaurencenovicio@gmail.com');
    expect(user['display_name'], 'John Laurence');
    expect(user['auth_provider'], 'password');

    final allUsers = await LocalDatabase.instance.getAllUsers();
    expect(allUsers.any((u) => u['email'] == 'admin@pulsemusic.app'), isFalse);
    expect(allUsers.any((u) => u['email'] == 'johnlaurencenovicio@gmail.com'), isTrue);
  });

  test('register stores salted password hash, never plaintext', () async {
    await AuthService.instance.register(
      name: 'Elena Gilbert',
      email: 'elena@gmail.com',
      password: 'password123',
    );

    final user = await LocalDatabase.instance.getUserByEmail('elena@gmail.com');
    expect(user, isNotNull);
    final hash = user!['password_hash'] as String?;
    expect(hash, isNotNull);
    expect(hash, isNotEmpty);
    expect(hash!.contains('password123'), isFalse);
    expect(hash.contains(':'), isTrue);

    // Correct password verifies, wrong password does not.
    final ok = await LocalDatabase.instance.verifyLocalPassword(
        'elena@gmail.com', 'password123');
    expect(ok, isNotNull);
    final bad = await LocalDatabase.instance.verifyLocalPassword(
        'elena@gmail.com', 'wrongpass');
    expect(bad, isNull);
  });

  test('hashPassword uses unique salts and verifies', () async {
    final h1 = LocalDatabase.hashPassword('same-password');
    final h2 = LocalDatabase.hashPassword('same-password');
    expect(h1, isNot(equals(h2)));
    expect(LocalDatabase.verifyPasswordHash('same-password', h1), isTrue);
    expect(LocalDatabase.verifyPasswordHash('other-password', h1), isFalse);
    expect(LocalDatabase.verifyPasswordHash('x', null), isFalse);
    expect(LocalDatabase.verifyPasswordHash('x', ''), isFalse);
  });

  test('employees table has EMP-001 preserved and never removed', () async {
    await LocalDatabase.instance.seedEmployeeIfNeeded();
    final employees = await LocalDatabase.instance.getEmployees();
    expect(employees, isNotEmpty);
    expect(employees.any((e) => e['employee_code'] == 'EMP-001'), isTrue);

    // Register a new user and ensure employees are still intact
    await AuthService.instance.register(
      name: 'Test Listener',
      email: 'listener@test.com',
      password: 'password123',
    );
    final employeesAfter = await LocalDatabase.instance.getEmployees();
    expect(employeesAfter, isNotEmpty);
    expect(employeesAfter.any((e) => e['employee_code'] == 'EMP-001'), isTrue);
  });

  test('creating new account with Google saves in SQLite users table', () async {
    AuthService.setMockVerifiedProfile(
      const VerifiedSocialProfile(
        email: 'newgoogleuser@gmail.com',
        displayName: 'Google Pioneer',
        provider: 'google',
      ),
    );
    await AuthService.instance.signInWithProviderAuto(
      provider: 'google',
      forceNewAccount: true,
    );

    final user = await LocalDatabase.instance.getUserByEmail('newgoogleuser@gmail.com');
    expect(user, isNotNull);
    expect(user!['email'], 'newgoogleuser@gmail.com');
    expect(user['display_name'], 'Google Pioneer');
    expect(user['auth_provider'], 'google');
    expect(user['role'], 'user');

    final allUsers = await LocalDatabase.instance.getAllUsers();
    expect(allUsers.any((u) => u['email'] == 'newgoogleuser@gmail.com'), isTrue);
  });

  test('creating new account with Facebook saves in SQLite users table', () async {
    AuthService.setMockVerifiedProfile(
      const VerifiedSocialProfile(
        email: 'newfacebookuser@facebook.com',
        displayName: 'Facebook Pioneer',
        provider: 'facebook',
      ),
    );
    await AuthService.instance.signInWithProviderAuto(
      provider: 'facebook',
      forceNewAccount: true,
    );

    final user = await LocalDatabase.instance.getUserByEmail('newfacebookuser@facebook.com');
    expect(user, isNotNull);
    expect(user!['email'], 'newfacebookuser@facebook.com');
    expect(user['display_name'], 'Facebook Pioneer');
    expect(user['auth_provider'], 'facebook');
    expect(user['role'], 'user');

    final allUsers = await LocalDatabase.instance.getAllUsers();
    expect(allUsers.any((u) => u['email'] == 'newfacebookuser@facebook.com'), isTrue);
  });

  test('Google taps reuse one account per email, never a different account', () async {
    AuthService.setMockVerifiedProfile(
      const VerifiedSocialProfile(
        email: 'same.person@gmail.com',
        displayName: 'Same Person',
        provider: 'google',
      ),
    );
    // First tap creates exactly one row for the real email.
    await AuthService.instance.signInWithProviderAuto(
      provider: 'google',
    );
    final first = await LocalDatabase.instance.getUserByEmail('same.person@gmail.com');
    expect(first, isNotNull);

    // Second tap with the same email reuses the SAME row (same id), no duplicate.
    await AuthService.instance.signInWithProviderAuto(
      provider: 'google',
    );
    final second = await LocalDatabase.instance.getUserByEmail('same.person@gmail.com');
    expect(second, isNotNull);
    expect(second!['id'], first!['id']);

    final googleRows = await LocalDatabase.instance.getUsersByProvider('google');
    final matches = googleRows.where((u) => u['email'] == 'same.person@gmail.com');
    expect(matches, hasLength(1));

    // A Google profile for an existing password email is rejected.
    await AuthService.instance.register(
      name: 'Pass User',
      email: 'shared@example.com',
      password: 'password123',
    );
    AuthService.setMockVerifiedProfile(
      const VerifiedSocialProfile(
        email: 'shared@example.com',
        displayName: 'Shared Person',
        provider: 'google',
      ),
    );
    expect(
      () => AuthService.instance.signInWithProviderAuto(provider: 'google'),
      throwsA(isA<FirebaseAuthException>().having(
        (e) => e.code,
        'code',
        'account-exists-with-different-credential',
      )),
    );
    final shared = await LocalDatabase.instance.getUserByEmail('shared@example.com');
    expect(shared, isNotNull);
    expect(shared!['auth_provider'], 'password');
    expect(shared['display_name'], 'Pass User');
  });

  test('Create mode with a different Google email creates that account', () async {
    AuthService.setMockVerifiedProfile(
      const VerifiedSocialProfile(
        email: 'first.person@gmail.com',
        displayName: 'First Person',
        provider: 'google',
      ),
    );
    await AuthService.instance.signInWithProviderAuto(
      provider: 'google',
      forceNewAccount: true,
    );
    AuthService.setMockVerifiedProfile(
      const VerifiedSocialProfile(
        email: 'second.person@gmail.com',
        displayName: 'Second Person',
        provider: 'google',
      ),
    );
    await AuthService.instance.signInWithProviderAuto(
      provider: 'google',
      forceNewAccount: true,
    );

    final first = await LocalDatabase.instance.getUserByEmail('first.person@gmail.com');
    final second = await LocalDatabase.instance.getUserByEmail('second.person@gmail.com');
    expect(first, isNotNull);
    expect(second, isNotNull);
    expect(first!['id'], isNot(equals(second!['id'])));
    expect(second['display_name'], 'Second Person');
    expect(AuthService.instance.userEmail, 'second.person@gmail.com');
  });

  test('Google with no saved account and no email asks for email, creates nothing fake', () async {
    try {
      await AuthService.instance.signInWithProviderAuto(
        provider: 'google',
        forceNewAccount: true,
      );
      fail('Expected google-unavailable');
    } on FirebaseAuthException catch (e) {
      expect(e.code, 'google-unavailable');
    }
    final allUsers = await LocalDatabase.instance.getAllUsers();
    expect(allUsers.any((u) => (u['email'] as String).startsWith('google.user')), isFalse);
    expect(allUsers.any((u) => (u['display_name'] as String).startsWith('google.user')), isFalse);
  });

  test('LocalDatabase.removeGenericPlaceholderUsers removes any stray google.user or facebook.user rows', () async {
    final db = await LocalDatabase.instance.database;
    // Directly insert a fake placeholder row
    await db.rawInsert('''
      INSERT INTO users (id, email, display_name, role, auth_provider, created_at, last_login_at)
      VALUES ('fake-1', 'google.user1790409015007@gmail.com', 'google.user1790409015007', 'user', 'google', 1000, 1000)
    ''');
    await db.rawInsert('''
      INSERT INTO user_sessions (user_id, saved_at) VALUES ('fake-1', 1000)
    ''');

    await LocalDatabase.instance.removeGenericPlaceholderUsers();

    final users = await LocalDatabase.instance.getAllUsers();
    expect(users.any((u) => (u['email'] as String).startsWith('google.user')), isFalse);
    expect(users.any((u) => (u['display_name'] as String).startsWith('google.user')), isFalse);
  });

  test('Real Google and Facebook account selection saves directly into users table and user_sessions', () async {
    // 1. Save different Google account
    AuthService.setMockVerifiedProfile(
      const VerifiedSocialProfile(
        email: 'arteezy0909@gmail.com',
        displayName: 'Arteezy',
        provider: 'google',
      ),
    );
    await AuthService.instance.signInWithGoogle();
    var user = await LocalDatabase.instance.getUserByEmail('arteezy0909@gmail.com');
    expect(user, isNotNull);
    expect(user!['email'], 'arteezy0909@gmail.com');
    expect(user['display_name'], 'Arteezy');
    expect(user['auth_provider'], 'google');
    var activeSessionUserId = await LocalDatabase.instance.getActiveSessionUserId();
    expect(activeSessionUserId, user['id']);

    // 2. Save another different Google account
    AuthService.setMockVerifiedProfile(
      const VerifiedSocialProfile(
        email: 'johnlaurencenovicio21@gmail.com',
        displayName: 'John Laurence Novicio',
        provider: 'google',
      ),
    );
    await AuthService.instance.signInWithGoogle();
    user = await LocalDatabase.instance.getUserByEmail('johnlaurencenovicio21@gmail.com');
    expect(user, isNotNull);
    expect(user!['email'], 'johnlaurencenovicio21@gmail.com');
    expect(user['display_name'], 'John Laurence Novicio');
    expect(user['auth_provider'], 'google');
    activeSessionUserId = await LocalDatabase.instance.getActiveSessionUserId();
    expect(activeSessionUserId, user['id']);

    // 3. Save Facebook account
    AuthService.setMockVerifiedProfile(
      const VerifiedSocialProfile(
        email: 'johnlaurencenovicio@gmail.com',
        displayName: 'John Laurence Novicio',
        provider: 'facebook',
      ),
    );
    await AuthService.instance.signInWithFacebook();
    user = await LocalDatabase.instance.getUserByEmail('johnlaurencenovicio@gmail.com');
    expect(user, isNotNull);
    expect(user!['display_name'], 'John Laurence Novicio');
    expect(user['auth_provider'], 'facebook');
    activeSessionUserId = await LocalDatabase.instance.getActiveSessionUserId();
    expect(activeSessionUserId, user['id']);
  });

  test('admin email or alias 1 requires password and does not bypass credentials', () async {
    // Attempting to sign in with admin email and invalid password fails with wrong-password or config-not-found
    expect(
      () => AuthService.instance.signInWithEmail(
        email: 'admin@pulsemusic.app',
        password: 'wrong_password',
      ),
      throwsA(isA<FirebaseAuthException>()),
    );

    expect(
      () => AuthService.instance.signInWithEmail(
        email: '1',
        password: 'wrong_password',
      ),
      throwsA(isA<FirebaseAuthException>()),
    );
  });

  test('registering an already existing email throws email-already-in-use and never overwrites password hash', () async {
    const email = 'victim@example.com';
    await AuthService.instance.register(
      name: 'Original User',
      email: email,
      password: 'OriginalPassword123!',
    );

    final originalUser = await LocalDatabase.instance.getUserByEmail(email);
    expect(originalUser, isNotNull);
    final originalHash = originalUser!['password_hash'] as String;
    final originalId = originalUser['id'] as String;

    // Attacker attempts to register the same email with a new password
    expect(
      () => AuthService.instance.register(
        name: 'Attacker',
        email: email,
        password: 'AttackerPassword123!',
      ),
      throwsA(isA<FirebaseAuthException>().having((e) => e.code, 'code', 'email-already-in-use')),
    );

    // Verify existing user ID and password hash were NOT changed
    final preservedUser = await LocalDatabase.instance.getUserByEmail(email);
    expect(preservedUser!['id'], originalId);
    expect(preservedUser['password_hash'], originalHash);
    expect(LocalDatabase.verifyPasswordHash('OriginalPassword123!', preservedUser['password_hash'] as String?), isTrue);
    expect(LocalDatabase.verifyPasswordHash('AttackerPassword123!', preservedUser['password_hash'] as String?), isFalse);
  });

  test('saveImportedPlaylist prevents cross-account playlist overwrites', () async {
    const userA = 'user-alice';
    const userB = 'user-bob';
    const playlistId = 'shared-playlist-id-123';

    await LocalDatabase.instance.saveImportedPlaylist(
      id: playlistId,
      userId: userA,
      title: "Alice's Mix",
      songs: [
        {'id': 'song-1', 'title': 'Track 1', 'artist': 'Artist 1'},
      ],
    );

    // Bob attempts to overwrite Alice's playlist
    expect(
      () => LocalDatabase.instance.saveImportedPlaylist(
        id: playlistId,
        userId: userB,
        title: "Bob's Takeover",
        songs: [
          {'id': 'song-2', 'title': 'Track 2', 'artist': 'Artist 2'},
        ],
      ),
      throwsA(isA<StateError>()),
    );

    // Verify Alice's playlist was not overwritten
    final db = await LocalDatabase.instance.database;
    final row = await db.query('imported_playlists', where: 'id = ?', whereArgs: [playlistId]);
    expect(row.first['user_id'], userA);
    expect(row.first['title'], "Alice's Mix");
  });

  test('deleteImportedPlaylist respects owner predicate', () async {
    const ownerId = 'user-owner';
    const unauthorizedId = 'user-unauthorized';
    const playlistId = 'protected-playlist-id-456';

    await LocalDatabase.instance.saveImportedPlaylist(
      id: playlistId,
      userId: ownerId,
      title: "Protected Mix",
      songs: [],
    );

    // Unauthorized user attempts deletion
    await LocalDatabase.instance.deleteImportedPlaylist(playlistId, userId: unauthorizedId);

    // Playlist should still exist
    final db = await LocalDatabase.instance.database;
    var rows = await db.query('imported_playlists', where: 'id = ?', whereArgs: [playlistId]);
    expect(rows, isNotEmpty);

    // Legitimate owner deletes playlist
    await LocalDatabase.instance.deleteImportedPlaylist(playlistId, userId: ownerId);
    rows = await db.query('imported_playlists', where: 'id = ?', whereArgs: [playlistId]);
    expect(rows, isEmpty);
  });
}

