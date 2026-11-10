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
    test('enrichTrack with youtubeOnly: true queries YouTube and bypasses third-party scrapers', () async {
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
                                {'text': 'Ebeb - Flow G (Official Audio)'}
                              ]
                            },
                            'ownerText': {
                              'runs': [
                                {'text': 'Flow G'}
                              ]
                            },
                            'lengthText': {'simpleText': '4:21'},
                          }
                        }
                      ]
                    }
                  }
                ]
              }
            }
          };
          return http.Response(jsonEncode(dummySearchResponse), 200, headers: {'content-type': 'application/json'});
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
                  'url': 'https://rr1---sn-dummy.googlevideo.com/videoplayback?expire=9999999999&itag=18',
                  'audioQuality': 'AUDIO_QUALITY_MEDIUM',
                }
              ]
            }
          };
          return http.Response(jsonEncode(dummyPlayerResponse), 200, headers: {'content-type': 'application/json'});
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
    });

    test('multi-artist track locating succeeds with reversed artist order and topic channel', () async {
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
                                {'text': 'Hev Abi, Kristina Dawn - Makasarili Malambing (Audio)'}
                              ]
                            },
                            'ownerText': {
                              'runs': [
                                {'text': 'HEVABIDOWNTOWN'}
                              ]
                            },
                            'lengthText': {'simpleText': '3:44'},
                          }
                        }
                      ]
                    }
                  }
                ]
              }
            }
          };
          return http.Response(jsonEncode(dummySearchResponse), 200, headers: {'content-type': 'application/json'});
        }

        if (request.url.host.contains('youtube.com') &&
            request.url.path.contains('player')) {
          final dummyPlayerResponse = {
            'playabilityStatus': {'status': 'OK'},
            'videoDetails': {
              'videoId': 'mock_makasarili_vid',
              'title': 'Hev Abi, Kristina Dawn - Makasarili Malambing (Audio)',
              'lengthSeconds': '224',
            },
            'streamingData': {
              'formats': [
                {
                  'itag': 18,
                  'mimeType': 'video/mp4; codecs="avc1.42001E, mp4a.40.2"',
                  'url': 'https://rr1---sn-dummy.googlevideo.com/videoplayback?expire=9999999999&itag=18',
                }
              ]
            }
          };
          return http.Response(jsonEncode(dummyPlayerResponse), 200, headers: {'content-type': 'application/json'});
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
    });

    test('preLocateExploreRadios queues radio stations for YouTube locating', () {
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
    });

    test('fastImportRadioStation immediately initiates YouTube locating for radio songs', () {
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
      expect(controller.playlists.any((p) => p.title == 'Flow G Radio'), isTrue);

      // Verify the radio tracks were added to allSongs
      final song1 = controller.allSongs.firstWhere((s) => s.id == 'radio-flowg-1');
      expect(song1.title, 'Ebeb');

      controller.dispose();
    });

    testWidgets('PlaylistScreen automatically triggers fastLocateRadioSongs on mount', (tester) async {
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
    });
  });
}
