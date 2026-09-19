import 'package:flutter/material.dart';
import '../models/song_model.dart';
import '../theme/app_theme.dart';
import '../controllers/music_player_controller.dart';
import '../widgets/sidebar_nav.dart';
import '../widgets/hero_banner.dart';
import '../widgets/album_card.dart';
import '../widgets/track_list_view.dart';
import '../widgets/right_panel.dart';
import '../widgets/bottom_player_bar.dart';

class MusicDashboardView extends StatefulWidget {
  const MusicDashboardView({super.key});

  @override
  State<MusicDashboardView> createState() => _MusicDashboardViewState();
}

class _MusicDashboardViewState extends State<MusicDashboardView> {
  late final MusicPlayerController _controller;
  final TextEditingController _searchTextController = TextEditingController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _controller = MusicPlayerController();
    _controller.addListener(_onStateChange);
  }

  void _onStateChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onStateChange);
    _controller.dispose();
    _searchTextController.dispose();
    super.dispose();
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
                    child: SidebarNav(controller: _controller),
                  ),
                )
              : null,
          endDrawer: !isDesktop
              ? Drawer(
                  backgroundColor: AppTheme.surface,
                  width: 320,
                  child: SafeArea(
                    child: RightActivityPanel(controller: _controller),
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
                        SidebarNav(controller: _controller),

                      // Main Content View
                      Expanded(
                        child: Column(
                          children: [
                            // Top App Bar / Search Header
                            _buildTopHeader(isMobile, isDesktop),

                            // Scrollable Feed
                            Expanded(
                              child: SingleChildScrollView(
                                padding: EdgeInsets.symmetric(
                                  horizontal: isMobile ? 16 : 28,
                                  vertical: 20,
                                ),
                                child: _buildCurrentTabContent(isMobile),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Right Activity / Now Playing Panel on Wide Screens
                      if (isDesktop)
                        RightActivityPanel(controller: _controller),
                    ],
                  ),
                ),

                // Persistent Bottom Player
                BottomPlayerBar(controller: _controller),
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

          // Open Now Playing Drawer on Mobile/Tablet
          if (!isDesktop)
            IconButton(
              tooltip: 'Now Playing',
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _controller.isPlaying
                      ? AppTheme.primary.withValues(alpha: 0.2)
                      : AppTheme.cardSurface,
                  border: Border.all(
                    color: _controller.isPlaying ? AppTheme.primary : AppTheme.border,
                  ),
                ),
                child: Icon(
                  Icons.graphic_eq_rounded,
                  size: 18,
                  color: _controller.isPlaying ? AppTheme.primary : AppTheme.textSecondary,
                ),
              ),
              onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
            ),

          // Notifications button
          IconButton(
            tooltip: 'Notifications',
            icon: const Icon(Icons.notifications_none_rounded, size: 22, color: AppTheme.textSecondary),
            onPressed: () {},
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
    final featuredSong = _controller.allSongs.where((s) => s.isFeatured).firstOrNull ??
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
          _buildSectionHeader('Curated Playlists', 'Hand-crafted sonic journeys'),
          const SizedBox(height: 14),
          SizedBox(
            height: 230,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: SampleMusicData.playlists.length,
              separatorBuilder: (context, index) => const SizedBox(width: 16),
              itemBuilder: (context, index) {
                final playlist = SampleMusicData.playlists[index];
                return AlbumCard(
                  playlist: playlist,
                  onTap: () {
                    _controller.setSelectedGenre(
                      playlist.title.contains('Lo-Fi')
                          ? 'Lo-Fi'
                          : playlist.title.contains('Cyberpunk')
                              ? 'Cyberpunk'
                              : playlist.title.contains('Ambient')
                                  ? 'Ambient'
                                  : 'Synthwave',
                    );
                  },
                  onPlay: () {
                    final matchingSong = _controller.allSongs.firstWhere(
                      (s) => s.genre.toLowerCase() == playlist.title.split(' ').first.toLowerCase(),
                      orElse: () => _controller.allSongs[index % _controller.allSongs.length],
                    );
                    _controller.playSong(matchingSong);
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 32),
        ],

        // Top Tracks / Filtered Songs Table
        _buildSectionHeader(
          _controller.searchQuery.isNotEmpty
              ? 'Search Results ("${_controller.searchQuery}")'
              : (_controller.selectedGenre == 'All' ? 'Trending Tracks' : '${_controller.selectedGenre} Tracks'),
          '${_controller.filteredSongs.length} songs available',
        ),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.cardSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.border, width: 1),
          ),
          child: TrackListView(
            songs: _controller.filteredSongs,
            controller: _controller,
          ),
        ),

        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildQuickGrid() {
    final recentSongs = _controller.allSongs.take(4).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 700 ? 2 : 1;

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

            return InkWell(
              onTap: () => _controller.playSong(song),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                decoration: BoxDecoration(
                  color: isCurrent
                      ? AppTheme.primary.withValues(alpha: 0.15)
                      : AppTheme.cardSurface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isCurrent ? AppTheme.primary : AppTheme.border,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.horizontal(left: Radius.circular(10)),
                        gradient: LinearGradient(colors: song.gradientColors),
                      ),
                      child: const Center(
                        child: Icon(Icons.music_note_rounded, color: Colors.white, size: 24),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            song.title,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: isCurrent ? AppTheme.primary : AppTheme.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            song.artist,
                            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isCurrent && _controller.isPlaying
                              ? AppTheme.primary
                              : Colors.white10,
                        ),
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
            );
          },
        );
      },
    );
  }

  Widget _buildExploreTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Explore Genres & Moods', 'Find soundscapes crafted for your day'),
        const SizedBox(height: 20),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: SampleMusicData.playlists.length,
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 220,
            mainAxisExtent: 230,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemBuilder: (context, index) {
            final playlist = SampleMusicData.playlists[index];
            return AlbumCard(
              playlist: playlist,
              onTap: () {
                _controller.setSelectedGenre(
                  playlist.title.contains('Lo-Fi')
                      ? 'Lo-Fi'
                      : playlist.title.contains('Cyberpunk')
                          ? 'Cyberpunk'
                          : playlist.title.contains('Ambient')
                              ? 'Ambient'
                              : 'Synthwave',
                );
                _controller.setNavIndex(0);
              },
              onPlay: () {
                final matchingSong = _controller.allSongs[index % _controller.allSongs.length];
                _controller.playSong(matchingSong);
              },
            );
          },
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
          ),
        ),
      ],
    );
  }

  Widget _buildLibraryTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Your Library', '${_controller.allSongs.length} saved songs across 4 playlists'),
        const SizedBox(height: 20),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.cardSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.border, width: 1),
          ),
          child: TrackListView(
            songs: _controller.allSongs,
            controller: _controller,
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
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionHeader('Favorite Songs', '${favorites.length} songs you love'),
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
                onPressed: () => _controller.playSong(favorites.first),
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
