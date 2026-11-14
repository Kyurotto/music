import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../controllers/music_player_controller.dart';
import '../auth/auth_service.dart';
import '../views/accounts_view.dart';
import '../views/listening_stats_view.dart';
import '../views/profile_view.dart';
import '../views/recents_view.dart';
import '../views/settings_view.dart';

class SidebarNav extends StatelessWidget {
  final MusicPlayerController controller;
  final ValueChanged<String>? onPlaylistSelected;
  final ValueChanged<String>? onArtistSelected;
  final VoidCallback? onCreatePlaylist;
  final VoidCallback? onImportSpotify;
  final String? selectedPlaylistId;
  final bool isDrawer;

  const SidebarNav({
    super.key,
    required this.controller,
    this.onPlaylistSelected,
    this.onArtistSelected,
    this.onCreatePlaylist,
    this.onImportSpotify,
    this.selectedPlaylistId,
    this.isDrawer = false,
  });

  /// Pushes an account screen from either the desktop sidebar or the mobile
  /// drawer. Closing the drawer first keeps the navigation stack tidy.
  void _openPage(BuildContext context, Widget page) {
    final scaffold = Scaffold.maybeOf(context);
    if (scaffold != null && scaffold.isDrawerOpen) {
      scaffold.closeDrawer();
    }
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  void _openSettings(BuildContext context) {
    final scaffold = Scaffold.maybeOf(context);
    if (scaffold != null && scaffold.isDrawerOpen) {
      scaffold.closeDrawer();
    }
    SettingsView.show(context, controller: controller);
  }

  void _showUpdatesSheet(BuildContext context) {
    final scaffold = Scaffold.maybeOf(context);
    if (scaffold != null && scaffold.isDrawerOpen) {
      scaffold.closeDrawer();
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Icon(
                      Icons.campaign_outlined,
                      color: Color(0xFF1DB954),
                      size: 26,
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Your Updates',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _buildUpdateTile(
                  title: 'Now Playing Artwork & Action Buttons',
                  description:
                      'Tap any song to view high-resolution cover art with Lyrics, Save, and Download actions.',
                  date: 'Just now',
                ),
                _buildUpdateTile(
                  title: 'Spotify & YouTube Fast Import',
                  description:
                      'Import playlists and songs with automatic full-track audio matching and offline caching.',
                  date: 'Recent',
                ),
                _buildUpdateTile(
                  title: '10-Band Graphic Equalizer',
                  description:
                      'Custom presets, dynamic visualizer, and acoustic tuning in Settings.',
                  date: 'Recent',
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildUpdateTile({
    required String title,
    required String description,
    required String date,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF282828),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  date,
                  style: const TextStyle(
                    color: Color(0xFFA7A7A7),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: const TextStyle(
                color: Color(0xFFA7A7A7),
                fontSize: 12.5,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getUserDisplayName() {
    final name = AuthService.instance.userDisplayName.trim();
    if (name.isNotEmpty && name != 'Guest') {
      return name;
    }
    final email = AuthService.instance.userEmail.trim();
    if (email.isNotEmpty && email != 'guest@pulsemusic.app') {
      return email.split('@').first;
    }
    return 'johnlaurencenovicio';
  }

  String _getUserInitial(String displayName) {
    if (displayName.isNotEmpty) {
      return displayName[0].toUpperCase();
    }
    return 'J';
  }

  @override
  Widget build(BuildContext context) {
    final displayName = _getUserDisplayName();
    final initial = _getUserInitial(displayName);

    return Container(
      width: isDrawer ? double.infinity : 240,
      decoration: BoxDecoration(
        color: isDrawer ? const Color(0xFF121212) : AppTheme.surface,
        border: isDrawer
            ? null
            : const Border(
                right: BorderSide(color: AppTheme.border, width: 1),
              ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Brand Header and Main Nav on desktop sidebar
              if (!isDrawer) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          gradient: AppTheme.primaryGradient,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primary.withValues(alpha: 0.4),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.graphic_eq_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'PULSE',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2.0,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          Row(
                            children: [
                              Text(
                                'STUDIO',
                                style: TextStyle(
                                  fontSize: 10,
                                  letterSpacing: 1.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.primary.withValues(alpha: 0.9),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                _buildDesktopNavItem(
                  icon: Icons.home_rounded,
                  label: 'Home',
                  isSelected: controller.currentNavIndex == 0,
                  onTap: () => controller.setNavIndex(0),
                ),
                _buildDesktopNavItem(
                  icon: Icons.explore_rounded,
                  label: 'Explore',
                  isSelected: controller.currentNavIndex == 1,
                  onTap: () => controller.setNavIndex(1),
                ),
                _buildDesktopNavItem(
                  icon: Icons.library_music_rounded,
                  label: 'Library',
                  isSelected: controller.currentNavIndex == 2,
                  badge: controller.libraryPlaylists.isNotEmpty
                      ? '${controller.libraryPlaylists.length}'
                      : null,
                  onTap: () => controller.setNavIndex(2),
                ),
                const SizedBox(height: 16),
              ],

              // Top Profile Card (Spotify Style)
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF242424),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    // Profile Header: Green circular Avatar + Username + View profile
                    InkWell(
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(16)),
                      onTap: () => _openPage(context, const ProfileView()),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: const BoxDecoration(
                                color: Color(0xFF1DB954),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                initial,
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
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
                                    displayName,
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                      letterSpacing: -0.2,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 3),
                                  const Text(
                                    'View profile',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w400,
                                      color: Color(0xFFA7A7A7),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Divider line
                    const Divider(
                      color: Color(0xFF333333),
                      height: 1,
                      thickness: 1,
                    ),

                    // Bottom: + Add account
                    InkWell(
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(16),
                      ),
                      onTap: () => _openPage(context, const AccountsView()),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: const BoxDecoration(
                                color: Color(0xFF333333),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.add,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Text(
                                'Add account',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Menu Items List
              _buildMenuItem(
                context: context,
                iconWidget: const _ListeningStatsIcon(
                  size: 26,
                  color: Colors.white,
                ),
                label: 'Listening stats',
                onTap: () => _openPage(
                  context,
                  ListeningStatsView(controller: controller),
                ),
              ),

              _buildMenuItem(
                context: context,
                icon: Icons.history_rounded,
                label: 'Recents',
                onTap: () => _openPage(
                  context,
                  RecentsView(controller: controller),
                ),
              ),

              _buildMenuItem(
                context: context,
                icon: Icons.campaign_outlined,
                label: 'Your Updates',
                onTap: () => _showUpdatesSheet(context),
              ),

              _buildMenuItem(
                context: context,
                icon: Icons.settings_outlined,
                label: 'Settings and privacy',
                onTap: () => _openSettings(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopNavItem({
    required IconData icon,
    required String label,
    required bool isSelected,
    String? badge,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: isSelected
                  ? AppTheme.primary.withValues(alpha: 0.15)
                  : Colors.transparent,
              border: Border.all(
                color: isSelected
                    ? AppTheme.primary.withValues(alpha: 0.4)
                    : Colors.transparent,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected
                          ? AppTheme.textPrimary
                          : AppTheme.textSecondary,
                    ),
                  ),
                ),
                if (badge != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.primary.withValues(alpha: 0.3)
                          : Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      badge,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color:
                            isSelected ? AppTheme.primary : AppTheme.textMuted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required BuildContext context,
    IconData? icon,
    Widget? iconWidget,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 30,
                alignment: Alignment.centerLeft,
                child: iconWidget ??
                    Icon(
                      icon,
                      size: 26,
                      color: Colors.white,
                    ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                    letterSpacing: -0.2,
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

class _ListeningStatsIcon extends StatelessWidget {
  final double size;
  final Color color;

  const _ListeningStatsIcon({this.size = 26, this.color = Colors.white});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _ListeningStatsPainter(color: color),
    );
  }
}

class _ListeningStatsPainter extends CustomPainter {
  final Color color;

  _ListeningStatsPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // L-shaped axis: left vertical and bottom horizontal line
    final axisPath = Path()
      ..moveTo(size.width * 0.08, size.height * 0.12)
      ..lineTo(size.width * 0.08, size.height * 0.88)
      ..lineTo(size.width * 0.92, size.height * 0.88);
    canvas.drawPath(axisPath, paint);

    // Rising trend line (jagged waveform curve like Spotify)
    final linePath = Path()
      ..moveTo(size.width * 0.16, size.height * 0.72)
      ..lineTo(size.width * 0.36, size.height * 0.72)
      ..lineTo(size.width * 0.58, size.height * 0.28)
      ..lineTo(size.width * 0.76, size.height * 0.52)
      ..lineTo(size.width * 0.90, size.height * 0.22);
    canvas.drawPath(linePath, paint);
  }

  @override
  bool shouldRepaint(covariant _ListeningStatsPainter oldDelegate) =>
      oldDelegate.color != color;
}
