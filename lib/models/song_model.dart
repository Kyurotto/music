import 'package:flutter/material.dart';

class Song {
  final String id;
  final String title;
  final String artist;
  final String album;
  final Duration duration;
  final String genre;
  final String imageUrl;
  final List<Color> gradientColors;
  final String plays;
  final List<String> lyrics;
  final bool isFeatured;
  bool isLiked;

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
    this.isFeatured = false,
    this.isLiked = false,
  });

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
}

class PlaylistCategory {
  final String id;
  final String title;
  final String subtitle;
  final String coverUrl;
  final List<Color> gradient;
  final int trackCount;

  const PlaylistCategory({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.coverUrl,
    required this.gradient,
    required this.trackCount,
  });
}

class SampleMusicData {
  static List<Song> get sampleSongs => [];

  static List<PlaylistCategory> get playlists => const [];

  static List<String> get genres => const [
        'All',
      ];
}
