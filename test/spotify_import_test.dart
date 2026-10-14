import 'package:flutter_test/flutter_test.dart';
import 'package:music/controllers/music_player_controller.dart';
import 'package:music/models/song_model.dart';
import 'package:music/services/spotify_import_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SpotifyImportService.tryParse', () {
    test('parses standard track URLs', () {
      final link = SpotifyImportService.tryParse(
        'https://open.spotify.com/track/2plbrEY59IikOBgBGLjaoe',
      );
      expect(link, isNotNull);
      expect(link!.type, SpotifyLinkType.track);
      expect(link.id, '2plbrEY59IikOBgBGLjaoe');
    });

    test('parses playlist URLs with query params and intl prefix', () {
      final link = SpotifyImportService.tryParse(
        'https://open.spotify.com/intl-en/playlist/37i9dQZF1DXcBWIGoYBM5M?si=abc123',
      );
      expect(link, isNotNull);
      expect(link!.type, SpotifyLinkType.playlist);
      expect(link.id, '37i9dQZF1DXcBWIGoYBM5M');
    });

    test('parses album embed URLs', () {
      final link = SpotifyImportService.tryParse(
        'https://open.spotify.com/embed/album/78bpIziExqiI9qztvNFlQu?utm_source=generator',
      );
      expect(link, isNotNull);
      expect(link!.type, SpotifyLinkType.album);
      expect(link.id, '78bpIziExqiI9qztvNFlQu');
    });

    test('parses spotify URI form', () {
      final link = SpotifyImportService.tryParse('spotify:track:2plbrEY59IikOBgBGLjaoe');
      expect(link, isNotNull);
      expect(link!.type, SpotifyLinkType.track);
      expect(link.id, '2plbrEY59IikOBgBGLjaoe');
    });

    test('rejects unsupported types and malformed input', () {
      expect(SpotifyImportService.tryParse(''), isNull);
      expect(SpotifyImportService.tryParse('   '), isNull);
      expect(
        SpotifyImportService.tryParse('https://open.spotify.com/show/abc123def456ghi789jkl0'),
        isNull,
      );
      expect(
        SpotifyImportService.tryParse('https://open.spotify.com/episode/abc123def456ghi789jkl0'),
        isNull,
      );
      expect(SpotifyImportService.tryParse('https://example.com/track/abc'), isNull);
      expect(SpotifyImportService.tryParse('https://open.spotify.com/track/short-id'), isNull);
      expect(SpotifyImportService.tryParse('not a link'), isNull);
    });

    test('detects short links', () {
      expect(SpotifyImportService.isShortLink('https://spotify.link/abc'), isTrue);
      expect(SpotifyImportService.isShortLink('https://open.spotify.com/track/x'), isFalse);
    });
  });

  group('MusicPlayerController.importSpotifyTracks', () {
    SpotifyImportedTrack track(String id, String title, String artist) {
      return SpotifyImportedTrack(
        spotifyId: id,
        title: title,
        artist: artist,
        album: 'Imported Album',
        duration: const Duration(minutes: 3, seconds: 30),
      );
    }

    test('creates a new playlist and adds imported tracks', () {
      final controller = MusicPlayerController();
      final before = controller.playlists.length;

      final result = controller.importSpotifyTracks(
        playlistName: 'My Spotify Mix',
        tracks: [
          track('aaaaaaaaaaaaaaaaaaaaa1', 'Frosted Glass', 'Night Drive'),
          track('aaaaaaaaaaaaaaaaaaaaa2', 'Neon Rain', 'Night Drive'),
        ],
      );

      expect(controller.playlists.length, before + 1);
      final playlist = controller.playlistById(result.playlistId);
      expect(playlist, isNotNull);
      expect(playlist!.title, 'My Spotify Mix');
      expect(playlist.trackCount, 2);
      expect(result.addedCount, 2);

      final songs = controller.songsForPlaylist(result.playlistId);
      expect(songs.map((s) => s.title), containsAll(['Frosted Glass', 'Neon Rain']));
      expect(songs.first.audioUrl, '');
      expect(songs.first.genre, 'Spotify');
    });

    test('re-importing the same link does not duplicate tracks', () {
      final controller = MusicPlayerController();
      final tracks = [
        track('bbbbbbbbbbbbbbbbbbbbb1', 'Static Bloom', 'Analog Heart'),
        track('bbbbbbbbbbbbbbbbbbbbb2', 'Waveform', 'Analog Heart'),
      ];

      final first = controller.importSpotifyTracks(
        playlistName: 'Duplicate Guard',
        tracks: tracks,
      );
      final second = controller.importSpotifyTracks(
        playlistName: 'Duplicate Guard',
        tracks: tracks,
      );

      expect(first.playlistId, second.playlistId);
      expect(second.addedCount, 0);
      final playlist = controller.playlistById(first.playlistId)!;
      expect(playlist.trackCount, 2);
      final importedCount =
          controller.allSongs.where((s) => s.id.startsWith('spotify-')).length;
      expect(importedCount, 2);
    });

    test('reuses a local library song when title and artist match', () {
      final controller = MusicPlayerController();
      final sample = Song(
        id: 'local-lose-yourself',
        title: 'Lose Yourself',
        artist: 'Eminem',
        album: '8 Mile',
        duration: const Duration(minutes: 5, seconds: 20),
        genre: 'Hip-Hop',
        imageUrl: '',
        gradientColors: const [],
        plays: '',
        lyrics: const [],
        audioUrl: 'assets/audio/lose-yourself.m4a',
      );
      controller.addSong(sample);
      final local = controller.allSongs.firstWhere((s) => s.title == 'Lose Yourself');

      final result = controller.importSpotifyTracks(
        playlistName: 'Local Match',
        tracks: [
          track('ccccccccccccccccccccc1', 'lose yourself', 'EMINEM'),
        ],
      );

      expect(result.reusedLocalCount, 1);
      final songs = controller.songsForPlaylist(result.playlistId);
      expect(songs.single.id, local.id);
      expect(songs.single.audioUrl, local.audioUrl);
    });

    test('imports into an existing playlist when targetPlaylistId is given', () {
      final controller = MusicPlayerController();
      expect(controller.createPlaylist('Existing Target'), isTrue);
      final target = controller.playlists.last;

      final result = controller.importSpotifyTracks(
        playlistName: 'Ignored Name',
        tracks: [track('ddddddddddddddddddddd1', 'Quiet Hours', 'Soft Static')],
        targetPlaylistId: target.id,
      );

      expect(result.playlistId, target.id);
      expect(target.trackCount, 1);
      expect(controller.playlists.length, 1);
    });

    test('never creates duplicate songs across different playlists', () {
      final controller = MusicPlayerController();
      final shared = [track('eeeeeeeeeeeeeeeeeeeee1', 'Shared Song', 'Twin Peaks')];

      controller.importSpotifyTracks(playlistName: 'Playlist A', tracks: shared);
      controller.importSpotifyTracks(playlistName: 'Playlist B', tracks: shared);

      final matches =
          controller.allSongs.where((s) => s.title == 'Shared Song').toList();
      expect(matches, hasLength(1));
      final playlistsWithSong = controller.playlists
          .where((p) => p.songIds.contains(matches.first.id))
          .length;
      expect(playlistsWithSong, 2);
    });

    test('imported track has a sane duration so playback cannot spin', () {
      final controller = MusicPlayerController();
      controller.importSpotifyTracks(
        playlistName: 'Duration Check',
        tracks: [
          SpotifyImportedTrack(
            spotifyId: 'ffffffffffffffffffffff1',
            title: 'Zero Length',
            artist: 'Nobody',
            album: 'Nowhere',
            duration: Duration.zero,
          ),
        ],
      );
      final song =
          controller.songsForPlaylist(controller.playlists.last.id).single;
      expect(song.duration.inSeconds, greaterThan(0));
      controller.dispose();
    });

    test('preview upgrades set full-track flags and real duration', () {
      final controller = MusicPlayerController();
      controller.importSpotifyTracks(
        playlistName: 'Upgrade Flags',
        tracks: [
          SpotifyImportedTrack(
            spotifyId: 'ggggggggggggggggggggg1',
            title: 'Slow Burn',
            artist: 'Night Drive',
            album: 'After Hours',
            duration: const Duration(seconds: 30),
            previewUrl: 'https://example.com/slow-burn-30s.m4a',
          ),
        ],
      );
      final song = controller.songsForPlaylist(controller.playlists.last.id).single;
      // Import never seeds the 30s preview — the track starts silent and
      // enrichment must resolve a full-length stream.
      expect(song.isPreview, isFalse);
      expect(song.hasAudio, isFalse);
      expect(song.isSilentPlaceholder, isTrue);
      expect(song.isFullTrack, isFalse);

      // Simulate enrichment resolving a full-length Saavn/YouTube stream.
      song.audioUrl = 'https://example.com/slow-burn-full.mp3';
      song.isPreview = false;
      song.isYouTubeAudio = false;
      song.duration = const Duration(minutes: 3, seconds: 42);

      expect(song.isFullTrack, isTrue);
      expect(song.isPreview, isFalse);
      expect(song.duration.inSeconds, 222);
      controller.dispose();
    });

    test('replaces noisy spotify titles to match bundled local tracks', () {
      final controller = MusicPlayerController();
      controller.importSpotifyTracks(
        playlistName: 'Clean Title Test',
        tracks: [
          SpotifyImportedTrack(
            spotifyId: 'noisy-eminem-1',
            title: 'Lose Yourself - From "8 Mile" Soundtrack',
            artist: 'Eminem',
            album: '8 Mile',
            duration: const Duration(minutes: 5, seconds: 20),
          ),
          SpotifyImportedTrack(
            spotifyId: 'noisy-taylor-1',
            title: 'Blank Space (Taylor\'s Version)',
            artist: 'Taylor Swift',
            album: '1989',
            duration: const Duration(minutes: 3, seconds: 50),
          ),
        ],
      );

      final songs = controller.songsForPlaylist(controller.playlists.last.id);
      expect(songs.length, 2);
      // Both should match the bundled audio tracks and have local asset audio
      expect(songs[0].audioUrl, startsWith('assets/audio/'));
      expect(songs[0].lyrics, isNotEmpty);
      expect(songs[1].audioUrl, startsWith('assets/audio/'));
      expect(songs[1].lyrics, isNotEmpty);
      controller.dispose();
    });

    test('offline playback handles un-cached imported song by falling back to audio and generating lyrics', () async {
      final controller = MusicPlayerController();
      controller.importSpotifyTracks(
        playlistName: 'Offline Test',
        tracks: [
          SpotifyImportedTrack(
            spotifyId: 'offline-random-12345',
            title: 'Custom Indie Track',
            artist: 'Indie Artist',
            album: 'Independent EP',
            duration: const Duration(minutes: 3),
            artworkUrl: 'https://example.com/unreachable-image.jpg',
          ),
        ],
      );

      final song = controller.songsForPlaylist(controller.playlists.last.id).single;
      expect(song.audioUrl, isEmpty); // Starts un-cached

      // Verify unbundled songs do not falsely play a different song's audio
      final fallbackAsset = controller.getOfflineAssetFallbackForTesting(song);
      expect(fallbackAsset, isEmpty);

      // Imported tracks get no invented placeholder lyrics; the lyrics sheet
      // looks up the real ones instead.
      final lyrics = controller.ensureOfflineLyricsForTesting(song);
      expect(lyrics, isEmpty);

      controller.dispose();
    });
  });
}
