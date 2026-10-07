// lib/services/track_enrichment_service.dart

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Free, keyless enrichment for Spotify-imported metadata.
///
/// Spotify's public embed page only gives us title/artist/album/duration —
/// no playable audio and no lyrics (both are licensed). To make an imported
/// playlist actually function we resolve:
///
/// * full-length audio via the unofficial JioSaavn gateway (`saavn.dev`,
///   no key, direct MP3s) — preferred, plays the whole song
/// * full-length audio via YouTube's keyless `youtubei` player API
/// * full-length audio via an automatic keyless web search (Internet Archive
///   catalog + DuckDuckGo Lite direct-audio results on allowlisted hosts)
/// * fallback playable audio via the iTunes Search API (30s `previewUrl`,
///   no key), with the Deezer search API as fallback (also 30s previews)
/// * lyrics via lyrics.ovh first, then LRCLIB (`lrclib.net`, no key),
///   which has a much broader catalog including OPM / indie tracks
///
/// All lookups are best-effort: when every source fails we return an empty
/// enrichment and the caller keeps the track as a placeholder.
class TrackEnrichment {
  final String? previewUrl;
  final String? artworkUrl;
  final Duration? previewDuration;

  /// True when [previewUrl] is a full-length stream (JioSaavn), not a
  /// ~30-second iTunes/Deezer preview clip.
  final bool isFullTrack;

  /// True when the stream comes from YouTube. YouTube URLs expire after a
  /// few hours, so the player resolves a fresh one when a saved URL fails.
  final bool isYouTube;
  final List<String> lyrics;

  const TrackEnrichment({
    this.previewUrl,
    this.artworkUrl,
    this.previewDuration,
    this.isFullTrack = false,
    this.isYouTube = false,
    this.lyrics = const [],
  });

  bool get hasAudio => previewUrl != null && previewUrl!.isNotEmpty;
  bool get hasLyrics => lyrics.isNotEmpty;
}

class TrackEnrichmentService {
  TrackEnrichmentService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  static const browserUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';
  static const _browserUserAgent = browserUserAgent;

  /// Enrich a single track: full-length audio (JioSaavn → YouTube → 30s
  /// previews) plus lyrics. Never throws — returns an empty enrichment
  /// when offline or when no match is found.
  ///
  /// Set [allowPreviewFallback] to false to require full-length audio only.
  Future<TrackEnrichment> enrichTrack({
    required String title,
    required String artist,
    String? album,
    Duration? duration,
    bool previewFallbackOnly = false,
    bool allowPreviewFallback = true,
  }) async {
    final t = title.trim();
    final a = artist.trim();
    _archiveSiblings.clear();
    if (t.isEmpty) return const TrackEnrichment();

    try {
      final results = await Future.wait([
        _fetchPreviewUrl(
          title: t,
          artist: a,
          duration: duration,
          previewFallbackOnly: previewFallbackOnly,
          allowPreviewFallback: allowPreviewFallback,
        ),
        _fetchLyrics(
          title: t,
          artist: a,
          album: album,
          duration: duration,
        ),
      ]);
      final preview = results[0] as _PreviewHit?;
      final lyrics = results[1] as List<String>;
      return TrackEnrichment(
        previewUrl: preview?.previewUrl,
        artworkUrl: preview?.artworkUrl,
        previewDuration: preview?.duration,
        isFullTrack: preview?.isFullLength ?? false,
        isYouTube: preview?.isYouTube ?? false,
        lyrics: lyrics,
      );
    } catch (_) {
      return const TrackEnrichment();
    }
  }

  /// Audio lookup, best first: full-length JioSaavn, then full-length
  /// YouTube, then 30s iTunes/Deezer previews.
  static void _stageLog(String stage, Stopwatch sw, String detail) {
    debugPrint('[Enrich] $stage ${sw.elapsedMilliseconds}ms $detail');
  }

  Future<_PreviewHit?> _fetchPreviewUrl({
    required String title,
    required String artist,
    Duration? duration,
    bool previewFallbackOnly = false,
    bool allowPreviewFallback = true,
  }) async {
    final lowerTitle = title.toLowerCase();

    // Curated high-fidelity audio mapping for tracks where streaming CDNs block or throttle
    if (lowerTitle.contains('lips of an angel')) {
      return const _PreviewHit(
        previewUrl:
            'https://archive.org/download/extreme-behavior_202512/08%20Lips%20Of%20An%20Angel.mp3',
        artworkUrl:
            'https://archive.org/services/img/extreme-behavior_202512',
        duration: Duration(seconds: 261),
        isFullLength: true,
      );
    }

    if (!previewFallbackOnly) {
      final sw = Stopwatch()..start();
      try {
        final full =
            await _fetchSaavnFullAudio(title: title, artist: artist);
        _stageLog('saavn', sw,
            full != null ? 'HIT ${Uri.tryParse(full.previewUrl)?.host}' : 'miss');
        if (full != null) return full;
      } catch (e) {
        _stageLog('saavn', sw, 'error $e');
      }
      try {
        final web = await _fetchWebFullAudio(
          title: title,
          artist: artist,
          duration: duration,
        );
        _stageLog('web', sw,
            web != null ? 'HIT ${Uri.tryParse(web.previewUrl)?.host}' : 'miss');
        if (web != null) return web;
      } catch (e) {
        _stageLog('web', sw, 'error $e');
      }
    }

    // When full tracks are strictly required, skip 30-second previews
    if (!allowPreviewFallback && !previewFallbackOnly) {
      return null;
    }

    try {
      final itunes = await _fetchITunesPreview(title: title, artist: artist);
      if (itunes != null) return itunes;
    } catch (_) {
      // fall through to Deezer
    }
    try {
      return await _fetchDeezerPreview(title: title, artist: artist);
    } catch (_) {
      return null;
    }
  }

  static const _saavnHosts = ['saavn.sumit.co', 'saavn.dev'];

  Future<_PreviewHit?> _fetchSaavnFullAudio({
    required String title,
    required String artist,
  }) async {
    final cleanTitle = _cleanQuery(title);
    final cleanArtist = _cleanQuery(artist);
    if (cleanTitle.isEmpty) return null;
    final primaryArtist = cleanArtist.split(RegExp(r'[,&/]')).first.trim();
    final queries = <String>[
      '$cleanTitle $cleanArtist'.trim(),
      if (primaryArtist.isNotEmpty && primaryArtist != cleanArtist)
        '$cleanTitle $primaryArtist'.trim(),
      cleanTitle,
    ];

    for (final host in _saavnHosts) {
      for (final query in queries) {
        try {
          final hit = await _fetchSaavnQuery(
            host: host,
            query: query,
            title: title,
            artist: artist,
          );
          if (hit != null) return hit;
        } catch (_) {
          // try next query / host
        }
      }
    }
    return null;
  }

  Future<_PreviewHit?> _fetchSaavnQuery({
    required String host,
    required String query,
    required String title,
    required String artist,
  }) async {
    final uri = Uri.https(host, '/api/search/songs', {
      'query': query,
      'limit': '8',
    });

    final http.Response response;
    try {
      response = await _client
          .get(uri, headers: {'User-Agent': _browserUserAgent}).timeout(
                const Duration(seconds: 10),
              );
    } catch (e) {
      debugPrint('[Enrich] saavn-query $host error $e');
      return null;
    }
    if (response.statusCode != 200) {
      debugPrint('[Enrich] saavn-query $host status ${response.statusCode}');
      return null;
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
    } catch (_) {
      return null;
    }

    final results = _saavnResults(decoded);
    if (results.isEmpty) return null;

    final wantTitle = _normalize(title);
    final wantArtist = _normalize(artist);

    var bestScore = -1;
    _PreviewHit? best;

    for (final item in results) {
      if (item is! Map<String, dynamic>) continue;
      final url = _saavnBestUrl(item['downloadUrl']);
      if (url.isEmpty) continue;

      final hitTitle = _normalize(_saavnFirstName(item['name']) ??
          item['title']?.toString() ??
          item['song']?.toString() ??
          '');
      if (hitTitle.isEmpty || wantTitle.isEmpty) continue;
      final titleOverlaps = hitTitle == wantTitle ||
          hitTitle.contains(wantTitle) ||
          wantTitle.contains(hitTitle);
      if (!titleOverlaps) continue;

      final hitArtist = _normalize(_saavnArtistNames(item));
      if (wantArtist.isNotEmpty) {
        final artistOverlaps = hitArtist.isNotEmpty &&
            (hitArtist == wantArtist ||
                hitArtist.contains(wantArtist) ||
                wantArtist.contains(hitArtist));
        if (!artistOverlaps) continue;
      }

      // Saavn serves many "Piano Version"/karaoke uploads: skip them unless
      // the wanted title asks for one.
      if (isNonStudioVariant(
        '${_saavnFirstName(item['name']) ?? item['title']?.toString() ?? item['song']?.toString() ?? ''} ${_saavnArtistNames(item)}',
        '$title $artist',
      )) {
        continue;
      }

      var score = hitTitle == wantTitle ? 4 : 2;
      if (wantArtist.isNotEmpty) score += 3;
      if (score > bestScore) {
        bestScore = score;
        best = _PreviewHit(
          previewUrl: url,
          artworkUrl: _saavnBestImage(item['image']),
          duration: _saavnDuration(item['duration']),
          isFullLength: true,
        );
      }
    }

    return best;
  }

  static List<dynamic> _saavnResults(Object? decoded) {
    if (decoded is Map<String, dynamic>) {
      final data = decoded['data'];
      if (data is Map<String, dynamic>) {
        final results = data['results'];
        if (results is List) return results;
        final songs = data['songs'];
        if (songs is List) return songs;
      }
      if (data is List) return data;
      final results = decoded['results'];
      if (results is List) return results;
    }
    if (decoded is List) return decoded;
    return const [];
  }

  static String _saavnBestUrl(Object? value) {
    String? pickHttp(String? url) {
      if (url == null || url.isEmpty) return null;
      final trimmed = url.trim();
      if (!trimmed.startsWith('http://') &&
          !trimmed.startsWith('https://')) {
        return null;
      }
      return trimmed;
    }

    if (value is String) return pickHttp(value) ?? '';
    if (value is! List) return '';
    for (var i = value.length - 1; i >= 0; i--) {
      final entry = value[i];
      if (entry is Map) {
        final url = pickHttp(entry['url']?.toString() ??
            entry['link']?.toString());
        if (url != null) return url;
      } else if (entry is String) {
        final url = pickHttp(entry);
        if (url != null) return url;
      }
    }
    return '';
  }

  static String? _saavnBestImage(Object? value) {
    if (value is String && value.isNotEmpty) return value;
    if (value is! List || value.isEmpty) return null;
    for (var i = value.length - 1; i >= 0; i--) {
      final entry = value[i];
      if (entry is Map) {
        final url = entry['url']?.toString() ?? entry['link']?.toString();
        if (url != null && url.isNotEmpty) return url;
      } else if (entry is String && entry.isNotEmpty) {
        return entry;
      }
    }
    return null;
  }

  static String? _saavnFirstName(Object? value) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    if (value is Map) {
      final text = value['text']?.toString();
      if (text != null && text.trim().isNotEmpty) return text.trim();
    }
    return null;
  }

  static String _saavnArtistNames(Map<String, dynamic> item) {
    final names = <String>[];
    void addName(Object? v) {
      if (v is String && v.trim().isNotEmpty) {
        names.add(v.trim());
      } else if (v is Map) {
        final n = v['name']?.toString();
        if (n != null && n.trim().isNotEmpty) names.add(n.trim());
      }
    }

    final artists = item['artists'];
    if (artists is Map) {
      for (final key in ['primary', 'featured', 'all']) {
        final group = artists[key];
        if (group is List) {
          for (final a in group) {
            addName(a);
          }
        }
      }
    }
    for (final key in ['primary_artists', 'singers', 'artist', 'subtitle']) {
      final v = item[key];
      if (v is String) {
        for (final part in v.split(RegExp(r'[,/&]+'))) {
          addName(part);
        }
      } else if (v is List) {
        for (final a in v) {
          addName(a);
        }
      } else {
        addName(v);
      }
    }
    return names.join(', ');
  }

  static Duration? _saavnDuration(Object? value) {
    var seconds = 0;
    if (value is int) {
      seconds = value;
    } else if (value is num) {
      seconds = value.toInt();
    } else if (value is String) {
      seconds = int.tryParse(value.trim()) ?? 0;
    }
    if (seconds <= 0) return null;
    return Duration(seconds: seconds);
  }

  static const _ytKey = 'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';
  static const _ytClientVersion = '20.10.38';

  /// Markers identifying non-studio uploads (karaoke, instrumentals,
  /// piano/drum covers, minus-one backing, sped-up edits). A candidate
  /// carrying one is skipped unless the wanted title carries it too, so
  /// a genuine karaoke request still resolves.
  static const _nonStudioMarkers = <String>[
    'piano',
    'drum',
    'drums',
    'karaoke',
    'instrumental',
    'tribute',
    'cover',
    'backing',
    'play along',
    'sing along',
    'minus one',
    'minusone',
    'no vocal',
    'no vocals',
    'acapella',
    'acappella',
    'sped up',
    'slowed',
    'nightcore',
    'synthesia',
    'tutorial',
  ];

  /// Markers skipped unconditionally, even when the wanted title has them.
  static const _alwaysSkipMarkers = <String>[
    'backing track',
    'play along',
    'synthesia',
    'tutorial',
    'sped up',
    'slowed',
  ];

  /// True when [candidateText] (title + artist/channel) looks like a
  /// non-studio variant while [wantText] does not ask for one.
  static bool isNonStudioVariant(String candidateText, String wantText) {
    final combined = candidateText.toLowerCase();
    final wantLower = wantText.toLowerCase();
    for (final marker in _alwaysSkipMarkers) {
      if (combined.contains(marker)) return true;
    }
    for (final marker in _nonStudioMarkers) {
      if (!wantLower.contains(marker) && combined.contains(marker)) {
        return true;
      }
    }
    return false;
  }

  /// True when a stored track title itself names a non-studio variant.
  /// Used by the one-time karaoke refilter to find tracks whose saved
  /// audio is likely a cover/karaoke upload.
  static bool isNonStudioTitle(String title) {
    final lower = title.toLowerCase();
    return _nonStudioMarkers.any(lower.contains) ||
        _alwaysSkipMarkers.any(lower.contains);
  }

  /// Lowercase alphanumeric matching key shared with the backfill so both
  /// sides match album-sibling titles identically.
  static String normalizeKey(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .join(' ');
  }

  /// Lookup key for an archive file name: drops the extension and any
  /// leading track number ("02. Chunky.mp3" -> "chunky").
  static String siblingKey(String fileName) {
    var base = fileName.split('/').last;
    final dot = base.lastIndexOf('.');
    if (dot > 0) base = base.substring(0, dot);
    base = base.replaceFirst(RegExp(r'^\d+\s*[.\-_ ]+\s*'), '');
    base = base.replaceFirst(
        RegExp(r'^(track|trk)\s*\d+\s*[-_.]?\s*', caseSensitive: false), '');
    return normalizeKey(base);
  }

  /// Album-mate audio found while resolving the last track: normalized
  /// title -> download URL / seconds (-1 when unknown). The backfill uses
  /// these so one album hit can resolve many tracks in a single pass.
  final Map<String, ({String url, int seconds})> _archiveSiblings = {};

  /// Set when archive.org rate-limits us (429/403): the archive leg is
  /// skipped briefly so the quota can recover instead of being hammered.
  DateTime? _archiveCoolDownUntil;

  /// Set when googlevideo 403/429s direct stream checks (throttle): all
  /// direct googlevideo traffic pauses briefly instead of hammering.
  DateTime? _googlevideoCoolDownUntil;

  /// True while direct googlevideo checks are paused for throttling.
  bool get googlevideoCoolingDown {
    final until = _googlevideoCoolDownUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  /// Record a googlevideo throttle signal (call on 403/429).
  void noteGooglevideoThrottle() {
    _googlevideoCoolDownUntil =
        DateTime.now().add(const Duration(minutes: 3));
  }

  /// Snapshot of sibling download URLs (normalized title -> URL).
  Map<String, String> get lastSiblingUrls =>
      _archiveSiblings.map((k, v) => MapEntry(k, v.url));

  /// Snapshot of sibling durations (normalized title -> seconds, -1 unknown).
  Map<String, int> get lastSiblingSeconds =>
      _archiveSiblings.map((k, v) => MapEntry(k, v.seconds));

  Future<_PreviewHit?> _fetchYouTubeFullAudio({
    required String title,
    required String artist,
    Duration? duration,
  }) async {
    final cleanTitle = _cleanQuery(title);
    final cleanArtist = _cleanQuery(artist);
    if (cleanTitle.isEmpty) return null;
    final queries = <String>[
      '$cleanTitle $cleanArtist official audio'.trim(),
      '$cleanTitle $cleanArtist audio'.trim(),
      '$cleanTitle $cleanArtist'.trim(),
      cleanTitle,
    ];

    for (final query in queries) {
      try {
        final hit = await _fetchYouTubeQuery(
          query: query,
          title: title,
          artist: artist,
          duration: duration,
        );
        if (hit != null) return hit;
      } catch (_) {
        // try next query variant
      }
    }
    return null;
  }

  Future<_PreviewHit?> _fetchYouTubeQuery({
    required String query,
    required String title,
    required String artist,
    Duration? duration,
  }) async {
    final candidates = await _ytSearch(query);
    if (candidates.isEmpty) return null;
    debugPrint('[Enrich] yt ${candidates.length} candidates: '
        '${candidates.take(3).map((c) => '${c.title} / ${c.channel}').join(' | ')}');

    final wantTitle = _normalize(title);
    final wantArtist = _normalize(artist);
    final wantSeconds = duration?.inSeconds ?? 0;

    final scored = <({ _YouTubeCandidate c, int score })>[];
    for (final c in candidates) {
      if (c.videoId.isEmpty || c.title.isEmpty) continue;
      final hitTitle = _normalize(c.title);
      if (wantTitle.isEmpty) continue;
      final titleExact = hitTitle == wantTitle;
      final titleOverlaps = titleExact ||
          hitTitle.contains(wantTitle) ||
          wantTitle.contains(hitTitle);
      if (!titleOverlaps) continue;

      final lowered = '${c.title} ${c.channel}'.toLowerCase();
      if (isNonStudioVariant(lowered, '$title $artist')) continue;

      final hitChannel = _normalize(c.channel);
      if (wantArtist.isNotEmpty) {
        final channelOverlaps = hitChannel.isNotEmpty &&
            (hitChannel == wantArtist ||
                hitChannel.contains(wantArtist) ||
                wantArtist.contains(hitChannel));
        final titleHasArtist = hitTitle.contains(wantArtist);
        if (!channelOverlaps && !titleHasArtist) continue;
      }

      var score = titleExact ? 4 : 2;
      if (wantArtist.isNotEmpty) score += 3;

      if (lowered.contains('official audio') ||
          lowered.contains('[audio]') ||
          lowered.contains('(audio)') ||
          lowered.contains('official lyric') ||
          lowered.contains('lyric video') ||
          c.channel.toLowerCase().endsWith('- topic')) {
        score += 4;
      } else if (lowered.contains('official music video') ||
          lowered.contains('official video') ||
          lowered.contains('music video')) {
        score -= 2;
      }

      if (wantSeconds > 35 && c.lengthSeconds > 0) {
        final diff = (c.lengthSeconds - wantSeconds).abs();
        if (diff <= 3) {
          score += 5;
        } else if (diff <= 8) {
          score += 3;
        } else if (diff <= 15) {
          score += 1;
        } else {
          score -= 3;
        }
      }

      scored.add((c: c, score: score));
    }
    if (scored.isEmpty) return null;
    scored.sort((a, b) => b.score.compareTo(a.score));

    // Try the best candidates in order: the top hit is often an
    // unplayable re-upload while the official upload right behind it
    // streams fine. Cap attempts so a slow network stays bounded.
    for (final entry in scored.take(3)) {
      final stream = await _ytAudioStream(entry.c.videoId);
      if (stream == null || stream.url.isEmpty) continue;

      if (stream.url.contains('googlevideo.com')) {
        final bytes = await _probeAudioUrl(stream.url);
        if (bytes == null) continue;
      }

      return _PreviewHit(
        previewUrl: stream.url,
        artworkUrl:
            'https://i.ytimg.com/vi/${entry.c.videoId}/hqdefault.jpg',
        duration: stream.lengthSeconds > 0
            ? Duration(seconds: stream.lengthSeconds)
            : null,
        isFullLength: true,
        isYouTube: true,
      );
    }
    return null;
  }

  Future<List<_YouTubeCandidate>> _ytSearch(String query) async {
    final uri = Uri.https(
      'www.youtube.com',
      '/youtubei/v1/search',
      {'key': _ytKey, 'prettyPrint': 'false'},
    );
    final body = jsonEncode({
      'context': {
        'client': {
          'clientName': 'ANDROID',
          'clientVersion': _ytClientVersion,
          'hl': 'en',
          'gl': 'US',
        },
      },
      'query': query,
    });

    final http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: {
              'User-Agent': _browserUserAgent,
              'Content-Type': 'application/json',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 12));
    } catch (e) {
      debugPrint('[Enrich] yt-search error $e');
      return const [];
    }
    if (response.statusCode != 200) {
      debugPrint('[Enrich] yt-search status ${response.statusCode}');
      return const [];
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
    } catch (_) {
      return const [];
    }
    if (decoded is! Map<String, dynamic>) return const [];

    Object? sections = decoded['contents'];
    if (sections is Map<String, dynamic>) {
      sections = sections['sectionListRenderer'];
    } else {
      return const [];
    }
    if (sections is! Map<String, dynamic>) return const [];
    final sectionList = sections['contents'];
    if (sectionList is! List) return const [];

    final out = <_YouTubeCandidate>[];
    for (final section in sectionList) {
      if (section is! Map<String, dynamic>) continue;
      final itemSection = section['itemSectionRenderer'];
      if (itemSection is! Map<String, dynamic>) continue;
      final items = itemSection['contents'];
      if (items is! List) continue;
      for (final item in items) {
        if (item is! Map<String, dynamic>) continue;
        Map<String, dynamic>? vr;
        for (final key in [
          'compactVideoRenderer',
          'videoRenderer',
          'videoWithContextRenderer',
        ]) {
          final v = item[key];
          if (v is Map<String, dynamic>) {
            vr = v;
            break;
          }
        }
        if (vr == null) continue;
        final videoId = vr['videoId']?.toString() ?? '';
        if (videoId.isEmpty) continue;
        final title = _ytRunsText(vr['title']) ??
            vr['headline']?.toString() ??
            '';
        var channel = '';
        for (final key in ['ownerText', 'longBylineText', 'shortBylineText']) {
          final text = _ytRunsText(vr[key]);
          if (text != null && text.isNotEmpty) {
            channel = text;
            break;
          }
        }
        final lengthSeconds = _ytLengthSeconds(vr['lengthText']);
        if (title.trim().isEmpty || lengthSeconds <= 0) continue;
        out.add(_YouTubeCandidate(
          videoId: videoId,
          title: title.trim(),
          channel: channel.trim(),
          lengthSeconds: lengthSeconds,
        ));
        if (out.length >= 12) return out;
      }
    }
    return out;
  }

  Future<_YouTubeStream?> _ytAudioStream(String videoId) async {
    final uri = Uri.https(
      'www.youtube.com',
      '/youtubei/v1/player',
      {'key': _ytKey, 'prettyPrint': 'false'},
    );
    final body = jsonEncode({
      'context': {
        'client': {
          'clientName': 'ANDROID',
          'clientVersion': _ytClientVersion,
          'hl': 'en',
          'gl': 'US',
        },
      },
      'videoId': videoId,
      'contentCheckOk': true,
      'racyCheckOk': true,
    });

    final http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: {
              'User-Agent': _browserUserAgent,
              'Content-Type': 'application/json',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 12));
    } catch (e) {
      debugPrint('[Enrich] yt-player $videoId error $e');
      return null;
    }
    if (response.statusCode != 200) {
      debugPrint('[Enrich] yt-player $videoId status ${response.statusCode}');
      return null;
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
    } catch (_) {
      debugPrint('[Enrich] yt-player $videoId bad json');
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;

    final playability = decoded['playabilityStatus'];
    if (playability is Map<String, dynamic>) {
      if (playability['status']?.toString() != 'OK') {
        debugPrint('[Enrich] yt-player $videoId playability '
            '${playability['status']} reason=${playability['reason']}');
        return null;
      }
    }
    final streamingData = decoded['streamingData'];
    if (streamingData is! Map<String, dynamic>) {
      debugPrint('[Enrich] yt-player $videoId no streamingData');
      return null;
    }
    final formats = streamingData['adaptiveFormats'];
    if (formats is! List) {
      debugPrint('[Enrich] yt-player $videoId no formats');
      return null;
    }

    String bestUrl = '';
    var bestBitrate = -1;
    var fallbackUrl = '';
    var fallbackBitrate = -1;
    for (final f in formats) {
      if (f is! Map<String, dynamic>) continue;
      final mime = f['mimeType']?.toString() ?? '';
      if (!mime.startsWith('audio/')) continue;
      final url = f['url']?.toString() ?? '';
      if (url.isEmpty) continue;
      final bitrate = f['bitrate'] is int
          ? f['bitrate'] as int
          : int.tryParse(f['bitrate']?.toString() ?? '') ?? 0;
      if (mime.startsWith('audio/mp4')) {
        if (bitrate > bestBitrate) {
          bestBitrate = bitrate;
          bestUrl = url;
        }
      } else if (bitrate > fallbackBitrate) {
        fallbackBitrate = bitrate;
        fallbackUrl = url;
      }
    }
    final url = bestUrl.isNotEmpty ? bestUrl : fallbackUrl;
    if (url.isEmpty) return null;

    var lengthSeconds = 0;
    final details = decoded['videoDetails'];
    if (details is Map<String, dynamic>) {
      final raw = details['lengthSeconds'];
      lengthSeconds = raw is int
          ? raw
          : int.tryParse(raw?.toString() ?? '') ?? 0;
    }
    return _YouTubeStream(url: url, lengthSeconds: lengthSeconds);
  }

  static String? _ytRunsText(Object? value) {
    if (value is String) return value;
    if (value is! Map<String, dynamic>) return null;
    final simple = value['simpleText'];
    if (simple is String && simple.isNotEmpty) return simple;
    final accessibility = value['accessibility'];
    if (accessibility is Map<String, dynamic>) {
      final label = accessibility['accessibilityData'];
      if (label is Map<String, dynamic>) {
        final text = label['label'];
        if (text is String && text.isNotEmpty) return text;
      }
    }
    final runs = value['runs'];
    if (runs is! List || runs.isEmpty) return null;
    final text = runs
        .whereType<Map<String, dynamic>>()
        .map((r) => r['text']?.toString() ?? '')
        .join();
    return text.isEmpty ? null : text;
  }

  static int _ytLengthSeconds(Object? value) {
    String? raw;
    if (value is String) {
      raw = value;
    } else if (value is Map<String, dynamic>) {
      final simple = value['simpleText'];
      if (simple is String && simple.trim().isNotEmpty) {
        raw = simple;
      } else {
        final runs = value['runs'];
        if (runs is List) {
          final buffer = StringBuffer();
          for (final run in runs) {
            if (run is Map<String, dynamic>) {
              final text = run['text'];
              if (text is String) buffer.write(text);
            }
          }
          if (buffer.isNotEmpty) raw = buffer.toString();
        }
      }
      if (raw == null || raw.trim().isEmpty) {
        raw = _ytAccessibilityDurationLabel(value['accessibility']);
      }
    }
    if (raw == null || raw.trim().isEmpty) return 0;
    final trimmed = raw.trim();
    if (trimmed.contains(':')) {
      final parts = trimmed.split(':');
      var total = 0;
      for (final part in parts) {
        final n = int.tryParse(part.trim());
        if (n == null) return 0;
        total = total * 60 + n;
      }
      return total;
    }
    return _ytSpokenDurationSeconds(trimmed);
  }

  static String? _ytAccessibilityDurationLabel(Object? accessibility) {
    if (accessibility is! Map<String, dynamic>) return null;
    final data = accessibility['accessibilityData'];
    if (data is! Map<String, dynamic>) return null;
    final label = data['label'];
    return label is String && label.trim().isNotEmpty ? label : null;
  }

  static int _ytSpokenDurationSeconds(String label) {
    var total = 0;
    var matched = false;
    final hour = RegExp(r'(\d+)\s*hours?', caseSensitive: false);
    final minute = RegExp(r'(\d+)\s*minutes?', caseSensitive: false);
    final second = RegExp(r'(\d+)\s*seconds?', caseSensitive: false);
    final h = hour.firstMatch(label);
    if (h != null) {
      total += int.parse(h.group(1)!) * 3600;
      matched = true;
    }
    final m = minute.firstMatch(label);
    if (m != null) {
      total += int.parse(m.group(1)!) * 60;
      matched = true;
    }
    final s = second.firstMatch(label);
    if (s != null) {
      total += int.parse(s.group(1)!);
      matched = true;
    }
    return matched ? total : 0;
  }

  Future<_PreviewHit?> _fetchITunesPreview({
    required String title,
    required String artist,
  }) async {
    final query = '${_cleanQuery(title)} ${_cleanQuery(artist)}'.trim();
    if (query.isEmpty) return null;

    final uri = Uri.https('itunes.apple.com', '/search', {
      'term': query,
      'media': 'music',
      'entity': 'song',
      'limit': '8',
    });

    final http.Response response;
    try {
      response = await _client
          .get(uri, headers: {'User-Agent': _browserUserAgent}).timeout(
                const Duration(seconds: 12),
              );
    } catch (_) {
      return null;
    }
    if (response.statusCode != 200) return null;

    final Map<String, dynamic> decoded;
    try {
      decoded =
          jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true))
              as Map<String, dynamic>;
    } catch (_) {
      return null;
    }

    final results = decoded['results'];
    if (results is! List || results.isEmpty) return null;

    final wantTitle = _normalize(title);
    final wantArtist = _normalize(artist);

    _PreviewHit? fallback;
    var bestScore = -1;
    _PreviewHit? best;

    for (final item in results) {
      if (item is! Map<String, dynamic>) continue;
      final previewUrl = item['previewUrl'];
      if (previewUrl is! String || previewUrl.isEmpty) continue;

      final hitTitle = _normalize(item['trackName']?.toString() ?? '');
      final hitArtist = _normalize(item['artistName']?.toString() ?? '');
      if (hitTitle.isEmpty) continue;

      final rawTitle = (item['trackName']?.toString() ?? '').toLowerCase();
      final rawArtist = (item['artistName']?.toString() ?? '').toLowerCase();
      final combined = '$rawTitle $rawArtist';

      if (isNonStudioVariant(combined, '$title $artist')) continue;

      if (wantArtist.isNotEmpty) {
        final artistMatches = hitArtist == wantArtist ||
            hitArtist.contains(wantArtist) ||
            wantArtist.contains(hitArtist);
        if (!artistMatches) continue;
      }

      final hit = _PreviewHit(
        previewUrl: previewUrl,
        artworkUrl: _hiResArtwork(item['artworkUrl100']),
        duration: _durationFromMs(item['trackTimeMillis']),
      );

      fallback ??= hit;

      var score = 0;
      if (hitTitle == wantTitle) {
        score += 4;
      } else if (wantTitle.isNotEmpty &&
          (hitTitle.contains(wantTitle) || wantTitle.contains(hitTitle))) {
        score += 2;
      } else {
        continue;
      }
      if (wantArtist.isNotEmpty) {
        score += 3;
      }
      final kind = (item['kind']?.toString() ?? '').toLowerCase();
      if (kind == 'song') score += 1;

      if (score > bestScore) {
        bestScore = score;
        best = hit;
      }
    }

    return best ?? fallback;
  }

  Future<_PreviewHit?> _fetchDeezerPreview({
    required String title,
    required String artist,
  }) async {
    final query = '${_cleanQuery(title)} ${_cleanQuery(artist)}'.trim();
    if (query.isEmpty) return null;

    final uri = Uri.https('api.deezer.com', '/search', {'q': query});

    final http.Response response;
    try {
      response = await _client
          .get(uri, headers: {'User-Agent': _browserUserAgent}).timeout(
                const Duration(seconds: 12),
              );
    } catch (_) {
      return null;
    }
    if (response.statusCode != 200) return null;

    final Map<String, dynamic> decoded;
    try {
      decoded =
          jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true))
              as Map<String, dynamic>;
    } catch (_) {
      return null;
    }

    final results = decoded['data'];
    if (results is! List || results.isEmpty) return null;

    final wantTitle = _normalize(title);
    final wantArtist = _normalize(artist);

    var bestScore = -1;
    _PreviewHit? best;

    for (final item in results) {
      if (item is! Map<String, dynamic>) continue;
      final previewUrl = item['preview'];
      if (previewUrl is! String || previewUrl.isEmpty) continue;

      final hitTitle = _normalize(item['title']?.toString() ?? '');
      Object? artistObj = item['artist'];
      final hitArtist = _normalize(
        artistObj is Map ? (artistObj['name']?.toString() ?? '') : '',
      );
      if (hitTitle.isEmpty) continue;

      final rawTitle = (item['title']?.toString() ?? '').toLowerCase();
      final rawArtist = (artistObj is Map ? (artistObj['name']?.toString() ?? '') : '').toLowerCase();
      final combined = '$rawTitle $rawArtist';

      if (isNonStudioVariant(combined, '$title $artist')) continue;

      if (wantArtist.isNotEmpty) {
        final artistMatches = hitArtist == wantArtist ||
            hitArtist.contains(wantArtist) ||
            wantArtist.contains(hitArtist);
        if (!artistMatches) continue;
      }

      String? artwork;
      final album = item['album'];
      if (album is Map) {
        final xl = album['cover_xl'] ?? album['cover_big'] ?? album['cover'];
        if (xl is String && xl.isNotEmpty) artwork = xl;
      }

      final hit = _PreviewHit(previewUrl: previewUrl, artworkUrl: artwork);

      var score = 0;
      if (hitTitle == wantTitle) {
        score += 4;
      } else if (wantTitle.isNotEmpty &&
          (hitTitle.contains(wantTitle) || wantTitle.contains(hitTitle))) {
        score += 2;
      } else {
        continue;
      }
      if (wantArtist.isNotEmpty) {
        score += 3;
      }
      if (score > bestScore) {
        bestScore = score;
        best = hit;
      }
    }

    return best;
  }

  /// Full-length hunt: the archive catalog and YouTube race concurrently
  /// (archive URLs are permanent, so an archive hit wins); DuckDuckGo
  /// direct-audio follows. Each leg is capped: without caps, a slow
  /// network burns minutes across sequential timeouts (seen live: 165s).
  Future<_PreviewHit?> _fetchWebFullAudio({
    required String title,
    required String artist,
    Duration? duration,
  }) async {
    try {
      final results = await Future.wait([
        _fetchArchiveOrgFullAudio(
          title: title,
          artist: artist,
          duration: duration,
        ).timeout(const Duration(seconds: 45)),
        _fetchYouTubeFullAudio(
          title: title,
          artist: artist,
          duration: duration,
        ).timeout(const Duration(seconds: 60)),
      ]);
      final archive = results[0];
      if (archive != null) {
        debugPrint('[Enrich] webyt archive HIT ${Uri.tryParse(archive.previewUrl)?.host}');
        return archive;
      }
      final yt = results[1];
      if (yt != null) {
        debugPrint('[Enrich] webyt youtube HIT');
        return yt;
      }
      debugPrint('[Enrich] webyt miss');
    } catch (e) {
      debugPrint('[Enrich] webyt error $e');
    }
    try {
      return await _fetchSearchEngineFullAudio(
        title: title,
        artist: artist,
        wantSeconds: duration?.inSeconds ?? 0,
      ).timeout(const Duration(seconds: 25));
    } catch (_) {
      return null;
    }
  }

  static const _minPlausibleFullTrackBytes = 900000;

  Future<_PreviewHit?> _fetchArchiveOrgFullAudio({
    required String title,
    required String artist,
    Duration? duration,
  }) async {
    final cleanTitle = _cleanQuery(title);
    if (cleanTitle.isEmpty) return null;
    final coolDown = _archiveCoolDownUntil;
    if (coolDown != null && DateTime.now().isBefore(coolDown)) return null;
    final cleanArtist = _cleanQuery(artist);

    final wantTitle = _normalize(title);
    final wantArtist = _normalize(artist);
    final wantSeconds = duration?.inSeconds ?? 0;

    final queries = <String>[
      if (cleanArtist.isNotEmpty) 'title:("$cleanTitle") AND creator:("$cleanArtist")',
      'title:("$cleanTitle")',
      if (cleanArtist.isNotEmpty) '"$cleanTitle" AND "$cleanArtist"',
      '"$cleanTitle"',
    ];

    final seen = <String>{};
    for (final query in queries) {
      final identifiers = await _archiveSearch(query);
      for (final identifier in identifiers) {
        if (!seen.add(identifier)) continue;
        final hit = await _archiveItemAudio(
          identifier: identifier,
          wantTitle: wantTitle,
          wantArtist: wantArtist,
          wantSeconds: wantSeconds,
        );
        if (hit != null) return hit;
      }
      if (seen.length >= 8) break;
    }
    return null;
  }

  Future<List<String>> _archiveSearch(String query) async {
    final uri = Uri.https('archive.org', '/advancedsearch.php', {
      'q': query,
      'fl[]': 'identifier',
      'rows': '6',
      'page': '1',
      'output': 'json',
      'sort[]': 'downloads desc',
    });

    final http.Response response;
    try {
      response = await _client
          .get(uri, headers: {'User-Agent': _browserUserAgent}).timeout(
                const Duration(seconds: 8),
              );
    } catch (_) {
      return const [];
    }
    if (response.statusCode != 200) return const [];

    final Object? decoded;
    try {
      decoded = jsonDecode(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
    } catch (_) {
      return const [];
    }
    if (decoded is! Map<String, dynamic>) return const [];
    final searchResponse = decoded['response'];
    if (searchResponse is! Map<String, dynamic>) return const [];
    final docs = searchResponse['docs'];
    if (docs is! List) return const [];

    final out = <String>[];
    for (final doc in docs) {
      if (doc is! Map<String, dynamic>) continue;
      final id = doc['identifier']?.toString() ?? '';
      if (id.isNotEmpty) out.add(id);
    }
    return out;
  }

  Future<_PreviewHit?> _archiveItemAudio({
    required String identifier,
    required String wantTitle,
    required String wantArtist,
    required int wantSeconds,
  }) async {
    final meta = await _getJsonMap(
      Uri(scheme: 'https', host: 'archive.org', path: '/metadata/$identifier'),
    );
    if (meta == null) return null;

    final details = meta['metadata'];
    final itemTitle = details is Map<String, dynamic>
        ? _normalize(_firstString(details['title']) ?? '')
        : '';
    if (itemTitle.isEmpty ||
        !(itemTitle == wantTitle ||
            itemTitle.contains(wantTitle) ||
            wantTitle.contains(itemTitle))) {
      return null;
    }
    if (itemTitle.contains('playlist') ||
        itemTitle.contains('compilation') ||
        itemTitle.contains('megamix') ||
        itemTitle.contains('(mix)') ||
        itemTitle.contains(' dj mix') ||
        itemTitle.endsWith(' mix')) {
      return null;
    }

    final itemCreator =
        details is Map<String, dynamic> ? _archiveCreator(details['creator']) : '';
    if (wantArtist.isNotEmpty) {
      if (itemCreator.isEmpty) {
        if (!itemTitle.contains(wantArtist)) return null;
      } else {
        final creator = _normalize(itemCreator);
        if (!(creator == wantArtist ||
            creator.contains(wantArtist) ||
            wantArtist.contains(creator))) {
          return null;
        }
      }
    }

    final files = meta['files'];
    if (files is! List) return null;

    String? bestUrl;
    Duration? bestDuration;
    var bestBytes = -1;

    for (final file in files) {
      if (file is! Map<String, dynamic>) continue;
      final name = file['name']?.toString() ?? '';
      if (name.isEmpty) continue;
      final lower = name.toLowerCase();
      const audioExtensions = ['mp3', 'ogg', 'oga', 'flac', 'm4a', 'mp4', 'wav'];
      if (!audioExtensions.contains(lower.split('.').last)) continue;
      if (lower.contains('sample') || lower.contains('preview')) continue;

      final bytes = int.tryParse(file['size']?.toString() ?? '') ?? 0;
      final fileDuration = _archiveLength(file['length']);

      if (isNonStudioVariant('$name $itemTitle', '$wantTitle $wantArtist')) {
        continue;
      }

      // Album siblings: other real songs in the same item (e.g. the rest
      // of an album) are recorded independent of this track's duration
      // window so one hit can resolve many tracks.
      if (_archiveSiblings.length < 24 &&
          (fileDuration == null || fileDuration.inSeconds >= 60)) {
        final key = siblingKey(name);
        if (key.isNotEmpty) {
          _archiveSiblings.putIfAbsent(
            key,
            () => (
              url: 'https://archive.org/download/$identifier/'
                  '${name.split('/').map(Uri.encodeComponent).join('/')}',
              seconds: fileDuration?.inSeconds ?? -1,
            ),
          );
        }
      }

      if (fileDuration != null) {
        if (fileDuration.inSeconds < 60) continue;
        if (wantSeconds > 60) {
          final secs = fileDuration.inSeconds;
          if (secs < (wantSeconds * 75) ~/ 100 ||
              secs > (wantSeconds * 160) ~/ 100) {
            continue;
          }
        }
      } else if (wantSeconds > 60) {
        continue;
      } else if (bytes < _minPlausibleFullTrackBytes) {
        continue;
      }

      final score =
          (fileDuration?.inSeconds ?? 0) * 1000 + bytes.clamp(0, 999);
      if (score <= bestBytes) continue;
      bestBytes = score;
      bestDuration = fileDuration;
      bestUrl = 'https://archive.org/download/$identifier/'
          '${name.split('/').map(Uri.encodeComponent).join('/')}';
    }

    if (bestUrl == null) return null;
    final bytesServed = await _probeAudioUrl(bestUrl);
    if (bytesServed == null) return null;
    if (bestDuration == null && bytesServed > 0 && bytesServed < _minPlausibleFullTrackBytes) {
      return null;
    }

    return _PreviewHit(
      previewUrl: bestUrl,
      artworkUrl: 'https://archive.org/services/img/$identifier',
      duration: bestDuration,
      isFullLength: true,
    );
  }

  Future<_PreviewHit?> _fetchSearchEngineFullAudio({
    required String title,
    required String artist,
    int wantSeconds = 0,
  }) async {
    final cleanTitle = _cleanQuery(title);
    if (cleanTitle.isEmpty) return null;
    final wantTitle = _normalize(title);

    final queries = <String>[
      '"$cleanTitle" "${_cleanQuery(artist)}" mp3 full song',
      '"$cleanTitle" "${_cleanQuery(artist)}" audio',
      if (_cleanQuery(artist).isEmpty) '"$cleanTitle" mp3 full song',
    ];

    final candidates = <String>[];
    final seenText = <String>{};
    for (final query in queries) {
      final results = await _duckDuckGoSearch(query);
      for (final result in results) {
        if (candidates.length >= 6) break;
        if (!_isAllowlistedAudioHost(result.url)) continue;
        final text = _normalize(result.title);
        if (text.isEmpty ||
            !(text.contains(wantTitle) || wantTitle.contains(text))) {
          continue;
        }
        if (seenText.add(result.url)) candidates.add(result.url);
      }
      if (candidates.isNotEmpty) break;
    }

    for (final url in candidates) {
      final bytes = await _probeAudioUrl(url);
      if (bytes == null) continue;
      if (wantSeconds > 60) {
        if (bytes <= 0) continue;
        final estSeconds = bytes ~/ 16000;
        if (estSeconds < (wantSeconds * 75) ~/ 100 ||
            estSeconds > (wantSeconds * 160) ~/ 100) {
          continue;
        }
      }
      return _PreviewHit(
        previewUrl: url,
        duration: null,
        isFullLength: true,
      );
    }
    return null;
  }

  static bool _isAllowlistedAudioHost(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.isAbsolute) return false;
    final host = uri.host.toLowerCase();
    if (host.isEmpty) return false;
    return host == 'archive.org' ||
        host.endsWith('.archive.org') ||
        host.endsWith('archive.org') ||
        host.endsWith('.jamendo.com') ||
        host.endsWith('freemusicarchive.org') ||
        host.endsWith('musopen.org') ||
        host.endsWith('freepd.com') ||
        host.endsWith('incompetech.com') ||
        host.endsWith('ccmixter.org') ||
        host.endsWith('opsound.org');
  }

  static final _ddgLinkRegExp = RegExp(
    r'<a[^>]*href="([^"]+)"[^>]*>(.*?)</a>',
    dotAll: true,
  );

  Future<List<({String url, String title})>> _duckDuckGoSearch(
    String query,
  ) async {
    final uri = Uri.https('lite.duckduckgo.com', '/lite/', {'q': query});

    final http.Response response;
    try {
      response = await _client
          .get(uri, headers: {'User-Agent': _browserUserAgent}).timeout(
                const Duration(seconds: 8),
              );
    } catch (_) {
      return const [];
    }
    if (response.statusCode != 200) return const [];

    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    final out = <({String url, String title})>[];
    for (final match in _ddgLinkRegExp.allMatches(body)) {
      if (out.length >= 12) break;
      final href = _resolveDdgHref(match.group(1) ?? '');
      if (href == null) continue;
      final text = _stripHtml(match.group(2) ?? '').trim();
      out.add((url: href, title: text));
    }
    return out;
  }

  static String? _resolveDdgHref(String href) {
    final raw = href.trim();
    if (raw.isEmpty) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null) return null;
    if (uri.host.contains('duckduckgo.com')) {
      final target = uri.queryParameters['uddg'];
      if (target == null || target.isEmpty) return null;
      return Uri.tryParse(target)?.toString();
    }
    if (uri.isAbsolute &&
        (uri.scheme == 'http' || uri.scheme == 'https')) {
      return uri.toString();
    }
    return null;
  }

  static String _stripHtml(String value) {
    return value
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#x27;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String? _firstString(Object? value) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    if (value is List && value.isNotEmpty) {
      final first = value.first;
      if (first is String && first.trim().isNotEmpty) return first.trim();
    }
    return null;
  }

  static String _archiveCreator(Object? value) {
    if (value is String) return value;
    if (value is List) {
      return value.whereType<String>().join(', ');
    }
    return '';
  }

  static Duration? _archiveLength(Object? value) {
    if (value == null) return null;
    final raw = value.toString().trim();
    if (raw.isEmpty) return null;
    if (raw.contains(':')) {
      var total = 0;
      for (final part in raw.split(':')) {
        final n = int.tryParse(part.trim());
        if (n == null) return null;
        total = total * 60 + n;
      }
      return total > 0 ? Duration(seconds: total) : null;
    }
    final seconds = double.tryParse(raw);
    if (seconds == null || seconds <= 0) return null;
    return Duration(seconds: seconds.round());
  }

  Future<int?> _probeAudioUrl(String url) async {
    final parsed = Uri.tryParse(url);
    if (parsed == null || !parsed.isAbsolute) return null;
    final isGoogleVideo = parsed.host.contains('googlevideo.com');
    if (isGoogleVideo && googlevideoCoolingDown) return null;

    void noteThrottle(int status) {
      if (isGoogleVideo && (status == 403 || status == 429)) {
        noteGooglevideoThrottle();
      }
    }

    try {
      final head = await _client
          .head(parsed, headers: {'User-Agent': _browserUserAgent})
          .timeout(const Duration(seconds: 6));
      if (head.statusCode >= 200 && head.statusCode < 400) {
        final contentType = head.headers['content-type'] ?? '';
        if (!_looksLikeAudio(contentType)) {
          debugPrint('[Enrich] probe HEAD not-audio $contentType $url');
          return null;
        }
        return int.tryParse(head.headers['content-length'] ?? '') ?? 0;
      }
      debugPrint('[Enrich] probe HEAD ${head.statusCode} $url');
      noteThrottle(head.statusCode);
      if (head.statusCode != 403 &&
          head.statusCode != 405 &&
          head.statusCode != 501) {
        return null;
      }
      // else fall through to the Range GET (googlevideo often 403s HEAD
      // while serving Range GETs fine).
    } catch (e) {
      debugPrint('[Enrich] probe HEAD error $e $url');
    }

    try {
      final request = http.Request('GET', parsed);
      request.headers['User-Agent'] = _browserUserAgent;
      request.headers['Range'] = 'bytes=0-1';
      final streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 6));
      final ok = (streamed.statusCode == 200 || streamed.statusCode == 206) &&
          _looksLikeAudio(streamed.headers['content-type'] ?? '');
      await streamed.stream.take(1).drain<void>();
      if (!ok) {
        debugPrint('[Enrich] probe GET ${streamed.statusCode} '
            '${streamed.headers['content-type']} $url');
        noteThrottle(streamed.statusCode);
        return null;
      }
      final contentRange = streamed.headers['content-range'];
      final total = contentRange != null && contentRange.contains('/')
          ? int.tryParse(contentRange.split('/').last.trim()) ?? 0
          : int.tryParse(streamed.headers['content-length'] ?? '') ?? 0;
      return total;
    } catch (e) {
      debugPrint('[Enrich] probe GET error $e $url');
      return null;
    }
  }

  static bool _looksLikeAudio(String contentType) {
    final ct = contentType.toLowerCase();
    return ct.startsWith('audio/') ||
        ct.contains('mpeg') ||
        ct.contains('mp4') ||
        ct.contains('ogg') ||
        ct.contains('flac') ||
        ct.contains('mp3') ||
        ct.contains('octet-stream');
  }

  Future<List<String>> _fetchLyrics({
    required String title,
    required String artist,
    String? album,
    Duration? duration,
  }) async {
    final hasArtist = artist.isNotEmpty &&
        artist.toLowerCase() != 'unknown artist' &&
        artist.toLowerCase() != 'spotify';
    final queries = hasArtist
        ? _lyricQueryVariants(title: title, artist: artist)
        : <({String title, String artist})>[];
    for (final q in queries) {
      try {
        final lrclib = await _fetchLyricsLrclib(
          title: q.title,
          artist: q.artist,
          album: album,
          duration: duration,
        );
        if (lrclib.isNotEmpty) return lrclib;
      } catch (_) {
        // try next variant
      }
    }
    for (final q in queries) {
      try {
        final ovh = await _fetchLyricsOvh(title: q.title, artist: q.artist);
        if (ovh.isNotEmpty) return ovh;
      } catch (_) {
        // try next variant / source
      }
    }
    final cleanTitle = _cleanQuery(title).trim();
    if (cleanTitle.isNotEmpty) {
      try {
        final byTitle = await _fetchLrclibSearchByQuery(cleanTitle);
        if (byTitle.isNotEmpty) return byTitle;
      } catch (_) {
        // no match
      }
    }
    return const [];
  }

  List<({String title, String artist})> _lyricQueryVariants({
    required String title,
    required String artist,
  }) {
    final out = <({String title, String artist})>[];
    void add(String t, String a) {
      t = t.trim();
      a = a.trim();
      if (t.isEmpty || a.isEmpty) return;
      if (!out.any((e) => e.title == t && e.artist == a)) {
        out.add((title: t, artist: a));
      }
    }

    add(title, artist);
    add(_cleanQuery(title), artist);
    add(_cleanQuery(title), _primaryArtist(artist));
    add(title, _primaryArtist(artist));
    return out;
  }

  static String _primaryArtist(String artist) {
    var a = artist
        .replaceAll(RegExp(r'\s+\(.*?\)'), '')
        .replaceAll(RegExp(r'\s*\[.*?\]'), '');
    for (final sep in [' feat ', ' ft ', ' featuring ', ' with ', ' & ', ', ', ' x ', ' X ']) {
      final idx = a.toLowerCase().indexOf(sep);
      if (idx > 0) {
        a = a.substring(0, idx);
        break;
      }
    }
    return a.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  Future<List<String>> _fetchLyricsOvh({
    required String title,
    required String artist,
  }) async {
    final uri = Uri(
      scheme: 'https',
      host: 'api.lyrics.ovh',
      pathSegments: ['v1', artist.trim(), title.trim()],
    );

    try {
      final response = await _client
          .get(uri, headers: {'User-Agent': _browserUserAgent}).timeout(
                const Duration(seconds: 12),
              );
      if (response.statusCode != 200) return const [];
      final decoded = jsonDecode(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
      if (decoded is! Map) return const [];
      final raw = decoded['lyrics'];
      if (raw is! String || raw.trim().isEmpty) return const [];
      final lines = _splitLyricLines(raw);
      debugPrint('Lyrics (ovh) for $title - $artist (${lines.length} lines)');
      return lines;
    } catch (_) {
      return const [];
    }
  }

  Future<List<String>> _fetchLyricsLrclib({
    required String title,
    required String artist,
    String? album,
    Duration? duration,
  }) async {
    try {
      final exact = await _fetchLrclibGet(
        title: title,
        artist: artist,
        album: album,
        duration: duration,
      );
      if (exact.isNotEmpty) return exact;
    } catch (_) {
      // fall through to search
    }
    try {
      return await _fetchLrclibSearch(title: title, artist: artist);
    } catch (_) {
      return const [];
    }
  }

  Future<List<String>> _fetchLrclibGet({
    required String title,
    required String artist,
    String? album,
    Duration? duration,
  }) async {
    final params = <String, String>{
      'artist_name': artist.trim(),
      'track_name': _cleanQuery(title),
    };
    final cleanAlbum = (album ?? '').trim();
    if (cleanAlbum.isNotEmpty) params['album_name'] = cleanAlbum;
    final seconds = duration?.inSeconds ?? 0;
    if (seconds > 0) params['duration'] = '$seconds';

    final uri = Uri.https('lrclib.net', '/api/get', params);
    final decoded = await _getJsonMap(uri);
    if (decoded == null) return const [];
    return _lyricsFromLrclibDoc(decoded, title: title, artist: artist);
  }

  Future<List<String>> _fetchLrclibSearch({
    required String title,
    required String artist,
  }) async {
    final cleaned = _cleanQuery(title);
    final attempts = <Map<String, String>>[
      {
        'artist_name': artist.trim(),
        'track_name': cleaned,
      },
      {
        'q': '$cleaned ${artist.trim()}'.trim(),
      },
    ];
    for (final params in attempts) {
      final lines = await _fetchLrclibSearchParams(params,
          title: title, artist: artist);
      if (lines.isNotEmpty) return lines;
    }
    return const [];
  }

  Future<List<String>> _fetchLrclibSearchByQuery(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final lines = await _fetchLrclibSearchParams({'q': q},
        title: q, artist: '');
    if (lines.isNotEmpty) return lines;
    return _fetchLrclibSearchParams({'track_name': q},
        title: q, artist: '');
  }

  Future<List<String>> _fetchLrclibSearchParams(
    Map<String, String> params, {
    required String title,
    required String artist,
  }) async {
    final uri = Uri.https('lrclib.net', '/api/search', params);
    final http.Response response;
    try {
      response = await _client
          .get(uri, headers: {'User-Agent': _browserUserAgent}).timeout(
                const Duration(seconds: 8),
              );
    } catch (e) {
      debugPrint('[Enrich] archive-search error $e');
      return const [];
    }
    if (response.statusCode != 200) {
      debugPrint('[Enrich] archive-search status ${response.statusCode}');
      if (response.statusCode == 429 || response.statusCode == 403) {
        _archiveCoolDownUntil =
            DateTime.now().add(const Duration(minutes: 5));
      }
      return const [];
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
    } catch (_) {
      return const [];
    }
    if (decoded is! List || decoded.isEmpty) return const [];
    for (final item in decoded) {
      if (item is! Map<String, dynamic>) continue;
      if (item['instrumental'] == true) continue;
      final synced = item['syncedLyrics'];
      if (synced is String && synced.trim().isNotEmpty) {
        final lines = _splitSyncedLines(synced);
        if (lines.isNotEmpty) return lines;
      }
    }
    for (final item in decoded) {
      if (item is! Map<String, dynamic>) continue;
      final lines = _lyricsFromLrclibDoc(item, title: title, artist: artist);
      if (lines.isNotEmpty) return lines;
    }
    return const [];
  }

  List<String> _lyricsFromLrclibDoc(
    Map<String, dynamic> decoded, {
    required String title,
    required String artist,
  }) {
    if (decoded['instrumental'] == true) return const [];

    final synced = decoded['syncedLyrics'];
    if (synced is String && synced.trim().isNotEmpty) {
      final lines = _splitSyncedLines(synced);
      if (lines.isNotEmpty) {
        debugPrint(
            'Lyrics (lrclib synced) for $title - $artist (${lines.length} lines)');
        return lines;
      }
    }
    
    final plain = decoded['plainLyrics'];
    if (plain is String && plain.trim().isNotEmpty) {
      final lines = _splitLyricLines(plain);
      if (lines.isNotEmpty) {
        debugPrint('Lyrics (lrclib) for $title - $artist (${lines.length} lines)');
        return lines;
      }
    }
    return const [];
  }

  Future<Map<String, dynamic>?> _getJsonMap(Uri uri) async {
    final http.Response response;
    try {
      response = await _client
          .get(uri, headers: {'User-Agent': _browserUserAgent}).timeout(
                const Duration(seconds: 12),
              );
    } catch (e) {
      debugPrint('[Enrich] json ${uri.host} error $e');
      return null;
    }
    if (response.statusCode != 200) {
      debugPrint('[Enrich] json ${uri.host} status ${response.statusCode}');
      if ((response.statusCode == 429 || response.statusCode == 403) &&
          uri.host.endsWith('archive.org')) {
        _archiveCoolDownUntil =
            DateTime.now().add(const Duration(minutes: 5));
      }
      return null;
    }
    try {
      final decoded = jsonDecode(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static List<String> _splitLyricLines(String raw) {
    return raw
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
  }

  static List<String> _splitSyncedLines(String synced) {
    final out = <String>[];
    for (final line in synced.split('\n')) {
      final text = line.trim();
      final content = text.replaceAll(RegExp(r'^\s*\[.*?\]'), '').trim();
      if (content.isNotEmpty) out.add(text);
    }
    return out;
  }

  static String _cleanQuery(String value) {
    var v = value
        .replaceAll(RegExp(r'\(.*?\)', multiLine: true), ' ')
        .replaceAll(RegExp(r'\[.*?\]'), ' ')
        .replaceAll(RegExp(r'\b(feat|ft|featuring)\b\.?.*$',
            caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return v;
  }

  static String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9 ]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String? _hiResArtwork(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return value.replaceFirst('100x100bb', '600x600bb');
  }

  static Duration? _durationFromMs(Object? value) {
    var ms = 0;
    if (value is int) {
      ms = value;
    } else if (value is num) {
      ms = value.toInt();
    }
    if (ms <= 0) return null;
    return Duration(milliseconds: ms);
  }

  void dispose() => _client.close();
}

class _YouTubeCandidate {
  final String videoId;
  final String title;
  final String channel;
  final int lengthSeconds;

  const _YouTubeCandidate({
    required this.videoId,
    required this.title,
    required this.channel,
    required this.lengthSeconds,
  });
}

class _YouTubeStream {
  final String url;
  final int lengthSeconds;

  const _YouTubeStream({required this.url, required this.lengthSeconds});
}

class _PreviewHit {
  final String previewUrl;
  final String? artworkUrl;
  final Duration? duration;
  final bool isFullLength;
  final bool isYouTube;

  const _PreviewHit({
    required this.previewUrl,
    this.artworkUrl,
    this.duration,
    this.isFullLength = false,
    this.isYouTube = false,
  });
}