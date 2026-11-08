import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:music/services/radio_discovery_service.dart';
import 'package:music/views/music_dashboard_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Dynamic Spotify Radio Search & Service Tests', () {
    late RadioDiscoveryService service;

    setUp(() {
      service = RadioDiscoveryService.instance;
      service.clearCache();
    });

    test('searchSpotifyRadio parses real catalog tracks, durations, artwork, and collaborators', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.host, 'itunes.apple.com');
        expect(request.url.path, '/search');
        expect(request.url.queryParameters['term'], 'Flow G');

        final sampleResponse = {
          'resultCount': 3,
          'results': [
            {
              'wrapperType': 'track',
              'kind': 'song',
              'artistId': 1481029412,
              'trackId': 1618294021,
              'artistName': 'Flow-G',
              'trackName': 'Rapstar',
              'collectionName': 'Rapstar - Single',
              'previewUrl': 'https://audio-ssl.itunes.apple.com/preview.m4a',
              'artworkUrl100': 'https://is1-ssl.mzstatic.com/image/thumb/cover.jpg/100x100bb.jpg',
              'trackTimeMillis': 252000,
              'primaryGenreName': 'Hip-Hop',
            },
            {
              'wrapperType': 'track',
              'kind': 'song',
              'artistId': 1481029412,
              'trackId': 1618294022,
              'artistName': 'Skusta Clee',
              'trackName': 'Since Day One (feat. Flow G)',
              'collectionName': 'Since Day One',
              'previewUrl': 'https://audio-ssl.itunes.apple.com/preview2.m4a',
              'artworkUrl100': 'https://is1-ssl.mzstatic.com/image/thumb/cover2.jpg/100x100bb.jpg',
              'trackTimeMillis': 214000,
              'primaryGenreName': 'Hip-Hop',
            },
            {
              'wrapperType': 'track',
              'kind': 'song',
              'artistId': 1481029412,
              'trackId': 1618294023,
              'artistName': 'MC Einstein',
              'trackName': 'Titig (feat. Flow G & Yuridope)',
              'collectionName': 'Titig - Single',
              'previewUrl': 'https://audio-ssl.itunes.apple.com/preview3.m4a',
              'artworkUrl100': 'https://is1-ssl.mzstatic.com/image/thumb/cover3.jpg/100x100bb.jpg',
              'trackTimeMillis': 198000,
              'primaryGenreName': 'Hip-Hop',
            },
          ],
        };

        return http.Response(jsonEncode(sampleResponse), 200, headers: {'content-type': 'application/json'});
      });

      final station = await service.searchSpotifyRadio('Flow G', client: mockClient);

      // Verify not default mock data
      expect(station.id, contains('dyn-flow-g'));
      expect(station.title, 'Flow G Radio');
      expect(station.artistName, 'Flow G');
      expect(station.backgroundColor, const Color(0xFF8BB7F0)); // Spotify pastel sky blue

      // Verify authentic collaborators subtitle
      expect(station.subtitle, contains('With'));
      expect(station.subtitle, contains('SUPAFLY')); // Spotify preset or extracted
      expect(station.subtitle, contains('and more'));

      // Verify 3 distinct avatar URLs collected
      expect(station.avatarUrls.length, 3);
      expect(station.avatarUrls[0], contains('600x600bb.jpg'));
      expect(station.avatarUrls[1], contains('cover2.jpg/600x600bb.jpg'));
      expect(station.avatarUrls[2], contains('cover3.jpg/600x600bb.jpg'));

      // Verify real songs with durations & previews
      expect(station.songs.length, 3);
      expect(station.songs[0].title, 'Rapstar');
      expect(station.songs[0].duration, const Duration(milliseconds: 252000));
      expect(station.songs[0].isPreview, isTrue);
      expect(station.songs[1].title, 'Since Day One (feat. Flow G)');
      expect(station.songs[1].artist, 'Skusta Clee');

      // Verify toPlaylist conversion
      final playlist = station.toPlaylist();
      expect(playlist.title, 'Flow G Radio');
      expect(playlist.songIds.length, 3);
      expect(playlist.imageUrl, contains('cover.jpg'));
    });

    test('extractCollaborators extracts names from track titles and artist strings', () {
      final sampleTracks = [
        {
          'trackName': 'Song One (feat. Singer A & Singer B)',
          'artistName': 'Main Artist',
        },
        {
          'trackName': 'Song Two (with Singer C)',
          'artistName': 'Main Artist',
        },
      ];

      final collaborators = service.extractCollaborators('Main Artist', sampleTracks);
      expect(collaborators, contains('Singer A'));
      expect(collaborators, contains('Singer B'));
      expect(collaborators, contains('Singer C'));
    });

    test('getPastelColor returns distinctive Spotify pastel colors for popular artists', () {
      expect(service.getPastelColor('Flow G'), const Color(0xFF8BB7F0));
      expect(service.getPastelColor('Air Supply'), const Color(0xFF8CECD4));
      expect(service.getPastelColor('LANY'), const Color(0xFFA5EAB7));
      expect(service.getPastelColor('Ben&Ben'), const Color(0xFFF7A278));
      expect(service.getPastelColor('Cup of Joe'), const Color(0xFF8DD8B5));
    });

    test('fetchTrendingRadios fetches multiple dynamic stations and caches them', () async {
      final mockClient = MockClient((request) async {
        final term = request.url.queryParameters['term'] ?? 'Artist';
        final sampleResponse = {
          'resultCount': 1,
          'results': [
            {
              'trackId': 1001,
              'artistName': term,
              'trackName': '$term Hit Song',
              'collectionName': '$term Hits',
              'artworkUrl100': 'https://is1-ssl.mzstatic.com/image/thumb/art.jpg/100x100bb.jpg',
              'trackTimeMillis': 200000,
            },
          ],
        };
        return http.Response(jsonEncode(sampleResponse), 200, headers: {'content-type': 'application/json'});
      });

      final stations = await service.fetchTrendingRadios(
        client: mockClient,
        initialArtists: ['Flow G', 'Air Supply'],
      );

      expect(stations.length, 2);
      expect(stations[0].artistName, 'Flow G');
      expect(stations[1].artistName, 'Air Supply');

      // Subsequent getPopularRadios returns cached dynamic stations
      final popular = service.getPopularRadios();
      expect(popular.length, 2);
      expect(popular[0].artistName, 'Flow G');
    });
  });

  group('Dynamic Spotify Radio UI & Search Widget Tests', () {
    testWidgets('Explore tab displays dynamic Spotify radio search bar', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MusicDashboardView(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Navigate to Explore tab
      final exploreNav = find.text('Explore');
      expect(exploreNav, findsWidgets);
      await tester.tap(exploreNav.first);
      await tester.pumpAndSettle();

      // Verify dynamic radio search bar exists
      final searchField = find.byType(TextField);
      expect(searchField, findsWidgets);

      expect(
        find.textContaining('Search any Spotify radio or artist'),
        findsOneWidget,
      );

      // Verify Popular radio section header
      expect(find.text('Popular radio'), findsOneWidget);

      // Verify RADIO badge on cards
      expect(find.text('RADIO'), findsWidgets);
    });
  });
}
