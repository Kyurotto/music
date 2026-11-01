import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../data/local_database.dart';
import '../models/song_model.dart';

/// A dashboard row that is filled automatically (no playlist import needed).
class DiscoverySection {
  const DiscoverySection({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.songs,
    this.openable = false,
  });

  final String id;
  final String title;
  final String subtitle;
  final List<Song> songs;

  /// True when tapping the section header opens a playlist-style list page.
  final bool openable;
}

/// Fetches dashboard discovery rows from Apple's keyless public catalog:
/// - iTunes Search API   (quick picks, covers & remixes, long listens)
/// - iTunes Lookup API   (adds preview URLs to chart results)
/// - Apple RSS charts    (trending for you, community favorites)
///
/// Every section fails soft: a network error yields an empty section that
/// the UI simply hides, so the dashboard never breaks offline.
///
/// Songs are created with the `spotify-itunes-<trackId>` id. That is the same
/// id the app's iTunes artist import produces, so the player treats them like
/// imported tracks: the 30s preview that ships with the catalog result starts
/// instantly, and the controller then resolves and hot-swaps the full-length
/// track (with its retry paths, lyrics and offline cache). Discovery songs are
/// never added to the saved library or the database.
class DiscoveryService {
  DiscoveryService({
    http.Client? client,
    Random? random,
    this.country = 'ph',
    this.persist = false,
  })  : _client = client ?? http.Client(),
        _random = random ?? Random();

  /// Shared singleton instance used across the app.
  static final DiscoveryService instance = DiscoveryService(persist: true);

  /// When true, every loaded row is also saved locally so the next app start
  /// can paint the dashboard instantly (see [loadSaved]).
  final bool persist;

  /// Display order of the rows.
  static const List<String> sectionOrder = [
    'quick',
    'covers',
    'long',
    'community',
    'trending',
  ];

  /// Two-letter storefront used for search and the "trending for you" chart.
  final String country;

  final http.Client _client;
  final Random _random;

  static const _cacheTtl = Duration(minutes: 5);
  static const _timeout = Duration(seconds: 4);
  static const _userAgent = 'Mozilla/5.0 (compatible; MusicApp/1.0)';

  /// A track counts as a "long listen" from this length.
  static const longListenMinimum = Duration(minutes: 6);

  /// Section key -> (title, subtitle).
  static const Map<String, (String, String)> _titles = {
    'quick': ('Quick Picks', 'Songs picked for you, no import needed'),
    'covers': ('Covers & Remixes', 'Fresh takes on songs you know'),
    'long': ('Long Listens', 'Extended mixes and epic tracks, 6+ minutes'),
    'community': ('Community Favorites', 'What listeners are playing right now'),
    'trending': ('Trending For You', 'Top songs trending in your region'),
  };

  /// Sections whose header opens a playlist-style list page.
  static const Set<String> _openableKeys = {'community', 'trending'};

  static final Map<String, _CacheEntry> _cache = {};

  /// Clears the shared in-memory cache. Intended for tests.
  static void clearCache() => _cache.clear();

  void dispose() => _client.close();

  /// Loads every section in parallel. Empty sections are omitted.
  /// When [forceRefresh] is true, cache is cleared to fetch fresh results immediately.
  ///
  /// [onSection] is called for each non-empty row the moment it is ready, so
  /// the UI can show fast rows immediately instead of waiting for the slowest.
  Future<List<DiscoverySection>> loadAll({
    bool forceRefresh = false,
    void Function(DiscoverySection section)? onSection,
  }) async {
    if (forceRefresh) {
      clearCache();
    }
    Future<DiscoverySection> ready(Future<DiscoverySection> pending) =>
        pending.then((section) {
          if (section.songs.isNotEmpty) {
            try {
              onSection?.call(section);
            } catch (_) {}
          }
          return section;
        });

    final sections = await Future.wait([
      ready(_cached('quick', _quickPicks)),
      ready(_cached('covers', _coversAndRemixes)),
      ready(_cached('long', _longListens)),
      ready(_cached('community', () => _chartSection('community', 'us', 25))),
      ready(_cached('trending', () => _chartSection('trending', country, 25))),
    ]);
    return sections.where((s) => s.songs.isNotEmpty).toList();
  }

  /// The rows saved by the previous run (no network). Empty when nothing was
  /// saved yet or [persist] is off.
  Future<List<DiscoverySection>> loadSaved() async {
    if (!persist) return const [];
    final loaded = await Future.wait(sectionOrder.map(_loadSavedSection));
    return loaded.whereType<DiscoverySection>().toList();
  }

  String _savedKey(String key) => 'discovery_saved_v1:$country:$key';

  Future<DiscoverySection?> _loadSavedSection(String key) async {
    try {
      final raw = await LocalDatabase.instance.getSetting(_savedKey(key));
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      final songs = <Song>[];
      for (final item in decoded.whereType<Map>()) {
        final song = _songFromJson(Map<String, dynamic>.from(item));
        if (song != null) songs.add(song);
      }
      return songs.isEmpty ? null : _sectionFromSongs(key, songs);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveSection(String key, DiscoverySection section) async {
    try {
      final payload = jsonEncode([for (final s in section.songs) _songToJson(s)]);
      await LocalDatabase.instance.setSetting(_savedKey(key), payload);
    } catch (_) {}
  }

  static Map<String, Object> _songToJson(Song s) => {
        'id': s.id,
        'title': s.title,
        'artist': s.artist,
        'album': s.album,
        'ms': s.duration.inMilliseconds,
        'art': s.imageUrl,
        'preview': '',
      };

  static Song? _songFromJson(Map<String, dynamic> j) {
    final id = j['id'];
    final title = j['title'];
    if (id is! String || title is! String || title.isEmpty) return null;
    final artist = (j['artist'] as String?) ?? '';
    final ms = j['ms'];
    return Song(
      id: id,
      title: title,
      artist: artist,
      album: (j['album'] as String?) ?? '',
      duration: ms is int && ms > 0
          ? Duration(milliseconds: ms)
          : const Duration(minutes: 3),
      genre: 'Discover',
      imageUrl: (j['art'] as String?) ?? '',
      gradientColors: _gradientFor('$title$artist'),
      plays: '',
      lyrics: <String>[],
      audioUrl: '',
      isPreview: false,
    );
  }

  // ---------------------------------------------------------------------------
  // Section builders
  // ---------------------------------------------------------------------------

  Future<DiscoverySection> _quickPicks() async {
    const terms = ['hits', 'pop', 'acoustic'];
    final batches = await Future.wait(
      terms.map((term) => _itunesSearch(term, limit: 12)),
    );
    final tracks = _dedupe(batches.expand((b) => b)).toList()
      ..shuffle(_random);
    return _section('quick', tracks.take(12));
  }

  Future<DiscoverySection> _coversAndRemixes() async {
    final batches = await Future.wait(
      ['cover', 'remix'].map((term) => _itunesSearch(term, limit: 25)),
    );
    final coverOrRemix = RegExp(r'\b(cover|covers|remix|remixed|rmx)\b', caseSensitive: false);
    final tracks = _dedupe(
      batches
          .expand((b) => b)
          .where((t) => coverOrRemix.hasMatch('${t.title} ${t.album}')),
    ).toList()
      ..shuffle(_random);
    return _section('covers', tracks.take(15));
  }

  /// Extended mixes, ambient, classical and live recordings, keeping only
  /// tracks that really run [longListenMinimum] or longer.
  Future<DiscoverySection> _longListens() async {
    const terms = ['extended mix', 'ambient', 'classical'];
    final batches = await Future.wait(
      terms.map((term) => _itunesSearch(term, limit: 25)),
    );
    final tracks = _dedupe(
      batches
          .expand((b) => b)
          .where((t) => t.durationMs >= longListenMinimum.inMilliseconds),
    ).toList()
      ..shuffle(_random);
    return _section('long', tracks.take(15));
  }

  Future<DiscoverySection> _chartSection(String key, String cc, int limit) async {
    final tracks = await _chartTracks(cc, limit);
    return _section(key, tracks);
  }

  // ---------------------------------------------------------------------------
  // Network helpers
  // ---------------------------------------------------------------------------

  Future<List<_Track>> _itunesSearch(String term, {int limit = 25}) async {
    final uri = Uri.https('itunes.apple.com', '/search', {
      'term': term,
      'media': 'music',
      'entity': 'song',
      'country': country,
      'limit': '$limit',
    });
    final json = await _getJson(uri);
    return _parseTracks(json?['results']);
  }

  /// Apple RSS chart (ordered, IDs only) -> one Lookup call for previews.
  Future<List<_Track>> _chartTracks(String cc, int limit) async {
    final rss = await _getJson(Uri.parse(
      'https://rss.applemarketingtools.com/api/v2/$cc/music/most-played/$limit/songs.json',
    ));
    final feed = rss?['feed'];
    final results = feed is Map ? feed['results'] : null;
    if (results is! List) return const [];

    final ids = results
        .whereType<Map>()
        .map((r) => r['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
    if (ids.isEmpty) return const [];

    final lookup = await _getJson(Uri.https('itunes.apple.com', '/lookup', {
      'id': ids.join(','),
      'country': cc,
    }));
    final byId = {for (final t in _parseTracks(lookup?['results'])) t.trackId: t};

    // Keep chart order.
    final ordered = <_Track>[];
    for (final id in ids) {
      final parsed = int.tryParse(id);
      final track = parsed == null ? null : byId[parsed];
      if (track != null) ordered.add(track);
    }
    return ordered;
  }

  Future<Map<String, dynamic>?> _getJson(Uri uri) async {
    try {
      final response = await _client
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(_timeout);
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Future<DiscoverySection> _cached(
    String key,
    Future<DiscoverySection> Function() build,
  ) async {
    final cacheKey = '$country:$key';
    final hit = _cache[cacheKey];
    if (hit != null && DateTime.now().difference(hit.at) < _cacheTtl) {
      return hit.section;
    }
    try {
      final section = await build();
      if (section.songs.isNotEmpty) {
        _cache[cacheKey] = _CacheEntry(section, DateTime.now());
        if (persist) unawaited(_saveSection(key, section));
      }
      return section;
    } catch (_) {
      return _section(key, const []);
    }
  }

  // ---------------------------------------------------------------------------
  // Parsing and mapping
  // ---------------------------------------------------------------------------

  static List<_Track> _parseTracks(Object? results) {
    if (results is! List) return const [];
    final out = <_Track>[];
    for (final item in results) {
      if (item is! Map) continue;
      if (item['wrapperType'] != 'track') continue;
      final id = item['trackId'];
      final title = (item['trackName'] as String?)?.trim() ?? '';
      if (id is! int || title.isEmpty) continue;
      final millis = item['trackTimeMillis'];
      out.add(_Track(
        trackId: id,
        title: title,
        artist: (item['artistName'] as String?)?.trim() ?? '',
        album: (item['collectionName'] as String?)?.trim() ?? '',
        artworkUrl: _hiRes(item['artworkUrl100'] as String?),
        previewUrl: (item['previewUrl'] as String?) ?? '',
        durationMs: millis is int ? millis : 0,
      ));
    }
    return out;
  }

  DiscoverySection _section(String key, Iterable<_Track> tracks) =>
      _sectionFromSongs(key, tracks.map((t) => t.toSong()).toList());

  DiscoverySection _sectionFromSongs(String key, List<Song> songs) {
    final meta = _titles[key]!;
    return DiscoverySection(
      id: key,
      title: meta.$1,
      subtitle: meta.$2,
      songs: songs,
      openable: _openableKeys.contains(key),
    );
  }

  static Iterable<_Track> _dedupe(Iterable<_Track> tracks) {
    final seenIds = <int>{};
    final seenKeys = <String>{};
    return tracks.where((t) {
      if (!seenIds.add(t.trackId)) return false;
      final key = '${t.title.trim().toLowerCase()}|${t.artist.trim().toLowerCase()}';
      return seenKeys.add(key);
    });
  }

  static String _hiRes(String? url) {
    if (url == null || url.isEmpty) return '';
    return url.replaceFirst('100x100bb', '600x600bb');
  }

  static const _palettes = <List<Color>>[
    [Color(0xFF6A4CFF), Color(0xFF1E1E2E)],
    [Color(0xFFFF5F6D), Color(0xFF2B1055)],
    [Color(0xFF11998E), Color(0xFF1B2735)],
    [Color(0xFFF7971E), Color(0xFF3A1C71)],
  ];

  static List<Color> _gradientFor(String seed) =>
      _palettes[seed.hashCode.abs() % _palettes.length];
}

typedef _Track = DiscoveryTrack;

class DiscoveryTrack {
  const DiscoveryTrack({
    required this.trackId,
    required this.title,
    required this.artist,
    required this.album,
    required this.artworkUrl,
    required this.previewUrl,
    required this.durationMs,
  });

  final int trackId;
  final String title;
  final String artist;
  final String album;
  final String artworkUrl;
  final String previewUrl;
  final int durationMs;

  /// `spotify-itunes-<trackId>` is the id the iTunes artist import already
  /// uses, so the player gives these songs the full imported-track treatment
  /// (full-length resolve, retries, lyrics, offline cache) without them ever
  /// being saved to the library.
  Song toSong() => Song(
        id: 'spotify-itunes-$trackId',
        title: title,
        artist: artist,
        album: album,
        duration: durationMs > 0
            ? Duration(milliseconds: durationMs)
            : const Duration(minutes: 3),
        genre: 'Discover',
        imageUrl: artworkUrl,
        gradientColors: DiscoveryService._gradientFor('$title$artist'),
        plays: '',
        lyrics: <String>[],
        // Do not default to the 30s preview clip. Songs will resolve
        // full track audio (YouTube, SoundCloud, Saavn, Archive.org).
        audioUrl: '',
        isPreview: false,
      );
}

class _CacheEntry {
  const _CacheEntry(this.section, this.at);

  final DiscoverySection section;
  final DateTime at;
}