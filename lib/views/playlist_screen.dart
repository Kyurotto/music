// lib/views/playlist_screen.dart

import 'package:flutter/material.dart';

import '../controllers/music_player_controller.dart';
import '../models/song_model.dart';
import '../theme/app_theme.dart';
import '../widgets/bottom_player_bar.dart';
import '../widgets/song_artwork_widget.dart';
import '../widgets/spotify_lyrics_sheet.dart';

/// YouTube Music-style playlist screen:
/// - Background: Colors.black, text: Colors.white and Colors.grey
/// - Top App Bar: transparent, back button and cast action
/// - Body in a CustomScrollView:
///   1. 2x2 Grid widget for the 4-cover collage
///   2. Text widgets for title, creator row with CircleAvatar, metadata views/runtime
///   3. Action buttons row with an elevated white circular Play button in the center
///   4. ListView of songs with custom row layout (leading cover, title, subtitle with artist & duration & full track indicator, trailing popup menu icon)
/// - Bottom Persistent widgets:
///   * Sticky mini-player bar above the bottom navigation
///   * BottomNavigationBar with 4 items: Home, Samples, Explore, Library
class PlaylistScreen extends StatefulWidget {
  final MusicPlaylist? playlist;
  final String? title;
  final String? subtitle;
  final String? creatorName;
  final String? creatorAvatarUrl;
  final List<Song>? songs;
  final MusicPlayerController controller;

  const PlaylistScreen({
    super.key,
    this.playlist,
    this.title,
    this.subtitle,
    this.creatorName,
    this.creatorAvatarUrl,
    this.songs,
    required this.controller,
  });

  static Route<void> route({
    MusicPlaylist? playlist,
    String? title,
    String? subtitle,
    String? creatorName,
    String? creatorAvatarUrl,
    List<Song>? songs,
    required MusicPlayerController controller,
  }) {
    return MaterialPageRoute<void>(
      builder: (_) => PlaylistScreen(
        playlist: playlist,
        title: title,
        subtitle: subtitle,
        creatorName: creatorName,
        creatorAvatarUrl: creatorAvatarUrl,
        songs: songs,
        controller: controller,
      ),
    );
  }

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  int _selectedBottomNav = 0;

  List<Song> _resolveSongs() {
    List<Song> base;
    if (widget.playlist != null) {
      base = widget.controller.songsForPlaylist(widget.playlist!.id);
      if (base.isEmpty && widget.songs != null && widget.songs!.isNotEmpty) {
        base = widget.songs!;
      }
    } else if (widget.songs != null && widget.songs!.isNotEmpty) {
      base = widget.songs!;
    } else {
      base = widget.controller.allSongs.take(20).toList();
    }

    final seenKeys = <String>{};
    final seenIds = <String>{};
    final deduplicated = <Song>[];
    for (final s in base) {
      if (!seenIds.add(s.id)) continue;
      final key = '${s.title.toLowerCase().trim()}|${s.artist.toLowerCase().trim()}';
      if (key != '|' && !seenKeys.add(key)) continue;
      deduplicated.add(s);
    }
    return deduplicated;
  }

  String get _displayTitle {
    if (widget.title != null && widget.title!.isNotEmpty) {
      return widget.title!;
    }
    if (widget.playlist != null && widget.playlist!.title.isNotEmpty) {
      return widget.playlist!.title;
    }
    return 'Pang relax';
  }

  String get _displayCreator {
    if (widget.creatorName != null && widget.creatorName!.isNotEmpty) {
      return widget.creatorName!;
    }
    if (widget.playlist != null && widget.playlist!.subtitle.isNotEmpty) {
      return widget.playlist!.subtitle;
    }
    return 'YouTube Music';
  }

  String _formatTotalRuntime(List<Song> songs) {
    var totalSeconds = 0;
    for (final s in songs) {
      totalSeconds += s.duration.inSeconds;
    }
    if (totalSeconds <= 0) return '0 min';
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    if (hours > 0) {
      return '$hours hr ${minutes > 0 ? '$minutes min' : ''}';
    }
    return '$minutes min';
  }

  String _formatPlays(List<Song> songs) {
    if (songs.isEmpty) return '12.4K';
    var totalPlays = 0;
    for (final s in songs) {
      final cleaned = s.plays.replaceAll(RegExp(r'[^0-9]'), '');
      final p = int.tryParse(cleaned);
      if (p != null) totalPlays += p;
    }
    if (totalPlays > 1000000) {
      return '${(totalPlays / 1000000).toStringAsFixed(1)}M';
    }
    if (totalPlays > 1000) {
      return '${(totalPlays / 1000).toStringAsFixed(1)}K';
    }
    return totalPlays > 0 ? '$totalPlays' : '45.2K';
  }

  void _playAll(List<Song> songs) {
    if (songs.isEmpty) return;
    widget.controller.playSongList(songs, startIndex: 0);
  }

  void _togglePlayPause(List<Song> songs) {
    if (songs.isEmpty) return;
    final currentId = widget.controller.currentSong?.id;
    final isCurrentInList = songs.any((s) => s.id == currentId);

    if (isCurrentInList) {
      widget.controller.togglePlayPause();
    } else {
      _playAll(songs);
    }
  }

  void _shufflePlay(List<Song> songs) {
    if (songs.isEmpty) return;
    final shuffled = List<Song>.from(songs)..shuffle();
    widget.controller.playSongList(shuffled, startIndex: 0);
  }

  void _playSongAt(List<Song> songs, int index) {
    widget.controller.playSongList(songs, startIndex: index);
    final song = songs[index];
    SpotifyLyricsSheet.show(context, song: song, controller: widget.controller);
  }

  void _openLyrics(BuildContext context) {
    final song = widget.controller.currentSong;
    if (song == null) return;
    SpotifyLyricsSheet.show(context, song: song, controller: widget.controller);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final songs = _resolveSongs();
        final currentSongId = widget.controller.currentSong?.id;
        final isPlayingCurrent = widget.controller.isPlaying &&
            songs.any((s) => s.id == currentSongId);

        return Scaffold(
          backgroundColor: Colors.black,
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.cast, color: Colors.white),
                tooltip: 'Cast',
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Cast device search active...'),
                      duration: Duration(seconds: 2),
                      backgroundColor: Color(0xFF222222),
                    ),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.search, color: Colors.white),
                tooltip: 'Search',
                onPressed: () {
                  widget.controller.setNavIndex(0);
                  Navigator.of(context).pop();
                },
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.white),
                color: const Color(0xFF212121),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'add_to_queue',
                    child: Text('Add playlist to queue',
                        style: TextStyle(color: Colors.white)),
                  ),
                  const PopupMenuItem(
                    value: 'play_next',
                    child: Text('Play next',
                        style: TextStyle(color: Colors.white)),
                  ),
                  const PopupMenuItem(
                    value: 'share',
                    child: Text('Share playlist',
                        style: TextStyle(color: Colors.white)),
                  ),
                ],
                onSelected: (val) {
                  if (val == 'add_to_queue' && songs.isNotEmpty) {
                    widget.controller.enqueueList(songs);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Added ${songs.length} songs to queue'),
                        backgroundColor: const Color(0xFF222222),
                      ),
                    );
                  } else if (val == 'play_next' && songs.isNotEmpty) {
                    widget.controller.playSongList(songs, startIndex: 0);
                  }
                },
              ),
            ],
          ),
          body: RefreshIndicator(
            color: Colors.white,
            backgroundColor: const Color(0xFF222222),
            onRefresh: () async {
              widget.controller.fastLocateDiscoverySongs(songs);
              widget.controller.bumpLocatingVersion();
              await Future<void>.delayed(const Duration(milliseconds: 600));
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 90, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // 1. 2x2 Grid widget for the 4-cover collage
                        _CoverCollage2x2(
                          songs: songs,
                          fallbackGradient: widget.playlist?.gradient ??
                              const [Color(0xFF212121), Color(0xFF0D0D0D)],
                        ),
                        const SizedBox(height: 24),

                        // 2. Text widgets: title ("Pang relax"), creator row with CircleAvatar, metadata views/runtime
                        Text(
                          _displayTitle,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Creator row with CircleAvatar
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircleAvatar(
                              radius: 12,
                              backgroundColor: Colors.white24,
                              backgroundImage: widget.creatorAvatarUrl != null &&
                                      widget.creatorAvatarUrl!.isNotEmpty
                                  ? NetworkImage(widget.creatorAvatarUrl!)
                                  : null,
                              child: widget.creatorAvatarUrl == null ||
                                      widget.creatorAvatarUrl!.isEmpty
                                  ? const Icon(Icons.person,
                                      size: 14, color: Colors.white)
                                  : null,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _displayCreator,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              '• Playlist',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Metadata views/runtime
                        Text(
                          '${songs.length} songs • ${_formatTotalRuntime(songs)} • ${_formatPlays(songs)} views',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        if (widget.subtitle != null &&
                            widget.subtitle!.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            widget.subtitle!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 24),

                        // 3. Action buttons row with an elevated white circular Play button in the center
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Download
                            IconButton(
                              icon: const Icon(Icons.download_outlined,
                                  color: Colors.white, size: 26),
                              tooltip: 'Download all',
                              onPressed: () {
                                widget.controller.cacheDisplayedDashboardAudio();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Downloading tracks for offline use...'),
                                    backgroundColor: Color(0xFF222222),
                                  ),
                                );
                              },
                            ),

                            // Bookmark / Library Add
                            IconButton(
                              icon: const Icon(Icons.bookmark_border_rounded,
                                  color: Colors.white, size: 26),
                              tooltip: 'Save to library',
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Playlist saved to your library'),
                                    backgroundColor: Color(0xFF222222),
                                  ),
                                );
                              },
                            ),

                            // Elevated white circular Play button in the center
                            Container(
                              width: 62,
                              height: 62,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.white.withValues(alpha: 0.3),
                                    blurRadius: 18,
                                    spreadRadius: 2,
                                    offset: const Offset(0, 4),
                                  ),
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.4),
                                    blurRadius: 12,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: () => _togglePlayPause(songs),
                                  child: Center(
                                    child: Icon(
                                      isPlayingCurrent
                                          ? Icons.pause_rounded
                                          : Icons.play_arrow_rounded,
                                      color: Colors.black,
                                      size: 38,
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            // Share
                            IconButton(
                              icon: const Icon(Icons.share_outlined,
                                  color: Colors.white, size: 24),
                              tooltip: 'Share',
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Shared "$_displayTitle"'),
                                    backgroundColor: const Color(0xFF222222),
                                  ),
                                );
                              },
                            ),

                            // Shuffle
                            IconButton(
                              icon: Icon(
                                widget.controller.isShuffle
                                    ? Icons.shuffle_on_rounded
                                    : Icons.shuffle_rounded,
                                color: widget.controller.isShuffle
                                    ? AppTheme.accentGreen
                                    : Colors.white,
                                size: 26,
                              ),
                              tooltip: 'Shuffle',
                              onPressed: () => _shufflePlay(songs),
                            ),

                            if (widget.playlist != null)
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded,
                                    color: Colors.white, size: 24),
                                tooltip: 'Delete playlist',
                                onPressed: _confirmDeletePlaylist,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // 4. ListView of songs with ListTile or custom row layout
                SliverPadding(
                  padding: const EdgeInsets.only(bottom: 120),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        if (index >= songs.length) return null;
                        final song = songs[index];
                        final isCurrent = song.id == currentSongId;

                        return _PlaylistSongTile(
                          song: song,
                          index: index,
                          isCurrent: isCurrent,
                          isPlaying: isCurrent && widget.controller.isPlaying,
                          onTap: () => _playSongAt(songs, index),
                          onMoreTap: () => _showSongOptions(context, song),
                        );
                      },
                      childCount: songs.length,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Bottom Sheet / Persistent widgets:
          // Sticky mini-player bar above the bottom navigation
          bottomSheet: Container(
            color: Colors.black,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BottomPlayerBar(
                  controller: widget.controller,
                  onOpenLyrics: () => _openLyrics(context),
                ),
                BottomNavigationBar(
                  currentIndex: _selectedBottomNav,
                  backgroundColor: Colors.black,
                  selectedItemColor: Colors.white,
                  unselectedItemColor: Colors.grey,
                  type: BottomNavigationBarType.fixed,
                  selectedFontSize: 11,
                  unselectedFontSize: 11,
                  elevation: 8,
                  onTap: (idx) {
                    setState(() => _selectedBottomNav = idx);
                    if (idx == 0) {
                      // Home
                      widget.controller.setNavIndex(0);
                      Navigator.of(context).pop();
                    } else if (idx == 1) {
                      // Samples
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Samples feed preview active'),
                          backgroundColor: Color(0xFF222222),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    } else if (idx == 2) {
                      // Explore
                      widget.controller.setNavIndex(1);
                      Navigator.of(context).pop();
                    } else if (idx == 3) {
                      // Library
                      widget.controller.setNavIndex(2);
                      Navigator.of(context).pop();
                    }
                  },
                  items: const [
                    BottomNavigationBarItem(
                      icon: Icon(Icons.home_filled),
                      label: 'Home',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.play_circle_outline_rounded),
                      label: 'Samples',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.explore_outlined),
                      label: 'Explore',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.library_music_outlined),
                      label: 'Library',
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSongOptions(BuildContext context, Song song) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF212121),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: SongArtworkWidget(song: song, size: 40, borderRadius: 6),
              title: Text(song.title,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
              subtitle: Text(song.artist,
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ),
            const Divider(color: Colors.white12),
            ListTile(
              leading: const Icon(Icons.playlist_play_rounded, color: Colors.white),
              title: const Text('Play next', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                widget.controller.enqueueNext(song);
              },
            ),
            ListTile(
              leading: const Icon(Icons.queue_music_rounded, color: Colors.white),
              title: const Text('Add to queue', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                widget.controller.enqueue(song);
              },
            ),
            ListTile(
              leading: const Icon(Icons.lyrics_outlined, color: Colors.white),
              title: const Text('View lyrics', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                SpotifyLyricsSheet.show(context,
                    song: song, controller: widget.controller);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined, color: Colors.white),
              title: const Text('Share', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
              },
            ),
            if (widget.playlist != null)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded,
                    color: AppTheme.accentPink),
                title: const Text('Remove from playlist',
                    style: TextStyle(color: AppTheme.accentPink)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await widget.controller
                      .deleteSongFromPlaylist(widget.playlist!.id, song.id);
                  if (mounted) setState(() {});
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeletePlaylist() async {
    final playlist = widget.playlist;
    if (playlist == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: AppTheme.cardSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.border),
        ),
        title: const Text(
          'Delete Playlist',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Are you sure you want to delete "${playlist.title}"?',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentPink,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.of(dCtx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await widget.controller.deletePlaylist(playlist.id);
      if (mounted) Navigator.of(context).pop();
    }
  }
}

/// 2x2 Grid widget for the 4-cover collage with YouTube Music aesthetic
class _CoverCollage2x2 extends StatelessWidget {
  final List<Song> songs;
  final List<Color> fallbackGradient;

  const _CoverCollage2x2({
    required this.songs,
    required this.fallbackGradient,
  });

  @override
  Widget build(BuildContext context) {
    final covers = <Song>[];
    for (final s in songs) {
      if (covers.length >= 4) break;
      covers.add(s);
    }

    return Container(
      width: 220,
      height: 220,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.7),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _buildCoverCell(covers, 0)),
                  Expanded(child: _buildCoverCell(covers, 1)),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _buildCoverCell(covers, 2)),
                  Expanded(child: _buildCoverCell(covers, 3)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoverCell(List<Song> covers, int index) {
    if (index < covers.length) {
      final song = covers[index];
      return SongArtworkWidget(
        song: song,
        size: 110,
        borderRadius: 0,
      );
    }
    // Fallback decorative tile if fewer than 4 songs exist
    final grad = fallbackGradient.length >= 2
        ? fallbackGradient
        : const [Color(0xFF2B2B2B), Color(0xFF141414)];
    final baseColor = grad[index % grad.length];
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            baseColor.withValues(alpha: 0.8),
            const Color(0xFF141414),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(
          Icons.music_note_rounded,
          size: 28,
          color: Colors.white24,
        ),
      ),
    );
  }
}

/// Custom row layout for songs in PlaylistScreen
class _PlaylistSongTile extends StatelessWidget {
  final Song song;
  final int index;
  final bool isCurrent;
  final bool isPlaying;
  final VoidCallback onTap;
  final VoidCallback onMoreTap;

  const _PlaylistSongTile({
    required this.song,
    required this.index,
    required this.isCurrent,
    required this.isPlaying,
    required this.onTap,
    required this.onMoreTap,
  });

  static String _clock(Duration d) {
    final minutes = d.inMinutes;
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      splashColor: Colors.white10,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // Leading cover with play indicator
            Stack(
              alignment: Alignment.center,
              children: [
                SongArtworkWidget(
                  song: song,
                  size: 46,
                  borderRadius: 6,
                ),
                if (isCurrent)
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Center(
                      child: Icon(
                        isPlaying
                            ? Icons.volume_up_rounded
                            : Icons.pause_rounded,
                        color: AppTheme.accentGreen,
                        size: 22,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),

            // Title and subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isCurrent ? AppTheme.accentGreen : Colors.white,
                      fontSize: 14.5,
                      fontWeight:
                          isCurrent ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          song.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                      const Text(
                        ' • ',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      Text(
                        _clock(song.duration),
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Real-time audio locating / full track indicator
                      _buildTrackBadge(song),
                    ],
                  ),
                ],
              ),
            ),

            // Trailing popup menu icon
            IconButton(
              icon: const Icon(Icons.more_vert, color: Colors.grey, size: 20),
              onPressed: onMoreTap,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrackBadge(Song song) {
    if (!song.hasAudio) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: AppTheme.accentPink.withValues(alpha: 0.6),
            width: 1,
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 7,
              height: 7,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: AppTheme.accentPink,
              ),
            ),
            SizedBox(width: 4),
            Text(
              'LOCATING AUDIO',
              style: TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.4,
                color: AppTheme.accentPink,
              ),
            ),
          ],
        ),
      );
    }

    if (song.isFullTrack) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: AppTheme.accentGreen.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: AppTheme.accentGreen.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
        child: const Text(
          'FULL TRACK',
          style: TextStyle(
            fontSize: 8.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
            color: AppTheme.accentGreen,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: Colors.amber.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: const Text(
        'PREVIEW',
        style: TextStyle(
          fontSize: 8.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          color: Colors.amber,
        ),
      ),
    );
  }
}
