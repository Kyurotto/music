import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
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
import 'playlist_screen.dart';
import '../services/discovery_service.dart';
import '../services/radio_discovery_service.dart';

class MusicDashboardView extends StatefulWidget {
  const MusicDashboardView({super.key});

  @override
  State<MusicDashboardView> createState() => _MusicDashboardViewState();
}

class _MusicDashboardViewState extends State<MusicDashboardView> {
  late final MusicPlayerController _controller;
  final TextEditingController _searchTextController = TextEditingController();
  final TextEditingController _librarySearchController =
      TextEditingController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<DiscoverySectionsState> _discoveryKey =
      GlobalKey<DiscoverySectionsState>();
  bool _pullToRefreshActive = false;
  String? _selectedPlaylistId;
  StreamSubscription<Object?>? _authSub;

  String _libraryFilter = 'All'; // 'All', 'Playlists', 'Artists', 'Albums'
  String _librarySearchQuery = '';
  bool _isLibraryGridView = false;
  int _libraryVisibleCount = 40;
  final ScrollController _pageScrollController = ScrollController();
  String _exploreCategory = 'All'; // 'All', 'Music', 'Podcasts', 'Audiobooks'
  List<RadioStation> _dynamicPopularRadios = [];
  bool _isLoadingDynamicRadios = false;
  final TextEditingController _radioSearchController = TextEditingController();

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
  int _lastExplicitNoticeVersion = 0;

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
    _lastPlaylistCount = _controller.libraryPlaylists.length;
    _lastRepeatMode = _controller.repeatMode;
    _lastShuffle = _controller.isShuffle;
    _lastIsMuted = _controller.isMuted;
    _lastExplicitNoticeVersion = _controller.explicitBlockNoticeVersion;
    _controller.addListener(_onStateChange);
    _pageScrollController.addListener(_onPageScroll);
    DisplayRateService.instance.initialize();
    _authSub = AuthService.instance.authChanges.listen((_) {
      if (mounted) {
        _controller.loadSavedPlaylists();
      }
    });
    _dynamicPopularRadios = RadioDiscoveryService.instance.getPopularRadios();
    _controller.preLocateExploreRadios(_dynamicPopularRadios);
    final isTest = !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
    if (!isTest) {
      _controller.autoDownloadExploreRadios([
        ..._dynamicPopularRadios,
        ...RadioDiscoveryService.instance.getOpmRadios(),
        ...RadioDiscoveryService.instance.getGlobalRadios(),
      ]);
    }
    _loadDynamicRadios();
  }

  Future<void> _loadDynamicRadios() async {
    if (_isLoadingDynamicRadios) return;
    setState(() => _isLoadingDynamicRadios = true);
    try {
      // Start all three fetches together, but wait for the OPM/Global rows
      // too. Previously they completed after the rebuild, so those carousels
      // kept rendering fallback stations with zero songs — and Download All
      // silently did nothing until the next rebuild.
      final trendingFuture = RadioDiscoveryService.instance
          .fetchTrendingRadios();
      final opmFuture = RadioDiscoveryService.instance.fetchOpmRadios();
      final globalFuture = RadioDiscoveryService.instance.fetchGlobalRadios();

      final stations = await trendingFuture;
      final opmStations = await opmFuture;
      final globalStations = await globalFuture;

      if (mounted) {
        setState(() {
          _dynamicPopularRadios = stations;
          _isLoadingDynamicRadios = false;
        });
        _controller.preLocateExploreRadios(stations);
        final isTest = !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
        if (!isTest) {
          _controller.autoDownloadExploreRadios([
            ...stations,
            ...opmStations,
            ...globalStations,
          ]);
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingDynamicRadios = false);
      }
    }
  }

  void _fastImportRadio(RadioStation station) {
    _controller.fastImportRadioStation(station);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Successfully imported "${station.title}" (${station.songs.length} tracks) to your Library!',
        ),
        backgroundColor: AppTheme.accentGreen,
        action: SnackBarAction(
          label: 'View',
          textColor: Colors.black,
          onPressed: () {
            _controller.setNavIndex(2);
          },
        ),
      ),
    );
  }

  Future<void> _searchRadioStation(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _dynamicPopularRadios = RadioDiscoveryService.instance
            .getPopularRadios();
      });
      return;
    }
    setState(() => _isLoadingDynamicRadios = true);
    try {
      final station = await RadioDiscoveryService.instance.searchSpotifyRadio(
        trimmed,
      );
      if (mounted) {
        setState(() {
          final existing = List<RadioStation>.from(_dynamicPopularRadios);
          existing.removeWhere((s) => s.id == station.id);
          _dynamicPopularRadios = [station, ...existing];
          _isLoadingDynamicRadios = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingDynamicRadios = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No Spotify radio found for "$trimmed"'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    }
  }

  /// Loads more library playlists as the page nears the bottom instead of
  /// building every card/row at once.
  void _onPageScroll() {
    if (_controller.currentNavIndex != 2) return;
    if (!_pageScrollController.hasClients) return;
    final position = _pageScrollController.position;
    if (!position.hasContentDimensions) return;
    if (position.extentAfter > 600) return;
    final total = _controller.libraryPlaylists.length;
    if (_libraryVisibleCount >= total) return;
    setState(() {
      _libraryVisibleCount += 40;
    });
  }

  void _onStateChange() {
    if (!mounted) return;
    final noticeVersion = _controller.explicitBlockNoticeVersion;
    if (noticeVersion != _lastExplicitNoticeVersion) {
      _lastExplicitNoticeVersion = noticeVersion;
      final notice = _controller.explicitBlockNotice;
      if (notice != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(notice),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
        _controller.clearExplicitBlockNotice();
      }
    }
    final currentSongId = _controller.currentSong?.id;
    final isPlaying = _controller.isPlaying;
    final navIndex = _controller.currentNavIndex;
    final genre = _controller.selectedGenre;
    final query = _controller.searchQuery;
    final songCount = _controller.allSongs.length;
    final playlistCount = _controller.libraryPlaylists.length;
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
    _pageScrollController
      ..removeListener(_onPageScroll)
      ..dispose();
    _controller.dispose();
    _searchTextController.dispose();
    _librarySearchController.dispose();
    _radioSearchController.dispose();
    super.dispose();
  }

  void _openPlaylist(String playlistId) {
    setState(() {
      _selectedPlaylistId = playlistId;
    });

    final playlist = _controller.playlistById(playlistId);
    if (playlist != null) {
      Navigator.of(
        context,
      ).push(PlaylistScreen.route(playlist: playlist, controller: _controller));
      return;
    }

    final radio = RadioDiscoveryService.instance
        .getPopularRadios()
        .where((r) => r.id == playlistId || 'radio-${r.id}' == playlistId)
        .firstOrNull;
    if (radio != null) {
      Navigator.of(context).push(
        PlaylistScreen.route(
          playlist: radio.toPlaylist(),
          songs: radio.songs,
          controller: _controller,
        ),
      );
      return;
    }

    if (playlistId == 'playlist-2000s' || playlistId == '2000s') {
      final p2000s = MusicPlaylist(
        id: 'playlist-2000s',
        title: "2000's",
        subtitle: 'loser',
        gradient: const [Color(0xFFF59E0B), Color(0xFFD97706)],
        imageUrl: '',
        songIds: [],
      );
      Navigator.of(
        context,
      ).push(PlaylistScreen.route(playlist: p2000s, controller: _controller));
      return;
    }

    // Default fallback to Library navigation
    _controller.setNavIndex(2);
  }

  void _playSongWithLyrics(Song song) {
    _controller.playSong(song);
    SpotifyLyricsSheet.show(context, song: song, controller: _controller);
  }

  void _playPlaylistWithLyrics(String playlistId) {
    _controller.playPlaylist(playlistId);
    final song = _controller.currentSong;
    if (song != null) {
      SpotifyLyricsSheet.show(context, song: song, controller: _controller);
    }
  }

  void _showLyricsForCurrentSong() {
    final song = _controller.currentSong ?? _controller.allSongs.firstOrNull;
    if (song != null) {
      SpotifyLyricsSheet.show(context, song: song, controller: _controller);
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
    final playlistId = await SpotifyImportDialog.show(
      context,
      controller: _controller,
    );
    if (playlistId == null || !mounted) return;
    setState(() {
      _controller.setNavIndex(2);
      _selectedPlaylistId = playlistId;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Spotify tracks imported. Downloading with 3 workers for offline playback...',
        ),
      ),
    );
  }

  /// Pull-to-refresh: reloads saved playlists and forces fresh discovery
  /// rows (Quick Picks, Covers & Remixes, Community Favorites, Trending For You)
  /// and immediately fast-locates their tracks.
  Future<void> _handleRefresh() async {
    await Future.wait([_controller.loadSavedPlaylists(), _refreshDiscovery()]);
    _controller.kickBackfill();
  }

  Future<void> _refreshDiscovery() async {
    final discoveryState = _discoveryKey.currentState;
    if (discoveryState != null) {
      await discoveryState.refresh();
    } else {
      final sections = await DiscoveryService.instance.loadAll(
        forceRefresh: true,
      );
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
              Text(
                'Add "${song.title}" to playlist',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ..._controller.libraryPlaylists.map(
                (playlist) => ListTile(
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      gradient: LinearGradient(colors: playlist.gradient),
                    ),
                    child: const Icon(
                      Icons.queue_music_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  title: Text(playlist.title),
                  subtitle: Text('${playlist.trackCount} songs'),
                  trailing:
                      (playlist.songIds.contains(song.id) ||
                          _controller
                              .songsForPlaylist(playlist.id)
                              .any(
                                (s) =>
                                    MusicPlayerController.isSameSong(s, song),
                              ))
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
      } else if (!added && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '"${song.title}" is already in ${selectedPlaylist.title}.',
            ),
          ),
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
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppTheme.textMuted),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentPink,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
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
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppTheme.textMuted),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentPink,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
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
                                      notification.metrics.axis !=
                                          Axis.vertical) {
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
                                  controller: _pageScrollController,
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  padding: EdgeInsets.symmetric(
                                    horizontal: isMobile ? 16 : 28,
                                    vertical: 20,
                                  ),
                                  child: ListenableBuilder(
                                    listenable: _controller,
                                    builder: (context, _) =>
                                        _buildCurrentTabContent(isMobile),
                                  ),
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
        border: Border(bottom: BorderSide(color: AppTheme.border, width: 1)),
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
                style: const TextStyle(
                  fontSize: 14,
                  color: AppTheme.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Search songs, artists, albums...',
                  hintStyle: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textMuted,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: AppTheme.textSecondary,
                  ),
                  suffixIcon: _searchTextController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(
                            Icons.clear_rounded,
                            size: 16,
                            color: AppTheme.textMuted,
                          ),
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
            icon: const Icon(
              Icons.notifications_none_rounded,
              size: 22,
              color: AppTheme.textSecondary,
            ),
            onPressed: () {},
          ),

          // Settings button
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(
              Icons.settings_outlined,
              size: 22,
              color: AppTheme.textSecondary,
            ),
            onPressed: () =>
                SettingsView.show(context, controller: _controller),
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

  Widget _buildHomeFeed(bool isMobile) {
    final featuredSong =
        _controller.allSongs.where((s) => s.isFeatured).firstOrNull ??
        _controller.allSongs.firstOrNull;
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

        if (_controller.searchQuery.isEmpty &&
            _controller.selectedGenre == 'All') ...[
          DiscoverySections(key: _discoveryKey, controller: _controller),
          const SizedBox(height: 32),
        ],

        // Search Results or Genre Tracks (Trending English Songs, Jump Back In, and Featured Playlists removed to reduce scrolling lag)
        if (_controller.searchQuery.isNotEmpty ||
            _controller.selectedGenre != 'All') ...[
          _buildSectionHeader(
            _controller.searchQuery.isNotEmpty
                ? 'Search Results'
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
              onDelete: (song) => _confirmDeleteSong(song),
            ),
          ),
        ],
      ],
    );
  }

  /// Sizes playlist grid cells to fit [AlbumCard] content at any width.
  ///
  /// Mirrors [SliverGridDelegateWithMaxCrossAxisExtent]'s own column math
  /// (count = ceil(width / (maxExtent + spacing))) so the fixed-height cell
  /// always clears the card's square artwork plus title and subtitle.
  SliverGridDelegate _albumGridDelegate(
    double gridWidth, {
    double maxExtent = 210,
  }) {
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
    final popularRadios = _dynamicPopularRadios.isNotEmpty
        ? _dynamicPopularRadios
        : RadioDiscoveryService.instance.getPopularRadios();
    final opmRadios = RadioDiscoveryService.instance.getOpmRadios();
    final globalRadios = RadioDiscoveryService.instance.getGlobalRadios();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category Pills (All, Music, Podcasts, Audiobooks) as seen in Screenshot 1
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: ['All', 'Music', 'Podcasts', 'Audiobooks'].map((cat) {
              final isSelected = _exploreCategory == cat;
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: FilterChip(
                  label: Text(cat),
                  selected: isSelected,
                  onSelected: (_) => setState(() => _exploreCategory = cat),
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

        const SizedBox(height: 16),

        // Spotify Radio / Artist Dynamic Search Bar
        Container(
          height: 44,
          decoration: BoxDecoration(
            color: AppTheme.cardSurface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: [
              const SizedBox(width: 14),
              const Icon(
                Icons.search_rounded,
                size: 20,
                color: AppTheme.textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _radioSearchController,
                  onSubmitted: _searchRadioStation,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textPrimary,
                  ),
                  decoration: const InputDecoration(
                    hintText:
                        'Search any Spotify radio or artist (e.g. Flow G, Air Supply, LANY, Ben&Ben)...',
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textMuted,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              if (_isLoadingDynamicRadios)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.accentGreen,
                    ),
                  ),
                )
              else if (_radioSearchController.text.isNotEmpty)
                IconButton(
                  icon: const Icon(
                    Icons.clear_rounded,
                    size: 16,
                    color: AppTheme.textMuted,
                  ),
                  onPressed: () {
                    _radioSearchController.clear();
                    _searchRadioStation('');
                  },
                )
              else
                IconButton(
                  tooltip: 'Search radio',
                  icon: const Icon(
                    Icons.arrow_forward_rounded,
                    size: 16,
                    color: AppTheme.accentGreen,
                  ),
                  onPressed: () =>
                      _searchRadioStation(_radioSearchController.text),
                ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Section 1: "Popular radio" matching Screenshot 2 & 3
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Popular radio',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            Row(
              children: [
                if (_isLoadingDynamicRadios) ...[
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.accentGreen,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                TextButton(
                  onPressed: _loadDynamicRadios,
                  child: const Text(
                    'Show all',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Horizontal Carousel of Popular Radio Cards
        SizedBox(
          height: 250,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: popularRadios.length,
            separatorBuilder: (context, index) => const SizedBox(width: 16),
            itemBuilder: (context, index) {
              final station = popularRadios[index];
              return _PopularRadioCard(
                station: station,
                onTap: () {
                  Navigator.of(context).push(
                    PlaylistScreen.route(
                      playlist: station.toPlaylist(),
                      songs: station.songs,
                      controller: _controller,
                    ),
                  );
                },
                onPlay: () {
                  if (station.songs.isNotEmpty) {
                    _controller.playSongList(station.songs, startIndex: 0);
                  }
                },
                onFastImport: () => _fastImportRadio(station),
              );
            },
          ),
        ),

        const SizedBox(height: 36),

        // Section 2: "More like Sugarfree" (OPM Radio) matching Screenshot 3
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFFFDE047),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.radio_rounded,
                      size: 18,
                      color: Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'More like',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.6),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Text(
                      'Sugarfree',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            TextButton(
              onPressed: () {},
              child: const Text(
                'Show all',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Horizontal Carousel of OPM Radio Cards
        SizedBox(
          height: 250,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: opmRadios.length,
            separatorBuilder: (context, index) => const SizedBox(width: 16),
            itemBuilder: (context, index) {
              final station = opmRadios[index];
              return _PopularRadioCard(
                station: station,
                onTap: () {
                  Navigator.of(context).push(
                    PlaylistScreen.route(
                      playlist: station.toPlaylist(),
                      songs: station.songs,
                      controller: _controller,
                    ),
                  );
                },
                onPlay: () {
                  if (station.songs.isNotEmpty) {
                    _controller.playSongList(station.songs, startIndex: 0);
                  }
                },
                onFastImport: () => _fastImportRadio(station),
              );
            },
          ),
        ),

        const SizedBox(height: 36),

        // Section 3: "More like Maroon 5" (Global Radio) matching Screenshot 1
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFFF87171),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.music_note_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'More like',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.6),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Text(
                      'Maroon 5',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            TextButton(
              onPressed: () {},
              child: const Text(
                'Show all',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Horizontal Carousel of Global Radio Cards
        SizedBox(
          height: 250,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: globalRadios.length,
            separatorBuilder: (context, index) => const SizedBox(width: 16),
            itemBuilder: (context, index) {
              final station = globalRadios[index];
              return _PopularRadioCard(
                station: station,
                onTap: () {
                  Navigator.of(context).push(
                    PlaylistScreen.route(
                      playlist: station.toPlaylist(),
                      songs: station.songs,
                      controller: _controller,
                    ),
                  );
                },
                onPlay: () {
                  if (station.songs.isNotEmpty) {
                    _controller.playSongList(station.songs, startIndex: 0);
                  }
                },
                onFastImport: () => _fastImportRadio(station),
              );
            },
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
        final narrow = constraints.maxWidth < 680;
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
            children: [header, const SizedBox(height: 12), actionWrap],
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
    final allPlaylists = _controller.libraryPlaylists;

    final q = _librarySearchQuery.trim().toLowerCase();

    // Filter playlists
    final filteredPlaylists = allPlaylists.where((p) {
      if (q.isNotEmpty &&
          !p.title.toLowerCase().contains(q) &&
          !p.subtitle.toLowerCase().contains(q)) {
        return false;
      }
      return true;
    }).toList();

    // Only build the first page of cards. More load automatically as the
    // page scrolls, keeping large libraries responsive.
    final visiblePlaylists = filteredPlaylists.length <= _libraryVisibleCount
        ? filteredPlaylists
        : filteredPlaylists.sublist(0, _libraryVisibleCount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with Action Buttons (preserves overflow test expectations)
        _buildHeaderWithActions(
          title: 'Your Library',
          subtitle:
              '${allPlaylists.length} ${allPlaylists.length == 1 ? 'playlist' : 'playlists'}',
          actions: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.cardSurface,
                foregroundColor: AppTheme.textPrimary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _showCreatePlaylistDialog,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Create playlist'),
            ),
          ],
        ),

        const SizedBox(height: 18),

        // Spotify Filter Pills: [All] [Playlists] [Albums]
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: ['All', 'Playlists', 'Albums'].map((filter) {
              final isSelected = _libraryFilter == filter;
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: FilterChip(
                  label: Text(filter),
                  selected: isSelected,
                  onSelected: (_) => setState(() {
                    _libraryFilter = filter;
                    _libraryVisibleCount = 40;
                  }),
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

        const SizedBox(height: 14),

        // Search in Library and Sort / Layout Switcher Row
        Row(
          children: [
            Expanded(
              child: Container(
                height: 38,
                decoration: BoxDecoration(
                  color: AppTheme.cardSurface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.border),
                ),
                child: TextField(
                  controller: _librarySearchController,
                  onChanged: (val) => setState(() {
                    _librarySearchQuery = val;
                    _libraryVisibleCount = 40;
                  }),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search in Your Library...',
                    hintStyle: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textMuted,
                    ),
                    prefixIcon: const Icon(
                      Icons.search,
                      size: 18,
                      color: AppTheme.textSecondary,
                    ),
                    suffixIcon: _librarySearchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(
                              Icons.clear,
                              size: 14,
                              color: AppTheme.textMuted,
                            ),
                            onPressed: () {
                              _librarySearchController.clear();
                              setState(() {
                                _librarySearchQuery = '';
                                _libraryVisibleCount = 40;
                              });
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 9),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Recents indicator & Layout toggle
            Row(
              children: [
                const Text(
                  'Recents',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: _isLibraryGridView
                      ? 'Switch to List view'
                      : 'Switch to Grid view',
                  icon: Icon(
                    _isLibraryGridView
                        ? Icons.list_rounded
                        : Icons.grid_view_rounded,
                    size: 20,
                    color: AppTheme.textSecondary,
                  ),
                  onPressed: () =>
                      setState(() => _isLibraryGridView = !_isLibraryGridView),
                ),
              ],
            ),
          ],
        ),

        const SizedBox(height: 18),

        // The Library Items
        if (filteredPlaylists.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
            decoration: BoxDecoration(
              color: AppTheme.cardSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.library_music_outlined,
                  size: 48,
                  color: AppTheme.textMuted.withValues(alpha: 0.6),
                ),
                const SizedBox(height: 12),
                Text(
                  _librarySearchQuery.isNotEmpty
                      ? 'No playlists match "$_librarySearchQuery"'
                      : 'Your library is empty',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _librarySearchQuery.isNotEmpty
                      ? 'Check your search spelling or clear the filter.'
                      : 'Import a Spotify playlist link or create a new playlist.',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (_librarySearchQuery.isEmpty) ...[
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: _importFromSpotify,
                        icon: const Icon(Icons.download_rounded, size: 16),
                        label: const Text('Import from Spotify'),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.textPrimary,
                          side: const BorderSide(color: AppTheme.border),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: _showCreatePlaylistDialog,
                        icon: const Icon(Icons.add_rounded, size: 16),
                        label: const Text('New playlist'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          )
        else if (_isLibraryGridView)
          // Grid View
          LayoutBuilder(
            builder: (context, constraints) => GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: visiblePlaylists.length,
              gridDelegate: _albumGridDelegate(constraints.maxWidth),
              itemBuilder: (context, index) {
                final playlist = visiblePlaylists[index];
                return AlbumCard(
                  playlist: playlist,
                  isSelected: playlist.id == _selectedPlaylistId,
                  onTap: () => _openPlaylist(playlist.id),
                  onPlay: () => _playPlaylistWithLyrics(playlist.id),
                  onDelete: () => _confirmDeletePlaylist(playlist),
                );
              },
            ),
          )
        else
          // Spotify-style List View
          Container(
            decoration: BoxDecoration(
              color: AppTheme.cardSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.border),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: visiblePlaylists.length,
              separatorBuilder: (context, index) => Divider(
                height: 1,
                thickness: 0.5,
                color: AppTheme.border.withValues(alpha: 0.5),
              ),
              itemBuilder: (context, index) {
                final playlist = visiblePlaylists[index];
                return _LibraryPlaylistTile(
                  playlist: playlist,
                  onTap: () => _openPlaylist(playlist.id),
                  onDelete: () => _confirmDeletePlaylist(playlist),
                );
              },
            ),
          ),
        if (visiblePlaylists.length < filteredPlaylists.length) ...[
          const SizedBox(height: 12),
          Center(
            child: TextButton.icon(
              onPressed: () => setState(() => _libraryVisibleCount += 40),
              icon: const Icon(Icons.expand_more_rounded, size: 18),
              label: Text(
                'Show more playlists (${filteredPlaylists.length - visiblePlaylists.length} remaining)',
              ),
            ),
          ),
        ],
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
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
          style: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
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
        ElevatedButton(onPressed: _submit, child: const Text('Create')),
      ],
    );
  }
}

class _PopularRadioCard extends StatefulWidget {
  final RadioStation station;
  final VoidCallback onTap;
  final VoidCallback onPlay;
  final VoidCallback? onFastImport;

  const _PopularRadioCard({
    required this.station,
    required this.onTap,
    required this.onPlay,
    this.onFastImport,
  });

  @override
  State<_PopularRadioCard> createState() => _PopularRadioCardState();
}

class _PopularRadioCardState extends State<_PopularRadioCard> {
  bool _isHovered = false;

  Widget _buildAvatarCircle({
    required String? url,
    required double size,
    required String fallbackText,
    required List<Color> gradientColors,
  }) {
    final hasUrl = url != null && url.isNotEmpty;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(
        child: hasUrl
            ? Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    _buildFallback(fallbackText, gradientColors, size),
              )
            : _buildFallback(fallbackText, gradientColors, size),
      ),
    );
  }

  Widget _buildFallback(String text, List<Color> gradientColors, double size) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors.length >= 2
              ? gradientColors
              : const [Color(0xFF334155), Color(0xFF64748B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            fontSize: size * 0.38,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final station = widget.station;
    final primaryAvatar = station.avatarUrls.isNotEmpty
        ? station.avatarUrls[0]
        : null;
    final leftAvatar = station.avatarUrls.length > 1
        ? station.avatarUrls[1]
        : null;
    final rightAvatar = station.avatarUrls.length > 2
        ? station.avatarUrls[2]
        : null;

    final initialLetter = station.artistName.isNotEmpty
        ? station.artistName.substring(0, 1).toUpperCase()
        : 'R';

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: SizedBox(
          width: 176,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Colored Pastel Card Container matching Spotify Screenshot
              Container(
                height: 180,
                width: 176,
                decoration: BoxDecoration(
                  color: station.backgroundColor,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Top Bar: Sound/Spotify-style icon and RADIO text
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                width: 22,
                                height: 22,
                                decoration: const BoxDecoration(
                                  color: Colors.black,
                                  shape: BoxShape.circle,
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.graphic_eq_rounded,
                                    size: 13,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const Text(
                                'RADIO',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.black87,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 10),

                          // 3-Avatar Cluster (Center overlapping circles with real artist images)
                          Center(
                            child: SizedBox(
                              height: 80,
                              width: 140,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  // Left collaborator avatar
                                  Positioned(
                                    left: 4,
                                    child: _buildAvatarCircle(
                                      url: leftAvatar,
                                      size: 50,
                                      fallbackText: '1',
                                      gradientColors: const [
                                        Color(0xFF334155),
                                        Color(0xFF64748B),
                                      ],
                                    ),
                                  ),
                                  // Right collaborator avatar
                                  Positioned(
                                    right: 4,
                                    child: _buildAvatarCircle(
                                      url: rightAvatar,
                                      size: 50,
                                      fallbackText: '2',
                                      gradientColors: const [
                                        Color(0xFF1E293B),
                                        Color(0xFF475569),
                                      ],
                                    ),
                                  ),
                                  // Center primary artist avatar
                                  _buildAvatarCircle(
                                    url: primaryAvatar,
                                    size: 70,
                                    fallbackText: initialLetter,
                                    gradientColors: station.gradientColors,
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const Spacer(),

                          // Station Artist Name in solid bold dark text inside the pastel card
                          Text(
                            station.artistName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: Colors.black,
                              letterSpacing: -0.4,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),

                    // Floating Fast Import Button on Hover (bottom left of colored card)
                    if (_isHovered && widget.onFastImport != null)
                      Positioned(
                        left: 10,
                        bottom: 10,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: widget.onFastImport,
                            borderRadius: BorderRadius.circular(18),
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black.withValues(alpha: 0.75),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.4),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.playlist_add_rounded,
                                  color: AppTheme.accentGreen,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                    // Floating Green Play Button on Hover (bottom right of colored card)
                    if (_isHovered)
                      Positioned(
                        right: 10,
                        bottom: 10,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: widget.onPlay,
                            borderRadius: BorderRadius.circular(22),
                            child: Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppTheme.accentGreen,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.5),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.play_arrow_rounded,
                                  color: Colors.black,
                                  size: 28,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // Station Subtitle below card ("With SUPAFLY, Lo ki, Hev Abi and more")
              Text(
                station.subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.65),
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LibraryPlaylistTile extends StatelessWidget {
  final MusicPlaylist playlist;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _LibraryPlaylistTile({
    required this.playlist,
    required this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cleanSubtitle = playlist.subtitle.isNotEmpty
        ? playlist.subtitle
        : (playlist.songIds.isNotEmpty
              ? '${playlist.songIds.length} ${playlist.songIds.length == 1 ? 'song' : 'songs'}'
              : '');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              // Square Artwork with rounded corners (Spotify Style)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: playlist.gradient.isNotEmpty
                          ? playlist.gradient
                          : [const Color(0xFF334155), const Color(0xFF64748B)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: SongArtworkWidget(
                    imageUrl: playlist.imageUrl,
                    title: playlist.title,
                    artist: playlist.subtitle,
                    gradientColors: playlist.gradient,
                    size: 52,
                    borderRadius: 8,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      playlist.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (cleanSubtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        cleanSubtitle,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.textMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (onDelete != null)
                IconButton(
                  tooltip: 'Delete playlist',
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    size: 18,
                    color: AppTheme.textMuted,
                  ),
                  onPressed: onDelete,
                ),
              const SizedBox(width: 4),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: AppTheme.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DailyMixCard extends StatefulWidget {
  final DailyMix mix;
  final VoidCallback onTap;
  final VoidCallback onPlay;

  const _DailyMixCard({
    required this.mix,
    required this.onTap,
    required this.onPlay,
  });

  @override
  State<_DailyMixCard> createState() => _DailyMixCardState();
}

class _DailyMixCardState extends State<_DailyMixCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final mix = widget.mix;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 172,
          decoration: BoxDecoration(
            color: const Color(0xFF181818),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Dual-Tone Header Banner matching Spotify Daily Mix in Screenshot 1
                    Container(
                      height: 130,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        gradient: LinearGradient(
                          colors: mix.gradientColors,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Stack(
                        children: [
                          // Top bar with "Daily Mix" and "01" number tag
                          Positioned(
                            top: 8,
                            left: 8,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.6),
                                    borderRadius: const BorderRadius.horizontal(
                                      left: Radius.circular(4),
                                    ),
                                  ),
                                  child: const Text(
                                    'Daily Mix',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 3,
                                  ),
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.horizontal(
                                      right: Radius.circular(4),
                                    ),
                                  ),
                                  child: Text(
                                    mix.number,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.black,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Music visualizer icon in center
                          Center(
                            child: Icon(
                              Icons.album_rounded,
                              size: 48,
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),

                    // Mix Title
                    Text(
                      mix.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),

                    const SizedBox(height: 4),

                    // Artists Subtitle
                    Text(
                      mix.subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.65),
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // Green hover play button
              if (_isHovered)
                Positioned(
                  right: 18,
                  bottom: 74,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: widget.onPlay,
                      borderRadius: BorderRadius.circular(22),
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.accentGreen,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.5),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.black,
                            size: 28,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentReleaseCard extends StatefulWidget {
  final Song song;
  final VoidCallback onTap;
  final VoidCallback onPlay;

  const _RecentReleaseCard({
    required this.song,
    required this.onTap,
    required this.onPlay,
  });

  @override
  State<_RecentReleaseCard> createState() => _RecentReleaseCardState();
}

class _RecentReleaseCardState extends State<_RecentReleaseCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final song = widget.song;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 172,
          decoration: BoxDecoration(
            color: const Color(0xFF181818),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Artwork
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        height: 130,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: song.gradientColors,
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.music_note_rounded,
                            size: 48,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    // Song Title
                    Text(
                      song.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),

                    const SizedBox(height: 3),

                    // Artist Name
                    Text(
                      song.artist,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.65),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // Green hover play button
              if (_isHovered)
                Positioned(
                  right: 18,
                  bottom: 74,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: widget.onPlay,
                      borderRadius: BorderRadius.circular(22),
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.accentGreen,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.5),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.black,
                            size: 28,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
