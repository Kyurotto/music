import 'package:flutter/material.dart';
import '../models/song_model.dart';
import '../theme/app_theme.dart';

class AlbumCard extends StatefulWidget {
  final MusicPlaylist playlist;
  final VoidCallback onPlay;
  final VoidCallback onTap;
  final bool isSelected;

  const AlbumCard({
    super.key,
    required this.playlist,
    required this.onPlay,
    required this.onTap,
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
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Artwork container
              AspectRatio(
                aspectRatio: 1.0,
                child: Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: AppTheme.cardSurfaceHover,
                        border: Border.all(color: AppTheme.border, width: 1),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.album_rounded,
                          size: 54,
                          color: AppTheme.textPrimary.withValues(alpha: 0.9),
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
                            color: AppTheme.primary,
                            border: Border.all(color: AppTheme.border, width: 1),
                          ),
                          child: IconButton(
                            icon: Icon(Icons.play_arrow_rounded, color: AppTheme.background, size: 24),
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
                style: TextStyle(
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
