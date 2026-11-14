import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import 'spotify_import_service.dart';

/// A playlist recovered from a Spotify "Download your data" export.
class SpotifyExportPlaylist {
  final String name;
  final List<SpotifyImportedTrack> tracks;

  /// True for the synthetic "Liked Songs" playlist built from the
  /// `tracks` array of `YourLibrary.json`.
  final bool isLikedSongs;

  const SpotifyExportPlaylist({
    required this.name,
    required this.tracks,
    this.isLikedSongs = false,
  });

  int get trackCount => tracks.length;
}

/// Everything usable that was found inside a Spotify data export.
class SpotifyExportBundle {
  final List<SpotifyExportPlaylist> playlists;

  /// Podcast episodes found in playlists or in the saved library. They are
  /// counted but never imported because Pulse is a music player.
  final int skippedEpisodes;

  /// Playlist rows that Spotify could not resolve (removed/unavailable
  /// tracks) or that point at user-uploaded local files.
  final int skippedUnavailable;

  /// Saved albums and followed artists. The export only lists their names
  /// and URIs, not their tracks, so they cannot be expanded offline.
  final int savedAlbums;
  final int followedArtists;

  /// Playlists that contained no importable music track.
  final int emptyPlaylists;

  /// Playlists whose names collided and were given a numeric suffix so the
  /// importer keeps them separate instead of merging them.
  final int renamedPlaylists;

  const SpotifyExportBundle({
    required this.playlists,
    this.skippedEpisodes = 0,
    this.skippedUnavailable = 0,
    this.savedAlbums = 0,
    this.followedArtists = 0,
    this.emptyPlaylists = 0,
    this.renamedPlaylists = 0,
  });

  int get totalTracks =>
      playlists.fold<int>(0, (sum, playlist) => sum + playlist.trackCount);

  bool get isEmpty => totalTracks == 0;

  int get playlistCount => playlists.length;
}

class SpotifyExportException implements Exception {
  final String message;

  const SpotifyExportException(this.message);

  @override
  String toString() => message;
}

/// A single JSON document coming from the export ZIP, or picked manually by
/// the user after unzipping.
class SpotifyExportFile {
  final String name;
  final Uint8List bytes;

  const SpotifyExportFile({required this.name, required this.bytes});
}

/// Parses Spotify's official "Download your data" package.
///
/// Supported inputs:
///  * the full ZIP attachment (`YourLibrary.json`, `Playlist1.json`, …), and
///  * individual JSON files after the user unzips it.
///
/// The export format only contains names and URIs — no durations, artwork or
/// audio — so tracks are imported as metadata and resolved by the existing
/// enrichment pipeline afterwards.
class SpotifyExportService {
  /// Refuse absurdly large archives: a phone cannot hold an uncompressed
  /// multi-hundred-megabyte streaming history in memory. Extended streaming
  /// history is not needed for a library import.
  static const int maxZipBytes = 120 * 1024 * 1024;

  /// Per-document guard, applied after decompression.
  static const int maxJsonBytes = 40 * 1024 * 1024;

  static const String likedSongsName = 'Liked Songs';

  static final RegExp _playlistFilePattern = RegExp(
    r'^(?:playlist|playlists)[0-9]*\.json$',
  );

  /// Reads a Spotify export ZIP.
  SpotifyExportBundle parseZipBytes(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw const SpotifyExportException(
        'That file is empty. Choose the ZIP attachment Spotify emailed you.',
      );
    }
    if (bytes.length > maxZipBytes) {
      throw const SpotifyExportException(
        'That ZIP is too large to read on this device.',
      );
    }
    if (!_looksLikeZip(bytes)) {
      throw const SpotifyExportException(
        "That doesn't look like a Spotify data export ZIP. Choose the ZIP "
        'attachment from the email Spotify sent after you requested your '
        'data.',
      );
    }

    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes, verify: false);
    } catch (_) {
      throw const SpotifyExportException(
        "That doesn't look like a Spotify data export ZIP. Choose the ZIP "
        'attachment from the email Spotify sent after you requested your '
        'data.',
      );
    }

    final documents = <SpotifyExportFile>[];
    for (final file in archive.files) {
      if (!file.isFile) continue;
      final name = file.name.replaceAll('\\', '/').split('/').last;
      if (!_isExportDocument(name)) continue;
      if (file.size > maxJsonBytes) continue;
      final content = file.readBytes();
      if (content == null || content.isEmpty) continue;
      documents.add(SpotifyExportFile(name: name, bytes: content));
    }

    if (documents.isEmpty) {
      throw const SpotifyExportException(
        'No Spotify library files were found in that ZIP. Expected '
        'YourLibrary.json or Playlist1.json inside it.',
      );
    }

    return parseJsonFiles(documents);
  }

  /// Reads previously unzipped export documents.
  SpotifyExportBundle parseJsonFiles(List<SpotifyExportFile> files) {
    final libraries = <_ParsedDocument>[];
    final playlists = <_ParsedDocument>[];

    for (final file in files) {
      final decoded = _decodeObject(file);
      if (decoded == null) continue;
      if (decoded['playlists'] is List) {
        playlists.add(_ParsedDocument(file.name, decoded));
      } else if (decoded.containsKey('tracks') ||
          decoded.containsKey('albums') ||
          decoded.containsKey('artists') ||
          decoded.containsKey('shows')) {
        libraries.add(_ParsedDocument(file.name, decoded));
      }
    }

    if (libraries.isEmpty && playlists.isEmpty) {
      throw const SpotifyExportException(
        'Those files do not contain Spotify library data. Expected '
        'YourLibrary.json or Playlist1.json.',
      );
    }

    // Prefer the real library document when several are present.
    libraries.sort((a, b) => _libraryRank(a.name) - _libraryRank(b.name));
    playlists.sort((a, b) => _naturalCompare(a.name, b.name));

    var skippedEpisodes = 0;
    var skippedUnavailable = 0;
    var savedAlbums = 0;
    var followedArtists = 0;
    var emptyPlaylists = 0;

    final result = <SpotifyExportPlaylist>[];
    final usedNames = <String>{};

    final library = libraries.firstOrNull;
    if (library != null) {
      final likedRows = _asList(library.json['tracks']);
      final likedTracks = <SpotifyImportedTrack>[];
      final seen = <String>{};
      for (final row in likedRows) {
        final track = _trackFrom(row);
        if (track == null) {
          skippedUnavailable++;
          continue;
        }
        if (seen.add(_dedupeKey(track))) likedTracks.add(track);
      }
      skippedEpisodes += _asList(library.json['episodes']).length;
      savedAlbums = _asList(library.json['albums']).length;
      followedArtists = _asList(library.json['artists']).length;
      if (likedTracks.isNotEmpty) {
        result.add(
          SpotifyExportPlaylist(
            name: likedSongsName,
            tracks: likedTracks,
            isLikedSongs: true,
          ),
        );
        usedNames.add(_nameKey(likedSongsName));
      }
    }

    var renamed = 0;
    for (final document in playlists) {
      for (final raw in _asList(document.json['playlists'])) {
        if (raw is! Map) continue;
        final playlistRows = _asMap(raw);
        final rawName = _asString(playlistRows['name']).trim();
        final fallbackName = 'Spotify Playlist ${result.length + 1}';
        var name = rawName.isEmpty ? fallbackName : rawName;

        final items = _asList(playlistRows['items']);
        final tracks = <SpotifyImportedTrack>[];
        final seen = <String>{};
        for (final item in items) {
          final itemMap = _asMap(item);
          final rawTrack = itemMap['track'];
          if (rawTrack is Map) {
            final track = _trackFrom(rawTrack, fallbackUri: itemMap['uri']);
            if (track == null) {
              skippedUnavailable++;
              continue;
            }
            if (seen.add(_dedupeKey(track))) tracks.add(track);
            continue;
          }
          if (itemMap['episode'] is Map || itemMap['show'] is Map) {
            skippedEpisodes++;
          } else {
            // local files, removed tracks, or unresolved rows
            skippedUnavailable++;
          }
        }

        if (tracks.isEmpty) {
          emptyPlaylists++;
          continue;
        }

        // Keep genuinely distinct playlists separate. The controller merges
        // by title, so identical names would otherwise collapse into one.
        if (!usedNames.add(_nameKey(name))) {
          final base = name;
          var suffix = 2;
          while (!usedNames.add(_nameKey('$base ($suffix)'))) {
            suffix++;
          }
          name = '$base ($suffix)';
          renamed++;
        }

        result.add(SpotifyExportPlaylist(name: name, tracks: tracks));
      }
    }

    return SpotifyExportBundle(
      playlists: result,
      skippedEpisodes: skippedEpisodes,
      skippedUnavailable: skippedUnavailable,
      savedAlbums: savedAlbums,
      followedArtists: followedArtists,
      emptyPlaylists: emptyPlaylists,
      renamedPlaylists: renamed,
    );
  }

  // ---------------------------------------------------------------------------
  // Parsing helpers
  // ---------------------------------------------------------------------------

  /// ZIP archives begin with "PK" followed by a local-file, end-of-central
  /// directory, or spanned marker. The archive package is lenient and returns
  /// an empty archive for arbitrary input, so check this before decoding.
  static bool _looksLikeZip(Uint8List bytes) {
    if (bytes.length < 4) return false;
    if (bytes[0] != 0x50 || bytes[1] != 0x4B) return false;
    return (bytes[2] == 0x03 && bytes[3] == 0x04) ||
        (bytes[2] == 0x05 && bytes[3] == 0x06) ||
        (bytes[2] == 0x07 && bytes[3] == 0x08);
  }

  static bool _isExportDocument(String name) {
    final lower = name.toLowerCase();
    if (!lower.endsWith('.json')) return false;
    if (lower.contains('yourlibrary')) return true;
    if (lower == 'library.json') return true;
    return _playlistFilePattern.hasMatch(lower);
  }

  static int _libraryRank(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('yourlibrary')) return 0;
    return 1;
  }

  static Map<String, dynamic>? _decodeObject(SpotifyExportFile file) {
    if (file.bytes.length > maxJsonBytes) return null;
    try {
      var text = utf8.decode(file.bytes, allowMalformed: true);
      if (text.startsWith('\uFEFF')) text = text.substring(1);
      final decoded = jsonDecode(text);
      if (decoded is! Map) return null;
      return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }
  }

  static SpotifyImportedTrack? _trackFrom(Object? raw, {Object? fallbackUri}) {
    final map = _asMap(raw);
    if (map.isEmpty) return null;

    final title = _firstNonEmpty([
      _asString(map['track']),
      _asString(map['title']),
      _asString(map['name']),
    ]);
    if (title.isEmpty) return null;

    final uri = _firstNonEmpty([_asString(map['uri']), _asString(fallbackUri)]);
    final spotifyId = _spotifyTrackId(uri);

    return SpotifyImportedTrack(
      spotifyId: spotifyId.isEmpty
          ? _fallbackId(title, _artistOf(map), _albumOf(map))
          : spotifyId,
      title: title,
      artist: _artistOf(map),
      album: _albumOf(map),
      // The export never includes duration; the enricher fills it in.
      duration: Duration.zero,
      isExplicit: map['explicit'] == true || map['isExplicit'] == true,
    );
  }

  static String _spotifyTrackId(String uri) {
    if (uri.isEmpty) return '';
    final parsed = SpotifyImportService.tryParse(uri);
    if (parsed != null && parsed.type == SpotifyLinkType.track) {
      return parsed.id;
    }
    // Bare 22-character IDs occasionally appear in hand-edited exports.
    if (parsed == null && RegExp(r'^[0-9A-Za-z]{22}$').hasMatch(uri)) {
      return uri;
    }
    return '';
  }

  /// Stable synthetic id for rows without a Spotify URI, so repeated imports
  /// of the same export map onto the same [Song] instead of duplicating.
  static String _fallbackId(String title, String artist, String album) {
    final digest = md5.convert(
      utf8.encode('${_nameKey(title)}|${_nameKey(artist)}|${_nameKey(album)}'),
    );
    return 'export$digest';
  }

  static String _dedupeKey(SpotifyImportedTrack track) {
    final id = track.spotifyId;
    if (id.isNotEmpty && !id.startsWith('export')) return 'id:$id';
    return 'meta:${_nameKey(track.title)}|${_nameKey(track.artist)}';
  }

  static String _artistOf(Map<String, dynamic> map) {
    final single = _asString(map['artist']).trim();
    if (single.isNotEmpty) return single;
    final names = <String>[];
    for (final entry in _asList(map['artists'])) {
      if (entry is Map) {
        final name = _asString(_asMap(entry)['name']).trim();
        if (name.isNotEmpty) names.add(name);
      } else {
        final name = _asString(entry).trim();
        if (name.isNotEmpty) names.add(name);
      }
    }
    return names.join(', ');
  }

  static String _albumOf(Map<String, dynamic> map) {
    final direct = _asString(map['album']).trim();
    if (direct.isNotEmpty) return direct;
    final nested = map['album'];
    if (nested is Map) return _asString(_asMap(nested)['name']).trim();
    return '';
  }

  static String _firstNonEmpty(List<String> values) {
    for (final value in values) {
      if (value.trim().isNotEmpty) return value.trim();
    }
    return '';
  }

  static List<Object?> _asList(Object? value) =>
      value is List ? value : const <Object?>[];

  static Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  static String _asString(Object? value) => value is String ? value : '';

  static String _nameKey(String value) {
    final lower = value.toLowerCase();
    final buffer = StringBuffer();
    for (final rune in lower.runes) {
      final char = String.fromCharCode(rune);
      if (RegExp(r'[a-z0-9]').hasMatch(char)) buffer.write(char);
    }
    return buffer.toString();
  }

  /// Orders `Playlist2.json` before `Playlist10.json`.
  static int _naturalCompare(String a, String b) {
    final pattern = RegExp(r'(\d+)|(\D+)');
    final left = pattern.allMatches(a.toLowerCase()).toList();
    final right = pattern.allMatches(b.toLowerCase()).toList();
    for (var i = 0; i < left.length && i < right.length; i++) {
      final l = left[i].group(0)!;
      final r = right[i].group(0)!;
      final ln = int.tryParse(l);
      final rn = int.tryParse(r);
      final cmp = (ln != null && rn != null)
          ? ln.compareTo(rn)
          : l.compareTo(r);
      if (cmp != 0) return cmp;
    }
    return left.length.compareTo(right.length);
  }
}

class _ParsedDocument {
  final String name;
  final Map<String, dynamic> json;

  const _ParsedDocument(this.name, this.json);
}
