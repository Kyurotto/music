import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:music/controllers/music_player_controller.dart';
import 'package:music/services/spotify_import_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const brunoMarsId = '0du5cEVh5yTK9QJze8zA0C';

  http.Response jsonOk(Object body) => http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json'},
      );

  Map<String, Object?> artistSearchJson({
    String artist = 'Bruno Mars',
    int artistId = 92,
  }) =>
      {
        'resultCount': 2,
        'results': [
          {
            'wrapperType': 'artist',
            'artistType': 'Artist',
            'artistName': '$artist Tribute Band',
            'artistId': 111,
          },
          {
            'wrapperType': 'artist',
            'artistType': 'Artist',
            'artistName': artist,
            'artistId': artistId,
          },
        ],
      };

  Map<String, Object?> artistLookupJson({
    String artist = 'Bruno Mars',
    int artistId = 92,
    String firstTitle = 'Uptown Funk',
    String firstCollection = 'Uptown Special',
    int firstTrackId = 1,
    String firstPreview = 'https://example.com/uptown.m4a',
    String secondTitle = 'Just the Way You Are',
    String secondCollection = 'Doo-Wops & Hooligans',
    int secondTrackId = 2,
    String secondPreview = 'https://example.com/jtwya.m4a',
  }) =>
      {
        'resultCount': 3,
        'results': [
          {
            'wrapperType': 'artist',
            'artistType': 'Artist',
            'artistName': artist,
            'artistId': artistId,
          },
          {
            'wrapperType': 'track',
            'kind': 'song',
            'artistName': artist,
            'trackName': firstTitle,
            'collectionName': firstCollection,
            'trackId': firstTrackId,
            'previewUrl': firstPreview,
            'artworkUrl100': 'https://example.com/a/100x100bb.jpg',
            'trackTimeMillis': 269000,
          },
          {
            'wrapperType': 'track',
            'kind': 'song',
            'artistName': artist,
            'trackName': secondTitle,
            'collectionName': secondCollection,
            'trackId': secondTrackId,
            'previewUrl': secondPreview,
            'artworkUrl100': 'https://example.com/b/100x100bb.jpg',
            'trackTimeMillis': 219000,
          },
        ],
      };

  /// iTunes mocks for the artist flow; oEmbed behavior is configurable.
  SpotifyImportService artistService({bool oEmbedOk = true}) {
    return SpotifyImportService(
      client: MockClient((request) async {
        final host = request.url.host;
        if (host == 'embed.spotify.com') {
          if (oEmbedOk) {
            return jsonOk({
              'title': 'Bruno Mars',
              'provider_name': 'Spotify',
              'type': 'rich',
            });
          }
          return http.Response('bad gateway', 502);
        }
        if (host == 'itunes.apple.com' &&
            request.url.path == '/search') {
          return jsonOk(artistSearchJson());
        }
        if (host == 'itunes.apple.com' &&
            request.url.path == '/lookup') {
          return jsonOk(artistLookupJson());
        }
        return http.Response('not found', 404);
      }),
    );
  }

  group('SpotifyImportService artist parsing', () {
    test('parses artist URLs, URIs, and embed URLs', () {
      final link = SpotifyImportService.tryParse(
        'https://open.spotify.com/artist/$brunoMarsId',
      );
      expect(link, isNotNull);
      expect(link!.type, SpotifyLinkType.artist);
      expect(link.id, brunoMarsId);

      final uri = SpotifyImportService.tryParse('spotify:artist:$brunoMarsId');
      expect(uri, isNotNull);
      expect(uri!.type, SpotifyLinkType.artist);

      final embed = SpotifyImportService.tryParse(
        'https://open.spotify.com/embed/artist/$brunoMarsId?utm_source=generator',
      );
      expect(embed, isNotNull);
      expect(embed!.type, SpotifyLinkType.artist);
    });

    test('rejects malformed artist links', () {
      expect(
        SpotifyImportService.tryParse(
            'https://open.spotify.com/artist/short-id'),
        isNull,
      );
      expect(SpotifyImportService.tryParse('spotify:artist:xyz'), isNull);
    });
  });

  group('SpotifyImportService artist import', () {
    test('imports top songs from an artist link', () async {
      final service = artistService();
      final result = await service.importFromLink(
        'https://open.spotify.com/artist/$brunoMarsId',
      );
      expect(result.type, SpotifyLinkType.artist);
      expect(result.title, 'Bruno Mars');
      expect(result.tracks, hasLength(2));
      expect(result.tracks.first.title, 'Uptown Funk');
      expect(result.tracks.first.artist, 'Bruno Mars');
      expect(result.tracks.first.previewUrl,
          'https://example.com/uptown.m4a');
      expect(result.tracks.first.duration.inSeconds, 269);
      service.dispose();
    });

    test('imports top songs from a plain artist name', () async {
      var oEmbedCalls = 0;
      final service = SpotifyImportService(
        client: MockClient((request) async {
          if (request.url.host == 'embed.spotify.com') {
            oEmbedCalls++;
            return http.Response('nope', 404);
          }
          if (request.url.host == 'itunes.apple.com' &&
              request.url.path == '/search') {
            return jsonOk(artistSearchJson());
          }
          if (request.url.host == 'itunes.apple.com' &&
              request.url.path == '/lookup') {
            return jsonOk(artistLookupJson());
          }
          return http.Response('not found', 404);
        }),
      );
      final result = await service.importFromLink('Bruno Mars');
      expect(result.type, SpotifyLinkType.artist);
      expect(result.title, 'Bruno Mars');
      expect(result.tracks, hasLength(2));
      expect(oEmbedCalls, 0,
          reason: 'plain names must not hit oEmbed');
      service.dispose();
    });

    test('artist link without oEmbed gives a name-typing hint', () async {
      final service = artistService(oEmbedOk: false);
      expect(
        () => service.importFromLink(
          'https://open.spotify.com/artist/$brunoMarsId',
        ),
        throwsA(
          isA<SpotifyImportException>().having(
            (e) => e.message,
            'message',
            contains('Type the artist name'),
          ),
        ),
      );
      service.dispose();
    });

    test('unknown artist name throws a friendly error', () async {
      final service = SpotifyImportService(
        client: MockClient((request) async {
          if (request.url.host == 'itunes.apple.com') {
            return jsonOk({'resultCount': 0, 'results': []});
          }
          return http.Response('not found', 404);
        }),
      );
      expect(
        () => service.importFromLink('Xyz No Such Artist Abc'),
        throwsA(isA<SpotifyImportException>()),
      );
      service.dispose();
    });

    test('non-Spotify URLs are still rejected, not name-searched', () async {
      final service = artistService();
      expect(
        () => service.importFromLink('https://example.com/track/abc'),
        throwsA(
          isA<SpotifyImportException>().having(
            (e) => e.message,
            'message',
            contains('does not look like'),
          ),
        ),
      );
      service.dispose();
    });
  });

  group('MusicPlayerController artist import', () {
    test('artist tracks import full-track-only, no 30s preview seeding',
        () async {
      // Fictional artist: must NOT collide with bundled sample songs,
      // otherwise the controller (correctly) reuses the local copies.
      final service = SpotifyImportService(
        client: MockClient((request) async {
          if (request.url.host == 'itunes.apple.com' &&
              request.url.path == '/search') {
            return jsonOk(artistSearchJson(
                artist: 'Aurora Skies', artistId: 777));
          }
          if (request.url.host == 'itunes.apple.com' &&
              request.url.path == '/lookup') {
            return jsonOk(artistLookupJson(
              artist: 'Aurora Skies',
              artistId: 777,
              firstTitle: 'Neon Skyline',
              firstCollection: 'Afterglow',
              firstTrackId: 101,
              firstPreview: 'https://example.com/neon.m4a',
              secondTitle: 'Midnight Drive',
              secondCollection: 'Afterglow',
              secondTrackId: 102,
              secondPreview: 'https://example.com/midnight.m4a',
            ));
          }
          return http.Response('not found', 404);
        }),
      );
      final result = await service.importFromLink('Aurora Skies');
      service.dispose();
      expect(result.title, 'Aurora Skies');

      final controller = MusicPlayerController();
      final outcome = controller.importSpotifyTracks(
        playlistName: result.title,
        tracks: result.tracks,
      );
      final songs = controller.songsForPlaylist(outcome.playlistId);
      expect(songs, hasLength(2));
      // Strict full-track mode: the baked-in 30s iTunes previews are never
      // seeded as playable audio — songs start silent until a full-length
      // stream resolves.
      expect(songs.first.hasAudio, isFalse);
      expect(songs.first.isPreview, isFalse);
      expect(songs.first.isSilentPlaceholder, isTrue);
      controller.dispose();
    });

    test('matchesArtist strictly validates target artist inclusion', () {
      expect(SpotifyImportService.matchesArtist('Adie', 'Adie'), isTrue);
      expect(SpotifyImportService.matchesArtist('Adie, Janine Berdin', 'Adie'), isTrue);
      expect(SpotifyImportService.matchesArtist('Dom Guyot, Adie', 'Adie'), isTrue);
      expect(SpotifyImportService.matchesArtist('Arthur Nery, Adie', 'Adie'), isTrue);
      expect(SpotifyImportService.matchesArtist('Adie & Flow G', 'Adie'), isTrue);
      expect(SpotifyImportService.matchesArtist('Jeremy Camp', 'Adie'), isFalse);
      expect(SpotifyImportService.matchesArtist('Wooden Wand', 'Adie'), isFalse);
      expect(SpotifyImportService.matchesArtist('Bruno Mars', 'Adie'), isFalse);

      expect(SpotifyImportService.matchesArtist('Bruno Mars', 'Bruno Mars'), isTrue);
      expect(SpotifyImportService.matchesArtist('Lady Gaga & Bruno Mars', 'Bruno Mars'), isTrue);
      expect(SpotifyImportService.matchesArtist('Silk Sonic (Bruno Mars & Anderson .Paak)', 'Bruno Mars'), isTrue);
      expect(SpotifyImportService.matchesArtist('Adele', 'Bruno Mars'), isFalse);
      expect(SpotifyImportService.matchesArtist('Janine Berdin', 'Bruno Mars'), isFalse);

      // Works dynamically for any other artist:
      expect(SpotifyImportService.matchesArtist('Taylor Swift', 'Taylor Swift'), isTrue);
      expect(SpotifyImportService.matchesArtist('Taylor Swift feat. Post Malone', 'Taylor Swift'), isTrue);
      expect(SpotifyImportService.matchesArtist('Ed Sheeran', 'Taylor Swift'), isFalse);

      expect(SpotifyImportService.matchesArtist('The Weeknd', 'The Weeknd'), isTrue);
      expect(SpotifyImportService.matchesArtist('The Weeknd, Playboi Carti', 'The Weeknd'), isTrue);
      expect(SpotifyImportService.matchesArtist('Drake', 'The Weeknd'), isFalse);

      expect(SpotifyImportService.matchesArtist('Arthur Nery', 'Arthur Nery'), isTrue);
      expect(SpotifyImportService.matchesArtist('Arthur Nery, Adie', 'Arthur Nery'), isTrue);
      expect(SpotifyImportService.matchesArtist('Ben&Ben', 'Arthur Nery'), isFalse);
    });

    test('deleting playlist removes songs from dashboard and library in memory', () async {
      final controller = MusicPlayerController();
      final outcome = controller.importSpotifyTracks(
        playlistName: 'Adie Top Hits',
        tracks: [
          const SpotifyImportedTrack(
            spotifyId: 'track-adie-1',
            title: 'Paraluman',
            artist: 'Adie',
            album: 'Paraluman - Single',
            duration: Duration(minutes: 5, seconds: 12),
          ),
          const SpotifyImportedTrack(
            spotifyId: 'track-adie-2',
            title: 'Mahika',
            artist: 'Adie, Janine Berdin',
            album: 'Mahika - Single',
            duration: Duration(minutes: 3, seconds: 21),
          ),
        ],
      );

      final songs = controller.songsForPlaylist(outcome.playlistId);
      expect(songs, hasLength(2));

      // Delete the playlist
      final deleted = await controller.deletePlaylist(outcome.playlistId);
      expect(deleted, isTrue);

      // Playlist is gone from memory
      expect(controller.playlistById(outcome.playlistId), isNull);

      // Songs are removed from _allSongs so they do NOT appear in dashboard or library
      expect(controller.allSongs.any((s) => s.id == songs[0].id), isFalse);
      expect(controller.allSongs.any((s) => s.id == songs[1].id), isFalse);
      expect(controller.filteredSongs.any((s) => s.id == songs[0].id), isFalse);
      expect(controller.filteredSongs.any((s) => s.id == songs[1].id), isFalse);

      controller.dispose();
    });

    test('isSameArtistPlaylist accurately matches variations of artist playlist titles', () {
      expect(MusicPlayerController.isSameArtistPlaylist('Adie', 'Adie'), isTrue);
      expect(MusicPlayerController.isSameArtistPlaylist('This Is Adie', 'Adie'), isTrue);
      expect(MusicPlayerController.isSameArtistPlaylist('Adie - Top Songs', 'Adie'), isTrue);
      expect(MusicPlayerController.isSameArtistPlaylist('Adie Top Songs', 'Adie'), isTrue);
      expect(MusicPlayerController.isSameArtistPlaylist('Adie Top Tracks', 'This Is Adie'), isTrue);
      expect(MusicPlayerController.isSameArtistPlaylist('Bruno Mars', 'Bruno Mars - Top Songs'), isTrue);
      expect(MusicPlayerController.isSameArtistPlaylist('Bruno Mars', 'Best of Bruno Mars'), isTrue);

      expect(MusicPlayerController.isSameArtistPlaylist('Adie', 'Bruno Mars'), isFalse);
      expect(MusicPlayerController.isSameArtistPlaylist('Adie', 'Adele'), isFalse);
      expect(MusicPlayerController.isSameArtistPlaylist('Arthur Nery', 'Adie'), isFalse);
    });

    test('importing same artist never duplicates the artist playlist', () {
      final controller = MusicPlayerController();
      final initialPlaylistCount = controller.playlists.length;

      // 1. First import: creates 'Adie'
      final result1 = controller.importSpotifyTracks(
        playlistName: 'Adie',
        tracks: [
          const SpotifyImportedTrack(
            spotifyId: 'track-adie-1',
            title: 'Paraluman',
            artist: 'Adie',
            album: 'Paraluman - Single',
            duration: Duration(minutes: 5, seconds: 12),
          ),
        ],
      );
      expect(controller.playlists.length, initialPlaylistCount + 1);

      // 2. Second import of the same artist (e.g. 'Adie - Top Songs'): reuses existing playlist
      final result2 = controller.importSpotifyTracks(
        playlistName: 'Adie - Top Songs',
        tracks: [
          const SpotifyImportedTrack(
            spotifyId: 'track-adie-2',
            title: 'Mahika',
            artist: 'Adie, Janine Berdin',
            album: 'Mahika - Single',
            duration: Duration(minutes: 3, seconds: 21),
          ),
        ],
      );

      // Must NOT create a duplicate playlist
      expect(result2.playlistId, result1.playlistId);
      expect(controller.playlists.length, initialPlaylistCount + 1);

      // Both songs are safely merged into the single artist playlist
      final playlistSongs = controller.songsForPlaylist(result1.playlistId);
      expect(playlistSongs, hasLength(2));
      expect(playlistSongs.map((s) => s.title), containsAll(['Paraluman', 'Mahika']));

      // 3. createPlaylist also rejects duplicate artist playlist
      final createdDuplicate = controller.createPlaylist('This Is Adie');
      expect(createdDuplicate, isFalse);
      expect(controller.playlists.length, initialPlaylistCount + 1);

      controller.dispose();
    });
  });
}
