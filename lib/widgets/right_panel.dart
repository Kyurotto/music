import 'package:flutter/material.dart';
import '../models/song_model.dart';
import '../theme/app_theme.dart';
import '../controllers/music_player_controller.dart';
import 'animated_visualizer.dart';
import 'song_artwork_widget.dart';

class RightActivityPanel extends StatefulWidget {
  final MusicPlayerController controller;
  final VoidCallback? onOpenLyrics;
  final ValueChanged<Song>? onPlaySong;

  const RightActivityPanel({
    super.key,
    required this.controller,
    this.onOpenLyrics,
    this.onPlaySong,
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
                            child: SongArtworkWidget(
                              song: currentSong,
                              size: 80,
                              isCircle: true,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.3),
                                width: 2,
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
                            const Flexible(
                              child: Text(
                                'AUDIO FREQUENCY',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.0,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: AppTheme.primary.withValues(alpha: 0.3),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Text(
                                    widget.controller.equalizerPreset,
                                    style: const TextStyle(
                                      fontSize: 9.5,
                                      color: AppTheme.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '${(widget.controller.volume * 100).toInt()}% Vol',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    color: AppTheme.secondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
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
                              equalizerBands: widget.controller.currentEqualizer.bands,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Synchronized Lyrics snippet (Tappable for full lyrics)
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: widget.onOpenLyrics,
                      child: Container(
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
                        if (currentSong != null &&
                            currentSong.lyrics.isNotEmpty) ...[
                          // Window of lines around the active one so the
                          // panel tracks playback instead of showing a
                          // frozen first-four preview.
                          Builder(
                            builder: (context) {
                              final total = widget.controller
                                  .displayDurationFor(currentSong);
                              final active = Song.lyricsLineIndexForProgress(
                                currentSong.lyrics,
                                widget.controller.currentPosition,
                                total,
                              );
                              final start = (active - 1)
                                  .clamp(0, currentSong.lyrics.length - 1)
                                  .toInt();
                              final end = (active + 3)
                                  .clamp(0, currentSong.lyrics.length)
                                  .toInt();
                              final window =
                                  currentSong.lyrics.sublist(start, end);
                              var offset = start;
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: window.map((line) {
                                  final i = offset++;
                                  final isActive = i == active;
                                  return Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 6),
                                    child: Text(
                                      line,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: isActive ? 14 : 13,
                                        height: 1.3,
                                        fontWeight: isActive
                                            ? FontWeight.w800
                                            : FontWeight.w600,
                                        color: Colors.white,
                                        shadows: const [
                                          BoxShadow(
                                            color: Colors.black54,
                                            blurRadius: 6,
                                            offset: Offset(0, 1),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              );
                            },
                          ),
                        ] else if (currentSong != null)
                          const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white70,
                                ),
                              ),
                              SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'Loading white lyrics…',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.white70,
                                  ),
                                ),
                              ),
                            ],
                          )
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
                            onTap: () {
                              if (widget.onPlaySong != null) {
                                widget.onPlaySong!(song);
                              } else {
                                widget.controller.playSong(song);
                              }
                            },
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
