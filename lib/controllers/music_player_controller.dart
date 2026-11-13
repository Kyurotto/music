import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:audio_session/audio_session.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../auth/auth_service.dart';
import '../data/local_database.dart';
import '../models/equalizer_preset.dart';
import '../models/song_model.dart';
import '../services/audio_equalizer_service.dart';
import '../services/playlist_persistence_service.dart';
import '../services/radio_discovery_service.dart';
import '../services/spotify_import_service.dart';
import '../services/track_enrichment_service.dart';

enum PlaybackRepeatMode { off, all, one }

/// Result of merging Spotify-imported tracks into a playlist.
class SpotifyPlaylistImportResult {
  final String playlistId;
  final int addedCount;
  final int reusedLocalCount;

  const SpotifyPlaylistImportResult({
    required this.playlistId,
    required this.addedCount,
    required this.reusedLocalCount,
  });
}

class _DownloadTask {
  final Song song;
  final List<Song> playlistSongs;
  final MusicPlaylist? playlist;
  final String? title;
  final String? subtitle;
  final List<Completer<bool>> completers;

  _DownloadTask({
    required this.song,
    required this.playlistSongs,
    this.playlist,
    this.title,
    this.subtitle,
    required this.completers,
  });
}

class MusicPlayerController extends ChangeNotifier {
  /// Files below this are treated as truncated/incomplete audio.
  static const int _minimumAudioFileBytes = 50000;

  /// Legacy 30-second preview cutoff. Kept for preview detection, but full
  /// downloads smaller than this are now trusted when the database marks
  /// them as non-preview.
  static const int _previewFileSizeThreshold = 1600000;

  /// Containers the downloader can produce. YouTube resolves to WebM/Opus
  /// more often than M4A, so downloads keep the real container instead of
  /// being renamed to `.m4a` and relying on the player to sniff it.
  static const List<String> _audioExtensions = [
    '.m4a',
    '.mp3',
    '.mp4',
    '.aac',
    '.wav',
    '.ogg',
    '.webm',
    '.opus',
    '.flac',
  ];

  /// Picks the on-disk extension for a downloaded stream.
  ///
  /// The response [contentType] wins when the server sends one; otherwise the
  /// URL (including a `mime=` query parameter) is inspected. Falling back to
  /// `.m4a` keeps older downloads discoverable.
  static String _audioExtensionForUrl(String url, {String? contentType}) {
    final mime = (contentType ?? '').toLowerCase().trim();
    if (mime.isNotEmpty) {
      if (mime.contains('audio/mpeg') && !mime.contains('audio/mp4')) {
        return '.mp3';
      }
      if (mime.contains('audio/mp4') ||
          mime.contains('audio/x-m4a') ||
          mime.contains('audio/m4a')) {
        return '.m4a';
      }
      if (mime.contains('audio/aac')) return '.aac';
      if (mime.contains('audio/wav') || mime.contains('audio/x-wav')) {
        return '.wav';
      }
      if (mime.contains('audio/flac') || mime.contains('audio/x-flac')) {
        return '.flac';
      }
      if (mime.contains('audio/opus') || mime.contains('audio/ogg')) {
        return '.ogg';
      }
      if (mime.contains('audio/webm') || mime.contains('video/webm')) {
        return '.webm';
      }
    }

    final lower = url.toLowerCase();
    final mimeParam = RegExp(
      r'[?&](?:mime|mimetype|type)=([^&]+)',
    ).firstMatch(lower)?.group(1);
    if (mimeParam != null && mimeParam.isNotEmpty) {
      final decoded = Uri.decodeComponent(mimeParam);
      // Guard against `type=audio`-style values that carry no container.
      if (decoded.contains('/')) {
        return _audioExtensionForUrl('', contentType: decoded);
      }
    }
    for (final ext in _audioExtensions) {
      if (lower.contains(ext)) return ext;
    }
    return '.m4a';
  }

  final List<Song> _allSongs = [];
  final List<MusicPlaylist> _playlists = [];
  final List<MusicPlaylist> _exploreRadioPlaylists = [];
  final Set<String> _deletedPlaylistIds = <String>{};
  late final UnmodifiableListView<MusicPlaylist> _playlistsView =
      UnmodifiableListView<MusicPlaylist>(_playlists);
  late List<Song> _queue;
  int _currentIndex = 0;

  /// O(1) lookup for [_allSongs]. Rebuilt lazily only when the list structure
  /// changes, instead of scanning the whole library for every row/playlist
  /// check (which made large libraries quadratic).
  final Map<String, Song> _songIndex = <String, Song>{};
  int _songsRevision = 0;
  int _indexedSongsRevision = -1;

  /// Playback progress is published separately from [notifyListeners] so the
  /// whole dashboard/library is not rebuilt 3x per second while a song plays.
  /// Only the small widgets that display progress listen to this notifier.
  final ValueNotifier<Duration> _positionNotifier = ValueNotifier<Duration>(
    Duration.zero,
  );

  bool _isPlaying = false;
  Duration _currentPosition = Duration.zero;
  Duration _audioDuration = Duration.zero;
  double _volume = 0.8;
  double _prevVolume = 0.8;
  bool _isMuted = false;
  bool _isShuffle = false;
  PlaybackRepeatMode _repeatMode = PlaybackRepeatMode.all;
  Timer? _playbackTimer;

  /// Throttle position-stream notifyListeners so UI rebuilds at most ~3x/sec.
  DateTime _lastPositionNotify = DateTime(0);
  static const _positionNotifyInterval = Duration(milliseconds: 300);

  // Real audio player. The Android equalizer effect is attached to the same
  // audio session so preset changes modify the actual output signal.
  final AudioEqualizerService _equalizer = AudioEqualizerService();
  late final AudioPlayer _audioPlayer = AudioPlayer(
    useProxyForRequestHeaders: false,
    audioPipeline: AudioEqualizerService.isPlatformSupported
        ? AudioPipeline(androidAudioEffects: [_equalizer.effect])
        : null,
  );
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<PlaybackEvent>? _playbackEventSub;
  StreamSubscription<int?>? _audioSessionSub;
  bool _audioPlayerHasSource = false;
  bool _isPlayingAudioInProgress = false;

  /// Id of the song whose audio load is currently in flight, so a request for
  /// a different song can supersede it instead of being dropped.
  String? _loadingSongId;
  int _playSessionId = 0;

  /// Guards [_onSongComplete] against duplicate completion signals.
  ///
  /// The player-state stream and the playback heartbeat timer can both report
  /// the same finished track (a 164s file with a 163s expected duration is a
  /// common trigger). Without this guard the first signal advanced to the next
  /// song and the second one immediately skipped that song too
  /// (Lil Kasalanan Shortie -> Babaero -> Burgis).
  bool _completionHandled = false;

  /// When an enrichment hot-swap arrives while [_isPlayingAudioInProgress] is
  /// true, [_playCurrentSongAudio] returns immediately and the new full-track
  /// URL is never loaded. This flag tells the `finally` block to re-enter
  /// [_playCurrentSongAudio] once the current attempt finishes.
  bool _pendingHotSwapReload = false;
  Duration _pendingHotSwapResumePosition = Duration.zero;

  // Keyless enrichment (full-length audio + lyrics) for Spotify imports.
  final TrackEnrichmentService _enrichment = TrackEnrichmentService();
  final Set<String> _enrichingIds = {};
  final Set<String> _enrichedIds = {};

  /// Preview tracks re-attempt a full-length upgrade on a cooldown so an
  /// old 30s import self-heals without spamming Saavn/YouTube on every tick.
  final Map<String, DateTime> _fullUpgradeAttemptedAt = {};
  static const _fullUpgradeCooldown = Duration(seconds: 15);

  /// Failed full-length resolve attempts this session per song. Feeds the
  /// exponential backoff in [_shouldAttemptFullUpgrade] so a track whose
  /// sources are unreachable does not hammer Saavn/YouTube/web search every
  /// 15s. The map is in-memory only, so a stuck preview always restarts at
  /// the 15s interval on the next app start — it is never marked done.
  final Map<String, int> _fullTrackAttemptCount = {};

  /// YouTube URLs expire after a few hours; each successful play re-arms a
  /// single refresh so an expired saved URL resolves fresh instead of
  /// going silent.
  final Set<String> _ytRefreshAttemptedIds = {};

  /// Songs currently playing a bundled offline fallback asset (playback-only).
  /// Their in-memory audioUrl/lyrics are placeholders so real enrichment can
  /// still overwrite them when connectivity returns. Without this, assigning
  /// a fallback would clear isSilentPlaceholder / fill lyrics and permanently
  /// block the background upgrade, leaving the track on the wrong audio with
  /// a stuck slider + lyrics tracker both offline and back online.
  final Set<String> _offlineFallbackIds = {};
  final Set<String> _offlineFakeLyricsIds = {};

  /// Last time the position stream emitted a non-zero position. Used by the
  /// stall watchdog to detect a remote URL stuck in buffering (muted + frozen
  /// slider/lyrics) and fall back to a local file instead of hanging forever.
  DateTime? _lastPositionUpdate;
  Timer? _stallWatchdog;

  String _searchQuery = '';
  String _selectedGenre = 'All';
  int _currentNavIndex = 0; // 0: Home, 1: Explore, 2: Library, 3: Favorites

  /// Monotonically increasing version counter bumped whenever any song's
  /// audio locating, preview-to-full track resolution, or offline caching status changes.
  int _locatingStatusVersion = 0;
  int get locatingStatusVersion => _locatingStatusVersion;

  void bumpLocatingVersion() {
    _locatingStatusVersion++;
    notifyListeners();
  }

  void _unmuteOnPlay() {
    if (_isMuted) {
      _isMuted = false;
    }
    if (_volume <= 0.05) {
      _volume = _prevVolume > 0.05 ? _prevVolume : 0.8;
    }
  }

  static const String _equalizerPresetSetting = 'equalizer_preset';
  static const String _equalizerBandsSetting = 'equalizer_custom_bands';

  String _equalizerPreset = 'Bass Boost';
  List<double> _customEqualizerBands = const [0, 0, 0, 0, 0];

  String get equalizerPreset => _equalizerPreset;

  List<double> get customEqualizerBands => _customEqualizerBands;

  EqualizerPreset get currentEqualizer {
    if (_equalizerPreset == EqualizerPreset.custom.name) {
      return EqualizerPreset.customWithBands(_customEqualizerBands);
    }
    return EqualizerPreset.getByName(_equalizerPreset);
  }

  void setEqualizerPreset(String presetName, {bool save = true}) {
    _equalizerPreset = EqualizerPreset.getByName(presetName).name;
    _applyCurrentEqualizer();
    notifyListeners();
    if (save) {
      unawaited(_persistEqualizerPreset(_equalizerPreset));
      if (_equalizerPreset == EqualizerPreset.custom.name) {
        unawaited(_persistEqualizerBands(_customEqualizerBands));
      }
    }
  }

  /// Applies a user-edited five-band curve (dB) and selects the Custom preset.
  ///
  /// Sliders call this while dragging, so the native equalizer follows the
  /// curve immediately instead of only updating the drawing.
  void setCustomEqualizerBands(List<double> bands, {bool save = true}) {
    _customEqualizerBands = List<double>.unmodifiable(
      bands.map((band) => band.clamp(-10.0, 10.0).toDouble()),
    );
    _equalizerPreset = EqualizerPreset.custom.name;
    _applyCurrentEqualizer();
    notifyListeners();
    if (save) {
      unawaited(_persistEqualizerPreset(_equalizerPreset));
      unawaited(_persistEqualizerBands(_customEqualizerBands));
    }
  }

  void _applyCurrentEqualizer() {
    // Fire-and-forget: the service queues the latest curve until the native
    // effect has published its band layout.
    // ignore: discarded_futures
    _equalizer.applyBands(currentEqualizer.bands);
  }

  Future<void> _loadEqualizerPreset() async {
    try {
      final savedPreset = await LocalDatabase.instance.getSetting(
        _equalizerPresetSetting,
      );
      final savedBands = await LocalDatabase.instance.getSetting(
        _equalizerBandsSetting,
      );
      _customEqualizerBands = _parseCustomBands(savedBands);
      if (savedPreset != null && savedPreset.isNotEmpty) {
        _equalizerPreset = EqualizerPreset.getByName(savedPreset).name;
      }
    } catch (_) {}
    _applyCurrentEqualizer();
    notifyListeners();
  }

  static List<double> _parseCustomBands(String? raw) {
    const flat = <double>[0, 0, 0, 0, 0];
    if (raw == null || raw.trim().isEmpty) return flat;
    final parsed = raw
        .split(',')
        .map((value) => double.tryParse(value.trim()))
        .whereType<double>()
        .toList();
    if (parsed.length != EqualizerPreset.frequencyLabels.length) return flat;
    return parsed
        .map((value) => value.clamp(-10.0, 10.0).toDouble())
        .toList(growable: false);
  }

  Future<void> _persistEqualizerPreset(String preset) =>
      LocalDatabase.instance.saveSetting(_equalizerPresetSetting, preset);

  Future<void> _persistEqualizerBands(List<double> bands) => LocalDatabase
      .instance
      .saveSetting(_equalizerBandsSetting, bands.join(','));

  static const String allowExplicitSettingKey = 'allow_explicit';
  static const String visualizerSettingKey = 'canvas_animation';

  bool _allowExplicit = true;
  bool _visualizerEnabled = true;
  bool _autoDownloadOnImport = true;

  /// False when the user enabled the Explicit Content Filter (i.e. the
  /// "Allow playback of explicit-rated content" switch is off).
  bool get allowExplicit => _allowExplicit;

  /// Whether the animated audio wave visualizer should be rendered.
  bool get visualizerEnabled => _visualizerEnabled;

  /// Whether newly imported playlists automatically begin downloading
  /// with 3 concurrent workers for offline mode.
  bool get autoDownloadOnImport => _autoDownloadOnImport;

  set autoDownloadOnImport(bool value) {
    _autoDownloadOnImport = value;
    notifyListeners();
  }

  void setAllowExplicit(bool allow, {bool save = true}) {
    if (_allowExplicit != allow) {
      _allowExplicit = allow;
      if (!allow && (currentSong?.isExplicit ?? false)) {
        pause();
        _notifyExplicitBlocked(currentSong!);
      }
      notifyListeners();
    }
    if (save) {
      unawaited(
        LocalDatabase.instance.saveSetting(
          allowExplicitSettingKey,
          allow.toString(),
        ),
      );
    }
  }

  void setVisualizerEnabled(bool enabled, {bool save = true}) {
    if (_visualizerEnabled != enabled) {
      _visualizerEnabled = enabled;
      notifyListeners();
    }
    if (save) {
      unawaited(
        LocalDatabase.instance.saveSetting(
          visualizerSettingKey,
          enabled.toString(),
        ),
      );
    }
  }

  bool _isExplicitBlocked(Song? song) =>
      !_allowExplicit && (song?.isExplicit ?? false);

  String? _explicitBlockNotice;
  int _explicitBlockNoticeVersion = 0;

  String? get explicitBlockNotice => _explicitBlockNotice;
  int get explicitBlockNoticeVersion => _explicitBlockNoticeVersion;

  void clearExplicitBlockNotice() {
    _explicitBlockNotice = null;
  }

  void _notifyExplicitBlocked(Song song) {
    if (_disposed) return;
    _explicitBlockNotice =
        '“${song.title}” is marked explicit. Turn off “Explicit Content '
        'Filter” in Settings to allow it.';
    _explicitBlockNoticeVersion++;
    notifyListeners();
  }

  /// First index at or after [start] whose track is not blocked by the
  /// explicit-content filter (wraps around the list).
  int? _firstAllowedIndex(List<Song> songs, int start) {
    if (songs.isEmpty) return null;
    final normalized = start.clamp(0, songs.length - 1);
    for (var offset = 0; offset < songs.length; offset++) {
      final index = (normalized + offset) % songs.length;
      if (!_isExplicitBlocked(songs[index])) return index;
    }
    return null;
  }

  /// Effective volume to push to the native player.
  ///
  /// Equalization happens on the audio session via [AudioEqualizerService], so
  /// volume no longer doubles as a fake preset gain.
  double get _effectiveVolume {
    final baseVol = _isMuted ? 0.0 : (_volume > 0.05 ? _volume : 0.8);
    return baseVol.clamp(0.0, 1.0).toDouble();
  }

  /// Re-assert volume on the native player.
  ///
  /// ExoPlayer resets its volume while a source is being (re)prepared, so a
  /// value written before `play()` is often discarded and the track starts
  /// silent — the mute the user reported on imported Spotify tracks. Nudging
  /// volume on every ready transition and for a few seconds after play covers
  /// both the immediate and the late-activating cases.
  void _assertNativeVolume() {
    if (_disposed || !_audioPlayerHasSource) return;
    try {
      // ignore: discarded_futures
      _audioPlayer.setVolume(_effectiveVolume).catchError((_) {});
    } catch (_) {}
  }

  /// Spread the volume re-assertions over the first few seconds of playback.
  void _scheduleVolumeReasserts() {
    for (final delayMs in const [0, 80, 200, 450, 800, 1400, 2200, 3200]) {
      Future.delayed(Duration(milliseconds: delayMs), _assertNativeVolume);
    }
  }

  /// Re-assert audio focus before starting playback.
  ///
  /// Android deactivates the session when another app takes focus. When that
  /// happens `play()` still succeeds but the output stays silent, which is the
  /// mute the user hit after backgrounding/resuming on imported tracks.
  void _activateAudioSession() {
    // ignore: discarded_futures
    _requestAudioFocus();
  }

  /// Ask the platform to re-activate the audio session (audio focus).
  Future<void> _requestAudioFocus() async {
    try {
      final session = await AudioSession.instance;
      await session.setActive(true);
      _audioFocusRequested = true;
    } catch (_) {}
  }

  /// True once we have successfully asked the platform for audio focus.
  /// `AudioSession` exposes no `isActive`, so we track our own request.
  bool _audioFocusRequested = false;

  /// The controller currently receiving media-notification transport taps.
  /// The notification outlives widgets, so this reference is static.
  static MusicPlayerController? _notificationController;

  MusicPlayerController() {
    _allSongs.addAll(SampleMusicData.sampleSongs);
    _playlists.addAll(SampleMusicData.initialPlaylists);
    _queue = List<Song>.from(_allSongs);

    _initAudioPlayer();
    _bindNotificationControls();
    unawaited(_equalizer.initialize());
    unawaited(_offlineCandidateDirs());
    _startImportRetryLoop();
    _startConnectivityWatcher();
    // Load previously imported playlists for the active user
    unawaited(
      loadSavedPlaylists().catchError((e) {
        debugPrint(
          '[MusicPlayerController] Initial loadSavedPlaylists skipped: $e',
        );
      }),
    );
    // Pre-extract offline audio assets so they are ready on disk immediately
    unawaited(
      _preExtractBundledAssets().catchError((e) {
        debugPrint(
          '[MusicPlayerController] _preExtractBundledAssets skipped: $e',
        );
      }),
    );
    unawaited(_loadEqualizerPreset());
  }

  /// Routes the media notification's previous/next buttons to this controller.
  ///
  /// `just_audio` is loaded one track at a time (`setAudioSource` per song), so
  /// its native sequence never reports a next/previous item and the
  /// notification would otherwise show only play/pause. The local fork in
  /// `packages/just_audio_background` exposes these callbacks; see
  /// [JustAudioBackground.onSkipToNext] / [onSkipToPrevious].
  ///
  /// Safe to call repeatedly: creating a new controller (e.g. after signing
  /// out and back in) simply re-points the notification at the live instance.
  void _bindNotificationControls() {
    _notificationController = this;
    JustAudioBackground.onSkipToNext = _skipToNextFromNotification;
    JustAudioBackground.onSkipToPrevious = _skipToPreviousFromNotification;
    // A notification from a previous session may still be visible; refresh it
    // so the new buttons appear immediately. Idle players ignore this.
    JustAudioBackground.refreshNotification();
  }

  static Future<void> _skipToNextFromNotification() async {
    final controller = _notificationController;
    if (controller == null || controller._disposed) return;
    controller.next();
  }

  static Future<void> _skipToPreviousFromNotification() async {
    final controller = _notificationController;
    if (controller == null || controller._disposed) return;
    controller.previous();
  }

  /// Configure and activate the shared audio session.
  ///
  /// main() configures the session before this controller (and therefore
  /// before its AudioPlayer) is created; this re-applies the music
  /// configuration and grabs focus so a freshly-created player always starts
  /// audible instead of silent.
  Future<void> _initAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      await session.setActive(true);

      // Another app (call, other player) took audio focus: when it hands
      // focus back, re-activate the session and re-assert volume/playback.
      // Without this the track resumed with the output still silent.
      await _interruptionSub?.cancel();
      _interruptionSub = session.interruptionEventStream.listen((event) {
        if (_disposed || event.begin) return;
        if (_isPlaying && _audioPlayerHasSource) {
          _activateAudioSession();
          _assertNativeVolume();
          _scheduleVolumeReasserts();
          try {
            if (!_audioPlayer.playing) {
              // ignore: discarded_futures
              _audioPlayer.play().catchError((_) {});
            }
          } catch (_) {}
        }
      });

      // Headphones unplugged / Bluetooth disconnected: pause instead of
      // blasting the speaker or playing to nowhere.
      await _noisySub?.cancel();
      _noisySub = session.becomingNoisyEventStream.listen((_) {
        if (_disposed) return;
        pause();
      });
    } catch (e) {
      debugPrint('[MusicPlayerController] AudioSession configure error: $e');
    }
  }

  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  StreamSubscription<void>? _noisySub;

  void _initAudioPlayer() {
    try {
      // ignore: discarded_futures
      _initAudioSession();

      // ignore: discarded_futures
      _audioPlayer.setVolume(_volume).catchError((_) {});

      // Listen to position updates from real audio player
      _positionSub = _audioPlayer.positionStream.listen((pos) {
        if (_audioPlayerHasSource && _isPlaying) {
          _currentPosition = pos;
          _lastPositionUpdate = DateTime.now();
          // A real position means this is genuine audio, not a placeholder.
          // Clear any stale fallback flag so future upgrades work normally.
          final song = currentSong;
          if (song != null &&
              pos > Duration.zero &&
              _offlineFallbackIds.contains(song.id) &&
              !song.audioUrl.contains('offline_audio') &&
              !song.audioUrl.contains('assets_audio_')) {
            _offlineFallbackIds.remove(song.id);
          }
          // Throttle to ~3 updates/sec — position ticks fire far more often
          // and rebuilding the whole app for each tick caused visible lag on
          // large libraries. Only progress widgets listen to this notifier.
          final now = DateTime.now();
          if (now.difference(_lastPositionNotify) >= _positionNotifyInterval) {
            _lastPositionNotify = now;
            _positionNotifier.value = _currentPosition;
          }
        }
      });

      // Listen to duration updates
      _durationSub = _audioPlayer.durationStream.listen((dur) {
        if (dur != null && dur > Duration.zero) {
          _audioDuration = dur;
          // If duration reported by the player is ~30s but the song's expected length
          // is > 60s, this is a 30s preview clip. Trigger full upgrade immediately.
          final song = currentSong;
          if (song != null) {
            if (dur <= const Duration(seconds: 35) &&
                song.duration > const Duration(seconds: 60)) {
              song.isPreview = true;
              // Skip when the full-track pass is already running (the quick
              // preview pass clears the flag in _enrichingIds when it ends).
              if (!_enrichingIds.contains(song.id) &&
                  !_pendingEnrichment.containsKey(song.id)) {
                _fullUpgradeAttemptedAt.remove(song.id);
                _enrichingIds.add(song.id);
                // ignore: discarded_futures
                _enrichOneSong(song, fastImport: true);
              }
            } else if (dur > const Duration(seconds: 45)) {
              // Real full track audio is active: clear any stuck preview flag and persist
              if (song.isPreview) {
                song.isPreview = false;
                song.duration = dur;
                _syncSongPathToQueueAndDb(song);
              }
            }
          }
          notifyListeners();
        }
      });

      // Listen to player state: when the stream enters the ready & playing state,
      // re-assert volume to guarantee that native audio initialization never leaves
      // the track muted.
      _playerStateSub = _audioPlayer.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.ready) {
          _cancelStallWatchdog();
          if (state.playing) {
            // Playback of the current track has genuinely started. Re-arm the
            // completion guard so a stale "completed" signal from the previous
            // track cannot skip this one (and so the next real completion is
            // handled normally).
            _completionHandled = false;
          }
          if (_isPlaying && !_isMuted && _audioPlayerHasSource) {
            _unmuteOnPlay();
            _assertNativeVolume();
            _scheduleVolumeReasserts();
          }
          final readySong = currentSong;
          if (readySong != null && state.playing) {
            // ignore: discarded_futures
            _logPlaybackDiagnostics('PLAYBACK READY', readySong);
          }
        }
        // A remote URL stuck in buffering/loading with no position progress
        // is the classic "muted + frozen slider + frozen lyrics" state.
        // Arm the watchdog so we fall back to a local file instead of
        // hanging forever on an expired YouTube link or dead offline stream.
        if (_isPlaying &&
            (state.processingState == ProcessingState.buffering ||
                state.processingState == ProcessingState.loading)) {
          _startStallWatchdog();
        }
        if (state.processingState == ProcessingState.completed) {
          _cancelStallWatchdog();
          _onSongComplete();
        }
      });

      // Keep the native equalizer bound to whatever audio session the player
      // is currently using. The id changes when the platform recreates its
      // audio track, and an effect attached to a dead session is silent.
      _audioSessionSub = _audioPlayer.androidAudioSessionIdStream.listen(
        (sessionId) {
          // ignore: discarded_futures
          _equalizer.setAudioSessionId(sessionId);
        },
        onError: (Object e) {
          debugPrint('Audio session id stream error: $e');
        },
      );

      // Async media failures arrive on the playback-event channel.
      // If the current song encounters a playback error, immediately recover!
      _playbackEventSub = _audioPlayer.playbackEventStream.listen(
        (_) {},
        onError: (Object e) {
          final song = currentSong;
          if (song == null) return;
          debugPrint('Audio playback error for ${song.title}: $e');
          // ignore: discarded_futures
          _handleAudioLoadFailure(song);
        },
      );
    } catch (e) {
      debugPrint('Error initializing audio player: $e');
    }
  }

  // Getters
  List<Song> get allSongs => _allSongs;
  List<MusicPlaylist> get playlists {
    for (final p in _playlists) {
      if (p.imageUrl.isEmpty) {
        final curated = _curatedCoverForTitle(p.title);
        if (curated.isNotEmpty) {
          p.imageUrl = curated;
          unawaited(
            LocalDatabase.instance.updateImportedPlaylistImageUrl(
              p.id,
              curated,
            ),
          );
        }
      }
    }
    return _playlistsView;
  }

  /// Helper to check if a playlist ID belongs to an internal Explore radio station.
  static bool isExploreRadioPlaylist(String id) {
    return id.startsWith('radio-') ||
        id.startsWith('dailymix-') ||
        id.startsWith('artist-');
  }

  /// Returns only user library playlists, strictly excluding Explore radio stations.
  List<MusicPlaylist> get libraryPlaylists =>
      _playlists.where((p) => !isExploreRadioPlaylist(p.id)).toList();

  /// Returns active Explore radio playlists (which stay solely in Explore).
  List<MusicPlaylist> get exploreRadioPlaylists =>
      List.unmodifiable(_exploreRadioPlaylists);

  List<Song> get queue => _queue;
  int get currentIndex => _currentIndex;
  Song? get currentSong =>
      (_queue.isNotEmpty && _currentIndex >= 0 && _currentIndex < _queue.length)
      ? _queue[_currentIndex]
      : null;
  bool get isPlaying => _isPlaying;
  Duration get currentPosition => _currentPosition;

  /// Lightweight listenable for playback progress. Widgets that render the
  /// slider/lyrics subscribe here instead of rebuilding on every
  /// [notifyListeners] call.
  ValueListenable<Duration> get positionListenable => _positionNotifier;
  Duration get currentDuration {
    if (_audioDuration > Duration.zero) return _audioDuration;
    return currentSong?.duration ?? Duration.zero;
  }

  /// Duration to display for [song].
  ///
  /// Preview clips report ~30s once loaded while full streams report the
  /// whole track. Once real audio loads, [_audioDuration] holds the true
  /// playable length — use it for the current track so the slider max and
  /// the time labels always agree.
  Duration displayDurationFor(Song song) {
    if (currentSong?.id == song.id && _audioDuration > Duration.zero) {
      return _audioDuration;
    }
    return song.duration;
  }

  double get volume => _isMuted ? 0.0 : _volume;
  bool get isMuted => _isMuted;
  bool get isShuffle => _isShuffle;
  PlaybackRepeatMode get repeatMode => _repeatMode;
  String get searchQuery => _searchQuery;
  String get selectedGenre => _selectedGenre;
  int get currentNavIndex => _currentNavIndex;

  List<Song> get filteredSongs {
    return _allSongs.where((song) {
      final matchesGenre =
          _selectedGenre == 'All' ||
          song.genre.toLowerCase() == _selectedGenre.toLowerCase();
      final matchesQuery =
          _searchQuery.isEmpty ||
          song.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          song.artist.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          song.album.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesGenre && matchesQuery;
    }).toList();
  }

  List<Song> get favoriteSongs {
    return _allSongs.where((song) => song.isLiked).toList();
  }

  MusicPlaylist? playlistById(String playlistId) {
    for (final playlist in _playlists) {
      if (playlist.id == playlistId) {
        if (playlist.imageUrl.isEmpty) {
          final curated = _curatedCoverForTitle(playlist.title);
          if (curated.isNotEmpty) {
            playlist.imageUrl = curated;
            unawaited(
              LocalDatabase.instance.updateImportedPlaylistImageUrl(
                playlist.id,
                curated,
              ),
            );
          }
        }
        return playlist;
      }
    }
    for (final playlist in _exploreRadioPlaylists) {
      if (playlist.id == playlistId) {
        return playlist;
      }
    }
    return null;
  }

  static bool isSameSong(Song a, Song b) {
    if (a.id == b.id) return true;
    final aTitle = _normalizeKey(a.title);
    final bTitle = _normalizeKey(b.title);
    if (aTitle.isEmpty || bTitle.isEmpty) return false;

    final aClean = _normalizeKey(_cleanSongTitle(a.title));
    final bClean = _normalizeKey(_cleanSongTitle(b.title));
    final titleMatch =
        aTitle == bTitle ||
        (aClean.isNotEmpty &&
            (aClean == bClean || aTitle == bClean || bTitle == aClean));
    if (!titleMatch) return false;

    // Check version tags so different versions aren't treated as the same
    final aTags = TrackEnrichmentService.versionTags(a.title);
    final bTags = TrackEnrichmentService.versionTags(b.title);
    if (aTags.length != bTags.length || !aTags.containsAll(bTags)) {
      return false;
    }

    final aArtist = _normalizeKey(a.artist);
    final bArtist = _normalizeKey(b.artist);
    final artistMatch =
        aArtist.isNotEmpty &&
        (aArtist == bArtist ||
            aArtist.contains(bArtist) ||
            bArtist.contains(aArtist));
    return artistMatch;
  }

  List<Song> songsForPlaylist(String playlistId) {
    final playlist = playlistById(playlistId);
    if (playlist == null) return const [];
    final seenIds = <String>{};
    final seenKeys = <String>{};
    final result = <Song>[];
    for (final songId in playlist.songIds) {
      if (!seenIds.add(songId)) continue;
      final song = songById(songId);
      if (song == null) continue;
      final vTags = TrackEnrichmentService.versionTags(song.title).join(',');
      final key =
          '${_normalizeKey(song.title)}|${_normalizeKey(song.artist)}|$vTags';
      if (key != '||' && !seenKeys.add(key)) continue;
      if (song.audioUrl.isEmpty ||
          (!song.audioUrl.startsWith('http') &&
              !song.audioUrl.startsWith('asset') &&
              !File(song.audioUrl).existsSync())) {
        final cached = findCachedAudioFileSync(song.id);
        if (cached != null &&
            cached.existsSync() &&
            cached.lengthSync() > 1024) {
          song.audioUrl = cached.path;
          song.isPreview = false;
          song.isYouTubeAudio = false;
        }
      }
      result.add(song);
    }
    return result;
  }

  /// Checks whether two playlist titles refer to the same artist playlist
  /// (e.g. "Adie", "This Is Adie", "Adie - Top Songs", "Adie Top Tracks").
  static bool isSameArtistPlaylist(String a, String b) {
    final normA = _normalizeKey(a);
    final normB = _normalizeKey(b);
    if (normA.isEmpty || normB.isEmpty) return false;
    if (normA == normB) return true;

    String stripArtistDecorations(String s) {
      var res = s.toLowerCase().trim();
      res = res.replaceAll(
        RegExp(r'^(this is|best of|top songs of|top tracks of)\s+'),
        '',
      );
      res = res.replaceAll(
        RegExp(r'\s*-\s*(top songs|top tracks|essentials|greatest hits)'),
        '',
      );
      res = res.replaceAll(
        RegExp(r'\s+(top songs|top tracks|essentials|greatest hits)$'),
        '',
      );
      return _normalizeKey(res);
    }

    final cleanA = stripArtistDecorations(a);
    final cleanB = stripArtistDecorations(b);
    return cleanA.isNotEmpty && cleanA == cleanB;
  }

  bool createPlaylist(String name) {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty ||
        _playlists.any(
          (playlist) =>
              playlist.title.toLowerCase() == trimmedName.toLowerCase() ||
              _normalizeKey(playlist.title) == _normalizeKey(trimmedName) ||
              isSameArtistPlaylist(playlist.title, trimmedName),
        )) {
      return false;
    }
    _playlists.add(
      MusicPlaylist(
        id: _newPlaylistId(),
        title: trimmedName,
        subtitle: 'Created by you',
        gradient: const [Color(0xFF11998E), Color(0xFF38EF7D)],
      ),
    );
    notifyListeners();
    return true;
  }

  /// Unique playlist id — microsecond timestamps alone can collide when two
  /// playlists are created in the same tick (rapid imports, tests).
  String _newPlaylistId() {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    var id = 'playlist-$stamp';
    var attempt = 0;
    while (_playlists.any((playlist) => playlist.id == id)) {
      attempt++;
      id = 'playlist-$stamp-$attempt';
    }
    return id;
  }

  bool addSongToPlaylist(String playlistId, Song song) {
    final playlist = playlistById(playlistId);
    if (playlist == null || playlist.songIds.contains(song.id)) return false;

    // Prevent duplicate entries of the same song (e.g. from discovery or import)
    final existingSongs = songsForPlaylist(playlistId);
    if (existingSongs.any((s) => isSameSong(s, song))) {
      return false;
    }

    if (!_allSongs.any((existing) => existing.id == song.id)) {
      _allSongs.add(song);
      _markSongsChanged();
    }
    playlist.songIds.add(song.id);
    _persistPlaylistToDb(playlist, null);
    notifyListeners();
    return true;
  }

  /// Creates (or reuses) a playlist named [playlistName] and merges every
  /// imported Spotify track into it.
  ///
  /// Tracks already present in the local library (matched by title + artist)
  /// reuse the existing [Song] so real audio keeps playing. Tracks that only
  /// exist on Spotify are added as metadata entries, then enriched in the
  /// background with a playable preview + lyrics so they are audible.
  /// Re-running the same import never duplicates songs.
  SpotifyPlaylistImportResult importSpotifyTracks({
    required String playlistName,
    required List<SpotifyImportedTrack> tracks,
    String? targetPlaylistId,
    String? spotifyUrl,
    String? imageUrl,
  }) {
    var playlist = targetPlaylistId == null
        ? null
        : playlistById(targetPlaylistId);
    playlist ??= _playlistByTitle(playlistName);
    playlist ??= _playlists
        .where((p) => isSameArtistPlaylist(p.title, playlistName))
        .firstOrNull;
    if (playlist == null) {
      final created = createPlaylist(playlistName);
      if (created) {
        playlist = _playlists.last;
      } else {
        playlist = _playlistByTitle(playlistName);
        playlist ??= _playlists
            .where((p) => isSameArtistPlaylist(p.title, playlistName))
            .firstOrNull;
      }
    }

    var resolvedCover = (imageUrl ?? '').trim();
    if (resolvedCover.isEmpty) {
      resolvedCover = _curatedCoverForTitle(playlistName);
    }
    if (resolvedCover.isEmpty && tracks.isNotEmpty) {
      for (final t in tracks) {
        if (t.artworkUrl.isNotEmpty) {
          resolvedCover = t.artworkUrl;
          break;
        }
      }
    }

    if (playlist == null) {
      playlist = MusicPlaylist(
        id: _newPlaylistId(),
        title: playlistName.trim().isEmpty
            ? 'Spotify Imports'
            : playlistName.trim(),
        subtitle: 'Imported from Spotify',
        gradient: _gradientFor(playlistName).colors,
        imageUrl: resolvedCover,
      );
      _playlists.add(playlist);
    } else if (resolvedCover.isNotEmpty && playlist.imageUrl.isEmpty) {
      playlist.imageUrl = resolvedCover;
    }

    if (playlist.imageUrl.isEmpty) {
      final targetPl = playlist;
      unawaited(() async {
        String? thumb;
        if (spotifyUrl != null && spotifyUrl.isNotEmpty) {
          thumb = await SpotifyImportService.fetchSpotifyThumbnail(spotifyUrl);
        }
        if ((thumb == null || thumb.isEmpty) && !_disposed) {
          thumb = await _fetchItunesCoverForTitle(targetPl.title);
        }
        if (thumb != null && thumb.isNotEmpty && !_disposed) {
          if (targetPl.imageUrl.isEmpty) {
            targetPl.imageUrl = thumb;
            await LocalDatabase.instance.updateImportedPlaylistImageUrl(
              targetPl.id,
              thumb,
            );
            notifyListeners();
          }
        }
      }());
    }

    var added = 0;
    var reusedLocal = 0;
    final newlyAdded = <Song>[];
    final uniqueTracks = <SpotifyImportedTrack>[];
    final seenImportKeys = <String>{};
    for (final t in tracks) {
      final key =
          '${_normalizeKey(t.title)}|${_normalizeKey(t.artist)}|${TrackEnrichmentService.versionTags(t.title).join(',')}';
      if (seenImportKeys.add(key)) {
        uniqueTracks.add(t);
      }
    }

    for (final imported in uniqueTracks) {
      final localMatch = _findLocalMatch(imported);
      final Song song;
      if (localMatch != null) {
        song = localMatch;
        reusedLocal++;
      } else {
        song = _songForImportedTrack(imported);
        if (!_allSongs.any((existing) => existing.id == song.id)) {
          _allSongs.add(song);
          _markSongsChanged();
          if (!_queue.any((existing) => existing.id == song.id)) {
            _queue.add(song);
          }
          newlyAdded.add(song);
        } else {
          // Already known — make sure a previous failed enrichment or preview track retries full resolution.
          final existing = _allSongs.firstWhere((e) => e.id == song.id);
          if (existing.isPreview ||
              !existing.hasAudio ||
              existing.audioUrl.contains('apple.com') ||
              existing.audioUrl.contains('itunes') ||
              existing.audioUrl.contains('deezer') ||
              existing.audioUrl.contains('dzcdn.net')) {
            existing.audioUrl = '';
            existing.isPreview = false;
            existing.isYouTubeAudio = true;
            _enrichedIds.remove(existing.id);
            newlyAdded.add(existing);
          } else if (existing.isSilentPlaceholder &&
              !_enrichedIds.contains(existing.id)) {
            newlyAdded.add(existing);
          }
        }
      }
      unawaited(
        LocalDatabase.instance.removeSetting('deleted_song_${song.id}'),
      );
      if (addSongToPlaylist(playlist.id, song)) {
        added++;
      }
    }

    notifyListeners();
    // Clear any stale backoff so newly imported songs attempt full-length
    // audio immediately instead of waiting on a previous failure's cooldown.
    for (final s in newlyAdded) {
      _fullUpgradeAttemptedAt.remove(s.id);
      _fullTrackAttemptCount.remove(s.id);
    }
    // Locate all imported tracks (full audio + lyrics) immediately.
    // As each song resolves, _applyEnrichment automatically downloads the audio
    // file for permanent offline playback.
    if (newlyAdded.isNotEmpty) {
      fastLocateImportedSongs(songs: newlyAdded);
    }

    // Persist imported playlist & tracks to local database for current user
    unawaited(_persistPlaylistToDb(playlist, spotifyUrl));

    // Automatically start downloading imported tracks with 3 concurrent workers
    // so the playlist is rapidly saved to SQLite and ready for offline playback.
    if (_autoDownloadOnImport) {
      final songsToDownload = newlyAdded.isNotEmpty
          ? newlyAdded
          : _allSongs.where((s) => playlist!.songIds.contains(s.id)).toList();
      if (songsToDownload.isNotEmpty) {
        unawaited(
          downloadPlaylistSongs(
            songsToDownload,
            playlist: playlist,
            title: playlist.title,
            subtitle: playlist.subtitle,
            maxConcurrentWorkers: 3,
          ),
        );
      }
    }

    return SpotifyPlaylistImportResult(
      playlistId: playlist.id,
      addedCount: added,
      reusedLocalCount: reusedLocal,
    );
  }

  /// Asynchronous variant of [importSpotifyTracks] that awaits SQLite disk write
  /// and WAL flush so imports are guaranteed persisted across immediate restarts.
  Future<SpotifyPlaylistImportResult> importSpotifyTracksAsync({
    required String playlistName,
    required List<SpotifyImportedTrack> tracks,
    String? targetPlaylistId,
    String? spotifyUrl,
    String? imageUrl,
  }) async {
    final result = importSpotifyTracks(
      playlistName: playlistName,
      tracks: tracks,
      targetPlaylistId: targetPlaylistId,
      spotifyUrl: spotifyUrl,
      imageUrl: imageUrl,
    );
    final playlist = playlistById(result.playlistId);
    if (playlist != null) {
      await _persistPlaylistToDb(playlist, spotifyUrl);
    }
    return result;
  }

  /// Fast imports an entire RadioStation into the user's Library playlists.
  MusicPlaylist fastImportRadioStation(RadioStation station) {
    var playlist = _playlistByTitle(station.title);
    if (playlist == null) {
      final newId = _newPlaylistId();
      playlist = MusicPlaylist(
        id: newId,
        title: station.title,
        subtitle: station.subtitle,
        gradient: station.gradientColors,
        imageUrl: station.heroImageUrl.isNotEmpty
            ? station.heroImageUrl
            : (station.avatarUrls.isNotEmpty ? station.avatarUrls.first : ''),
        songIds: [],
      );
      _playlists.add(playlist);
    } else {
      if (playlist.imageUrl.isEmpty && station.avatarUrls.isNotEmpty) {
        playlist.imageUrl = station.avatarUrls.first;
      }
    }

    unawaited(
      LocalDatabase.instance.unmarkPlaylistDeleted(
        playlist.id,
        title: playlist.title,
      ),
    );

    for (final song in station.songs) {
      if (!_allSongs.any((s) => s.id == song.id)) {
        _allSongs.add(song);
        _markSongsChanged();
      }
      if (!playlist.songIds.contains(song.id)) {
        playlist.songIds.add(song.id);
      }
    }

    unawaited(_persistPlaylistToDb(playlist, null));
    // Fast-locate all radio tracks strictly via YouTube into full tracks immediately
    fastLocateRadioSongs(station.songs);

    // Automatically start downloading imported radio station tracks with 3 concurrent workers
    if (_autoDownloadOnImport && station.songs.isNotEmpty) {
      unawaited(
        downloadPlaylistSongs(
          station.songs,
          playlist: playlist,
          title: playlist.title,
          subtitle: playlist.subtitle,
          maxConcurrentWorkers: 3,
        ),
      );
    }

    notifyListeners();
    return playlist;
  }

  Future<void> _persistPlaylistToDb(
    MusicPlaylist playlist,
    String? spotifyUrl,
  ) async {
    try {
      final playlistSongs = _allSongs
          .where((s) => playlist.songIds.contains(s.id))
          .toList();

      final rawUserId = AuthService.instance.currentUserId;
      final currentUserId = rawUserId.isEmpty ? 'default_user' : rawUserId;

      await PlaylistPersistenceService.instance.persistPlaylist(
        playlist: playlist,
        songs: playlistSongs,
        spotifyUrl: spotifyUrl,
        userId: currentUserId,
      );
    } catch (e) {
      debugPrint('[MusicPlayerController] _persistPlaylistToDb skipped: $e');
    }
  }

  /// Offline variant: saves the in-memory playlist [playlistId] and its
  /// songs to local SQLite for [userId] (defaults to the current user,
  /// falling back to the anonymous owner), without touching Firebase or
  /// requiring connectivity. Awaitable so callers can confirm the save;
  /// throws on ownership violations or database errors.
  Future<void> persistPlaylistOffline(
    String playlistId, {
    String? userId,
  }) async {
    final playlist = playlistById(playlistId);
    if (playlist == null) {
      throw StateError('Playlist not found: $playlistId');
    }
    final rawId = (userId ?? AuthService.instance.currentUserId);
    final effectiveUserId = rawId.isEmpty ? 'default_user' : rawId;
    final playlistSongs = _allSongs
        .where((s) => playlist.songIds.contains(s.id))
        .map(_songToImportedMap)
        .toList();
    await LocalDatabase.instance.saveImportedPlaylistOffline(
      id: playlist.id,
      userId: effectiveUserId,
      title: playlist.title,
      subtitle: playlist.subtitle,
      spotifyUrl: null,
      gradientColors: playlist.gradient.map((c) => c.toARGB32()).toList(),
      songs: playlistSongs,
    );
  }

  String? _loadedUserId;
  String? get loadedUserId => _loadedUserId;

  /// Restores all saved imported playlists and songs for [userId] (or the current user).
  Future<void> loadSavedPlaylists({String? userId}) async {
    try {
      final uid = userId ?? AuthService.instance.currentUserId;
      _loadedUserId = uid;

      // Purge any playlists or songs that were explicitly marked deleted by ID from in-memory state
      final allSettings = await LocalDatabase.instance.getAllSettings();
      _autoCachePlayedSongs = allSettings[_autoCachePlayedSongsKey] != 'false';
      _allowExplicit = allSettings[allowExplicitSettingKey] != 'false';
      _visualizerEnabled = allSettings[visualizerSettingKey] != 'false';
      _playlists.removeWhere((p) {
        if (allSettings['deleted_playlist_${p.id}'] == 'true') return true;
        final cleanId = p.id.replaceAll(RegExp(r'-[356]$'), '');
        if (cleanId != p.id &&
            allSettings['deleted_playlist_$cleanId'] == 'true') {
          return true;
        }
        return false;
      });

      _allSongs.removeWhere(
        (s) => allSettings['deleted_song_${s.id}'] == 'true',
      );
      _markSongsChanged();
      _queue.removeWhere((s) => allSettings['deleted_song_${s.id}'] == 'true');

      final savedPlaylists = await LocalDatabase.instance
          .getImportedPlaylistsForUser(uid);
      if (savedPlaylists.isEmpty) {
        notifyListeners();
        return;
      }

      var hasChanges = false;
      for (final pData in savedPlaylists) {
        final playlistId = pData['id'] as String;
        final title = pData['title'] as String;
        final isDel = (pData['is_deleted'] as int? ?? 0) == 1;
        if (isDel) continue;

        if (await LocalDatabase.instance.isPlaylistDeleted(
          playlistId,
          title: title,
          userId: uid,
        )) {
          continue;
        }

        final subtitle =
            pData['subtitle'] as String? ?? 'Imported from Spotify';
        final rawColors = pData['gradient_colors'] as List<int>?;
        final colors = (rawColors != null && rawColors.isNotEmpty)
            ? rawColors.map((c) => Color(c)).toList()
            : _gradientFor(title).colors;

        final rawSongs = pData['songs'] as List<dynamic>? ?? [];
        final songIds = <String>[];

        for (final sMap in rawSongs) {
          final s = sMap as Map<String, dynamic>;
          final songId = s['id'] as String;
          final isSongDel = (s['is_deleted'] as int? ?? 0) == 1;
          if (isSongDel) continue;
          if (await LocalDatabase.instance.isSongDeleted(songId)) continue;
          songIds.add(songId);

          var resolvedAudio = s['audio_url'] as String? ?? '';
          var isPreviewVal = s['is_preview'];
          var isPreview = isPreviewVal == 1 || isPreviewVal == true;
          var isYouTubeVal = s['is_youtube_audio'];
          var isYouTubeAudio = isYouTubeVal == 1 || isYouTubeVal == true;
          final youtubeVideoId = s['youtube_video_id'] as String? ?? '';

          // Discard ephemeral googlevideo URLs as well as any 30s preview URLs
          // (apple.com/itunes/deezer/dzcdn.net) so they automatically resolve
          // full-length streams on the phone's live network.
          if (resolvedAudio.contains('googlevideo.com') ||
              resolvedAudio.contains('apple.com') ||
              resolvedAudio.contains('itunes') ||
              resolvedAudio.contains('deezer') ||
              resolvedAudio.contains('dzcdn.net')) {
            resolvedAudio = '';
            isPreview = false;
            isYouTubeAudio = true;
          }

          final cachedFile = await _findCachedAudioFile(songId);
          if (cachedFile != null) {
            if (await _isCompleteOfflineFile(songId, cachedFile)) {
              resolvedAudio = cachedFile.path;
              isPreview = false;
              isYouTubeAudio = false;
              _downloadedSongIds.add(songId);
            } else {
              // Delete incomplete or 30s preview clips so the full track can
              // resolve on the live network.
              try {
                cachedFile.deleteSync();
              } catch (_) {}
              _invalidateOfflineLookup(songId);
              resolvedAudio = '';
              isPreview = false;
              isYouTubeAudio = true;
            }
          } else if (resolvedAudio.isNotEmpty &&
              !resolvedAudio.startsWith('http://') &&
              !resolvedAudio.startsWith('https://') &&
              !resolvedAudio.startsWith('assets/') &&
              !resolvedAudio.startsWith('asset:/')) {
            final f = File(resolvedAudio);
            final length = f.existsSync() ? f.lengthSync() : 0;
            final isPreviewFile =
                isPreview && length < _previewFileSizeThreshold;
            if (!f.existsSync() ||
                length < _minimumAudioFileBytes ||
                isPreviewFile) {
              try {
                if (f.existsSync()) f.deleteSync();
              } catch (_) {}
              resolvedAudio = '';
              isPreview = false;
              isYouTubeAudio = true;
            } else {
              _downloadedSongIds.add(songId);
            }
          }

          // Library tracks used to be forced onto a bundled default clip here
          // whenever their title matched one of the sample songs, so the real
          // track was never even tried. Leave resolvedAudio alone: the real
          // source is resolved at play time and the bundled copy is only a
          // last-resort fallback there.

          final existingIdx = _allSongs.indexWhere(
            (existing) => existing.id == songId,
          );
          if (existingIdx < 0) {
            final songTitle = s['title'] as String? ?? 'Unknown';
            final songArtist = s['artist'] as String? ?? 'Unknown Artist';
            var img = (s['image_url'] as String? ?? '').trim();
            if (img.isEmpty) img = _curatedCoverForTitle(songTitle);

            final song = Song(
              id: songId,
              title: songTitle,
              artist: songArtist,
              album: s['album'] as String? ?? '',
              duration: Duration(
                milliseconds: s['duration_ms'] as int? ?? 180000,
              ),
              genre: s['genre'] as String? ?? 'Spotify',
              imageUrl: img,
              gradientColors: _gradientFor(
                '${s['title']}${s['artist']}',
              ).colors,
              plays: '',
              lyrics: _withoutPlaceholderLyrics(
                (s['lyrics'] as List<dynamic>? ?? [])
                    .map((e) => e.toString())
                    .toList(),
              ),
              audioUrl: resolvedAudio,
              isPreview: isPreview,
              isYouTubeAudio: isYouTubeAudio,
              youtubeVideoId: youtubeVideoId,
              isExplicit:
                  (s['is_explicit'] == 1 ||
                      s['is_explicit'] == true ||
                      s['is_explicit'] == 'true')
                  ? true
                  : null,
            );
            _ensureOfflineLyrics(song);
            if (song.imageUrl.isEmpty) {
              _resolveMissingSongArtwork(song);
            }
            _allSongs.add(song);
            _markSongsChanged();
            if (!_queue.any((existing) => existing.id == songId)) {
              _queue.add(song);
            }
            hasChanges = true;
          } else {
            final existing = _allSongs[existingIdx];
            final storedExplicit =
                s['is_explicit'] == 1 ||
                s['is_explicit'] == true ||
                s['is_explicit'] == 'true';
            if (storedExplicit && !existing.isExplicit) {
              existing.isExplicit = true;
              hasChanges = true;
            }
            final incomingImage = (s['image_url'] as String? ?? '').trim();
            if (existing.imageUrl.isEmpty && incomingImage.isNotEmpty) {
              existing.imageUrl = incomingImage;
              hasChanges = true;
            }
            if (youtubeVideoId.isNotEmpty && existing.youtubeVideoId.isEmpty) {
              existing.youtubeVideoId = youtubeVideoId;
            }
            if (!existing.id.startsWith('spotify-') &&
                !existing.id.startsWith('itunes-') &&
                existing.title.toLowerCase().contains('lips of an angel')) {
              existing.isPreview = false;
              existing.isYouTubeAudio = false;
              existing.duration = const Duration(minutes: 4, seconds: 21);
              if (existing.audioUrl.isEmpty ||
                  existing.audioUrl.contains('googlevideo.com') ||
                  existing.audioUrl.contains('apple.com') ||
                  existing.audioUrl.contains('itunes') ||
                  existing.audioUrl.contains('deezer')) {
                existing.audioUrl = 'assets/audio/lips-of-an-angel.mp3';
                hasChanges = true;
              }
            }
            if (resolvedAudio.isNotEmpty &&
                (existing.isSilentPlaceholder ||
                    existing.isPreview ||
                    (cachedFile != null &&
                        existing.audioUrl != cachedFile.path))) {
              existing.audioUrl = resolvedAudio;
              existing.isPreview = isPreview;
              existing.isYouTubeAudio = isYouTubeAudio;
              hasChanges = true;
            } else if (existing.audioUrl.contains('apple.com') ||
                existing.audioUrl.contains('itunes') ||
                existing.audioUrl.contains('deezer') ||
                existing.audioUrl.contains('dzcdn.net')) {
              existing.audioUrl = '';
              existing.isPreview = false;
              existing.isYouTubeAudio = true;
              hasChanges = true;
            }
            final dbLyrics = _withoutPlaceholderLyrics(
              (s['lyrics'] as List<dynamic>? ?? [])
                  .map((e) => e.toString())
                  .toList(),
            );
            if (existing.lyrics.isEmpty && dbLyrics.isNotEmpty) {
              existing.lyrics = dbLyrics;
              hasChanges = true;
            }
            _ensureOfflineLyrics(existing);
          }
        }

        var rawImageUrl = (pData['image_url'] as String? ?? '').trim();
        final spotifyUrl = (pData['spotify_url'] as String? ?? '').trim();

        // 1. Resolve curated covers for imported playlists
        if (rawImageUrl.isEmpty) {
          rawImageUrl = _curatedCoverForTitle(title);
        }

        // 2. Fallback to first song with artwork
        if (rawImageUrl.isEmpty) {
          for (final sid in songIds) {
            final s = _allSongs.where((song) => song.id == sid).firstOrNull;
            if (s != null && s.imageUrl.isNotEmpty) {
              rawImageUrl = s.imageUrl;
              break;
            }
          }
        }

        final isRadio = isExploreRadioPlaylist(playlistId);
        if (isRadio) {
          final existingExploreIdx = _exploreRadioPlaylists.indexWhere(
            (p) => p.id == playlistId,
          );
          if (existingExploreIdx >= 0) {
            final existing = _exploreRadioPlaylists[existingExploreIdx];
            for (final sid in songIds) {
              if (!existing.songIds.contains(sid)) {
                existing.songIds.add(sid);
              }
            }
          } else {
            _exploreRadioPlaylists.add(
              MusicPlaylist(
                id: playlistId,
                title: title,
                subtitle: subtitle,
                gradient: colors,
                songIds: songIds,
                imageUrl: rawImageUrl.isNotEmpty
                    ? rawImageUrl
                    : _curatedCoverForTitle(title),
              ),
            );
          }
          _playlists.removeWhere((p) => p.id == playlistId);
        } else {
          final existingPlaylistIdx = _playlists.indexWhere(
            (p) =>
                p.id == playlistId ||
                _normalizeKey(p.title) == _normalizeKey(title) ||
                isSameArtistPlaylist(p.title, title),
          );
          if (existingPlaylistIdx >= 0) {
            final existing = _playlists[existingPlaylistIdx];
            final resolvedImage = rawImageUrl.isNotEmpty
                ? rawImageUrl
                : _curatedCoverForTitle(existing.title);
            if (resolvedImage.isNotEmpty && existing.imageUrl.isEmpty) {
              existing.imageUrl = resolvedImage;
              hasChanges = true;
            }
            final existingSongs = songsForPlaylist(existing.id);
            for (final sid in songIds) {
              if (existing.songIds.contains(sid)) continue;
              final incomingSong = _allSongs
                  .where((s) => s.id == sid)
                  .firstOrNull;
              if (incomingSong != null &&
                  existingSongs.any((s) => isSameSong(s, incomingSong))) {
                continue;
              }
              existing.songIds.add(sid);
              hasChanges = true;
            }
          } else {
            final cleanSongIds = <String>[];
            final seenKeys = <String>{};
            for (final sid in songIds) {
              final s = _allSongs.where((song) => song.id == sid).firstOrNull;
              if (s != null) {
                final vTags = TrackEnrichmentService.versionTags(
                  s.title,
                ).join(',');
                final key =
                    '${_normalizeKey(s.title)}|${_normalizeKey(s.artist)}|$vTags';
                if (!seenKeys.add(key)) continue;
              }
              if (!cleanSongIds.contains(sid)) cleanSongIds.add(sid);
            }
            final newPlaylist = MusicPlaylist(
              id: playlistId,
              title: title,
              subtitle: subtitle,
              gradient: colors,
              songIds: cleanSongIds,
              imageUrl: rawImageUrl.isNotEmpty
                  ? rawImageUrl
                  : _curatedCoverForTitle(title),
            );
            _playlists.add(newPlaylist);
            hasChanges = true;
          }
        }

        final targetPl = playlistById(playlistId);
        final currentPlCover = targetPl?.imageUrl ?? rawImageUrl;
        if (currentPlCover.isNotEmpty) {
          unawaited(
            LocalDatabase.instance.updateImportedPlaylistImageUrl(
              playlistId,
              currentPlCover,
            ),
          );
        } else {
          // Try Spotify oEmbed first, then fall back to iTunes search
          unawaited(() async {
            String? thumb;
            if (spotifyUrl.isNotEmpty) {
              thumb = await SpotifyImportService.fetchSpotifyThumbnail(
                spotifyUrl,
              );
            }
            if ((thumb == null || thumb.isEmpty) && !_disposed) {
              thumb = await _fetchItunesCoverForTitle(title);
            }
            if (thumb != null && thumb.isNotEmpty && !_disposed) {
              final pl = playlistById(playlistId);
              if (pl != null && pl.imageUrl.isEmpty) {
                pl.imageUrl = thumb;
                await LocalDatabase.instance.updateImportedPlaylistImageUrl(
                  playlistId,
                  thumb,
                );
                notifyListeners();
              }
            }
          }());
        }
      }

      if (hasChanges) {
        notifyListeners();
      }

      // One-time refilter: audio resolved before the piano/drum/karaoke
      // cover guard existed may point at same-title cover tracks (common
      // on 2000s imports, where JioSaavn returns "Piano Version"/"Drums"
      // uploads). Drop those stored URLs and delete their cached files so
      // enrichment re-resolves them with the stricter matching.
      final needsAudioRefilter =
          (await LocalDatabase.instance.getSetting(
            'saavn_audio_refilter_v1',
          )) !=
          'done';
      if (needsAudioRefilter) {
        for (final s in _allSongs.where((s) => s.id.startsWith('spotify-'))) {
          final looksBad =
              s.audioUrl.contains('saavn.') ||
              (s.audioUrl.isNotEmpty && !s.audioUrl.startsWith('http'));
          if (!looksBad) continue;
          try {
            if (!s.audioUrl.startsWith('http')) {
              final f = File(s.audioUrl);
              if (await f.exists()) await f.delete();
            }
          } catch (_) {}
          s.audioUrl = '';
          s.isPreview = false;
          s.isYouTubeAudio = false;
          try {
            unawaited(
              LocalDatabase.instance.updateImportedSong(
                id: s.id,
                audioUrl: '',
                isPreview: false,
                isYouTubeAudio: false,
                durationMs: s.duration.inMilliseconds,
                imageUrl: s.imageUrl,
                lyrics: s.lyrics,
              ),
            );
          } catch (_) {}
        }
        await LocalDatabase.instance.saveSetting(
          'saavn_audio_refilter_v1',
          'done',
        );
      }

      // One-time cleanup: drop any remaining 30-second piano/drum previews,
      // iTunes/Deezer clips, or expired YouTube URLs so that real full studio
      // tracks from YouTube are freshly resolved and attached.
      final needsAudioRefilterV2 =
          (await LocalDatabase.instance.getSetting('piano_drum_refilter_v2')) !=
          'done';
      if (needsAudioRefilterV2) {
        for (final s in _allSongs.where((s) => s.id.startsWith('spotify-'))) {
          final isLipsOfAnAngel = s.title.toLowerCase().contains(
            'lips of an angel',
          );
          if (isLipsOfAnAngel) continue;
          final isPreviewOrExpired =
              s.isPreview ||
              s.audioUrl.contains('apple.com') ||
              s.audioUrl.contains('itunes') ||
              s.audioUrl.contains('deezer') ||
              s.audioUrl.contains('dzcdn.net') ||
              s.audioUrl.contains('saavn.') ||
              s.audioUrl.contains('googlevideo.com');
          if (!isPreviewOrExpired) continue;
          try {
            if (!s.audioUrl.startsWith('http')) {
              final f = File(s.audioUrl);
              if (await f.exists()) await f.delete();
            }
          } catch (_) {}
          s.audioUrl = '';
          s.isPreview = false;
          s.isYouTubeAudio = false;
          try {
            unawaited(
              LocalDatabase.instance.updateImportedSong(
                id: s.id,
                audioUrl: '',
                isPreview: false,
                isYouTubeAudio: false,
                durationMs: s.duration.inMilliseconds,
                imageUrl: s.imageUrl,
                lyrics: s.lyrics,
              ),
            );
          } catch (_) {}
        }
        await LocalDatabase.instance.saveSetting(
          'piano_drum_refilter_v2',
          'done',
        );
      }

      // One-time cleanup v3: drop stored karaoke/instrumental/cover-variant
      // audio, 30s Spotify-preview URLs and pre-gate web-match URLs so the
      // real studio full tracks are re-resolved from Spotify/YouTube with
      // the stricter guard (which then plays unmuted via the normal
      // hot-swap path). Runs only while online — a silent LOCATING track
      // must never lose its only audio while offline.
      final needsAudioRefilterV3 =
          (await LocalDatabase.instance.getSetting('karaoke_refilter_v3')) !=
          'done';
      if (needsAudioRefilterV3) {
        if (await _isDeviceOnline()) {
          final cacheDirs = await _offlineCandidateDirs();
          for (final s in _allSongs.where((s) => s.id.startsWith('spotify-'))) {
            final url = s.audioUrl;
            final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
            final isStaleHost =
                host.contains('scdn.co') || host.contains('archive.org');
            if (!isStaleHost &&
                !TrackEnrichmentService.isNonStudioTitle(s.title)) {
              continue;
            }
            // Delete any cached file for this song so a stale karaoke
            // download cannot be resurrected after the URL is wiped.
            for (final dir in cacheDirs) {
              for (final ext in _audioExtensions) {
                try {
                  final f = File(p.join(dir.path, '${s.id}$ext'));
                  if (await f.exists()) await f.delete();
                } catch (_) {}
              }
            }
            try {
              if (url.isNotEmpty && !url.startsWith('http')) {
                final f = File(url);
                if (await f.exists()) await f.delete();
              }
            } catch (_) {}
            _invalidateOfflineLookup(s.id);
            s.audioUrl = '';
            s.isPreview = false;
            s.isYouTubeAudio = false;
            try {
              unawaited(
                LocalDatabase.instance.updateImportedSong(
                  id: s.id,
                  audioUrl: '',
                  isPreview: false,
                  isYouTubeAudio: false,
                  durationMs: s.duration.inMilliseconds,
                  imageUrl: s.imageUrl,
                  lyrics: s.lyrics,
                ),
              );
            } catch (_) {}
          }
          await LocalDatabase.instance.saveSetting(
            'karaoke_refilter_v3',
            'done',
          );
        }
      }

      // Drop unplayable googlevideo.com URLs (which fail with 403 Forbidden on ExoPlayer)
      // so all imported playlists cleanly resolve authentic audio from Saavn / iTunes / Deezer.
      final needsCleanGoogleVideoV4 =
          (await LocalDatabase.instance.getSetting('clean_googlevideo_v4')) !=
          'done';
      if (needsCleanGoogleVideoV4) {
        for (final s in _allSongs.where((s) => s.id.startsWith('spotify-'))) {
          if (s.audioUrl.contains('googlevideo.com')) {
            s.audioUrl = '';
            s.isYouTubeAudio = false;
            unawaited(
              LocalDatabase.instance.updateImportedSong(
                id: s.id,
                audioUrl: '',
                isPreview: false,
                isYouTubeAudio: false,
                durationMs: s.duration.inMilliseconds,
                imageUrl: s.imageUrl,
                lyrics: s.lyrics,
              ),
            );
          }
        }
        await LocalDatabase.instance.saveSetting(
          'clean_googlevideo_v4',
          'done',
        );
      }

      // Drop unplayable .m3u8 HLS playlist URLs which fail with ExoPlayer Source/Zip errors
      final needsCleanM3u8V1 =
          (await LocalDatabase.instance.getSetting('clean_m3u8_v1')) != 'done';
      if (needsCleanM3u8V1) {
        for (final s in _allSongs.where(
          (s) => s.id.startsWith('spotify-') || s.id.startsWith('itunes-'),
        )) {
          if (s.audioUrl.toLowerCase().contains('.m3u8')) {
            s.audioUrl = '';
            s.isPreview = false;
            s.isYouTubeAudio = true;
            unawaited(
              LocalDatabase.instance.updateImportedSong(
                id: s.id,
                audioUrl: '',
                isPreview: false,
                isYouTubeAudio: true,
                durationMs: s.duration.inMilliseconds,
                imageUrl: s.imageUrl,
                lyrics: s.lyrics,
              ),
            );
          }
        }
        await LocalDatabase.instance.saveSetting('clean_m3u8_v1', 'done');
      }

      // Pin resolved tracks first: re-link cached full downloads so they
      // never flip back to LOCATING after a restart.
      if (await _relinkCachedAudio() > 0) {
        _locatingStatusVersion++;
        notifyListeners();
      }

      // Re-enrich songs that are missing audio, previews, have unplayable
      // YouTube URLs, or are still missing lyrics (full-track Saavn hits with
      // no lyrics would otherwise never fetch lyrics on restart).
      final toEnrich = _allSongs
          .where(
            (s) =>
                s.id.startsWith('spotify-') &&
                (s.isSilentPlaceholder ||
                    s.isPreview ||
                    s.isYouTubeAudio ||
                    s.audioUrl.isEmpty ||
                    s.audioUrl.contains('apple.com') ||
                    s.audioUrl.contains('itunes') ||
                    s.audioUrl.contains('deezer') ||
                    s.title.toLowerCase().contains('lips of an angel') ||
                    s.audioUrl.contains('googlevideo.com') ||
                    s.lyrics.isEmpty ||
                    !s.lyrics.any((l) => l.trim().startsWith('[')) ||
                    _offlineFallbackIds.contains(s.id) ||
                    _offlineFakeLyricsIds.contains(s.id)),
          )
          .toList();
      if (toEnrich.isNotEmpty) {
        _enrichImportedSongs(toEnrich);
      }

      // Resolve every still-silent track across all accounts, one by one,
      // in the background (results are saved permanently).
      // ignore: discarded_futures
      _backfillSilentTracks();

      // Backfill missing song artworks across the entire library from iTunes
      _backfillMissingSongArtworks();

      // Ensure internal Explore radio stations are never in the user's Library
      _playlists.removeWhere((p) => isExploreRadioPlaylist(p.id));

      // Automatically download saved playlists with undownloaded tracks using 3 workers
      final isTestEnv =
          !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
      if (_autoDownloadOnImport && !isTestEnv) {
        for (final pl in _playlists) {
          final plSongs =
              _allSongs.where((s) => pl.songIds.contains(s.id)).toList();
          final hasUndownloaded = plSongs.any((s) => !isSongDownloaded(s.id));
          if (hasUndownloaded) {
            unawaited(
              downloadPlaylistSongs(
                plSongs,
                playlist: pl,
                title: pl.title,
                subtitle: pl.subtitle,
                maxConcurrentWorkers: 3,
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[MusicPlayerController] loadSavedPlaylists skipped: $e');
    }
  }

  Future<bool> deletePlaylist(String playlistId, {String? userId}) async {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index < 0) return false;
    final deletedPlaylist = _playlists.removeAt(index);
    final deletedTitle = deletedPlaylist.title;
    _deletedPlaylistIds.add(playlistId);
    _deletedPlaylistIds.add(_normalizeKey(deletedTitle));

    // Also remove any duplicate or same-artist playlist variations from memory
    _playlists.removeWhere(
      (p) =>
          p.id == playlistId ||
          _normalizeKey(p.title) == _normalizeKey(deletedTitle) ||
          isSameArtistPlaylist(p.title, deletedTitle),
    );
    _exploreRadioPlaylists.removeWhere(
      (p) =>
          p.id == playlistId ||
          _normalizeKey(p.title) == _normalizeKey(deletedTitle) ||
          isSameArtistPlaylist(p.title, deletedTitle),
    );

    // Remove songs that are no longer part of any playlist from _allSongs
    // so they do NOT appear on the dashboard or library screen.
    // (Full tracks remain permanently saved in SQLite imported_songs).
    final sampleSongIds = SampleMusicData.sampleSongs.map((s) => s.id).toSet();
    final remainingSongIds = _playlists.expand((p) => p.songIds).toSet();
    _allSongs.removeWhere(
      (s) => !sampleSongIds.contains(s.id) && !remainingSongIds.contains(s.id),
    );
    _markSongsChanged();

    _queue.removeWhere(
      (s) => !sampleSongIds.contains(s.id) && !remainingSongIds.contains(s.id),
    );

    if (currentSong != null &&
        !sampleSongIds.contains(currentSong!.id) &&
        !remainingSongIds.contains(currentSong!.id)) {
      pause();
      _currentIndex = -1;
      _currentPosition = Duration.zero;
      _audioDuration = Duration.zero;
    } else if (currentSong != null) {
      _currentIndex = _queue.indexWhere((s) => s.id == currentSong!.id);
    }

    notifyListeners();
    try {
      final uid = (userId != null && userId.isNotEmpty)
          ? userId
          : ((_loadedUserId != null && _loadedUserId!.isNotEmpty)
                ? _loadedUserId!
                : (AuthService.instance.currentUserId.isNotEmpty
                      ? AuthService.instance.currentUserId
                      : AuthService.instance.userEmail));
      await LocalDatabase.instance.deleteImportedPlaylist(
        playlistId,
        userId: uid,
      );
    } catch (e) {
      debugPrint('[MusicPlayerController] deletePlaylist DB error: $e');
    }
    return true;
  }

  /// Removes [songId] from [playlistId] and automatically syncs the deletion to SQLite.
  Future<bool> deleteSongFromPlaylist(
    String playlistId,
    String songId, {
    String? userId,
  }) async {
    final playlist = playlistById(playlistId);
    if (playlist == null) return false;

    final removed = playlist.songIds.remove(songId);
    if (!removed) return false;

    // If this song is not part of any remaining playlist, remove from _allSongs and _queue
    // so it does not appear on the dashboard or library screen.
    final sampleSongIds = SampleMusicData.sampleSongs.map((s) => s.id).toSet();
    final remainingSongIds = _playlists.expand((p) => p.songIds).toSet();
    if (!sampleSongIds.contains(songId) && !remainingSongIds.contains(songId)) {
      _allSongs.removeWhere((s) => s.id == songId);
      _markSongsChanged();
      _queue.removeWhere((s) => s.id == songId);
    }

    if (currentSong?.id == songId &&
        !sampleSongIds.contains(songId) &&
        !remainingSongIds.contains(songId)) {
      pause();
      _currentIndex = -1;
      _currentPosition = Duration.zero;
      _audioDuration = Duration.zero;
    } else if (currentSong != null) {
      _currentIndex = _queue.indexWhere((s) => s.id == currentSong!.id);
    }

    notifyListeners();
    try {
      await LocalDatabase.instance.deleteImportedSongFromPlaylist(
        playlistId: playlistId,
        songId: songId,
      );
    } catch (e) {
      debugPrint('[MusicPlayerController] deleteSongFromPlaylist DB error: $e');
    }
    return true;
  }

  /// Removes [songId] completely from all playlists, catalog, and SQLite database.
  Future<bool> deleteSong(String songId) async {
    for (final p in _playlists) {
      p.songIds.remove(songId);
    }
    _allSongs.removeWhere((s) => s.id == songId);
    _markSongsChanged();
    _queue.removeWhere((s) => s.id == songId);

    if (currentSong?.id == songId) {
      pause();
      _queue.clear();
      _currentIndex = -1;
      _currentPosition = Duration.zero;
      _audioDuration = Duration.zero;
    } else if (currentSong != null) {
      _currentIndex = _queue.indexWhere((s) => s.id == currentSong!.id);
    }

    notifyListeners();
    try {
      await LocalDatabase.instance.deleteImportedSongCompletely(songId);
    } catch (e) {
      debugPrint('[MusicPlayerController] deleteSong DB error: $e');
    }
    return true;
  }

  /// Returns a high-quality cover URL for well-known artist/playlist names,
  /// sourced from Apple Music (iTunes). Returns empty string when not found.
  static String _curatedCoverForTitle(String title) {
    final t = title.toLowerCase();
    // Specific song & track-named playlists
    if (t.contains('perfect')) {
      return 'https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/15/e6/e8/15e6e8a4-4190-6a8b-86c3-ab4a51b88288/190295851286.jpg/600x600bb.jpg';
    } else if (t.contains('just the way you are') ||
        t.contains('just way you are') ||
        t.contains('the way you are')) {
      return 'https://is1-ssl.mzstatic.com/image/thumb/Music114/v4/52/b1/45/52b1452b-229e-78db-231b-7b43fa0077cc/075679956491.jpg/600x600bb.jpg';
    } else if (t.contains('maroon 5') ||
        t.contains('maroon5') ||
        t.contains('maroon-5')) {
      return 'https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/22/4d/37/224d3743-a17b-7e87-bc7e-e5d1e8d6d3e6/00602567039976.rgb.jpg/600x600bb.jpg';
    }
    // Artist-named playlists & radios
    if (t.contains('calum scott')) {
      return 'https://is1-ssl.mzstatic.com/image/thumb/Music125/v4/cd/12/9f/cd129f77-7690-7440-2a25-d9c7f39889d8/17UM1IM44770.rgb.jpg/600x600bb.jpg';
    } else if (t.contains('bruno mars')) {
      return 'https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/71/6a/d0/716ad090-a548-c2bb-6e06-5381aa99e1ee/075679907721.jpg/600x600bb.jpg';
    } else if (t.contains('the script')) {
      return 'https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/be/fc/74/befc74ff-ce69-b5bf-4076-2f1d9fa496e5/886444857430.jpg/600x600bb.jpg';
    } else if (t.contains('ed sheeran')) {
      return 'https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/15/e6/e8/15e6e8a4-4190-6a8b-86c3-ab4a51b88288/190295851286.jpg/600x600bb.jpg';
    } else if (t.contains('eminem')) {
      return 'https://is1-ssl.mzstatic.com/image/thumb/Music128/v4/ea/ac/03/eaac03e5-8e9d-847e-d5b9-af7dee6a970b/00606949063221.rgb.jpg/600x600bb.jpg';
    } else if (t.contains('hinder')) {
      return 'https://is1-ssl.mzstatic.com/image/thumb/Music112/v4/20/a1/64/20a1646d-5e48-2461-21f5-b6201362941f/16UMGIM02722.rgb.jpg/600x600bb.jpg';
    } else if (t.contains('westlife')) {
      return 'https://is1-ssl.mzstatic.com/image/thumb/Music124/v4/02/19/c5/0219c580-295f-5f65-fa83-0ee1f0a0d54b/mzi.iykdfloi.jpg/600x600bb.jpg';
    } else if (t.contains('one direction')) {
      return 'https://is1-ssl.mzstatic.com/image/thumb/Features125/v4/66/75/88/6675882c-3685-2b6b-f9de-c6d3e06602b5/dj.fuklqvvg.jpg/600x600bb.jpg';
    } else if (t.contains('adele')) {
      return 'https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/eb/ca/25/ebca2596-cd1e-b295-91a3-771c868d0a79/191404113868.png/600x600bb.jpg';
    } else if (t.contains('coldplay')) {
      return 'https://is1-ssl.mzstatic.com/image/thumb/Music125/v4/59/4b/e9/594be9e1-5573-6eba-f1ff-83ef7ded2a30/886449255382.jpg/600x600bb.jpg';
    } else if (t.contains('taylor swift')) {
      return 'https://is1-ssl.mzstatic.com/image/thumb/Music116/v4/de/a2/a5/dea2a5fc-4b6b-3b30-7e3d-6fb7e0d65bc4/23UM1IM24638.rgb.jpg/600x600bb.jpg';
    } else if (t.contains('imagine dragons')) {
      return 'https://is1-ssl.mzstatic.com/image/thumb/Music125/v4/43/72/0f/43720fa0-4273-cd5c-8e0a-5e7e3b99fd78/00602547549334.rgb.jpg/600x600bb.jpg';
    } else if (t.contains('linkin park')) {
      return 'https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/c7/ea/4a/c7ea4af9-80dd-0d3e-3e37-a28eb9bbbf0f/00093624781523.rgb.jpg/600x600bb.jpg';
    } else if (t.contains('sam smith')) {
      return 'https://is1-ssl.mzstatic.com/image/thumb/Music125/v4/cf/88/af/cf88af5c-6a73-b265-dbbe-62c76a2a3bb2/00602547064141.rgb.jpg/600x600bb.jpg';
    } else if (t.contains('shawn mendes')) {
      return 'https://is1-ssl.mzstatic.com/image/thumb/Music125/v4/c1/96/6f/c1966f80-77b1-8fc2-b4e9-fc6df7c8e6d5/00602567673224.rgb.jpg/600x600bb.jpg';
    } else if (t.contains('dua lipa')) {
      return 'https://is1-ssl.mzstatic.com/image/thumb/Music124/v4/c0/de/ca/c0deca7a-5faf-a7ea-65dd-f08f49c56b1e/00602508614125.rgb.jpg/600x600bb.jpg';
    } else if (t.contains('the weeknd')) {
      return 'https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/07/48/63/0748637b-4f7d-22de-a04d-1d0ad9dcc6a9/00602508189005.rgb.jpg/600x600bb.jpg';
    } else if (t.contains('justin bieber')) {
      return 'https://is1-ssl.mzstatic.com/image/thumb/Music124/v4/01/26/ad/0126ad4b-9e73-4cd9-bb3a-0617b6fa5a38/00602435963556.rgb.jpg/600x600bb.jpg';
    } else if (t.contains('billie eilish')) {
      return 'https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/82/36/58/82365809-9ab7-9c64-2f31-d1bb3b7e0d0c/00602547859273.rgb.jpg/600x600bb.jpg';
    } else if (t.contains('ariana grande')) {
      return 'https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/a5/71/1c/a5711c8f-fae6-1264-a8c3-c18cf99ecdcb/00602577513527.rgb.jpg/600x600bb.jpg';
    } else if (t.contains('post malone')) {
      return 'https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/56/dd/7a/56dd7ac9-fb56-e55e-fa1d-4a70e18dc0e0/00602577506482.rgb.jpg/600x600bb.jpg';
    } else if (t.contains('rihanna')) {
      return 'https://is1-ssl.mzstatic.com/image/thumb/Music125/v4/d7/4a/ef/d74aef27-7e18-d4d4-0476-e11ffa7a9daa/886445445855.jpg/600x600bb.jpg';
    } else if (t.contains('beyonce') || t.contains('beyoncé')) {
      return 'https://is1-ssl.mzstatic.com/image/thumb/Music116/v4/2f/36/1b/2f361b9d-65d2-5e45-7f5c-a3498a1e8fd5/mzl.oibdotot.jpg/600x600bb.jpg';
    } else if (t.contains('drake')) {
      return 'https://is1-ssl.mzstatic.com/image/thumb/Music125/v4/4a/51/b6/4a51b6de-0f54-a2b3-b0ba-df3044c5be45/00602567799498.rgb.jpg/600x600bb.jpg';
    } else if (t.contains('khalid')) {
      return 'https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/b1/76/46/b17646c1-ee87-0b90-56c2-60f3b3e83e0f/00602577533792.rgb.jpg/600x600bb.jpg';
    } else if (t.contains('charlie puth')) {
      return 'https://is1-ssl.mzstatic.com/image/thumb/Music125/v4/ac/f4/eb/acf4ebee-3a67-4e26-2e0a-0f7c2fa09e26/00602567804628.rgb.jpg/600x600bb.jpg';
    } else if (t.contains('lewis capaldi')) {
      return 'https://is1-ssl.mzstatic.com/image/thumb/Music125/v4/d0/c9/95/d0c995e9-3de6-0fc3-5c76-7a0ba0e6deff/00602577838668.rgb.jpg/600x600bb.jpg';
    } else if (t.contains('a-ha') || t.contains('aha')) {
      return 'https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/5f/37/15/5f371523-ca16-fe52-a80a-39e9c41beecd/00731452649928.rgb.jpg/600x600bb.jpg';
    }
    // Genre/era playlists
    if (t.contains('2000') || t.contains('2000s')) {
      return 'https://image-cdn-fa.spotifycdn.com/image/ab67706c0000da8449869823efd0e91716bcc00c';
    } else if (t.contains('pop rock') || t.contains('pop-rock')) {
      return 'https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/31/6f/a0/316fa05d-9c3a-2336-39db-1faad46d6107/00602547549321.rgb.jpg/600x600bb.jpg';
    } else if (t.contains('r&b') || t.contains('rnb')) {
      return 'https://is1-ssl.mzstatic.com/image/thumb/Features115/v4/05/a3/09/05a30904-e4bf-49c6-b5d3-5afa09e0b4f0/dj.bdpocjib.jpg/600x600bb.jpg';
    } else if (t.contains('hip hop') ||
        t.contains('hip-hop') ||
        t.contains('hiphop')) {
      return 'https://is1-ssl.mzstatic.com/image/thumb/Features115/v4/6a/01/6c/6a016cbe-82dd-c81f-5aac-ce0e05a4c3e8/dj.dnogaida.jpg/600x600bb.jpg';
    } else if (t.contains('chill') || t.contains('relax')) {
      return 'https://is1-ssl.mzstatic.com/image/thumb/Features115/v4/58/4d/c8/584dc8cb-bcd5-9e0c-c22f-da3f4df53a79/dj.mwkfyqga.jpg/600x600bb.jpg';
    } else if (t.contains('workout') ||
        t.contains('gym') ||
        t.contains('fitness')) {
      return 'https://is1-ssl.mzstatic.com/image/thumb/Features115/v4/b4/8e/0f/b48e0f3c-4fe0-5e93-7614-cbc6b46e7efa/dj.eidpvvts.jpg/600x600bb.jpg';
    } else if (t.contains('love') ||
        t.contains('romance') ||
        t.contains('romantic')) {
      return 'https://is1-ssl.mzstatic.com/image/thumb/Features115/v4/3c/57/12/3c571250-2dbd-84ff-e8fc-5dc3be5c0985/dj.xvdbttiu.jpg/600x600bb.jpg';
    }
    return '';
  }

  /// Queries the iTunes Search API for a cover image matching [title].
  /// Returns null if nothing useful is found or on any network error.
  static Future<String?> _fetchItunesCoverForTitle(String title) async {
    try {
      final clean = title
          .replaceAll(RegExp(r'\s*radio\b', caseSensitive: false), '')
          .replaceAll(RegExp(r'^(the\s+)', caseSensitive: false), '')
          .trim();
      final terms = <String>[
        if (clean.isNotEmpty && clean != title.trim()) clean,
        title.trim(),
      ];

      final client = http.Client();
      try {
        for (final term in terms) {
          for (final entity in const ['album', 'song']) {
            final query = Uri.encodeQueryComponent(term);
            final url = Uri.parse(
              'https://itunes.apple.com/search?term=$query&entity=$entity&limit=1',
            );
            final res = await client
                .get(url)
                .timeout(const Duration(seconds: 4));
            if (res.statusCode == 200) {
              final data = jsonDecode(res.body) as Map<String, dynamic>?;
              final results = data?['results'] as List<dynamic>?;
              if (results != null && results.isNotEmpty) {
                final item = results.first as Map<String, dynamic>?;
                var artUrl = (item?['artworkUrl100'] as String? ?? '').trim();
                if (artUrl.isNotEmpty) {
                  return artUrl.replaceAll('/100x100bb.', '/600x600bb.');
                }
              }
            }
          }
        }
      } finally {
        client.close();
      }
    } catch (_) {}
    return null;
  }

  /// Queries the iTunes Search API for a cover image matching a specific [title] and [artist].
  static Future<String?> _fetchItunesCoverForSong(
    String title,
    String artist,
  ) async {
    try {
      final cleanTitle = _cleanSongTitle(title);
      final query = Uri.encodeQueryComponent('$cleanTitle $artist');
      final url = Uri.parse(
        'https://itunes.apple.com/search?term=$query&entity=song&limit=1',
      );
      final client = http.Client();
      try {
        final res = await client.get(url).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>?;
          final results = data?['results'] as List<dynamic>?;
          if (results != null && results.isNotEmpty) {
            final item = results.first as Map<String, dynamic>?;
            var art = (item?['artworkUrl100'] as String? ?? '').trim();
            if (art.isNotEmpty) {
              return art.replaceAll('/100x100bb.', '/600x600bb.');
            }
          }
        }
      } finally {
        client.close();
      }
    } catch (_) {}
    return null;
  }

  void _resolveMissingSongArtwork(Song song) {
    if (song.imageUrl.isNotEmpty) return;
    unawaited(() async {
      try {
        var art = _curatedCoverForTitle(song.title);
        if (art.isEmpty) {
          art = await _fetchItunesCoverForSong(song.title, song.artist) ?? '';
        }
        if (art.isNotEmpty && !_disposed) {
          if (song.imageUrl.isEmpty) {
            song.imageUrl = art;
            await LocalDatabase.instance.updateImportedSong(
              id: song.id,
              imageUrl: art,
            );
            notifyListeners();
          }
        }
      } catch (_) {}
    }());
  }

  void _backfillMissingSongArtworks() {
    final missing = _allSongs.where((s) => s.imageUrl.isEmpty).toList();
    if (missing.isEmpty) return;

    unawaited(() async {
      for (final song in missing) {
        if (_disposed) break;
        if (song.imageUrl.isNotEmpty) continue;
        var art = _curatedCoverForTitle(song.title);
        if (art.isEmpty) {
          art = await _fetchItunesCoverForSong(song.title, song.artist) ?? '';
        }
        if (art.isNotEmpty && !_disposed) {
          song.imageUrl = art;
          try {
            await LocalDatabase.instance.updateImportedSong(
              id: song.id,
              imageUrl: art,
            );
          } catch (_) {}
          notifyListeners();
        }
      }
    }());
  }

  MusicPlaylist? _playlistByTitle(String title) {
    final needle = _normalizeKey(title);
    if (needle.isEmpty) return null;
    for (final playlist in _playlists) {
      if (_normalizeKey(playlist.title) == needle) return playlist;
    }
    return null;
  }

  static String _cleanSongTitle(String title) {
    return title
        .replaceAll(RegExp(r'\s*\([^)]*\)'), '')
        .replaceAll(RegExp(r'\s*\[[^\]]*\]'), '')
        .replaceAll(RegExp(r'\s*-\s*.*$'), '')
        .replaceAll(
          RegExp(r'\b(feat|ft|featuring)\b.*$', caseSensitive: false),
          '',
        )
        .trim();
  }

  Song? _findLocalMatch(SpotifyImportedTrack imported) {
    final titleKey = _normalizeKey(imported.title);
    final cleanTitleKey = _normalizeKey(_cleanSongTitle(imported.title));
    final artistKey = _normalizeKey(imported.artist);
    if ((titleKey.isEmpty && cleanTitleKey.isEmpty) || artistKey.isEmpty) {
      return null;
    }

    for (final song in _allSongs) {
      // Do not match bundled assets — imported music must not default to the assets folder.
      if (song.audioUrl.startsWith('assets/') ||
          song.audioUrl.startsWith('asset:/')) {
        continue;
      }

      final songTitleKey = _normalizeKey(song.title);
      final songCleanTitleKey = _normalizeKey(_cleanSongTitle(song.title));
      final titleMatches =
          songTitleKey == titleKey ||
          (cleanTitleKey.isNotEmpty &&
              (songCleanTitleKey == cleanTitleKey ||
                  songTitleKey == cleanTitleKey ||
                  (cleanTitleKey.length >= 4 &&
                      (songTitleKey.contains(cleanTitleKey) ||
                          cleanTitleKey.contains(songCleanTitleKey)))));
      if (!titleMatches) continue;

      // "X (Tagalog Version)" and "X (English Version)" clean to the same
      // title, so the second one used to be merged into the first and dropped
      // from the playlist. Different versions are different songs.
      final importedTags = TrackEnrichmentService.versionTags(imported.title);
      final songTags = TrackEnrichmentService.versionTags(song.title);
      if (importedTags.length != songTags.length ||
          !importedTags.containsAll(songTags)) {
        continue;
      }

      final songArtist = _normalizeKey(song.artist);
      if (songArtist.isNotEmpty &&
          (songArtist == artistKey ||
              songArtist.contains(artistKey) ||
              artistKey.contains(songArtist))) {
        return song;
      }
    }

    for (final song in SampleMusicData.bundledTracks) {
      final songTitleKey = _normalizeKey(song.title);
      final songCleanTitleKey = _normalizeKey(_cleanSongTitle(song.title));
      final titleMatches =
          songTitleKey == titleKey ||
          (cleanTitleKey.isNotEmpty &&
              (songCleanTitleKey == cleanTitleKey ||
                  songTitleKey == cleanTitleKey ||
                  (cleanTitleKey.length >= 4 &&
                      (songTitleKey.contains(cleanTitleKey) ||
                          cleanTitleKey.contains(songCleanTitleKey)))));
      if (!titleMatches) continue;

      final songArtist = _normalizeKey(song.artist);
      if (songArtist.isNotEmpty &&
          (songArtist == artistKey ||
              songArtist.contains(artistKey) ||
              artistKey.contains(songArtist))) {
        return song;
      }
    }

    return null;
  }

  Song _songForImportedTrack(SpotifyImportedTrack imported) {
    final duration = imported.duration > Duration.zero
        ? imported.duration
        : const Duration(minutes: 3);

    var artwork = imported.artworkUrl.trim();
    if (artwork.isEmpty) {
      artwork = _curatedCoverForTitle(imported.title);
    }

    final song = Song(
      id: 'spotify-${imported.spotifyId}',
      title: imported.title,
      artist: imported.artist,
      album: imported.album,
      duration: duration,
      genre: 'Spotify',
      imageUrl: artwork,
      gradientColors: _gradientFor(
        '${imported.title}${imported.artist}',
      ).colors,
      plays: '',
      lyrics: const [],
      audioUrl:
          '', // Do NOT default to assets/audio! Stored dynamically in local audio cache.
      isPreview: false,
      isExplicit: imported.isExplicit,
    );
    _ensureOfflineLyrics(song);
    if (song.imageUrl.isEmpty) {
      _resolveMissingSongArtwork(song);
    }
    return song;
  }

  void _enrichImportedSongs(
    List<Song> songs, {
    bool fastImport = true,
    int maxConcurrency = 3,
  }) {
    final pending = songs.where((s) {
      if (_enrichingIds.contains(s.id)) return false;
      final isFallback = _offlineFallbackIds.contains(s.id);
      final hasFakeLyrics = _offlineFakeLyricsIds.contains(s.id);
      final isRadioTrack = s.id.startsWith('radio-') || s.id.startsWith('dm-');

      // Silent tracks and fallbacks retry under exponential backoff
      final needsAudio =
          (!s.hasAudio || s.isSilentPlaceholder || isFallback || s.isPreview) &&
          (fastImport || isRadioTrack || _shouldAttemptFullUpgrade(s.id));

      final hasSyncedLyrics = s.lyrics.any((l) => l.trim().startsWith('['));
      final needsLyrics =
          (s.lyrics.isEmpty || hasFakeLyrics || !hasSyncedLyrics) &&
          (fastImport || isRadioTrack || !_enrichedIds.contains(s.id));
      return needsAudio || needsLyrics;
    }).toList();

    if (pending.isEmpty) return;

    // Process with bounded concurrency (3 concurrent workers) so whole playlists
    // resolve in seconds on WiFi and mobile data without network choking.
    // Prioritizes currently active or first tracks first.
    // ignore: discarded_futures
    Future.microtask(() async {
      _importEnrichPasses++;
      try {
        final activeId = currentSong?.id;
        final ordered = List<Song>.from(pending);
        if (activeId != null) {
          final activeIdx = ordered.indexWhere((s) => s.id == activeId);
          if (activeIdx > 0) {
            final activeSong = ordered.removeAt(activeIdx);
            ordered.insert(0, activeSong);
          }
        }

        var nextIdx = 0;

        Future<void> worker() async {
          while (!_disposed) {
            final song = nextIdx < ordered.length ? ordered[nextIdx++] : null;
            if (song == null) break;
            // Clear stale backoff so fast-locate never skips a song
            _fullUpgradeAttemptedAt.remove(song.id);
            _fullTrackAttemptCount.remove(song.id);
            _enrichingIds.add(song.id);
            _fullUpgradeAttemptedAt[song.id] = DateTime.now();
            try {
              await _enrichOneSong(song, fastImport: fastImport);
            } catch (_) {}
          }
        }

        final workers = List.generate(
          ordered.length < maxConcurrency ? ordered.length : maxConcurrency,
          (_) => worker(),
        );
        await Future.wait(workers);
      } finally {
        _importEnrichPasses--;
      }
    });
  }

  /// Background pass that keeps retrying full-track resolution for imported
  /// songs that are still silent. Strict mode never falls back to a 30s
  /// preview, so without this loop a failed resolve would leave the song
  /// muted until the next app restart or manual play/lyrics-sheet attempt.
  /// The exponential backoff in [_shouldAttemptFullUpgrade] keeps the loop
  /// cheap: a track that keeps failing is re-checked less often, capped at
  /// once every 5 minutes.
  Timer? _importRetryTimer;
  int _importEnrichPasses = 0;
  bool _backfillRunning = false;

  void _startImportRetryLoop() {
    _importRetryTimer?.cancel();
    _importRetryTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_disposed || _importEnrichPasses > 0) return;
      // Nothing to resolve while offline; the connectivity watcher re-runs
      // this the moment the network returns.
      if (!_cachedOnline) return;
      // Tracks on an offline fallback or a 30s preview are included too:
      // before, only tracks with no audio at all were ever retried, so a
      // fallback/preview track never upgraded after connectivity returned.
      final stuck = _allSongs
          .where(
            (s) =>
                needsFullTrack(s) &&
                !_enrichingIds.contains(s.id) &&
                _shouldAttemptFullUpgrade(s.id),
          )
          .toList();
      if (stuck.isEmpty) return;
      _logDiag('import retry loop: ${stuck.length} silent/preview track(s)');
      _enrichImportedSongs(stuck, maxConcurrency: 2);
    });
  }

  // ---------------------------------------------------------------------
  // Connectivity watcher (Wi-Fi / mobile data / offline)
  // ---------------------------------------------------------------------

  Timer? _connectivityTimer;
  bool _watchedOnline = true;

  /// app_settings key written by the "Download on mobile data" switch.
  static const String _downloadOnMobileKey = 'download_on_mobile_data';

  /// app_settings key written by the "Cache played songs" switch.
  static const String _autoCachePlayedSongsKey = 'auto_cache_played_songs';

  /// When true, playing a remote track still writes a local copy. Importing
  /// playlists no longer downloads anything: only playback and explicit
  /// downloads touch the offline cache.
  bool _autoCachePlayedSongs = true;

  bool get autoCachePlayedSongs => _autoCachePlayedSongs;

  void setAutoCachePlayedSongs(bool enabled) {
    if (_autoCachePlayedSongs == enabled) return;
    _autoCachePlayedSongs = enabled;
    unawaited(
      LocalDatabase.instance
          .saveSetting(_autoCachePlayedSongsKey, enabled.toString())
          .catchError((_) {}),
    );
    notifyListeners();
  }

  /// Songs the player gave up on (no cache, no stream, no bundled asset).
  /// Drives the "can't play" message and Retry in the player bar.
  final Set<String> _unavailableIds = {};

  bool isUnavailable(String songId) => _unavailableIds.contains(songId);

  /// True on cellular without Wi-Fi/ethernet. Returns false when the platform
  /// can't tell (tests, desktop) so downloads are never blocked by mistake.
  Future<bool> _isOnMeteredConnection() async {
    try {
      final results = await Connectivity().checkConnectivity();
      final unmetered =
          results.contains(ConnectivityResult.wifi) ||
          results.contains(ConnectivityResult.ethernet);
      return results.contains(ConnectivityResult.mobile) && !unmetered;
    } catch (_) {
      return false;
    }
  }

  /// Offline-cache downloads are skipped on mobile data unless the user
  /// turned "Download on mobile data" on. Streaming for playback is unaffected.
  Future<bool> _mayDownloadNow() async {
    if (!await _isOnMeteredConnection()) return true;
    try {
      final v = await LocalDatabase.instance.getSetting(_downloadOnMobileKey);
      return v == 'true';
    } catch (_) {
      return true;
    }
  }

  /// The current song could not be played: stop pretending it is playing.
  void _markUnavailable(Song song) {
    if (_disposed || song.id != currentSong?.id) return;
    _unavailableIds.add(song.id);
    _cancelStallWatchdog();
    _playbackTimer?.cancel();
    _isPlaying = false;
    _logDiag('marked unavailable', song: song);
    notifyListeners();
  }

  /// Retry button in the player bar after "can't play".
  void retryCurrentSong() {
    final song = currentSong;
    if (song == null) return;
    resetEnrichmentBackoff(song.id);
    _unavailableIds.remove(song.id);
    _clearSilentRetry();
    _isPlaying = true;
    _unmuteOnPlay();
    _lastPositionUpdate = DateTime.now();
    _startTimer();
    _playCurrentSongAudio();
    notifyListeners();
  }

  /// Polls reachability every 10s and reacts to changes. There is no
  /// platform connectivity callback in this app, so without this the
  /// controller only noticed the network had returned when the user pressed
  /// play or the 30s retry loop happened to run.
  void _startConnectivityWatcher() {
    _connectivityTimer?.cancel();
    _connectivityTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (_disposed) return;
      bool online;
      try {
        online = await _isDeviceOnline();
      } catch (_) {
        return;
      }
      // Back on Wi-Fi after mobile data: playback-triggered caching will retry
      // naturally on the next play. Do not bulk-download the whole library.
      if (_disposed || online == _watchedOnline) return;
      _watchedOnline = online;
      _logDiag('connectivity changed: online=$online');
      if (online) {
        _onBackOnline();
      }
      notifyListeners();
    });
  }

  /// Network came back: forget the failure backoff (it was caused by being
  /// offline, not by the tracks) and upgrade every silent, fallback or
  /// preview imported track, current song first.
  void _onBackOnline() {
    _fullUpgradeAttemptedAt.clear();
    _fullTrackAttemptCount.clear();
    _ytRefreshAttemptedIds.clear();
    _unavailableIds.clear();
    final pending = _allSongs
        .where(
          (s) =>
              (needsFullTrack(s) ||
                  _offlineFallbackIds.contains(s.id) ||
                  _offlineFakeLyricsIds.contains(s.id)) &&
              !_enrichingIds.contains(s.id),
        )
        .toList();
    if (pending.isNotEmpty) {
      _enrichImportedSongs(pending, maxConcurrency: 2);
    }
    // A song that never got a source while offline should start now.
    if (_isPlaying && !_audioPlayerHasSource && !_isPlayingAudioInProgress) {
      _playCurrentSongAudio();
    }
  }

  /// Lets the lyrics sheet's Retry button bypass the per-song backoff.
  void resetEnrichmentBackoff(String songId) {
    _fullUpgradeAttemptedAt.remove(songId);
    _fullTrackAttemptCount.remove(songId);
  }

  bool _shouldAttemptFullUpgrade(String songId) {
    final last = _fullUpgradeAttemptedAt[songId];
    if (last == null) return true;
    return DateTime.now().difference(last) >= _fullUpgradeBackoff(songId);
  }

  /// Retry spacing for a track's full-length resolve: 15s, then 30s, 60s,
  /// 120s and 240s, capped at 5 minutes. Consecutive failures slow a stuck
  /// preview down instead of locking it out, and the count is per-session so
  /// the next app start always begins at the eager 15s interval again.
  Duration _fullUpgradeBackoff(String songId) {
    final failures = (_fullTrackAttemptCount[songId] ?? 0) - 1;
    if (failures <= 0) return _fullUpgradeCooldown;
    var seconds = 15;
    for (var i = 0; i < failures && seconds < 300; i++) {
      seconds *= 2;
    }
    return Duration(seconds: seconds > 300 ? 300 : seconds);
  }

  /// Decode a stored lyrics JSON blob the same way the playlist loader
  /// does, so the backfill never overwrites kept lyrics with blanks.
  static List<String> _decodeDbLyrics(String? raw) {
    if (raw == null || raw.isEmpty) return <String>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map((e) => e.toString()).toList();
      }
    } catch (_) {
      return raw.split('\n');
    }
    return <String>[];
  }

  /// One-by-one backfill across EVERY account: resolves each silent or
  /// preview-only imported track (artist playlists, radios, all users)
  /// through the normal Spotify/YouTube/iTunes-web chain and saves the
  /// result permanently, oldest playlists first. Sequential with small
  /// gaps and online-gated so it never hammers the network; each launch
  /// resumes where the last one stopped.
  Future<void> _backfillSilentTracks() async {
    if (_backfillRunning || _disposed) return;
    _backfillRunning = true;
    try {
      if (!await _isDeviceOnline()) return;
      final rows = await LocalDatabase.instance.getUnresolvedImportedSongs();
      if (rows.isEmpty || _disposed) return;
      debugPrint(
        '[MusicPlayerController] Backfill: ${rows.length} unresolved track(s)',
      );
      final resolvedIds = <String>{};
      for (final row in rows) {
        if (_disposed) return;
        final id = row['id']?.toString() ?? '';
        if (id.isEmpty ||
            !id.startsWith('spotify-') ||
            resolvedIds.contains(id) ||
            _pendingEnrichment.containsKey(id) ||
            _pendingEnrichment.containsKey('$id:preview') ||
            _enrichingIds.contains(id)) {
          continue;
        }
        Song? mem;
        try {
          mem = _allSongs.firstWhere((s) => s.id == id);
        } catch (_) {}
        if (mem != null && mem.hasAudio && !mem.isPreview) continue;
        if (!await _isDeviceOnline()) return;
        final song =
            mem ??
            Song(
              id: id,
              title: row['title']?.toString() ?? '',
              artist: row['artist']?.toString() ?? '',
              album: row['album']?.toString() ?? '',
              duration: Duration(
                milliseconds: (row['duration_ms'] as int?) ?? 180000,
              ),
              genre: 'Spotify',
              imageUrl: '',
              gradientColors: const [],
              plays: '',
              lyrics: _decodeDbLyrics(row['lyrics']?.toString()),
              audioUrl: row['audio_url']?.toString() ?? '',
              isPreview: ((row['is_preview'] as int?) ?? 0) == 1,
              isYouTubeAudio: ((row['is_youtube_audio'] as int?) ?? 0) == 1,
              youtubeVideoId: row['youtube_video_id']?.toString() ?? '',
              isExplicit: ((row['is_explicit'] as int?) ?? 0) == 1
                  ? true
                  : null,
            );
        if (song.title.isEmpty) continue;
        try {
          // Full track first, 30s preview as last resort — the shared
          // recovery persists the result and unmutes silent tracks.
          await _ensureRecoverableAudio(song);
          if (song.hasAudio) {
            debugPrint(
              '[MusicPlayerController] Backfill resolved: ${song.title}',
            );
            resolvedIds.add(id);
            _locatingStatusVersion++;
            notifyListeners();
          }
          // Album-mates found along the way resolve sibling rows in place.
          await _attachSiblings(resolvedIds, rows, song.artist);
        } catch (_) {
          // Next track.
        }
        await Future.delayed(const Duration(milliseconds: 500));
      }
      debugPrint('[MusicPlayerController] Backfill pass finished');
    } finally {
      _backfillRunning = false;
    }
  }

  /// Attaches album-mate audio discovered while resolving another track:
  /// any still-unresolved row with the same artist and a matching title +
  /// duration window gets its sibling file saved permanently.
  Future<void> _attachSiblings(
    Set<String> resolvedIds,
    List<Map<String, Object?>> rows,
    String artist,
  ) async {
    final urls = _enrichment.lastSiblingUrls;
    if (urls.isEmpty || _disposed) return;
    final seconds = _enrichment.lastSiblingSeconds;
    final wantArtist = TrackEnrichmentService.normalizeKey(artist);
    for (final row in rows) {
      if (_disposed) return;
      final id = row['id']?.toString() ?? '';
      if (id.isEmpty ||
          !id.startsWith('spotify-') ||
          resolvedIds.contains(id)) {
        continue;
      }
      final key = TrackEnrichmentService.normalizeKey(
        row['title']?.toString() ?? '',
      );
      final url = urls[key];
      if (key.isEmpty || url == null || url.isEmpty) continue;
      final rowArtist = TrackEnrichmentService.normalizeKey(
        row['artist']?.toString() ?? '',
      );
      if (rowArtist.isEmpty ||
          !(rowArtist == wantArtist ||
              rowArtist.contains(wantArtist) ||
              wantArtist.contains(rowArtist))) {
        continue;
      }
      final s = seconds[key] ?? -1;
      final rowMs = (row['duration_ms'] as int?) ?? 0;
      if (s > 0 && rowMs > 60000) {
        final rowSecs = rowMs ~/ 1000;
        if (rowSecs < (s * 75) ~/ 100 || rowSecs > (s * 160) ~/ 100) {
          continue;
        }
      }
      Song? mem;
      try {
        mem = _allSongs.firstWhere((s) => s.id == id);
      } catch (_) {}
      if (mem != null && mem.hasAudio && !mem.isPreview) {
        resolvedIds.add(id);
        continue;
      }
      if (mem != null) {
        final changed = _applyEnrichment(
          mem,
          TrackEnrichment(
            previewUrl: url,
            previewDuration: s > 0 ? Duration(seconds: s) : null,
            isFullTrack: true,
          ),
        );
        if (changed) notifyListeners();
      } else {
        try {
          await LocalDatabase.instance.updateImportedSong(
            id: id,
            audioUrl: url,
            isPreview: false,
            isYouTubeAudio: false,
            durationMs: s > 0 ? s * 1000 : (rowMs > 0 ? rowMs : null),
          );
        } catch (_) {}
      }
      resolvedIds.add(id);
      debugPrint(
        '[MusicPlayerController] Backfill sibling resolved: ${row['title']}',
      );
    }
  }

  /// Pin: once a track is full, it stays full. Re-links the cached full
  /// download on startup so resolved tracks never flip back to LOCATING
  /// after a restart (expiring stream URLs are intentionally not stored,
  /// but the permanent offline file is). Only full downloads qualify —
  /// preview clips are left alone so they can still upgrade.
  /// Returns how many tracks were pinned.
  Future<int> _relinkCachedAudio() async {
    var pinned = 0;
    try {
      try {
        final dirs = await _offlineCandidateDirs();
        for (final dir in dirs) {
          if (!await dir.exists()) continue;
          final list = dir.listSync();
          for (final f in list) {
            if (f is File) {
              final name = p.basename(f.path);
              final ext = p.extension(name).toLowerCase();
              if (!_audioExtensions.contains(ext)) continue;
              final length = f.lengthSync();
              if (length < _minimumAudioFileBytes) continue;
              final songId = p.basenameWithoutExtension(name);
              // Large files are trustworthy by size alone; smaller ones must
              // be confirmed by the database so short full tracks survive a
              // restart while 30s previews stay out of the downloaded set.
              if (length >= _previewFileSizeThreshold ||
                  await _isCompleteOfflineFile(songId, f)) {
                _downloadedSongIds.add(songId);
              }
            }
          }
        }
      } catch (_) {}

      for (final s in _allSongs.where(
        (s) =>
            _isDownloadableCatalogId(s.id) &&
            (!s.hasAudio ||
                s.isPreview ||
                !s.audioUrl.contains('offline_audio')),
      )) {
        if (_disposed) break;
        try {
          final cached = await _findCachedAudioFile(s.id);
          if (cached != null &&
              cached.existsSync() &&
              await _isCompleteOfflineFile(s.id, cached)) {
            _downloadedSongIds.add(s.id);
            final wasPreview = s.isPreview;
            s.audioUrl = cached.path;
            s.isPreview = false;
            s.isYouTubeAudio = false;
            _syncSongPathToQueueAndDb(s);
            if (wasPreview) {
              unawaited(
                LocalDatabase.instance
                    .updateImportedSong(
                      id: s.id,
                      audioUrl: cached.path,
                      isPreview: false,
                      isYouTubeAudio: false,
                      durationMs: s.duration.inMilliseconds,
                    )
                    .catchError((_) {}),
              );
            }
            pinned++;
          }
        } catch (_) {}
      }
    } catch (_) {}
    return pinned;
  }

  /// Pull-to-refresh entry point: (re)starts the one-by-one full-track
  /// backfill. Safe to call anytime; no-ops while a pass is running.
  void kickBackfill() {
    // ignore: discarded_futures
    _backfillSilentTracks();
  }

  /// In-flight enrichment passes keyed by song id, so the playback path and
  /// the audio-source resolver share one lookup instead of each paying for
  /// their own (previously a 12s await plus a separate 15s await).
  final Map<String, Future<void>> _pendingEnrichment = {};

  /// Starts enrichment for [song] once and returns the shared in-flight
  /// future. Callers may await it (with a bounded timeout) when they genuinely
  /// need audio, or ignore it to stay fully non-blocking. Preview fallbacks
  /// run in their own slot so a slow in-flight full pass never starves them
  /// (the attach rules keep the two passes safe: preview only attaches
  /// while silent, full always upgrades a preview).
  Future<void> _ensureEnrichment(
    Song song, {
    bool previewFallbackOnly = false,
    bool fastImport = false,
  }) {
    if (_disposed) return Future<void>.value();
    final key = previewFallbackOnly ? '${song.id}:preview' : song.id;
    final existing = _pendingEnrichment[key];
    if (existing != null) return existing;
    _fullUpgradeAttemptedAt[song.id] = DateTime.now();
    // _enrichOneSong only clears this flag in its `finally`, so the caller has
    // to raise it. Without it isEnriching() reports false mid-pass and the
    // lyrics sheet stops waiting and flashes "not available" too early.
    _enrichingIds.add(song.id);
    final future = _enrichOneSong(
      song,
      previewFallbackOnly: previewFallbackOnly,
      fastImport: fastImport,
    ).whenComplete(() => _pendingEnrichment.remove(key));
    _pendingEnrichment[key] = future;
    return future;
  }

  /// Playback-failure recovery for a track's audio source.
  Future<void> _ensureRecoverableAudio(
    Song song, {
    String? failedUrl,
    String? failedVideoId,
  }) async {
    final isImported = _isDownloadableCatalogId(song.id);
    if (!isImported) {
      // Local/bundled tracks have no full-track catalog to search.
      try {
        await _ensureEnrichment(
          song,
          previewFallbackOnly: true,
        ).timeout(const Duration(seconds: 8));
      } catch (_) {}
      return;
    }

    final fullPass = _ensureEnrichment(song, fastImport: true);
    try {
      await fullPass.timeout(const Duration(seconds: 12));
    } catch (_) {
      try {
        await fullPass.timeout(const Duration(seconds: 8));
      } catch (_) {}
    }
    if (_disposed) return;
    final isFailedUrl =
        failedUrl != null && failedUrl.isNotEmpty && song.audioUrl == failedUrl;
    final isGvExpired =
        song.audioUrl.contains('googlevideo.com') &&
        _isGoogleVideoExpired(song.audioUrl);
    if (song.hasAudio &&
        !song.isPreview &&
        !isGvExpired &&
        !song.audioUrl.toLowerCase().contains('.m3u8') &&
        !isFailedUrl) {
      return;
    }
    // DO NOT downgrade to 30s preview clip from iTunes/Deezer!
    // Try one more clean full track resolution with direct YouTube stream lookup ONLY
    // if videoId is known and is NOT the failed video ID that triggered recovery!
    if (song.youtubeVideoId.isNotEmpty &&
        song.youtubeVideoId != failedVideoId) {
      try {
        final ytStream = await _enrichment.fetchYouTubeStreamById(
          song.youtubeVideoId,
        );
        if (ytStream.hasAudio && ytStream.previewUrl != failedUrl) {
          _applyEnrichment(song, ytStream);
          notifyListeners();
          return;
        }
      } catch (_) {}
    }
  }

  static bool _isDownloadableCatalogId(String id) {
    return id.startsWith('spotify-') ||
        id.startsWith('itunes-') ||
        id.startsWith('radio-') ||
        id.startsWith('artist-') ||
        id.startsWith('dyn-') ||
        id.startsWith('discovery-') ||
        id.startsWith('dm-') ||
        id.startsWith('recent-');
  }

  /// Catalog tracks are resolved strictly via YouTube. Local/bundled tracks
  /// keep their own audio and must never be searched on YouTube.
  static bool _isYouTubeCatalogSong(Song song) {
    return _isDownloadableCatalogId(song.id);
  }

  Future<void> _enrichOneSong(
    Song song, {
    bool previewFallbackOnly = false,
    bool fastImport = false,
  }) async {
    if (!previewFallbackOnly) {
      final isStuck =
          !song.hasAudio ||
          song.isPreview ||
          (song.audioUrl.contains('googlevideo.com') &&
              _isGoogleVideoExpired(song.audioUrl)) ||
          _offlineFallbackIds.contains(song.id);
      if (isStuck) {
        _fullTrackAttemptCount[song.id] =
            (_fullTrackAttemptCount[song.id] ?? 0) + 1;
      }
    }
    song.isEnrichingLyrics = true;
    final enrichStart = DateTime.now();
    try {
      // Fast check: if a valid offline full-track audio file already exists on device,
      // attach it immediately with 0ms network latency.
      final cached = await _findCachedAudioFile(song.id);
      if (cached != null && cached.existsSync()) {
        if (await _isCompleteOfflineFile(song.id, cached)) {
          _downloadedSongIds.add(song.id);
          final changed = _applyEnrichment(
            song,
            TrackEnrichment(previewUrl: cached.path, isFullTrack: true),
          );
          song.isEnrichingLyrics = false;
          if (changed) notifyListeners();
          return;
        } else {
          // Purge 30s previews and truncated files so the full track can
          // resolve from the network.
          try {
            cached.deleteSync();
          } catch (_) {}
          _invalidateOfflineLookup(song.id);
        }
      }

      // If we already have a known youtubeVideoId, resolve its live stream immediately:
      if (song.youtubeVideoId.isNotEmpty) {
        try {
          final ytEnrichment = await _enrichment
              .fetchYouTubeStreamById(song.youtubeVideoId)
              .timeout(const Duration(seconds: 8));
          if (ytEnrichment.hasAudio) {
            final changed = _applyEnrichment(song, ytEnrichment);
            song.isEnrichingLyrics = false;
            if (changed) notifyListeners();
            return;
          }
        } catch (_) {}
      }

      // Check if this song was already located as a full track in the local database:
      final savedDbSong = await LocalDatabase.instance.getImportedSong(song.id);
      if (savedDbSong != null) {
        final dbYtId = (savedDbSong['youtube_video_id'] as String? ?? '')
            .trim();
        if (dbYtId.isNotEmpty && song.youtubeVideoId.isEmpty) {
          song.youtubeVideoId = dbYtId;
          try {
            final ytEnrichment = await _enrichment
                .fetchYouTubeStreamById(dbYtId)
                .timeout(const Duration(seconds: 8));
            if (ytEnrichment.hasAudio) {
              final changed = _applyEnrichment(song, ytEnrichment);
              song.isEnrichingLyrics = false;
              if (changed) notifyListeners();
              return;
            }
          } catch (_) {}
        }

        final dbAudio = (savedDbSong['audio_url'] as String? ?? '').trim();
        final dbPreview = (savedDbSong['is_preview'] as int? ?? 0) == 1;
        if (!dbPreview &&
            dbAudio.isNotEmpty &&
            !dbAudio.contains('apple.com') &&
            !dbAudio.contains('itunes') &&
            !dbAudio.contains('deezer') &&
            !dbAudio.contains('dzcdn.net')) {
          final dbLyrics = (savedDbSong['lyrics'] as List<dynamic>? ?? [])
              .map((e) => e.toString())
              .toList();
          final changed = _applyEnrichment(
            song,
            TrackEnrichment(
              previewUrl: dbAudio,
              isFullTrack: true,
              lyrics: dbLyrics,
            ),
          );
          song.isEnrichingLyrics = false;
          if (changed) notifyListeners();
          return;
        }
      }

      // Every catalog track is resolved strictly via YouTube. Discovery and
      // imported tracks previously fell through Saavn → SoundCloud → web →
      // YouTube, which took 30-45s per song. Local/bundled tracks keep their
      // own audio and never reach this path.
      final enrichment = await _enrichment.enrichTrack(
        title: song.title,
        artist: song.artist,
        album: song.album,
        duration: song.duration,
        previewFallbackOnly: false,
        allowPreviewFallback: false,
        prioritizeYouTube: true,
        fastImport: fastImport,
        youtubeOnly: _isYouTubeCatalogSong(song),
      );
      _logDiag(
        'enrichment done in ${DateTime.now().difference(enrichStart).inMilliseconds}ms '
        'hasAudio=${enrichment.hasAudio} fullTrack=${enrichment.isFullTrack} '
        'host=${_hostOf(enrichment.previewUrl)} previewOnly=$previewFallbackOnly',
        song: song,
      );
      if (enrichment.hasAudio || enrichment.hasLyrics) {
        _enrichedIds.add(song.id);
      }
      final changed = _applyEnrichment(song, enrichment);
      song.isEnrichingLyrics = false;
      if (changed) notifyListeners();
    } catch (_) {
      _logDiag(
        'enrichment FAILED after ${DateTime.now().difference(enrichStart).inMilliseconds}ms',
        song: song,
      );
      song.isEnrichingLyrics = false;
    } finally {
      _enrichingIds.remove(song.id);
    }
  }

  /// Shared audio/lyrics attach used by import enrichment and the lyrics
  /// sheet retry. Returns true when the song actually changed.
  ///
  /// Attaches audio when silent, upgrades a 30s preview when a full-length
  /// stream resolves, refreshes duration from the real stream, and fills
  /// lyrics once. Mid-playback upgrades hot-swap and resume in place.
  bool _applyEnrichment(Song song, TrackEnrichment enrichment) {
    var changed = false;

    final isImported = _isDownloadableCatalogId(song.id);
    final isFallbackAudio = _offlineFallbackIds.contains(song.id);
    final isM3u8 =
        enrichment.previewUrl?.toLowerCase().contains('.m3u8') ?? false;
    final shouldAttachAudio =
        enrichment.hasAudio &&
        !isM3u8 &&
        (!isImported || enrichment.isFullTrack) &&
        (!song.hasAudio ||
            song.audioUrl.contains('googlevideo.com') ||
            song.audioUrl.toLowerCase().contains('.m3u8') ||
            isFallbackAudio ||
            song.isPreview ||
            ((song.isYouTubeAudio ||
                    song.audioUrl.contains('googlevideo.com')) &&
                enrichment.isFullTrack));
    if (shouldAttachAudio) {
      final resumePosition = song.id == currentSong?.id
          ? _currentPosition
          : Duration.zero;
      song.audioUrl = enrichment.previewUrl!;
      song.isPreview = !enrichment.isFullTrack;
      song.isYouTubeAudio = enrichment.isFullTrack && enrichment.isYouTube;
      if (enrichment.youtubeVideoId != null &&
          enrichment.youtubeVideoId!.isNotEmpty) {
        song.youtubeVideoId = enrichment.youtubeVideoId!;
      }
      // Prefer the resolved stream length (full track or real 30s clip)
      // so list rows and the slider agree with what actually plays.
      if (enrichment.isFullTrack &&
          enrichment.previewDuration != null &&
          enrichment.previewDuration! > Duration.zero) {
        song.duration = enrichment.previewDuration!;
      }
      if (enrichment.artworkUrl != null && enrichment.artworkUrl!.isNotEmpty) {
        song.imageUrl = enrichment.artworkUrl!;
        for (final p in _playlists) {
          if (p.songIds.contains(song.id) && p.imageUrl.isEmpty) {
            p.imageUrl = song.imageUrl;
            unawaited(
              LocalDatabase.instance.updateImportedPlaylistImageUrl(
                p.id,
                p.imageUrl,
              ),
            );
          }
        }
      }
      changed = true;
      // Real audio replaces the offline fallback — clear the placeholder flag
      // so future logic treats this as genuine audio, not a fallback.
      _offlineFallbackIds.remove(song.id);
      if (enrichment.isFullTrack) {
        // Full-length audio landed: the failure history (and its backoff)
        // no longer applies to this track.
        _fullUpgradeAttemptedAt.remove(song.id);
        _fullTrackAttemptCount.remove(song.id);
      }
      _unavailableIds.remove(song.id);
      // Hot-swap mid-playback or trigger newly resolved audio
      if (song.id == currentSong?.id) {
        _isPlaying = true;
        _unmuteOnPlay();
        _lastPositionUpdate = DateTime.now();
        _startTimer();
        if (!_isPlayingAudioInProgress) {
          // ignore: discarded_futures
          _playCurrentSongAudio().then((_) {
            if (resumePosition > Duration.zero) {
              seekTo(resumePosition);
            }
          });
        } else {
          // A play attempt is in-flight. Queue a deferred reload so the
          // `finally` block picks it up once the in-flight attempt finishes.
          _pendingHotSwapReload = true;
          _pendingHotSwapResumePosition = resumePosition;
          _logDiag(
            'hot-swap deferred — play in progress, queued reload',
            song: song,
          );
        }
      }
    }

    final hasFakeLyrics = _offlineFakeLyricsIds.contains(song.id);
    final hasSyncedLyrics = song.lyrics.any(
      (l) => Song.parseLyricTimestamp(l) != null,
    );
    final enrichmentHasSynced = enrichment.lyrics.any(
      (l) => Song.parseLyricTimestamp(l) != null,
    );
    if (enrichment.hasLyrics &&
        (song.lyrics.isEmpty ||
            hasFakeLyrics ||
            !hasSyncedLyrics ||
            enrichmentHasSynced)) {
      song.lyrics = enrichment.lyrics;
      _offlineFakeLyricsIds.remove(song.id);
      changed = true;
    }

    if (changed &&
        (_isDownloadableCatalogId(song.id) ||
            song.id.startsWith('discovery-'))) {
      try {
        final dbAudioUrl =
            (song.audioUrl.contains('googlevideo.com') ||
                song.audioUrl.toLowerCase().contains('.m3u8'))
            ? ''
            : song.audioUrl;
        unawaited(
          LocalDatabase.instance
              .updateImportedSong(
                id: song.id,
                audioUrl: dbAudioUrl,
                isPreview: song.isPreview,
                isYouTubeAudio: song.isYouTubeAudio,
                youtubeVideoId: song.youtubeVideoId.isNotEmpty
                    ? song.youtubeVideoId
                    : null,
                durationMs: song.duration.inMilliseconds,
                imageUrl: song.imageUrl,
                lyrics: song.lyrics,
              )
              .catchError((e) {
                debugPrint(
                  '[MusicPlayerController] Error updating song in DB: $e',
                );
              }),
        );
      } catch (_) {}
    }

    if (changed) {
      _locatingStatusVersion++;
    }
    return changed;
  }

  static const int _maxConcurrentDownloadWorkers = 3;
  int _activeDownloadWorkers = 0;
  final List<_DownloadTask> _downloadQueue = [];
  final Map<String, List<Completer<bool>>> _inFlightCompleters = {};
  final Set<String> _cachingIds = {};
  final Set<String> _downloadedSongIds = {};

  /// Synchronously checks if a song is downloaded and available offline.
  bool isSongDownloaded(String songId) {
    if (_downloadedSongIds.contains(songId)) {
      if (findCachedAudioFileSync(songId) != null) return true;
      // The file was deleted outside the app (e.g. cache clear); drop the
      // stale in-memory flag so the download button becomes actionable again.
      _downloadedSongIds.remove(songId);
    }
    final memo = _audioLookupMemo[songId];
    if (memo != null && memo.existsSync() && memo.lengthSync() > 1024) {
      _downloadedSongIds.add(songId);
      return true;
    }
    final song = songById(songId);
    if (song != null) {
      if ((song.audioUrl.contains('offline_audio') ||
              song.audioUrl.contains('pulse_music_offline')) &&
          !song.audioUrl.startsWith('assets/')) {
        try {
          final file = File(song.audioUrl);
          if (file.existsSync() && file.lengthSync() > 1024) {
            _downloadedSongIds.add(songId);
            return true;
          }
        } catch (_) {}
      }
    }
    return false;
  }

  /// Synchronously checks if a song is currently downloading or waiting in the 3-worker queue.
  bool isSongDownloading(String songId) =>
      _cachingIds.contains(songId) ||
      _downloadQueue.any((t) => t.song.id == songId);

  /// Synchronously checks if all songs in a playlist are downloaded.
  bool isPlaylistFullyDownloaded(List<Song> songs) {
    if (songs.isEmpty) return false;
    return songs.every((s) => isSongDownloaded(s.id));
  }

  /// Synchronously checks if any song in a playlist is currently downloading.
  bool isPlaylistDownloading(List<Song> songs) {
    return songs.any((s) => isSongDownloading(s.id));
  }

  Future<Directory> _getPrimaryOfflineDirectory() async {
    Directory? primary;
    try {
      final supp = await getApplicationSupportDirectory();
      primary = Directory(p.join(supp.path, 'offline_audio'));
    } catch (_) {}
    if (primary == null) {
      try {
        final docs = await getApplicationDocumentsDirectory();
        primary = Directory(p.join(docs.path, 'offline_audio'));
      } catch (_) {}
    }
    if (primary == null) {
      try {
        final temp = await getTemporaryDirectory();
        primary = Directory(p.join(temp.path, 'offline_audio'));
      } catch (_) {}
    }
    primary ??= Directory(
      p.join(Directory.systemTemp.path, 'pulse_music_offline'),
    );
    if (!await primary.exists()) {
      await primary.create(recursive: true);
    }
    return primary;
  }

  /// Offline cache directories, resolved once per session.
  ///
  /// Both lookups below ran 3 `path_provider` plugin calls *each*, and the
  /// player called them 2-3 times for the same song on every play. Memoizing
  /// the dirs removes that repeated cross-isolate chatter from the hot path.
  List<Directory>? _offlineDirCache;
  static List<Directory>? _staticOfflineDirs;
  static final Map<String, File?> _staticAudioLookupMemo = {};

  static final String _systemTempOfflineDir = p.join(
    Directory.systemTemp.path,
    'pulse_music_offline',
  );

  static final List<String> _knownFallbackDirs = [
    if (!kIsWeb && Platform.isAndroid) ...[
      '/data/user/0/com.example.music/files/offline_audio',
      '/data/user/0/com.example.music/files',
      '/data/user/0/com.example.music/app_flutter/offline_audio',
      '/data/user/0/com.example.music/app_flutter',
      '/data/data/com.example.music/files/offline_audio',
      '/data/data/com.example.music/files',
    ],
    'offline_audio',
    _systemTempOfflineDir,
  ];

  static File? findCachedAudioFileSync(String songId) {
    final memo = _staticAudioLookupMemo[songId];
    if (memo != null && memo.existsSync() && memo.lengthSync() > 1024) {
      return memo;
    }
    // A previous lookup already determined there is no cached file. Trust it
    // until a download/extraction invalidates the memo; rescanning every
    // directory for every row made large playlists crawl.
    if (_staticAudioLookupMemo.containsKey(songId)) {
      return null;
    }
    final dirs = <Directory>[
      ...?_staticOfflineDirs,
      for (final pth in _knownFallbackDirs) Directory(pth),
    ];
    for (final dir in dirs) {
      try {
        if (!dir.existsSync()) continue;
        for (final ext in _audioExtensions) {
          final f = File(p.join(dir.path, '$songId$ext'));
          if (f.existsSync() && f.lengthSync() > 1024) {
            _staticAudioLookupMemo[songId] = f;
            return f;
          }
        }
      } catch (_) {}
    }
    return null;
  }

  Future<List<Directory>> _offlineCandidateDirs() async {
    final cached = _offlineDirCache;
    if (cached != null) return cached;
    final dirs = <Directory>[];
    if (!kIsWeb && Platform.isAndroid) {
      dirs.add(Directory('/data/user/0/com.example.music/files/offline_audio'));
      dirs.add(Directory('/data/user/0/com.example.music/files'));
      dirs.add(
        Directory('/data/user/0/com.example.music/app_flutter/offline_audio'),
      );
      dirs.add(Directory('/data/user/0/com.example.music/app_flutter'));
      dirs.add(Directory('/data/data/com.example.music/files/offline_audio'));
      dirs.add(Directory('/data/data/com.example.music/files'));
    }
    try {
      final supp = await getApplicationSupportDirectory();
      dirs.add(Directory(p.join(supp.path, 'offline_audio')));
      dirs.add(supp);
    } catch (_) {}
    try {
      final docs = await getApplicationDocumentsDirectory();
      dirs.add(Directory(p.join(docs.path, 'offline_audio')));
      dirs.add(docs);
    } catch (_) {}
    try {
      final temp = await getTemporaryDirectory();
      dirs.add(Directory(p.join(temp.path, 'offline_audio')));
      dirs.add(temp);
    } catch (_) {}
    dirs.add(Directory(_systemTempOfflineDir));
    _offlineDirCache = dirs;
    _staticOfflineDirs = dirs;
    // Any lookup made before the candidate directories were known could not
    // see real cache files. Forget those premature misses now that the search
    // paths are final.
    _staticAudioLookupMemo.clear();
    return dirs;
  }

  final Map<String, File?> _audioLookupMemo = {};
  final Map<String, File?> _artworkLookupMemo = {};

  /// Drop memoized cache lookups for a song after we write a file for it.
  void _invalidateOfflineLookup(String songId, {bool artwork = false}) {
    if (artwork) {
      _artworkLookupMemo.remove(songId);
    } else {
      _audioLookupMemo.remove(songId);
      _staticAudioLookupMemo.remove(songId);
    }
  }

  /// True when [file] is a complete offline download rather than a 30-second
  /// preview or a truncated stream. Files at/above the legacy preview cutoff
  /// are always trusted; smaller files are trusted only when the database
  /// records this exact path as a non-preview download.
  Future<bool> _isCompleteOfflineFile(String songId, File file) async {
    try {
      final length = await file.length();
      if (length < _minimumAudioFileBytes) return false;
      if (length >= _previewFileSizeThreshold) return true;
      final row = await LocalDatabase.instance.getImportedSong(songId);
      if (row == null) return false;
      final isPreview = (row['is_preview'] as int? ?? 0) == 1;
      if (isPreview) return false;
      final audioUrl = (row['audio_url'] as String? ?? '').trim();
      if (audioUrl.isEmpty) return true;
      return p.equals(audioUrl, file.path) ||
          p.basename(audioUrl).toLowerCase() ==
              p.basename(file.path).toLowerCase();
    } catch (_) {
      return false;
    }
  }

  /// A fresh network resolve is needed when the stored URL is empty, expired,
  /// an HLS playlist, a local path, or a known preview URL.
  bool _needsFreshDownloadUrl(Song song, String url) {
    if (url.isEmpty) return true;
    final lower = url.toLowerCase();
    if (lower.contains('.m3u8')) return true;
    if (_isGoogleVideoExpired(url)) return true;
    if (!url.startsWith('http://') && !url.startsWith('https://')) return true;
    // A preview is never a permanent download, even when it is a live
    // googlevideo URL: try to resolve the full track first.
    if (song.isPreview) return true;
    return false;
  }

  Future<File?> _findCachedAudioFile(String songId) async {
    final memo = _audioLookupMemo[songId];
    if (memo != null || _audioLookupMemo.containsKey(songId)) {
      return memo;
    }

    final dirs = await _offlineCandidateDirs();
    for (final dir in dirs) {
      try {
        if (!await dir.exists()) continue;
        for (final ext in _audioExtensions) {
          final f = File(p.join(dir.path, '$songId$ext'));
          if (await f.exists()) {
            final len = await f.length();
            if (len > 1024) {
              _audioLookupMemo[songId] = f;
              _staticAudioLookupMemo[songId] = f;
              return f;
            }
          }
        }
      } catch (_) {}
    }
    _audioLookupMemo[songId] = null;
    _staticAudioLookupMemo[songId] = null;
    return null;
  }

  Future<File?> _findCachedArtworkFile(String songId) async {
    final memo = _artworkLookupMemo[songId];
    if (memo != null || _artworkLookupMemo.containsKey(songId)) {
      return memo;
    }

    final dirs = await _offlineCandidateDirs();
    for (final dir in dirs) {
      try {
        if (!await dir.exists()) continue;
        for (final ext in const ['.jpg', '.jpeg', '.png', '.webp']) {
          final f = File(p.join(dir.path, '$songId$ext'));
          if (await f.exists() && await f.length() > 100) {
            _artworkLookupMemo[songId] = f;
            return f;
          }
        }
      } catch (_) {}
    }
    _artworkLookupMemo[songId] = null;
    return null;
  }

  Future<MediaItem> _createSafeMediaItem(Song song) async {
    Uri? safeArtUri;
    if (song.imageUrl.isNotEmpty) {
      if (song.imageUrl.startsWith('file://') ||
          song.imageUrl.startsWith('asset:///')) {
        safeArtUri = Uri.tryParse(song.imageUrl);
      } else if (File(song.imageUrl).existsSync()) {
        safeArtUri = Uri.file(song.imageUrl);
      } else {
        final cachedArt = await _findCachedArtworkFile(song.id);
        if (cachedArt != null && cachedArt.existsSync()) {
          safeArtUri = Uri.file(cachedArt.path);
        }
      }
    }

    final duration = song.duration > Duration.zero
        ? song.duration
        : const Duration(minutes: 3);

    return MediaItem(
      id: song.id,
      album: song.album.isNotEmpty ? song.album : 'Pulse Studio',
      title: song.title,
      artist: song.artist,
      artUri: safeArtUri,
      duration: duration,
    );
  }

  static String _cleanAssetUri(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return '';
    final clean = trimmed
        .replaceFirst(RegExp(r'^asset:[/\\]*'), '')
        .replaceFirst(RegExp(r'^[/\\]+'), '');
    if (clean.isEmpty) return '';
    return clean.startsWith('assets/') ? clean : 'assets/audio/$clean';
  }

  static const Map<String, ({String asset, String artist})> _bundledAssets = {
    'lips of an angel': (
      asset: 'assets/audio/lips-of-an-angel.mp3',
      artist: 'hinder',
    ),
    'perfect': (asset: 'assets/audio/perfect.m4a', artist: 'ed sheeran'),
    'shape of you': (
      asset: 'assets/audio/shape-of-you.m4a',
      artist: 'ed sheeran',
    ),
    'bad habits': (asset: 'assets/audio/bad-habits.m4a', artist: 'ed sheeran'),
    'thinking out loud': (
      asset: 'assets/audio/thinking-out-loud.m4a',
      artist: 'ed sheeran',
    ),
    'blank space': (
      asset: 'assets/audio/blank-space.m4a',
      artist: 'taylor swift',
    ),
    'cruel summer': (
      asset: 'assets/audio/cruel-summer.m4a',
      artist: 'taylor swift',
    ),
    'just the way you are': (
      asset: 'assets/audio/just-the-way-you-are.m4a',
      artist: 'bruno mars',
    ),
    'uptown funk': (
      asset: 'assets/audio/uptown-funk.m4a',
      artist: 'mark ronson',
    ),
    'lose yourself': (
      asset: 'assets/audio/lose-yourself.m4a',
      artist: 'eminem',
    ),
    'mockingbird': (asset: 'assets/audio/mockingbird.m4a', artist: 'eminem'),
    'the real slim shady': (
      asset: 'assets/audio/the-real-slim-shady.m4a',
      artist: 'eminem',
    ),
    'without me': (asset: 'assets/audio/without-me.m4a', artist: 'eminem'),
  };

  String _getOfflineAssetFallbackForFields(
    String title,
    String artist,
    String songId,
  ) {
    // Imported songs must not default to bundled folder assets — they use local audio cache
    if (songId.startsWith('spotify-') || songId.startsWith('itunes-')) {
      return '';
    }
    // A Tagalog/English/acoustic version is a different recording: never
    // substitute the bundled original for it.
    if (TrackEnrichmentService.versionTags(title).isNotEmpty) return '';
    final cleanT = _cleanSongTitle(title).toLowerCase();
    final cleanA = _normalizeKey(artist);

    // 1. Direct title AND artist match against bundled assets (never substitute a different song/artist)
    for (final entry in _bundledAssets.entries) {
      final key = entry.key;
      final expectedArtist = entry.value.artist;
      final titleMatches =
          cleanT == key ||
          (cleanT.isNotEmpty &&
              key.isNotEmpty &&
              (cleanT.contains(key) || key.contains(cleanT)));
      if (titleMatches) {
        // Enforce strict artist match so e.g. Simple Plan "Perfect" never matches Ed Sheeran "Perfect"
        if (cleanA.isNotEmpty &&
            (cleanA.contains(expectedArtist) ||
                expectedArtist.contains(cleanA))) {
          return entry.value.asset;
        }
      }
    }

    // 2. Exact title AND artist match against bundled sample songs
    for (final sample in SampleMusicData.sampleSongs) {
      final sampleT = _cleanSongTitle(sample.title).toLowerCase();
      final sampleA = _normalizeKey(sample.artist);
      final titleMatches =
          cleanT.isNotEmpty &&
          (cleanT == sampleT ||
              cleanT.contains(sampleT) ||
              sampleT.contains(cleanT));
      if (titleMatches && cleanA.isNotEmpty && sampleA.isNotEmpty) {
        if (cleanA.contains(sampleA) || sampleA.contains(cleanA)) {
          if (sample.audioUrl.isNotEmpty) return sample.audioUrl;
        }
      }
    }

    return '';
  }

  String _getOfflineAssetFallback(Song song) {
    return _getOfflineAssetFallbackForFields(song.title, song.artist, song.id);
  }

  Future<String> _extractAssetToFile(String assetPath) async {
    final cleanPath = assetPath
        .replaceFirst(RegExp(r'^asset:[/\\]*'), '')
        .replaceFirst(RegExp(r'^[/\\]+'), '');
    try {
      final offlineDir = await _getPrimaryOfflineDirectory();
      final sanitizedFileName = cleanPath.replaceAll(RegExp(r'[/\\]'), '_');
      final file = File(p.join(offlineDir.path, sanitizedFileName));
      if (!await file.exists() || await file.length() < 1000) {
        final data = await rootBundle.load(cleanPath);
        await file.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
      }
      return file.path;
    } catch (e) {
      debugPrint(
        '[MusicPlayerController] Primary asset extraction failed for $cleanPath: $e',
      );
      try {
        final tempDir = await getTemporaryDirectory();
        final sanitizedFileName = cleanPath.replaceAll(RegExp(r'[/\\]'), '_');
        final file = File(p.join(tempDir.path, sanitizedFileName));
        if (!await file.exists() || await file.length() < 1000) {
          final data = await rootBundle.load(cleanPath);
          await file.writeAsBytes(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            flush: true,
          );
        }
        return file.path;
      } catch (e2) {
        debugPrint('[MusicPlayerController] Temp asset extraction failed: $e2');
        return cleanPath;
      }
    }
  }

  Future<void> _preExtractBundledAssets() async {
    try {
      for (final sample in SampleMusicData.sampleSongs) {
        if (sample.audioUrl.isNotEmpty &&
            sample.audioUrl.startsWith('assets/')) {
          await _extractAssetToFile(sample.audioUrl);
        }
      }
    } catch (e) {
      debugPrint('[MusicPlayerController] Pre-extraction error: $e');
    }
  }

  static bool _isGoogleVideoExpired(String url) {
    if (!url.contains('googlevideo.com')) return false;
    final uri = Uri.tryParse(url);
    if (uri == null) return true;
    final expireStr = uri.queryParameters['expire'];
    if (expireStr == null) return false;
    final expireEpoch = int.tryParse(expireStr);
    if (expireEpoch == null) return false;
    final expireTime = DateTime.fromMillisecondsSinceEpoch(expireEpoch * 1000);
    return DateTime.now().isAfter(
      expireTime.subtract(const Duration(minutes: 5)),
    );
  }

  DateTime? _lastOnlineCheck;
  bool _cachedOnline = true;
  Future<bool>? _onlineProbeInFlight;

  /// Reachability probe for the playback path.
  ///
  /// Reachability verdict with a *short* negative cache.
  ///
  /// A success is trusted for 20s. A failure is only trusted for 2s: the old
  /// code cached `false` for a full 20s after a single 1.2s DNS timeout, so
  /// one slow resolver made the player believe it was offline for the entire
  /// recovery window. Every online fallback (fresh enrichment, stream
  /// re-resolve, `_handleAudioLoadFailure`) was skipped because of it, which
  /// is what left the track muted with a frozen progress slider and a frozen
  /// lyrics tracker. Concurrent callers still share a single in-flight probe.
  Future<bool> _isDeviceOnline() {
    final last = _lastOnlineCheck;
    if (last != null) {
      final ttl = _cachedOnline
          ? const Duration(seconds: 20)
          : const Duration(seconds: 2);
      if (DateTime.now().difference(last) < ttl) {
        return Future<bool>.value(_cachedOnline);
      }
    }
    final inFlight = _onlineProbeInFlight;
    if (inFlight != null) return inFlight;

    final probe = _probeReachability();
    _onlineProbeInFlight = probe;
    return probe.whenComplete(() => _onlineProbeInFlight = null);
  }

  /// Probes DNS *and* plain HTTP in parallel and reports online as soon as
  /// either answers.
  ///
  /// A DNS-only check false-negatives on mobile networks where the resolver
  /// is slow or `dns.google` is unreachable while normal HTTP works fine, and
  /// that false negative used to be cached long enough to disable playback
  /// recovery. Only when both probes fail is the device reported offline,
  /// bounded to roughly 2.5s.
  Future<bool> _probeReachability() async {
    final now = DateTime.now();
    var ok = false;
    try {
      ok = await _firstSuccess(<Future<bool>>[
        Future<bool>(() async {
          final res = await InternetAddress.lookup(
            'dns.google',
          ).timeout(const Duration(seconds: 2));
          return res.isNotEmpty && res.first.rawAddress.isNotEmpty;
        }),
        Future<bool>(() async {
          final res = await http
              .get(
                Uri.parse('http://connectivitycheck.gstatic.com/generate_204'),
                headers: {
                  'User-Agent': TrackEnrichmentService.browserUserAgent,
                },
              )
              .timeout(const Duration(milliseconds: 2500));
          // Any HTTP answer (even a 4xx or redirect) proves the network is up.
          return res.statusCode > 0 && res.statusCode < 500;
        }),
        // Hosts this app really needs. Some carriers and Wi-Fi networks block
        // Google's check hosts while Spotify/iTunes work, so a Google-only
        // probe reported "offline" on a perfectly usable connection.
        Future<bool>(() async {
          final res = await http
              .head(
                Uri.parse('https://itunes.apple.com/'),
                headers: {
                  'User-Agent': TrackEnrichmentService.browserUserAgent,
                },
              )
              .timeout(const Duration(milliseconds: 2500));
          return res.statusCode > 0 && res.statusCode < 500;
        }),
        Future<bool>(() async {
          final res = await http
              .head(
                Uri.parse('https://open.spotify.com/'),
                headers: {
                  'User-Agent': TrackEnrichmentService.browserUserAgent,
                },
              )
              .timeout(const Duration(milliseconds: 2500));
          return res.statusCode > 0 && res.statusCode < 500;
        }),
      ]);
    } catch (_) {
      ok = false;
    }
    _cachedOnline = ok;
    _lastOnlineCheck = now;
    return ok;
  }

  /// Completes with `true` as soon as any probe succeeds, and with `false`
  /// only after every probe has failed.
  static Future<bool> _firstSuccess(List<Future<bool>> probes) {
    var pending = probes.length;
    final completer = Completer<bool>();
    void settle(bool value) {
      if (value) {
        if (!completer.isCompleted) completer.complete(true);
      } else {
        pending -= 1;
        if (pending == 0 && !completer.isCompleted) completer.complete(false);
      }
    }

    for (final probe in probes) {
      probe.then(settle, onError: (_) => settle(false));
    }
    return completer.future;
  }

  /// Drops the generated "Playing in Offline Mode" placeholder lines that
  /// older builds saved to the database. Kept, they looked like real synced
  /// lyrics, so the lyrics sheet never looked the real ones up and the
  /// highlight sat on one line for up to 25 seconds at a time.
  static List<String> _withoutPlaceholderLyrics(List<String> lines) {
    if (lines.any((l) => l.contains('Playing in Offline Mode'))) {
      return <String>[];
    }
    return lines;
  }

  List<String> _ensureOfflineLyrics(Song song) {
    // Real lyrics (or already-generated fake) stay — but never block a future
    // real lookup: fake lines are tracked so enrichment can overwrite them.
    if (song.lyrics.isNotEmpty && !_offlineFakeLyricsIds.contains(song.id)) {
      return song.lyrics;
    }
    if (song.lyrics.isNotEmpty && _offlineFakeLyricsIds.contains(song.id)) {
      return song.lyrics;
    }
    // Check if matched bundled track has lyrics (genuine, not fake).
    final cleanT = _cleanSongTitle(song.title).toLowerCase();
    for (final sample in SampleMusicData.sampleSongs) {
      final sampleT = _cleanSongTitle(sample.title).toLowerCase();
      if (cleanT.isNotEmpty &&
          (cleanT == sampleT ||
              cleanT.contains(sampleT) ||
              sampleT.contains(cleanT))) {
        // Same title is not enough: another artist's "Perfect" must not get
        // Ed Sheeran's lyrics.
        final a = _normalizeKey(song.artist);
        final sa = _normalizeKey(sample.artist);
        final sameArtist =
            a.isNotEmpty && sa.isNotEmpty && (a.contains(sa) || sa.contains(a));
        if (sample.lyrics.isNotEmpty && sameArtist) {
          song.lyrics = List<String>.from(sample.lyrics);
          _offlineFakeLyricsIds.remove(song.id);
          return song.lyrics;
        }
      }
    }
    // Imported tracks never get invented placeholder lyrics: an empty list
    // makes the lyrics sheet look up the real ones instead of showing a
    // fixed fake timeline, UNLESS this imported track matches a bundled offline asset.
    if ((song.id.startsWith('spotify-') || song.id.startsWith('itunes-')) &&
        !_offlineFallbackIds.contains(song.id) &&
        !song.audioUrl.startsWith('assets/')) {
      return song.lyrics;
    }
    // Generate rhythmic, timestamped lyrics for offline tracking
    final durationSeconds = song.duration.inSeconds > 0
        ? song.duration.inSeconds
        : 180;
    final lines = <String>[
      '[00:00.00] ♫ ${song.title} ♫',
      '[00:05.00] ${song.artist}',
      if (song.album.isNotEmpty) '[00:10.00] ${song.album}',
      '[00:16.00] ♫ Playing in Offline Mode ♫',
      '[00:26.00] ♫ High-fidelity audio playback active ♫',
      '[00:40.00] (Instrumental Groove & Rhythm)',
      '[01:00.00] ♫ Lyrics tracker moving in real-time ♫',
      '[01:25.00] ♫ Enjoying music without internet connection ♫',
      '[01:50.00] (Instrumental Melody)',
      '[02:15.00] ♫ Seamless offline listening experience ♫',
      if (durationSeconds > 150) '[02:35.00] (Dynamic Bridge)',
      if (durationSeconds > 180) '[03:00.00] ♫ Pulse Studio ♫',
    ];
    song.lyrics = lines;
    _offlineFakeLyricsIds.add(song.id);
    return lines;
  }

  @visibleForTesting
  String getOfflineAssetFallbackForTesting(Song song) =>
      _getOfflineAssetFallback(song);

  @visibleForTesting
  List<String> ensureOfflineLyricsForTesting(Song song) =>
      _ensureOfflineLyrics(song);

  /// Simulates the audio player finishing the current song. Used by tests to
  /// verify that duplicate completion signals advance exactly one track.
  @visibleForTesting
  void handleSongCompleteForTesting() => _onSongComplete();

  Future<void> _cacheAudioOffline(Song song) async {
    // Automatic caching is playback-only. Imports and background enrichment
    // never write audio unless the user explicitly downloads it.
    if (!_autoCachePlayedSongs) return;
    if (song.isPreview) return;

    // 1. Check if a valid local offline file already exists
    final cached = await _findCachedAudioFile(song.id);
    if (cached != null) {
      if (!await _isCompleteOfflineFile(song.id, cached)) {
        try {
          await cached.delete();
        } catch (_) {}
        _invalidateOfflineLookup(song.id);
      } else {
        _downloadedSongIds.add(song.id);
        if (song.audioUrl != cached.path) {
          song.audioUrl = cached.path;
          song.isPreview = false;
          song.isYouTubeAudio = false;
          _syncSongPathToQueueAndDb(song);
          notifyListeners();
        }
        return;
      }
    }

    // Don't download over mobile data unless the user allowed it.
    if (!await _mayDownloadNow()) {
      _logDiag('offline cache skipped: on mobile data', song: song);
      return;
    }

    if (_cachingIds.contains(song.id)) return;
    _cachingIds.add(song.id);

    try {
      final offlineDir = await _getPrimaryOfflineDirectory();
      String urlToDownload = song.audioUrl;

      // If the URL is empty or expired, resolve fresh full or preview stream
      if (urlToDownload.isEmpty ||
          urlToDownload.toLowerCase().contains('.m3u8') ||
          _isGoogleVideoExpired(urlToDownload) ||
          (song.isPreview && !urlToDownload.contains('googlevideo.com'))) {
        try {
          final enrichment = await _enrichment.enrichTrack(
            title: song.title,
            artist: song.artist,
            album: song.album,
            duration: song.duration,
            previewFallbackOnly: false,
            allowPreviewFallback: false,
            prioritizeYouTube: true,
            youtubeOnly: _isYouTubeCatalogSong(song),
          );
          if (enrichment.hasAudio &&
              enrichment.previewUrl != null &&
              !enrichment.previewUrl!.toLowerCase().contains('.m3u8') &&
              enrichment.previewUrl!.startsWith('http')) {
            urlToDownload = enrichment.previewUrl!;
            _applyEnrichment(song, enrichment);
          }
        } catch (_) {}
      }

      if (urlToDownload.isEmpty ||
          urlToDownload.toLowerCase().contains('.m3u8') ||
          (!urlToDownload.startsWith('http://') &&
              !urlToDownload.startsWith('https://'))) {
        return;
      }

      final isGoogleVideo = urlToDownload.contains('googlevideo.com');
      final userAgent = isGoogleVideo
          ? TrackEnrichmentService.ytAndroidUserAgent
          : TrackEnrichmentService.browserUserAgent;

      final uri = Uri.parse(urlToDownload);
      final tempFile = File(p.join(offlineDir.path, '${song.id}.tmp'));

      final request = http.Request('GET', uri);
      request.headers['User-Agent'] = userAgent;
      request.headers['Accept'] = '*/*';
      if (!isGoogleVideo) {
        request.headers['Range'] = 'bytes=0-';
      }

      final client = http.Client();
      try {
        final streamedResponse = await client
            .send(request)
            .timeout(const Duration(seconds: 50));
        if (streamedResponse.statusCode == 200 ||
            streamedResponse.statusCode == 206) {
          final sink = tempFile.openWrite();
          await streamedResponse.stream.pipe(sink);
          await sink.flush();
          await sink.close();

          final downloadedBytes = await tempFile.length();
          if (downloadedBytes >= _minimumAudioFileBytes) {
            final ext = _audioExtensionForUrl(
              urlToDownload,
              contentType: streamedResponse.headers['content-type'],
            );
            final targetFile = File(p.join(offlineDir.path, '${song.id}$ext'));
            if (await targetFile.exists()) {
              try {
                await targetFile.delete();
              } catch (_) {}
            }
            await tempFile.rename(targetFile.path);
            _invalidateOfflineLookup(song.id);
            _downloadedSongIds.add(song.id);
            LocalDatabase.notifyAudioCacheChanged();

            song.audioUrl = targetFile.path;
            song.isPreview = false;
            song.isYouTubeAudio = false;
            _syncSongPathToQueueAndDb(song);
            _locatingStatusVersion++;
            notifyListeners();
            debugPrint(
              '[MusicPlayerController] Successfully cached ${song.title} ($downloadedBytes bytes) to local file: ${targetFile.path}',
            );

            // Persist to local SQLite database so offline playback works permanently
            unawaited(
              LocalDatabase.instance
                  .updateImportedSong(
                    id: song.id,
                    audioUrl: targetFile.path,
                    isPreview: false,
                    isYouTubeAudio: false,
                    durationMs: song.duration.inMilliseconds,
                    imageUrl: song.imageUrl,
                    lyrics: song.lyrics,
                  )
                  .catchError((e) {
                    debugPrint(
                      '[MusicPlayerController] updateImportedSong error: $e',
                    );
                  }),
            );

            // Also cache artwork locally if available
            if (song.imageUrl.startsWith('http')) {
              try {
                final artTarget = File(
                  p.join(offlineDir.path, '${song.id}.jpg'),
                );
                if (!artTarget.existsSync()) {
                  final artResp = await http
                      .get(Uri.parse(song.imageUrl))
                      .timeout(const Duration(seconds: 15));
                  if (artResp.statusCode == 200 &&
                      artResp.bodyBytes.isNotEmpty) {
                    await artTarget.writeAsBytes(
                      artResp.bodyBytes,
                      flush: true,
                    );
                    _invalidateOfflineLookup(song.id, artwork: true);
                    LocalDatabase.notifyAudioCacheChanged();
                  }
                }
              } catch (_) {}
            }
          } else {
            if (await tempFile.exists()) {
              try {
                await tempFile.delete();
              } catch (_) {}
            }
            if ((streamedResponse.statusCode == 429 ||
                    streamedResponse.statusCode == 403) &&
                isGoogleVideo) {
              _enrichment.noteGooglevideoThrottle();
            }
            debugPrint(
              '[MusicPlayerController] Cache rejected (${streamedResponse.statusCode}) for ${song.title}',
            );
          }
        } else {
          if (await tempFile.exists()) {
            try {
              await tempFile.delete();
            } catch (_) {}
          }
          if ((streamedResponse.statusCode == 429 ||
                  streamedResponse.statusCode == 403) &&
              isGoogleVideo) {
            _enrichment.noteGooglevideoThrottle();
          }
          debugPrint(
            '[MusicPlayerController] Cache rejected (${streamedResponse.statusCode}) for ${song.title}',
          );
        }
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint(
        '[MusicPlayerController] Offline cache error for ${song.title}: $e',
      );
    } finally {
      _cachingIds.remove(song.id);
    }
  }

  void _syncSongPathToQueueAndDb(Song song) {
    for (final s in _allSongs) {
      if (s.id == song.id) {
        s.audioUrl = song.audioUrl;
        s.isPreview = song.isPreview;
        s.duration = song.duration;
      }
    }
    for (final s in _queue) {
      if (s.id == song.id) {
        s.audioUrl = song.audioUrl;
        s.isPreview = song.isPreview;
        s.duration = song.duration;
      }
    }
    if (_isDownloadableCatalogId(song.id) ||
        song.id.startsWith('discovery-')) {
      try {
        final dbAudioUrl =
            (song.audioUrl.contains('googlevideo.com') ||
                song.audioUrl.toLowerCase().contains('.m3u8'))
            ? ''
            : song.audioUrl;
        unawaited(
          LocalDatabase.instance
              .updateImportedSong(
                id: song.id,
                audioUrl: dbAudioUrl,
                isPreview: song.isPreview,
                isYouTubeAudio: song.isYouTubeAudio,
                durationMs: song.duration.inMilliseconds,
                imageUrl: song.imageUrl,
                lyrics: song.lyrics,
              )
              .catchError((_) {}),
        );
      } catch (_) {}
    }
  }

  /// Downloads a song to the local offline directory for permanent offline playback.
  /// Resolves the stream if needed, saves audio and artwork, and updates local database.
  ///
  /// Full tracks only by default: preview clips are not stored as permanent
  /// downloads. Set [allowPreviewFallback] only when a caller explicitly
  /// accepts a 30-second clip.
  Future<bool> downloadSong(
    Song song, {
    bool allowPreviewFallback = false,
  }) async {
    // 1. Check if a valid local offline file already exists. A stale preview
    //    or truncated file is removed so the full track can be fetched below.
    final cached = await _findCachedAudioFile(song.id);
    if (cached != null && cached.existsSync()) {
      if (await _isCompleteOfflineFile(song.id, cached)) {
        _downloadedSongIds.add(song.id);
        if (song.audioUrl != cached.path) {
          song.audioUrl = cached.path;
          song.isPreview = false;
          song.isYouTubeAudio = false;
          _syncSongPathToQueueAndDb(song);
          notifyListeners();
        }
        return true;
      }
      try {
        await cached.delete();
      } catch (_) {}
      _invalidateOfflineLookup(song.id);
    }

    // Don't download over mobile data unless the user allowed it.
    if (!await _mayDownloadNow()) {
      _logDiag('downloadSong skipped: on mobile data', song: song);
      return false;
    }

    if (_cachingIds.contains(song.id)) return false;
    _cachingIds.add(song.id);
    notifyListeners();

    try {
      final offlineDir = await _getPrimaryOfflineDirectory();
      var urlToDownload = song.audioUrl;
      var previewOnly = song.isPreview;

      // Reuse the controller's shared enrichment pass so a download and a
      // concurrent playback/radio lookup never resolve the same track twice
      // (duplicate searches were a major source of YouTube throttling).
      if (_needsFreshDownloadUrl(song, urlToDownload)) {
        try {
          await _ensureEnrichment(song, fastImport: true)
              .timeout(const Duration(seconds: 45));
        } catch (_) {}
        urlToDownload = song.audioUrl;
        previewOnly = song.isPreview;
      }

      // Preview fallback is opt-in only. Catalog downloads stay full-track so
      // a 30s clip is never stored as if it were a permanent download.
      if (_needsFreshDownloadUrl(song, urlToDownload) &&
          allowPreviewFallback) {
        try {
          final enrichment = await _enrichment.enrichTrack(
            title: song.title,
            artist: song.artist,
            album: song.album,
            duration: song.duration,
            previewFallbackOnly: true,
            allowPreviewFallback: true,
            prioritizeYouTube: true,
            youtubeOnly: _isYouTubeCatalogSong(song),
          );
          if (enrichment.hasAudio &&
              enrichment.previewUrl != null &&
              !enrichment.previewUrl!.toLowerCase().contains('.m3u8') &&
              enrichment.previewUrl!.startsWith('http')) {
            urlToDownload = enrichment.previewUrl!;
            previewOnly = !enrichment.isFullTrack;
          }
        } catch (_) {}
      }

      // Never persist a 30-second clip as a permanent download unless the
      // caller explicitly opted in. This also covers previews that were
      // already attached with a live googlevideo URL before the download.
      if (previewOnly && !allowPreviewFallback) {
        _logDiag(
          'downloadSong skipped: only a preview stream is available',
          song: song,
        );
        return false;
      }

      if (urlToDownload.isEmpty ||
          urlToDownload.toLowerCase().contains('.m3u8') ||
          (!urlToDownload.startsWith('http://') &&
              !urlToDownload.startsWith('https://'))) {
        return false;
      }

      final isGoogleVideo = urlToDownload.contains('googlevideo.com');
      final userAgent = isGoogleVideo
          ? TrackEnrichmentService.ytAndroidUserAgent
          : TrackEnrichmentService.browserUserAgent;

      final uri = Uri.parse(urlToDownload);
      final tempFile = File(p.join(offlineDir.path, '${song.id}.tmp'));

      final request = http.Request('GET', uri);
      request.headers['User-Agent'] = userAgent;
      request.headers['Accept'] = '*/*';
      if (!isGoogleVideo) {
        request.headers['Range'] = 'bytes=0-';
      }

      final client = http.Client();
      try {
        final streamedResponse = await client
            .send(request)
            .timeout(const Duration(seconds: 50));
        if (streamedResponse.statusCode == 200 ||
            streamedResponse.statusCode == 206) {
          final sink = tempFile.openWrite();
          await streamedResponse.stream.pipe(sink);
          await sink.flush();
          await sink.close();

          final downloadedBytes = await tempFile.length();
          if (downloadedBytes >= _minimumAudioFileBytes) {
            final ext = _audioExtensionForUrl(
              urlToDownload,
              contentType: streamedResponse.headers['content-type'],
            );
            final targetFile = File(p.join(offlineDir.path, '${song.id}$ext'));
            if (await targetFile.exists()) {
              try {
                await targetFile.delete();
              } catch (_) {}
            }
            await tempFile.rename(targetFile.path);
            _invalidateOfflineLookup(song.id);
            _downloadedSongIds.add(song.id);
            LocalDatabase.notifyAudioCacheChanged();

            song.audioUrl = targetFile.path;
            song.isPreview = previewOnly;
            song.isYouTubeAudio = false;
            _syncSongPathToQueueAndDb(song);
            _locatingStatusVersion++;
            notifyListeners();
            debugPrint(
              '[MusicPlayerController] Successfully downloaded ${song.title} ($downloadedBytes bytes) to: ${targetFile.path}',
            );

            // Persist to local SQLite before reporting success. Radio and
            // discovery tracks may not have a row yet, so insert first and
            // then point that row at the downloaded file.
            try {
              final db = LocalDatabase.instance;
              await db.ensureImportedSong(
                id: song.id,
                title: song.title,
                artist: song.artist,
                album: song.album,
                durationMs: song.duration.inMilliseconds,
                imageUrl: song.imageUrl,
                lyrics: song.lyrics,
                genre: song.genre,
                isPreview: song.isPreview,
                isYouTubeAudio: false,
                youtubeVideoId: song.youtubeVideoId,
                isExplicit: song.isExplicit,
              );
              await db.updateImportedSong(
                id: song.id,
                audioUrl: targetFile.path,
                isPreview: song.isPreview,
                isYouTubeAudio: false,
                youtubeVideoId: song.youtubeVideoId.isNotEmpty
                    ? song.youtubeVideoId
                    : null,
                durationMs: song.duration.inMilliseconds,
                imageUrl: song.imageUrl,
                lyrics: song.lyrics,
              );
            } catch (e) {
              debugPrint(
                '[MusicPlayerController] persist download error: $e',
              );
            }

            // Also cache artwork locally if available
            if (song.imageUrl.startsWith('http')) {
              try {
                final artTarget = File(
                  p.join(offlineDir.path, '${song.id}.jpg'),
                );
                if (!artTarget.existsSync()) {
                  final artResp = await http
                      .get(Uri.parse(song.imageUrl))
                      .timeout(const Duration(seconds: 15));
                  if (artResp.statusCode == 200 &&
                      artResp.bodyBytes.isNotEmpty) {
                    await artTarget.writeAsBytes(
                      artResp.bodyBytes,
                      flush: true,
                    );
                    _invalidateOfflineLookup(song.id, artwork: true);
                    LocalDatabase.notifyAudioCacheChanged();
                  }
                }
              } catch (_) {}
            }
            return true;
          } else {
            if (await tempFile.exists()) {
              try {
                await tempFile.delete();
              } catch (_) {}
            }
            return false;
          }
        } else {
          if (await tempFile.exists()) {
            try {
              await tempFile.delete();
            } catch (_) {}
          }
          if ((streamedResponse.statusCode == 429 ||
                  streamedResponse.statusCode == 403) &&
              isGoogleVideo) {
            _enrichment.noteGooglevideoThrottle();
          }
          return false;
        }
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint(
        '[MusicPlayerController] Download error for ${song.title}: $e',
      );
      return false;
    } finally {
      _cachingIds.remove(song.id);
      notifyListeners();
    }
  }

  Completer<void>? _persistDownloadLock;

  Future<void> _safePersistDownloadTarget(
    List<Song> songs, {
    MusicPlaylist? playlist,
    String? title,
    String? subtitle,
  }) async {
    while (_persistDownloadLock != null) {
      try {
        await _persistDownloadLock!.future;
      } catch (_) {}
    }
    final lock = Completer<void>();
    _persistDownloadLock = lock;
    try {
      await _persistDownloadTarget(
        songs,
        playlist: playlist,
        title: title,
        subtitle: subtitle,
      );
    } finally {
      if (_persistDownloadLock == lock) {
        _persistDownloadLock = null;
      }
      if (!lock.isCompleted) {
        lock.complete();
      }
    }
  }

  /// Downloads all pending songs in a playlist concurrently using [maxConcurrentWorkers]
  /// parallel download workers (defaults to 3), progressively persisting completed tracks
  /// directly to the local SQLite database so offline playback is immediately available.
  ///
  /// The playlist is persisted before the first download so radio, artist,
  /// and discovery playlists (which normally live only in memory) are restored
  /// with their downloaded files after a restart.
  ///
  /// Returns how many tracks are available offline when the pass finishes.
  Future<int> downloadPlaylistSongs(
    List<Song> songs, {
    MusicPlaylist? playlist,
    String? title,
    String? subtitle,
    int maxConcurrentWorkers = 3,
  }) async {
    final distinct = <Song>[];
    final seen = <String>{};
    for (final song in songs) {
      if (seen.add(song.id)) distinct.add(song);
    }
    if (distinct.isEmpty) return 0;

    await _safePersistDownloadTarget(
      distinct,
      playlist: playlist,
      title: title,
      subtitle: subtitle,
    );

    var available = 0;
    final completers = <Completer<bool>>[];

    for (final song in distinct) {
      if (isSongDownloaded(song.id)) {
        available++;
        continue;
      }

      final completer = Completer<bool>();
      completers.add(completer);

      if (_cachingIds.contains(song.id)) {
        _inFlightCompleters.putIfAbsent(song.id, () => []).add(completer);
        continue;
      }

      final existingTask =
          _downloadQueue.where((t) => t.song.id == song.id).firstOrNull;
      if (existingTask != null) {
        existingTask.completers.add(completer);
      } else {
        _downloadQueue.add(
          _DownloadTask(
            song: song,
            playlistSongs: distinct,
            playlist: playlist,
            title: title,
            subtitle: subtitle,
            completers: [completer],
          ),
        );
      }
    }

    _processDownloadQueue();

    if (completers.isNotEmpty) {
      final results = await Future.wait(completers.map((c) => c.future));
      available += results.where((ok) => ok).length;
    }

    await _safePersistDownloadTarget(
      distinct,
      playlist: playlist,
      title: title,
      subtitle: subtitle,
    );
    return available;
  }

  void _processDownloadQueue() {
    if (_disposed) return;
    while (_activeDownloadWorkers < _maxConcurrentDownloadWorkers &&
        _downloadQueue.isNotEmpty) {
      _activeDownloadWorkers++;
      final task = _downloadQueue.removeAt(0);
      _runDownloadWorker(task);
    }
  }

  Future<void> _runDownloadWorker(_DownloadTask task) async {
    final song = task.song;
    var success = false;
    try {
      if (isSongDownloaded(song.id)) {
        success = true;
      } else {
        success = await downloadSong(song);
      }
    } catch (e) {
      debugPrint(
        '[MusicPlayerController] worker download error for ${song.title}: $e',
      );
      success = false;
    } finally {
      for (final c in task.completers) {
        if (!c.isCompleted) c.complete(success);
      }
      final inFlight = _inFlightCompleters.remove(song.id);
      if (inFlight != null) {
        for (final c in inFlight) {
          if (!c.isCompleted) c.complete(success);
        }
      }

      if (success && !_disposed) {
        await _safePersistDownloadTarget(
          task.playlistSongs,
          playlist: task.playlist,
          title: task.title,
          subtitle: task.subtitle,
        );
      }

      _activeDownloadWorkers--;
      _processDownloadQueue();
    }
  }

  /// Automatically downloads and persists the songs in Explore radio playlists
  /// using 3 parallel workers so they are available offline and saved in the SQLite database.
  void autoDownloadExploreRadios(List<RadioStation> stations) {
    if (stations.isEmpty || _disposed || !_autoDownloadOnImport) return;
    for (final st in stations) {
      if (st.songs.isEmpty) continue;
      unawaited(
        downloadPlaylistSongs(
          st.songs,
          playlist: st.toPlaylist(),
          title: st.title,
          subtitle: st.subtitle,
          maxConcurrentWorkers: 3,
        ),
      );
    }
  }

  /// Moves the given songs to the front of the download queue so the screen the user
  /// is currently viewing downloads first with the 3 workers.
  void prioritizePlaylistDownloads(List<Song> songs) {
    if (songs.isEmpty || _downloadQueue.isEmpty) return;
    final ids = songs.map((s) => s.id).toSet();
    final prioritized = <_DownloadTask>[];
    final remaining = <_DownloadTask>[];
    for (final task in _downloadQueue) {
      if (ids.contains(task.song.id)) {
        prioritized.add(task);
      } else {
        remaining.add(task);
      }
    }
    if (prioritized.isNotEmpty) {
      _downloadQueue
        ..clear()
        ..addAll(prioritized)
        ..addAll(remaining);
    }
  }

  /// Downloads playlist songs using [workerCount] concurrent workers (defaults to 3)
  /// for high-speed offline caching and immediate SQLite database persistence.
  Future<int> downloadPlaylistWithWorkers(
    List<Song> songs, {
    MusicPlaylist? playlist,
    String? title,
    String? subtitle,
    int workerCount = 3,
  }) {
    return downloadPlaylistSongs(
      songs,
      playlist: playlist,
      title: title,
      subtitle: subtitle,
      maxConcurrentWorkers: workerCount,
    );
  }

  /// Downloads all songs for a specific playlist ID using 3 parallel workers.
  Future<int> downloadPlaylistById(
    String playlistId, {
    int workerCount = 3,
  }) async {
    final playlist = playlistById(playlistId);
    if (playlist == null) return 0;
    final songs =
        _allSongs.where((s) => playlist.songIds.contains(s.id)).toList();
    return downloadPlaylistSongs(
      songs,
      playlist: playlist,
      title: playlist.title,
      subtitle: playlist.subtitle,
      maxConcurrentWorkers: workerCount,
    );
  }

  /// Persists a playlist from a download action and returns whether the track
  /// is available offline afterwards. Used by the per-song download buttons so
  /// a single radio/discovery download is still reachable after a restart.
  Future<bool> downloadPlaylistSong(
    Song song, {
    MusicPlaylist? playlist,
    List<Song>? songs,
    String? title,
    String? subtitle,
  }) async {
    final context = <Song>[...?songs, song];
    await _safePersistDownloadTarget(
      context,
      playlist: playlist,
      title: title,
      subtitle: subtitle,
    );
    final success = await downloadSong(song);
    if (success) {
      await _safePersistDownloadTarget(
        context,
        playlist: playlist,
        title: title,
        subtitle: subtitle,
      );
    }
    return success;
  }

  /// Saves the playlist + its songs to local SQLite before downloading.
  ///
  /// [playlist] is used for radio/artist/daily-mix screens. Discovery sections
  /// pass only [title]/[subtitle], in which case a stable `download-*` playlist
  /// is created (or an existing same-title playlist is reused).
  Future<void> _persistDownloadTarget(
    List<Song> songs, {
    MusicPlaylist? playlist,
    String? title,
    String? subtitle,
  }) async {
    if (songs.isEmpty) return;
    try {
      final rawUserId = (_loadedUserId != null && _loadedUserId!.isNotEmpty)
          ? _loadedUserId!
          : (AuthService.instance.currentUserId.isNotEmpty
              ? AuthService.instance.currentUserId
              : 'default_user');
      final userId = rawUserId;

      MusicPlaylist target;
      if (playlist != null) {
        target =
            playlistById(playlist.id) ??
            _playlistByTitle(playlist.title) ??
            playlist;
        if (_deletedPlaylistIds.contains(target.id) ||
            _deletedPlaylistIds.contains(_normalizeKey(target.title)) ||
            await LocalDatabase.instance.isPlaylistDeleted(
              target.id,
              title: target.title,
              userId: userId,
            )) {
          return;
        }
        if (isExploreRadioPlaylist(target.id)) {
          if (!_exploreRadioPlaylists.any((p) => p.id == target.id)) {
            _exploreRadioPlaylists.add(target);
          }
          _playlists.removeWhere((p) => p.id == target.id);
        } else if (!_playlists.any((p) => p.id == target.id)) {
          _playlists.add(target);
        }
      } else {
        final cleanTitle = (title ?? '').trim();
        if (cleanTitle.isEmpty) return;
        if (_deletedPlaylistIds.contains(_normalizeKey(cleanTitle))) return;
        final existing = _playlistByTitle(cleanTitle);
        if (existing != null) {
          target = existing;
        } else {
          final pId = _downloadPlaylistId(cleanTitle);
          target = MusicPlaylist(
            id: pId,
            title: cleanTitle,
            subtitle: (subtitle ?? '').trim().isEmpty
                ? 'Downloaded for offline'
                : subtitle!.trim(),
            gradient: _gradientFor(cleanTitle).colors,
          );
          if (_deletedPlaylistIds.contains(target.id) ||
              _deletedPlaylistIds.contains(_normalizeKey(target.title)) ||
              await LocalDatabase.instance.isPlaylistDeleted(
                target.id,
                title: target.title,
                userId: userId,
              )) {
            return;
          }
          if (isExploreRadioPlaylist(target.id)) {
            if (!_exploreRadioPlaylists.any((p) => p.id == target.id)) {
              _exploreRadioPlaylists.add(target);
            }
          } else {
            _playlists.add(target);
          }
        }
      }

      final seen = <String>{};
      var addedSong = false;
      for (final song in songs) {
        if (!seen.add(song.id)) continue;
        if (!_allSongs.any((s) => s.id == song.id)) {
          _allSongs.add(song);
          addedSong = true;
        }
        if (!target.songIds.contains(song.id)) {
          target.songIds.add(song.id);
        }
      }
      if (addedSong) _markSongsChanged();

      final playlistSongs = _allSongs
          .where((s) => target.songIds.contains(s.id))
          .toList();
      final songRows = <Map<String, dynamic>>[];
      for (final s in playlistSongs) {
        final row = _songToImportedMap(s);
        // saveImportedPlaylistOffline rewrites whole rows with INSERT OR
        // REPLACE. Inject the on-disk file for tracks that are already
        // downloaded so re-saving a playlist never resets them to a network
        // URL (which also made startup cleanup delete the file).
        final cached = await _findCachedAudioFile(s.id);
        if (cached != null &&
            await cached.exists() &&
            await _isCompleteOfflineFile(s.id, cached)) {
          row['audio_url'] = cached.path;
          row['is_preview'] = 0;
          row['is_youtube_audio'] = 0;
          _downloadedSongIds.add(s.id);
        } else {
          final audioUrl = row['audio_url'] as String? ?? '';
          // Expiring stream URLs are dead after a restart; leave the row
          // empty so enrichment resolves a fresh one instead.
          if (audioUrl.contains('googlevideo.com') ||
              audioUrl.toLowerCase().contains('.m3u8')) {
            row['audio_url'] = '';
          }
        }
        songRows.add(row);
      }
      await LocalDatabase.instance.saveImportedPlaylistOffline(
        id: target.id,
        userId: userId,
        title: target.title,
        subtitle: target.subtitle,
        imageUrl: target.imageUrl,
        gradientColors: target.gradient.map((c) => c.toARGB32()).toList(),
        songs: songRows,
      );
      notifyListeners();
    } catch (e) {
      debugPrint(
        '[MusicPlayerController] persist download playlist skipped: $e',
      );
    }
  }

  static String _downloadPlaylistId(String title) {
    final slug = _normalizeKey(
      title,
    ).replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(
      RegExp(r'^-+|-+$'),
      '',
    );
    return 'download-${slug.isEmpty ? DateTime.now().microsecondsSinceEpoch : slug}';
  }

  static Map<String, dynamic> _songToImportedMap(Song s) {
    return <String, dynamic>{
      'id': s.id,
      'title': s.title,
      'artist': s.artist,
      'album': s.album,
      'duration_ms': s.duration.inMilliseconds,
      'image_url': s.imageUrl,
      'audio_url': s.audioUrl,
      'lyrics': s.lyrics,
      'genre': s.genre,
      'is_preview': s.isPreview ? 1 : 0,
      'is_youtube_audio': s.isYouTubeAudio ? 1 : 0,
      'youtube_video_id': s.youtubeVideoId,
      'is_explicit': s.isExplicit ? 1 : 0,
    };
  }

  /// Removes a downloaded song and artwork from offline storage,
  /// updating the local database and notifying listeners.
  Future<bool> removeDownloadedSong(Song song) async {
    try {
      _downloadedSongIds.remove(song.id);
      final cached = await _findCachedAudioFile(song.id);
      if (cached != null && await cached.exists()) {
        try {
          await cached.delete();
        } catch (_) {}
      }
      _invalidateOfflineLookup(song.id);

      final artwork = await _findCachedArtworkFile(song.id);
      if (artwork != null && await artwork.exists()) {
        try {
          await artwork.delete();
        } catch (_) {}
      }
      _invalidateOfflineLookup(song.id, artwork: true);
      LocalDatabase.notifyAudioCacheChanged();

      song.audioUrl = '';
      _syncSongPathToQueueAndDb(song);
      _locatingStatusVersion++;
      notifyListeners();

      unawaited(
        LocalDatabase.instance
            .updateImportedSong(
              id: song.id,
              audioUrl: '',
              isPreview: false,
              isYouTubeAudio: true,
            )
            .catchError((_) {}),
      );

      return true;
    } catch (e) {
      debugPrint(
        '[MusicPlayerController] Error removing downloaded song ${song.title}: $e',
      );
      return false;
    }
  }

  /// Public retry used by the lyrics sheet when a track has no lyrics yet
  /// (or is still stuck on a 30s preview). Returns true when lyrics are
  /// now available.
  Future<bool> ensureLyricsFor(Song song) async {
    final hasFakeLyrics = _offlineFakeLyricsIds.contains(song.id);
    final hasSyncedLyrics = song.lyrics.any(
      (l) => Song.parseLyricTimestamp(l) != null,
    );
    final needsLyrics =
        song.lyrics.isEmpty || hasFakeLyrics || !hasSyncedLyrics;
    final needsFullAudio =
        (song.isPreview ||
            _offlineFallbackIds.contains(song.id) ||
            song.isYouTubeAudio ||
            song.isSilentPlaceholder) &&
        _shouldAttemptFullUpgrade(song.id);
    if (!needsLyrics && !needsFullAudio) return song.lyrics.isNotEmpty;
    final existingPass = _pendingEnrichment[song.id];
    if (existingPass != null) {
      try {
        await existingPass;
      } catch (_) {}
      return song.lyrics.isNotEmpty;
    }
    if (_enrichingIds.contains(song.id)) return song.lyrics.isNotEmpty;
    // Reuse the local bundled lyrics when this import matched a local song.
    if (!song.id.startsWith('spotify-')) return song.lyrics.isNotEmpty;
    _enrichingIds.add(song.id);
    if (needsFullAudio) {
      _fullUpgradeAttemptedAt[song.id] = DateTime.now();
    }
    song.isEnrichingLyrics = true;
    notifyListeners();
    try {
      final enrichment = await _enrichment.enrichTrack(
        title: song.title,
        artist: song.artist,
        album: song.album,
        duration: song.duration,
        allowPreviewFallback: true,
        prioritizeYouTube: false,
        youtubeOnly: _isYouTubeCatalogSong(song),
      );
      if (enrichment.hasAudio || enrichment.hasLyrics) {
        _enrichedIds.add(song.id);
      }
      final changed = _applyEnrichment(song, enrichment);
      song.isEnrichingLyrics = false;
      if (changed) notifyListeners();
      // If enrichment found nothing (offline), ensure the tracker still has
      // timestamped lines so it moves instead of showing empty.
      if (song.lyrics.isEmpty) {
        _ensureOfflineLyrics(song);
        if (song.lyrics.isEmpty) {
          final durationSeconds = song.duration.inSeconds > 0
              ? song.duration.inSeconds
              : 180;
          song.lyrics = [
            '[00:00.00] ♫ ${song.title} ♫',
            '[00:05.00] ${song.artist}',
            if (song.album.isNotEmpty) '[00:10.00] ${song.album}',
            '[00:16.00] ♫ High-fidelity audio playback active ♫',
            '[00:26.00] (Instrumental Groove & Rhythm)',
            '[00:40.00] ♫ Lyrics tracker moving in real-time ♫',
            '[01:00.00] ♫ ${song.title} by ${song.artist} ♫',
            '[01:25.00] (Dynamic Melody & Rhythm)',
            '[01:50.00] ♫ Seamless listening experience ♫',
            if (durationSeconds > 150) '[02:15.00] (Harmonic Bridge)',
            if (durationSeconds > 180) '[02:40.00] ♫ Pulse Studio ♫',
          ];
          _offlineFakeLyricsIds.add(song.id);
        }
        notifyListeners();
      }
      return song.lyrics.isNotEmpty;
    } catch (_) {
      song.isEnrichingLyrics = false;
      _ensureOfflineLyrics(song);
      if (song.lyrics.isEmpty) {
        final durationSeconds = song.duration.inSeconds > 0
            ? song.duration.inSeconds
            : 180;
        song.lyrics = [
          '[00:00.00] ♫ ${song.title} ♫',
          '[00:05.00] ${song.artist}',
          if (song.album.isNotEmpty) '[00:10.00] ${song.album}',
          '[00:16.00] ♫ High-fidelity audio playback active ♫',
          '[00:26.00] (Instrumental Groove & Rhythm)',
          '[00:40.00] ♫ Lyrics tracker moving in real-time ♫',
          '[01:00.00] ♫ ${song.title} by ${song.artist} ♫',
          '[01:25.00] (Dynamic Melody & Rhythm)',
          '[01:50.00] ♫ Seamless listening experience ♫',
          if (durationSeconds > 150) '[02:15.00] (Harmonic Bridge)',
          if (durationSeconds > 180) '[02:40.00] ♫ Pulse Studio ♫',
        ];
        _offlineFakeLyricsIds.add(song.id);
      }
      notifyListeners();
      return song.lyrics.isNotEmpty;
    } finally {
      _enrichingIds.remove(song.id);
    }
  }

  bool isEnriching(String songId) => _enrichingIds.contains(songId);

  static String _normalizeKey(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }

  static LinearGradient _gradientFor(String seed) {
    const palettes = <LinearGradient>[
      LinearGradient(colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)]),
      LinearGradient(colors: [Color(0xFF06B6D4), Color(0xFF3B82F6)]),
      LinearGradient(colors: [Color(0xFFEC4899), Color(0xFFF59E0B)]),
      LinearGradient(colors: [Color(0xFF10B981), Color(0xFF06B6D4)]),
      LinearGradient(colors: [Color(0xFFF43F5E), Color(0xFF8B5CF6)]),
    ];
    var hash = 0;
    for (final unit in seed.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return palettes[hash % palettes.length];
  }

  void playPlaylist(String playlistId) {
    final songs = songsForPlaylist(playlistId);
    if (songs.isEmpty) return;
    final firstAllowed = _firstAllowedIndex(songs, 0);
    if (firstAllowed == null) {
      _notifyExplicitBlocked(songs.first);
      return;
    }
    _queue = List<Song>.from(songs);
    _currentIndex = firstAllowed;
    _completionHandled = false;
    _currentPosition = Duration.zero;
    _audioDuration = Duration.zero;
    _lastPositionUpdate = DateTime.now();
    _unmuteOnPlay();
    _isPlaying = true;
    _pendingHotSwapReload = false;
    _playbackTimer?.cancel();
    _cancelStallWatchdog();
    _startTimer();
    _clearSilentRetry();
    _playCurrentSongAudio();
    notifyListeners();
  }

  /// Plays [songs] as the active queue starting at [startIndex], without
  /// adding them to the saved library. Used by the dashboard discovery rows
  /// and their playlist pages.
  void playSongList(List<Song> songs, {int startIndex = 0}) {
    if (songs.isEmpty) return;
    var start = startIndex;
    if (start < 0) start = 0;
    if (start > songs.length - 1) start = songs.length - 1;
    final firstAllowed = _firstAllowedIndex(songs, start);
    if (firstAllowed == null) {
      _notifyExplicitBlocked(songs[start]);
      return;
    }
    start = firstAllowed;
    _queue = List<Song>.from(songs);
    _currentIndex = start;
    _completionHandled = false;

    for (final s in _queue) {
      if (s.audioUrl.isEmpty ||
          (!s.audioUrl.startsWith('http') &&
              !s.audioUrl.startsWith('asset') &&
              !File(s.audioUrl).existsSync())) {
        final cached = findCachedAudioFileSync(s.id);
        if (cached != null &&
            cached.existsSync() &&
            cached.lengthSync() > 1024) {
          s.audioUrl = cached.path;
          s.isPreview = false;
          s.isYouTubeAudio = false;
        }
      }
    }

    // When starting playback, if the target track is actively in "LOCATING" status
    // (no audio resolved yet), skip forward to the next playable track so playback
    // begins immediately without stalling on "LOCATING".
    if (isLocatingStatus(_queue[_currentIndex])) {
      final playableIndex = nextPlayableTrackIndex(
        _queue,
        _currentIndex - 1,
        true,
        isBlocked: _isExplicitBlocked,
      );
      if (playableIndex != null) {
        final skipped = <Song>[];
        for (var i = 0; i < playableIndex; i++) {
          if (isLocatingStatus(_queue[i])) skipped.add(_queue[i]);
        }
        _currentIndex = playableIndex;
        if (skipped.isNotEmpty) {
          for (final s in skipped) {
            _fullUpgradeAttemptedAt.remove(s.id);
          }
          _enrichImportedSongs(skipped, fastImport: true);
        }
      }
    }

    _currentPosition = Duration.zero;
    _audioDuration = Duration.zero;
    _lastPositionUpdate = DateTime.now();
    _unmuteOnPlay();
    _isPlaying = true;
    _pendingHotSwapReload = false;
    _playbackTimer?.cancel();
    _cancelStallWatchdog();
    _startTimer();
    _clearSilentRetry();
    _playCurrentSongAudio();
    notifyListeners();
  }

  /// Fast-locates full tracks, audio and lyrics for discovery tracks across
  /// Quick Picks, Covers & Remixes, Community Favorites, and Trending For You.
  /// Bypasses retry backoff cooldowns so refreshing immediately locates the songs.
  void fastLocateDiscoverySongs(List<Song> songs) {
    if (songs.isEmpty || _disposed) return;
    final seen = <String>{};
    final unique = <Song>[];
    for (final s in songs) {
      if (!seen.add(s.id)) continue;
      _fullUpgradeAttemptedAt.remove(s.id);
      _fullTrackAttemptCount.remove(s.id);
      unique.add(s);
    }
    // Earlier rows (Quick Picks first) are located first, 2 at a time to prevent UI lag.
    _enrichImportedSongs(unique, fastImport: true, maxConcurrency: 2);
  }

  /// Fast-locates full tracks + audio + lyrics strictly via YouTube for
  /// Explore radio playlists and imported radio stations.
  /// Bypasses backoff cooldowns and uses 4 workers for immediate resolution.
  void fastLocateRadioSongs(List<Song> songs) {
    if (songs.isEmpty || _disposed) return;
    final seen = <String>{};
    final unique = <Song>[];
    for (final s in songs) {
      if (!seen.add(s.id)) continue;
      _fullUpgradeAttemptedAt.remove(s.id);
      _fullTrackAttemptCount.remove(s.id);
      unique.add(s);
    }
    _enrichImportedSongs(unique, fastImport: true, maxConcurrency: 4);
  }

  /// Pre-locates tracks for the given Explore radio stations in the background
  /// using YouTube only, so that when a user browses or opens a radio station,
  /// the songs are already resolved to full tracks instead of showing "LOCATING".
  void preLocateExploreRadios(List<RadioStation> stations) {
    if (stations.isEmpty || _disposed) return;
    final allSongs = <Song>[];
    for (final st in stations.take(4)) {
      allSongs.addAll(st.songs);
    }
    fastLocateRadioSongs(allSongs);
  }

  /// Fast-locates full tracks + audio + lyrics for imported Spotify playlist
  /// songs (the ones stuck on "LOCATING AUDIO"). Clears retry backoff so a
  /// re-import / refresh locates them immediately instead of waiting minutes.
  /// Uses higher concurrency (4) since imported tracks are the user's priority.
  void fastLocateImportedSongs({List<Song>? songs}) {
    final targets =
        songs ??
        _allSongs
            .where(
              (s) =>
                  s.id.startsWith('spotify-') ||
                  s.id.startsWith('itunes-') ||
                  s.isSilentPlaceholder ||
                  s.isPreview,
            )
            .toList();
    if (targets.isEmpty || _disposed) return;
    final seen = <String>{};
    final unique = <Song>[];
    for (final s in targets) {
      if (!seen.add(s.id)) continue;
      _fullUpgradeAttemptedAt.remove(s.id);
      _fullTrackAttemptCount.remove(s.id);
      unique.add(s);
    }
    _enrichImportedSongs(unique, fastImport: true, maxConcurrency: 6);
  }

  void addSong(Song song) {
    _allSongs.add(song);
    _markSongsChanged();
    _queue.add(song);
    notifyListeners();
  }

  void setSongs(List<Song> songs) {
    _allSongs.clear();
    _allSongs.addAll(songs);
    _markSongsChanged();
    _queue = List<Song>.from(_allSongs);
    _currentIndex = 0;
    _completionHandled = false;
    _currentPosition = Duration.zero;
    _audioDuration = Duration.zero;
    _isPlaying = false;
    _playbackTimer?.cancel();
    try {
      // ignore: discarded_futures
      _audioPlayer.stop().catchError((_) {});
    } catch (_) {}
    _audioPlayerHasSource = false;
    notifyListeners();
  }

  void clearSongs() {
    _allSongs.clear();
    _markSongsChanged();
    _queue.clear();
    _currentIndex = 0;
    _completionHandled = false;
    _currentPosition = Duration.zero;
    _audioDuration = Duration.zero;
    _isPlaying = false;
    _playbackTimer?.cancel();
    try {
      // ignore: discarded_futures
      _audioPlayer.stop().catchError((_) {});
    } catch (_) {}
    _audioPlayerHasSource = false;
    notifyListeners();
  }

  void setNavIndex(int index) {
    _currentNavIndex = index;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void setSelectedGenre(String genre) {
    _selectedGenre = genre;
    notifyListeners();
  }

  void playSong(Song song) {
    if (_isExplicitBlocked(song)) {
      _notifyExplicitBlocked(song);
      return;
    }
    final existingIndex = _queue.indexWhere((s) => s.id == song.id);
    if (existingIndex != -1) {
      _currentIndex = existingIndex;
    } else if (_queue.isEmpty ||
        _currentIndex < 0 ||
        _currentIndex >= _queue.length) {
      _queue.add(song);
      _currentIndex = _queue.length - 1;
    } else {
      _queue.insert(_currentIndex + 1, song);
      _currentIndex++;
    }
    _completionHandled = false;
    _currentPosition = Duration.zero;
    _audioDuration = Duration.zero;
    _lastPositionUpdate = DateTime.now();
    _unmuteOnPlay();
    _isPlaying = true;
    _pendingHotSwapReload = false;
    _playbackTimer?.cancel();
    _cancelStallWatchdog();
    _startTimer();
    _clearSilentRetry();
    _playCurrentSongAudio();
    notifyListeners();
  }

  void togglePlayPause() {
    if (currentSong == null) return;
    if (!_isPlaying && _isExplicitBlocked(currentSong)) {
      _notifyExplicitBlocked(currentSong!);
      return;
    }
    _isPlaying = !_isPlaying;
    if (_isPlaying) {
      _completionHandled = false;
      _unmuteOnPlay();
      _activateAudioSession();
      _lastPositionUpdate = DateTime.now();
      _startTimer();
      if (_audioPlayerHasSource) {
        try {
          final effectiveVolume = _isMuted
              ? 0.0
              : (_volume > 0.05 ? _volume : 0.8);
          // ignore: discarded_futures
          _audioPlayer.setVolume(effectiveVolume).catchError((_) {});
          // ignore: discarded_futures
          _audioPlayer.play().catchError((_) {});
          _scheduleVolumeReasserts();
        } catch (_) {}
      } else {
        _playCurrentSongAudio();
      }
    } else {
      if (_audioPlayerHasSource) {
        try {
          // ignore: discarded_futures
          _audioPlayer.pause().catchError((_) {});
        } catch (_) {}
      }
      _playbackTimer?.cancel();
      _cancelStallWatchdog();
    }
    notifyListeners();
  }

  void play() {
    if (currentSong == null) return;
    if (_isExplicitBlocked(currentSong)) {
      _notifyExplicitBlocked(currentSong!);
      return;
    }
    if (!_isPlaying) {
      _completionHandled = false;
      _unmuteOnPlay();
      _activateAudioSession();
      _isPlaying = true;
      _lastPositionUpdate = DateTime.now();
      _startTimer();
      if (_audioPlayerHasSource) {
        try {
          final effectiveVolume = _isMuted
              ? 0.0
              : (_volume > 0.05 ? _volume : 0.8);
          // ignore: discarded_futures
          _audioPlayer.setVolume(effectiveVolume).catchError((_) {});
          // ignore: discarded_futures
          _audioPlayer.play().catchError((_) {});
          _scheduleVolumeReasserts();
        } catch (_) {}
      } else {
        _playCurrentSongAudio();
      }
      notifyListeners();
    }
  }

  void pause() {
    if (_isPlaying) {
      _isPlaying = false;
      if (_audioPlayerHasSource) {
        try {
          // ignore: discarded_futures
          _audioPlayer.pause().catchError((_) {});
        } catch (_) {}
      }
      _playbackTimer?.cancel();
      _cancelStallWatchdog();
      notifyListeners();
    }
  }

  /// True when a track has no full audio yet (still locating, silent,
  /// or a 30s preview) — these skip forward into full tracks or are targeted for full upgrade.
  /// Status FULL TRACK (song.isFullTrack == true) must NEVER be skipped or flagged as needing full track.
  static bool needsFullTrack(Song song) {
    if (song.isFullTrack) {
      return false;
    }
    if (song.audioUrl.startsWith('assets/') ||
        song.audioUrl.startsWith('asset:/')) {
      return false;
    }
    if (song.id.startsWith('local-') || song.id.startsWith('sample-')) {
      return false;
    }
    return !song.hasAudio || song.isPreview || song.isSilentPlaceholder;
  }

  /// Index of the next full track after [fromIndex] in [queue], or null
  /// when none exists. Locating/preview placeholders are skipped; with
  /// [wrap] the search continues from the top (repeat-all / shuffle).
  static int? nextFullTrackIndex(List<Song> queue, int fromIndex, bool wrap) {
    if (queue.isEmpty) return null;
    final start = fromIndex.clamp(-1, queue.length - 1);
    for (var i = start + 1; i < queue.length; i++) {
      if (!needsFullTrack(queue[i])) return i;
    }
    if (wrap) {
      for (var i = 0; i <= start && i < queue.length; i++) {
        if (!needsFullTrack(queue[i])) return i;
      }
    }
    return null;
  }

  /// Checks whether a song should be skipped during sequential playback.
  ///
  /// Only genuinely unplayable placeholders are skipped:
  /// 1. "LOCATING" status (no audio URL resolved yet), OR
  /// 2. "PREVIEW" status (30s preview clip, not a full track).
  ///
  /// Full tracks must NEVER be skipped here — even when their saved URL is an
  /// expired YouTube link, an .m3u8, or a local path that no longer exists.
  /// Those are playback-recovery problems: playback refreshes or re-resolves
  /// the source instead of silently jumping over a real song the user expects
  /// to hear.
  static bool isLocatingStatus(Song song) {
    // Bundled assets, local songs, and offline cached files are full tracks.
    if (song.audioUrl.startsWith('assets/') ||
        song.audioUrl.startsWith('asset:/')) {
      return false;
    }
    if (song.id.startsWith('local-') || song.id.startsWith('sample-')) {
      return false;
    }

    // A local audio file that already exists on disk is a full track.
    if (song.audioUrl.isNotEmpty &&
        !song.audioUrl.startsWith('http://') &&
        !song.audioUrl.startsWith('https://')) {
      final f = File(song.audioUrl);
      if (f.existsSync() && f.lengthSync() > 1024) {
        return false;
      }
    }

    // Recover an unlinked cached full-track file before deciding to skip.
    final cached = findCachedAudioFileSync(song.id);
    if (cached != null && cached.existsSync() && cached.lengthSync() > 1024) {
      song.audioUrl = cached.path;
      song.isPreview = false;
      song.isYouTubeAudio = false;
      unawaited(
        LocalDatabase.instance.updateImportedSong(
          id: song.id,
          audioUrl: cached.path,
          isPreview: false,
          isYouTubeAudio: false,
        ),
      );
      return false;
    }

    // A resolved, non-preview track is a full track no matter how its source
    // currently looks. Never skip it; let playback try to recover the URL.
    if (song.isFullTrack) {
      return false;
    }

    // 30-second preview clips are not full tracks.
    if (song.isPreview) {
      return true;
    }

    // No audio URL at all means the track is still locating.
    return !song.hasAudio || song.audioUrl.isEmpty;
  }

  /// Index of the next playable track after [fromIndex] in [queue], or null
  /// when none exists. Tracks in "LOCATING" status (no audio yet) are skipped.
  /// With [wrap] the search continues from the top (repeat-all / shuffle).
  static int? nextPlayableTrackIndex(
    List<Song> queue,
    int fromIndex,
    bool wrap, {
    bool Function(Song)? isBlocked,
  }) {
    if (queue.isEmpty) return null;
    bool playable(Song song) =>
        !isLocatingStatus(song) && !(isBlocked?.call(song) ?? false);
    final start = fromIndex.clamp(-1, queue.length - 1);
    for (var i = start + 1; i < queue.length; i++) {
      if (playable(queue[i])) return i;
    }
    if (wrap) {
      for (var i = 0; i <= start && i < queue.length; i++) {
        if (playable(queue[i])) return i;
      }
    }
    return null;
  }

  /// Index of the previous playable track before [fromIndex] in [queue], or null
  /// when none exists. Tracks in "LOCATING" status are skipped.
  static int? previousPlayableTrackIndex(
    List<Song> queue,
    int fromIndex,
    bool wrap, {
    bool Function(Song)? isBlocked,
  }) {
    if (queue.isEmpty) return null;
    bool playable(Song song) =>
        !isLocatingStatus(song) && !(isBlocked?.call(song) ?? false);
    final start = fromIndex.clamp(0, queue.length);
    for (var i = start - 1; i >= 0; i--) {
      if (playable(queue[i])) return i;
    }
    if (wrap) {
      for (var i = queue.length - 1; i >= start && i >= 0; i--) {
        if (playable(queue[i])) return i;
      }
    }
    return null;
  }

  void next({bool fromCompletion = false}) {
    if (_queue.isEmpty) return;
    if (!fromCompletion) {
      // A manual skip starts fresh; only auto-advance keeps the completion
      // guard armed so a duplicate completion signal cannot skip twice.
      _completionHandled = false;
    }

    for (final s in _queue) {
      if (s.audioUrl.isEmpty ||
          (!s.audioUrl.startsWith('http') &&
              !s.audioUrl.startsWith('asset') &&
              !File(s.audioUrl).existsSync())) {
        final cached = findCachedAudioFileSync(s.id);
        if (cached != null &&
            cached.existsSync() &&
            cached.lengthSync() > 1024) {
          s.audioUrl = cached.path;
          s.isPreview = false;
          s.isYouTubeAudio = false;
        }
      }
    }

    if (_repeatMode == PlaybackRepeatMode.one &&
        !_isExplicitBlocked(currentSong)) {
      _currentPosition = Duration.zero;
      _audioDuration = Duration.zero;
      _playCurrentSongAudio();
      _startTimer();
      notifyListeners();
      return;
    }

    int? nextIndex;

    if (_isShuffle) {
      final random = Random();
      final playableIndices = <int>[];
      for (var i = 0; i < _queue.length; i++) {
        if (!isLocatingStatus(_queue[i]) && !_isExplicitBlocked(_queue[i])) {
          playableIndices.add(i);
        }
      }
      if (playableIndices.isNotEmpty) {
        nextIndex = playableIndices[random.nextInt(playableIndices.length)];
      }
    } else {
      nextIndex = nextPlayableTrackIndex(
        _queue,
        _currentIndex,
        _repeatMode == PlaybackRepeatMode.all,
        isBlocked: _isExplicitBlocked,
      );
    }

    if (nextIndex == null) {
      // No playable tracks available ahead in queue.
      // Trigger background enrichment for all locating songs so they can resolve.
      final locatingSongs = _queue.where((s) => isLocatingStatus(s)).toList();
      if (locatingSongs.isNotEmpty) {
        for (final s in locatingSongs) {
          _fullUpgradeAttemptedAt.remove(s.id);
        }
        _enrichImportedSongs(locatingSongs, fastImport: true);
      }
      pause();
      return;
    }

    // Identify tracks that were skipped because they have LOCATING status
    final skippedLocating = <Song>[];
    if (nextIndex > _currentIndex) {
      for (var i = _currentIndex + 1; i < nextIndex; i++) {
        if (isLocatingStatus(_queue[i])) {
          skippedLocating.add(_queue[i]);
        }
      }
    } else if (nextIndex < _currentIndex) {
      for (var i = _currentIndex + 1; i < _queue.length; i++) {
        if (isLocatingStatus(_queue[i])) {
          skippedLocating.add(_queue[i]);
        }
      }
      for (var i = 0; i < nextIndex; i++) {
        if (isLocatingStatus(_queue[i])) {
          skippedLocating.add(_queue[i]);
        }
      }
    }

    _currentIndex = nextIndex;

    // Fast-track enrichment for all skipped locating tracks in the background
    if (skippedLocating.isNotEmpty) {
      for (final s in skippedLocating) {
        _fullUpgradeAttemptedAt.remove(s.id);
      }
      _enrichImportedSongs(skippedLocating, fastImport: true);
    }

    // Trigger priority enrichment for newly selected song if it needs audio or full track
    final nextSong = _queue[_currentIndex];
    if (needsFullTrack(nextSong) &&
        !_enrichingIds.contains(nextSong.id) &&
        !_pendingEnrichment.containsKey(nextSong.id)) {
      _fullUpgradeAttemptedAt.remove(nextSong.id);
      // ignore: discarded_futures
      _ensureEnrichment(nextSong, fastImport: true);
    }

    _currentPosition = Duration.zero;
    _audioDuration = Duration.zero;
    _pendingHotSwapReload = false;
    if (_isPlaying) {
      _unmuteOnPlay();
      _lastPositionUpdate = DateTime.now();
      _playbackTimer?.cancel();
      _startTimer();
      _playCurrentSongAudio();
    }
    notifyListeners();
  }

  void previous() {
    if (_queue.isEmpty) return;
    _completionHandled = false;

    if (_currentPosition.inSeconds > 3 && !_isExplicitBlocked(currentSong)) {
      _currentPosition = Duration.zero;
      _audioDuration = Duration.zero;
      _pendingHotSwapReload = false;
      if (_isPlaying) {
        _unmuteOnPlay();
        _lastPositionUpdate = DateTime.now();
        _playbackTimer?.cancel();
        _startTimer();
        _playCurrentSongAudio();
      }
      return;
    }

    for (final s in _queue) {
      if (s.audioUrl.isEmpty ||
          (!s.audioUrl.startsWith('http') &&
              !s.audioUrl.startsWith('asset') &&
              !File(s.audioUrl).existsSync())) {
        final cached = findCachedAudioFileSync(s.id);
        if (cached != null &&
            cached.existsSync() &&
            cached.lengthSync() > 1024) {
          s.audioUrl = cached.path;
          s.isPreview = false;
          s.isYouTubeAudio = false;
        }
      }
    }

    final prevIndex = previousPlayableTrackIndex(
      _queue,
      _currentIndex,
      _repeatMode == PlaybackRepeatMode.all || _isShuffle,
      isBlocked: _isExplicitBlocked,
    );

    if (prevIndex != null) {
      _currentIndex = prevIndex;
      _currentPosition = Duration.zero;
      _audioDuration = Duration.zero;
      _pendingHotSwapReload = false;
      if (_isPlaying) {
        _unmuteOnPlay();
        _lastPositionUpdate = DateTime.now();
        _playbackTimer?.cancel();
        _startTimer();
        _playCurrentSongAudio();
      }
      notifyListeners();
    }
  }

  void seekTo(Duration position) {
    _completionHandled = false;
    if (position < Duration.zero) {
      _currentPosition = Duration.zero;
    } else if (position > currentDuration) {
      _currentPosition = currentDuration;
    } else {
      _currentPosition = position;
    }
    _lastPositionUpdate = DateTime.now();
    if (_audioPlayerHasSource) {
      try {
        // ignore: discarded_futures
        _audioPlayer.seek(_currentPosition).catchError((_) {});
      } catch (_) {}
    }
    notifyListeners();
  }

  void setVolume(double val) {
    _volume = val.clamp(0.0, 1.0);
    if (_volume > 0) {
      _isMuted = false;
    }
    try {
      // ignore: discarded_futures
      _audioPlayer.setVolume(_isMuted ? 0.0 : _volume).catchError((_) {});
    } catch (_) {}
    notifyListeners();
  }

  void toggleMute() {
    if (_isMuted) {
      _isMuted = false;
      _volume = _prevVolume > 0 ? _prevVolume : 0.5;
    } else {
      _prevVolume = _volume;
      _isMuted = true;
    }
    try {
      // ignore: discarded_futures
      _audioPlayer.setVolume(_isMuted ? 0.0 : _volume).catchError((_) {});
    } catch (_) {}
    notifyListeners();
  }

  void toggleShuffle() {
    _isShuffle = !_isShuffle;
    notifyListeners();
  }

  void toggleRepeat() {
    switch (_repeatMode) {
      case PlaybackRepeatMode.off:
        _repeatMode = PlaybackRepeatMode.all;
        break;
      case PlaybackRepeatMode.all:
        _repeatMode = PlaybackRepeatMode.one;
        break;
      case PlaybackRepeatMode.one:
        _repeatMode = PlaybackRepeatMode.off;
        break;
    }
    notifyListeners();
  }

  void toggleLike(String songId) {
    final index = _allSongs.indexWhere((s) => s.id == songId);
    if (index != -1) {
      _allSongs[index].isLiked = !_allSongs[index].isLiked;
      notifyListeners();
    }
  }

  /// Call whenever songs are added to or removed from [_allSongs].
  void _markSongsChanged() {
    _songsRevision++;
  }

  Song? songById(String id) {
    if (_indexedSongsRevision != _songsRevision) {
      _songIndex.clear();
      // Keep the first occurrence for duplicate ids, matching the previous
      // linear scan.
      for (final song in _allSongs) {
        _songIndex.putIfAbsent(song.id, () => song);
      }
      _indexedSongsRevision = _songsRevision;
    }
    return _songIndex[id];
  }

  void addToQueue(Song song) {
    _queue.add(song);
    notifyListeners();
  }

  void enqueue(Song song) => addToQueue(song);

  void enqueueNext(Song song) {
    if (_queue.isEmpty || _currentIndex < 0 || _currentIndex >= _queue.length) {
      _queue.add(song);
    } else {
      _queue.insert(_currentIndex + 1, song);
    }
    notifyListeners();
  }

  void enqueueList(List<Song> songs) {
    _queue.addAll(songs);
    notifyListeners();
  }

  void removeFromQueue(int index) {
    if (index >= 0 && index < _queue.length && _queue.length > 1) {
      if (index == _currentIndex) {
        next();
      }
      _queue.removeAt(index);
      if (_currentIndex >= _queue.length) {
        _currentIndex = _queue.length - 1;
      }
      notifyListeners();
    }
  }

  /// Load and play the current song's audio URL or asset.
  /// Resolves the optimal AudioSource for [song] with multi-tier resilience:
  /// 1. Cached offline audio file on disk
  /// 2. Local audio file on disk
  /// 3. Bundled asset in app package (direct asset URI or extracted file)
  /// 4. Remote HTTP stream (if online and not expired)
  /// 5. Bundled offline fallback asset
  Future<AudioSource> _resolveAudioSource(
    Song song,
    MediaItem mediaItem, {
    bool forceAsset = false,
  }) async {
    // Drop unplayable .m3u8 or expired googlevideo streams so ExoPlayer is never sent unplayable sources
    if (song.audioUrl.toLowerCase().contains('.m3u8') ||
        (song.audioUrl.contains('googlevideo.com') &&
            _isGoogleVideoExpired(song.audioUrl))) {
      song.audioUrl = '';
      song.isYouTubeAudio = true;
      song.isPreview = false;
    }

    // 0. Dedicated check for Lips of an Angel: use bundled high-fidelity asset (4:21 full track)
    if (!forceAsset &&
        !song.id.startsWith('spotify-') &&
        !song.id.startsWith('itunes-') &&
        song.title.toLowerCase().contains('lips of an angel')) {
      final matching = _cleanAssetUri(_getOfflineAssetFallback(song));
      if (matching.isNotEmpty) {
        final extracted = await _extractAssetToFile(matching);
        if (File(extracted).existsSync() &&
            File(extracted).lengthSync() > 1024) {
          song.audioUrl = extracted;
          song.duration = const Duration(minutes: 4, seconds: 21);
          song.isPreview = false;
          song.isYouTubeAudio = false;
          _offlineFallbackIds.remove(song.id);
          _syncSongPathToQueueAndDb(song);
          return AudioSource.file(extracted, tag: mediaItem);
        }
      }
    }

    // 1. Cached offline audio file on disk
    if (!forceAsset) {
      final cached = await _findCachedAudioFile(song.id);
      if (cached != null && cached.existsSync() && cached.lengthSync() > 1024) {
        song.audioUrl = cached.path;
        final isComplete = await _isCompleteOfflineFile(song.id, cached);
        song.isPreview = !isComplete;
        song.isYouTubeAudio = false;
        _offlineFallbackIds.remove(song.id);
        _syncSongPathToQueueAndDb(song);
        return AudioSource.file(cached.path, tag: mediaItem);
      }
    }

    // 2. Local audio file on disk
    if (!forceAsset &&
        song.audioUrl.isNotEmpty &&
        !song.audioUrl.startsWith('http://') &&
        !song.audioUrl.startsWith('https://') &&
        !song.audioUrl.startsWith('assets/') &&
        !song.audioUrl.startsWith('asset:/')) {
      final f = File(song.audioUrl);
      if (f.existsSync() && f.lengthSync() > 1024) {
        return AudioSource.file(f.path, tag: mediaItem);
      } else {
        final cachedOnDevice = await _findCachedAudioFile(song.id);
        if (cachedOnDevice != null &&
            cachedOnDevice.existsSync() &&
            cachedOnDevice.lengthSync() > 1024) {
          song.audioUrl = cachedOnDevice.path;
          final isComplete =
              await _isCompleteOfflineFile(song.id, cachedOnDevice);
          song.isPreview = !isComplete;
          song.isYouTubeAudio = false;
          _syncSongPathToQueueAndDb(song);
          return AudioSource.file(cachedOnDevice.path, tag: mediaItem);
        } else {
          // Reset stale/preview path so remote playback or online enrichment can execute!
          song.audioUrl = '';
          song.isYouTubeAudio = true;
          song.isPreview = false;
        }
      }
    }

    // 3. Bundled asset in app package
    if (!forceAsset &&
        (song.audioUrl.startsWith('assets/') ||
            song.audioUrl.startsWith('asset:/'))) {
      final clean = _cleanAssetUri(song.audioUrl);
      final extracted = await _extractAssetToFile(clean);
      if (File(extracted).existsSync() && File(extracted).lengthSync() > 1024) {
        return AudioSource.file(extracted, tag: mediaItem);
      }
      return AudioSource.uri(Uri.parse('asset:///$clean'), tag: mediaItem);
    }

    // 4. Remote HTTP stream or opportunistic online enrichment
    if (!forceAsset &&
        (song.audioUrl.isEmpty ||
            song.audioUrl.startsWith('http://') ||
            song.audioUrl.startsWith('https://'))) {
      final online = await _isDeviceOnline();
      if (online) {
        final needsFreshAudio =
            song.audioUrl.isEmpty ||
            song.isPreview ||
            song.audioUrl.contains('googlevideo.com') ||
            song.audioUrl.toLowerCase().contains('.m3u8') ||
            _isGoogleVideoExpired(song.audioUrl);

        if (needsFreshAudio) {
          if (song.audioUrl.isEmpty || song.isPreview) {
            // Track with no full audio or on preview: prioritize resolving full-length track
            final fullPass = _ensureEnrichment(song, fastImport: true);
            try {
              await fullPass.timeout(const Duration(seconds: 12));
            } catch (_) {}
            // The URL is read below, so a hot-swap queued while we waited
            // would only reload the same source a second later if full audio already landed.
            if (currentSong?.id == song.id &&
                song.audioUrl.isNotEmpty &&
                !song.isPreview) {
              _pendingHotSwapReload = false;
            }
          } else {
            unawaited(_ensureEnrichment(song, fastImport: true));
          }
        }
        if (song.audioUrl.isNotEmpty &&
            !song.audioUrl.toLowerCase().contains('.m3u8')) {
          unawaited(_cacheAudioOffline(song));
        }
        if (song.audioUrl.isNotEmpty &&
            !song.audioUrl.toLowerCase().contains('.m3u8') &&
            (song.audioUrl.startsWith('http://') ||
                song.audioUrl.startsWith('https://'))) {
          final isGv = song.audioUrl.contains('googlevideo.com');
          return AudioSource.uri(
            Uri.parse(song.audioUrl),
            headers: {
              'User-Agent': isGv
                  ? TrackEnrichmentService.ytAndroidUserAgent
                  : TrackEnrichmentService.browserUserAgent,
            },
            tag: mediaItem,
          );
        }
      }
    }

    // 5. Offline fallback asset (only if an asset actually matches this song and is not imported)
    if (!song.id.startsWith('spotify-') && !song.id.startsWith('itunes-')) {
      final fallbackAsset = _cleanAssetUri(_getOfflineAssetFallback(song));
      if (fallbackAsset.isNotEmpty) {
        _offlineFallbackIds.add(song.id);
        final extracted = await _extractAssetToFile(fallbackAsset);
        if (File(extracted).existsSync() &&
            File(extracted).lengthSync() > 1024) {
          return AudioSource.file(extracted, tag: mediaItem);
        }
        return AudioSource.uri(
          Uri.parse('asset:///$fallbackAsset'),
          tag: mediaItem,
        );
      }
    }

    if (song.audioUrl.isNotEmpty &&
        !song.audioUrl.toLowerCase().contains('.m3u8') &&
        (song.audioUrl.startsWith('http://') ||
            song.audioUrl.startsWith('https://'))) {
      final isGv = song.audioUrl.contains('googlevideo.com');
      return AudioSource.uri(
        Uri.parse(song.audioUrl),
        headers: {
          'User-Agent': isGv
              ? TrackEnrichmentService.ytAndroidUserAgent
              : TrackEnrichmentService.browserUserAgent,
        },
        tag: mediaItem,
      );
    }

    throw StateError('No audio source available for ${song.title}');
  }

  /// Load and play the current song's audio URL or asset.
  ///
  /// Multi-tier resilience ensures imported Spotify playlists across all accounts
  /// produce real, audible, high-fidelity sound through speakers/headphones
  /// while keeping the progress slider and lyrics tracker in perfect real-time sync.
  Future<void> _playCurrentSongAudio() async {
    final song = currentSong;
    if (song == null) return;
    if (_isExplicitBlocked(song)) {
      _isPlaying = false;
      _notifyExplicitBlocked(song);
      return;
    }
    if (_isPlayingAudioInProgress) {
      // A different song was requested (skip / previous / tap) while another
      // load is still running. Previously this returned silently, so the new
      // song never loaded and the old attempt finished against the old song:
      // muted, frozen slider, frozen lyrics. Supersede the old attempt and
      // have its `finally` block start the current song.
      final loadingId = _loadingSongId;
      if (loadingId != null && loadingId != song.id) {
        _playSessionId++;
        _pendingHotSwapReload = true;
        _pendingHotSwapResumePosition = Duration.zero;
        _audioPlayerHasSource = false;
        _logDiag(
          'play superseded by a newer request — aborting old load',
          song: song,
        );
        try {
          // ignore: discarded_futures
          _audioPlayer.stop().catchError((_) {});
        } catch (_) {}
      }
      return;
    }
    _isPlayingAudioInProgress = true;
    _loadingSongId = song.id;
    _unavailableIds.remove(song.id);

    final sessionId = ++_playSessionId;

    try {
      // Library tracks are imported and resolve their audio at play time.
      // Until the new source loads, the player still holds the PREVIOUS track:
      // its position kept feeding the new song's progress slider and lyrics
      // tracker (stuck / wrong) and its volume state leaked into the new track.
      // Drop it first. Bundled songs resolve instantly and are left as they are.
      if (_isDownloadableCatalogId(song.id)) {
        _audioPlayerHasSource = false;
        try {
          await _audioPlayer.stop().timeout(const Duration(seconds: 1));
        } catch (_) {}
      }
      if (sessionId != _playSessionId || _disposed) return;

      final playStart = DateTime.now();
      _logDiag('PLAY REQUESTED', song: song);
      final online = await _isDeviceOnline();
      _logDiag(
        'online=$online',
        song: song,
        since: DateTime.now().difference(playStart),
      );

      // Opportunistic upgrade: if online and song is on fallback or preview,
      // fire background enrichment without blocking audible playback.
      final isLipsOfAnAngel = song.title.toLowerCase().contains(
        'lips of an angel',
      );
      final needsUpgrade =
          !isLipsOfAnAngel &&
          (song.isSilentPlaceholder ||
              song.audioUrl.isEmpty ||
              song.isPreview ||
              song.audioUrl.contains('googlevideo.com') ||
              song.audioUrl.toLowerCase().contains('.m3u8') ||
              _isGoogleVideoExpired(song.audioUrl));

      if (online && needsUpgrade && !_enrichingIds.contains(song.id)) {
        // Fire-and-forget. Awaiting enrichment here blocked playback for up to
        // 12s before setAudioSource() even ran, which is the ~10s "delay then
        // play" the user sees on imported Spotify tracks. The resolved
        // full-track URL hot-swaps in via _applyEnrichment when it lands.
        // ignore: discarded_futures
        _ensureEnrichment(song, fastImport: true);
      }

      // Ensure audioUrl is valid (check for empty or deleted local file paths)
      final isLocalPath =
          song.audioUrl.isNotEmpty &&
          !song.audioUrl.startsWith('http://') &&
          !song.audioUrl.startsWith('https://') &&
          !song.audioUrl.startsWith('assets/') &&
          !song.audioUrl.startsWith('asset:/');
      if (song.audioUrl.toLowerCase().contains('.m3u8') ||
          (song.audioUrl.contains('googlevideo.com') &&
              _isGoogleVideoExpired(song.audioUrl))) {
        song.audioUrl = '';
        song.isYouTubeAudio = true;
        song.isPreview = false;
      }
      if (song.audioUrl.isEmpty ||
          (isLocalPath && !File(song.audioUrl).existsSync())) {
        final cached = await _findCachedAudioFile(song.id);
        if (cached != null &&
            cached.existsSync() &&
            cached.lengthSync() > 1024) {
          song.audioUrl = cached.path;
          _offlineFallbackIds.remove(song.id);
        } else {
          final fallback = _cleanAssetUri(_getOfflineAssetFallback(song));
          if (fallback.isNotEmpty) {
            song.audioUrl = fallback;
            _offlineFallbackIds.add(song.id);
          } else {
            song.audioUrl = '';
          }
        }
      }

      _ensureOfflineLyrics(song);

      final mediaItem = await _createSafeMediaItem(song);
      final audioSource = await _resolveAudioSource(song, mediaItem);
      // The user skipped while the source was resolving: never load the old
      // song's source over the new request.
      if (sessionId != _playSessionId || _disposed) return;
      _logDiag(
        'source resolved, loading',
        song: song,
        since: DateTime.now().difference(playStart),
      );
      unawaited(_logPlaybackDiagnostics('PRE-LOAD', song));

      final loadStart = DateTime.now();
      try {
        await _audioPlayer
            .setAudioSource(audioSource)
            .timeout(const Duration(seconds: 8));
        _logDiag(
          'setAudioSource OK in ${DateTime.now().difference(loadStart).inMilliseconds}ms',
          song: song,
        );
        _audioPlayerHasSource = true;
        _clearSilentRetry();
      } on MissingPluginException {
        _audioPlayerHasSource = false;
      } catch (loadErr) {
        // Aborted because a newer play request superseded this one: skip the
        // slow online recovery chain, the new attempt takes over.
        if (sessionId != _playSessionId || _disposed) return;
        _logDiag(
          'setAudioSource FAILED in ${DateTime.now().difference(loadStart).inMilliseconds}ms: $loadErr',
          song: song,
        );
        debugPrint(
          '[MusicPlayerController] Primary setAudioSource failed ($loadErr)',
        );
        var recovered = false;

        // Re-resolve the stream: a fresh full-length source first (Saavn →
        // YouTube → web search), preview-only as a last resort.
        final online = await _isDeviceOnline();
        _logDiag('recovery: online=$online', song: song);
        if (online) {
          debugPrint(
            '[MusicPlayerController] Attempting stream fallback recovery for ${song.title}...',
          );
          try {
            try {
              await _audioPlayer.stop();
            } catch (_) {}
            // Share the in-flight pass when one exists so recovery never pays
            // for a second lookup on top of the one already running.
            final failedUrl = song.audioUrl;
            final failedVideoId = song.youtubeVideoId;
            _enrichment.clearGooglevideoThrottle();
            song.audioUrl = '';
            song.youtubeVideoId =
                ''; // Clear failed video ID so recovery doesn't loop
            // Bound the whole re-resolve: the inner chain can otherwise run
            // up to ~35s with the player silent and the slider frozen.
            await _ensureRecoverableAudio(
              song,
              failedUrl: failedUrl,
              failedVideoId: failedVideoId,
            ).timeout(const Duration(seconds: 12), onTimeout: () {});
            if (sessionId != _playSessionId || _disposed) return;
            final retryUrl = song.audioUrl;
            // Retry whatever the resolve produced.
            if (retryUrl.isNotEmpty &&
                !retryUrl.toLowerCase().contains('.m3u8') &&
                retryUrl != failedUrl) {
              final isGv = retryUrl.contains('googlevideo.com');
              final retrySource = AudioSource.uri(
                Uri.parse(retryUrl),
                headers: {
                  'User-Agent': isGv
                      ? TrackEnrichmentService.ytAndroidUserAgent
                      : TrackEnrichmentService.browserUserAgent,
                },
                tag: mediaItem,
              );
              await _audioPlayer
                  .setAudioSource(retrySource)
                  .timeout(const Duration(seconds: 8));
              _audioPlayerHasSource = true;
              recovered = true;
              // Crucial: clear pending hot swap so finally block does not trigger a duplicate reload
              _pendingHotSwapReload = false;
              _logDiag('recovery: retried fresh URL and it loaded', song: song);
            } else {
              _logDiag(
                'recovery: no fresh URL (retryUrl=${retryUrl.isEmpty ? "empty" : "same-failed"})',
                song: song,
              );
            }
          } catch (err) {
            debugPrint('[MusicPlayerController] Live fallback failed: $err');
            _logDiag('recovery: retry threw — $err', song: song);
          }
        } else {
          _logDiag('recovery SKIPPED — device reported offline', song: song);
        }

        if (!recovered) {
          final matchingAsset = _cleanAssetUri(_getOfflineAssetFallback(song));
          _logDiag(
            'recovery: asset=${matchingAsset.isEmpty ? "none" : matchingAsset}',
            song: song,
          );
          if (matchingAsset.isNotEmpty) {
            _offlineFallbackIds.add(song.id);
            try {
              await _audioPlayer.stop();
            } catch (_) {}
            try {
              final fallbackSource = await _resolveAudioSource(
                song,
                mediaItem,
                forceAsset: true,
              );
              await _audioPlayer
                  .setAudioSource(fallbackSource)
                  .timeout(const Duration(seconds: 6));
              _audioPlayerHasSource = true;
              recovered = true;
            } catch (fbErr) {
              debugPrint(
                '[MusicPlayerController] Fallback setAudioSource failed: $fbErr',
              );
              _audioPlayerHasSource = false;
            }
          } else {
            _audioPlayerHasSource = false;
          }
        }
      }

      if (sessionId != _playSessionId) {
        _logDiag(
          'session superseded ($sessionId != $_playSessionId) — abandoning attempt',
          song: song,
        );
        return;
      }

      _ytRefreshAttemptedIds.remove(song.id);
      _playbackTimer?.cancel();

      _unmuteOnPlay();
      _activateAudioSession();
      _lastPositionUpdate = DateTime.now();
      final effectiveVolume = _isMuted ? 0.0 : (_volume > 0.05 ? _volume : 0.8);
      try {
        await _audioPlayer.setVolume(effectiveVolume);
      } catch (_) {}

      if (_isPlaying) {
        _startTimer();
        if (_audioPlayerHasSource) {
          try {
            unawaited(
              _audioPlayer.play().catchError((playErr) {
                debugPrint('[MusicPlayerController] play() error: $playErr');
                // ignore: discarded_futures
                _handleAudioLoadFailure(song);
              }),
            );
            if (sessionId == _playSessionId) {
              try {
                await _audioPlayer.setVolume(effectiveVolume);
              } catch (_) {}
              _scheduleVolumeReasserts();
              _preloadNextQueueSong();
            }
          } catch (playErr) {
            debugPrint(
              '[MusicPlayerController] play() failed: $playErr, recovering…',
            );
            await _handleAudioLoadFailure(song);
          }
        } else {
          _cancelStallWatchdog();
          _startTimer();
          _logDiag(
            'no source after recovery — scheduling silent retry',
            song: song,
          );
          _scheduleSilentRetry(song, sessionId);
        }
      }
    } catch (e) {
      if (sessionId != _playSessionId || _disposed) return;
      debugPrint('Audio playback load error for ${song.title}: $e');
      await _handleAudioLoadFailure(song);
    } finally {
      _isPlayingAudioInProgress = false;
      _loadingSongId = null;
      _logDiag(
        'play attempt finished: hasSource=$_audioPlayerHasSource '
        'session=$sessionId/$_playSessionId playing=$_isPlaying '
        'pendingSwap=$_pendingHotSwapReload',
        song: song,
      );

      // A full-track enrichment arrived while we were mid-load and was
      // deferred. Now that we are done, honour it so the new URL actually
      // gets loaded instead of leaving the player on the old source.
      if (_pendingHotSwapReload && !_disposed) {
        _pendingHotSwapReload = false;
        _isPlaying = true;
        final resumePos = _pendingHotSwapResumePosition;
        _pendingHotSwapResumePosition = Duration.zero;
        _logDiag('executing deferred hot-swap reload', song: song);
        _unmuteOnPlay();
        _lastPositionUpdate = DateTime.now();
        _startTimer();
        // ignore: discarded_futures
        _playCurrentSongAudio().then((_) {
          if (resumePos > Duration.zero) {
            seekTo(resumePos);
          }
        });
      }
    }
  }

  void _preloadNextQueueSong() {
    if (_queue.isEmpty ||
        _currentIndex < 0 ||
        _currentIndex >= _queue.length - 1) {
      return;
    }
    final nextSong = _queue[_currentIndex + 1];
    if (needsFullTrack(nextSong)) {
      if (!_enrichingIds.contains(nextSong.id) &&
          !_pendingEnrichment.containsKey(nextSong.id)) {
        // ignore: discarded_futures
        _ensureEnrichment(nextSong, fastImport: true);
      }
    }
  }

  /// Shared recovery for sync load errors and async media failures.
  Future<void> _handleAudioLoadFailure(Song song) async {
    if (_disposed || song.id != currentSong?.id) return;
    _cancelStallWatchdog();
    _logDiag('AUDIO LOAD FAILURE RECOVERY ENTERED', song: song);

    // Prevent redundant recovery loops if already running fallback with active source
    if (_offlineFallbackIds.contains(song.id) && _audioPlayerHasSource) {
      return;
    }

    // 1. Check if offline cached file exists before trying online recovery
    final cached = await _findCachedAudioFile(song.id);
    if (cached != null &&
        song.audioUrl != cached.path &&
        cached.existsSync() &&
        cached.lengthSync() > 1024) {
      debugPrint('Recovering with offline cached file: ${cached.path}');
      song.audioUrl = cached.path;
      _offlineFallbackIds.remove(song.id);
      _syncSongPathToQueueAndDb(song);
      if (song.id == currentSong?.id) {
        await _playCurrentSongAudio();
        return;
      }
    }

    // 2. Online stream recovery: if connected, try to refresh full stream
    final online = await _isDeviceOnline();
    if (online && !_ytRefreshAttemptedIds.contains(song.id)) {
      _ytRefreshAttemptedIds.add(song.id);
      try {
        final failedUrl = song.audioUrl;
        final failedVideoId = song.youtubeVideoId;
        song.audioUrl = '';
        song.youtubeVideoId =
            ''; // Clear failed video ID to break infinite recovery loops
        try {
          await _ensureRecoverableAudio(
            song,
            failedUrl: failedUrl,
            failedVideoId: failedVideoId,
          );
        } catch (_) {}
        if (song.audioUrl.isNotEmpty &&
            !song.audioUrl.toLowerCase().contains('.m3u8')) {
          if (song.id == currentSong?.id) {
            await _playCurrentSongAudio();
            return;
          }
        }
      } catch (_) {}
    }

    // 3. Offline Fallback: Only play bundled audio if a genuine matching asset exists for THIS song (title match)
    final matchingAsset = _cleanAssetUri(_getOfflineAssetFallback(song));
    if (matchingAsset.isNotEmpty) {
      try {
        _offlineFallbackIds.add(song.id);
        final mediaItem = await _createSafeMediaItem(song);
        _ensureOfflineLyrics(song);

        try {
          await _audioPlayer.stop();
        } catch (_) {}

        final fallbackSource = await _resolveAudioSource(
          song,
          mediaItem,
          forceAsset: true,
        );
        await _audioPlayer
            .setAudioSource(fallbackSource)
            .timeout(const Duration(seconds: 6));
        _audioPlayerHasSource = true;
        _lastPositionUpdate = DateTime.now();
        _unmuteOnPlay();
        _activateAudioSession();
        final effectiveVolume = _isMuted
            ? 0.0
            : (_volume > 0.05 ? _volume : 0.8);
        await _audioPlayer.setVolume(effectiveVolume);
        if (_isPlaying) {
          if (_currentPosition > Duration.zero &&
              _currentPosition < currentDuration) {
            try {
              await _audioPlayer.seek(_currentPosition);
            } catch (_) {}
          }
          unawaited(_audioPlayer.play().catchError((_) {}));
          _scheduleVolumeReasserts();
        }
        _startTimer();
        notifyListeners();
      } catch (err) {
        debugPrint(
          '[MusicPlayerController] Fallback asset recovery failed: $err',
        );
        _audioPlayerHasSource = false;
        notifyListeners();
      }
    } else {
      // No cached file, no working stream, and no matching bundled asset:
      // there is genuinely nothing to play. Reset playing flag and timers so UI
      // does not freeze in an artificial playing-yet-stuck state.
      _audioPlayerHasSource = false;
      _playbackTimer?.cancel();
      _cancelStallWatchdog();
      _logDiag(
        'NO AUDIO SOURCE AVAILABLE (no cache, no stream, no asset)',
        song: song,
      );
      _markUnavailable(song);

      // If we were actively playing, automatically skip to the next playable track
      // instead of remaining stalled in an unplayable locating state.
      if (_isPlaying && _queue.isNotEmpty) {
        _logDiag(
          'Auto-skipping unplayable locating track to next playable song',
          song: song,
        );
        next();
        return;
      }

      _isPlaying = false;
      notifyListeners();
    }
  }

  /// Called when audio completes a song
  void _onSongComplete() {
    if (_completionHandled) {
      // The heartbeat timer and the native player-state stream can both report
      // the same completion. Advancing twice skipped a real full track
      // (Lil Kasalanan Shortie -> Babaero -> Burgis).
      _logDiag('duplicate completion signal ignored');
      return;
    }
    _completionHandled = true;
    if (_repeatMode == PlaybackRepeatMode.one) {
      _currentPosition = Duration.zero;
      _playCurrentSongAudio();
      _startTimer();
      notifyListeners();
      return;
    }
    final song = currentSong;
    // A 30s preview just ended: go to this song's full track audio first
    // instead of skipping to the next song.
    if (song != null && (song.isPreview || needsFullTrack(song))) {
      // ignore: discarded_futures
      _proceedToFullTrack(song);
      return;
    }
    next(fromCompletion: true);
  }

  final Set<String> _fullTrackHandoffIds = {};

  /// The preview indicator ended (or was skipped): resolve the full track
  /// audio and continue the same song from where the preview stopped.
  /// [_applyEnrichment] hot-swaps the full audio in and resumes in place.
  /// Only when no full audio exists does playback move to the next full track.
  Future<void> _proceedToFullTrack(Song song) async {
    if (!_fullTrackHandoffIds.add(song.id)) return;
    try {
      _fullUpgradeAttemptedAt.remove(song.id);
      try {
        await _ensureEnrichment(song).timeout(const Duration(seconds: 12));
      } catch (_) {}
    } finally {
      _fullTrackHandoffIds.remove(song.id);
    }
    if (_disposed || currentSong?.id != song.id) return;
    if (needsFullTrack(song)) {
      _logDiag('no full track yet — skipping to next full track', song: song);
      next(fromCompletion: true);
    } else {
      _logDiag('preview -> full track audio', song: song);
      _currentPosition = Duration.zero;
      _audioDuration = Duration.zero;
      _isPlaying = true;
      _unmuteOnPlay();
      _playCurrentSongAudio();
    }
  }

  /// RELIABILITY HARDWARE — TEMPORARY DIAGNOSTICS.
  ///
  /// Mute-vs-no-source was ambiguous because the UI fabricated playback
  /// progress while no audio existed, so "silent" was indistinguishable from
  /// "playing quietly". This one switch prints everything needed to tell them
  /// apart in a single test play. Remove once the device confirms the cause.
  static const bool _diagEnabled = true;

  void _logDiag(String message, {Song? song, Duration? since}) {
    if (!_diagEnabled) return;
    final s = song ?? currentSong;
    final pos = since != null ? ' (+${since.inMilliseconds}ms)' : '';
    debugPrint(
      '[MusicDiag]$pos $message'
      '${s == null ? '' : ' | ${s.title} / ${s.artist}'}',
    );
  }

  /// Host portion of a URL, for diagnostics only.
  static String _hostOf(String? url) {
    if (url == null || url.isEmpty) return 'none';
    if (!url.startsWith('http')) return 'non-http';
    return Uri.tryParse(url)?.host ?? 'unparsable';
  }

  /// Dump every value that distinguishes "volume is zero" from "nothing loaded".
  Future<void> _logPlaybackDiagnostics(String label, Song song) async {
    if (!_diagEnabled) return;
    double nativeVol = -1;
    try {
      nativeVol = _audioPlayer.volume;
    } catch (_) {}
    var sessionActive = false;
    try {
      await AudioSession.instance;
      sessionActive = _audioFocusRequested;
    } catch (_) {}
    final url = song.audioUrl;
    String host = 'none';
    if (url.startsWith('http')) {
      host = Uri.tryParse(url)?.host ?? 'unparsable';
    } else if (url.isEmpty) {
      host = 'EMPTY';
    } else if (url.startsWith('assets/') || url.startsWith('asset:/')) {
      host = 'bundled-asset';
    } else {
      host = 'local-file';
    }
    Duration nativeDuration = Duration.zero;
    try {
      nativeDuration = _audioPlayer.duration ?? Duration.zero;
    } catch (_) {}
    _logDiag(
      '$label -> source=$host hasSource=$_audioPlayerHasSource '
      'preview=${song.isPreview} yt=${song.isYouTubeAudio} '
      'nativeVol=$nativeVol effectiveVol=${_effectiveVolume.toStringAsFixed(2)} '
      'muted=$_isMuted uiVol=${_volume.toStringAsFixed(2)} '
      'sessionActive=$sessionActive '
      'nativeDur=${nativeDuration.inSeconds}s expectedDur=${song.duration.inSeconds}s',
    );
  }

  /// Reliable playback heartbeat timer and lyrics tracker.
  ///
  /// Historically this synthesized `_currentPosition` whenever the native
  /// stream wasn't emitting ticks. That made a track with **no audio at all**
  /// look like it was playing: the slider slid and lyrics scrolled for the
  /// full song duration while nothing was audible. Interpolation is now only
  /// allowed once real audio has actually produced a position, so a dead
  /// source surfaces honestly instead of masquerading as playback.
  void _startTimer() {
    _playbackTimer?.cancel();
    _playbackTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!_isPlaying) {
        timer.cancel();
        return;
      }

      // If audio load is actively in progress, pause timer briefly until resolved
      if (!_audioPlayerHasSource && _isPlayingAudioInProgress) {
        return;
      }

      // If native player's position stream emitted a fresh update within the last 1200ms,
      // native audio is actively driving the position.
      final lastUpdate = _lastPositionUpdate;
      final isNativeAdvancing =
          lastUpdate != null &&
          DateTime.now().difference(lastUpdate) <
              const Duration(milliseconds: 1200);

      if (!isNativeAdvancing) {
        // Never fake progress for a source that never produced audio. Wait for
        // real ticks (or the stall watchdog) instead of inventing them.
        if (!_audioPlayerHasSource || lastUpdate == null) {
          return;
        }

        // Only bridge the gap between ticks while the native player is truly
        // playing. During a buffering stall or a lost audio focus it is not,
        // and interpolating then made the slider and lyrics keep moving over
        // silence. Instead make sure the stall watchdog is armed so the track
        // recovers rather than looking alive.
        var nativeReady = true;
        var nativeLoading = false;
        try {
          final ps = _audioPlayer.playerState;
          nativeReady =
              ps.playing && ps.processingState == ProcessingState.ready;
          nativeLoading =
              ps.processingState == ProcessingState.buffering ||
              ps.processingState == ProcessingState.loading;
        } catch (_) {}
        if (!nativeReady) {
          // Stuck loading/buffering: arm recovery. Ready-but-paused means the
          // system paused us (audio focus); the interruption listener resumes
          // it, so it must not be treated as a dead stream.
          if (nativeLoading && _stallWatchdog?.isActive != true) {
            _startStallWatchdog();
          }
          return;
        }

        // Native stream is temporarily between position ticks.
        // Smoothly interpolate currentPosition while bounded by actual duration.
        if (_currentPosition < currentDuration) {
          _currentPosition += const Duration(milliseconds: 500);
          if (_currentPosition > currentDuration) {
            _currentPosition = currentDuration;
          }
          _positionNotifier.value = _currentPosition;
        } else {
          timer.cancel();
          _onSongComplete();
        }
      }
    });
  }

  /// Retries a play attempt that ended with **no source at all**.
  ///
  /// One failed `setAudioSource` used to leave the player reporting "playing"
  /// with nothing behind it: the progress slider sat at 0:00, the lyrics
  /// tracker never advanced and no sound came out — for the rest of the song.
  /// Three tries, three seconds apart, give a slow enrichment or a flaky
  /// resolver time to land while still giving up quickly on a track that is
  /// genuinely unplayable.
  Timer? _silentRetryTimer;
  String? _silentRetrySongId;
  int _silentRetryCount = 0;

  void _scheduleSilentRetry(Song song, int sessionId) {
    if (!_isPlaying || _disposed) {
      _logDiag('silent retry NOT scheduled — not playing', song: song);
      return;
    }
    if (song.id != currentSong?.id) return;
    if (_silentRetrySongId != song.id) {
      _silentRetrySongId = song.id;
      _silentRetryCount = 0;
    }
    if (_silentRetryCount >= 3) {
      // Out of retries: show "can't play" instead of a silent frozen player.
      _markUnavailable(song);
      return;
    }
    _silentRetryCount += 1;
    final attempt = _silentRetryCount;
    _logDiag('silent retry #$attempt scheduled in 3s', song: song);
    _silentRetryTimer?.cancel();
    _silentRetryTimer = Timer(const Duration(seconds: 3), () {
      if (_disposed || sessionId != _playSessionId) return;
      if (_audioPlayerHasSource || !_isPlaying) return;
      if (currentSong?.id != song.id) return;
      _logDiag(
        'silent retry #$attempt — no source yet, re-resolving',
        song: song,
      );
      // ignore: discarded_futures
      _playCurrentSongAudio();
    });
  }

  /// Drops any pending silent retry and returns the per-song retry budget.
  void _clearSilentRetry() {
    _silentRetryTimer?.cancel();
    _silentRetryTimer = null;
    _silentRetrySongId = null;
    _silentRetryCount = 0;
  }

  /// Watches for an audio stream stuck in buffering/loading. If no position
  /// progress arrives within 8s while playing a remote stream, recover to a bundled
  /// local asset so the user is never left muted with a frozen player.
  /// Local files and assets decode cleanly without network stalls and bypass watchdog.
  void _startStallWatchdog() {
    _cancelStallWatchdog();
    final song = currentSong;
    if (song == null) return;

    // Local assets and local files decode without network stalls; watchdog not needed
    if (_offlineFallbackIds.contains(song.id) ||
        song.audioUrl.startsWith('assets/') ||
        song.audioUrl.startsWith('asset:/') ||
        (song.audioUrl.isNotEmpty &&
            !song.audioUrl.startsWith('http://') &&
            !song.audioUrl.startsWith('https://'))) {
      return;
    }

    final startedAt = DateTime.now();
    _lastPositionUpdate ??= startedAt;
    _stallWatchdog = Timer.periodic(const Duration(milliseconds: 1000), (
      timer,
    ) {
      if (_disposed || !_isPlaying || song.id != currentSong?.id) {
        timer.cancel();
        return;
      }
      final last = _lastPositionUpdate;
      final stalled =
          last == null ||
          DateTime.now().difference(last) > const Duration(milliseconds: 3500);
      final elapsed = DateTime.now().difference(startedAt);
      if (stalled && elapsed > const Duration(milliseconds: 3500)) {
        timer.cancel();
        debugPrint(
          '[MusicPlayerController] Stall detected for ${song.title} (${elapsed.inSeconds}s), recovering…',
        );
        // ignore: discarded_futures
        _handleAudioLoadFailure(song);
      }
      if (elapsed > const Duration(seconds: 45)) {
        timer.cancel();
      }
    });
  }

  void _cancelStallWatchdog() {
    _stallWatchdog?.cancel();
    _stallWatchdog = null;
  }

  bool _disposed = false;

  @override
  void notifyListeners() {
    if (_disposed) return;
    final binding = WidgetsBinding.instance;
    if (binding.buildOwner?.debugBuilding == true ||
        binding.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      binding.addPostFrameCallback((_) {
        if (!_disposed) {
          _syncPositionNotifier();
          super.notifyListeners();
        }
      });
      return;
    }
    _syncPositionNotifier();
    super.notifyListeners();
  }

  void _syncPositionNotifier() {
    if (_positionNotifier.value != _currentPosition) {
      _positionNotifier.value = _currentPosition;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final task in _downloadQueue) {
      for (final c in task.completers) {
        if (!c.isCompleted) c.complete(false);
      }
    }
    _downloadQueue.clear();
    for (final completers in _inFlightCompleters.values) {
      for (final c in completers) {
        if (!c.isCompleted) c.complete(false);
      }
    }
    _inFlightCompleters.clear();
    _playbackTimer?.cancel();
    _silentRetryTimer?.cancel();
    _importRetryTimer?.cancel();
    _connectivityTimer?.cancel();
    _interruptionSub?.cancel();
    _noisySub?.cancel();
    _stallWatchdog?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playerStateSub?.cancel();
    _playbackEventSub?.cancel();
    _audioSessionSub?.cancel();
    _equalizer.dispose();
    _enrichment.dispose();
    _positionNotifier.dispose();
    // Only unbind if the notification still points at this controller; a
    // newer instance may already have replaced these handlers.
    if (identical(_notificationController, this)) {
      _notificationController = null;
      JustAudioBackground.onSkipToNext = null;
      JustAudioBackground.onSkipToPrevious = null;
    }
    try {
      // ignore: discarded_futures
      _audioPlayer.dispose().catchError((_) {});
    } catch (_) {}
    super.dispose();
  }
}
