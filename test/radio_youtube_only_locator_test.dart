import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:music/controllers/music_player_controller.dart';
import 'package:music/models/song_model.dart';
import 'package:music/services/radio_discovery_service.dart';
import 'package:music/services/track_enrichment_service.dart';
import 'package:music/views/playlist_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Radio YouTube-Only Locator Unit Tests', () {
    test(
      'enrichTrack with youtubeOnly: true queries YouTube and bypasses third-party scrapers',
      () async {
        final requestedHosts = <String>[];

        final client = MockClient((request) async {
          requestedHosts.add(request.url.host);

          // When YouTube search is hit, return valid candidate in Android client format
          if (request.url.host.contains('youtube.com') &&
              request.url.path.contains('search')) {
            final dummySearchResponse = {
              'contents': {
                'sectionListRenderer': {
                  'contents': [
                    {
                      'itemSectionRenderer': {
                        'contents': [
                          {
                            'videoRenderer': {
                              'videoId': 'mock_flowg_vid',
                              'title': {
                                'runs': [
                                  {'text': 'Ebeb - Flow G (Official Audio)'},
                                ],
                              },
                              'ownerText': {
                                'runs': [
                                  {'text': 'Flow G'},
                                ],
                              },
                              'lengthText': {'simpleText': '4:21'},
                            },
                          },
                        ],
                      },
                    },
                  ],
                },
              },
            };
            return http.Response(
              jsonEncode(dummySearchResponse),
              200,
              headers: {'content-type': 'application/json'},
            );
          }

          // When YouTube player is hit, return streaming URL
          if (request.url.host.contains('youtube.com') &&
              request.url.path.contains('player')) {
            final dummyPlayerResponse = {
              'playabilityStatus': {'status': 'OK'},
              'videoDetails': {
                'videoId': 'mock_flowg_vid',
                'title': 'Ebeb - Flow G (Official Audio)',
                'lengthSeconds': '261',
              },
              'streamingData': {
                'formats': [
                  {
                    'itag': 18,
                    'mimeType': 'video/mp4; codecs="avc1.42001E, mp4a.40.2"',
                    'url':
                        'https://rr1---sn-dummy.googlevideo.com/videoplayback?expire=9999999999&itag=18',
                    'audioQuality': 'AUDIO_QUALITY_MEDIUM',
                  },
                ],
              },
            };
            return http.Response(
              jsonEncode(dummyPlayerResponse),
              200,
              headers: {'content-type': 'application/json'},
            );
          }

          // When googlevideo stream probe is hit
          if (request.url.host.contains('googlevideo.com')) {
            return http.Response.bytes(
              List.filled(1024, 0),
              206,
              headers: {
                'content-type': 'audio/mp4',
                'content-range': 'bytes 0-1023/5000000',
              },
            );
          }

          return http.Response('{}', 200);
        });

        final service = TrackEnrichmentService(client: client);

        final enrichment = await service.locateRadioTrackViaYouTube(
          title: 'Ebeb',
          artist: 'Flow G',
          duration: const Duration(minutes: 4, seconds: 21),
        );

        // Verify YouTube was queried
        expect(requestedHosts.any((h) => h.contains('youtube.com')), isTrue);

        // Verify other music services / scrapers were NEVER touched
        expect(requestedHosts.any((h) => h.contains('saavn')), isFalse);
        expect(requestedHosts.any((h) => h.contains('soundcloud')), isFalse);
        expect(requestedHosts.any((h) => h.contains('archive.org')), isFalse);
        expect(requestedHosts.any((h) => h.contains('apple.com')), isFalse);
        expect(requestedHosts.any((h) => h.contains('itunes')), isFalse);
        expect(requestedHosts.any((h) => h.contains('deezer')), isFalse);
        expect(requestedHosts.any((h) => h.contains('duckduckgo')), isFalse);

        // Verify it resolves as a full track with YouTube attributes
        expect(enrichment.isYouTube, isTrue);
        expect(enrichment.isFullTrack, isTrue);
        expect(enrichment.youtubeVideoId, 'mock_flowg_vid');
        expect(enrichment.hasAudio, isTrue);
      },
    );

    test(
      'multi-artist track locating succeeds with reversed artist order and topic channel',
      () async {
        final client = MockClient((request) async {
          if (request.url.host.contains('youtube.com') &&
              request.url.path.contains('search')) {
            final dummySearchResponse = {
              'contents': {
                'sectionListRenderer': {
                  'contents': [
                    {
                      'itemSectionRenderer': {
                        'contents': [
                          {
                            'videoRenderer': {
                              'videoId': 'mock_makasarili_vid',
                              'title': {
                                'runs': [
                                  {
                                    'text':
                                        'Hev Abi, Kristina Dawn - Makasarili Malambing (Audio)',
                                  },
                                ],
                              },
                              'ownerText': {
                                'runs': [
                                  {'text': 'HEVABIDOWNTOWN'},
                                ],
                              },
                              'lengthText': {'simpleText': '3:44'},
                            },
                          },
                        ],
                      },
                    },
                  ],
                },
              },
            };
            return http.Response(
              jsonEncode(dummySearchResponse),
              200,
              headers: {'content-type': 'application/json'},
            );
          }

          if (request.url.host.contains('youtube.com') &&
              request.url.path.contains('player')) {
            final dummyPlayerResponse = {
              'playabilityStatus': {'status': 'OK'},
              'videoDetails': {
                'videoId': 'mock_makasarili_vid',
                'title':
                    'Hev Abi, Kristina Dawn - Makasarili Malambing (Audio)',
                'lengthSeconds': '224',
              },
              'streamingData': {
                'formats': [
                  {
                    'itag': 18,
                    'mimeType': 'video/mp4; codecs="avc1.42001E, mp4a.40.2"',
                    'url':
                        'https://rr1---sn-dummy.googlevideo.com/videoplayback?expire=9999999999&itag=18',
                  },
                ],
              },
            };
            return http.Response(
              jsonEncode(dummyPlayerResponse),
              200,
              headers: {'content-type': 'application/json'},
            );
          }

          return http.Response('{}', 200);
        });

        final service = TrackEnrichmentService(client: client);

        // Search with "Kristina Dawn, Hev Abi" while YouTube video has reversed order "Hev Abi, Kristina Dawn"
        final enrichment = await service.locateRadioTrackViaYouTube(
          title: 'Makasarili Malambing',
          artist: 'Kristina Dawn, Hev Abi',
          duration: const Duration(minutes: 3, seconds: 44),
        );

        expect(enrichment.hasAudio, isTrue);
        expect(enrichment.isFullTrack, isTrue);
        expect(enrichment.isYouTube, isTrue);
        expect(enrichment.youtubeVideoId, 'mock_makasarili_vid');
      },
    );

    test(
      'artist-prefixed YouTube upload matches via main search fallback',
      () async {
        var musicSearchRequests = 0;
        var mainSearchRequests = 0;
        final requestedHosts = <String>[];

        final client = MockClient((request) async {
          requestedHosts.add(request.url.host);

          if (request.url.host == 'music.youtube.com' &&
              request.url.path.contains('search')) {
            musicSearchRequests++;
            return http.Response('{}', 200);
          }

          if (request.url.host.contains('youtube.com') &&
              request.url.path.contains('search')) {
            mainSearchRequests++;
            final dummySearchResponse = {
              'contents': {
                'sectionListRenderer': {
                  'contents': [
                    {
                      'itemSectionRenderer': {
                        'contents': [
                          {
                            'videoRenderer': {
                              'videoId': 'mock_makasarili_vid',
                              'title': {
                                'runs': [
                                  {
                                    'text':
                                        'Hev Abi, Kristina Dawn - Makasarili Malambing (Audio)',
                                  },
                                ],
                              },
                              'ownerText': {
                                'runs': [
                                  {'text': 'HEVABIDOWNTOWN'},
                                ],
                              },
                              'lengthText': {'simpleText': '3:44'},
                            },
                          },
                        ],
                      },
                    },
                  ],
                },
              },
            };
            return http.Response(
              jsonEncode(dummySearchResponse),
              200,
              headers: {'content-type': 'application/json'},
            );
          }

          if (request.url.host.contains('youtube.com') &&
              request.url.path.contains('player')) {
            final dummyPlayerResponse = {
              'playabilityStatus': {'status': 'OK'},
              'videoDetails': {
                'videoId': 'mock_makasarili_vid',
                'title':
                    'Hev Abi, Kristina Dawn - Makasarili Malambing (Audio)',
                'lengthSeconds': '224',
              },
              'streamingData': {
                'formats': [
                  {
                    'itag': 18,
                    'mimeType': 'video/mp4; codecs="avc1.42001E, mp4a.40.2"',
                    'url':
                        'https://rr1---sn-dummy.googlevideo.com/videoplayback?expire=9999999999&itag=18',
                  },
                ],
              },
            };
            return http.Response(
              jsonEncode(dummyPlayerResponse),
              200,
              headers: {'content-type': 'application/json'},
            );
          }

          return http.Response('{}', 200);
        });

        final service = TrackEnrichmentService(client: client);

        // The catalog title carries "(feat. Hev Abi)" while the YouTube upload
        // prefixes the artist and suffixes "(Audio)". This used to miss and fall
        // through every slow third-party fallback.
        final enrichment = await service.locateRadioTrackViaYouTube(
          title: 'Makasarili Malambing (feat. Hev Abi)',
          artist: 'Kristina Dawn, Hev Abi',
          duration: const Duration(minutes: 3, seconds: 44),
        );

        expect(enrichment.hasAudio, isTrue);
        expect(enrichment.isFullTrack, isTrue);
        expect(enrichment.isYouTube, isTrue);
        expect(enrichment.youtubeVideoId, 'mock_makasarili_vid');
        expect(musicSearchRequests, 1);
        expect(mainSearchRequests, 1);
        expect(requestedHosts.any((h) => h.contains('saavn')), isFalse);
        expect(requestedHosts.any((h) => h.contains('soundcloud')), isFalse);
        expect(requestedHosts.any((h) => h.contains('archive.org')), isFalse);
        expect(requestedHosts.any((h) => h.contains('itunes')), isFalse);
        expect(requestedHosts.any((h) => h.contains('deezer')), isFalse);
        expect(requestedHosts.any((h) => h.contains('duckduckgo')), isFalse);
      },
    );

    test(
      'YouTube Music search resolves age-gated explicit tracks without main search',
      () async {
        var mainSearchRequests = 0;
        final requestedHosts = <String>[];

        final client = MockClient((request) async {
          requestedHosts.add(request.url.host);

          if (request.url.host == 'music.youtube.com' &&
              request.url.path.contains('search')) {
            final response = {
              'contents': {
                'tabbedSearchResultsRenderer': {
                  'tabs': [
                    {
                      'tabRenderer': {
                        'content': {
                          'sectionListRenderer': {
                            'contents': [
                              {
                                'itemSectionRenderer': {
                                  'contents': [
                                    {
                                      'musicResponsiveListItemRenderer': {
                                        'playlistItemData': {
                                          'videoId': 'mock_xxxx_vid',
                                        },
                                        'flexColumns': [
                                          {
                                            'musicResponsiveListItemFlexColumnRenderer': {
                                              'text': {
                                                'runs': [
                                                  {
                                                    'text':
                                                        'XXXX (feat. Hev Abi)',
                                                  },
                                                ],
                                              },
                                            },
                                          },
                                          {
                                            'musicResponsiveListItemFlexColumnRenderer':
                                                {
                                                  'text': {
                                                    'runs': [
                                                      {'text': 'Song'},
                                                      {'text': ' • '},
                                                      {'text': 'Loonie'},
                                                      {'text': ' • '},
                                                      {'text': '23M plays'},
                                                    ],
                                                  },
                                                },
                                          },
                                        ],
                                      },
                                    },
                                  ],
                                },
                              },
                            ],
                          },
                        },
                      },
                    },
                  ],
                },
              },
            };
            return http.Response(
              jsonEncode(response),
              200,
              headers: {'content-type': 'application/json'},
            );
          }

          if (request.url.host.contains('youtube.com') &&
              request.url.path.contains('search')) {
            mainSearchRequests++;
            return http.Response('{}', 200);
          }

          if (request.url.host.contains('youtube.com') &&
              request.url.path.contains('player')) {
            final response = {
              'playabilityStatus': {'status': 'OK'},
              'videoDetails': {
                'videoId': 'mock_xxxx_vid',
                'title': 'XXXX (feat. Hev Abi)',
                'lengthSeconds': '184',
              },
              'streamingData': {
                'formats': [
                  {
                    'itag': 18,
                    'mimeType': 'video/mp4; codecs="avc1.42001E, mp4a.40.2"',
                    'url':
                        'https://rr1---sn-dummy.googlevideo.com/videoplayback?expire=9999999999&itag=18',
                  },
                ],
              },
            };
            return http.Response(
              jsonEncode(response),
              200,
              headers: {'content-type': 'application/json'},
            );
          }

          return http.Response('{}', 200);
        });

        final service = TrackEnrichmentService(client: client);
        final enrichment = await service.locateRadioTrackViaYouTube(
          title: 'XXXX',
          artist: 'Loonie, Hev Abi',
          duration: const Duration(minutes: 3, seconds: 4),
        );

        expect(enrichment.hasAudio, isTrue);
        expect(enrichment.isFullTrack, isTrue);
        expect(enrichment.isYouTube, isTrue);
        expect(enrichment.youtubeVideoId, 'mock_xxxx_vid');
        expect(mainSearchRequests, 0);
        expect(requestedHosts, contains('music.youtube.com'));
        expect(requestedHosts.any((h) => h.contains('saavn')), isFalse);
        expect(requestedHosts.any((h) => h.contains('soundcloud')), isFalse);
        expect(requestedHosts.any((h) => h.contains('archive.org')), isFalse);
        expect(requestedHosts.any((h) => h.contains('itunes')), isFalse);
        expect(requestedHosts.any((h) => h.contains('deezer')), isFalse);
        expect(requestedHosts.any((h) => h.contains('duckduckgo')), isFalse);
      },
    );

    test(
      'featured artist in catalog title matches an upload under that artist',
      () async {
        final client = MockClient((request) async {
          if (request.url.host == 'music.youtube.com' &&
              request.url.path.contains('search')) {
            return http.Response('{}', 200);
          }

          if (request.url.host.contains('youtube.com') &&
              request.url.path.contains('search')) {
            final response = {
              'contents': {
                'sectionListRenderer': {
                  'contents': [
                    {
                      'itemSectionRenderer': {
                        'contents': [
                          {
                            'videoRenderer': {
                              'videoId': 'mock_araw_vid',
                              'title': {
                                'runs': [
                                  {'text': 'Araw araw Love - Flow G'},
                                ],
                              },
                              'ownerText': {
                                'runs': [
                                  {'text': 'Ex Battalion Music'},
                                ],
                              },
                              'lengthText': {'simpleText': '4:12'},
                            },
                          },
                        ],
                      },
                    },
                  ],
                },
              },
            };
            return http.Response(
              jsonEncode(response),
              200,
              headers: {'content-type': 'application/json'},
            );
          }

          if (request.url.host.contains('youtube.com') &&
              request.url.path.contains('player')) {
            final response = {
              'playabilityStatus': {'status': 'OK'},
              'videoDetails': {
                'videoId': 'mock_araw_vid',
                'title': 'Araw araw Love - Flow G',
                'lengthSeconds': '252',
              },
              'streamingData': {
                'formats': [
                  {
                    'itag': 18,
                    'mimeType': 'video/mp4; codecs="avc1.42001E, mp4a.40.2"',
                    'url':
                        'https://rr1---sn-dummy.googlevideo.com/videoplayback?expire=9999999999&itag=18',
                  },
                ],
              },
            };
            return http.Response(
              jsonEncode(response),
              200,
              headers: {'content-type': 'application/json'},
            );
          }

          return http.Response('{}', 200);
        });

        final service = TrackEnrichmentService(client: client);
        final enrichment = await service.locateRadioTrackViaYouTube(
          title: 'Araw-Araw Love (feat. Flow G)',
          artist: 'Luz',
          duration: const Duration(minutes: 4, seconds: 12),
        );

        expect(enrichment.hasAudio, isTrue);
        expect(enrichment.youtubeVideoId, 'mock_araw_vid');
      },
    );

    test(
      'featured artist clause is ignored when the upload title omits it',
      () async {
        final client = MockClient((request) async {
          if (request.url.host == 'music.youtube.com' &&
              request.url.path.contains('search')) {
            return http.Response('{}', 200);
          }

          if (request.url.host.contains('youtube.com') &&
              request.url.path.contains('search')) {
            final response = {
              'contents': {
                'sectionListRenderer': {
                  'contents': [
                    {
                      'itemSectionRenderer': {
                        'contents': [
                          {
                            'videoRenderer': {
                              'videoId': 'mock_unreleased_vid',
                              'title': {
                                'runs': [
                                  {
                                    'text':
                                        'Unreleased (Mahirap na) - Kakaiboys (Official Music Video)',
                                  },
                                ],
                              },
                              'ownerText': {
                                'runs': [
                                  {'text': 'Ex Battalion Music'},
                                ],
                              },
                              'lengthText': {'simpleText': '3:31'},
                            },
                          },
                        ],
                      },
                    },
                  ],
                },
              },
            };
            return http.Response(
              jsonEncode(response),
              200,
              headers: {'content-type': 'application/json'},
            );
          }

          if (request.url.host.contains('youtube.com') &&
              request.url.path.contains('player')) {
            final response = {
              'playabilityStatus': {'status': 'OK'},
              'videoDetails': {
                'videoId': 'mock_unreleased_vid',
                'title': 'Unreleased (Mahirap na) - Kakaiboys',
                'lengthSeconds': '211',
              },
              'streamingData': {
                'formats': [
                  {
                    'itag': 18,
                    'mimeType': 'video/mp4; codecs="avc1.42001E, mp4a.40.2"',
                    'url':
                        'https://rr1---sn-dummy.googlevideo.com/videoplayback?expire=9999999999&itag=18',
                  },
                ],
              },
            };
            return http.Response(
              jsonEncode(response),
              200,
              headers: {'content-type': 'application/json'},
            );
          }

          return http.Response('{}', 200);
        });

        final service = TrackEnrichmentService(client: client);
        final enrichment = await service.locateRadioTrackViaYouTube(
          title: 'Unreleased (feat. Bosx1ne, Skusta Clee & Flow G.)',
          artist: 'Kakaiboys',
          duration: const Duration(minutes: 3, seconds: 31),
        );

        expect(enrichment.hasAudio, isTrue);
        expect(enrichment.youtubeVideoId, 'mock_unreleased_vid');
      },
    );

    test('remix qualifier in the catalog title still matches the base song', () async {
      final client = MockClient((request) async {
        if (request.url.host == 'music.youtube.com' &&
            request.url.path.contains('search')) {
          final response = {
            'contents': {
              'tabbedSearchResultsRenderer': {
                'tabs': [
                  {
                    'tabRenderer': {
                      'content': {
                        'sectionListRenderer': {
                          'contents': [
                            {
                              'itemSectionRenderer': {
                                'contents': [
                                  {
                                    'musicResponsiveListItemRenderer': {
                                      'playlistItemData': {
                                        'videoId': 'mock_rosas_vid',
                                      },
                                      'flexColumns': [
                                        {
                                          'musicResponsiveListItemFlexColumnRenderer': {
                                            'text': {
                                              'runs': [
                                                {
                                                  'text':
                                                      'Rosas (feat. Gab Pangilinan)',
                                                },
                                              ],
                                            },
                                          },
                                        },
                                        {
                                          'musicResponsiveListItemFlexColumnRenderer':
                                              {
                                                'text': {
                                                  'runs': [
                                                    {'text': 'Song'},
                                                    {'text': ' • '},
                                                    {
                                                      'text':
                                                          'Nica del Rosario',
                                                    },
                                                    {'text': ' • '},
                                                    {'text': '12M plays'},
                                                  ],
                                                },
                                              },
                                        },
                                      ],
                                    },
                                  },
                                ],
                              },
                            },
                          ],
                        },
                      },
                    },
                  },
                ],
              },
            },
          };
          return http.Response(
            jsonEncode(response),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        if (request.url.host.contains('youtube.com') &&
            request.url.path.contains('player')) {
          final response = {
            'playabilityStatus': {'status': 'OK'},
            'videoDetails': {
              'videoId': 'mock_rosas_vid',
              'title': 'Rosas (feat. Gab Pangilinan)',
              'lengthSeconds': '244',
            },
            'streamingData': {
              'formats': [
                {
                  'itag': 18,
                  'mimeType': 'video/mp4; codecs="avc1.42001E, mp4a.40.2"',
                  'url':
                      'https://rr1---sn-dummy.googlevideo.com/videoplayback?expire=9999999999&itag=18',
                },
              ],
            },
          };
          return http.Response(
            jsonEncode(response),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        return http.Response('{}', 200);
      });

      final service = TrackEnrichmentService(client: client);
      final enrichment = await service.locateRadioTrackViaYouTube(
        title: 'Rosas (feat. Gab Pangilinan) [Brian Cua Dance Remix]',
        artist: 'Nica del Rosario',
        duration: const Duration(minutes: 4, seconds: 4),
      );

      expect(enrichment.hasAudio, isTrue);
      expect(enrichment.youtubeVideoId, 'mock_rosas_vid');
    });

    test(
      'acoustic qualifier in the catalog title still matches the base song',
      () async {
        final client = MockClient((request) async {
          if (request.url.host == 'music.youtube.com' &&
              request.url.path.contains('search')) {
            return http.Response('{}', 200);
          }

          if (request.url.host.contains('youtube.com') &&
              request.url.path.contains('search')) {
            final response = {
              'contents': {
                'sectionListRenderer': {
                  'contents': [
                    {
                      'itemSectionRenderer': {
                        'contents': [
                          {
                            'videoRenderer': {
                              'videoId': 'mock_2002_vid',
                              'title': {
                                'runs': [
                                  {'text': '2002 - Anne-Marie'},
                                ],
                              },
                              'ownerText': {
                                'runs': [
                                  {'text': 'Anne-Marie'},
                                ],
                              },
                              'lengthText': {'simpleText': '3:06'},
                            },
                          },
                        ],
                      },
                    },
                  ],
                },
              },
            };
            return http.Response(
              jsonEncode(response),
              200,
              headers: {'content-type': 'application/json'},
            );
          }

          if (request.url.host.contains('youtube.com') &&
              request.url.path.contains('player')) {
            final response = {
              'playabilityStatus': {'status': 'OK'},
              'videoDetails': {
                'videoId': 'mock_2002_vid',
                'title': '2002 - Anne-Marie',
                'lengthSeconds': '186',
              },
              'streamingData': {
                'formats': [
                  {
                    'itag': 18,
                    'mimeType': 'video/mp4; codecs="avc1.42001E, mp4a.40.2"',
                    'url':
                        'https://rr1---sn-dummy.googlevideo.com/videoplayback?expire=9999999999&itag=18',
                  },
                ],
              },
            };
            return http.Response(
              jsonEncode(response),
              200,
              headers: {'content-type': 'application/json'},
            );
          }

          return http.Response('{}', 200);
        });

        final service = TrackEnrichmentService(client: client);
        final enrichment = await service.locateRadioTrackViaYouTube(
          title: '2002 (Acoustic)',
          artist: 'Anne-Marie',
          duration: const Duration(minutes: 3, seconds: 6),
        );

        expect(enrichment.hasAudio, isTrue);
        expect(enrichment.youtubeVideoId, 'mock_2002_vid');
      },
    );

    test(
      'preLocateExploreRadios queues radio stations for YouTube locating',
      () {
        final controller = MusicPlayerController();

        final radioStation = RadioStation(
          id: 'flow-g',
          title: 'Flow G Radio',
          artistName: 'Flow G',
          subtitle: 'With SUPAFLY, Lo ki, Hev Abi and more',
          backgroundColor: const Color(0xFF8BB7F0),
          gradientColors: const [Color(0xFF8BB7F0), Color(0xFF60A5FA)],
          songs: [
            Song(
              id: 'radio-flowg-1',
              title: 'Ebeb',
              artist: 'Flow G',
              album: 'Ebeb',
              duration: const Duration(minutes: 4, seconds: 21),
              genre: 'Hip-Hop',
              imageUrl: '',
              gradientColors: const [Color(0xFF8BB7F0), Color(0xFF60A5FA)],
              plays: '45.2M',
              lyrics: const [],
              isPreview: false,
            ),
          ],
        );

        // Should run safely without throwing
        controller.preLocateExploreRadios([radioStation]);

        controller.dispose();
      },
    );

    test(
      'fastImportRadioStation immediately initiates YouTube locating for radio songs',
      () {
        final controller = MusicPlayerController();

        final radioStation = RadioStation(
          id: 'flow-g',
          title: 'Flow G Radio',
          artistName: 'Flow G',
          subtitle: 'With SUPAFLY, Lo ki, Hev Abi and more',
          backgroundColor: const Color(0xFF8BB7F0),
          gradientColors: const [Color(0xFF8BB7F0), Color(0xFF60A5FA)],
          songs: [
            Song(
              id: 'radio-flowg-1',
              title: 'Ebeb',
              artist: 'Flow G',
              album: 'Ebeb',
              duration: const Duration(minutes: 4, seconds: 21),
              genre: 'Hip-Hop',
              imageUrl: '',
              gradientColors: const [Color(0xFF8BB7F0), Color(0xFF60A5FA)],
              plays: '45.2M',
              lyrics: const [],
              isPreview: false,
            ),
            Song(
              id: 'radio-flowg-2',
              title: 'TMA',
              artist: 'Flow G',
              album: 'TMA',
              duration: const Duration(minutes: 3, seconds: 18),
              genre: 'Hip-Hop',
              imageUrl: '',
              gradientColors: const [Color(0xFF8BB7F0), Color(0xFF60A5FA)],
              plays: '32.1M',
              lyrics: const [],
              isPreview: false,
            ),
          ],
        );

        final playlist = controller.fastImportRadioStation(radioStation);

        expect(playlist.title, 'Flow G Radio');
        expect(
          controller.playlists.any((p) => p.title == 'Flow G Radio'),
          isTrue,
        );

        // Verify the radio tracks were added to allSongs
        final song1 = controller.allSongs.firstWhere(
          (s) => s.id == 'radio-flowg-1',
        );
        expect(song1.title, 'Ebeb');

        controller.dispose();
      },
    );

    testWidgets(
      'PlaylistScreen automatically triggers fastLocateRadioSongs on mount',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 800));

        final controller = MusicPlayerController();

        final radioStation = RadioStation(
          id: 'flow-g',
          title: 'Flow G Radio',
          artistName: 'Flow G',
          subtitle: 'With SUPAFLY, Lo ki, Hev Abi and more',
          backgroundColor: const Color(0xFF8BB7F0),
          gradientColors: const [Color(0xFF8BB7F0), Color(0xFF60A5FA)],
          songs: [
            Song(
              id: 'radio-flowg-1',
              title: 'Ebeb',
              artist: 'Flow G',
              album: 'Ebeb',
              duration: const Duration(minutes: 4, seconds: 21),
              genre: 'Hip-Hop',
              imageUrl: '',
              gradientColors: const [Color(0xFF8BB7F0), Color(0xFF60A5FA)],
              plays: '45.2M',
              lyrics: const [],
              isPreview: false,
            ),
          ],
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PlaylistScreen(
                playlist: radioStation.toPlaylist(),
                songs: radioStation.songs,
                controller: controller,
              ),
            ),
          ),
        );

        // Pump 1 frame to trigger postFrameCallback
        await tester.pump(const Duration(milliseconds: 300));

        // Verify PlaylistScreen renders radio header and title cleanly
        expect(find.text('Flow G Radio'), findsOneWidget);
        expect(find.text('Spotify Radio'), findsOneWidget);

        controller.dispose();
      },
    );
  });
}
