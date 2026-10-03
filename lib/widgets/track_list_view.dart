import 'package:flutter/material.dart';
import '../models/song_model.dart';
import '../theme/app_theme.dart';
import '../controllers/music_player_controller.dart';
import 'animated_visualizer.dart';

class TrackListView extends StatelessWidget {
  final List<Song> songs;
  final MusicPlayerController controller;
  final ValueChanged<Song>? onAddToPlaylist;
  final ValueChanged<Song>? onSongTap;
  final String? emptyTitle;
  final String? emptySubtitle;

  const TrackListView({
    super.key,
    required this.songs,
    required this.controller,
    this.onAddToPlaylist,
    this.onSongTap,
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
              style: TextStyle(
                  fontSize: 16,
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              emptySubtitle ?? 'Try changing your search query or genre filter',
              style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
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
            // Table Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  SizedBox(
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
                  Expanded(
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
                    Expanded(
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
                    SizedBox(
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
                  SizedBox(
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
                  const SizedBox(width: 36),
                ],
              ),
            ),
            const Divider(height: 1),

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
                // Track number or play indicator
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
                            ? Icon(Icons.play_arrow_rounded,
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

                // Artwork Thumbnail
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: AppTheme.cardSurfaceHover,
                    border: Border.all(color: AppTheme.border, width: 1),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.music_note_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 14),

                // Title & Artist
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
                      Text(
                        widget.song.artist,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (widget.song.isPreview ||
                          widget.song.isSilentPlaceholder ||
                          widget.song.isFullTrack) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: widget.song.hasAudio
                                      ? AppTheme.accentGreen
                                          .withValues(alpha: 0.15)
                                      : AppTheme.accentPink
                                          .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: widget.song.hasAudio
                                        ? AppTheme.accentGreen
                                            .withValues(alpha: 0.4)
                                        : AppTheme.accentPink
                                            .withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Text(
                                  widget.song.isFullTrack
                                      ? 'FULL TRACK'
                                      : widget.song.hasAudio
                                          ? 'PREVIEW'
                                          : 'LOCATING AUDIO',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  softWrap: false,
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.6,
                                    color: widget.song.hasAudio
                                        ? AppTheme.accentGreen
                                        : AppTheme.accentPink,
                                  ),
                                ),
                              ),
                            ),
                            if (widget.song.lyrics.isEmpty) ...[
                              const SizedBox(width: 6),
                              Icon(
                                Icons.lyrics_outlined,
                                size: 13,
                                color: AppTheme.textMuted,
                              ),
                            ],
                          ],
                        ),
                      ],
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
                        style: TextStyle(
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
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textMuted,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),

                // Duration
                SizedBox(
                  width: 70,
                  child: Text(
                    widget.song.formattedDuration,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textMuted,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),

                // Action buttons — mainAxisSize.min prevents any overflow
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: widget.onLikeToggle,
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
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
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(
                            Icons.playlist_add_rounded,
                            size: 19,
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
}
