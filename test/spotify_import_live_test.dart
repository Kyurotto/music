import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music/services/spotify_import_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SpotifyImportService service;

  setUpAll(() {
    // Allow real HTTP against Spotify (flutter_test mocks HttpClient by default).
    HttpOverrides.global = null;
  });

  setUp(() {
    HttpOverrides.global = null;
    service = SpotifyImportService();
  });

  tearDown(() => service.dispose());

  test('live: imports playlist tracks from Spotify', () async {
    final result = await service.importFromLink(
      'https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M',
    );
    expect(result.type, SpotifyLinkType.playlist);
    expect(result.title, isNotEmpty);
    expect(result.tracks, isNotEmpty);
    expect(result.tracks.first.title, isNotEmpty);
    expect(result.tracks.first.artist, isNotEmpty);
    expect(result.tracks.first.duration.inSeconds, greaterThan(0));
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('live: imports album tracks from Spotify', () async {
    final result = await service.importFromLink(
      'https://open.spotify.com/album/78bpIziExqiI9qztvNFlQu?si=xyz',
    );
    expect(result.type, SpotifyLinkType.album);
    expect(result.title, 'AM');
    expect(result.tracks.length, 12);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('live: imports a single track', () async {
    final result = await service.importFromLink(
      'spotify:track:2plbrEY59IikOBgBGLjaoe',
    );
    expect(result.type, SpotifyLinkType.track);
    expect(result.tracks, hasLength(1));
    expect(result.tracks.first.title.toLowerCase(), contains('die with a smile'));
    expect(result.tracks.first.artist.toLowerCase(), contains('lady gaga'));
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('live: imports artist top songs by name', () async {
    final result = await service.importFromLink('Bruno Mars');
    expect(result.type, SpotifyLinkType.artist);
    expect(result.title.toLowerCase(), contains('bruno mars'));
    expect(result.tracks, isNotEmpty);
    expect(result.tracks.first.title, isNotEmpty);
    expect(result.tracks.first.artist, isNotEmpty);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('live: imports artist top songs from an artist link', () async {
    final result = await service.importFromLink(
        'https://open.spotify.com/artist/0du5cEVh5yTK9QJze8zA0C');
    expect(result.type, SpotifyLinkType.artist);
    expect(result.tracks, isNotEmpty);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
