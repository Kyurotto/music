import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:music/services/discovery_service.dart';

Map<String, Object?> _track({
  required int id,
  required String name,
  String artist = 'Artist',
  String album = 'Album',
  int millis = 210000,
}) {
  return {
    'wrapperType': 'track',
    'trackId': id,
    'trackName': name,
    'artistName': artist,
    'collectionName': album,
    'artworkUrl100': 'https://img.example/x/100x100bb.jpg',
    'previewUrl': 'https://preview.example/$id.m4a',
    'trackTimeMillis': millis,
  };
}

void main() {
  setUp(DiscoveryService.clearCache);

  test('covers & remixes keeps only cover/remix titles', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/search') {
        return http.Response(
          jsonEncode({
            'results': [
              _track(id: 1, name: 'Hello (Cover)'),
              _track(id: 2, name: 'Original Song'),
            ],
          }),
          200,
        );
      }
      // Apple RSS charts are unavailable in this test.
      return http.Response('{}', 404);
    });

    final service = DiscoveryService(client: client, random: Random(1));
    final sections = await service.loadAll();

    final covers = sections.firstWhere((s) => s.id == 'covers');
    expect(covers.songs.map((s) => s.title), ['Hello (Cover)']);
    expect(covers.openable, isFalse);

    final song = covers.songs.single;
    // Same id scheme as the iTunes artist import, so the player resolves the
    // full-length track and runs its retry paths for it.
    expect(song.id, 'spotify-itunes-1');
    // Songs do not default to 30s preview; they start empty to resolve full tracks
    expect(song.audioUrl, isEmpty);
    expect(song.isPreview, isFalse);
    expect(song.imageUrl, contains('600x600bb'));
  });

  test('long listens keeps only tracks of 6 minutes or more', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/search') {
        return http.Response(
          jsonEncode({
            'results': [
              _track(id: 10, name: 'Epic Mix', millis: 9 * 60 * 1000),
              _track(id: 11, name: 'Just Under', millis: 5 * 60 * 1000 + 59000),
              _track(id: 12, name: 'Exactly Six', millis: 6 * 60 * 1000),
              _track(id: 13, name: 'Radio Edit', millis: 3 * 60 * 1000),
            ],
          }),
          200,
        );
      }
      return http.Response('{}', 404);
    });

    final service = DiscoveryService(client: client, random: Random(1));
    final sections = await service.loadAll();

    final long = sections.firstWhere((s) => s.id == 'long');
    expect(
      long.songs.map((s) => s.title).toSet(),
      {'Epic Mix', 'Exactly Six'},
    );
    expect(long.title, 'Long Listens');
  });

  test('sections with no results are omitted instead of breaking', () async {
    final client = MockClient((_) async => http.Response('boom', 500));

    final service = DiscoveryService(client: client, random: Random(1));
    final sections = await service.loadAll();

    expect(sections, isEmpty);
  });

  test('chart sections keep Apple RSS order and open as playlists', () async {
    final client = MockClient((request) async {
      if (request.url.path.contains('/most-played/')) {
        return http.Response(
          jsonEncode({
            'feed': {
              'results': [
                {'id': '30'},
                {'id': '10'},
              ],
            },
          }),
          200,
        );
      }
      if (request.url.path == '/lookup') {
        return http.Response(
          jsonEncode({
            'results': [
              _track(id: 10, name: 'Second In Chart'),
              _track(id: 30, name: 'First In Chart'),
            ],
          }),
          200,
        );
      }
      return http.Response('{}', 404);
    });

    final service = DiscoveryService(client: client, random: Random(1));
    final sections = await service.loadAll();

    for (final id in ['trending', 'community']) {
      final section = sections.firstWhere((s) => s.id == id);
      expect(
        section.songs.map((s) => s.title),
        ['First In Chart', 'Second In Chart'],
      );
      expect(section.openable, isTrue, reason: '$id should open a list page');
    }
  });

  test('loadAll with forceRefresh: true clears cache and refetches fresh data', () async {
    var callCount = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/search') {
        callCount++;
        return http.Response(
          jsonEncode({
            'results': [
              _track(id: callCount, name: 'Song $callCount (Cover)', millis: 400000),
            ],
          }),
          200,
        );
      }
      return http.Response('{}', 404);
    });

    final service = DiscoveryService(client: client, random: Random(1));
    final first = await service.loadAll();
    final firstCount = callCount;
    expect(first, isNotEmpty);

    // Without forceRefresh, cached results are returned immediately without extra network calls
    final cached = await service.loadAll();
    expect(callCount, firstCount);
    expect(cached, isNotEmpty);

    // With forceRefresh: true, cache is cleared and fresh requests are sent
    final fresh = await service.loadAll(forceRefresh: true);
    expect(callCount, greaterThan(firstCount));
    expect(fresh, isNotEmpty);
  });
}