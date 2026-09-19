import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../controllers/music_player_controller.dart';
import 'animated_visualizer.dart';

class RightActivityPanel extends StatefulWidget {
  final MusicPlayerController controller;

  const RightActivityPanel({
    super.key,
    required this.controller,
  });

  @override
  State<RightActivityPanel> createState() => _RightActivityPanelState();
}

class _RightActivityPanelState extends State<RightActivityPanel>
    with SingleTickerProviderStateMixin {
  late AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    );
    if (widget.controller.isPlaying) {
      _rotationController.repeat();
    }
  }

  @override
  void didUpdateWidget(RightActivityPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller.isPlaying != oldWidget.controller.isPlaying) {
      if (widget.controller.isPlaying) {
        _rotationController.repeat();
      } else {
        _rotationController.stop();
      }
    }
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentSong = widget.controller.currentSong;
    final isPlaying = widget.controller.isPlaying;

    return Container(
      width: 320,
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          left: BorderSide(color: AppTheme.border, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'NOW PLAYING',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.4,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isPlaying ? AppTheme.accentGreen : AppTheme.textMuted,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isPlaying ? 'LIVE' : 'IDLE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isPlaying ? AppTheme.accentGreen : AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Spinning Vinyl / Album Showcase
                  const SizedBox(height: 10),
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      // Glow
                      Container(
                        width: 190,
                        height: 190,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: (currentSong?.gradientColors.first ?? AppTheme.primary)
                                  .withValues(alpha: isPlaying ? 0.35 : 0.05),
                              blurRadius: 36,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                      ),

                      // Vinyl Disc
                      RotationTransition(
                        turns: _rotationController,
                        child: Container(
                          width: 180,
                          height: 180,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const RadialGradient(
                              colors: [
                                Color(0xFF1E293B),
                                Color(0xFF0F172A),
                                Color(0xFF090D16),
                              ],
                              stops: [0.3, 0.7, 1.0],
                            ),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.15),
                              width: 3,
                            ),
                          ),
                          child: Center(
                            child: Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: currentSong?.gradientColors ??
                                      const [Color(0xFF334155), Color(0xFF1E293B)],
                                ),
                              ),
                              child: const Icon(
                                Icons.album_rounded,
                                color: Colors.white,
                                size: 36,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Track Info
                  Text(
                    currentSong?.title ?? 'No Track Playing',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    currentSong != null
                        ? '${currentSong.artist} • ${currentSong.album}'
                        : 'Player is currently idle',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),

                  const SizedBox(height: 16),

                  // Live Animated Equalizer
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.cardSurface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.border, width: 1),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'AUDIO FREQUENCY',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.0,
                                color: AppTheme.textMuted,
                              ),
                            ),
                            Text(
                              '${(widget.controller.volume * 100).toInt()}% Vol',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.secondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 38,
                          child: Center(
                            child: AnimatedVisualizer(
                              isPlaying: isPlaying,
                              barCount: 24,
                              maxHeight: 34,
                              barWidth: 4.5,
                              gradientColors: currentSong?.gradientColors,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Synchronized Lyrics snippet
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.cardSurface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.border, width: 1),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.lyrics_rounded, size: 16, color: AppTheme.primary),
                            SizedBox(width: 8),
                            Text(
                              'LYRICS PREVIEW',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.0,
                                color: AppTheme.textMuted,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (currentSong != null && currentSong.lyrics.isNotEmpty)
                          ...currentSong.lyrics.take(3).map((line) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text(
                                line,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.textSecondary,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            );
                          })
                        else
                          const Text(
                            'No lyrics or active track loaded',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.textMuted,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Up Next Section Header
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'UP NEXT IN QUEUE',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                            color: AppTheme.textMuted,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${widget.controller.queue.length} Tracks',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Up Next queue list
                  if (widget.controller.queue.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      alignment: Alignment.center,
                      child: const Text(
                        'Queue is empty',
                        style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                      ),
                    )
                  else
                    ...widget.controller.queue.asMap().entries.take(5).map((entry) {
                      final idx = entry.key;
                      final song = entry.value;
                      final isCurrent = idx == widget.controller.currentIndex;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => widget.controller.playSong(song),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              child: Row(
                                children: [
                                  Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(6),
                                      gradient: LinearGradient(colors: song.gradientColors),
                                    ),
                                    child: Center(
                                      child: Icon(
                                        isCurrent ? Icons.volume_up_rounded : Icons.music_note_rounded,
                                        size: 16,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          song.title,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                                            color: isCurrent ? AppTheme.primary : AppTheme.textPrimary,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          song.artist,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: AppTheme.textMuted,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    song.formattedDuration,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
