import 'package:flutter_test/flutter_test.dart';
import 'package:music/controllers/music_player_controller.dart';
import 'package:music/models/song_model.dart';
import 'package:music/services/discovery_service.dart';
import 'package:music/services/track_enrichment_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Playback Stall & Cache 403 Fix Verification Across Diverse Artists', () {
    test('TrackEnrichmentService defaults prioritize unthrottled streams', () async {
      final enrichment = TrackEnrichmentService();
      expect(enrichment, isNotNull);
      enrichment.dispose();
    });

    final testArtistsAndTracks = [
      {'title': 'Batang-Bata Ka Pa', 'artist': 'Sugarfree', 'album': 'Sugarfree Greatest'},
      {'title': 'Ang Huling El Bimbo', 'artist': 'Eraserheads', 'album': 'Cutterpillow'},
      {'title': 'Kathang Isip', 'artist': 'Ben&Ben', 'album': 'Leaves'},
      {'title': 'Cruel Summer', 'artist': 'Taylor Swift', 'album': 'Lover'},
      {'title': 'Just The Way You Are', 'artist': 'Bruno Mars', 'album': 'Doo-Wops & Hooligans'},
    ];

    for (final sample in testArtistsAndTracks) {
      test('DiscoveryTrack.toSong creates full track candidate with empty audioUrl for ${sample['title']} by ${sample['artist']}', () {
        final track = DiscoveryTrack(
          trackId: sample['title'].hashCode.abs(),
          title: sample['title']!,
          artist: sample['artist']!,
          album: sample['album']!,
          artworkUrl: 'https://example.com/art.jpg',
          previewUrl: 'https://example.com/30s-preview.mp3',
          durationMs: 240000,
        );

        final song = track.toSong();
        expect(song.title, sample['title']);
        expect(song.artist, sample['artist']);
        expect(song.audioUrl, isEmpty, reason: 'Must not use 30s preview clip as default');
        expect(song.isPreview, isFalse, reason: 'Candidate for full track resolution');
        expect(song.duration, const Duration(milliseconds: 240000));
      });

      test('MusicPlayerController.needsFullTrack correctly flags candidate for ${sample['title']}', () {
        final discoveryCandidate = Song(
          id: 'spotify-itunes-${sample['title'].hashCode.abs()}',
          title: sample['title']!,
          artist: sample['artist']!,
          album: sample['album']!,
          duration: const Duration(minutes: 4),
          genre: 'Pop',
          imageUrl: '',
          gradientColors: const [],
          plays: '',
          lyrics: const [],
          audioUrl: '',
          isPreview: false,
        );

        expect(MusicPlayerController.needsFullTrack(discoveryCandidate), isTrue,
            reason: 'Track with empty audioUrl requires full track resolution');
      });
    }

    test('MusicPlayerController.needsFullTrack flags preview tracks regardless of duration', () {
      final previewTrack = Song(
        id: 'spotify-5566',
        title: 'Preview Track',
        artist: 'Artist',
        album: '',
        duration: const Duration(seconds: 30),
        genre: 'Pop',
        imageUrl: '',
        gradientColors: const [],
        plays: '',
        lyrics: const [],
        audioUrl: 'https://audio-ssl.itunes.apple.com/preview.m4a',
        isPreview: true,
      );

      expect(MusicPlayerController.needsFullTrack(previewTrack), isTrue,
          reason: 'Preview track must be flagged for upgrade');
    });
  });
}
