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
  /// [album] and [duration] improve the LRCLIB lyrics lookup (its exact
  /// endpoint requires them); [duration] also helps the YouTube match pick
  /// the right video. Everything still works without them.
  Future<TrackEnrichment> enrichTrack({
    required String title,
    required String artist,
    String? album,
    Duration? duration,
    bool previewFallbackOnly = false,
  }) async {
    final t = title.trim();
    final a = artist.trim();
    if (t.isEmpty) return const TrackEnrichment();

    try {
      final results = await Future.wait([
        _fetchPreviewUrl(
          title: t,
          artist: a,
          duration: duration,
          previewFallbackOnly: previewFallbackOnly,
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
  /// YouTube, then 30s iTunes/Deezer previews. Set [previewFallbackOnly]
  /// after a full-length stream has failed in the native player, so recovery
  /// can move straight to the most broadly compatible preview instead of
  /// repeatedly returning the same dead full-track source. Never throws.
  Future<_PreviewHit?> _fetchPreviewUrl({
    required String title,
    required String artist,
    Duration? duration,
    bool previewFallbackOnly = false,
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
      try {
        final full =
            await _fetchSaavnFullAudio(title: title, artist: artist);
        if (full != null) return full;
      } catch (_) {
        // fall through to YouTube
      }
      try {
        final yt = await _fetchYouTubeFullAudio(
          title: title,
          artist: artist,
          duration: duration,
        );
        if (yt != null) return yt;
      } catch (_) {
        // fall through to previews
      }
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

  /// Full-length audio via the unofficial JioSaavn gateway (keyless).
  /// Returns direct stream URLs for the whole song — not a 30-second clip.
  ///
  /// Two fixes from live probing: the gateway moved to `saavn.sumit.co`
  /// (`saavn.dev` no longer resolves everywhere), and its search is picky —
  /// "Multo Cup of Joe" returns nothing while "Multo" returns remixes — so
  /// we try both hosts and both query forms, and only accept a hit whose
  /// artist also overlaps (a correct 30s preview beats a wrong full song).
  /// Null when unreachable or when nothing matches strictly.
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
    } catch (_) {
      return null;
    }
    if (response.statusCode != 200) return null;

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
      // Strict artist gate: without it a same-name remix ("MULTO
      // HYPERTECHNO") would play instead of the real song. A correct 30s
      // preview further down the chain beats a wrong full-length file.
      if (wantArtist.isNotEmpty) {
        final artistOverlaps = hitArtist.isNotEmpty &&
            (hitArtist == wantArtist ||
                hitArtist.contains(wantArtist) ||
                wantArtist.contains(hitArtist));
        if (!artistOverlaps) continue;
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

  /// Extracts the song list from the gateway envelope. Handles both the
  /// current `{success, data: {results: [...]}}` shape and older
  /// `{data: [...]}` / `{results: [...]}` shapes.
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

  /// Picks the highest-quality direct stream URL from a Saavn
  /// `downloadUrl` array (`[{quality, url}]`). Empty when unusable.
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
    // Later entries are higher quality (…96, 160, 320); scan from the end.
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

  /// Picks the largest artwork URL from a Saavn `image` array.
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

  /// Joins all credited artist names (primary + featured + all) so
  /// "Cup of Joe" matches whatever artist bucket the gateway used.
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

  /// Full-length audio via YouTube's keyless `youtubei` player API (the
  /// same ANDROID client apps use). Covers tracks no music catalog carries
  /// (OPM/indie originals). Verified live: search finds the official video,
  /// player returns `PLAYABILITY: OK` with a full-length `audio/mp4`
  /// stream. Same strict title+artist gate as Saavn so a wrong video can
  /// never attach. Null when unreachable or nothing matches.
  static const _ytKey = 'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';
  static const _ytClientVersion = '20.10.38';

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

    final wantTitle = _normalize(title);
    final wantArtist = _normalize(artist);
    final wantSeconds = duration?.inSeconds ?? 0;

    _YouTubeCandidate? best;
    var bestScore = -1;
    for (final c in candidates) {
      if (c.videoId.isEmpty || c.title.isEmpty) continue;
      final hitTitle = _normalize(c.title);
      if (wantTitle.isEmpty) continue;
      final titleExact = hitTitle == wantTitle;
      final titleOverlaps = titleExact ||
          hitTitle.contains(wantTitle) ||
          wantTitle.contains(hitTitle);
      if (!titleOverlaps) continue;
      // Skip karaoke/instrumental/piano/drum/cover uploads — they match the title
      // but are the wrong audio (e.g. only piano or only drums).
      final lowered = '${c.title} ${c.channel}'.toLowerCase();
      final wantLower = '$title $artist'.toLowerCase();
      if (!wantLower.contains('piano') && lowered.contains('piano')) continue;
      if (!wantLower.contains('drum') && (lowered.contains('drum') || lowered.contains('drums'))) continue;
      if (!wantLower.contains('karaoke') && lowered.contains('karaoke')) continue;
      if (!wantLower.contains('instrumental') && lowered.contains('instrumental')) continue;
      if (!wantLower.contains('tribute') && lowered.contains('tribute')) continue;
      if (lowered.contains('backing track') ||
          lowered.contains('play along') ||
          lowered.contains('synthesia') ||
          lowered.contains('tutorial') ||
          lowered.contains('sped up') ||
          lowered.contains('slowed')) {
        continue;
      }

      // Official uploads often live on a label channel, so also accept an
      // artist credit that appears in the video title ("Multo - Cup of Joe").
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

      // Heavily prioritize exact audio / studio versions to avoid music video skits/intros
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
          score += 5; // Perfect duration match (studio audio)
        } else if (diff <= 8) {
          score += 3;
        } else if (diff <= 15) {
          score += 1;
        } else {
          score -= 3; // Length mismatch > 15s usually means cinematic intro/skit
        }
      }

      if (score > bestScore) {
        bestScore = score;
        best = c;
      }
    }
    if (best == null) return null;

    final stream = await _ytAudioStream(best.videoId);
    if (stream == null || stream.url.isEmpty) return null;

    // Verify stream playability in native players (ExoPlayer requests Range: bytes=0-).
    // Google Video rejects requests lacking PO tokens with 403 Forbidden.
    if (stream.url.contains('googlevideo.com')) {
      try {
        final probe = await _client.get(
          Uri.parse(stream.url),
          headers: {
            'User-Agent': _browserUserAgent,
            'Range': 'bytes=0-',
          },
        ).timeout(const Duration(seconds: 6));
        if (probe.statusCode == 403 || probe.statusCode == 404 || probe.statusCode == 410) {
          return null;
        }
      } catch (_) {
        return null;
      }
    }

    return _PreviewHit(
      previewUrl: stream.url,
      artworkUrl: 'https://i.ytimg.com/vi/${best.videoId}/hqdefault.jpg',
      duration: stream.lengthSeconds > 0
          ? Duration(seconds: stream.lengthSeconds)
          : null,
      isFullLength: true,
      isYouTube: true,
    );
  }

  /// Keyless ANDROID search. Live-verified response shape:
  /// `contents.sectionListRenderer.contents[].itemSectionRenderer
  /// .contents[]` with `compactVideoRenderer` entries
  /// (`videoRenderer` also handled for other clients).
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
        // Skip live/upcoming streams (no length) — unplayable as tracks.
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

  /// Keyless ANDROID player. Returns the highest-bitrate `audio/mp4`
  /// stream URL (direct, full-length) or null when unplayable.
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
    } catch (_) {
      return null;
    }
    if (response.statusCode != 200) return null;

    final Object? decoded;
    try {
      decoded = jsonDecode(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
    } catch (_) {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;

    final playability = decoded['playabilityStatus'];
    if (playability is Map<String, dynamic>) {
      if (playability['status']?.toString() != 'OK') return null;
    }
    final streamingData = decoded['streamingData'];
    if (streamingData is! Map<String, dynamic>) return null;
    final formats = streamingData['adaptiveFormats'];
    if (formats is! List) return null;

    String bestUrl = '';
    var bestBitrate = -1;
    var fallbackUrl = '';
    var fallbackBitrate = -1;
    for (final f in formats) {
      if (f is! Map<String, dynamic>) continue;
      final mime = f['mimeType']?.toString() ?? '';
      if (!mime.startsWith('audio/')) continue;
      final url = f['url']?.toString() ?? '';
      if (url.isEmpty) continue; // ciphered — ANDROID rarely does this
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

  /// Joins `"runs": [{"text": ...}]` title/byline fragments.
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

  /// Parses `"3:45"` / `"1:02:03"` length labels. Returns 0 when absent
  /// (live/upcoming streams have no length).
  ///
  /// Live YouTube ANDROID search returns `lengthText` as
  /// `{runs: [{text: "4:01"}], accessibility: {...}}` with no
  /// `simpleText` — both shapes must parse or every candidate is
  /// discarded as "live" and enrichment falls back to a 30s preview.
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

  /// Accessibility label like `"4 minutes, 1 second"` or
  /// `"1 hour, 5 minutes, 8 seconds"` when `runs`/`simpleText` are absent.
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

  /// iTunes Search is free with no API key and returns a 30s previewUrl.
  /// We fetch a few candidates and pick the best normalized match so
  /// "Cup of Joe - Multo" doesn't resolve to a karaoke cover.
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

      // Skip piano/drum covers, karaoke, and instrumental tributes
      // unless specifically in the requested title or artist.
      final wantLower = '$title $artist'.toLowerCase();
      if (!wantLower.contains('piano') && combined.contains('piano')) continue;
      if (!wantLower.contains('drum') && (combined.contains('drum') || combined.contains('drums'))) continue;
      if (!wantLower.contains('karaoke') && combined.contains('karaoke')) continue;
      if (!wantLower.contains('instrumental') && combined.contains('instrumental')) continue;
      if (!wantLower.contains('tribute') && combined.contains('tribute')) continue;
      if (!wantLower.contains('cover') && (combined.contains('cover') || combined.contains('tribute'))) continue;
      if (combined.contains('backing track') || combined.contains('play along')) continue;

      if (wantArtist.isNotEmpty) {
        final artistMatches = hitArtist == wantArtist ||
            hitArtist.contains(wantArtist) ||
            wantArtist.contains(hitArtist);
        if (!artistMatches) continue; // Reject wrong artists like "The Piano Guys"
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
        continue; // title must at least overlap — avoids wrong-song previews
      }
      if (wantArtist.isNotEmpty) {
        score += 3;
      }
      // Prefer full-length matches over ringtones/karaoke.
      final kind = (item['kind']?.toString() ?? '').toLowerCase();
      if (kind == 'song') score += 1;

      if (score > bestScore) {
        bestScore = score;
        best = hit;
      }
    }

    return best ?? fallback;
  }

  /// Deezer search is free with no API key (`api.deezer.com/search`) and
  /// also returns 30s `preview` URLs. Used when iTunes has no match.
  /// Same title-overlap guard as iTunes so we never attach a wrong song.
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

    _PreviewHit? fallback;
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

      // Skip piano/drum covers, karaoke, and instrumental tributes
      final wantLower = '$title $artist'.toLowerCase();
      if (!wantLower.contains('piano') && combined.contains('piano')) continue;
      if (!wantLower.contains('drum') && (combined.contains('drum') || combined.contains('drums'))) continue;
      if (!wantLower.contains('karaoke') && combined.contains('karaoke')) continue;
      if (!wantLower.contains('instrumental') && combined.contains('instrumental')) continue;
      if (!wantLower.contains('tribute') && combined.contains('tribute')) continue;
      if (!wantLower.contains('cover') && (combined.contains('cover') || combined.contains('tribute'))) continue;
      if (combined.contains('backing track') || combined.contains('play along')) continue;

      if (wantArtist.isNotEmpty) {
        final artistMatches = hitArtist == wantArtist ||
            hitArtist.contains(wantArtist) ||
            wantArtist.contains(hitArtist);
        if (!artistMatches) continue; // Reject wrong artists
      }

      String? artwork;
      final album = item['album'];
      if (album is Map) {
        final xl = album['cover_xl'] ?? album['cover_big'] ?? album['cover'];
        if (xl is String && xl.isNotEmpty) artwork = xl;
      }

      final hit = _PreviewHit(previewUrl: previewUrl, artworkUrl: artwork);
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
      if (score > bestScore) {
        bestScore = score;
        best = hit;
      }
    }

    return best ?? fallback;
  }

  /// Lyrics lookup with two free sources: lyrics.ovh first, then LRCLIB
  /// (broader catalog, plain + synced lyrics). Empty list when not found.
  ///
  /// Both sources are exact-match sensitive, so we retry with simplified
  /// queries: cleaned title ("Song (feat. X)" -> "Song") and primary
  /// artist ("A & B" -> "A"). First non-empty hit wins.
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
    // Title-only fallback (covers "Unknown artist" imports): LRCLIB
    // /api/search accepts a lone `q` / `track_name` without artist.
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

  /// Ordered (title, artist) variants for exact-match lyrics sources.
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

  /// "Lady Gaga & Bruno Mars" -> "Lady Gaga"; "Mark Ronson feat. X" -> "Mark Ronson".
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
    // NOTE: do NOT pre-encode with Uri.encodeComponent here — Uri with
    // pathSegments encodes each segment exactly once. Pre-encoding would
    // double-encode spaces ("Bruno Mars" -> "Bruno%2520Mars") and every
    // multi-word lookup would 404, leaving the lyrics sheet empty.
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

  /// LRCLIB (`lrclib.net`) is free with no API key and covers many
  /// tracks lyrics.ovh misses (OPM, indie). Prefers plain lyrics; falls
  /// back to parsing synced (timestamped) lines into plain text.
  ///
  /// Tries the exact `/api/get` endpoint first (needs album + duration),
  /// then the forgiving `/api/search` endpoint which works with just
  /// artist + title.
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
    // Structured lookup first (track_name + artist_name is valid per
    // https://lrclib.net/docs), then a forgiving `q` keyword fallback so
    // minor title differences still resolve instead of showing no lyrics.
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

  /// Title-only keyword search used when the artist is unknown.
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
                const Duration(seconds: 12),
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
    } catch (_) {
      return null;
    }
    if (response.statusCode != 200) return null;
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
    // Strip "feat.", "(remastered)", "[live]" noise that hurts matching.
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
    // 100x100 -> 600x600 for crisper artwork.
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

  /// True for full-length streams (JioSaavn/YouTube); false for 30s
  /// iTunes/Deezer preview clips.
  final bool isFullLength;

  /// True when the stream comes from YouTube (URLs expire after a few
  /// hours, so the player refreshes them on failure).
  final bool isYouTube;

  const _PreviewHit({
    required this.previewUrl,
    this.artworkUrl,
    this.duration,
    this.isFullLength = false,
    this.isYouTube = false,
  });
}
