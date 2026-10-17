import 'dart:async';
import 'package:flutter/material.dart';

import '../controllers/music_player_controller.dart';
import '../models/song_model.dart';
import '../services/discovery_auto_refresh.dart';
import '../services/discovery_service.dart';
import '../theme/app_theme.dart';
import '../widgets/song_artwork_widget.dart';
import '../widgets/spotify_lyrics_sheet.dart';
import 'discovery_playlist_page.dart';

/// Automatic dashboard rows (Quick Picks, Covers & Remixes, Long Listens,
/// Community Favorites, Trending For You). Needs no imported playlist.
///
/// Tapping a song plays its whole row as a queue. Community Favorites and
/// Trending For You also open a playlist-style list page from their header.
class DiscoverySections extends StatefulWidget {
  const DiscoverySections({super.key, required this.controller});

  final MusicPlayerController controller;

  @override
  State<DiscoverySections> createState() => DiscoverySectionsState();
}

class DiscoverySectionsState extends State<DiscoverySections> {
  List<DiscoverySection> _sections = const [];
  bool _isLoading = true;
  Future<void>? _inFlight;
  int _signature = 0;
  late final DiscoveryAutoRefresher _autoRefresher;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChange);
    // Auto-refresh every 5 minutes while the dashboard is open, and when the
    // app returns to the foreground after 3+ minutes.
    _autoRefresher = DiscoveryAutoRefresher(
      onRefresh: () => refresh(silent: true),
      interval: const Duration(minutes: 5),
      staleAfter: const Duration(minutes: 3),
      minGap: const Duration(seconds: 45),
    )..start();
    // Paint the last saved rows instantly, then fetch fresh ones.
    unawaited(_showSaved());
    _loadDiscovery(forceRefresh: false);
  }

  void _onControllerChange() {
    if (!mounted) return;
    // The controller notifies on every playback tick. Rebuild only when a
    // visible song gained audio or finished upgrading from its preview.
    final signature = _computeSignature(_sections);
    if (signature != _signature) {
      _signature = signature;
      setState(() {});
    }
  }

  static int _computeSignature(List<DiscoverySection> sections) {
    var h = 17;
    for (final section in sections) {
      for (final song in section.songs) {
        h = (h * 31 + (song.hasAudio ? 1 : 0) + (song.isPreview ? 2 : 0)) &
            0x3fffffff;
      }
    }
    return h;
  }

  @override
  void dispose() {
    _autoRefresher.dispose();
    widget.controller.removeListener(_onControllerChange);
    super.dispose();
  }

  Future<void> _showSaved() async {
    final saved = await DiscoveryService.instance.loadSaved();
    if (!mounted || saved.isEmpty || _sections.isNotEmpty) return;
    setState(() {
      _sections = saved;
      _isLoading = false;
      _signature = _computeSignature(saved);
    });
  }

  /// Refreshes discovery rows with forced fresh data and immediately fast-locates tracks.
  Future<void> refresh({bool silent = false}) {
    if (!silent) _autoRefresher.markRefreshed();
    return _loadDiscovery(forceRefresh: true);
  }

  Future<void> _loadDiscovery({bool forceRefresh = false}) {
    // One load at a time; a second caller simply waits for the running one.
    final running = _inFlight;
    if (running != null) return running;
    final future = _fetch(forceRefresh: forceRefresh)
        .whenComplete(() => _inFlight = null);
    _inFlight = future;
    return future;
  }

  Future<void> _fetch({required bool forceRefresh}) async {
    try {
      await DiscoveryService.instance.loadAll(
        forceRefresh: forceRefresh,
        // Each row appears as soon as it is ready.
        onSection: (section) {
          if (mounted) _applySection(section);
        },
      );
    } catch (_) {}
    if (!mounted) return;
    // Rows that failed (offline, timeout) keep their previous content.
    setState(() => _isLoading = false);
    _fastLocateTracks(_sections);
  }

  void _applySection(DiscoverySection incoming) {
    final merged = _reuseResolved(incoming);
    final next = List<DiscoverySection>.from(_sections);
    final index = next.indexWhere((s) => s.id == incoming.id);
    if (index >= 0) {
      next[index] = merged;
    } else {
      next.add(merged);
    }
    next.sort((a, b) => DiscoveryService.sectionOrder
        .indexOf(a.id)
        .compareTo(DiscoveryService.sectionOrder.indexOf(b.id)));
    setState(() {
      _sections = next;
      _isLoading = false;
      _signature = _computeSignature(next);
    });
  }

  /// A refresh builds brand-new Song objects. Keep the ones that already
  /// resolved to a full track so they do not flip back to preview/LOCATING.
  DiscoverySection _reuseResolved(DiscoverySection incoming) {
    final resolved = <String, Song>{
      for (final section in _sections)
        for (final song in section.songs)
          if (song.hasAudio && !song.isPreview) song.id: song,
    };
    if (resolved.isEmpty) return incoming;
    return DiscoverySection(
      id: incoming.id,
      title: incoming.title,
      subtitle: incoming.subtitle,
      songs: [for (final song in incoming.songs) resolved[song.id] ?? song],
      openable: incoming.openable,
    );
  }

  void _fastLocateTracks(List<DiscoverySection> sections) {
    if (sections.isEmpty) return;
    // Interleave songs across all sections (top of Quick Picks, Covers,
    // Community, Trending) so the top tracks of each section resolve simultaneously
    final interleaved = <Song>[];
    final maxLen = sections.fold<int>(0, (max, s) => s.songs.length > max ? s.songs.length : max);
    for (var i = 0; i < maxLen; i++) {
      for (final sec in sections) {
        if (i < sec.songs.length) {
          interleaved.add(sec.songs[i]);
        }
      }
    }
    widget.controller.fastLocateDiscoverySongs(interleaved);
  }

  void _playFrom(DiscoverySection section, int index) {
    widget.controller.playSongList(section.songs, startIndex: index);
    SpotifyLyricsSheet.show(
      context,
      song: section.songs[index],
      controller: widget.controller,
    );
  }

  void _openSection(DiscoverySection section) {
    Navigator.of(context).push(
      DiscoveryPlaylistPage.route(
        section: section,
        controller: widget.controller,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _sections.isEmpty) {
      return const SizedBox(
        height: 120,
        child: Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (_sections.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final section in _sections) ...[
          _DiscoveryRail(
            section: section,
            onPlay: (index) => _playFrom(section, index),
            onOpen: section.openable ? () => _openSection(section) : null,
          ),
          const SizedBox(height: 32),
        ],
      ],
    );
  }
}

class _DiscoveryRail extends StatelessWidget {
  const _DiscoveryRail({
    required this.section,
    required this.onPlay,
    this.onOpen,
  });

  final DiscoverySection section;
  final ValueChanged<int> onPlay;

  /// Non-null for sections that open a playlist-style page.
  final VoidCallback? onOpen;

  static const double _tileWidth = 140;
  static const double _railHeight = 190;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(),
        const SizedBox(height: 14),
        SizedBox(
          height: _railHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: section.songs.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, index) => _tile(section.songs[index], index),
          ),
        ),
      ],
    );
  }

  Widget _header() {
    final titles = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          section.title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          section.subtitle,
          style: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
        ),
      ],
    );

    final open = onOpen;
    if (open == null) return titles;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: open,
      child: Row(
        children: [
          Expanded(child: titles),
          const SizedBox(width: 8),
          const Text(
            'See all',
            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: AppTheme.textSecondary,
          ),
        ],
      ),
    );
  }

  Widget _tile(Song song, int index) {
    return SizedBox(
      width: _tileWidth,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onPlay(index),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                SongArtworkWidget(
                  song: song,
                  size: _tileWidth,
                  borderRadius: 12,
                ),
                if (!song.hasAudio)
                  Positioned(
                    bottom: 6,
                    left: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: AppTheme.accentPink.withValues(alpha: 0.5),
                          width: 1,
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 8,
                            height: 8,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: AppTheme.accentPink,
                            ),
                          ),
                          SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              'LOCATING',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                                color: AppTheme.accentPink,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            Text(
              song.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}