import 'dart:io';
import 'package:flutter/material.dart';
import '../models/song_model.dart';
import '../theme/app_theme.dart';

/// Renders an authentic album cover art image icon for every song, just like Spotify.
///
/// If an [imageUrl] (or [song.imageUrl]) is present, it loads the real album art
/// (network URL, local cached file, or asset). If missing or offline, it renders
/// a procedural Spotify-style studio cover with unique gradient tones, subtle
/// vinyl grooves, and soundwave pulse accents tailored to the song.
class SongArtworkWidget extends StatelessWidget {
  final Song? song;
  final String? imageUrl;
  final String? title;
  final String? artist;
  final List<Color>? gradientColors;
  final double? size;
  final double? width;
  final double? height;
  final double borderRadius;
  final bool isCircle;
  final bool showGlow;
  final BoxFit fit;
  final BoxBorder? border;

  const SongArtworkWidget({
    super.key,
    this.song,
    this.imageUrl,
    this.title,
    this.artist,
    this.gradientColors,
    this.size = 44.0,
    this.width,
    this.height,
    this.borderRadius = 8.0,
    this.isCircle = false,
    this.showGlow = false,
    this.fit = BoxFit.cover,
    this.border,
  });

  String get _effectiveImageUrl => (imageUrl ?? song?.imageUrl ?? '').trim();
  String get _effectiveTitle => (title ?? song?.title ?? '').trim();
  String get _effectiveArtist => (artist ?? song?.artist ?? '').trim();

  List<Color> get _effectiveColors {
    if (gradientColors != null && gradientColors!.length >= 2) {
      return gradientColors!;
    }
    if (song != null && song!.gradientColors.length >= 2) {
      return song!.gradientColors;
    }
    return _generatePalette(_effectiveTitle, _effectiveArtist);
  }

  static const List<List<Color>> _spotifyPalettes = [
    [Color(0xFF1DB954), Color(0xFF121212)], // Spotify Iconic Green / Dark
    [Color(0xFF8B5CF6), Color(0xFF3B82F6)], // Electric Violet / Blue
    [Color(0xFFEC4899), Color(0xFF8B5CF6)], // Pink Fuchsia / Violet
    [Color(0xFFF59E0B), Color(0xFFDC2626)], // Warm Amber / Crimson
    [Color(0xFF06B6D4), Color(0xFF3B82F6)], // Cyan / Indigo
    [Color(0xFF10B981), Color(0xFF047857)], // Emerald Studio
    [Color(0xFF6366F1), Color(0xFF1E1B4B)], // Midnight Indigo
    [Color(0xFFE11D48), Color(0xFF4C0519)], // Deep Ruby / Velvet
    [Color(0xFFD97706), Color(0xFF78350F)], // Warm Bronze / Mahogany
    [Color(0xFF0284C7), Color(0xFF082F49)], // Deep Ocean
  ];

  static List<Color> _generatePalette(String title, String artist) {
    if (title.isEmpty && artist.isEmpty) {
      return const [Color(0xFF2E2E38), Color(0xFF121214)];
    }
    final combined = '$title|$artist'.toLowerCase();
    var hash = 0;
    for (int i = 0; i < combined.length; i++) {
      hash = (hash * 31 + combined.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    return _spotifyPalettes[hash % _spotifyPalettes.length];
  }

  @override
  Widget build(BuildContext context) {
    final w = width ?? size ?? 44.0;
    final h = height ?? size ?? 44.0;
    final rawUrl = _effectiveImageUrl;
    final colors = _effectiveColors;

    Widget content;
    if (rawUrl.isNotEmpty) {
      content = _buildImageWithFallback(rawUrl, colors, w, h);
    } else {
      content = _buildSpotifyProceduralArt(colors, w, h);
    }

    final shapeBorderRadius = isCircle ? BorderRadius.circular(w / 2) : BorderRadius.circular(borderRadius);

    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        borderRadius: isCircle ? null : shapeBorderRadius,
        shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
        border: border,
        boxShadow: showGlow
            ? [
                BoxShadow(
                  color: colors.first.withValues(alpha: 0.35),
                  blurRadius: 16,
                  spreadRadius: 1,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: isCircle ? BorderRadius.circular(w / 2) : shapeBorderRadius,
        child: content,
      ),
    );
  }

  Widget _buildImageWithFallback(String url, List<Color> colors, double w, double h) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return Image.network(
        url,
        width: w,
        height: h,
        fit: fit,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) return child;
          return _buildSpotifyProceduralArt(colors, w, h);
        },
        errorBuilder: (context, error, stackTrace) => _buildSpotifyProceduralArt(colors, w, h),
      );
    }

    if (url.startsWith('assets/') || url.startsWith('asset:/')) {
      final cleanPath = url.replaceFirst('asset:/', 'assets/').replaceFirst(RegExp(r'^/+'), '');
      return Image.asset(
        cleanPath,
        width: w,
        height: h,
        fit: fit,
        errorBuilder: (context, error, stackTrace) => _buildSpotifyProceduralArt(colors, w, h),
      );
    }

    // Local file path
    try {
      final file = File(url);
      if (file.existsSync()) {
        return Image.file(
          file,
          width: w,
          height: h,
          fit: fit,
          errorBuilder: (context, error, stackTrace) => _buildSpotifyProceduralArt(colors, w, h),
        );
      }
    } catch (_) {}

    return _buildSpotifyProceduralArt(colors, w, h);
  }

  Widget _buildSpotifyProceduralArt(List<Color> colors, double w, double h) {
    final initials = _getInitials();
    final isTiny = w < 40;
    final isSmall = w < 60;
    final isMedium = w < 120;

    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colors.first,
            colors.length > 1 ? colors[1] : AppTheme.surface,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Subtle vinyl groove lines
          CustomPaint(
            painter: _VinylGroovePainter(color: Colors.white.withValues(alpha: 0.08)),
          ),

          // Diagonal light sheen
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: h * 0.5,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.14),
                    Colors.white.withValues(alpha: 0.0),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),

          // Central Motif: initials monogram or stylized audio wave
          Center(
            child: isTiny
                ? const Icon(
                    Icons.music_note_rounded,
                    color: Colors.white,
                    size: 18,
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (initials.isNotEmpty) ...[
                        Text(
                          initials,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.95),
                            fontSize: isSmall
                                ? 15
                                : isMedium
                                    ? 24
                                    : 36,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.0,
                            shadows: const [
                              Shadow(
                                color: Colors.black45,
                                blurRadius: 6,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        Icon(
                          Icons.album_rounded,
                          color: Colors.white.withValues(alpha: 0.9),
                          size: isSmall ? 22 : (isMedium ? 40 : 54),
                        ),
                      ],
                      if (!isSmall && _effectiveTitle.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Container(
                          width: w * 0.45,
                          height: 2,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),

          // Small subtle audio wave indicator in bottom corner for Spotify aesthetic
          if (!isTiny)
            Positioned(
              right: 5,
              bottom: 4,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _waveBar(4, isSmall),
                  const SizedBox(width: 1.5),
                  _waveBar(8, isSmall),
                  const SizedBox(width: 1.5),
                  _waveBar(6, isSmall),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _waveBar(double maxHeight, bool isSmall) {
    final scale = isSmall ? 0.7 : 1.0;
    return Container(
      width: 2.0 * scale,
      height: maxHeight * scale,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }

  String _getInitials() {
    final t = _effectiveTitle;
    final a = _effectiveArtist;
    if (t.isEmpty && a.isEmpty) return '';

    if (t.isNotEmpty) {
      final words = t.trim().split(RegExp(r'\s+'));
      if (words.length >= 2 && words[0].isNotEmpty && words[1].isNotEmpty) {
        final f = words[0][0].toUpperCase();
        final s = words[1][0].toUpperCase();
        if (_isAlpha(f) && _isAlpha(s)) return '$f$s';
      }
      if (words[0].isNotEmpty && _isAlpha(words[0][0])) {
        return words[0][0].toUpperCase();
      }
    }
    if (a.isNotEmpty) {
      return a.trim()[0].toUpperCase();
    }
    return '';
  }

  static bool _isAlpha(String ch) {
    return RegExp(r'[A-Za-z0-9]').hasMatch(ch);
  }
}

class _VinylGroovePainter extends CustomPainter {
  final Color color;
  const _VinylGroovePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width * 0.45;
    for (double r = maxRadius * 0.35; r < maxRadius; r += 7.0) {
      canvas.drawCircle(center, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _VinylGroovePainter oldDelegate) =>
      oldDelegate.color != color;
}
