import 'package:flutter/material.dart';
import '../models/song_model.dart';
import '../theme/app_theme.dart';
import '../controllers/music_player_controller.dart';

class HeroBanner extends StatelessWidget {
  final Song? song;
  final MusicPlayerController controller;
  final ValueChanged<Song>? onPlaySong;

  const HeroBanner({
    super.key,
    required this.song,
    required this.controller,
    this.onPlaySong,
  });

  @override
  Widget build(BuildContext context) {
    final currentSong = song;
    final isCurrentPlaying = currentSong != null &&
        controller.isPlaying &&
        controller.currentSong?.id == currentSong.id;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 620;
        final showSideArtwork = constraints.maxWidth >= 550;

        return Container(
          width: double.infinity,
          constraints: BoxConstraints(minHeight: isCompact ? 180 : 220),
          decoration: BoxDecoration(
            color: AppTheme.cardSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppTheme.border,
              width: 1,
            ),
          ),
          child: Padding(
                padding: EdgeInsets.all(isCompact ? 18.0 : 28.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Info Section
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.15),
                                width: 1,
                              ),
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    currentSong != null
                                        ? Icons.local_fire_department_rounded
                                        : Icons.music_note_rounded,
                                    size: 15,
                                    color: currentSong != null
                                        ? const Color(0xFFFF7A00)
                                        : AppTheme.secondary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    currentSong != null ? 'NOW PLAYING' : 'OFFLINE MUSIC PLAYER',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.0,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Title
                          Text(
                            currentSong != null ? currentSong.title : 'Welcome to Pulse Music',
                            style: TextStyle(
                              fontSize: isCompact ? 22 : 28,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.textPrimary,
                              letterSpacing: -0.5,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),

                          // Artist & Album
                          Text(
                            currentSong != null
                                ? '${currentSong.artist} • ${currentSong.album}'
                                : 'Ready for your offline songs. Add or import tracks to play.',
                            style: TextStyle(
                              fontSize: isCompact ? 12 : 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.75),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 16),

                          // Buttons
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            children: [
                              if (currentSong != null) ...[
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: const Color(0xFF0F172A),
                                    padding: EdgeInsets.symmetric(
                                      horizontal: isCompact ? 16 : 22,
                                      vertical: isCompact ? 10 : 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    elevation: 4,
                                  ),
                                  icon: Icon(
                                    isCurrentPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                    size: isCompact ? 18 : 22,
                                  ),
                                  label: Text(
                                    isCurrentPlaying ? 'Pause' : (isCompact ? 'Play' : 'Listen Now'),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  onPressed: () {
                                    if (isCurrentPlaying) {
                                      controller.pause();
                                    } else {
                                      if (onPlaySong != null) {
                                        onPlaySong!(currentSong);
                                      } else {
                                        controller.playSong(currentSong);
                                      }
                                    }
                                  },
                                ),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: BorderSide(
                                      color: Colors.white.withValues(alpha: 0.3),
                                      width: 1.5,
                                    ),
                                    padding: EdgeInsets.symmetric(
                                      horizontal: isCompact ? 14 : 18,
                                      vertical: isCompact ? 10 : 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  icon: Icon(
                                    currentSong.isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                    size: isCompact ? 16 : 20,
                                    color: currentSong.isLiked ? AppTheme.accentPink : Colors.white,
                                  ),
                                  label: Text(
                                    currentSong.isLiked ? 'Saved' : 'Favorite',
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                  ),
                                  onPressed: () => controller.toggleLike(currentSong.id),
                                ),
                              ] else ...[
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primary,
                                    foregroundColor: const Color(0xFF0F172A),
                                    padding: EdgeInsets.symmetric(
                                      horizontal: isCompact ? 16 : 22,
                                      vertical: isCompact ? 10 : 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  icon: const Icon(Icons.library_music_rounded, size: 18),
                                  label: const Text('Your Library', style: TextStyle(fontWeight: FontWeight.bold)),
                                  onPressed: () => controller.setNavIndex(2),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Artwork Visual
                    if (showSideArtwork) ...[
                      const SizedBox(width: 20),
                      Container(
                        width: isCompact ? 110 : 150,
                        height: isCompact ? 110 : 150,
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppTheme.border,
                            width: 1,
                          ),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Icon(
                              Icons.album_rounded,
                              size: isCompact ? 52 : 72,
                              color: AppTheme.textPrimary.withValues(alpha: 0.85),
                            ),
                            if (isCurrentPlaying)
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.black45,
                                ),
                                child: Icon(
                                  Icons.graphic_eq_rounded,
                                  color: AppTheme.primary,
                                  size: 26,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
        );
      },
    );
  }
}
