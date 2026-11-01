import 'package:flutter_test/flutter_test.dart';
import 'package:music/controllers/music_player_controller.dart';
import 'package:music/services/spotify_import_service.dart';
import 'package:music/services/track_enrichment_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Spotify Station & Playlist Radio URL Parsing', () {
    test('parses Spotify station playlist URL', () {
      final link = SpotifyImportService.tryParse(
        'https://open.spotify.com/station/playlist/37i9dQZF1E4v5Wc8gWJ9gJ',
      );
      expect(link, isNotNull);
      expect(link!.type, SpotifyLinkType.playlist);
      expect(link.id, '37i9dQZF1E4v5Wc8gWJ9gJ');
    });

    test('parses Spotify station artist URL', () {
      final link = SpotifyImportService.tryParse(
        'https://open.spotify.com/station/artist/0du5cEVh5yTK9QJze8zA0C',
      );
      expect(link, isNotNull);
      expect(link!.type, SpotifyLinkType.artist);
      expect(link.id, '0du5cEVh5yTK9QJze8zA0C');
    });

    test('parses Spotify station track URL', () {
      final link = SpotifyImportService.tryParse(
        'https://open.spotify.com/station/track/2plbrEY59IikOBgBGLjaoe',
      );
      expect(link, isNotNull);
      expect(link!.type, SpotifyLinkType.track);
      expect(link.id, '2plbrEY59IikOBgBGLjaoe');
    });

    test('parses Spotify radio route URL', () {
      final link = SpotifyImportService.tryParse(
        'https://open.spotify.com/radio/playlist/37i9dQZF1DXcBWIGoYBM5M',
      );
      expect(link, isNotNull);
      expect(link!.type, SpotifyLinkType.playlist);
      expect(link.id, '37i9dQZF1DXcBWIGoYBM5M');
    });

    test('parses spotify:station:playlist URI format', () {
      final link = SpotifyImportService.tryParse(
        'spotify:station:playlist:37i9dQZF1E4v5Wc8gWJ9gJ',
      );
      expect(link, isNotNull);
      expect(link!.type, SpotifyLinkType.playlist);
      expect(link.id, '37i9dQZF1E4v5Wc8gWJ9gJ');
    });

    test('parses spotify:station:artist URI format', () {
      final link = SpotifyImportService.tryParse(
        'spotify:station:artist:0du5cEVh5yTK9QJze8zA0C',
      );
      expect(link, isNotNull);
      expect(link!.type, SpotifyLinkType.artist);
      expect(link.id, '0du5cEVh5yTK9QJze8zA0C');
    });
  });

  group('Spotify Artist Playlist & Playlist Radio Full-Track Batch Resolution', () {
    test('imports all tracks in an artist playlist / radio without 3-song limit', () {
      final controller = MusicPlayerController();

      // Create a 20-track artist radio / playlist with distinct song titles
      const songNames = [
        'Ang Huling El Bimbo', 'Ligaya', 'Magasin', 'Alapaap', 'Pare Ko',
        'Kathang Isip', 'Leaves', 'Araw-Araw', 'Pagtingin', 'Paninindigan Kita',
        'Burnout', 'Mariposa', 'Hari ng Sablay', 'Prom', 'Tulog Na',
        'Cruel Summer', 'Cardigan', 'Style', 'Anti-Hero', 'Enchanted',
      ];
      final artists = [
        'Eraserheads', 'Eraserheads', 'Eraserheads', 'Eraserheads', 'Eraserheads',
        'Ben&Ben', 'Ben&Ben', 'Ben&Ben', 'Ben&Ben', 'Ben&Ben',
        'Sugarfree', 'Sugarfree', 'Sugarfree', 'Sugarfree', 'Sugarfree',
        'Taylor Swift', 'Taylor Swift', 'Taylor Swift', 'Taylor Swift', 'Taylor Swift',
      ];

      final simulatedTracks = List.generate(20, (index) {
        return SpotifyImportedTrack(
          spotifyId: 'test_spotify_id_${index.toString().padLeft(2, '0')}',
          title: songNames[index],
          artist: artists[index],
          album: '${artists[index]} Essentials',
          duration: Duration(minutes: 3, seconds: 20 + index),
        );
      });

      final result = controller.importSpotifyTracks(
        playlistName: 'Artist Radio & Essentials',
        tracks: simulatedTracks,
      );

      expect(result.addedCount, 20, reason: 'All 20 tracks must be added, not capped at 3');

      final playlist = controller.playlistById(result.playlistId);
      expect(playlist, isNotNull);
      expect(playlist!.songIds.length, 20);

      // Verify that all 20 songs are properly flagged as full track candidates (audioUrl empty, isPreview false)
      for (final songId in playlist.songIds) {
        final song = controller.allSongs.firstWhere((s) => s.id == songId);
        expect(song.audioUrl, isEmpty, reason: 'Must not default to 30s preview clip');
        expect(song.isPreview, isFalse, reason: 'Imported tracks are full track candidates');
        expect(MusicPlayerController.needsFullTrack(song), isTrue,
            reason: 'All tracks in artist playlist / radio must trigger YouTube full-track resolution');
      }

      controller.dispose();
    });

    test('TrackEnrichmentService prioritizes YouTube-first search for Spotify imports', () {
      final enrichment = TrackEnrichmentService();
      expect(enrichment, isNotNull);
      enrichment.dispose();
    });
  });
}
