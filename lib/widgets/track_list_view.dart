import 'package:flutter/material.dart';
import '../models/song_model.dart';
import '../theme/app_theme.dart';
import '../controllers/music_player_controller.dart';
import 'animated_visualizer.dart';
import 'song_artwork_widget.dart';

class TrackListView extends StatelessWidget {
  final List<Song> songs;
  final MusicPlayerController controller;
  final ValueChanged<Song>? onAddToPlaylist;
  final ValueChanged<Song>? onSongTap;
  final ValueChanged<Song>? onDelete;
  final String? emptyTitle;
  final String? emptySubtitle;

  const TrackListView({
    super.key,
    required this.songs,
    required this.controller,
    this.onAddToPlaylist,
    this.onSongTap,
    this.onDelete,
    this.emptyTitle,
    this.emptySubtitle,
  });

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(40),
        alignment: Alignment.center,
        child: Column(
          children: [
            Icon(Icons.queue_music_rounded,
                size: 48, color: AppTheme.textMuted.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(
              emptyTitle ?? 'No tracks found',
              style: const TextStyle(
                  fontSize: 16,
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              emptySubtitle ?? 'Try changing your search query or genre filter',
              style: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 650;
        final showAlbum = constraints.maxWidth > 750;
        final showPlays = constraints.maxWidth > 550;

        return Column(
          children: [
            // Table Header (desktop / wide screens only)
            if (!isCompact) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 32,
                      child: Text(
                        '#',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textMuted,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const SizedBox(width: 44), // Artwork column spacer
                    const SizedBox(width: 14),
                    const Expanded(
                      flex: 4,
                      child: Text(
                        'TITLE',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textMuted,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                    if (showAlbum)
                      const Expanded(
                        flex: 3,
                        child: Text(
                          'ALBUM',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textMuted,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                    if (showPlays)
                      const SizedBox(
                        width: 90,
                        child: Text(
                          'PLAYS',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textMuted,
                            letterSpacing: 1.0,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    const SizedBox(
                      width: 70,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Icon(Icons.access_time_rounded,
                              size: 14, color: AppTheme.textMuted),
                        ],
                      ),
                    ),
                    // Spacer matching the action buttons area
                    const SizedBox(width: 72),
                  ],
                ),
              ),
              const Divider(height: 1),
            ],

            // Track Rows
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: songs.length,
              itemBuilder: (context, index) {
                final song = songs[index];
                final isCurrent = controller.currentSong?.id == song.id;
                final isCurrentPlaying = isCurrent && controller.isPlaying;

                return _TrackRow(
                  index: index + 1,
                  song: song,
                  isCurrent: isCurrent,
                  isPlaying: isCurrentPlaying,
                  showAlbum: showAlbum,
                  showPlays: showPlays,
                  isCompact: isCompact,
                  onTap: () {
                    if (onSongTap != null) {
                      onSongTap!(song);
                    } else {
                      if (isCurrent) {
                        controller.togglePlayPause();
                      } else {
                        controller.playSong(song);
                      }
                    }
                  },
                  onLikeToggle: () => controller.toggleLike(song.id),
                  onAddToQueue: () => controller.addToQueue(song),
                  onAddToPlaylist:
                      onAddToPlaylist == null ? null : () => onAddToPlaylist!(song),
                  onDelete: onDelete == null ? null : () => onDelete!(song),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _TrackRow extends StatefulWidget {
  final int index;
  final Song song;
  final bool isCurrent;
  final bool isPlaying;
  final bool showAlbum;
  final bool showPlays;
  final bool isCompact;
  final VoidCallback onTap;
  final VoidCallback onLikeToggle;
  final VoidCallback onAddToQueue;
  final VoidCallback? onAddToPlaylist;
  final VoidCallback? onDelete;

  const _TrackRow({
    required this.index,
    required this.song,
    required this.isCurrent,
    required this.isPlaying,
    required this.showAlbum,
    required this.showPlays,
    required this.isCompact,
    required this.onTap,
    required this.onLikeToggle,
    required this.onAddToQueue,
    this.onAddToPlaylist,
    this.onDelete,
  });

  @override
  State<_TrackRow> createState() => _TrackRowState();
}

class _TrackRowState extends State<_TrackRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            margin: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: widget.isCurrent
                  ? AppTheme.primary.withValues(alpha: 0.12)
                  : (_isHovered ? AppTheme.cardSurfaceHover : Colors.transparent),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: widget.isCurrent
                    ? AppTheme.borderActive
                    : Colors.transparent,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                // Track number or play indicator (desktop / wide screens only)
                if (!widget.isCompact) ...[
                  SizedBox(
                    width: 32,
                    child: Center(
                      child: widget.isPlaying
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: AnimatedVisualizer(
                                isPlaying: true,
                                barCount: 4,
                                maxHeight: 16,
                                barWidth: 2,
                              ),
                            )
                          : (_isHovered
                              ? const Icon(Icons.play_arrow_rounded,
                                  size: 18, color: AppTheme.textPrimary)
                              : Text(
                                  '${widget.index}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: widget.isCurrent
                                        ? AppTheme.primary
                                        : AppTheme.textMuted,
                                  ),
                                )),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],

                // Artwork Thumbnail
                SongArtworkWidget(
                  song: widget.song,
                  size: 44,
                  borderRadius: 8,
                ),
                const SizedBox(width: 14),

                // Title & Artist with inline indicator
                Expanded(
                  flex: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.song.title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: widget.isCurrent
                              ? AppTheme.primary
                              : AppTheme.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          if (_hasBadge(widget.song)) ...[
                            ExcludeSemantics(child: _buildInlineBadge(widget.song)),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
                            child: Text(
                              widget.song.artist,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),


                        ],
                      ),
                    ],
                  ),
                ),

                // Album column
                if (widget.showAlbum)
                  Expanded(
                    flex: 3,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: Text(
                        widget.song.album,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.textMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),

                // Plays column
                if (widget.showPlays)
                  SizedBox(
                    width: 90,
                    child: Text(
                      widget.song.plays,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.textMuted,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),

                // Duration — bounded so it never forces the track row to
                // overflow on narrow dashboard/library widths.
                SizedBox(
                  width: widget.isCompact ? 50 : 70,
                  child: Text(
                    widget.song.formattedDuration,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppTheme.textMuted,
                    ),
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),

                // Action buttons — mainAxisSize.min prevents any overflow
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: widget.onLikeToggle,
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.all(5),
                        child: Icon(
                          widget.song.isLiked
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          size: 18,
                          color: widget.song.isLiked
                              ? AppTheme.accentPink
                              : AppTheme.textMuted,
                        ),
                      ),
                    ),
                    if (widget.onAddToPlaylist != null)
                      InkWell(
                        onTap: widget.onAddToPlaylist,
                        borderRadius: BorderRadius.circular(20),
                        child: const Padding(
                          padding: EdgeInsets.all(5),
                          child: Icon(
                            Icons.playlist_add_rounded,
                            size: 19,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ),
                    if (widget.onDelete != null)
                      InkWell(
                        onTap: widget.onDelete,
                        borderRadius: BorderRadius.circular(20),
                        child: const Padding(
                          padding: EdgeInsets.all(5),
                          child: Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _hasBadge(Song song) => !song.hasAudio || song.isFullTrack || song.isPreview;

  Widget _buildInlineBadge(Song song) {
    if (!song.hasAudio) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
        decoration: BoxDecoration(
          color: AppTheme.accentPink.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: AppTheme.accentPink.withValues(alpha: 0.4),
            width: 1,
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 7,
              height: 7,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: AppTheme.accentPink,
              ),
            ),
            SizedBox(width: 4),
            Text(
              'LOCATING AUDIO',
              style: TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.4,
                color: AppTheme.accentPink,
              ),
            ),
          ],
        ),
      );
    }

    if (song.isFullTrack) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
        decoration: BoxDecoration(
          color: AppTheme.accentGreen.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: AppTheme.accentGreen.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
        child: const Text(
          'FULL TRACK',
          style: TextStyle(
            fontSize: 8.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
            color: AppTheme.accentGreen,
          ),
        ),
      );
    }

    if (song.isPreview) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: Colors.amber.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
        child: const Text(
          'PREVIEW',
          style: TextStyle(
            fontSize: 8.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
            color: Colors.amber,
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
