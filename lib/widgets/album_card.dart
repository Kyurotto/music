import 'package:flutter/material.dart';
import '../models/song_model.dart';
import '../theme/app_theme.dart';

class AlbumCard extends StatefulWidget {
  final PlaylistCategory playlist;
  final VoidCallback onPlay;
  final VoidCallback onTap;

  const AlbumCard({
    super.key,
    required this.playlist,
    required this.onPlay,
    required this.onTap,
  });

  @override
  State<AlbumCard> createState() => _AlbumCardState();
}

class _AlbumCardState extends State<AlbumCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          transform: Matrix4.translationValues(0.0, _isHovered ? -4.0 : 0.0, 0.0),
          width: 175,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _isHovered ? AppTheme.cardSurfaceHover : AppTheme.cardSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _isHovered ? AppTheme.borderActive : AppTheme.border,
              width: 1,
            ),
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: widget.playlist.gradient.first.withValues(alpha: 0.25),
                      blurRadius: 16,
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
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: LinearGradient(
                          colors: widget.playlist.gradient,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.album_rounded,
                          size: 54,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ),
                    // Floating play button on hover or always accessible
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 200),
                      right: 8,
                      bottom: _isHovered ? 8 : -40,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: _isHovered ? 1.0 : 0.0,
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
      ),
    );
  }
}
