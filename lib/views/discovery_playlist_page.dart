import 'package:flutter/material.dart';

import '../controllers/music_player_controller.dart';
import '../models/song_model.dart';
import '../services/discovery_service.dart';
import '../theme/app_theme.dart';
import '../widgets/bottom_player_bar.dart';
import '../widgets/song_artwork_widget.dart';
import '../widgets/spotify_lyrics_sheet.dart';

/// Playlist-style page for a discovery section (Community Favorites,
/// Trending For You): cover, Play / Shuffle, and the full song list.
///
/// Songs play as a real queue, so the next track starts on its own. Nothing
/// here is saved to the library.
class DiscoveryPlaylistPage extends StatelessWidget {
  const DiscoveryPlaylistPage({
    super.key,
    required this.section,
    required this.controller,
  });

  final DiscoverySection section;
  final MusicPlayerController controller;

  static Route<void> route({
    required DiscoverySection section,
    required MusicPlayerController controller,
  }) {
    return MaterialPageRoute<void>(
      builder: (_) => DiscoveryPlaylistPage(section: section, controller: controller),
    );
  }

  void _playFrom(List<Song> songs, int index) {
    controller.playSongList(songs, startIndex: index);
  }

  void _shuffle() {
    final shuffled = List<Song>.from(section.songs)..shuffle();
    _playFrom(shuffled, 0);
  }

  void _openLyrics(BuildContext context) {
    final song = controller.currentSong ?? section.songs.firstOrNull;
    if (song == null) return;
    SpotifyLyricsSheet.show(context, song: song, controller: controller);
  }

  static String _clock(Duration d) {
    final minutes = d.inMinutes;
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final songs = section.songs;
    final cover = songs.firstOrNull;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
        title: Text(
          section.title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final currentId = controller.currentSong?.id;
          return RefreshIndicator(
            onRefresh: () async {
              controller.fastLocateDiscoverySongs(songs);
              await Future<void>.delayed(const Duration(milliseconds: 600));
            },
            color: AppTheme.primary,
            backgroundColor: AppTheme.cardSurface,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
              itemCount: songs.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _Header(
                    section: section,
                    cover: cover,
                    onPlay: () => _playFrom(songs, 0),
                    onShuffle: _shuffle,
                  );
                }
                final songIndex = index - 1;
                final song = songs[songIndex];
                final isCurrent = song.id == currentId;
                return _SongRow(
                  number: songIndex + 1,
                  song: song,
                  isCurrent: isCurrent,
                  isPlaying: isCurrent && controller.isPlaying,
                  duration: _clock(song.duration),
                  onTap: () => isCurrent
                      ? controller.togglePlayPause()
                      : _playFrom(songs, songIndex),
                );
              },
            ),
          );
        },
      ),
      bottomNavigationBar: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => BottomPlayerBar(
          controller: controller,
          onOpenLyrics: () => _openLyrics(context),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.section,
    required this.cover,
    required this.onPlay,
    required this.onShuffle,
  });

  final DiscoverySection section;
  final Song? cover;
  final VoidCallback onPlay;
  final VoidCallback onShuffle;

  @override
  Widget build(BuildContext context) {
    final count = section.songs.length;
    final total = section.songs.fold<Duration>(
      Duration.zero,
      (sum, s) => sum + s.duration,
    );
    final hours = total.inHours;
    final minutes = total.inMinutes % 60;
    final length = hours > 0 ? '$hours hr $minutes min' : '${total.inMinutes} min';

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (cover != null)
            SongArtworkWidget(song: cover!, size: 120, borderRadius: 14),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  section.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$count songs · $length',
                  style: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: onPlay,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Play'),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.cardSurface,
                        foregroundColor: AppTheme.textPrimary,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: const BorderSide(color: AppTheme.border),
                        ),
                      ),
                      onPressed: onShuffle,
                      icon: const Icon(Icons.shuffle_rounded, size: 18),
                      label: const Text('Shuffle'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SongRow extends StatelessWidget {
  const _SongRow({
    required this.number,
    required this.song,
    required this.isCurrent,
    required this.isPlaying,
    required this.duration,
    required this.onTap,
  });

  final int number;
  final Song song;
  final bool isCurrent;
  final bool isPlaying;
  final String duration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isCurrent
                  ? AppTheme.primary.withValues(alpha: 0.15)
                  : AppTheme.cardSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isCurrent
                    ? AppTheme.primary.withValues(alpha: 0.5)
                    : AppTheme.border,
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    '$number',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: isCurrent ? AppTheme.primary : AppTheme.textMuted,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                SongArtworkWidget(song: song, size: 44, borderRadius: 8),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isCurrent ? AppTheme.primary : AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              song.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textMuted,
                              ),
                            ),
                          ),
                          if (!song.hasAudio) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: AppTheme.accentPink.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: AppTheme.accentPink.withValues(alpha: 0.4),
                                ),
                              ),
                              child: const Text(
                                'LOCATING',
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.accentPink,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  duration,
                  style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
                const SizedBox(width: 8),
                Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 22,
                  color: isCurrent ? AppTheme.primary : AppTheme.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}