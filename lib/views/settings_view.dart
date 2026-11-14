import 'dart:async';

import 'package:flutter/material.dart';
import '../auth/auth_service.dart';
import '../controllers/music_player_controller.dart';
import '../data/local_database.dart';
import '../models/equalizer_preset.dart';
import '../theme/app_theme.dart';
import 'auth_gate.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({
    super.key,
    this.controller,
    this.openProfileEdit = false,
  });

  final MusicPlayerController? controller;
  final bool openProfileEdit;

  static Future<void> show(
    BuildContext context, {
    MusicPlayerController? controller,
    bool openProfileEdit = false,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SettingsView(
          controller: controller,
          openProfileEdit: openProfileEdit,
        ),
      ),
    );
  }

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  // Spotify-style Settings State
  double _crossfadeSeconds = 4.0;
  bool _gaplessPlayback = true;
  bool _automix = true;
  bool _normalizeVolume = true;
  bool _monoAudio = false;
  bool _autoplay = true;

  String _streamingQuality = 'Very High (320 kbps)';
  String _downloadQuality = 'High (160 kbps)';
  String _equalizerPreset = 'Bass Boost';

  bool _canvasAnimation = true;
  bool _autoLyrics = false;
  bool _allowExplicit = true;
  bool _downloadOnMobile = false;
  bool _autoCachePlayedSongs = true;
  bool _dataSaverMode = false;

  int _cacheSizeBytes = -1;
  bool _clearingCache = false;
  bool _cacheRefreshInFlight = false;
  bool _cacheRefreshQueued = false;
  Timer? _cacheRefreshDebounce;

  final List<String> _qualityOptions = const [
    'Automatic',
    'Low (24 kbps)',
    'Normal (96 kbps)',
    'High (160 kbps)',
    'Very High (320 kbps)',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _equalizerPreset = widget.controller!.equalizerPreset;
    }
    _loadSettings();
    _refreshCacheSize();
    LocalDatabase.audioCacheRevision.addListener(_onAudioCacheChanged);
    if (widget.openProfileEdit) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showEditProfileDialog();
      });
    }
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await LocalDatabase.instance.getAllSettings();
      if (!mounted) return;
      setState(() {
        if (settings.containsKey('crossfade')) {
          _crossfadeSeconds =
              double.tryParse(settings['crossfade']!) ?? _crossfadeSeconds;
        }
        if (settings.containsKey('gapless_playback')) {
          _gaplessPlayback = settings['gapless_playback'] == 'true';
        }
        if (settings.containsKey('automix')) {
          _automix = settings['automix'] == 'true';
        }
        if (settings.containsKey('normalize_volume')) {
          _normalizeVolume = settings['normalize_volume'] == 'true';
        }
        if (settings.containsKey('mono_audio')) {
          _monoAudio = settings['mono_audio'] == 'true';
        }
        if (settings.containsKey('autoplay')) {
          _autoplay = settings['autoplay'] == 'true';
        }
        if (settings.containsKey('streaming_quality')) {
          _streamingQuality = settings['streaming_quality']!;
        }
        if (settings.containsKey('download_quality')) {
          _downloadQuality = settings['download_quality']!;
        }
        if (settings.containsKey('equalizer_preset')) {
          _equalizerPreset = settings['equalizer_preset']!;
        }
        if (settings.containsKey('canvas_animation')) {
          _canvasAnimation = settings['canvas_animation'] == 'true';
        }
        if (settings.containsKey('auto_lyrics')) {
          _autoLyrics = settings['auto_lyrics'] == 'true';
        }
        if (settings.containsKey('allow_explicit')) {
          _allowExplicit = settings['allow_explicit'] == 'true';
        }
        if (settings.containsKey('download_on_mobile_data')) {
          _downloadOnMobile = settings['download_on_mobile_data'] == 'true';
        }
        if (settings.containsKey('auto_cache_played_songs')) {
          _autoCachePlayedSongs = settings['auto_cache_played_songs'] == 'true';
        }
        if (settings.containsKey('data_saver_mode')) {
          _dataSaverMode = settings['data_saver_mode'] == 'true';
        }
      });
    } catch (e) {
      debugPrint('Error loading settings: $e');
    }
  }

  Future<void> _saveSetting(String key, String value) async {
    try {
      await LocalDatabase.instance.saveSetting(key, value);
    } catch (e) {
      debugPrint('Error saving setting $key: $e');
    }
  }

  void _onAudioCacheChanged() {
    _cacheRefreshDebounce?.cancel();
    _cacheRefreshDebounce = Timer(const Duration(milliseconds: 1200), () {
      _refreshCacheSize();
    });
  }

  Future<void> _refreshCacheSize() async {
    if (_cacheRefreshInFlight) {
      _cacheRefreshQueued = true;
      return;
    }
    _cacheRefreshInFlight = true;
    try {
      final bytes = await LocalDatabase.getLocalAudioCacheSizeBytes();
      if (!mounted || bytes == _cacheSizeBytes) return;
      setState(() => _cacheSizeBytes = bytes);
    } catch (e) {
      debugPrint('Error reading audio cache size: $e');
    } finally {
      _cacheRefreshInFlight = false;
      if (_cacheRefreshQueued) {
        _cacheRefreshQueued = false;
        unawaited(_refreshCacheSize());
      }
    }
  }

  String _formatCacheSize(int bytes) {
    if (bytes < 0) return 'Calculating…';
    if (bytes == 0) return '0 MB';
    const kb = 1024;
    const mb = kb * 1024;
    const gb = mb * 1024;
    if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
    if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
    return '${(bytes / kb).toStringAsFixed(0)} KB';
  }

  /// Visual share of a nominal 8 GB cache budget for the storage bar.
  int get _cacheBarFlex {
    if (_cacheSizeBytes <= 0) return 1;
    const referenceBytes = 8 * 1024 * 1024 * 1024;
    return ((_cacheSizeBytes / referenceBytes) * 100).clamp(1, 100).round();
  }

  Future<void> _showQualityPicker({required bool isStreaming}) async {
    final current = isStreaming ? _streamingQuality : _downloadQuality;
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Text(
                  isStreaming
                      ? 'Streaming Audio Quality'
                      : 'Download Audio Quality',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              const Divider(color: AppTheme.border),
              ..._qualityOptions.map(
                (opt) => ListTile(
                  title: Text(
                    opt,
                    style: TextStyle(
                      color: opt == current
                          ? AppTheme.primary
                          : AppTheme.textPrimary,
                      fontWeight: opt == current
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                  trailing: opt == current
                      ? const Icon(Icons.check_rounded, color: AppTheme.primary)
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(opt),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (selected != null && mounted) {
      setState(() {
        if (isStreaming) {
          _streamingQuality = selected;
        } else {
          _downloadQuality = selected;
        }
      });
      _saveSetting(
        isStreaming ? 'streaming_quality' : 'download_quality',
        selected,
      );
      if (isStreaming) {
        widget.controller?.setStreamingQuality(selected, save: false);
      } else {
        widget.controller?.setDownloadQuality(selected, save: false);
      }
    }
  }

  Future<void> _showEqualizerPicker() async {
    final initialPreset =
        widget.controller?.currentEqualizer ??
        EqualizerPreset.getByName(_equalizerPreset);
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        String activePresetName = initialPreset.name;
        List<double> activeBands = List<double>.from(initialPreset.bands);

        return StatefulBuilder(
          builder: (context, setSheetState) {
            final activePreset = EqualizerPreset.getByName(activePresetName);

            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.88,
              ),
              decoration: const BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(
                  top: BorderSide(color: AppTheme.border, width: 1),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Drag Handle
                    const SizedBox(height: 12),
                    Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppTheme.textMuted.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Header
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppTheme.primary.withValues(
                                    alpha: 0.15,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.graphic_eq_rounded,
                                  color: AppTheme.primary,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Audio Equalizer',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                  Text(
                                    activePreset.name,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.close_rounded,
                              color: AppTheme.textMuted,
                            ),
                            onPressed: () => Navigator.of(
                              sheetContext,
                            ).pop(activePresetName),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // 5-Band Frequency Sliders / Visual Curve Card
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.cardSurface,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'FREQUENCY RESPONSE (dB)',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.0,
                                    color: AppTheme.textMuted,
                                  ),
                                ),
                                Flexible(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primary.withValues(
                                        alpha: 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      activePreset.description,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: AppTheme.textSecondary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // 5 Interactive / Animated Frequency Sliders
                            SizedBox(
                              height: 125,
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: List.generate(5, (index) {
                                  final db = activeBands[index];
                                  final label =
                                      EqualizerPreset.frequencyLabels[index];

                                  return Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '${db >= 0 ? '+' : ''}${db.toStringAsFixed(1)}',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: db != 0
                                              ? AppTheme.primary
                                              : AppTheme.textMuted,
                                        ),
                                      ),
                                      Expanded(
                                        child: RotatedBox(
                                          quarterTurns: -1,
                                          child: SliderTheme(
                                            data: SliderTheme.of(context).copyWith(
                                              trackHeight: 3,
                                              thumbShape:
                                                  const RoundSliderThumbShape(
                                                    enabledThumbRadius: 5,
                                                  ),
                                              overlayShape:
                                                  const RoundSliderOverlayShape(
                                                    overlayRadius: 10,
                                                  ),
                                              activeTrackColor:
                                                  AppTheme.primary,
                                              inactiveTrackColor:
                                                  AppTheme.border,
                                              thumbColor: AppTheme.primary,
                                            ),
                                            child: Slider(
                                              value: db,
                                              min: -10.0,
                                              max: 10.0,
                                              onChanged: (newVal) {
                                                setSheetState(() {
                                                  activeBands[index] = newVal;
                                                  activePresetName =
                                                      EqualizerPreset
                                                          .custom
                                                          .name;
                                                });
                                                // Move the native equalizer
                                                // while dragging, but only
                                                // persist once the drag ends.
                                                widget.controller
                                                    ?.setCustomEqualizerBands(
                                                      activeBands,
                                                      save: false,
                                                    );
                                              },
                                              onChangeEnd: (_) {
                                                widget.controller
                                                    ?.setCustomEqualizerBands(
                                                      activeBands,
                                                    );
                                              },
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        label,
                                        style: const TextStyle(
                                          fontSize: 9.5,
                                          color: AppTheme.textSecondary,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  );
                                }),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1, color: AppTheme.border),

                    // Scrollable Presets List (Fixes the 28px bottom overflow!)
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        itemCount: EqualizerPreset.all.length,
                        separatorBuilder: (_, index) =>
                            const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final preset = EqualizerPreset.all[index];
                          final isSelected = preset.name == activePresetName;

                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () {
                                final bands =
                                    preset.name == EqualizerPreset.custom.name
                                    ? List<double>.from(
                                        widget
                                                .controller
                                                ?.customEqualizerBands ??
                                            preset.bands,
                                      )
                                    : List<double>.from(preset.bands);
                                setSheetState(() {
                                  activePresetName = preset.name;
                                  activeBands = bands;
                                });
                                widget.controller?.setEqualizerPreset(
                                  preset.name,
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 11,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppTheme.primary.withValues(alpha: 0.12)
                                      : AppTheme.cardSurface.withValues(
                                          alpha: 0.5,
                                        ),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isSelected
                                        ? AppTheme.primary
                                        : AppTheme.border,
                                    width: isSelected ? 1.5 : 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? AppTheme.primary
                                            : AppTheme.surface,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(
                                        preset.icon,
                                        color: isSelected
                                            ? Colors.black87
                                            : AppTheme.textMuted,
                                        size: 18,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            preset.name,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: isSelected
                                                  ? FontWeight.bold
                                                  : FontWeight.w600,
                                              color: isSelected
                                                  ? AppTheme.primary
                                                  : AppTheme.textPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            preset.description,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: AppTheme.textSecondary,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (isSelected)
                                      const Icon(
                                        Icons.check_circle_rounded,
                                        color: AppTheme.primary,
                                        size: 20,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    // Apply Button
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.black87,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          onPressed: () =>
                              Navigator.of(sheetContext).pop(activePresetName),
                          child: const Text(
                            'Apply Equalizer Preset',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
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

    if (selected != null && mounted) {
      setState(() => _equalizerPreset = selected);
      widget.controller?.setEqualizerPreset(selected);
      _saveSetting('equalizer_preset', selected);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Equalizer set to "$selected"'),
          backgroundColor: AppTheme.surface,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _clearCache() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppTheme.border),
        ),
        title: const Text(
          'Clear audio cache?',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          'This will free up storage space by clearing temporary streaming cache. Your permanently downloaded songs, playlists, library tracks, and account data will NOT be deleted.',
          style: TextStyle(color: AppTheme.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              'Clear',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      setState(() => _clearingCache = true);
      final freed = await LocalDatabase.clearLocalAudioCache();
      if (!mounted) return;
      await _refreshCacheSize();
      if (!mounted) return;
      setState(() => _clearingCache = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cache cleared! Freed ${_formatCacheSize(freed)} of storage. Offline downloads remain intact.',
          ),
        ),
      );
    }
  }

  Future<void> _handleLogout() async {
    final displayName = AuthService.instance.userDisplayName;
    final email = AuthService.instance.userEmail;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppTheme.border),
        ),
        title: const Row(
          children: [
            Icon(Icons.logout_rounded, color: Colors.redAccent, size: 24),
            SizedBox(width: 10),
            Text(
              'Log out?',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to log out of $displayName ($email)?\nYou will return to the sign-in screen.',
          style: const TextStyle(color: AppTheme.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      // Perform sign out
      await AuthService.instance.signOut();

      if (!mounted) return;

      // Navigate back to AuthGate / AuthView cleanly
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (route) => false,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You have been logged out.')),
      );
    }
  }

  @override
  void dispose() {
    LocalDatabase.audioCacheRevision.removeListener(_onAudioCacheChanged);
    _cacheRefreshDebounce?.cancel();
    super.dispose();
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
        title: const Text(
          'Settings',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppTheme.border),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. User Profile Header Card
                _buildProfileCard(),
                const SizedBox(height: 24),

                // 2. Playback Settings Section
                _buildSectionHeader(
                  Icons.play_circle_outline_rounded,
                  'Playback',
                ),
                _buildCard([
                  // Crossfade Slider
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Crossfade',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            Text(
                              _crossfadeSeconds == 0
                                  ? 'Off'
                                  : '${_crossfadeSeconds.toInt()}s',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Allows you to crossfade smoothly between songs',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textMuted,
                          ),
                        ),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: AppTheme.primary,
                            inactiveTrackColor: AppTheme.border,
                            thumbColor: AppTheme.primary,
                            overlayColor: AppTheme.primary.withValues(
                              alpha: 0.2,
                            ),
                          ),
                          child: Slider(
                            value: _crossfadeSeconds,
                            min: 0,
                            max: 12,
                            divisions: 12,
                            onChanged: (val) =>
                                setState(() => _crossfadeSeconds = val),
                            onChangeEnd: (val) {
                              _saveSetting('crossfade', val.toString());
                              widget.controller?.setCrossfadeSeconds(
                                val,
                                save: false,
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: AppTheme.border),

                  // Gapless Playback
                  _buildSwitchTile(
                    title: 'Gapless Playback',
                    subtitle: 'Seamless playback of songs with no silent gaps',
                    value: _gaplessPlayback,
                    onChanged: (val) {
                      setState(() => _gaplessPlayback = val);
                      widget.controller?.setGaplessPlayback(val, save: false);
                      _saveSetting('gapless_playback', val.toString());
                    },
                  ),
                  const Divider(height: 1, color: AppTheme.border),

                  // Automix
                  _buildSwitchTile(
                    title: 'Automix',
                    subtitle:
                        'Allow smooth AI-curated transitions between tracks',
                    value: _automix,
                    onChanged: (val) {
                      setState(() => _automix = val);
                      widget.controller?.setAutomix(val, save: false);
                      _saveSetting('automix', val.toString());
                    },
                  ),
                  const Divider(height: 1, color: AppTheme.border),

                  // Normalize Volume
                  _buildSwitchTile(
                    title: 'Normalize Volume',
                    subtitle: 'Set the same volume level for all audio tracks',
                    value: _normalizeVolume,
                    onChanged: (val) {
                      setState(() => _normalizeVolume = val);
                      widget.controller?.setNormalizeVolume(val, save: false);
                      _saveSetting('normalize_volume', val.toString());
                    },
                  ),
                  const Divider(height: 1, color: AppTheme.border),

                  // Mono Audio
                  _buildSwitchTile(
                    title: 'Mono Audio',
                    subtitle:
                        'Makes the left and right speakers play the same audio',
                    value: _monoAudio,
                    onChanged: (val) {
                      setState(() => _monoAudio = val);
                      widget.controller?.setMonoAudio(val, save: false);
                      _saveSetting('mono_audio', val.toString());
                      if (val) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Mono Audio is saved. Downmixing depends on '
                              'the device audio engine.',
                            ),
                          ),
                        );
                      }
                    },
                  ),
                  const Divider(height: 1, color: AppTheme.border),

                  // Autoplay
                  _buildSwitchTile(
                    title: 'Autoplay',
                    subtitle:
                        'Keep listening to similar songs when your queue ends',
                    value: _autoplay,
                    onChanged: (val) {
                      setState(() => _autoplay = val);
                      widget.controller?.setAutoplay(val, save: false);
                      _saveSetting('autoplay', val.toString());
                    },
                  ),
                ]),
                const SizedBox(height: 24),

                // 3. Audio Quality Section
                _buildSectionHeader(Icons.equalizer_rounded, 'Audio Quality'),
                _buildCard([
                  ListTile(
                    title: const Text(
                      'Streaming Quality',
                      style: TextStyle(
                        fontSize: 15,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      _dataSaverMode
                          ? '$_streamingQuality · Data Saver caps at 96 kbps'
                          : _streamingQuality,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.primary,
                      ),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      color: AppTheme.textSecondary,
                    ),
                    onTap: () => _showQualityPicker(isStreaming: true),
                  ),
                  const Divider(height: 1, color: AppTheme.border),
                  ListTile(
                    title: const Text(
                      'Download Quality',
                      style: TextStyle(
                        fontSize: 15,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      _dataSaverMode
                          ? '$_downloadQuality · Data Saver caps at 96 kbps'
                          : _downloadQuality,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      color: AppTheme.textSecondary,
                    ),
                    onTap: () => _showQualityPicker(isStreaming: false),
                  ),
                  const Divider(height: 1, color: AppTheme.border),
                  ListTile(
                    title: const Text(
                      'Equalizer',
                      style: TextStyle(
                        fontSize: 15,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      _equalizerPreset,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.primary,
                      ),
                    ),
                    trailing: const Icon(
                      Icons.tune_rounded,
                      color: AppTheme.primary,
                    ),
                    onTap: _showEqualizerPicker,
                  ),
                ]),
                const SizedBox(height: 24),

                // 4. Data Saver Section
                _buildSectionHeader(Icons.data_saver_on_rounded, 'Data Saver'),
                _buildCard([
                  _buildSwitchTile(
                    title: 'Data Saver Mode',
                    subtitle:
                        'Caps new streams and downloads at ~96 kbps, pauses '
                        'automatic song caching, and blocks cache downloads on '
                        'mobile data so your data lasts longer.',
                    value: _dataSaverMode,
                    onChanged: (val) {
                      setState(() => _dataSaverMode = val);
                      widget.controller?.setDataSaverMode(val, save: false);
                      _saveSetting('data_saver_mode', val.toString());
                    },
                  ),
                ]),
                const SizedBox(height: 24),

                // 5. Display & Visuals Section
                _buildSectionHeader(Icons.palette_outlined, 'Display & Lyrics'),
                _buildCard([
                  _buildSwitchTile(
                    title: 'Animated Audio Wave Visualizer',
                    subtitle:
                        'Show live frequency wave effect in the player bar',
                    value: _canvasAnimation,
                    onChanged: (val) {
                      setState(() => _canvasAnimation = val);
                      widget.controller?.setVisualizerEnabled(val, save: false);
                      _saveSetting('canvas_animation', val.toString());
                    },
                  ),
                  const Divider(height: 1, color: AppTheme.border),
                  _buildSwitchTile(
                    title: 'Show Lyrics Automatically',
                    subtitle:
                        'Pop up the Spotify-style lyrics sheet when starting a song',
                    value: _autoLyrics,
                    onChanged: (val) {
                      setState(() => _autoLyrics = val);
                      widget.controller?.setAutoLyrics(val, save: false);
                      _saveSetting('auto_lyrics', val.toString());
                    },
                  ),
                  const Divider(height: 1, color: AppTheme.border),
                  _buildSwitchTile(
                    title: 'Explicit Content Filter',
                    subtitle: 'Block playback of explicit-rated tracks',
                    value: !_allowExplicit,
                    onChanged: (val) {
                      final allow = !val;
                      setState(() => _allowExplicit = allow);
                      widget.controller?.setAllowExplicit(allow, save: false);
                      _saveSetting('allow_explicit', allow.toString());
                    },
                  ),
                ]),
                const SizedBox(height: 24),

                // 5. Storage & Cache Section
                _buildSectionHeader(Icons.storage_rounded, 'Storage & Cache'),
                _buildCard([
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Local Audio Cache',
                              style: TextStyle(
                                fontSize: 14,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            Text(
                              _formatCacheSize(_cacheSizeBytes),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Row(
                            children: [
                              Expanded(
                                flex: _cacheBarFlex,
                                child: Container(
                                  height: 8,
                                  color: AppTheme.primary,
                                ),
                              ),
                              Expanded(
                                flex: 20,
                                child: Container(
                                  height: 8,
                                  color: Colors.blueAccent,
                                ),
                              ),
                              Expanded(
                                flex: 65,
                                child: Container(
                                  height: 8,
                                  color: AppTheme.border,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Row(
                          children: [
                            _StorageLegend(
                              color: AppTheme.primary,
                              label: 'Audio Cache',
                            ),
                            SizedBox(width: 16),
                            _StorageLegend(
                              color: Colors.blueAccent,
                              label: 'Playlists & Tracks',
                            ),
                            SizedBox(width: 16),
                            _StorageLegend(
                              color: AppTheme.border,
                              label: 'Free Space',
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                          onPressed: _cacheSizeBytes > 0 && !_clearingCache
                              ? _clearCache
                              : null,
                          icon: _clearingCache
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppTheme.textMuted,
                                  ),
                                )
                              : const Icon(
                                  Icons.delete_sweep_outlined,
                                  size: 18,
                                ),
                          label: Text(
                            _clearingCache
                                ? 'Clearing cache…'
                                : _cacheSizeBytes < 0
                                ? 'Calculating…'
                                : _cacheSizeBytes > 0
                                ? 'Clear Audio Cache'
                                : 'Cache is Clean (0 MB)',
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _cacheSizeBytes > 0
                                ? AppTheme.textPrimary
                                : AppTheme.textMuted,
                            side: BorderSide(
                              color: _cacheSizeBytes > 0
                                  ? AppTheme.border
                                  : AppTheme.border.withValues(alpha: 0.3),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: AppTheme.border),
                  _buildSwitchTile(
                    title: 'Cache played songs',
                    subtitle:
                        'Only save audio when you play it; imports no longer download automatically',
                    value: _autoCachePlayedSongs,
                    onChanged: (val) {
                      setState(() => _autoCachePlayedSongs = val);
                      if (widget.controller != null) {
                        widget.controller!.setAutoCachePlayedSongs(val);
                      } else {
                        _saveSetting('auto_cache_played_songs', val.toString());
                      }
                    },
                  ),
                  const Divider(height: 1, color: AppTheme.border),
                  _buildSwitchTile(
                    title: 'Download on mobile data',
                    subtitle:
                        'Off: songs are saved for offline use only on Wi-Fi',
                    value: _downloadOnMobile,
                    onChanged: (val) {
                      setState(() => _downloadOnMobile = val);
                      _saveSetting('download_on_mobile_data', val.toString());
                    },
                  ),
                ]),
                const SizedBox(height: 32),

                // 6. Log Out Button (Spotify Style)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  child: OutlinedButton.icon(
                    onPressed: _handleLogout,
                    icon: const Icon(
                      Icons.logout_rounded,
                      color: Colors.redAccent,
                      size: 20,
                    ),
                    label: const Text(
                      'Log out',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.redAccent,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: BorderSide(
                        color: Colors.redAccent.withValues(alpha: 0.5),
                        width: 1.5,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Footer branding
                const Center(
                  child: Text(
                    'Pulse Studio • Crafted for audiophiles',
                    style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileCard() {
    final displayName = AuthService.instance.userDisplayName;
    final email = AuthService.instance.userEmail;
    final initials = AuthService.instance.userInitials;
    final role = AuthService.instance.userRole;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: _showEditProfileDialog,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Stack(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.primary,
                          AppTheme.primary.withValues(alpha: 0.6),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary.withValues(alpha: 0.3),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        initials,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: AppTheme.cardSurface,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.edit_rounded,
                        size: 12,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            displayName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: role == 'admin'
                                ? Colors.amber.withValues(alpha: 0.2)
                                : AppTheme.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            role.toUpperCase(),
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                              color: role == 'admin'
                                  ? Colors.amber
                                  : AppTheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.email_outlined,
                          size: 13,
                          color: AppTheme.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            email.isNotEmpty ? email : 'No Gmail assigned',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppTheme.textSecondary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.cardSurface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.border),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.edit_rounded, size: 14, color: AppTheme.primary),
                    SizedBox(width: 6),
                    Text(
                      'Edit',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showEditProfileDialog() async {
    final formKey = GlobalKey<FormState>();
    final emailController = TextEditingController(
      text: AuthService.instance.userEmail,
    );
    final backupEmailController = TextEditingController(
      text: AuthService.instance.userBackupEmail,
    );
    final phoneController = TextEditingController(
      text: AuthService.instance.userPhoneNumber,
    );
    final nameController = TextEditingController(
      text: AuthService.instance.userDisplayName,
    );
    final passwordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    bool obscurePassword = true;
    bool obscureConfirm = true;
    bool isSaving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: !isSaving,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContentContext, setDialogState) {
          return AlertDialog(
            backgroundColor: AppTheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: const BorderSide(color: AppTheme.border),
            ),
            titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 8,
            ),
            actionsPadding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.manage_accounts_rounded,
                    color: AppTheme.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Edit Profile Account',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        'Update credentials & recovery details',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      // Display Name
                      TextFormField(
                        controller: nameController,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 14,
                        ),
                        decoration: _inputDecoration(
                          label: 'Full Name',
                          hint: 'e.g. John Laurence',
                          icon: Icons.person_outline_rounded,
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Please enter your name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // Gmail / Primary Email
                      TextFormField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 14,
                        ),
                        decoration: _inputDecoration(
                          label: 'Gmail / Primary Email',
                          hint: 'user@gmail.com',
                          icon: Icons.email_outlined,
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Primary Gmail is required';
                          }
                          if (!val.contains('@') || !val.contains('.')) {
                            return 'Enter a valid email address';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // Backup Gmail
                      TextFormField(
                        controller: backupEmailController,
                        keyboardType: TextInputType.emailAddress,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 14,
                        ),
                        decoration: _inputDecoration(
                          label: 'Back up Gmail (Recovery)',
                          hint: 'backup@gmail.com',
                          icon: Icons.mark_email_read_outlined,
                        ),
                        validator: (val) {
                          if (val != null && val.trim().isNotEmpty) {
                            if (!val.contains('@') || !val.contains('.')) {
                              return 'Enter a valid backup email address';
                            }
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // Phone Number
                      TextFormField(
                        controller: phoneController,
                        keyboardType: TextInputType.phone,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 14,
                        ),
                        decoration: _inputDecoration(
                          label: 'Phone Number',
                          hint: '+1 555-0199 or 09123456789',
                          icon: Icons.phone_iphone_rounded,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Password (Hash) Section
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.cardSurface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(
                                  Icons.shield_outlined,
                                  size: 16,
                                  color: AppTheme.secondary,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'PASSWORD',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.8,
                                    color: AppTheme.secondary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: passwordController,
                              obscureText: obscurePassword,
                              style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 14,
                              ),
                              decoration: _inputDecoration(
                                label: 'New Password',
                                hint: 'Leave blank to keep existing',
                                icon: Icons.lock_outline_rounded,
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    obscurePassword
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                    size: 18,
                                    color: AppTheme.textMuted,
                                  ),
                                  onPressed: () => setDialogState(
                                    () => obscurePassword = !obscurePassword,
                                  ),
                                ),
                              ),
                              validator: (val) {
                                if (val != null &&
                                    val.isNotEmpty &&
                                    val.length < 6) {
                                  return 'Password must be at least 6 characters';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: confirmPasswordController,
                              obscureText: obscureConfirm,
                              style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 14,
                              ),
                              decoration: _inputDecoration(
                                label: 'Confirm New Password',
                                hint: 'Re-enter password',
                                icon: Icons.lock_reset_rounded,
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    obscureConfirm
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                    size: 18,
                                    color: AppTheme.textMuted,
                                  ),
                                  onPressed: () => setDialogState(
                                    () => obscureConfirm = !obscureConfirm,
                                  ),
                                ),
                              ),
                              validator: (val) {
                                if (passwordController.text.isNotEmpty &&
                                    val != passwordController.text) {
                                  return 'Passwords do not match';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving
                    ? null
                    : () => Navigator.of(dialogContext).pop(),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.black87,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: isSaving
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        setDialogState(() => isSaving = true);
                        try {
                          await AuthService.instance.updateProfileAccount(
                            newEmail: emailController.text.trim(),
                            backupEmail: backupEmailController.text.trim(),
                            phoneNumber: phoneController.text.trim(),
                            displayName: nameController.text.trim(),
                            newPassword: passwordController.text.isNotEmpty
                                ? passwordController.text
                                : null,
                          );
                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop();
                          }
                          if (mounted) {
                            setState(() {});
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Profile account updated successfully!',
                                ),
                                backgroundColor: AppTheme.primary,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        } catch (e) {
                          setDialogState(() => isSaving = false);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Failed to update account: $e'),
                                backgroundColor: Colors.redAccent,
                              ),
                            );
                          }
                        }
                      },
                child: isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black87,
                        ),
                      )
                    : const Text(
                        'Save Changes',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required String hint,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, size: 18, color: AppTheme.primary),
      suffixIcon: suffixIcon,
      labelStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
      hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
      filled: true,
      fillColor: AppTheme.cardSurface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
      ),
    );
  }

  Widget _buildSectionHeader(IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile.adaptive(
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: AppTheme.textPrimary,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
      ),
      value: value,
      activeTrackColor: AppTheme.primary.withValues(alpha: 0.5),
      activeThumbColor: AppTheme.primary,
      onChanged: onChanged,
    );
  }
}

class _StorageLegend extends StatelessWidget {
  const _StorageLegend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
        ),
      ],
    );
  }
}
