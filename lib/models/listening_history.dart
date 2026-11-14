/// One completed or partially played track session.
///
/// The row is written when audio actually starts and updated when playback
/// stops (skip, pause, completion or app dispose). [listenedSeconds] is the
/// time the listener actually heard the track, not the track length.
class ListeningHistoryEntry {
  const ListeningHistoryEntry({
    this.id,
    required this.songId,
    required this.title,
    required this.artist,
    required this.album,
    required this.imageUrl,
    required this.startedAt,
    required this.listenedSeconds,
    required this.completed,
  });

  final int? id;
  final String songId;
  final String title;
  final String artist;
  final String album;
  final String imageUrl;
  final DateTime startedAt;
  final int listenedSeconds;
  final bool completed;

  Duration get listenedDuration => Duration(seconds: listenedSeconds);

  factory ListeningHistoryEntry.fromMap(Map<String, Object?> map) {
    final rawStartedAt = map['started_at'];
    final startedAtMs = rawStartedAt is int
        ? rawStartedAt
        : int.tryParse('$rawStartedAt') ?? 0;
    return ListeningHistoryEntry(
      id: map['id'] as int?,
      songId: map['song_id'] as String? ?? '',
      title: map['title'] as String? ?? '',
      artist: map['artist'] as String? ?? '',
      album: map['album'] as String? ?? '',
      imageUrl: map['image_url'] as String? ?? '',
      startedAt: DateTime.fromMillisecondsSinceEpoch(startedAtMs),
      listenedSeconds: (map['listened_seconds'] as int?) ?? 0,
      completed: ((map['completed'] as int?) ?? 0) == 1,
    );
  }
}

/// A song or artist ranked by play count for the Listening Stats screen.
class ListeningRankedItem {
  const ListeningRankedItem({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.plays,
    required this.listenedSeconds,
  });

  final String key;
  final String title;
  final String subtitle;
  final String imageUrl;
  final int plays;
  final int listenedSeconds;

  Duration get listenedDuration => Duration(seconds: listenedSeconds);
}

/// Aggregated listening figures for the current account.
class ListeningStats {
  const ListeningStats({
    required this.totalPlays,
    required this.totalListenedSeconds,
    required this.uniqueSongs,
    required this.uniqueArtists,
    required this.completedPlays,
    required this.topSongs,
    required this.topArtists,
  });

  final int totalPlays;
  final int totalListenedSeconds;
  final int uniqueSongs;
  final int uniqueArtists;
  final int completedPlays;
  final List<ListeningRankedItem> topSongs;
  final List<ListeningRankedItem> topArtists;

  static const empty = ListeningStats(
    totalPlays: 0,
    totalListenedSeconds: 0,
    uniqueSongs: 0,
    uniqueArtists: 0,
    completedPlays: 0,
    topSongs: [],
    topArtists: [],
  );

  Duration get totalListened => Duration(seconds: totalListenedSeconds);

  int get averageListenedSeconds =>
      totalPlays == 0 ? 0 : totalListenedSeconds ~/ totalPlays;
}
