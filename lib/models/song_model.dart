import 'package:flutter/material.dart';

class Song {
  final String id;
  final String title;
  final String artist;
  final String album;

  /// Mutable so a resolved full-length stream can correct the Spotify
  /// metadata duration (or a 30s clip can report its real length).
  Duration duration;
  final String genre;
  String imageUrl;
  final List<Color> gradientColors;
  final String plays;
  List<String> lyrics;
  String audioUrl;
  final bool isFeatured;
  bool isLiked;
  bool isPreview;

  /// True when audio comes from YouTube (URLs expire after a few hours —
  /// the player resolves a fresh one when a saved URL fails to load).
  bool isYouTubeAudio;
  bool isEnrichingLyrics;

  Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.genre,
    required this.imageUrl,
    required this.gradientColors,
    required this.plays,
    required this.lyrics,
    this.audioUrl = '',
    this.isFeatured = false,
    this.isLiked = false,
    this.isPreview = false,
    this.isYouTubeAudio = false,
    this.isEnrichingLyrics = false,
  });

  /// True when this song can actually produce sound (local asset or URL).
  bool get hasAudio => audioUrl.isNotEmpty;

  /// Imported Spotify metadata starts silent — only true until enrichment
  /// resolves a playable preview URL.
  bool get isSilentPlaceholder => id.startsWith('spotify-') && !hasAudio;

  /// True when an imported track resolved to a full-length stream
  /// (not a 30-second preview clip).
  bool get isFullTrack =>
      id.startsWith('spotify-') && hasAudio && !isPreview;

  String get formattedDuration {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  static String formatTime(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  static Duration? parseLyricTimestamp(String line) {
    final trimmed = line.trim();
    final match = RegExp(r'^\[(\d+):(\d+)(?:[.:](\d+))?\]').firstMatch(trimmed);
    if (match != null) {
      final min = int.parse(match.group(1)!);
      final sec = int.parse(match.group(2)!);
      final frac = match.group(3);
      int millis = 0;
      if (frac != null && frac.isNotEmpty) {
        if (frac.length == 1) {
          millis = int.parse(frac) * 100;
        } else if (frac.length == 2) {
          millis = int.parse(frac) * 10;
        } else {
          millis = int.parse(frac.substring(0, 3));
        }
      }
      return Duration(milliseconds: min * 60000 + sec * 1000 + millis);
    }
    final alt = RegExp(r'^\[(\d+):(\d+\.?\d*)\]').firstMatch(trimmed);
    if (alt != null) {
      final min = int.parse(alt.group(1)!);
      final sec = double.parse(alt.group(2)!);
      return Duration(milliseconds: (min * 60000 + sec * 1000).round());
    }
    return null;
  }

  static String stripTimestamp(String line) {
    return line.replaceAll(RegExp(r'^\s*\[.*?\]'), '').trim();
  }

  /// Which lyric line should be active for this playback position.
  ///
  /// Uses synced timestamps if available. Otherwise, plain (untimed) lyric 
  /// lines are spread evenly across the track.
  static int lyricsLineIndexForProgress(
    List<String> lyrics,
    Duration position,
    Duration total,
  ) {
    if (lyrics.isEmpty) return 0;
    final effectiveTotal =
        total > Duration.zero ? total : const Duration(minutes: 3);

    final hasTimestamped = lyrics.any((l) => parseLyricTimestamp(l) != null);
    if (hasTimestamped) {
      int lastIndex = -1;
      for (int i = 0; i < lyrics.length; i++) {
        final time = parseLyricTimestamp(lyrics[i]);
        if (time != null) {
          if (position >= time) {
            lastIndex = i;
          } else {
            break;
          }
        }
      }
      if (lastIndex >= 0) return lastIndex;
      final firstIdx = lyrics.indexWhere((l) => parseLyricTimestamp(l) != null);
      return firstIdx >= 0 ? firstIdx : 0;
    }

    final posUs = position.inMicroseconds;
    final totalUs = effectiveTotal.inMicroseconds;
    if (posUs <= 0 || totalUs <= 0) return 0;
    final progress = posUs / totalUs;
    if (progress >= 1) return lyrics.length - 1;
    final idx = (progress * lyrics.length).floor();
    if (idx < 0) return 0;
    if (idx >= lyrics.length) return lyrics.length - 1;
    return idx;
  }

  /// Playback position for a tapped lyric line (inverse of
  /// [lyricsLineIndexForProgress]) so tapping a line seeks the player.
  static Duration positionForLyricsLine(
    List<String> lyrics,
    int lineIndex,
    Duration total,
  ) {
    if (lyrics.isEmpty) return Duration.zero;
    final effectiveTotal =
        total > Duration.zero ? total : const Duration(minutes: 3);
    final clamped = lineIndex.clamp(0, lyrics.length - 1).toInt();

    final time = parseLyricTimestamp(lyrics[clamped]);
    if (time != null) return time;

    final micros = (effectiveTotal.inMicroseconds * clamped) ~/ lyrics.length;
    return Duration(microseconds: micros);
  }
}

class MusicPlaylist {
  final String id;
  final String title;
  final String subtitle;
  final List<Color> gradient;
  final List<String> songIds;
  String imageUrl;

  MusicPlaylist({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.gradient,
    List<String>? songIds,
    this.imageUrl = '',
  }) : songIds = songIds ?? [];

  int get trackCount => songIds.length;
}

class SampleMusicData {
  /// No pre-loaded sample songs — the app starts with an empty library.
  static List<Song> get sampleSongs => [];

  /// No pre-loaded artist playlists.
  static List<MusicPlaylist> get initialPlaylists => [];

  static List<MusicPlaylist> get playlists => initialPlaylists;

  static List<String> get genres => const ['All', 'Pop', 'Hip-Hop', 'Acoustic', 'Funk'];
}
