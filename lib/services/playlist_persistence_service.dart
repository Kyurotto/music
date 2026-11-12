import 'package:flutter/foundation.dart';
import '../data/local_database.dart';
import '../models/song_model.dart';

/// Centralized service to manage safe, transactional persistence and loading
/// of imported Spotify playlists and songs across all user sessions and app restarts.
class PlaylistPersistenceService {
  PlaylistPersistenceService._();
  static final PlaylistPersistenceService instance = PlaylistPersistenceService._();

  /// Persists [playlist] and its [songs] to SQLite local storage, ensuring
  /// deletion flags are unmasked, changes are written, and WAL is flushed to disk.
  Future<void> persistPlaylist({
    required MusicPlaylist playlist,
    required List<Song> songs,
    String? spotifyUrl,
    required String userId,
  }) async {
    try {
      final effectiveUserId = userId.isEmpty ? 'default_user' : userId;
      final songMaps = songs.map((s) => <String, dynamic>{
        'id': s.id,
        'title': s.title,
        'artist': s.artist,
        'album': s.album,
        'duration_ms': s.duration.inMilliseconds,
        'image_url': s.imageUrl,
        'audio_url': s.audioUrl,
        'lyrics': s.lyrics,
        'genre': s.genre,
        'is_preview': s.isPreview ? 1 : 0,
        'is_youtube_audio': s.isYouTubeAudio ? 1 : 0,
        'youtube_video_id': s.youtubeVideoId,
        'is_explicit': s.isExplicit ? 1 : 0,
      }).toList();

      final gradientColors = playlist.gradient.map((c) => c.toARGB32()).toList();

      await LocalDatabase.instance.saveImportedPlaylist(
        id: playlist.id,
        userId: effectiveUserId,
        title: playlist.title,
        subtitle: playlist.subtitle,
        spotifyUrl: spotifyUrl,
        imageUrl: playlist.imageUrl,
        gradientColors: gradientColors,
        songs: songMaps,
      );
    } catch (e) {
      debugPrint('[PlaylistPersistenceService] persistPlaylist error: $e');
      rethrow;
    }
  }

  /// Retrieves all non-deleted imported playlists accessible to [userId].
  /// Guarantees that guest/default_user imports are seamlessly loaded when logged in.
  Future<List<Map<String, dynamic>>> loadImportedPlaylists(String userId) async {
    return LocalDatabase.instance.getImportedPlaylistsForUser(userId);
  }
}
