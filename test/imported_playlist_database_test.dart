import 'package:flutter_test/flutter_test.dart';
import 'package:music/controllers/music_player_controller.dart';
import 'package:music/data/local_database.dart';
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

    final userPlaylists = await LocalDatabase.instance.getImportedPlaylistsForUser('1');
    expect(userPlaylists, isNotEmpty);
    final saved = userPlaylists.firstWhere((p) => p['id'] == result.playlistId);
    expect(saved['title'], 'Auto Saved Playlist');
    expect(saved['spotify_url'], link);
    expect(saved['songs'], hasLength(1));
    expect((saved['songs'] as List).first['title'], 'Auto Saved Track');

    controller.dispose();
  });
}
