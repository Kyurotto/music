import 'package:flutter/material.dart';
import '../models/song_model.dart';
import '../theme/app_theme.dart';
import '../controllers/music_player_controller.dart';
import 'animated_visualizer.dart';

class BottomPlayerBar extends StatelessWidget {
  final MusicPlayerController controller;

  const BottomPlayerBar({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final song = controller.currentSong;
    final isPlaying = controller.isPlaying;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F131D),
        border: const Border(
          top: BorderSide(color: AppTheme.border, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 700;

          if (isCompact) {
            return _buildCompactPlayer(context, song, isPlaying);
          }
          return _buildDesktopPlayer(context, song, isPlaying);
        },
      ),
    );
  }

  Widget _buildCompactPlayer(BuildContext context, Song? song, bool isPlaying) {
    final pos = controller.currentPosition.inMilliseconds.toDouble();
    final dur = controller.currentDuration.inMilliseconds.toDouble();
    final progress = dur > 0 ? (pos / dur).clamp(0.0, 1.0) : 0.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Top slim progress bar
        LinearProgressIndicator(
          value: progress,
          backgroundColor: Colors.white10,
          valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
          minHeight: 2.5,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              // Artwork
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: LinearGradient(
                    colors: song?.gradientColors ?? const [Color(0xFF334155), Color(0xFF1E293B)],
                  ),
                ),
                child: const Icon(Icons.music_note_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),

              // Title & Artist
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      song?.title ?? 'No track selected',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      song?.artist ?? 'Select or add a track',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // Like button
              IconButton(
                icon: Icon(
                  (song?.isLiked ?? false) ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  size: 20,
                  color: (song?.isLiked ?? false) ? AppTheme.accentPink : AppTheme.textSecondary,
                ),
                onPressed: song != null ? () => controller.toggleLike(song.id) : null,
              ),

              // Play / Pause
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: song != null
                      ? AppTheme.primaryGradient
                      : const LinearGradient(colors: [Color(0xFF334155), Color(0xFF1E293B)]),
                ),
                child: IconButton(
                  icon: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                  onPressed: song != null ? controller.togglePlayPause : null,
                ),
              ),

              // Next
              IconButton(
                icon: const Icon(Icons.skip_next_rounded, size: 26, color: AppTheme.textPrimary),
                onPressed: song != null ? controller.next : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopPlayer(BuildContext context, Song? song, bool isPlaying) {
    return Container(
      height: 86,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          // Left: Current Track Info (260px)
          SizedBox(
            width: 240,
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: LinearGradient(
                      colors: song?.gradientColors ?? const [Color(0xFF334155), Color(0xFF1E293B)],
                    ),
                    boxShadow: song != null
                        ? [
                            BoxShadow(
                              color: song.gradientColors.first.withValues(alpha: 0.3),
                              blurRadius: 8,
                            ),
                          ]
                        : null,
                  ),
                  child: const Center(
                    child: Icon(Icons.music_note_rounded, color: Colors.white, size: 24),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song?.title ?? 'No track selected',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        song?.artist ?? 'Select a song to play',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    (song?.isLiked ?? false) ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    size: 20,
                    color: (song?.isLiked ?? false) ? AppTheme.accentPink : AppTheme.textMuted,
                  ),
                  splashRadius: 18,
                  onPressed: song != null ? () => controller.toggleLike(song.id) : null,
                ),
              ],
            ),
          ),

          // Center: Main Controls & Scrubber (Expanded)
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Buttons row
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Shuffle
                    IconButton(
                      icon: Icon(
                        Icons.shuffle_rounded,
                        size: 18,
                        color: controller.isShuffle ? AppTheme.secondary : AppTheme.textMuted,
                      ),
                      splashRadius: 18,
                      tooltip: 'Shuffle',
                      onPressed: song != null ? controller.toggleShuffle : null,
                    ),
                    const SizedBox(width: 8),

                    // Previous
                    IconButton(
                      icon: const Icon(Icons.skip_previous_rounded, size: 26, color: AppTheme.textPrimary),
                      splashRadius: 20,
                      onPressed: song != null ? controller.previous : null,
                    ),
                    const SizedBox(width: 8),

                    // Play / Pause with glow
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: song != null
                            ? AppTheme.primaryGradient
                            : const LinearGradient(colors: [Color(0xFF334155), Color(0xFF1E293B)]),
                        boxShadow: song != null
                            ? [
                                BoxShadow(
                                  color: AppTheme.primary.withValues(alpha: 0.45),
                                  blurRadius: 12,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: IconButton(
                        icon: Icon(
                          isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                        onPressed: song != null ? controller.togglePlayPause : null,
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Next
                    IconButton(
                      icon: const Icon(Icons.skip_next_rounded, size: 26, color: AppTheme.textPrimary),
                      splashRadius: 20,
                      onPressed: song != null ? controller.next : null,
                    ),
                    const SizedBox(width: 8),

                    // Repeat
                    IconButton(
                      icon: Icon(
                        controller.repeatMode == PlaybackRepeatMode.one
                            ? Icons.repeat_one_rounded
                            : Icons.repeat_rounded,
                        size: 18,
                        color: controller.repeatMode != PlaybackRepeatMode.off
                            ? AppTheme.primary
                            : AppTheme.textMuted,
                      ),
                      splashRadius: 18,
                      tooltip: 'Repeat: ${controller.repeatMode.name}',
                      onPressed: song != null ? controller.toggleRepeat : null,
                    ),
                  ],
                ),

                // Scrubber row
                Row(
                  children: [
                    Text(
                      Song.formatTime(controller.currentPosition),
                      style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3.5,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                        ),
                        child: Slider(
                          value: controller.currentPosition.inSeconds
                              .toDouble()
                              .clamp(0.0, controller.currentDuration.inSeconds.toDouble()),
                          min: 0.0,
                          max: controller.currentDuration.inSeconds.toDouble() > 0
                              ? controller.currentDuration.inSeconds.toDouble()
                              : 1.0,
                          onChanged: song != null
                              ? (val) {
                                  controller.seekTo(Duration(seconds: val.toInt()));
                                }
                              : null,
                        ),
                      ),
                    ),
                    Text(
                      song != null ? song.formattedDuration : '0:00',
                      style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Right: Mini visualizer, Queue, Volume Controls (240px)
          SizedBox(
            width: 240,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Mini visualizer
                SizedBox(
                  width: 32,
                  height: 20,
                  child: AnimatedVisualizer(
                    isPlaying: isPlaying,
                    barCount: 5,
                    maxHeight: 18,
                    barWidth: 2.5,
                  ),
                ),
                const SizedBox(width: 8),

                // Volume button
                IconButton(
                  icon: Icon(
                    controller.isMuted || controller.volume == 0
                        ? Icons.volume_off_rounded
                        : (controller.volume < 0.5 ? Icons.volume_down_rounded : Icons.volume_up_rounded),
                    size: 20,
                    color: controller.isMuted ? AppTheme.accentPink : AppTheme.textSecondary,
                  ),
                  splashRadius: 18,
                  onPressed: controller.toggleMute,
                ),

                // Volume slider
                SizedBox(
                  width: 85,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
                      activeTrackColor: AppTheme.secondary,
                    ),
                    child: Slider(
                      value: controller.volume,
                      min: 0.0,
                      max: 1.0,
                      onChanged: controller.setVolume,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
