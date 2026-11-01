import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

enum SpotifyLinkType { track, playlist, album, artist }

class SpotifyLink {
  final SpotifyLinkType type;
  final String id;

  const SpotifyLink({required this.type, required this.id});
}

class SpotifyImportedTrack {
  final String spotifyId;
  final String title;
  final String artist;
  final String album;
  final Duration duration;

  /// Optional playable preview resolved at import time (artist top-song
  /// imports via iTunes). Empty for plain Spotify metadata imports, which
  /// get enriched afterwards instead.
  final String previewUrl;
  final String artworkUrl;

  const SpotifyImportedTrack({
    required this.spotifyId,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    this.previewUrl = '',
    this.artworkUrl = '',
  });
}

class SpotifyImportResult {
  final SpotifyLinkType type;
  final String title;
  final String subtitle;
  final List<SpotifyImportedTrack> tracks;
  final String imageUrl;

  const SpotifyImportResult({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.tracks,
    this.imageUrl = '',
  });
}

class SpotifyImportException implements Exception {
  final String message;

  const SpotifyImportException(this.message);

  @override
  String toString() => message;
}

/// Keyless Spotify import: parses track/playlist/album links (URL, intl URL,
/// embed URL, and spotify: URI forms) and reads track metadata from Spotify's
/// public embed page — no API credentials required.
class SpotifyImportService {
  SpotifyImportService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _browserUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  static final RegExp _idPattern = RegExp(r'^[0-9A-Za-z]{22}$');
  static final RegExp _intlPrefixPattern = RegExp(r'^intl-[A-Za-z-]+$');

  /// Parses a Spotify link or URI. Returns null when the input is not a
  /// supported Spotify track/playlist/album link.
  static SpotifyLink? tryParse(String input) {
    final raw = input.trim();
    if (raw.isEmpty) return null;

    if (raw.startsWith('spotify:')) {
      final parts = raw.split(':');
      if (parts.length != 3) return null;
      final type = _typeFrom(parts[1]);
      if (type == null) return null;
      final id = parts[2].trim();
      if (!_idPattern.hasMatch(id)) return null;
      return SpotifyLink(type: type, id: id);
    }

    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasAuthority) return null;

    final host = uri.host.toLowerCase();
    final isSpotifyHost = host == 'open.spotify.com' || host.endsWith('.open.spotify.com');
    if (!isSpotifyHost) return null;

    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    final meaningful = <String>[];
    for (final segment in segments) {
      if (_intlPrefixPattern.hasMatch(segment)) continue;
      meaningful.add(segment);
    }
    if (meaningful.isNotEmpty && meaningful.first == 'embed') {
      meaningful.removeAt(0);
    }
    if (meaningful.length != 2) return null;

    final type = _typeFrom(meaningful[0]);
    if (type == null) return null;

    final id = meaningful[1];
    if (!_idPattern.hasMatch(id)) return null;
    return SpotifyLink(type: type, id: id);
  }

  static SpotifyLinkType? _typeFrom(String value) {
    switch (value.toLowerCase()) {
      case 'track':
        return SpotifyLinkType.track;
      case 'playlist':
        return SpotifyLinkType.playlist;
      case 'album':
        return SpotifyLinkType.album;
      case 'artist':
        return SpotifyLinkType.artist;
      default:
        return null;
    }
  }

  static bool isShortLink(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null || !uri.hasAuthority) return false;
    final host = uri.host.toLowerCase();
    return host == 'spotify.link' || host == 'link.spotify.com';
  }

  /// Full import flow: parse (resolving short links when needed), fetch the
  /// embed page, and return playlist/album tracks or a single track.
  ///
  /// Also accepts Spotify artist links (imported as top songs via a free
  /// catalog lookup) and plain artist names like "Bruno Mars" (anything
  /// that is not a URL is treated as an artist search).
  Future<SpotifyImportResult> importFromLink(String input) {
    // One overall deadline so no single slow step (short-link redirects,
    // embed page, iTunes lookups) can leave the import dialog spinning
    // forever on a weak Wi-Fi or mobile-data connection.
    return _importFromLinkImpl(input).timeout(
      _importDeadline,
      onTimeout: () => throw const SpotifyImportException(
        'Spotify is taking too long to respond. Check your connection and try again.',
      ),
    );
  }

  static const Duration _importDeadline = Duration(seconds: 25);
  static const Duration _requestTimeout = Duration(seconds: 12);

  Future<SpotifyImportResult> _importFromLinkImpl(String input) async {
    if (kIsWeb) {
      throw const SpotifyImportException(
        'Spotify import is not supported on web builds. Use the desktop or mobile app.',
      );
    }

    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw const SpotifyImportException('Paste a Spotify link first.');
    }

    var link = tryParse(trimmed);
    if (link == null && isShortLink(trimmed)) {
      final resolved = await _resolveShortLink(trimmed);
      link = resolved == null ? null : tryParse(resolved);
    }
    if (link == null) {
      if (_looksLikeUrl(trimmed)) {
        throw const SpotifyImportException(
          'That does not look like a Spotify track, playlist, album, or artist link.',
        );
      }
      // Plain text — treat as an artist name search ("Bruno Mars").
      return importArtistTopSongs(artistName: trimmed);
    }

    if (link.type == SpotifyLinkType.artist) {
      try {
        final entity = await _fetchEmbedEntity(link);
        return _resultFromEntity(link, entity);
      } catch (_) {
        // Fall back to oEmbed + top song lookup if embed fetch fails
        return importArtistTopSongs(spotifyId: link.id);
      }
    }

    final entity = await _fetchEmbedEntity(link);
    return _resultFromEntity(link, entity);
  }

  /// True when the input is URL-shaped (so it can never be an artist name).
  static bool _looksLikeUrl(String input) {
    final lowered = input.trim().toLowerCase();
    if (lowered.contains('://') || lowered.startsWith('www.')) return true;
    final uri = Uri.tryParse(input.trim());
    return uri != null && uri.hasAuthority;
  }

  /// Imports an artist's top songs as a playlist.
  ///
  /// Spotify embeds don't support artist pages, so the track list comes
  /// from the free iTunes catalog (which also provides playable previews).
  /// Either a Spotify artist [spotifyId] (name resolved via oEmbed) or a
  /// plain [artistName] like "Bruno Mars" is required.
  Future<SpotifyImportResult> importArtistTopSongs({
    String? spotifyId,
    String? artistName,
    int limit = 50,
  }) async {
    var name = artistName?.trim() ?? '';
    if (name.isEmpty) {
      if (spotifyId == null || spotifyId.isEmpty) {
        throw const SpotifyImportException('Type an artist name first.');
      }
      final resolved = await _resolveArtistNameViaOEmbed(spotifyId);
      if (resolved == null || resolved.isEmpty) {
        throw const SpotifyImportException(
          'Artist links cannot be read directly. Type the artist name instead (e.g. "Bruno Mars").',
        );
      }
      name = resolved;
    }

    final artistId = await _searchITunesArtistId(name);
    if (artistId == null) {
      throw SpotifyImportException('No artist found named "$name".');
    }
    final tracks = await _fetchITunesArtistSongs(
      artistId: artistId,
      artistName: name,
      limit: limit,
    );
    if (tracks.isEmpty) {
      throw SpotifyImportException('No top songs found for "$name".');
    }
    final displayName =
        tracks.first.artist.isNotEmpty ? tracks.first.artist : name;
    final firstArtwork = tracks.isNotEmpty ? tracks.first.artworkUrl : '';
    return SpotifyImportResult(
      type: SpotifyLinkType.artist,
      title: displayName,
      subtitle: 'Top songs · ${tracks.length} tracks',
      tracks: tracks,
      imageUrl: firstArtwork,
    );
  }

  /// Resolves a Spotify artist ID to its display name via Spotify's keyless
  /// oEmbed endpoint. Returns null when unreachable — callers fall back to
  /// asking the user to type the name.
  Future<String?> _resolveArtistNameViaOEmbed(String spotifyId) async {
    final pageUrl = 'https://open.spotify.com/artist/$spotifyId';
    final uri = Uri.https('embed.spotify.com', '/oembed', {'url': pageUrl});
    try {
      final response = await _client
          .get(uri, headers: {'User-Agent': _browserUserAgent}).timeout(
                const Duration(seconds: 8),
              );
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
      if (decoded is! Map) return null;
      final title = decoded['title'];
      if (title is! String || title.trim().isEmpty) return null;
      return title.trim();
    } catch (_) {
      return null;
    }
  }

  /// Finds the iTunes artist ID whose name best matches [name].
  Future<int?> _searchITunesArtistId(String name) async {
    // 1. First search songs by this term. Count which artistId appears most
    // frequently among songs whose artistName matches [name]. This guarantees
    // we pick the famous/popular artist (e.g. OPM Adie with Paraluman/Mahika)
    // rather than an obscure artist who happens to share the same name.
    final songSearchUri = Uri.https('itunes.apple.com', '/search', {
      'term': _cleanArtistQuery(name),
      'media': 'music',
      'entity': 'song',
      'limit': '25',
    });
    final songDecoded = await _getJson(songSearchUri);
    final songResults = songDecoded?['results'];
    if (songResults is List && songResults.isNotEmpty) {
      final counts = <int, int>{};
      for (final item in songResults) {
        if (item is! Map) continue;
        final id = item['artistId'];
        if (id is! int) continue;
        final aName = (item['artistName']?.toString() ?? '').trim();
        if (matchesArtist(aName, name)) {
          counts[id] = (counts[id] ?? 0) + 1;
        }
      }
      if (counts.isNotEmpty) {
        int? topId;
        var topCount = -1;
        for (final entry in counts.entries) {
          if (entry.value > topCount) {
            topCount = entry.value;
            topId = entry.key;
          }
        }
        if (topId != null) return topId;
      }
    }

    // 2. Fall back to standard artist search
    final uri = Uri.https('itunes.apple.com', '/search', {
      'term': _cleanArtistQuery(name),
      'media': 'music',
      'entity': 'musicArtist',
      'limit': '10',
    });
    Map<String, dynamic>? decoded = await _getJson(uri);
    var results = decoded?['results'];
    if (results is! List || results.isEmpty) return null;

    final want = _normalizeName(name);
    int? fallbackId;
    var bestScore = -1;
    int? bestId;
    for (final item in results) {
      if (item is! Map) continue;
      final id = item['artistId'];
      if (id is! int) continue;
      fallbackId ??= id;
      final hitName = _normalizeName(item['artistName']?.toString() ?? '');
      if (hitName.isEmpty || want.isEmpty) continue;
      var score = 0;
      if (hitName == want) {
        score = 3;
      } else if (matchesArtist(item['artistName']?.toString() ?? '', name)) {
        score = 2;
      } else if (hitName.contains(want) || want.contains(hitName)) {
        score = 1;
      } else {
        continue;
      }
      if (score > bestScore) {
        bestScore = score;
        bestId = id;
      }
    }
    return bestId ?? fallbackId;
  }

  /// Fetches an artist's songs (iTunes `lookup`, most popular first) and
  /// maps them to importable tracks with previews baked in.
  Future<List<SpotifyImportedTrack>> _fetchITunesArtistSongs({
    required int artistId,
    required String artistName,
    required int limit,
  }) async {
    final clamped = limit.clamp(5, 200);
    final uri = Uri.https('itunes.apple.com', '/lookup', {
      'id': '$artistId',
      'entity': 'song',
      'limit': '$clamped',
    });
    final Map<String, dynamic>? decoded = await _getJson(uri);
    if (decoded == null) return const [];
    final results = decoded['results'];
    if (results is! List || results.length < 2) return const [];

    final tracks = <SpotifyImportedTrack>[];
    for (final item in results.skip(1)) {
      if (item is! Map) continue;
      if ((item['wrapperType']?.toString() ?? '').toLowerCase() != 'track') {
        continue;
      }
      final title = (item['trackName']?.toString() ?? '').trim();
      if (title.isEmpty) continue;
      final rawArtist = (item['artistName']?.toString() ?? '').trim();
      final trackArtist = rawArtist.isEmpty ? artistName : rawArtist;

      // Strictly enforce artist match: only songs by or featuring the target artist!
      if (!matchesArtist(trackArtist, artistName)) {
        continue;
      }

      final trackId = item['trackId'];
      final preview = item['previewUrl'];
      tracks.add(SpotifyImportedTrack(
        spotifyId: trackId is int ? 'itunes-$trackId' : _fallbackTrackId(title, artistName),
        title: title,
        artist: trackArtist,
        album: (item['collectionName']?.toString() ?? '').trim(),
        duration: _durationFromTrackMillis(item['trackTimeMillis']),
        previewUrl: preview is String ? preview : '',
        artworkUrl: _hiResArtwork(item['artworkUrl100']),
      ));
      if (tracks.length >= clamped) break;
    }
    return tracks;
  }

  /// Checks whether [trackArtist] includes [targetArtist] as a primary or
  /// collaborating artist.
  static bool matchesArtist(String trackArtist, String targetArtist) {
    final normTrack = _normalizeName(trackArtist);
    final normTarget = _normalizeName(targetArtist);
    if (normTrack.isEmpty || normTarget.isEmpty) return false;
    if (normTrack == normTarget) return true;

    final parts = trackArtist
        .split(RegExp(r'[,&/]|(\b(and|feat|ft|with|featuring)\b)', caseSensitive: false))
        .map((p) => _normalizeName(p))
        .where((p) => p.isNotEmpty);

    for (final part in parts) {
      if (part == normTarget) return true;
      if (part.startsWith('$normTarget ') ||
          part.endsWith(' $normTarget') ||
          part.contains(' $normTarget ')) {
        return true;
      }
    }

    final wordRegExp = RegExp(r'\b' + RegExp.escape(normTarget) + r'\b');
    return wordRegExp.hasMatch(normTrack);
  }

  Future<Map<String, dynamic>?> _getJson(Uri uri) async {
    try {
      final response = await _client
          .get(uri, headers: {'User-Agent': _browserUserAgent}).timeout(
                const Duration(seconds: 12),
              );
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static String _cleanArtistQuery(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _normalizeName(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9 ]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _hiResArtwork(Object? value) {
    if (value is! String || value.isEmpty) return '';
    return value.replaceFirst('100x100bb', '600x600bb');
  }

  static Duration _durationFromTrackMillis(Object? value) {
    var ms = 0;
    if (value is int) {
      ms = value;
    } else if (value is num) {
      ms = value.toInt();
    }
    if (ms <= 0) return const Duration(minutes: 3);
    return Duration(milliseconds: ms);
  }

  String _fallbackTrackId(String title, String artist) {
    final source = '$title|$artist'.toLowerCase();
    var hash = 0;
    for (final unit in source.codeUnits) {
      hash = 0x1fffffff & (hash + unit);
      hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 15));
    }
    return 'itunes-${hash.toRadixString(16).padLeft(11, '0')}';
  }

  Future<String?> _resolveShortLink(String input) async {
    final parsed = Uri.tryParse(input.trim());
    if (parsed == null) return null;
    var uri = parsed;

    for (var hop = 0; hop < 6; hop++) {
      final http.Response response;
      try {
        response = await _client
            .get(uri, headers: {'User-Agent': _browserUserAgent})
            .timeout(const Duration(seconds: 8));
      } on Exception {
        // Includes TimeoutException and SocketException.
        return null;
      }

      if (response.statusCode >= 300 && response.statusCode < 400) {
        final location = response.headers['location'];
        if (location == null || location.isEmpty) return null;
        final next = uri.resolve(location);
        if (next == uri) return null;
        uri = next;
        continue;
      }

      if (response.statusCode != 200) return null;
      return response.request?.url.toString() ?? uri.toString();
    }
    return null;
  }

  Future<Map<String, dynamic>> _fetchEmbedEntity(SpotifyLink link) async {
    final embedUrl = Uri.https('open.spotify.com', '/embed/${link.type.name}/${link.id}');

    // Mobile data often drops the first request, so try twice with a bounded
    // wait each time instead of hanging on a dead socket.
    http.Response? fetched;
    for (var attempt = 0; attempt < 2 && fetched == null; attempt++) {
      try {
        fetched = await _client.get(embedUrl, headers: {
          'User-Agent': _browserUserAgent,
          'Accept': 'text/html,application/xhtml+xml',
        }).timeout(_requestTimeout);
      } on Exception {
        // Includes TimeoutException and SocketException.
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      }
    }
    if (fetched == null) {
      throw const SpotifyImportException(
        'Could not reach Spotify. Check your internet connection and try again.',
      );
    }
    final http.Response response = fetched;

    if (response.statusCode == 404) {
      throw const SpotifyImportException(
        'This Spotify link was not found. It may be private or removed.',
      );
    }
    if (response.statusCode != 200) {
      throw const SpotifyImportException(
        'Spotify is unavailable right now. Please try again in a moment.',
      );
    }

    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    final nextData = _extractNextData(body);
    if (nextData == null) {
      throw const SpotifyImportException(
        'Could not read this Spotify link. Please open it in Spotify and copy the share link again.',
      );
    }

    final pageProps = _mapAt(const ['props', 'pageProps'], nextData);
    if (pageProps == null) {
      throw const SpotifyImportException('Could not read this Spotify link.');
    }

    final status = pageProps['status'];
    if (status is int && status >= 400) {
      throw const SpotifyImportException(
        'This Spotify link was not found. It may be private or removed.',
      );
    }

    final entity = _findEntity(pageProps);
    if (entity == null) {
      final title = pageProps['title'];
      final detail = title is String && title.isNotEmpty ? ' ($title)' : '';
      throw SpotifyImportException(
        'This Spotify link could not be imported$detail. It may be private or unavailable.',
      );
    }
    return entity;
  }

  Map<String, dynamic>? _extractNextData(String html) {
    const marker = '<script id="__NEXT_DATA__" type="application/json">';
    final start = html.indexOf(marker);
    if (start < 0) {
      final alt = html.indexOf('<script id="__NEXT_DATA__"');
      if (alt < 0) return null;
      final open = html.indexOf('>', alt);
      if (open < 0) return null;
      final end = html.indexOf('</script>', open);
      if (end < 0) return null;
      return _decodeJsonObject(html.substring(open + 1, end));
    }
    final contentStart = start + marker.length;
    final end = html.indexOf('</script>', contentStart);
    if (end < 0) return null;
    return _decodeJsonObject(html.substring(contentStart, end));
  }

  Map<String, dynamic>? _decodeJsonObject(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    try {
      final decoded = jsonDecode(trimmed);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  Map<String, dynamic>? _findEntity(Map<String, dynamic> pageProps) {
    const knownPaths = <List<String>>[
      ['state', 'data', 'entity'],
      ['data', 'entity'],
      ['entity'],
    ];
    for (final path in knownPaths) {
      final entity = _mapAt(path, pageProps);
      if (entity != null && _looksLikeEntity(entity)) return entity;
    }

    final deep = _deepFindMap(pageProps, 'trackList', maxDepth: 10);
    if (deep != null) return deep;
    return _deepFindTypedEntity(pageProps, maxDepth: 8);
  }

  bool _looksLikeEntity(Map<String, dynamic> entity) {
    return entity.containsKey('trackList') ||
        entity.containsKey('uri') ||
        entity.containsKey('title') ||
        entity.containsKey('name');
  }

  Map<String, dynamic>? _mapAt(List<String> path, Map<String, dynamic> root) {
    Object? current = root;
    for (final key in path) {
      if (current is Map<String, dynamic>) {
        current = current[key];
      } else if (current is Map) {
        current = current[key];
      } else {
        return null;
      }
    }
    return current is Map<String, dynamic> ? current : null;
  }

  Map<String, dynamic>? _deepFindMap(Map<String, dynamic> node, String key, {int maxDepth = 8}) {
    if (node.containsKey(key) && node[key] is Map<String, dynamic>) {
      return node[key] as Map<String, dynamic>;
    }
    if (maxDepth <= 0) return null;
    for (final value in node.values) {
      if (value is Map<String, dynamic>) {
        final found = _deepFindMap(value, key, maxDepth: maxDepth - 1);
        if (found != null) return found;
      }
    }
    return null;
  }

  Map<String, dynamic>? _deepFindTypedEntity(Map<String, dynamic> node, {int maxDepth = 8}) {
    final type = node['type'];
    if (type is String && const {'track', 'playlist', 'album', 'artist'}.contains(type) && _looksLikeEntity(node)) {
      return node;
    }
    if (maxDepth <= 0) return null;
    for (final value in node.values) {
      if (value is Map<String, dynamic>) {
        final found = _deepFindTypedEntity(value, maxDepth: maxDepth - 1);
        if (found != null) return found;
      }
    }
    return null;
  }

  SpotifyImportResult _resultFromEntity(SpotifyLink link, Map<String, dynamic> entity) {
    final name = _stringValue(entity, 'name', 'title');
    final subtitle = _stringValue(entity, 'subtitle');

    var imageUrl = '';
    final coverArt = entity['coverArt'];
    if (coverArt is Map) {
      final sources = coverArt['sources'];
      if (sources is List && sources.isNotEmpty) {
        final last = sources.last;
        if (last is Map && last['url'] is String) {
          imageUrl = (last['url'] as String).trim();
        }
      }
    }
    if (imageUrl.isEmpty) {
      final visualIdentity = entity['visualIdentity'];
      if (visualIdentity is Map && visualIdentity['image'] is List) {
        final images = visualIdentity['image'] as List;
        if (images.isNotEmpty) {
          final last = images.last;
          if (last is Map && last['url'] is String) {
            imageUrl = (last['url'] as String).trim();
          }
        }
      }
    }

    switch (link.type) {
      case SpotifyLinkType.track:
        final track = _trackFromEntity(
          entity,
          fallbackAlbum: subtitle,
          fallbackArtworkUrl: imageUrl,
        );
        if (track == null) {
          throw const SpotifyImportException('This track could not be read from Spotify.');
        }
        return SpotifyImportResult(
          type: SpotifyLinkType.track,
          title: track.title,
          subtitle: track.artist,
          tracks: [track],
          imageUrl: imageUrl.isNotEmpty ? imageUrl : track.artworkUrl,
        );
      case SpotifyLinkType.playlist:
      case SpotifyLinkType.album:
      case SpotifyLinkType.artist:
        final trackList = entity['trackList'];
        final tracks = <SpotifyImportedTrack>[];
        if (trackList is List) {
          for (final item in trackList) {
            if (item is! Map<String, dynamic>) continue;
            final track = _trackFromListEntry(
              item,
              fallbackArtist: subtitle.isNotEmpty && subtitle != 'Top tracks' ? subtitle : name,
              fallbackAlbum: name,
              fallbackArtworkUrl: imageUrl,
            );
            if (track != null) {
              // For artist import: strictly verify that the track is by this artist!
              if (link.type == SpotifyLinkType.artist && name.isNotEmpty) {
                if (!matchesArtist(track.artist, name)) {
                  continue;
                }
              }
              tracks.add(track);
            }
          }
        }
        if (tracks.isEmpty) {
          throw SpotifyImportException(
            link.type == SpotifyLinkType.artist
                ? 'No tracks found for "$name" on Spotify.'
                : (link.type == SpotifyLinkType.playlist
                    ? 'No tracks were found in this Spotify playlist.'
                    : 'No tracks were found in this Spotify album.'),
          );
        }
        if (imageUrl.isEmpty && tracks.isNotEmpty && tracks.first.artworkUrl.isNotEmpty) {
          imageUrl = tracks.first.artworkUrl;
        }
        return SpotifyImportResult(
          type: link.type,
          title: name.isEmpty
              ? (link.type == SpotifyLinkType.artist
                  ? 'Artist'
                  : (link.type == SpotifyLinkType.playlist ? 'Spotify Playlist' : 'Spotify Album'))
              : name,
          subtitle: link.type == SpotifyLinkType.artist
              ? 'Top songs · ${tracks.length} tracks'
              : subtitle,
          tracks: tracks,
          imageUrl: imageUrl,
        );
    }
  }

  static String _extractArtworkFromMap(Map<String, dynamic> map) {
    final coverArt = map['coverArt'];
    if (coverArt is Map) {
      final sources = coverArt['sources'];
      if (sources is List && sources.isNotEmpty) {
        final last = sources.last;
        if (last is Map && last['url'] is String) {
          final u = (last['url'] as String).trim();
          if (u.isNotEmpty) return u;
        }
      }
    }
    final visualIdentity = map['visualIdentity'];
    if (visualIdentity is Map && visualIdentity['image'] is List) {
      final images = visualIdentity['image'] as List;
      if (images.isNotEmpty) {
        final last = images.last;
        if (last is Map && last['url'] is String) {
          final u = (last['url'] as String).trim();
          if (u.isNotEmpty) return u;
        }
      }
    }
    final album = map['album'];
    if (album is Map<String, dynamic>) {
      final albumArt = _extractArtworkFromMap(album);
      if (albumArt.isNotEmpty) return albumArt;
    }
    final images = map['images'];
    if (images is List && images.isNotEmpty) {
      final first = images.first;
      if (first is Map && first['url'] is String) {
        final u = (first['url'] as String).trim();
        if (u.isNotEmpty) return u;
      }
    }
    final direct = map['artworkUrl'] ?? map['thumbnail'] ?? map['image'] ?? map['artworkUrl100'];
    if (direct is String && direct.trim().isNotEmpty) {
      return direct.trim();
    }
    return '';
  }

  SpotifyImportedTrack? _trackFromEntity(
    Map<String, dynamic> entity, {
    required String fallbackAlbum,
    String fallbackArtworkUrl = '',
  }) {
    var id = _spotifyIdFromUri(_stringValue(entity, 'uri'));
    if (id.isEmpty) id = _stringValue(entity, 'id');
    final title = _stringValue(entity, 'title', 'name');
    if (title.isEmpty) return null;

    final artists = entity['artists'];
    var artist = subtitleFromList(artists);
    if (artist.isEmpty) artist = _stringValue(entity, 'subtitle');
    if (artist.isEmpty) artist = 'Unknown artist';

    final album = _stringValue(entity, 'album');
    final durationMs = _intValue(entity, 'duration');

    var artwork = _extractArtworkFromMap(entity);
    if (artwork.isEmpty) artwork = fallbackArtworkUrl;

    return SpotifyImportedTrack(
      spotifyId: id.isEmpty ? _fallbackId(title, artist) : id,
      title: title,
      artist: artist,
      album: album.isEmpty ? fallbackAlbum : album,
      duration: _durationFromMs(durationMs),
      artworkUrl: artwork,
    );
  }

  SpotifyImportedTrack? _trackFromListEntry(
    Map<String, dynamic> entry, {
    required String fallbackArtist,
    required String fallbackAlbum,
    String fallbackArtworkUrl = '',
  }) {
    final title = _stringValue(entry, 'title', 'name');
    if (title.isEmpty) return null;

    final id = _spotifyIdFromUri(_stringValue(entry, 'uri'));
    var artist = subtitleFromList(entry['artists']);
    if (artist.isEmpty) artist = _stringValue(entry, 'subtitle');
    if (artist.isEmpty) artist = fallbackArtist;
    if (artist.isEmpty) artist = 'Unknown artist';

    final album = _stringValue(entry, 'album');
    final durationMs = _intValue(entry, 'duration');

    var artwork = _extractArtworkFromMap(entry);
    if (artwork.isEmpty) artwork = fallbackArtworkUrl;

    return SpotifyImportedTrack(
      spotifyId: (id.isEmpty) ? _fallbackId(title, artist) : id,
      title: title,
      artist: artist,
      album: album.isEmpty ? fallbackAlbum : album,
      duration: _durationFromMs(durationMs),
      artworkUrl: artwork,
    );
  }

  String subtitleFromList(Object? value) {
    if (value is! List) return '';
    final names = <String>[];
    for (final item in value) {
      if (item is Map) {
        final name = item['name'];
        if (name is String && name.trim().isNotEmpty) names.add(name.trim());
      } else if (item is String && item.trim().isNotEmpty) {
        names.add(item.trim());
      }
    }
    return names.join(', ');
  }

  String _stringValue(Map<String, dynamic> map, String primary, [String? secondary]) {
    final primaryValue = map[primary];
    if (primaryValue is String && primaryValue.trim().isNotEmpty) return primaryValue.trim();
    if (secondary != null) {
      final secondaryValue = map[secondary];
      if (secondaryValue is String && secondaryValue.trim().isNotEmpty) {
        return secondaryValue.trim();
      }
    }
    return '';
  }

  int _intValue(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }

  Duration _durationFromMs(int durationMs) {
    if (durationMs <= 0) return const Duration(minutes: 3);
    return Duration(milliseconds: durationMs);
  }

  String _spotifyIdFromUri(String uri) {
    if (uri.isEmpty) return '';
    final parts = uri.split(':');
    if (parts.length != 3 || parts[0] != 'spotify' || parts[1] != 'track') return '';
    final id = parts[2];
    return _idPattern.hasMatch(id) ? id : '';
  }

  String _fallbackId(String title, String artist) {
    final source = '$title|$artist'.toLowerCase();
    var hash = 0;
    for (final unit in source.codeUnits) {
      hash = 0x1fffffff & (hash + unit);
      hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 15));
    }
    return hash.toRadixString(16).padLeft(11, '0');
  }

  /// Resolves playlist/album thumbnail URL via Spotify's keyless oEmbed endpoint.
  static Future<String?> fetchSpotifyThumbnail(String urlOrId) async {
    try {
      final clean = urlOrId.trim();
      if (clean.isEmpty) return null;
      final String fullUrl;
      if (clean.startsWith('http')) {
        fullUrl = clean;
      } else {
        fullUrl = 'https://open.spotify.com/playlist/$clean';
      }
      final uri = Uri.https('open.spotify.com', '/oembed', {'url': fullUrl});
      final client = http.Client();
      try {
        final res = await client.get(
          uri,
          headers: {'User-Agent': _browserUserAgent},
        ).timeout(const Duration(seconds: 5));
        if (res.statusCode == 200) {
          final decoded = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
          if (decoded is Map && decoded['thumbnail_url'] is String) {
            final thumb = (decoded['thumbnail_url'] as String).trim();
            if (thumb.isNotEmpty) return thumb;
          }
        }
      } finally {
        client.close();
      }
    } catch (_) {}
    return null;
  }

  void dispose() {
    _client.close();
  }
}
