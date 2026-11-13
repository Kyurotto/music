import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music/services/spotify_export_service.dart';

/// Spotify IDs are exactly 22 base-62 characters.
String _id(int value) => value.toString().padLeft(22, '0');

Uint8List _encode(Map<String, Object?> json) =>
    Uint8List.fromList(utf8.encode(jsonEncode(json)));

SpotifyExportFile _file(String name, Map<String, Object?> json) =>
    SpotifyExportFile(name: name, bytes: _encode(json));

Uint8List _zip(Map<String, Map<String, Object?>> documents) {
  final archive = Archive();
  documents.forEach((name, json) {
    final bytes = utf8.encode(jsonEncode(json));
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return ZipEncoder().encodeBytes(archive);
}

Map<String, Object?> _track(
  String title, {
  String? artist,
  String? album,
  int id = 0,
}) {
  return <String, Object?>{
    'artist': artist ?? 'Artist',
    'album': album ?? 'Album',
    'track': title,
    'uri': 'spotify:track:${_id(id)}',
  };
}

Map<String, Object?> _row(Map<String, Object?> track) => <String, Object?>{
  'uri': track['uri'],
  'track': track,
};

Map<String, Object?> _playlist(String name, List<Map<String, Object?>> rows) {
  return <String, Object?>{'name': name, 'items': rows};
}

void main() {
  late SpotifyExportService service;

  setUp(() {
    service = SpotifyExportService();
  });

  group('SpotifyExportService ZIP parsing', () {
    test('reads Liked Songs and playlist tracks from a real export layout', () {
      final zip = _zip({
        'YourLibrary.json': {
          'tracks': [
            _track('Song One', artist: 'A', album: 'X', id: 1),
            _track('Song Two', artist: 'B', album: 'Y', id: 2),
            _track('Song Three', artist: 'C', album: 'Z', id: 3),
            _track('Song One', artist: 'A', album: 'X', id: 1),
          ],
          'episodes': [
            {'name': 'Episode', 'uri': 'spotify:episode:abc'},
          ],
          'albums': [
            {'artist': 'A', 'album': 'X', 'uri': 'spotify:album:xyz'},
            {'artist': 'B', 'album': 'Y', 'uri': 'spotify:album:abc'},
          ],
          'artists': [
            {'name': 'A', 'uri': 'spotify:artist:a'},
          ],
        },
        'Playlist1.json': {
          'playlists': [
            _playlist('Road Trip', [
              _row(_track('Highway', id: 4)),
              _row(_track('Sunset', id: 5)),
              _row(_track('Sunset', id: 5)),
              {
                'episode': {'name': 'A podcast', 'uri': 'spotify:episode:x'},
                'uri': 'spotify:episode:x',
              },
            ]),
          ],
        },
      });

      final bundle = service.parseZipBytes(zip);

      expect(bundle.playlistCount, 2);
      expect(bundle.playlists.first.name, SpotifyExportService.likedSongsName);
      expect(bundle.playlists.first.isLikedSongs, isTrue);
      expect(
        bundle.playlists.first.trackCount,
        3,
        reason: 'duplicates collapse',
      );

      final roadTrip = bundle.playlists.last;
      expect(roadTrip.name, 'Road Trip');
      expect(
        roadTrip.trackCount,
        2,
        reason: 'episode and duplicate are dropped',
      );
      expect(roadTrip.tracks.first.title, 'Highway');
      expect(roadTrip.tracks.first.artist, 'Artist');
      expect(roadTrip.tracks.first.spotifyId, _id(4));

      expect(bundle.skippedEpisodes, 2);
      expect(bundle.savedAlbums, 2);
      expect(bundle.followedArtists, 1);
      expect(bundle.totalTracks, 5);
    });

    test(
      'finds documents inside a nested folder and ignores unrelated JSON',
      () {
        final zip = _zip({
          'Spotify Account Data/YourLibrary.json': {
            'tracks': [_track('Nested', id: 10)],
          },
          'Spotify Account Data/Playlist1.json': {
            'playlists': [
              _playlist('Nested Playlist', [_row(_track('Deep', id: 11))]),
            ],
          },
          'Spotify Account Data/StreamingHistory0.json': <String, Object?>{
            'items': <Object?>[],
          },
        });

        final bundle = service.parseZipBytes(zip);

        expect(bundle.playlistCount, 2);
        expect(bundle.totalTracks, 2);
      },
    );

    test('orders Playlist2 before Playlist10', () {
      final zip = _zip({
        'Playlist10.json': {
          'playlists': [
            _playlist('Tenth', [_row(_track('T10', id: 20))]),
          ],
        },
        'Playlist2.json': {
          'playlists': [
            _playlist('Second', [_row(_track('T2', id: 21))]),
          ],
        },
      });

      final bundle = service.parseZipBytes(zip);

      expect(bundle.playlists.map((p) => p.name), ['Second', 'Tenth']);
    });

    test('keeps same-named playlists separate instead of merging them', () {
      final zip = _zip({
        'Playlist1.json': {
          'playlists': [
            _playlist('Favorites', [_row(_track('One', id: 30))]),
            _playlist('Favorites', [_row(_track('Two', id: 31))]),
          ],
        },
      });

      final bundle = service.parseZipBytes(zip);

      expect(bundle.playlists.map((p) => p.name), [
        'Favorites',
        'Favorites (2)',
      ]);
      expect(bundle.renamedPlaylists, 1);
    });

    test('handles a UTF-8 BOM and uppercase file names', () {
      final bytes = Uint8List.fromList([
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode(
          jsonEncode({
            'tracks': [_track('Bom', id: 40)],
          }),
        ),
      ]);
      final archive = Archive()
        ..addFile(ArchiveFile('YOURLIBRARY.JSON', bytes.length, bytes));
      final zip = ZipEncoder().encodeBytes(archive);

      final bundle = service.parseZipBytes(zip);

      expect(bundle.totalTracks, 1);
      expect(bundle.playlists.single.tracks.single.title, 'Bom');
    });

    test('creates stable ids for rows without a Spotify URI', () {
      final zip = _zip({
        'Playlist1.json': {
          'playlists': [
            _playlist('Local', [
              {
                'track': {
                  'track': 'Local File',
                  'artist': 'Me',
                  'album': 'Disk',
                },
              },
            ]),
          ],
        },
      });

      final first = service.parseZipBytes(zip).playlists.single.tracks.single;
      final second = service.parseZipBytes(zip).playlists.single.tracks.single;

      expect(first.spotifyId, isNotEmpty);
      expect(first.spotifyId, second.spotifyId);
      expect(first.spotifyId, startsWith('export'));
      expect(first.duration, Duration.zero);
    });

    test('reports playlists that contain no music', () {
      final zip = _zip({
        'Playlist1.json': {
          'playlists': [
            _playlist('Podcasts', [
              {
                'episode': {'name': 'Ep', 'uri': 'spotify:episode:1'},
                'uri': 'spotify:episode:1',
              },
            ]),
            _playlist('Music', [_row(_track('Real', id: 50))]),
          ],
        },
      });

      final bundle = service.parseZipBytes(zip);

      expect(bundle.playlistCount, 1);
      expect(bundle.emptyPlaylists, 1);
      expect(bundle.skippedEpisodes, 1);
    });

    test('rejects a file that is not a ZIP', () {
      expect(
        () => service.parseZipBytes(
          Uint8List.fromList(utf8.encode('not a zip at all')),
        ),
        throwsA(
          isA<SpotifyExportException>().having(
            (e) => e.message,
            'message',
            contains("doesn't look like a Spotify data export"),
          ),
        ),
      );
    });

    test('rejects an empty file', () {
      expect(
        () => service.parseZipBytes(Uint8List(0)),
        throwsA(isA<SpotifyExportException>()),
      );
    });

    test('rejects a ZIP without library documents', () {
      final zip = _zip({
        'Userdata.json': {'username': 'someone'},
        'StreamingHistory0.json': <String, Object?>{'items': <Object?>[]},
      });

      expect(
        () => service.parseZipBytes(zip),
        throwsA(
          isA<SpotifyExportException>().having(
            (e) => e.message,
            'message',
            contains('No Spotify library files'),
          ),
        ),
      );
    });

    test('rejects oversized archives before decoding', () {
      final tooLarge = Uint8List(SpotifyExportService.maxZipBytes + 1);

      expect(
        () => service.parseZipBytes(tooLarge),
        throwsA(
          isA<SpotifyExportException>().having(
            (e) => e.message,
            'message',
            contains('too large'),
          ),
        ),
      );
    });
  });

  group('SpotifyExportService JSON parsing', () {
    test('accepts unzipped files picked manually', () {
      final bundle = service.parseJsonFiles([
        _file('YourLibrary.json', {
          'tracks': [_track('Manual', id: 60)],
        }),
        _file('Playlist1.json', {
          'playlists': [
            _playlist('Manual Playlist', [_row(_track('From File', id: 61))]),
          ],
        }),
      ]);

      expect(bundle.playlistCount, 2);
      expect(bundle.totalTracks, 2);
    });

    test('tolerates missing fields and malformed rows', () {
      final bundle = service.parseJsonFiles([
        _file('Playlist1.json', {
          'playlists': [
            {
              'name': 'Messy',
              'items': [
                <String, Object?>{},
                {'track': <String, Object?>{}},
                {
                  'track': {'track': 'Only Title'},
                },
                {
                  'track': {'name': 'Named', 'artist': 'Someone'},
                },
              ],
            },
          ],
        }),
      ]);

      expect(bundle.playlists.single.name, 'Messy');
      expect(bundle.playlists.single.trackCount, 2);
      expect(bundle.skippedUnavailable, 2);
    });

    test('reads artists supplied as a list', () {
      final bundle = service.parseJsonFiles([
        _file('Playlist1.json', {
          'playlists': [
            {
              'name': 'Collab',
              'items': [
                {
                  'track': {
                    'name': 'Together',
                    'artists': [
                      {'name': 'First'},
                      {'name': 'Second'},
                    ],
                  },
                },
              ],
            },
          ],
        }),
      ]);

      expect(bundle.playlists.single.tracks.single.artist, 'First, Second');
    });

    test('rejects files that are not Spotify library data', () {
      expect(
        () => service.parseJsonFiles([
          _file('Userdata.json', {'username': 'someone'}),
        ]),
        throwsA(isA<SpotifyExportException>()),
      );
    });
  });
}
