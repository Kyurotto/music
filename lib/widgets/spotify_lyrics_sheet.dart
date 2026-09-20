import 'package:flutter/material.dart';
import '../models/song_model.dart';
import '../theme/app_theme.dart';
import '../controllers/music_player_controller.dart';

class SpotifyLyricsSheet extends StatefulWidget {
  final Song song;
  final MusicPlayerController controller;

  const SpotifyLyricsSheet({
    super.key,
    required this.song,
    required this.controller,
  });

  static Future<void> show(BuildContext context, {
    required Song song,
    required MusicPlayerController controller,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (context) => SpotifyLyricsSheet(
        song: song,
        controller: controller,
      ),
    );
  }

  @override
  State<SpotifyLyricsSheet> createState() => _SpotifyLyricsSheetState();
}

class _SpotifyLyricsSheetState extends State<SpotifyLyricsSheet> {
  final ScrollController _scrollController = ScrollController();
  int? _highlightedLineIndex;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final sheetHeight = mediaQuery.size.height * 0.90;

    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final currentSong = widget.controller.currentSong ?? widget.song;
        final isPlaying = widget.controller.isPlaying;
        final primaryColor = currentSong.gradientColors.isNotEmpty
            ? currentSong.gradientColors.first
            : const Color(0xFF6366F1);
        final secondaryColor = currentSong.gradientColors.length > 1
            ? currentSong.gradientColors.last
            : const Color(0xFF1E1B4B);

        return Container(
          height: sheetHeight,
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                primaryColor.withValues(alpha: 0.95),
                secondaryColor.withValues(alpha: 0.85),
                const Color(0xFF111422),
                const Color(0xFF090B10),
              ],
              stops: const [0.0, 0.30, 0.65, 1.0],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.7),
                blurRadius: 32,
                offset: const Offset(0, -6),
              ),
            ],
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.15),
              width: 1,
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                // Drag handle pill
                const SizedBox(height: 10),
                Center(
                  child: Container(
                    width: 42,
                    height: 4.5,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(height: 6),

                // Top navigation bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                        tooltip: 'Close lyrics',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'PLAYING WITH LYRICS',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2,
                                color: Colors.white.withValues(alpha: 0.7),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              currentSong.album,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          currentSong.isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          color: currentSong.isLiked ? AppTheme.accentPink : Colors.white70,
                          size: 24,
                        ),
                        tooltip: 'Like',
                        onPressed: () => widget.controller.toggleLike(currentSong.id),
                      ),
                    ],
                  ),
                ),

                const Divider(color: Colors.white12, height: 16),

                // Song Header Preview Card
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Row(
                    children: [
                      // Thumbnail
                      Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: LinearGradient(
                            colors: currentSong.gradientColors,
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: currentSong.gradientColors.first.withValues(alpha: 0.4),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Icon(Icons.music_note_rounded, color: Colors.white, size: 28),
                        ),
                      ),
                      const SizedBox(width: 14),

                      // Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              currentSong.title,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: -0.3,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    currentSong.artist,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.white.withValues(alpha: 0.85),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    currentSong.genre,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Lyrics tag badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.lyrics_rounded, size: 14, color: Colors.white),
                            SizedBox(width: 5),
                            Text(
                              'LYRICS',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // Main Lyrics View
                Expanded(
                  child: currentSong.lyrics.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.queue_music_rounded,
                                size: 56,
                                color: Colors.white.withValues(alpha: 0.4),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Lyrics are not available yet',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Enjoy "${currentSong.title}" by ${currentSong.artist}',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.white.withValues(alpha: 0.65),
                                ),
                              ),
                            ],
                          ),
                        )
                      : ShaderMask(
                          shaderCallback: (Rect bounds) {
                            return const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.white,
                                Colors.white,
                                Colors.transparent,
                              ],
                              stops: [0.0, 0.04, 0.94, 1.0],
                            ).createShader(bounds);
                          },
                          blendMode: BlendMode.dstIn,
                          child: ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                            itemCount: currentSong.lyrics.length,
                            itemBuilder: (context, index) {
                              final line = currentSong.lyrics[index];
                              final isSelected = _highlightedLineIndex == index;

                              return InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () {
                                  setState(() => _highlightedLineIndex = index);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                                  margin: const EdgeInsets.only(bottom: 6),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? Colors.white.withValues(alpha: 0.12)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    line,
                                    style: TextStyle(
                                      fontSize: 21,
                                      height: 1.45,
                                      fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                                      letterSpacing: -0.3,
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.white.withValues(alpha: 0.72),
                                      shadows: isSelected
                                          ? [
                                              BoxShadow(
                                                color: Colors.black.withValues(alpha: 0.6),
                                                blurRadius: 10,
                                                offset: const Offset(0, 2),
                                              ),
                                            ]
                                          : null,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                ),

                // Bottom Controls & Scrubber Section
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF090B10).withValues(alpha: 0.92),
                    border: Border(
                      top: BorderSide(
                        color: Colors.white.withValues(alpha: 0.1),
                        width: 1,
                      ),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Scrubber row
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3.5,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                          activeTrackColor: Colors.white,
                          inactiveTrackColor: Colors.white24,
                          thumbColor: Colors.white,
                        ),
                        child: Slider(
                          value: widget.controller.currentPosition.inSeconds
                              .toDouble()
                              .clamp(0.0, widget.controller.currentDuration.inSeconds.toDouble()),
                          min: 0.0,
                          max: widget.controller.currentDuration.inSeconds.toDouble() > 0
                              ? widget.controller.currentDuration.inSeconds.toDouble()
                              : 1.0,
                          onChanged: (val) {
                            widget.controller.seekTo(Duration(seconds: val.toInt()));
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              Song.formatTime(widget.controller.currentPosition),
                              style: const TextStyle(fontSize: 11, color: Colors.white60),
                            ),
                            Text(
                              currentSong.formattedDuration,
                              style: const TextStyle(fontSize: 11, color: Colors.white60),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 6),

                      // Player buttons row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // Shuffle
                          IconButton(
                            icon: Icon(
                              Icons.shuffle_rounded,
                              size: 22,
                              color: widget.controller.isShuffle
                                  ? AppTheme.primary
                                  : Colors.white54,
                            ),
                            tooltip: 'Shuffle',
                            onPressed: widget.controller.toggleShuffle,
                          ),

                          // Previous
                          IconButton(
                            icon: const Icon(
                              Icons.skip_previous_rounded,
                              size: 32,
                              color: Colors.white,
                            ),
                            tooltip: 'Previous',
                            onPressed: widget.controller.previous,
                          ),

                          // Play / Pause Circle
                          Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: AppTheme.primaryGradient,
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.primary.withValues(alpha: 0.45),
                                  blurRadius: 14,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: IconButton(
                              icon: Icon(
                                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                size: 30,
                                color: Colors.white,
                              ),
                              tooltip: isPlaying ? 'Pause' : 'Play',
                              onPressed: widget.controller.togglePlayPause,
                            ),
                          ),

                          // Next
                          IconButton(
                            icon: const Icon(
                              Icons.skip_next_rounded,
                              size: 32,
                              color: Colors.white,
                            ),
                            tooltip: 'Next',
                            onPressed: widget.controller.next,
                          ),

                          // Repeat
                          IconButton(
                            icon: Icon(
                              widget.controller.repeatMode == PlaybackRepeatMode.one
                                  ? Icons.repeat_one_rounded
                                  : Icons.repeat_rounded,
                              size: 22,
                              color: widget.controller.repeatMode != PlaybackRepeatMode.off
                                  ? AppTheme.primary
                                  : Colors.white54,
                            ),
                            tooltip: 'Repeat',
                            onPressed: widget.controller.toggleRepeat,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
