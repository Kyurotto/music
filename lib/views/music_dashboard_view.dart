import 'dart:async';
import 'package:flutter/material.dart';
import '../auth/auth_service.dart';
import '../models/song_model.dart';
import '../theme/app_theme.dart';
import '../controllers/music_player_controller.dart';
import '../widgets/sidebar_nav.dart';
import '../widgets/hero_banner.dart';
import '../widgets/album_card.dart';
import '../widgets/track_list_view.dart';
import '../widgets/right_panel.dart';
import '../widgets/bottom_player_bar.dart';
import '../widgets/spotify_lyrics_sheet.dart';
import '../widgets/spotify_import_dialog.dart';
import '../widgets/song_artwork_widget.dart';
import '../services/display_rate_service.dart';
import 'settings_view.dart';
import 'discovery_sections.dart';
import '../services/discovery_service.dart';

class MusicDashboardView extends StatefulWidget {
  const MusicDashboardView({super.key});

  @override
  State<MusicDashboardView> createState() => _MusicDashboardViewState();
}

class _MusicDashboardViewState extends State<MusicDashboardView> {
  late final MusicPlayerController _controller;
  final TextEditingController _searchTextController = TextEditingController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<DiscoverySectionsState> _discoveryKey = GlobalKey<DiscoverySectionsState>();
  bool _pullToRefreshActive = false;
  String? _selectedPlaylistId;
  StreamSubscription<Object?>? _authSub;

  String? _lastSongId;
  bool _lastIsPlaying = false;
  int _lastNavIndex = 0;
  String _lastGenre = 'All';
  String _lastQuery = '';
  int _lastSongCount = 0;
  int _lastPlaylistCount = 0;
  PlaybackRepeatMode _lastRepeatMode = PlaybackRepeatMode.all;
  bool _lastShuffle = false;
  bool _lastIsMuted = false;

  @override
  void initState() {
    super.initState();
    _controller = MusicPlayerController();
    _lastSongId = _controller.currentSong?.id;
    _lastIsPlaying = _controller.isPlaying;
    _lastNavIndex = _controller.currentNavIndex;
    _lastGenre = _controller.selectedGenre;
    _lastQuery = _controller.searchQuery;
    _lastSongCount = _controller.allSongs.length;
    _lastPlaylistCount = _controller.playlists.length;
    _lastRepeatMode = _controller.repeatMode;
    _lastShuffle = _controller.isShuffle;
    _lastIsMuted = _controller.isMuted;
    _controller.addListener(_onStateChange);
    DisplayRateService.instance.initialize();
    _authSub = AuthService.instance.authChanges.listen((_) {
      if (mounted) {
        _controller.loadSavedPlaylists();
      }
    });
  }

  void _onStateChange() {
    if (!mounted) return;
    final currentSongId = _controller.currentSong?.id;
    final isPlaying = _controller.isPlaying;
    final navIndex = _controller.currentNavIndex;
    final genre = _controller.selectedGenre;
    final query = _controller.searchQuery;
    final songCount = _controller.allSongs.length;
    final playlistCount = _controller.playlists.length;
    final repeatMode = _controller.repeatMode;
    final shuffle = _controller.isShuffle;
    final isMuted = _controller.isMuted;

    if (currentSongId != _lastSongId ||
        isPlaying != _lastIsPlaying ||
        navIndex != _lastNavIndex ||
        genre != _lastGenre ||
        query != _lastQuery ||
        songCount != _lastSongCount ||
        playlistCount != _lastPlaylistCount ||
        repeatMode != _lastRepeatMode ||
        shuffle != _lastShuffle ||
        isMuted != _lastIsMuted) {
      _lastSongId = currentSongId;
      _lastIsPlaying = isPlaying;
      _lastNavIndex = navIndex;
      _lastGenre = genre;
      _lastQuery = query;
      _lastSongCount = songCount;
      _lastPlaylistCount = playlistCount;
      _lastRepeatMode = repeatMode;
      _lastShuffle = shuffle;
      _lastIsMuted = isMuted;
      setState(() {});
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _controller.removeListener(_onStateChange);
    _controller.dispose();
    _searchTextController.dispose();
    super.dispose();
  }

  void _openPlaylist(String playlistId) {
    setState(() {
      _selectedPlaylistId = playlistId;
      _controller.setNavIndex(2);
    });
  }

  void _selectPlaylist(String playlistId) {
    setState(() => _selectedPlaylistId = playlistId);
  }

  void _playSongWithLyrics(Song song) {
    _controller.playSong(song);
    SpotifyLyricsSheet.show(
      context,
      song: song,
      controller: _controller,
    );
  }

  void _playPlaylistWithLyrics(String playlistId) {
    _controller.playPlaylist(playlistId);
    final song = _controller.currentSong;
    if (song != null) {
      SpotifyLyricsSheet.show(
        context,
        song: song,
        controller: _controller,
      );
    }
  }

  void _showLyricsForCurrentSong() {
    final song = _controller.currentSong ?? _controller.allSongs.firstOrNull;
    if (song != null) {
      SpotifyLyricsSheet.show(
        context,
        song: song,
        controller: _controller,
      );
    }
  }

  Future<void> _showCreatePlaylistDialog() async {
    final title = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => const _CreatePlaylistDialog(),
    );

    if (title != null && title.trim().isNotEmpty && mounted) {
      if (_controller.createPlaylist(title.trim())) {
        final playlist = _controller.playlists.last;
        setState(() => _selectedPlaylistId = playlist.id);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${playlist.title}" is ready for songs.')),
        );
      }
    }
  }

  Future<void> _importFromSpotify() async {
    final playlistId = await SpotifyImportDialog.show(context, controller: _controller);
    if (playlistId == null || !mounted) return;
    setState(() {
      _controller.setNavIndex(2);
      _selectedPlaylistId = playlistId;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text(
              'Spotify tracks imported. Full audio + lyrics load automatically.')),
    );
  }

  /// Pull-to-refresh: reloads saved playlists and forces fresh discovery
  /// rows (Quick Picks, Covers & Remixes, Community Favorites, Trending For You)
  /// and immediately fast-locates their tracks.
  Future<void> _handleRefresh() async {
    await Future.wait([
      _controller.loadSavedPlaylists(),
      _refreshDiscovery(),
    ]);
    _controller.kickBackfill();
  }

  Future<void> _refreshDiscovery() async {
    final discoveryState = _discoveryKey.currentState;
    if (discoveryState != null) {
      await discoveryState.refresh();
    } else {
      final sections = await DiscoveryService.instance.loadAll(forceRefresh: true);
      final allSongs = sections.expand((s) => s.songs).toList();
      _controller.fastLocateDiscoverySongs(allSongs);
    }
  }

  Future<void> _showAddToPlaylistSheet(Song song) async {
    final selectedPlaylist = await showModalBottomSheet<MusicPlaylist>(
      context: context,
      backgroundColor: AppTheme.surface,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Add "${song.title}" to playlist',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ..._controller.playlists.map(
                (playlist) => ListTile(
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      gradient: LinearGradient(colors: playlist.gradient),
                    ),
                    child: const Icon(Icons.queue_music_rounded,
                        color: Colors.white, size: 20),
                  ),
                  title: Text(playlist.title),
                  subtitle: Text('${playlist.trackCount} songs'),
                  trailing: playlist.songIds.contains(song.id)
                      ? const Icon(Icons.check_rounded, color: AppTheme.primary)
                      : const Icon(Icons.add_rounded),
                  onTap: () => Navigator.of(sheetContext).pop(playlist),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (selectedPlaylist != null && mounted) {
      final added = _controller.addSongToPlaylist(selectedPlaylist.id, song);
      if (added && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added to ${selectedPlaylist.title}.')),
        );
      }
    }
  }

  Future<void> _confirmDeletePlaylist(MusicPlaylist playlist) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
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
          'Are you sure you want to delete "${playlist.title}" from your library and database?',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentPink,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final title = playlist.title;
      if (_selectedPlaylistId == playlist.id) {
        setState(() => _selectedPlaylistId = null);
      }
      await _controller.deletePlaylist(playlist.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deleted "$title" from library and database.'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _confirmDeleteSongFromPlaylist(
    MusicPlaylist playlist,
    Song song,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppTheme.cardSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.border),
        ),
        title: const Text(
          'Delete Song',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Are you sure you want to remove "${song.title}" from "${playlist.title}" and delete it from the database?',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentPink,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _controller.deleteSongFromPlaylist(playlist.id, song.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deleted "${song.title}" from database.'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _confirmDeleteSong(Song song) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppTheme.cardSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.border),
        ),
        title: const Text(
          'Delete Song',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Are you sure you want to delete "${song.title}" from your library and database?',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentPink,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _controller.deleteSong(song.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deleted "${song.title}" from database.'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 1150;
        final isMobile = constraints.maxWidth < 750;

        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: AppTheme.background,
          drawer: isMobile
              ? Drawer(
                  backgroundColor: AppTheme.surface,
                  child: SafeArea(
                    child: SidebarNav(
                      controller: _controller,
                      selectedPlaylistId: _selectedPlaylistId,
                      onPlaylistSelected: (id) {
                        Navigator.of(context).pop();
                        _openPlaylist(id);
                      },
                      onCreatePlaylist: () {
                        Navigator.of(context).pop();
                        _showCreatePlaylistDialog();
                      },
                      onImportSpotify: () {
                        Navigator.of(context).pop();
                        _importFromSpotify();
                      },
                    ),
                  ),
                )
              : null,
          body: SafeArea(
            child: Column(
              children: [
                // Main Body Area
                Expanded(
                  child: Row(
                    children: [
                      // Persistent Sidebar for Desktop and Tablet
                      if (!isMobile)
                        SidebarNav(
                          controller: _controller,
                          selectedPlaylistId: _selectedPlaylistId,
                          onPlaylistSelected: _openPlaylist,
                          onCreatePlaylist: _showCreatePlaylistDialog,
                          onImportSpotify: _importFromSpotify,
                        ),

                      // Main Content View
                      Expanded(
                        child: Column(
                          children: [
                            // Top App Bar / Search Header
                            _buildTopHeader(isMobile, isDesktop),

                            // Scrollable Feed (pull down to refresh +
                            // re-resolve locating tracks)
                            Expanded(
                              child: RefreshIndicator(
                                onRefresh: _handleRefresh,
                                color: AppTheme.primary,
                                backgroundColor: AppTheme.cardSurface,
                                notificationPredicate: (notification) {
                                  // Only the page's own vertical scroll counts. Horizontal
                                  // discovery carousels (depth > 0, pixels == 0) used to flip
                                  // the flag on, so scrolling up from below showed the circle.
                                  if (notification.depth != 0 ||
                                      notification.metrics.axis != Axis.vertical) {
                                    return false;
                                  }
                                  if (notification is ScrollStartNotification) {
                                    // Pull-to-refresh only when the drag began at the very top.
                                    _pullToRefreshActive =
                                        notification.metrics.pixels <= 0;
                                  }
                                  final active = _pullToRefreshActive;
                                  if (notification is ScrollEndNotification) {
                                    // The indicator must still see this end event; reset
                                    // afterwards so a fling that overscrolls the top (started
                                    // lower down) can never trigger the circle.
                                    _pullToRefreshActive = false;
                                  }
                                  return active;
                                },
                                child: SingleChildScrollView(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  padding: EdgeInsets.symmetric(
                                    horizontal: isMobile ? 16 : 28,
                                    vertical: 20,
                                  ),
                                  child: _buildCurrentTabContent(isMobile),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Right Activity / Now Playing Panel on Wide Screens
                      if (isDesktop)
                        ListenableBuilder(
                          listenable: _controller,
                          builder: (context, _) => RightActivityPanel(
                            controller: _controller,
                            onOpenLyrics: _showLyricsForCurrentSong,
                            onPlaySong: _playSongWithLyrics,
                          ),
                        ),
                    ],
                  ),
                ),

                // Persistent Bottom Player
                ListenableBuilder(
                  listenable: _controller,
                  builder: (context, _) => BottomPlayerBar(
                    controller: _controller,
                    onOpenLyrics: _showLyricsForCurrentSong,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopHeader(bool isMobile, bool isDesktop) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 24,
        vertical: 12,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          bottom: BorderSide(color: AppTheme.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Drawer Hamburger for Mobile
          if (isMobile)
            IconButton(
              icon: const Icon(Icons.menu_rounded, color: AppTheme.textPrimary),
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            ),

          // Search Input Bar
          Expanded(
            child: Container(
              height: 42,
              decoration: BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border, width: 1),
              ),
              child: TextField(
                controller: _searchTextController,
                onChanged: (val) => _controller.setSearchQuery(val),
                style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search songs, artists, albums...',
                  hintStyle: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
                  prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppTheme.textSecondary),
                  suffixIcon: _searchTextController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 16, color: AppTheme.textMuted),
                          onPressed: () {
                            _searchTextController.clear();
                            _controller.setSearchQuery('');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),

          const SizedBox(width: 12),

          // Notifications button
          IconButton(
            tooltip: 'Notifications',
            icon: const Icon(Icons.notifications_none_rounded, size: 22, color: AppTheme.textSecondary),
            onPressed: () {},
          ),

          // Settings button
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined, size: 22, color: AppTheme.textSecondary),
            onPressed: () => SettingsView.show(context, controller: _controller),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentTabContent(bool isMobile) {
    switch (_controller.currentNavIndex) {
      case 1:
        return _buildExploreTab();
      case 2:
        return _buildLibraryTab();
      case 3:
        return _buildFavoritesTab();
      case 0:
      default:
        return _buildHomeFeed(isMobile);
    }
  }

  /// Selected-playlist detail shared by the Library tab and the dashboard,
  /// so tapping a featured playlist on the dashboard opens it right here
  /// instead of jumping to the Library tab.
  Widget _buildSelectedPlaylistDetail(MusicPlaylist selectedPlaylist) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeaderWithActions(
          title: selectedPlaylist.title,
          subtitle:
              '${selectedPlaylist.trackCount} ${selectedPlaylist.trackCount == 1 ? 'song' : 'songs'}',
          actions: [
            if (_controller.songsForPlaylist(selectedPlaylist.id).isNotEmpty)
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => _playPlaylistWithLyrics(selectedPlaylist.id),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Play'),
              ),
            ElevatedButton.icon(
              key: const ValueKey('delete_selected_playlist_btn'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.cardSurface,
                foregroundColor: AppTheme.accentPink,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: AppTheme.accentPink.withValues(alpha: 0.6),
                    width: 1,
                  ),
                ),
              ),
              onPressed: () => _confirmDeletePlaylist(selectedPlaylist),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text('Delete playlist'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.cardSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.border, width: 1),
          ),
          child: TrackListView(
            songs: _controller.songsForPlaylist(selectedPlaylist.id),
            controller: _controller,
            onSongTap: _playSongWithLyrics,
            onAddToPlaylist: _showAddToPlaylistSheet,
            onDelete: (song) => _confirmDeleteSongFromPlaylist(selectedPlaylist, song),
            emptyTitle: 'No songs in this playlist yet',
            emptySubtitle: 'Add songs from "All saved songs" below by clicking "+"',
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildHomeFeed(bool isMobile) {
    final featuredSong = _controller.allSongs.where((s) => s.isFeatured).firstOrNull ??
        _controller.allSongs.firstOrNull;
    final playlists = _controller.playlists;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Genre filter pills
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: SampleMusicData.genres.map((genre) {
              final isSelected = _controller.selectedGenre == genre;
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: FilterChip(
                  label: Text(genre),
                  selected: isSelected,
                  onSelected: (_) => _controller.setSelectedGenre(genre),
                  backgroundColor: AppTheme.cardSurface,
                  selectedColor: AppTheme.primary,
                  checkmarkColor: Colors.white,
                  labelStyle: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? Colors.white : AppTheme.textSecondary,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: isSelected ? AppTheme.primary : AppTheme.border,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        const SizedBox(height: 24),

        // Hero Banner (Featured Release)
        if (_controller.searchQuery.isEmpty) ...[
          HeroBanner(
            song: featuredSong,
            controller: _controller,
            onPlaySong: _playSongWithLyrics,
          ),
          const SizedBox(height: 32),
        ],

        if (_controller.searchQuery.isEmpty && _controller.selectedGenre == 'All') ...[
          DiscoverySections(
            key: _discoveryKey,
            controller: _controller,
          ),
          const SizedBox(height: 32),
        ],

        // Quick Jump In (Recently Played Grid)
        if (_controller.searchQuery.isEmpty && _controller.selectedGenre == 'All') ...[
          _buildSectionHeader('Jump Back In', 'Recent listening highlights'),
          const SizedBox(height: 14),
          _buildQuickGrid(),
          const SizedBox(height: 32),
        ],

        // Featured Playlists Carousel
        if (_controller.searchQuery.isEmpty) ...[
          _buildSectionHeader('Featured Playlists', 'Fresh playlists updated for you'),
          const SizedBox(height: 14),
          SizedBox(
            height: 230,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: playlists.length,
              separatorBuilder: (context, index) => const SizedBox(width: 16),
              itemBuilder: (context, index) {
                final playlist = playlists[index];
                return AlbumCard(
                  playlist: playlist,
                  isSelected: playlist.id == _selectedPlaylistId,
                  // Stay on the dashboard: the detail opens inline above.
                  onTap: () => _selectPlaylist(playlist.id),
                  onPlay: () => _playPlaylistWithLyrics(playlist.id),
                );
              },
            ),
          ),
          const SizedBox(height: 32),
        ],

        // Main Songs Section Header
        _buildSectionHeader(
          _controller.searchQuery.isNotEmpty
              ? 'Search Results'
              : _controller.selectedGenre == 'All'
                  ? 'Trending English Songs'
                  : '${_controller.selectedGenre} Tracks',
          '${_controller.filteredSongs.length} tracks available',
        ),
        const SizedBox(height: 16),

        // Interactive Track Table
        Container(
          decoration: BoxDecoration(
            color: AppTheme.cardSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.border, width: 1),
          ),
          child: TrackListView(
            songs: _controller.filteredSongs,
            controller: _controller,
            onSongTap: _playSongWithLyrics,
            onAddToPlaylist: _showAddToPlaylistSheet,
          ),
        ),
      ],
    );
  }

  Widget _buildQuickGrid() {
    final recentSongs = _controller.allSongs.take(6).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 900 ? 3 : 2;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: recentSongs.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisExtent: 64,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemBuilder: (context, index) {
            final song = recentSongs[index];
            final isCurrent = _controller.currentSong?.id == song.id;

            return Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _playSongWithLyrics(song),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isCurrent ? AppTheme.primary.withValues(alpha: 0.15) : AppTheme.cardSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isCurrent ? AppTheme.primary.withValues(alpha: 0.5) : AppTheme.border,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      SongArtworkWidget(
                        song: song,
                        size: 48,
                        borderRadius: 8,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              song.title,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isCurrent ? AppTheme.primary : AppTheme.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              song.artist,
                              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isCurrent ? AppTheme.primary : Colors.white.withValues(alpha: 0.1),
                        ),
                        child: Center(
                          child: Icon(
                            isCurrent && _controller.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Sizes playlist grid cells to fit [AlbumCard] content at any width.
  ///
  /// Mirrors [SliverGridDelegateWithMaxCrossAxisExtent]'s own column math
  /// (count = ceil(width / (maxExtent + spacing))) so the fixed-height cell
  /// always clears the card's square artwork plus title and subtitle.
  SliverGridDelegate _albumGridDelegate(double gridWidth, {double maxExtent = 210}) {
    const spacing = 16.0;
    var count = (gridWidth / (maxExtent + spacing)).ceil();
    if (count < 1) count = 1;
    final cardWidth = (gridWidth - spacing * (count - 1)) / count;
    return SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: maxExtent,
      mainAxisExtent: cardWidth + 88,
      crossAxisSpacing: spacing,
      mainAxisSpacing: spacing,
    );
  }

  Widget _buildExploreTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Explore Playlists', 'Find soundscapes crafted for your day'),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) => GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _controller.playlists.length,
            gridDelegate: _albumGridDelegate(constraints.maxWidth, maxExtent: 220),
            itemBuilder: (context, index) {
              final playlist = _controller.playlists[index];
              return AlbumCard(
                playlist: playlist,
                isSelected: playlist.id == _selectedPlaylistId,
                onTap: () => _openPlaylist(playlist.id),
                onPlay: () => _playPlaylistWithLyrics(playlist.id),
              );
            },
          ),
        ),
        const SizedBox(height: 32),
        _buildSectionHeader('All Available Catalog', 'Complete library tracks'),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.cardSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.border, width: 1),
          ),
          child: TrackListView(
            songs: _controller.allSongs,
            controller: _controller,
            onSongTap: _playSongWithLyrics,
            onAddToPlaylist: _showAddToPlaylistSheet,
          ),
        ),
      ],
    );
  }

  /// Section header plus action buttons. Stacks vertically below 560 px
  /// instead of overflowing on narrow screens.
  Widget _buildHeaderWithActions({
    required String title,
    required String subtitle,
    required List<Widget> actions,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 560;
        final header = _buildSectionHeader(title, subtitle);
        final actionWrap = Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: narrow ? WrapAlignment.start : WrapAlignment.end,
          children: actions,
        );
        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              header,
              const SizedBox(height: 12),
              actionWrap,
            ],
          );
        }
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(child: header),
            const SizedBox(width: 12),
            Flexible(child: actionWrap),
          ],
        );
      },
    );
  }

  Widget _buildLibraryTab() {
    final selectedPlaylist = _selectedPlaylistId == null
        ? null
        : _controller.playlistById(_selectedPlaylistId!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeaderWithActions(
          title: 'Your Library',
          subtitle:
              '${_controller.allSongs.length} saved songs across ${_controller.playlists.length} playlists',
          actions: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.cardSurface,
                foregroundColor: AppTheme.textPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: AppTheme.border),
                ),
              ),
              onPressed: _importFromSpotify,
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Import Spotify link'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _showCreatePlaylistDialog,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Create playlist'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) => GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _controller.playlists.length,
            gridDelegate: _albumGridDelegate(constraints.maxWidth),
            itemBuilder: (context, index) {
              final playlist = _controller.playlists[index];
              return AlbumCard(
                playlist: playlist,
                isSelected: playlist.id == _selectedPlaylistId,
                onTap: () => _selectPlaylist(playlist.id),
                onPlay: () => _playPlaylistWithLyrics(playlist.id),
                onDelete: () => _confirmDeletePlaylist(playlist),
              );
            },
          ),
        ),
        const SizedBox(height: 32),
        if (selectedPlaylist != null)
          _buildSelectedPlaylistDetail(selectedPlaylist),
        _buildSectionHeader('All saved songs', 'Add any song to a playlist'),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.cardSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.border, width: 1),
          ),
          child: TrackListView(
            songs: _controller.allSongs,
            controller: _controller,
            onSongTap: _playSongWithLyrics,
            onAddToPlaylist: _showAddToPlaylistSheet,
            onDelete: (song) => _confirmDeleteSong(song),
          ),
        ),
      ],
    );
  }

  Widget _buildFavoritesTab() {
    final favorites = _controller.favoriteSongs;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeaderWithActions(
          title: 'Favorite Songs',
          subtitle: '${favorites.length} songs you love',
          actions: [
            if (favorites.isNotEmpty)
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Play All'),
                onPressed: () => _playSongWithLyrics(favorites.first),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.cardSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.border, width: 1),
          ),
          child: TrackListView(
            songs: favorites,
            controller: _controller,
            onSongTap: _playSongWithLyrics,
            onAddToPlaylist: _showAddToPlaylistSheet,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 13,
            color: AppTheme.textMuted,
          ),
        ),
      ],
    );
  }
}

class _CreatePlaylistDialog extends StatefulWidget {
  const _CreatePlaylistDialog();

  @override
  State<_CreatePlaylistDialog> createState() => _CreatePlaylistDialogState();
}

class _CreatePlaylistDialogState extends State<_CreatePlaylistDialog> {
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _nameController.text.trim();
    if (text.isNotEmpty) {
      Navigator.of(context).pop(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      title: const Text(
        'Create playlist',
        style: TextStyle(color: AppTheme.textPrimary),
      ),
      content: TextField(
        controller: _nameController,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        style: const TextStyle(color: AppTheme.textPrimary),
        decoration: const InputDecoration(
          hintText: 'My new playlist',
          hintStyle: TextStyle(color: AppTheme.textMuted),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: const Text('Create'),
        ),
      ],
    );
  }
}