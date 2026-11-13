import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music/controllers/music_player_controller.dart';
import 'package:music/data/local_database.dart';
import 'package:music/models/song_model.dart';
import 'package:music/services/radio_discovery_service.dart';
import 'package:music/services/spotify_import_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    HttpOverrides.global = null;
    await LocalDatabase.instance.initialize();
  });

  test('Importing a Spotify playlist locks in its imported image and does not randomly change', () async {
    final controller = MusicPlayerController();

    const expectedCover = 'https://i.scdn.co/image/ab67706c0000bebb1234567890abcdef12345678';
    final result = controller.importSpotifyTracks(
      playlistName: 'My Awesome Playlist',
      imageUrl: expectedCover,
      tracks: const [
        SpotifyImportedTrack(
          spotifyId: 'sp-track-1',
          title: 'Track One',
          artist: 'Artist One',
          album: 'Album One',
          duration: Duration(minutes: 3),
          artworkUrl: 'https://i.scdn.co/image/track-1-artwork',
        ),
        SpotifyImportedTrack(
          spotifyId: 'sp-track-2',
          title: 'Track Two',
          artist: 'Artist Two',
          album: 'Album Two',
          duration: Duration(minutes: 3),
          artworkUrl: 'https://i.scdn.co/image/track-2-artwork',
        ),
      ],
    );

    final playlist = controller.playlistById(result.playlistId);
    expect(playlist, isNotNull);
    expect(playlist!.imageUrl, equals(expectedCover));

    // Allow unawaited SQLite persist to complete
    await Future<void>.delayed(const Duration(milliseconds: 300));

    // Verify it was persisted to SQLite
    final savedPlaylists = await LocalDatabase.instance.getImportedPlaylistsForUser('default_user');
    final dbEntry = savedPlaylists.firstWhere((p) => p['id'] == result.playlistId);
    expect(dbEntry['image_url'], equals(expectedCover));
  });

  test('Fast importing a RadioStation locks in its image and does not change on track locate', () async {
    final controller = MusicPlayerController();

    const stationHero = 'https://is1-ssl.mzstatic.com/image/thumb/Music115/flowg.jpg';
    final station = RadioStation(
      id: 'flow-g-radio',
      title: 'Flow G Radio',
      artistName: 'Flow G',
      subtitle: 'Popular Radio',
      backgroundColor: const Color(0xFF1E3A8A),
      gradientColors: const [Color(0xFF1E3A8A), Color(0xFF3B82F6)],
      heroImageUrl: stationHero,
      songs: [
        Song(
          id: 'flow-g-1',
          title: 'Rapstar',
          artist: 'Flow G',
          album: 'Rapstar',
          duration: const Duration(minutes: 3, seconds: 45),
          genre: 'Hip-Hop',
          imageUrl: 'https://is1-ssl.mzstatic.com/image/thumb/rapstar.jpg',
          gradientColors: const [Color(0xFF1E3A8A), Color(0xFF3B82F6)],
          plays: '10M',
          lyrics: const [],
        ),
      ],
    );

    final playlist = controller.fastImportRadioStation(station);
    expect(playlist.imageUrl, equals(stationHero));

    // Allow unawaited SQLite persist to complete
    await Future<void>.delayed(const Duration(milliseconds: 300));

    // Verify saved to SQLite with stationHero
    final savedPlaylists = await LocalDatabase.instance.getImportedPlaylistsForUser('default_user');
    final dbEntry = savedPlaylists.firstWhere((p) => p['id'] == playlist.id);
    expect(dbEntry['image_url'], equals(stationHero));
  });

  test('Fast importing a static RadioStation without heroImageUrl uses first song artwork deterministically', () async {
    final controller = MusicPlayerController();

    const songArt = 'https://is1-ssl.mzstatic.com/image/thumb/Music115/rapstar-song.jpg';
    final station = RadioStation(
      id: 'static-radio',
      title: 'Trending OPM Radio',
      artistName: 'OPM Artists',
      subtitle: 'OPM Radio',
      backgroundColor: const Color(0xFF1E3A8A),
      gradientColors: const [Color(0xFF1E3A8A), Color(0xFF3B82F6)],
      heroImageUrl: '',
      avatarUrls: const [],
      songs: [
        Song(
          id: 'opm-1',
          title: 'Gento',
          artist: 'SB19',
          album: 'PAGTATAG!',
          duration: const Duration(minutes: 3, seconds: 50),
          genre: 'P-Pop',
          imageUrl: songArt,
          gradientColors: const [Color(0xFF1E3A8A), Color(0xFF3B82F6)],
          plays: '15M',
          lyrics: const [],
        ),
      ],
    );

    final playlist = controller.fastImportRadioStation(station);
    expect(playlist.imageUrl, equals(songArt));

    // Allow unawaited SQLite persist to complete
    await Future<void>.delayed(const Duration(milliseconds: 300));

    // Verify persisted
    final savedPlaylists = await LocalDatabase.instance.getImportedPlaylistsForUser('default_user');
    final dbEntry = savedPlaylists.firstWhere((p) => p['id'] == playlist.id);
    expect(dbEntry['image_url'], equals(songArt));
  });
}
