import 'package:flutter_test/flutter_test.dart';
import 'package:music/controllers/music_player_controller.dart';
import 'package:music/services/spotify_import_service.dart';
import 'package:music/services/track_enrichment_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('version-aware track matching', () {
    test('a Tagalog request accepts the Tagalog and the untagged base song', () {
      expect(
        TrackEnrichmentService.versionCompatible(
            'perfect tagalog version', 'perfect tagalog version'),
        isTrue,
      );
      expect(
        TrackEnrichmentService.versionCompatible(
            'perfect tagalog version', 'perfect'),
        isTrue,
      );
    });

    test('a Tagalog request never gets the English version', () {
      expect(
        TrackEnrichmentService.versionCompatible(
            'perfect tagalog version', 'perfect english version'),
        isFalse,
      );
    });

    test('a plain request never gets a language version', () {
      expect(
        TrackEnrichmentService.versionCompatible(
            'perfect', 'perfect tagalog version'),
        isFalse,
      );
      expect(
        TrackEnrichmentService.versionCompatible('perfect', 'perfect'),
        isTrue,
      );
    });

    test('cover markers do not reject a requested language version', () {
      expect(
        TrackEnrichmentService.isNonStudioVariant(
            'perfect tagalog cover some channel',
            'Perfect (Tagalog Version) Some Artist'),
        isFalse,
      );
      // ...but a plain request still skips covers.
      expect(
        TrackEnrichmentService.isNonStudioVariant(
            'perfect cover some channel', 'Perfect Ed Sheeran'),
        isTrue,
      );
    });

    test('markers match whole words only', () {
      expect(
        TrackEnrichmentService.isNonStudioVariant(
            'discovery recovery drummer boy', 'Anything Artist'),
        isFalse,
      );
      expect(
        TrackEnrichmentService.isNonStudioVariant(
            'perfect piano version', 'Perfect Ed Sheeran'),
        isTrue,
      );
    });

    test('importing both versions keeps both songs in the playlist', () {
      final controller = MusicPlayerController();
      controller.importSpotifyTracks(
        playlistName: 'Versions',
        tracks: [
          const SpotifyImportedTrack(
            spotifyId: 'tag-1',
            title: 'Sample Love Song (Tagalog Version)',
            artist: 'Sample Artist',
            album: 'Singles',
            duration: Duration(minutes: 3),
            artworkUrl: '',
          ),
          const SpotifyImportedTrack(
            spotifyId: 'eng-1',
            title: 'Sample Love Song (English Version)',
            artist: 'Sample Artist',
            album: 'Singles',
            duration: Duration(minutes: 3),
            artworkUrl: '',
          ),
        ],
      );
      final songs =
          controller.songsForPlaylist(controller.playlists.last.id);
      expect(songs.length, 2);
      expect(songs.map((s) => s.title).toSet().length, 2);
      controller.dispose();
    });
  });
}
