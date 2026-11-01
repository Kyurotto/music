import 'package:flutter/material.dart';
import '../models/song_model.dart';
import '../theme/app_theme.dart';
import '../controllers/music_player_controller.dart';
import 'song_artwork_widget.dart';

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
  bool _lyricsLookupRunning = false;
  bool _lyricsLookupFailed = false;
  String? _fetchingForId;
  String? _lastSeenSongId;

  /// True after the user taps a line — freezes auto-tracking for that
  /// song so a tap does not fight the playback progress cursor.
  bool _userPinnedLine = false;

  /// Approximate row height (line + padding + margin) for auto-scroll.
  static const _lineExtent = 58.0;

  @override
  void initState() {
    super.initState();
    _maybeFetchLyrics(widget.controller.currentSong ?? widget.song);
  }

  Future<void> _maybeFetchLyrics(Song song) async {
    final hasSyncedLyrics = song.lyrics.any((l) => Song.parseLyricTimestamp(l) != null);
    if (song.lyrics.isNotEmpty && hasSyncedLyrics) return;
    // Auto-lookup for Spotify imports — bundled songs already ship lyrics,
    // but imported previews still need a full-length upgrade pass.
    if (!song.id.startsWith('spotify-')) return;
    if (_lyricsLookupRunning && _fetchingForId == song.id) return;
    _fetchingForId = song.id;
    setState(() {
      _lyricsLookupRunning = true;
      _lyricsLookupFailed = false;
    });
    var ok = await widget.controller.ensureLyricsFor(song);
    // The import-time background enrichment may already be fetching this
    // song (ensureLyricsFor then returns false immediately). Wait for it
    // instead of flashing "not available" too early.
    if (!ok && mounted && widget.controller.isEnriching(song.id)) {
      for (var i = 0; i < 30; i++) {
        await Future.delayed(const Duration(seconds: 1));
        if (!mounted) return;
        if (song.lyrics.isNotEmpty) {
          ok = true;
          break;
        }
        if (!widget.controller.isEnriching(song.id)) break;
      }
      ok = song.lyrics.isNotEmpty;
    }
    if (!mounted) return;
    setState(() {
      _lyricsLookupRunning = false;
      _fetchingForId = null;
      _lyricsLookupFailed = !ok && song.lyrics.isEmpty;
    });
  }

  Future<void> _retryLyrics() async {
    final song = widget.controller.currentSong ?? widget.song;
    // Retry means retry now: drop the per-song failure backoff so the lookup
    // also re-resolves a stuck preview/fallback source.
    widget.controller.resetEnrichmentBackoff(song.id);
    setState(() {
      _lyricsLookupFailed = false;
      _highlightedLineIndex = null;
      _userPinnedLine = false;
      // Clear a stale "running" flag so the retry always issues a fresh
      // lookup instead of early-returning and getting stuck.
      if (_fetchingForId != song.id) {
        _lyricsLookupRunning = false;
        _fetchingForId = null;
      }
    });
    await _maybeFetchLyrics(song);
  }

  /// Sync the active line to playback progress (evenly spaced plain lines).
  /// Returns true when the highlight changed and a rebuild/scroll is needed.
  bool _syncHighlightToPlayback(Song song) {
    if (song.lyrics.isEmpty) return false;
    // User tapped a line: keep their pin until they tap again or the
    // track changes (both clear _userPinnedLine).
    if (_userPinnedLine) return false;
    final total = widget.controller.displayDurationFor(song);
    final auto = Song.lyricsLineIndexForProgress(
      song.lyrics,
      widget.controller.currentPosition,
      total,
    );
    if (_highlightedLineIndex == auto) return false;
    _highlightedLineIndex = auto;
    return true;
  }

  void _scrollToLine(int index) {
    if (!_scrollController.hasClients) return;
    final target = (index * _lineExtent - 120).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _onLineTapped(Song song, int index) {
    setState(() {
      if (_highlightedLineIndex == index && _userPinnedLine) {
        // Second tap on the same line: release the pin and resume tracking.
        _userPinnedLine = false;
        _syncHighlightToPlayback(song);
      } else {
        _userPinnedLine = true;
        _highlightedLineIndex = index;
      }
    });
    // Seek so the audio and the highlighted line stay in agreement.
    final total = widget.controller.displayDurationFor(song);
    widget.controller.seekTo(
      Song.positionForLyricsLine(song.lyrics, index, total),
    );
    _scrollToLine(index);
  }

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
        // If the track changed while the sheet is open (auto-next, skip),
        // kick off a lyrics lookup for the newly displayed song.
        if (_lastSeenSongId != currentSong.id) {
          _lastSeenSongId = currentSong.id;
          _highlightedLineIndex = null;
          _userPinnedLine = false;
          final hasSyncedLyrics =
              currentSong.lyrics.any((l) => Song.parseLyricTimestamp(l) != null);
          if (currentSong.id.startsWith('spotify-') &&
              (currentSong.lyrics.isEmpty ||
                  !hasSyncedLyrics ||
                  currentSong.isPreview)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _maybeFetchLyrics(currentSong);
            });
          } else {
            _lyricsLookupFailed = false;
          }
        }
        // Compute the highlight line index *without* mutating state inside the
        // builder — _syncHighlightToPlayback sets _highlightedLineIndex, and
        // doing that mid-build can trigger the parentDataDirty assertion.
        // Instead, read what the line *should* be and, if it differs from the
        // current highlight, schedule a post-frame setState + scroll.
        if (!_userPinnedLine && currentSong.lyrics.isNotEmpty) {
          final total = widget.controller.displayDurationFor(currentSong);
          final expected = Song.lyricsLineIndexForProgress(
            currentSong.lyrics,
            widget.controller.currentPosition,
            total,
          );
          if (_highlightedLineIndex != expected) {
            final target = expected;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() {
                _highlightedLineIndex = target;
              });
              if (!_userPinnedLine) _scrollToLine(target);
            });
          }
        }

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
                        SongArtworkWidget(
                          song: currentSong,
                          size: 58,
                          borderRadius: 12,
                          showGlow: true,
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
                          child: SingleChildScrollView(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 32),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_lyricsLookupRunning ||
                                    currentSong.isEnrichingLyrics)
                                  const SizedBox(
                                    width: 44,
                                    height: 44,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                      color: Colors.white,
                                    ),
                                  )
                                else
                                  Icon(
                                    Icons.queue_music_rounded,
                                    size: 56,
                                    color: Colors.white.withValues(alpha: 0.4),
                                  ),
                                const SizedBox(height: 16),
                                Text(
                                  (_lyricsLookupRunning ||
                                          currentSong.isEnrichingLyrics)
                                      ? 'Looking up lyrics…'
                                      : 'Lyrics are not available yet',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  (_lyricsLookupRunning ||
                                          currentSong.isEnrichingLyrics)
                                      ? 'Fetching "${currentSong.title}" by ${currentSong.artist}…'
                                      : 'Enjoy "${currentSong.title}" by ${currentSong.artist}',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.white.withValues(alpha: 0.65),
                                  ),
                                ),
                                if (_lyricsLookupFailed &&
                                    !_lyricsLookupRunning &&
                                    !currentSong.isEnrichingLyrics) ...[
                                  const SizedBox(height: 16),
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      side: const BorderSide(
                                          color: Colors.white30),
                                    ),
                                    onPressed: _retryLyrics,
                                    icon: const Icon(
                                        Icons.refresh_rounded,
                                        size: 18),
                                    label: const Text('Retry lyrics lookup'),
                                  ),
                                ],
                              ],
                            ),
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
                                onTap: () => _onLineTapped(currentSong, index),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                                  margin: const EdgeInsets.only(bottom: 6),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? Colors.white.withValues(alpha: 0.22)
                                        : Colors.white.withValues(alpha: 0.06),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isSelected
                                          ? Colors.white.withValues(alpha: 0.35)
                                          : Colors.white.withValues(alpha: 0.08),
                                      width: 1,
                                    ),
                                  ),
                                  child: Text(
                                    Song.stripTimestamp(line),
                                    style: const TextStyle(
                                      fontSize: 21,
                                      height: 1.45,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.3,
                                      // Pure white on every line so lyrics
                                      // stay readable on any artwork tint.
                                      color: Colors.white,
                                      shadows: [
                                        BoxShadow(
                                          color: Colors.black54,
                                          blurRadius: 8,
                                          offset: Offset(0, 2),
                                        ),
                                      ],
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
                        child: Builder(
                          builder: (context) {
                            final totalDur = widget.controller.displayDurationFor(currentSong);
                            final maxMs = totalDur.inMilliseconds > 0
                                ? totalDur.inMilliseconds.toDouble()
                                : 1.0;
                            final currentMs = widget.controller.currentPosition.inMilliseconds
                                .toDouble()
                                .clamp(0.0, maxMs);
                            return Slider(
                              value: currentMs,
                              min: 0.0,
                              max: maxMs,
                              onChanged: (val) {
                                widget.controller.seekTo(
                                    Duration(milliseconds: val.toInt()));
                              },
                            );
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
                              // Use the real playable length for the current
                              // track so a ~30s preview shows 0:30 (matching
                              // the slider) instead of a full-length timer.
                              Song.formatTime(widget.controller
                                  .displayDurationFor(currentSong)),
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
