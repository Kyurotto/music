import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../controllers/music_player_controller.dart';
import '../data/local_database.dart';
import '../models/listening_history.dart';
import '../theme/app_theme.dart';
import '../widgets/song_artwork_widget.dart';

/// Listening dashboard for the signed-in account: totals plus top songs and
/// artists, all derived from the local `listening_history` table.
class ListeningStatsView extends StatefulWidget {
  const ListeningStatsView({super.key, this.controller});

  final MusicPlayerController? controller;

  static Route<void> route({MusicPlayerController? controller}) {
    return MaterialPageRoute<void>(
      builder: (_) => ListeningStatsView(controller: controller),
    );
  }

  @override
  State<ListeningStatsView> createState() => _ListeningStatsViewState();
}

class _ListeningStatsViewState extends State<ListeningStatsView> {
  ListeningStats _stats = ListeningStats.empty;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = AuthService.instance.currentUserId;
    final stats = userId.isEmpty
        ? ListeningStats.empty
        : await LocalDatabase.instance.getListeningStats(userId: userId);
    if (!mounted) return;
    setState(() {
      _stats = stats;
      _loading = false;
    });
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text(
          'Clear listening history?',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: const Text(
          'This removes all plays, Recents and Listening Stats for this '
          'account. Your downloaded songs are not deleted.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              'Clear',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final userId = AuthService.instance.currentUserId;
    if (userId.isEmpty) return;
    await LocalDatabase.instance.clearListeningHistory(userId: userId);
    await _load();
  }

  void _play(String songId) {
    final controller = widget.controller;
    if (controller == null) return;
    final song = controller.songById(songId);
    if (song == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This song is no longer in your library.'),
        ),
      );
      return;
    }
    controller.playSong(song);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: AppTheme.textPrimary,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Listening Stats'),
        actions: [
          if (!_loading && _stats.totalPlays > 0)
            IconButton(
              tooltip: 'Clear listening history',
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: AppTheme.textSecondary,
              ),
              onPressed: _clearHistory,
            ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppTheme.border),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              color: AppTheme.primary,
              backgroundColor: AppTheme.cardSurface,
              child: _stats.totalPlays == 0
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(32),
                      children: const [
                        SizedBox(height: 90),
                        Icon(
                          Icons.insights_rounded,
                          size: 54,
                          color: AppTheme.textMuted,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'No listening history yet',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Play a song and your stats will appear here. '
                          'Listening history stays on this device.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    )
                  : ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(24),
                      children: [
                        _buildSummary(),
                        const SizedBox(height: 26),
                        if (_stats.topSongs.isNotEmpty) ...[
                          _SectionHeader(
                            icon: Icons.trending_up_rounded,
                            title: 'Top Songs',
                          ),
                          const SizedBox(height: 10),
                          _buildTopSongs(),
                          const SizedBox(height: 26),
                        ],
                        if (_stats.topArtists.isNotEmpty) ...[
                          _SectionHeader(
                            icon: Icons.mic_none_rounded,
                            title: 'Top Artists',
                          ),
                          const SizedBox(height: 10),
                          _buildTopArtists(),
                        ],
                        const SizedBox(height: 30),
                      ],
                    ),
            ),
    );
  }

  Widget _buildSummary() {
    final completedPercent = _stats.totalPlays == 0
        ? 0
        : ((_stats.completedPlays / _stats.totalPlays) * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(icon: Icons.bar_chart_rounded, title: 'Overview'),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 520 ? 4 : 2;
            final spacing = 10.0;
            final width =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;
            final tiles = [
              _StatTile(
                icon: Icons.play_circle_outline_rounded,
                value: '${_stats.totalPlays}',
                label: 'Plays',
                width: width,
              ),
              _StatTile(
                icon: Icons.schedule_rounded,
                value: _formatDuration(_stats.totalListenedSeconds),
                label: 'Listen time',
                width: width,
              ),
              _StatTile(
                icon: Icons.music_note_rounded,
                value: '${_stats.uniqueSongs}',
                label: 'Unique songs',
                width: width,
              ),
              _StatTile(
                icon: Icons.people_alt_outlined,
                value: '${_stats.uniqueArtists}',
                label: 'Artists',
                width: width,
              ),
            ];
            return Wrap(spacing: spacing, runSpacing: spacing, children: tiles);
          },
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.check_circle_outline_rounded,
                size: 17,
                color: AppTheme.accentGreen,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$completedPercent% of plays finished · average '
                  '${_formatDuration(_stats.averageListenedSeconds)} per play',
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTopSongs() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < _stats.topSongs.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppTheme.border),
            _TopSongRow(
              rank: i + 1,
              item: _stats.topSongs[i],
              onTap: widget.controller == null
                  ? null
                  : () => _play(_stats.topSongs[i].key),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTopArtists() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < _stats.topArtists.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppTheme.border),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Text(
                    '${i + 1}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textMuted,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 38,
                    height: 38,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.cardSurface,
                    ),
                    child: Center(
                      child: Text(
                        _initials(_stats.topArtists[i].title),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _stats.topArtists[i].title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${_stats.topArtists[i].plays} plays',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final value = parts.first;
      return value.substring(0, value.length >= 2 ? 2 : 1).toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  static String _formatDuration(int seconds) {
    if (seconds <= 0) return '0m';
    if (seconds < 60) return '${seconds}s';
    final duration = Duration(seconds: seconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours > 0) {
      return minutes > 0 ? '${hours}h ${minutes}m' : '${hours}h';
    }
    return '${minutes}m';
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Row(
        children: [
          Icon(icon, size: 17, color: AppTheme.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.2,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.value,
    required this.label,
    required this.width,
  });

  final IconData icon;
  final String value;
  final String label;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppTheme.textSecondary),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }
}

class _TopSongRow extends StatelessWidget {
  const _TopSongRow({required this.rank, required this.item, this.onTap});

  final int rank;
  final ListeningRankedItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: Text(
                  '$rank',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textMuted,
                  ),
                ),
              ),
              SongArtworkWidget(
                imageUrl: item.imageUrl,
                title: item.title,
                artist: item.subtitle,
                size: 42,
                borderRadius: 8,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (item.subtitle.isNotEmpty)
                      Text(
                        item.subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${item.plays} plays',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
