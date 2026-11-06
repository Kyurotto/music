import 'package:flutter/material.dart';
import '../models/song_model.dart';
import '../theme/app_theme.dart';
import 'song_artwork_widget.dart';

class AlbumCard extends StatefulWidget {
  final MusicPlaylist playlist;
  final VoidCallback onPlay;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final bool isSelected;

  const AlbumCard({
    super.key,
    required this.playlist,
    required this.onPlay,
    required this.onTap,
    this.onDelete,
    this.isSelected = false,
  });

  @override
  State<AlbumCard> createState() => _AlbumCardState();
}

class _AlbumCardState extends State<AlbumCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final active = _isHovered || widget.isSelected;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          transform: Matrix4.translationValues(0.0, active ? -4.0 : 0.0, 0.0),
          width: 175,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: active ? AppTheme.cardSurfaceHover : AppTheme.cardSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.isSelected
                  ? AppTheme.primary
                  : (_isHovered ? AppTheme.borderActive : AppTheme.border),
              width: widget.isSelected ? 2 : 1,
            ),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: (widget.isSelected ? AppTheme.primary : widget.playlist.gradient.first)
                          .withValues(alpha: widget.isSelected ? 0.35 : 0.25),
                      blurRadius: widget.isSelected ? 20 : 16,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : [],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Artwork container with gradient
              AspectRatio(
                aspectRatio: 1.0,
                child: Stack(
                  children: [
                    SongArtworkWidget(
                      imageUrl: widget.playlist.imageUrl,
                      title: widget.playlist.title,
                      artist: widget.playlist.subtitle,
                      gradientColors: widget.playlist.gradient,
                      borderRadius: 12,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                    if (widget.onDelete != null)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Material(
                          color: Colors.black.withValues(alpha: active ? 0.85 : 0.6),
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: widget.onDelete,
                            child: const Padding(
                              padding: EdgeInsets.all(6),
                              child: Icon(
                                Icons.delete_outline_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                      ),
                    // Floating play button on hover or when selected
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 200),
                      right: 8,
                      bottom: active ? 8 : -40,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: active ? 1.0 : 0.0,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: AppTheme.primaryGradient,
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primary.withValues(alpha: 0.5),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24),
                            onPressed: widget.onPlay,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Title
              Text(
                widget.playlist.title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),

              // Subtitle
              Text(
                widget.playlist.subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: widget.isSelected ? AppTheme.primary : AppTheme.textMuted,
                  fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
