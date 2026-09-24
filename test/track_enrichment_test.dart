import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:music/models/song_model.dart';
import 'package:music/services/track_enrichment_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TrackEnrichmentService serviceFor(
    Future<http.Response> Function(http.Request) handler,
  ) {
    return TrackEnrichmentService(client: MockClient(handler));
  }

  http.Response jsonOk(Object body) => http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json'},
      );

  group('TrackEnrichmentService audio', () {
    test('picks the best iTunes title/artist match, not a cover', () async {
      final service = serviceFor((request) async {
        if (request.url.host == 'itunes.apple.com') {
          return jsonOk({
            'results': [
              {
                'trackName': 'Multo Karaoke Version',
                'artistName': 'Sing Along Kings',
                'previewUrl': 'https://example.com/karaoke.m4a',
                'kind': 'song',
              },
              {
                'trackName': 'Multo',
                'artistName': 'Cup of Joe',
                'previewUrl': 'https://example.com/multo.m4a',
                'artworkUrl100':
                    'https://example.com/art/100x100bb.jpg',
                'trackTimeMillis': 245000,
                'kind': 'song',
              },
            ],
          });
        }
        return http.Response('not found', 404);
      });

      final enrichment = await service.enrichTrack(
        title: 'Multo',
        artist: 'Cup of Joe',
      );
      expect(enrichment.previewUrl, 'https://example.com/multo.m4a');
      expect(enrichment.artworkUrl,
          'https://example.com/art/600x600bb.jpg');
      service.dispose();
    });

    test('falls back to Deezer when iTunes has no match', () async {
      final service = serviceFor((request) async {
        if (request.url.host == 'itunes.apple.com') {
          return jsonOk({'results': []});
        }
        if (request.url.host == 'api.deezer.com') {
          return jsonOk({
            'data': [
              {
                'title': 'Tingin',
                'artist': {'name': 'Cup of Joe'},
                'preview': 'https://example.com/tingin.mp3',
                'album': {'cover_xl': 'https://example.com/cover.jpg'},
              },
            ],
          });
        }
        return http.Response('not found', 404);
      });

      final enrichment = await service.enrichTrack(
        title: 'Tingin',
        artist: 'Cup of Joe',
      );
      expect(enrichment.previewUrl, 'https://example.com/tingin.mp3');
      expect(enrichment.artworkUrl, 'https://example.com/cover.jpg');
      service.dispose();
    });

    test('returns empty enrichment when every source fails', () async {
      final service = serviceFor((_) async => http.Response('nope', 404));
      final enrichment = await service.enrichTrack(
        title: 'Unknown Song',
        artist: 'Unknown Artist',
      );
      expect(enrichment.hasAudio, isFalse);
      expect(enrichment.hasLyrics, isFalse);
      service.dispose();
    });
  });

  group('TrackEnrichmentService lyrics', () {
    test('uses lyrics.ovh when available', () async {
      final service = serviceFor((request) async {
        if (request.url.host == 'api.lyrics.ovh') {
          return jsonOk({'lyrics': 'line one\nline two\n\nline three'});
        }
        if (request.url.host == 'itunes.apple.com') {
          return jsonOk({'results': []});
        }
        if (request.url.host == 'api.deezer.com') {
          return jsonOk({'data': []});
        }
        return http.Response('not found', 404);
      });

      final enrichment = await service.enrichTrack(
        title: 'Multo',
        artist: 'Cup of Joe',
      );
      expect(enrichment.lyrics, ['line one', 'line two', 'line three']);
      service.dispose();
    });

    test('falls back to LRCLIB plain lyrics when ovh misses', () async {
      final service = serviceFor((request) async {
        if (request.url.host == 'api.lyrics.ovh') {
          return http.Response('not found', 404);
        }
        if (request.url.host == 'lrclib.net') {
          return jsonOk({
            'plainLyrics': 'first line\nsecond line',
            'syncedLyrics': null,
            'instrumental': false,
          });
        }
        if (request.url.host == 'itunes.apple.com') {
          return jsonOk({'results': []});
        }
        if (request.url.host == 'api.deezer.com') {
          return jsonOk({'data': []});
        }
        return http.Response('not found', 404);
      });

      final enrichment = await service.enrichTrack(
        title: 'Multo',
        artist: 'Cup of Joe',
      );
      expect(enrichment.lyrics, ['first line', 'second line']);
      service.dispose();
    });

    test('parses LRCLIB synced lyrics by stripping timestamps', () async {
      final service = serviceFor((request) async {
        if (request.url.host == 'api.lyrics.ovh') {
          return http.Response('not found', 404);
        }
        if (request.url.host == 'lrclib.net') {
          return jsonOk({
            'plainLyrics': null,
            'syncedLyrics':
                '[00:01.00] hello\n[00:05.50] world\n[00:09.00]  ',
            'instrumental': false,
          });
        }
        if (request.url.host == 'itunes.apple.com') {
          return jsonOk({'results': []});
        }
        if (request.url.host == 'api.deezer.com') {
          return jsonOk({'data': []});
        }
        return http.Response('not found', 404);
      });

      final enrichment = await service.enrichTrack(
        title: 'Multo',
        artist: 'Cup of Joe',
      );
      expect(enrichment.lyrics, ['hello', 'world']);
      service.dispose();
    });

    test('sends album and duration to LRCLIB exact lookup', () async {
      var sawDuration = false;
      var sawAlbum = false;
      final service = serviceFor((request) async {
        if (request.url.host == 'api.lyrics.ovh') {
          return http.Response('not found', 404);
        }
        if (request.url.host == 'lrclib.net' &&
            request.url.path == '/api/get') {
          sawDuration =
              request.url.queryParameters['duration'] == '269';
          sawAlbum =
              request.url.queryParameters['album_name'] == 'Uptown Special';
          return jsonOk({
            'plainLyrics': 'exact hit',
            'syncedLyrics': null,
            'instrumental': false,
          });
        }
        if (request.url.host == 'itunes.apple.com') {
          return jsonOk({'results': []});
        }
        if (request.url.host == 'api.deezer.com') {
          return jsonOk({'data': []});
        }
        return http.Response('not found', 404);
      });

      final enrichment = await service.enrichTrack(
        title: 'Uptown Funk',
        artist: 'Mark Ronson',
        album: 'Uptown Special',
        duration: const Duration(seconds: 269),
      );
      expect(enrichment.lyrics, ['exact hit']);
      expect(sawDuration, isTrue);
      expect(sawAlbum, isTrue);
      service.dispose();
    });

    test('falls back to LRCLIB search when exact lookup misses', () async {
      final service = serviceFor((request) async {
        if (request.url.host == 'api.lyrics.ovh') {
          return http.Response('not found', 404);
        }
        if (request.url.host == 'lrclib.net' &&
            request.url.path == '/api/get') {
          return http.Response('not found', 404);
        }
        if (request.url.host == 'lrclib.net' &&
            request.url.path == '/api/search') {
          return jsonOk([
            {
              'trackName': 'Uptown Funk',
              'artistName': 'Mark Ronson',
              'plainLyrics': 'search hit line',
              'syncedLyrics': null,
              'instrumental': false,
            },
          ]);
        }
        if (request.url.host == 'itunes.apple.com') {
          return jsonOk({'results': []});
        }
        if (request.url.host == 'api.deezer.com') {
          return jsonOk({'data': []});
        }
        return http.Response('not found', 404);
      });

      final enrichment = await service.enrichTrack(
        title: 'Uptown Funk',
        artist: 'Mark Ronson',
      );
      expect(enrichment.lyrics, ['search hit line']);
      service.dispose();
    });
  });

  group('TrackEnrichmentService full-length audio', () {
    http.Response saavnOk(List<Map<String, dynamic>> songs) => jsonOk({
          'success': true,
          'data': {'results': songs},
        });

    Map<String, dynamic> saavnSong({
      required String name,
      required String artist,
      required String url,
      int duration = 245,
    }) =>
        {
          'id': 'test-id-$name',
          'name': name,
          'artists': {
            'primary': [
              {'name': artist},
            ],
          },
          'duration': duration,
          'image': [
            {'url': 'https://example.com/cover500.jpg'},
          ],
          'downloadUrl': [
            {'quality': '96kbps', 'url': 'https://example.com/low.mp3'},
            {'quality': '320kbps', 'url': url},
          ],
        };

    test('prefers full-length Saavn stream over iTunes preview', () async {
      final service = serviceFor((request) async {
        if (request.url.host == 'saavn.dev') {
          return saavnOk([
            saavnSong(
              name: 'Multo',
              artist: 'Cup of Joe',
              url: 'https://example.com/multo-full-320.mp3',
            ),
          ]);
        }
        if (request.url.host == 'itunes.apple.com') {
          return jsonOk({
            'results': [
              {
                'trackName': 'Multo',
                'artistName': 'Cup of Joe',
                'previewUrl': 'https://example.com/multo-30s.m4a',
                'kind': 'song',
              },
            ],
          });
        }
        if (request.url.host == 'api.deezer.com') {
          return jsonOk({'data': []});
        }
        if (request.url.host == 'api.lyrics.ovh') {
          return http.Response('not found', 404);
        }
        if (request.url.host == 'lrclib.net') {
          return http.Response('not found', 404);
        }
        return http.Response('not found', 404);
      });

      final enrichment = await service.enrichTrack(
        title: 'Multo',
        artist: 'Cup of Joe',
      );
      expect(
        enrichment.previewUrl,
        'https://example.com/multo-full-320.mp3',
      );
      expect(enrichment.isFullTrack, isTrue);
      service.dispose();
    });

    test('picks the best Saavn title match, not a cover', () async {
      final service = serviceFor((request) async {
        if (request.url.host == 'saavn.dev') {
          return saavnOk([
            saavnSong(
              name: 'Multo Karaoke Version',
              artist: 'Sing Along Kings',
              url: 'https://example.com/karaoke-full.mp3',
            ),
            saavnSong(
              name: 'Multo',
              artist: 'Cup of Joe',
              url: 'https://example.com/multo-full.mp3',
            ),
          ]);
        }
        if (request.url.host == 'itunes.apple.com') {
          return jsonOk({'results': []});
        }
        if (request.url.host == 'api.deezer.com') {
          return jsonOk({'data': []});
        }
        return http.Response('not found', 404);
      });

      final enrichment = await service.enrichTrack(
        title: 'Multo',
        artist: 'Cup of Joe',
      );
      expect(enrichment.previewUrl, 'https://example.com/multo-full.mp3');
      expect(enrichment.isFullTrack, isTrue);
      service.dispose();
    });

    test('falls back to iTunes preview when Saavn misses', () async {
      final service = serviceFor((request) async {
        if (request.url.host == 'saavn.dev') {
          return http.Response('not found', 404);
        }
        if (request.url.host == 'itunes.apple.com') {
          return jsonOk({
            'results': [
              {
                'trackName': 'Tingin',
                'artistName': 'Cup of Joe',
                'previewUrl': 'https://example.com/tingin-30s.m4a',
                'kind': 'song',
              },
            ],
          });
        }
        if (request.url.host == 'api.deezer.com') {
          return jsonOk({'data': []});
        }
        return http.Response('not found', 404);
      });

      final enrichment = await service.enrichTrack(
        title: 'Tingin',
        artist: 'Cup of Joe',
      );
      expect(enrichment.previewUrl, 'https://example.com/tingin-30s.m4a');
      expect(enrichment.isFullTrack, isFalse);
      service.dispose();
    });

    test('uses a compatible preview directly after full-track playback fails',
        () async {
      var fullSourceRequests = 0;
      final service = serviceFor((request) async {
        if (request.url.host.startsWith('saavn.') ||
            request.url.host == 'www.youtube.com') {
          fullSourceRequests++;
          return http.Response('full source should be skipped', 500);
        }
        if (request.url.host == 'itunes.apple.com') {
          return jsonOk({
            'results': [
              {
                'trackName': 'Tingin',
                'artistName': 'Cup of Joe',
                'previewUrl': 'https://example.com/tingin-30s.m4a',
                'kind': 'song',
              },
            ],
          });
        }
        if (request.url.host == 'api.deezer.com') {
          return jsonOk({'data': []});
        }
        return http.Response('not found', 404);
      });

      final enrichment = await service.enrichTrack(
        title: 'Tingin',
        artist: 'Cup of Joe',
        previewFallbackOnly: true,
      );

      expect(fullSourceRequests, 0);
      expect(enrichment.previewUrl, 'https://example.com/tingin-30s.m4a');
      expect(enrichment.isFullTrack, isFalse);
      service.dispose();
    });

    test('tries the saavn mirror when the primary host fails', () async {
      final service = serviceFor((request) async {
        if (request.url.host == 'saavn.sumit.co') {
          return http.Response('gateway down', 502);
        }
        if (request.url.host == 'saavn.dev') {
          return saavnOk([
            saavnSong(
              name: 'Multo',
              artist: 'Cup of Joe',
              url: 'https://example.com/multo-mirror.mp3',
            ),
          ]);
        }
        if (request.url.host == 'itunes.apple.com') {
          return jsonOk({'results': []});
        }
        if (request.url.host == 'api.deezer.com') {
          return jsonOk({'data': []});
        }
        return http.Response('not found', 404);
      });

      final enrichment = await service.enrichTrack(
        title: 'Multo',
        artist: 'Cup of Joe',
      );
      expect(enrichment.previewUrl, 'https://example.com/multo-mirror.mp3');
      expect(enrichment.isFullTrack, isTrue);
      service.dispose();
    });

    test('rejects Saavn remixes with the wrong artist', () async {
      // Live case: "Multo" search returns only HYPERTECHNO remixes by other
      // uploaders. A correct 30s preview must win over a wrong full song.
      final service = serviceFor((request) async {
        if (request.url.host.startsWith('saavn.')) {
          return saavnOk([
            saavnSong(
              name: 'MULTO (HYPERTECHNO SPED UP)',
              artist: 'Fantasia Recordings',
              url: 'https://example.com/wrong-remix.mp3',
            ),
          ]);
        }
        if (request.url.host == 'itunes.apple.com') {
          return jsonOk({
            'results': [
              {
                'trackName': 'Multo',
                'artistName': 'Cup of Joe',
                'previewUrl': 'https://example.com/multo-30s.m4a',
                'kind': 'song',
              },
            ],
          });
        }
        if (request.url.host == 'api.deezer.com') {
          return jsonOk({'data': []});
        }
        return http.Response('not found', 404);
      });

      final enrichment = await service.enrichTrack(
        title: 'Multo',
        artist: 'Cup of Joe',
      );
      expect(enrichment.previewUrl, 'https://example.com/multo-30s.m4a');
      expect(enrichment.isFullTrack, isFalse);
      service.dispose();
    });

    test('retries Saavn with title-only query when needed', () async {
      final service = serviceFor((request) async {
        if (request.url.host.startsWith('saavn.')) {
          // "Multo Cup of Joe" returns nothing; "Multo" finds the track.
          if ((request.url.queryParameters['query'] ?? '').contains(' ')) {
            return saavnOk(const []);
          }
          return saavnOk([
            saavnSong(
              name: 'Multo',
              artist: 'Cup of Joe',
              url: 'https://example.com/multo-title-only.mp3',
            ),
          ]);
        }
        if (request.url.host == 'itunes.apple.com') {
          return jsonOk({'results': []});
        }
        if (request.url.host == 'api.deezer.com') {
          return jsonOk({'data': []});
        }
        return http.Response('not found', 404);
      });

      final enrichment = await service.enrichTrack(
        title: 'Multo',
        artist: 'Cup of Joe',
      );
      expect(
        enrichment.previewUrl,
        'https://example.com/multo-title-only.mp3',
      );
      expect(enrichment.isFullTrack, isTrue);
      service.dispose();
    });
  });

  group('TrackEnrichmentService YouTube full-length audio', () {
    Map<String, dynamic> ytVideo({
      required String videoId,
      required String title,
      required String channel,
      String length = '4:00',
      bool liveLengthShape = false,
    }) =>
        {
          'compactVideoRenderer': {
            'videoId': videoId,
            'title': {
              'runs': [
                {'text': title},
              ],
            },
            'longBylineText': {
              'runs': [
                {'text': channel},
              ],
            },
            // Live ANDROID search omits simpleText and only ships runs.
            'lengthText': liveLengthShape
                ? {
                    'runs': [
                      {'text': length},
                    ],
                    'accessibility': {
                      'accessibilityData': {
                        'label': '4 minutes, 1 second',
                      },
                    },
                  }
                : {'simpleText': length},
          },
        };

    http.Response ytSearchOk(List<Map<String, dynamic>> videos) => jsonOk({
          'contents': {
            'sectionListRenderer': {
              'contents': [
                {
                  'itemSectionRenderer': {'contents': videos},
                },
              ],
            },
          },
        });

    http.Response ytPlayerOk({
      required String url,
      int bitrate = 130951,
      int lengthSeconds = 240,
    }) =>
        jsonOk({
          'playabilityStatus': {'status': 'OK'},
          'videoDetails': {'lengthSeconds': '$lengthSeconds'},
          'streamingData': {
            'adaptiveFormats': [
              {
                'itag': 140,
                'mimeType': 'audio/mp4; codecs="mp4a.40.2"',
                'bitrate': bitrate,
                'url': url,
              },
              {
                'itag': 249,
                'mimeType': 'audio/webm; codecs="opus"',
                'bitrate': 50000,
                'url': 'https://example.com/low.opus',
              },
            ],
          },
        });

    TrackEnrichmentService youtubeService(
      Future<http.Response> Function(http.Request) handler,
    ) {
      return TrackEnrichmentService(client: MockClient(handler));
    }

    test('resolves full-length YouTube audio when catalogs miss', () async {
      final service = youtubeService((request) async {
        if (request.url.host.startsWith('saavn.')) {
          return http.Response('not found', 404);
        }
        if (request.url.host == 'www.youtube.com' &&
            request.url.path == '/youtubei/v1/search') {
          return ytSearchOk([
            ytVideo(
              videoId: 'Rht8rS4cR1s',
              title: 'Multo - Cup of Joe (Official Lyric Video)',
              channel: 'Cup of Joe',
              // Live ANDROID shape: lengthText has runs, no simpleText.
              length: '4:01',
              liveLengthShape: true,
            ),
          ]);
        }
        if (request.url.host == 'www.youtube.com' &&
            request.url.path == '/youtubei/v1/player') {
          return ytPlayerOk(url: 'https://example.com/multo-full.m4a');
        }
        if (request.url.host == 'itunes.apple.com') {
          return jsonOk({
            'results': [
              {
                'trackName': 'Multo',
                'artistName': 'Cup of Joe',
                'previewUrl': 'https://example.com/multo-30s.m4a',
                'kind': 'song',
              },
            ],
          });
        }
        if (request.url.host == 'api.deezer.com') {
          return jsonOk({'data': []});
        }
        if (request.url.host == 'api.lyrics.ovh') {
          return http.Response('not found', 404);
        }
        if (request.url.host == 'lrclib.net') {
          return http.Response('not found', 404);
        }
        return http.Response('not found', 404);
      });

      final enrichment = await service.enrichTrack(
        title: 'Multo',
        artist: 'Cup of Joe',
        duration: const Duration(seconds: 245),
      );
      expect(enrichment.previewUrl, 'https://example.com/multo-full.m4a');
      expect(enrichment.isFullTrack, isTrue);
      expect(enrichment.isYouTube, isTrue);
      expect(enrichment.artworkUrl, contains('Rht8rS4cR1s'));
      service.dispose();
    });

    test('accepts official video when artist is only in the title (label channel)', () async {
      // Live-shaped case: upload channel is a label, artist credit is in
      // the title — must still attach as full-length YouTube audio.
      final service = serviceFor((request) async {
        if (request.url.host.startsWith('saavn.')) {
          return http.Response('not found', 404);
        }
        if (request.url.host == 'www.youtube.com' &&
            request.url.path == '/youtubei/v1/search') {
          return ytSearchOk([
            ytVideo(
              videoId: 'LabelChannel1',
              title: 'Multo - Cup of Joe (Official Audio)',
              channel: 'Sony Music PH',
            ),
          ]);
        }
        if (request.url.host == 'www.youtube.com' &&
            request.url.path == '/youtubei/v1/player') {
          return ytPlayerOk(url: 'https://example.com/multo-label.m4a');
        }
        if (request.url.host == 'itunes.apple.com') {
          return jsonOk({'results': []});
        }
        if (request.url.host == 'api.deezer.com') {
          return jsonOk({'data': []});
        }
        if (request.url.host == 'api.lyrics.ovh') {
          return http.Response('not found', 404);
        }
        if (request.url.host == 'lrclib.net') {
          return http.Response('not found', 404);
        }
        return http.Response('not found', 404);
      });

      final enrichment = await service.enrichTrack(
        title: 'Multo',
        artist: 'Cup of Joe',
        duration: const Duration(seconds: 245),
      );
      expect(enrichment.previewUrl, 'https://example.com/multo-label.m4a');
      expect(enrichment.isFullTrack, isTrue);
      expect(enrichment.isYouTube, isTrue);
      service.dispose();
    });

    test('skips karaoke uploads and wrong artists on YouTube', () async {
      final service = youtubeService((request) async {
        if (request.url.host.startsWith('saavn.')) {
          return http.Response('not found', 404);
        }
        if (request.url.host == 'www.youtube.com' &&
            request.url.path == '/youtubei/v1/search') {
          return ytSearchOk([
            ytVideo(
              videoId: 'Karaoke001',
              title: 'Multo - Cup of Joe (Karaoke Version)',
              channel: 'Sing Along Kings',
              liveLengthShape: true,
            ),
            ytVideo(
              videoId: 'Wrong00001',
              title: 'Multo (Cover)',
              channel: 'Random Uploader',
              liveLengthShape: true,
            ),
          ]);
        }
        if (request.url.host == 'www.youtube.com' &&
            request.url.path == '/youtubei/v1/player') {
          return ytPlayerOk(url: 'https://example.com/should-not-use.m4a');
        }
        if (request.url.host == 'itunes.apple.com') {
          return jsonOk({
            'results': [
              {
                'trackName': 'Multo',
                'artistName': 'Cup of Joe',
                'previewUrl': 'https://example.com/multo-30s.m4a',
                'kind': 'song',
              },
            ],
          });
        }
        if (request.url.host == 'api.deezer.com') {
          return jsonOk({'data': []});
        }
        return http.Response('not found', 404);
      });

      final enrichment = await service.enrichTrack(
        title: 'Multo',
        artist: 'Cup of Joe',
        duration: const Duration(seconds: 245),
      );
      expect(enrichment.previewUrl, 'https://example.com/multo-30s.m4a');
      expect(enrichment.isFullTrack, isFalse);
      expect(enrichment.isYouTube, isFalse);
      service.dispose();
    });

    test('does not treat live runs-only lengthText as zero length', () async {
      // Regression: live ANDROID search ships lengthText as runs only.
      // Returning 0 discarded every video and forced the 30s iTunes path.
      final service = youtubeService((request) async {
        if (request.url.host.startsWith('saavn.')) {
          return http.Response('not found', 404);
        }
        if (request.url.host == 'www.youtube.com' &&
            request.url.path == '/youtubei/v1/search') {
          return ytSearchOk([
            ytVideo(
              videoId: 'RunsOnlyLen1',
              title: 'Multo - Cup of Joe (Official Music Video)',
              channel: 'Cup of Joe and Viva Records',
              length: '3:58',
              liveLengthShape: true,
            ),
          ]);
        }
        if (request.url.host == 'www.youtube.com' &&
            request.url.path == '/youtubei/v1/player') {
          return ytPlayerOk(url: 'https://example.com/multo-runs.m4a');
        }
        if (request.url.host == 'itunes.apple.com') {
          return jsonOk({'results': []});
        }
        if (request.url.host == 'api.deezer.com') {
          return jsonOk({'data': []});
        }
        if (request.url.host == 'api.lyrics.ovh') {
          return http.Response('not found', 404);
        }
        if (request.url.host == 'lrclib.net') {
          return http.Response('not found', 404);
        }
        return http.Response('not found', 404);
      });

      final enrichment = await service.enrichTrack(
        title: 'Multo',
        artist: 'Cup of Joe',
      );
      expect(enrichment.previewUrl, 'https://example.com/multo-runs.m4a');
      expect(enrichment.isFullTrack, isTrue);
      expect(enrichment.isYouTube, isTrue);
      service.dispose();
    });
  });

  group('Song lyrics tracker math', () {
    final lines = List<String>.generate(10, (i) => 'line $i');
    const total = Duration(minutes: 4); // 240s -> 24s per line

    test('maps playback progress to the active lyric line', () {
      expect(
        Song.lyricsLineIndexForProgress(
            lines, Duration.zero, total),
        0,
      );
      expect(
        Song.lyricsLineIndexForProgress(
            lines, const Duration(seconds: 24), total),
        1,
      );
      expect(
        Song.lyricsLineIndexForProgress(
            lines, const Duration(seconds: 120), total),
        5,
      );
      expect(
        Song.lyricsLineIndexForProgress(
            lines, total, total),
        9,
      );
      expect(
        Song.lyricsLineIndexForProgress(
            lines, total + const Duration(seconds: 30), total),
        9,
      );
    });

    test('returns 0 for empty lyrics or unknown duration', () {
      expect(
        Song.lyricsLineIndexForProgress(
            const [], const Duration(seconds: 10), total),
        0,
      );
      expect(
        Song.lyricsLineIndexForProgress(
            lines, const Duration(seconds: 10), Duration.zero),
        0,
      );
    });

    test('tapping a line seeks to that line position', () {
      expect(
        Song.positionForLyricsLine(lines, 0, total),
        Duration.zero,
      );
      expect(
        Song.positionForLyricsLine(lines, 5, total),
        const Duration(seconds: 120),
      );
      expect(
        Song.positionForLyricsLine(lines, 999, total),
        Song.positionForLyricsLine(lines, 9, total),
      );
      // Round-trip: seek then progress maps back to the same line.
      final pos = Song.positionForLyricsLine(lines, 3, total);
      expect(Song.lyricsLineIndexForProgress(lines, pos, total), 3);
    });
  });
}

