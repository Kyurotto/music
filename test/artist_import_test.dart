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
    test('artist tracks arrive with playable previews, no silent gap',
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
      expect(songs.first.hasAudio, isTrue);
      expect(songs.first.isPreview, isTrue);
      expect(songs.first.audioUrl, 'https://example.com/neon.m4a');
      expect(songs.first.isSilentPlaceholder, isFalse);
      controller.dispose();
    });
  });
}
