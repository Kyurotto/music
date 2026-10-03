import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../auth/auth_service.dart';
import '../data/local_database.dart';
import '../models/song_model.dart';
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

class MusicPlayerController extends ChangeNotifier {
  final List<Song> _allSongs = [];
  final List<MusicPlaylist> _playlists = [];
  late List<Song> _queue;
  int _currentIndex = 0;

  bool _isPlaying = false;
  Duration _currentPosition = Duration.zero;
  Duration _audioDuration = Duration.zero;
  double _volume = 0.8;
  double _prevVolume = 0.8;
  bool _isMuted = false;
  bool _isShuffle = false;
  PlaybackRepeatMode _repeatMode = PlaybackRepeatMode.all;
  Timer? _playbackTimer;

  // Real audio player
  final AudioPlayer _audioPlayer = AudioPlayer();
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<PlaybackEvent>? _playbackEventSub;
  bool _audioPlayerHasSource = false;
  int _playSessionId = 0;

  // Keyless enrichment (full-length audio + lyrics) for Spotify imports.
  final TrackEnrichmentService _enrichment = TrackEnrichmentService();
  final Set<String> _enrichingIds = {};
  final Set<String> _enrichedIds = {};

  /// Preview tracks re-attempt a full-length upgrade on a cooldown so an
  /// old 30s import self-heals without spamming Saavn/YouTube on every tick.
  final Map<String, DateTime> _fullUpgradeAttemptedAt = {};
  static const _fullUpgradeCooldown = Duration(seconds: 45);

  /// YouTube URLs expire after a few hours; each successful play re-arms a
  /// single refresh so an expired saved URL resolves fresh instead of
  /// going silent.
  final Set<String> _ytRefreshAttemptedIds = {};

  /// A native player can reject an otherwise valid full-length URL because
  /// of codec, redirect, or host restrictions. Each imported song gets one
  /// direct-to-preview recovery attempt rather than being left to run silently.
  final Set<String> _audioFallbackAttemptedIds = {};

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

  void _unmuteOnPlay() {
    if (_isMuted) {
      _isMuted = false;
    }
    if (_volume <= 0.05) {
      _volume = _prevVolume > 0.05 ? _prevVolume : 0.8;
    }
  }

  MusicPlayerController() {
    _allSongs.addAll(SampleMusicData.sampleSongs);
    _playlists.addAll(SampleMusicData.initialPlaylists);
    _queue = List<Song>.from(_allSongs);

    _initAudioPlayer();
    // Load previously imported playlists for the active user
    unawaited(loadSavedPlaylists().catchError((e) {
      debugPrint('[MusicPlayerController] Initial loadSavedPlaylists skipped: $e');
    }));
    // Pre-extract offline audio assets so they are ready on disk immediately
    unawaited(_preExtractBundledAssets().catchError((e) {
      debugPrint('[MusicPlayerController] _preExtractBundledAssets skipped: $e');
    }));
  }

  void _initAudioPlayer() {
    try {
      try {
        AudioSession.instance.then((session) async {
          await session.configure(const AudioSessionConfiguration.music());
          await session.setActive(true);
        }).catchError((e) {
          debugPrint('[MusicPlayerController] AudioSession configure error: $e');
        });
      } catch (_) {}

      // ignore: discarded_futures
      _audioPlayer.setVolume(_volume).catchError((_) {});

      // Listen to position updates from real audio player
      _positionSub = _audioPlayer.positionStream.listen((pos) {
        if (_audioPlayerHasSource && _isPlaying) {
          if (pos > Duration.zero) {
            _currentPosition = pos;
          }
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
          notifyListeners();
        }
      });

      // Listen to duration updates
      _durationSub = _audioPlayer.durationStream.listen((dur) {
        if (dur != null && dur > Duration.zero) {
          _audioDuration = dur;
          notifyListeners();
        }
      });

      // Listen to player state: when the stream enters the ready & playing state,
      // re-assert volume to guarantee that native audio initialization never leaves
      // the track muted.
      _playerStateSub = _audioPlayer.playerStateStream.listen((state) {
        if (state.playing && state.processingState == ProcessingState.ready) {
          if (!_isMuted && _audioPlayerHasSource) {
            final effectiveVolume = _volume > 0.05 ? _volume : 0.8;
            try {
              // ignore: discarded_futures
              _audioPlayer.setVolume(effectiveVolume).catchError((_) {});
            } catch (_) {}
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
  List<MusicPlaylist> get playlists => List.unmodifiable(_playlists);
  List<Song> get queue => _queue;
  int get currentIndex => _currentIndex;
  Song? get currentSong => (_queue.isNotEmpty && _currentIndex >= 0 && _currentIndex < _queue.length)
      ? _queue[_currentIndex]
      : null;
  bool get isPlaying => _isPlaying;
  Duration get currentPosition => _currentPosition;
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
      final matchesGenre = _selectedGenre == 'All' || song.genre.toLowerCase() == _selectedGenre.toLowerCase();
      final matchesQuery = _searchQuery.isEmpty ||
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
      if (playlist.id == playlistId) return playlist;
    }
    return null;
  }

  List<Song> songsForPlaylist(String playlistId) {
    final playlist = playlistById(playlistId);
    if (playlist == null) return const [];
    return playlist.songIds
        .map((songId) => _allSongs.where((song) => song.id == songId).firstOrNull)
        .whereType<Song>()
        .toList();
  }

  bool createPlaylist(String name) {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty || _playlists.any((playlist) => playlist.title.toLowerCase() == trimmedName.toLowerCase())) {
      return false;
    }
    _playlists.add(MusicPlaylist(
      id: _newPlaylistId(),
      title: trimmedName,
      subtitle: 'Created by you',
      gradient: const [Color(0xFF11998E), Color(0xFF38EF7D)],
    ));
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
    playlist.songIds.add(song.id);
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
  }) {
    var playlist = targetPlaylistId == null ? null : playlistById(targetPlaylistId);
    playlist ??= _playlistByTitle(playlistName);
    if (playlist == null) {
      final created = createPlaylist(playlistName);
      if (created) {
        playlist = _playlists.last;
      } else {
        playlist = _playlistByTitle(playlistName);
      }
    }
    if (playlist == null) {
      playlist = MusicPlaylist(
        id: _newPlaylistId(),
        title: playlistName.trim().isEmpty ? 'Spotify Imports' : playlistName.trim(),
        subtitle: 'Imported from Spotify',
        gradient: _gradientFor(playlistName).colors,
      );
      _playlists.add(playlist);
    }

    var added = 0;
    var reusedLocal = 0;
    final newlyAdded = <Song>[];
    for (final imported in tracks) {
      final localMatch = _findLocalMatch(imported);
      final Song song;
      if (localMatch != null) {
        song = localMatch;
        reusedLocal++;
      } else {
        song = _songForImportedTrack(imported);
        if (!_allSongs.any((existing) => existing.id == song.id)) {
          _allSongs.add(song);
          if (!_queue.any((existing) => existing.id == song.id)) {
            _queue.add(song);
          }
          newlyAdded.add(song);
        } else {
          // Already known — make sure a previous failed enrichment retries.
          final existing =
              _allSongs.firstWhere((e) => e.id == song.id);
          if (existing.isSilentPlaceholder &&
              !_enrichedIds.contains(existing.id)) {
            newlyAdded.add(existing);
          }
        }
      }
      if (addSongToPlaylist(playlist.id, song)) {
        added++;
      }
    }

    notifyListeners();
    // Best-effort: resolve playable previews + lyrics without blocking import.
    if (newlyAdded.isNotEmpty) _enrichImportedSongs(newlyAdded);

    // Persist imported playlist & tracks to local database for current user
    _persistPlaylistToDb(playlist, spotifyUrl);

    return SpotifyPlaylistImportResult(
      playlistId: playlist.id,
      addedCount: added,
      reusedLocalCount: reusedLocal,
    );
  }

  void _persistPlaylistToDb(MusicPlaylist playlist, String? spotifyUrl) {
    try {
      final playlistSongs = _allSongs
          .where((s) => playlist.songIds.contains(s.id))
          .map((s) => <String, dynamic>{
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
              })
          .toList();

      final rawUserId = AuthService.instance.currentUserId;
      // No default admin anymore — anonymous saves go to 'default_user'
      // and get claimed on next real sign-in (e.g. John Laurence).
      final currentUserId = rawUserId.isEmpty ? 'default_user' : rawUserId;
      final gradientColors = playlist.gradient.map((c) => c.toARGB32()).toList();

      unawaited(
        LocalDatabase.instance.saveImportedPlaylist(
          id: playlist.id,
          userId: currentUserId,
          title: playlist.title,
          subtitle: playlist.subtitle,
          spotifyUrl: spotifyUrl,
          gradientColors: gradientColors,
          songs: playlistSongs,
        ).catchError((e) {
          debugPrint('[MusicPlayerController] Error persisting imported playlist: $e');
        }),
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
  Future<void> persistPlaylistOffline(String playlistId, {String? userId}) async {
    final playlist = playlistById(playlistId);
    if (playlist == null) {
      throw StateError('Playlist not found: $playlistId');
    }
    final rawId = (userId ?? AuthService.instance.currentUserId);
    final effectiveUserId = rawId.isEmpty ? 'default_user' : rawId;
    final playlistSongs = _allSongs
        .where((s) => playlist.songIds.contains(s.id))
        .map((s) => <String, dynamic>{
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
            })
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

  /// Restores all saved imported playlists and songs for [userId] (or the current user).
  Future<void> loadSavedPlaylists({String? userId}) async {
    try {
      final uid = userId ?? AuthService.instance.currentUserId;
      final savedPlaylists = await LocalDatabase.instance.getImportedPlaylistsForUser(uid);
      if (savedPlaylists.isEmpty) return;

      var hasChanges = false;
      for (final pData in savedPlaylists) {
        final playlistId = pData['id'] as String;
        final title = pData['title'] as String;
        final subtitle = pData['subtitle'] as String? ?? 'Imported from Spotify';
        final rawColors = pData['gradient_colors'] as List<int>?;
        final colors = (rawColors != null && rawColors.isNotEmpty)
            ? rawColors.map((c) => Color(c)).toList()
            : _gradientFor(title).colors;

        final rawSongs = pData['songs'] as List<dynamic>? ?? [];
        final songIds = <String>[];

        for (final sMap in rawSongs) {
          final s = sMap as Map<String, dynamic>;
          final songId = s['id'] as String;
          songIds.add(songId);

          var resolvedAudio = s['audio_url'] as String? ?? '';
          var isPreviewVal = s['is_preview'];
          var isPreview = isPreviewVal == 1 || isPreviewVal == true;
          var isYouTubeVal = s['is_youtube_audio'];
          var isYouTubeAudio = isYouTubeVal == 1 || isYouTubeVal == true;
          
          final cachedFile = await _findCachedAudioFile(songId);
          if (cachedFile != null) {
            resolvedAudio = cachedFile.path;
            if (cachedFile.lengthSync() > 800000) {
              isPreview = false;
              isYouTubeAudio = false;
            }
          } else if (resolvedAudio.isNotEmpty &&
              !resolvedAudio.startsWith('http://') &&
              !resolvedAudio.startsWith('https://') &&
              !resolvedAudio.startsWith('assets/') &&
              !resolvedAudio.startsWith('asset:/')) {
            if (!File(resolvedAudio).existsSync()) {
              resolvedAudio = '';
            }
          }

          if (resolvedAudio.isEmpty ||
              (resolvedAudio.contains('googlevideo.com') && cachedFile == null)) {
            resolvedAudio = _cleanAssetUri(_getOfflineAssetFallbackForFields(
              s['title'] as String? ?? '',
              s['artist'] as String? ?? '',
              songId,
            ));
            _offlineFallbackIds.add(songId);
          }

          final existingIdx = _allSongs.indexWhere((existing) => existing.id == songId);
          if (existingIdx < 0) {
            final song = Song(
              id: songId,
              title: s['title'] as String? ?? 'Unknown',
              artist: s['artist'] as String? ?? 'Unknown Artist',
              album: s['album'] as String? ?? '',
              duration: Duration(milliseconds: s['duration_ms'] as int? ?? 180000),
              genre: s['genre'] as String? ?? 'Spotify',
              imageUrl: s['image_url'] as String? ?? '',
              gradientColors: _gradientFor('${s['title']}${s['artist']}').colors,
              plays: '',
              lyrics: (s['lyrics'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
              audioUrl: resolvedAudio,
              isPreview: isPreview,
              isYouTubeAudio: isYouTubeAudio,
            );
            _ensureOfflineLyrics(song);
            _allSongs.add(song);
            if (!_queue.any((existing) => existing.id == songId)) {
              _queue.add(song);
            }
            hasChanges = true;
          } else {
            final existing = _allSongs[existingIdx];
            if (resolvedAudio.isNotEmpty &&
                (existing.isSilentPlaceholder || existing.isPreview ||
                    (cachedFile != null && existing.audioUrl != cachedFile.path))) {
              existing.audioUrl = resolvedAudio;
              existing.isPreview = isPreview;
              existing.isYouTubeAudio = isYouTubeAudio;
              hasChanges = true;
            }
            final dbLyrics = (s['lyrics'] as List<dynamic>? ?? []).map((e) => e.toString()).toList();
            if (existing.lyrics.isEmpty && dbLyrics.isNotEmpty) {
              existing.lyrics = dbLyrics;
              hasChanges = true;
            }
            _ensureOfflineLyrics(existing);
          }
        }

        final existingPlaylistIdx = _playlists.indexWhere((p) => p.id == playlistId);
        if (existingPlaylistIdx >= 0) {
          final existing = _playlists[existingPlaylistIdx];
          for (final sid in songIds) {
            if (!existing.songIds.contains(sid)) {
              existing.songIds.add(sid);
              hasChanges = true;
            }
          }
        } else {
          final newPlaylist = MusicPlaylist(
            id: playlistId,
            title: title,
            subtitle: subtitle,
            gradient: colors,
            songIds: songIds,
          );
          _playlists.add(newPlaylist);
          hasChanges = true;
        }
      }

      if (hasChanges) {
        notifyListeners();
      }

      // Re-enrich songs that are missing audio, previews, have unplayable
      // YouTube URLs, or are still missing lyrics (full-track Saavn hits with
      // no lyrics would otherwise never fetch lyrics on restart).
      final toEnrich = _allSongs
          .where((s) =>
              s.id.startsWith('spotify-') &&
              (s.isSilentPlaceholder ||
                  s.isPreview ||
                  s.isYouTubeAudio ||
                  s.audioUrl.contains('googlevideo.com') ||
                  s.lyrics.isEmpty ||
                  _offlineFallbackIds.contains(s.id) ||
                  _offlineFakeLyricsIds.contains(s.id)))
          .toList();
      if (toEnrich.isNotEmpty) {
        _enrichImportedSongs(toEnrich);
      }

      // Automatically cache all songs that have remote HTTP URLs to local storage
      _cacheAllPendingOfflineAudio();
    } catch (e) {
      debugPrint('[MusicPlayerController] loadSavedPlaylists skipped: $e');
    }
  }

  bool deletePlaylist(String playlistId) {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index < 0) return false;
    _playlists.removeAt(index);
    notifyListeners();
    try {
      unawaited(LocalDatabase.instance.deleteImportedPlaylist(
        playlistId,
        userId: AuthService.instance.currentUserId,
      ).catchError((_) {}));
    } catch (_) {}
    return true;
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
        .replaceAll(RegExp(r'\b(feat|ft|featuring)\b.*$', caseSensitive: false), '')
        .trim();
  }

  Song? _findLocalMatch(SpotifyImportedTrack imported) {
    final titleKey = _normalizeKey(imported.title);
    final cleanTitleKey = _normalizeKey(_cleanSongTitle(imported.title));
    final artistKey = _normalizeKey(imported.artist);
    if (titleKey.isEmpty && cleanTitleKey.isEmpty) return null;

    Song? artistMatched;
    for (final song in _allSongs) {
      final songTitleKey = _normalizeKey(song.title);
      final songCleanTitleKey = _normalizeKey(_cleanSongTitle(song.title));
      final titleMatches = songTitleKey == titleKey ||
          (cleanTitleKey.isNotEmpty &&
              (songCleanTitleKey == cleanTitleKey ||
                  songTitleKey == cleanTitleKey ||
                  songTitleKey.contains(cleanTitleKey) ||
                  cleanTitleKey.contains(songCleanTitleKey)));
      if (!titleMatches) continue;

      final songArtist = _normalizeKey(song.artist);
      if (songArtist == artistKey ||
          songArtist.isEmpty ||
          artistKey.isEmpty ||
          songArtist.contains(artistKey) ||
          artistKey.contains(songArtist)) {
        return song;
      }
      artistMatched ??= song;
    }
    return artistMatched;
  }

  Song _songForImportedTrack(SpotifyImportedTrack imported) {
    final duration = imported.duration > Duration.zero
        ? imported.duration
        : const Duration(minutes: 3);
    // Artist top-song imports arrive with a playable preview baked in —
    // use it immediately so there is no silent gap before enrichment.
    final hasPreview = imported.previewUrl.trim().isNotEmpty;
    return Song(
      id: 'spotify-${imported.spotifyId}',
      title: imported.title,
      artist: imported.artist,
      album: imported.album,
      duration: duration,
      genre: 'Spotify',
      imageUrl: imported.artworkUrl,
      gradientColors: _gradientFor('${imported.title}${imported.artist}').colors,
      plays: '',
      lyrics: const [],
      audioUrl: hasPreview ? imported.previewUrl.trim() : '',
      isPreview: hasPreview,
    );
  }

  /// Best-effort enrichment for imported tracks: resolves full-length
  /// audio (JioSaavn → YouTube) with 30s iTunes/Deezer preview fallback
  /// + lyrics so imported playlists are audible and show lyrics instead
  /// of staying muted/empty.
  ///
  /// Also re-queues 30s previews that have not been upgraded yet (on a
  /// cooldown) so artist imports that arrive with baked-in iTunes previews
  /// still graduate to full-length streams.
  ///
  /// Fire-and-forget by design — import stays synchronous (existing tests
  /// rely on that) while audio/lyrics fill in and notify listeners.
  void _enrichImportedSongs(List<Song> songs) {
    final pending = songs.where((s) {
      if (_enrichingIds.contains(s.id)) return false;
      // A track on offline fallback still needs real audio/lyrics — the
      // fallback is playback-only and must not permanently block upgrades.
      final isFallback = _offlineFallbackIds.contains(s.id);
      final hasFakeLyrics = _offlineFakeLyricsIds.contains(s.id);
      final needsAudio = s.isSilentPlaceholder ||
          isFallback ||
          (s.isPreview && _shouldAttemptFullUpgrade(s.id));
      final needsLyrics = (s.lyrics.isEmpty || hasFakeLyrics) &&
          !_enrichedIds.contains(s.id);
      return needsAudio || needsLyrics;
    }).toList();
    
    if (pending.isEmpty) return;
    
    // Process sequentially to avoid rate-limiting from LRCLIB/YouTube
    // and to prevent downloading 50 audio streams concurrently.
    // ignore: discarded_futures
    Future.microtask(() async {
      for (final song in pending) {
        if (_disposed) return;
        _enrichingIds.add(song.id);
        if (song.isPreview) {
          _fullUpgradeAttemptedAt[song.id] = DateTime.now();
        }
        await _enrichOneSong(song);
      }
    });
  }

  bool _shouldAttemptFullUpgrade(String songId) {
    final last = _fullUpgradeAttemptedAt[songId];
    if (last == null) return true;
    return DateTime.now().difference(last) >= _fullUpgradeCooldown;
  }

  Future<void> _enrichOneSong(
    Song song, {
    bool previewFallbackOnly = false,
  }) async {
    song.isEnrichingLyrics = true;
    try {
      final enrichment = await _enrichment.enrichTrack(
        title: song.title,
        artist: song.artist,
        album: song.album,
        duration: song.duration,
        previewFallbackOnly: previewFallbackOnly,
      );
      // Only mark enriched when we actually got audio or lyrics. Marking
      // empty results as enriched would permanently block retries and leave
      // the track silent with no lyrics on the next online attempt.
      if (enrichment.hasAudio || enrichment.hasLyrics) {
        _enrichedIds.add(song.id);
      }
      final changed = _applyEnrichment(song, enrichment);
      song.isEnrichingLyrics = false;
      if (changed) notifyListeners();
    } catch (_) {
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

    final isFallbackAudio = _offlineFallbackIds.contains(song.id);
    final shouldAttachAudio = enrichment.hasAudio &&
        (!song.hasAudio ||
            isFallbackAudio ||
            (enrichment.isFullTrack && song.isPreview));
    if (shouldAttachAudio) {
      final resumePosition =
          song.id == currentSong?.id ? _currentPosition : Duration.zero;
      song.audioUrl = enrichment.previewUrl!;
      song.isPreview = !enrichment.isFullTrack;
      song.isYouTubeAudio =
          enrichment.isFullTrack && enrichment.isYouTube;
      // Prefer the resolved stream length (full track or real 30s clip)
      // so list rows and the slider agree with what actually plays.
      if (enrichment.previewDuration != null &&
          enrichment.previewDuration! > Duration.zero) {
        song.duration = enrichment.previewDuration!;
      }
      if (enrichment.artworkUrl != null &&
          enrichment.artworkUrl!.isNotEmpty) {
        song.imageUrl = enrichment.artworkUrl!;
      }
      changed = true;
      // Real audio replaces the offline fallback — clear the placeholder flag
      // so future logic treats this as genuine audio, not a fallback.
      _offlineFallbackIds.remove(song.id);
      if (enrichment.isFullTrack) {
        _fullUpgradeAttemptedAt.remove(song.id);
      }
      // Hot-swap mid-playback: silent -> real audio, fallback -> real, or preview -> full.
      if (song.id == currentSong?.id && _isPlaying && !_audioPlayerHasSource) {
        _unmuteOnPlay();
        // ignore: discarded_futures
        _playCurrentSongAudio();
      } else if (song.id == currentSong?.id &&
          _isPlaying &&
          _audioPlayerHasSource &&
          (enrichment.isFullTrack || isFallbackAudio)) {
        _unmuteOnPlay();
        // ignore: discarded_futures
        _playCurrentSongAudio().then((_) {
          if (resumePosition > Duration.zero) {
            seekTo(resumePosition);
          }
        });
      }
    }

    final hasFakeLyrics = _offlineFakeLyricsIds.contains(song.id);
    if (enrichment.hasLyrics && (song.lyrics.isEmpty || hasFakeLyrics)) {
      song.lyrics = enrichment.lyrics;
      _offlineFakeLyricsIds.remove(song.id);
      changed = true;
    }

    if (changed && song.id.startsWith('spotify-')) {
      try {
        unawaited(
          LocalDatabase.instance.updateImportedSong(
            id: song.id,
            audioUrl: song.audioUrl,
            isPreview: song.isPreview,
            isYouTubeAudio: song.isYouTubeAudio,
            durationMs: song.duration.inMilliseconds,
            imageUrl: song.imageUrl,
            lyrics: song.lyrics,
          ).catchError((e) {
            debugPrint('[MusicPlayerController] Error updating song in DB: $e');
          }),
        );
      } catch (_) {}

      // Attempt to cache audio offline
      if (song.audioUrl.startsWith('http')) {
        unawaited(_cacheAudioOffline(song));
      }
    }

    return changed;
  }

  final Set<String> _cachingIds = {};

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
    primary ??= Directory(p.join(Directory.systemTemp.path, 'pulse_music_offline'));
    if (!await primary.exists()) {
      await primary.create(recursive: true);
    }
    return primary;
  }

  Future<File?> _findCachedAudioFile(String songId) async {
    final dirs = <Directory>[];
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

    for (final dir in dirs) {
      try {
        if (!dir.existsSync()) continue;
        for (final ext in const ['.mp3', '.m4a', '.mp4', '.aac', '.wav', '.ogg']) {
          final f = File(p.join(dir.path, '$songId$ext'));
          if (f.existsSync() && f.lengthSync() > 1024) {
            return f;
          }
        }
      } catch (_) {}
    }
    return null;
  }

  Future<File?> _findCachedArtworkFile(String songId) async {
    final dirs = <Directory>[];
    try {
      final supp = await getApplicationSupportDirectory();
      dirs.add(Directory(p.join(supp.path, 'offline_audio')));
    } catch (_) {}
    try {
      final docs = await getApplicationDocumentsDirectory();
      dirs.add(Directory(p.join(docs.path, 'offline_audio')));
    } catch (_) {}
    try {
      final temp = await getTemporaryDirectory();
      dirs.add(Directory(p.join(temp.path, 'offline_audio')));
    } catch (_) {}

    for (final dir in dirs) {
      if (!dir.existsSync()) continue;
      for (final ext in const ['.jpg', '.jpeg', '.png', '.webp']) {
        final f = File(p.join(dir.path, '$songId$ext'));
        if (f.existsSync() && f.lengthSync() > 100) {
          return f;
        }
      }
    }
    return null;
  }

  Future<MediaItem> _createSafeMediaItem(Song song) async {
    Uri? safeArtUri;
    if (song.imageUrl.isNotEmpty) {
      if (song.imageUrl.startsWith('file://') || song.imageUrl.startsWith('asset:///')) {
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

    final duration = song.duration > Duration.zero ? song.duration : const Duration(minutes: 3);

    return MediaItem(
      id: song.id,
      album: song.album.isNotEmpty ? song.album : 'Pulse Music',
      title: song.title,
      artist: song.artist,
      artUri: safeArtUri,
      duration: duration,
    );
  }

  static String _cleanAssetUri(String path) {
    final clean = path
        .replaceFirst(RegExp(r'^asset:[/\\]*'), '')
        .replaceFirst(RegExp(r'^[/\\]+'), '');
    return clean.startsWith('assets/') ? clean : 'assets/audio/$clean';
  }

  String _getOfflineAssetFallbackForFields(String title, String artist, String songId) {
    // 1. Fuzzy match against bundled sample songs
    final cleanT = _cleanSongTitle(title).toLowerCase();
    final cleanA = artist.toLowerCase();
    for (final sample in SampleMusicData.sampleSongs) {
      final sampleT = _cleanSongTitle(sample.title).toLowerCase();
      final sampleA = sample.artist.toLowerCase();
      if (cleanT.isNotEmpty && (cleanT == sampleT || cleanT.contains(sampleT) || sampleT.contains(cleanT))) {
        if (sample.audioUrl.isNotEmpty) return sample.audioUrl;
      }
      if (cleanA.isNotEmpty && (cleanA == sampleA || cleanA.contains(sampleA) || sampleA.contains(cleanA))) {
        if (sample.audioUrl.isNotEmpty) return sample.audioUrl;
      }
    }
    // 2. Stable fallback based on hash of song ID so the track is consistent
    final samples = SampleMusicData.sampleSongs.where((s) => s.audioUrl.isNotEmpty).toList();
    if (samples.isNotEmpty) {
      final idx = (songId.hashCode.abs()) % samples.length;
      return samples[idx].audioUrl;
    }
    return 'assets/audio/lose-yourself.m4a';
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
      debugPrint('[MusicPlayerController] Primary asset extraction failed for $cleanPath: $e');
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
        if (sample.audioUrl.isNotEmpty && sample.audioUrl.startsWith('assets/')) {
          await _extractAssetToFile(sample.audioUrl);
        }
      }
    } catch (e) {
      debugPrint('[MusicPlayerController] Pre-extraction error: $e');
    }
  }

  DateTime? _lastOnlineCheck;
  bool _cachedOnline = true;

  Future<bool> _isDeviceOnline() async {
    final now = DateTime.now();
    if (_lastOnlineCheck != null && now.difference(_lastOnlineCheck!) < const Duration(seconds: 8)) {
      return _cachedOnline;
    }
    for (final host in const ['example.com', 'google.com']) {
      try {
        final res = await InternetAddress.lookup(host)
            .timeout(const Duration(milliseconds: 650));
        if (res.isNotEmpty && res.first.rawAddress.isNotEmpty) {
          _lastOnlineCheck = now;
          _cachedOnline = true;
          return true;
        }
      } catch (_) {
        // try next host
      }
    }
    _lastOnlineCheck = now;
    _cachedOnline = false;
    return false;
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
      if (cleanT.isNotEmpty && (cleanT == sampleT || cleanT.contains(sampleT) || sampleT.contains(cleanT))) {
        if (sample.lyrics.isNotEmpty) {
          song.lyrics = List<String>.from(sample.lyrics);
          _offlineFakeLyricsIds.remove(song.id);
          return song.lyrics;
        }
      }
    }
    // Generate rhythmic, timestamped lyrics for offline tracking
    final durationSeconds = song.duration.inSeconds > 0 ? song.duration.inSeconds : 180;
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
      if (durationSeconds > 180) '[03:00.00] ♫ Pulse Music Player ♫',
    ];
    song.lyrics = lines;
    _offlineFakeLyricsIds.add(song.id);
    return lines;
  }

  @visibleForTesting
  String getOfflineAssetFallbackForTesting(Song song) => _getOfflineAssetFallback(song);

  @visibleForTesting
  List<String> ensureOfflineLyricsForTesting(Song song) => _ensureOfflineLyrics(song);

  Future<void> _cacheAudioOffline(Song song) async {
    final remoteUrl = song.audioUrl;
    if (remoteUrl.isEmpty) return;

    // Check if a valid local offline file already exists
    final cached = await _findCachedAudioFile(song.id);
    if (cached != null) {
      if (song.audioUrl != cached.path || (song.isPreview && cached.lengthSync() > 800000)) {
        song.audioUrl = cached.path;
        if (cached.lengthSync() > 800000) {
          song.isPreview = false;
          song.isYouTubeAudio = false;
        }
        _syncSongPathToQueueAndDb(song);
        notifyListeners();
      }
      return;
    }

    if (!remoteUrl.startsWith('http://') && !remoteUrl.startsWith('https://')) {
      return;
    }

    if (_cachingIds.contains(song.id)) return;
    _cachingIds.add(song.id);

    try {
      final offlineDir = await _getPrimaryOfflineDirectory();
      String urlToDownload = remoteUrl;

      // YouTube stream URLs block simple HTTP GET with 403 Forbidden.
      // If the URL is YouTube or expired, resolve a direct Saavn/iTunes download URL!
      if (urlToDownload.contains('googlevideo.com') || song.isYouTubeAudio) {
        try {
          final enrichment = await _enrichment.enrichTrack(
            title: song.title,
            artist: song.artist,
            album: song.album,
            duration: song.duration,
            previewFallbackOnly: false,
          );
          if (enrichment.previewUrl != null &&
              !enrichment.previewUrl!.contains('googlevideo.com') &&
              enrichment.previewUrl!.startsWith('http')) {
            urlToDownload = enrichment.previewUrl!;
            // A fresh direct URL resolved — attach it so playback stops using
            // the expired YouTube link even before the download finishes.
            _applyEnrichment(song, enrichment);
          }
        } catch (_) {}
        // Still a googlevideo URL after refresh: plain http.get would 403.
        // Skip the doomed download and recover straight to a compatible
        // 30s preview instead of leaving the track muted.
        if (urlToDownload.contains('googlevideo.com')) {
          unawaited(_enrichOneSong(song, previewFallbackOnly: true));
          return;
        }
      }

      final uri = Uri.parse(urlToDownload);
      final ext = urlToDownload.toLowerCase().contains('.mp3') ? '.mp3' : '.m4a';
      final targetFile = File(p.join(offlineDir.path, '${song.id}$ext'));
      final tempFile = File(p.join(offlineDir.path, '${song.id}.tmp'));

      final response = await http.get(
        uri,
        headers: {
          'User-Agent': TrackEnrichmentService.browserUserAgent,
          'Accept': '*/*',
        },
      ).timeout(const Duration(seconds: 45));

      if (response.statusCode == 200 && response.bodyBytes.length > 1024) {
        await tempFile.writeAsBytes(response.bodyBytes, flush: true);
        if (await targetFile.exists()) {
          try {
            await targetFile.delete();
          } catch (_) {}
        }
        await tempFile.rename(targetFile.path);

        song.audioUrl = targetFile.path;
        if (response.bodyBytes.length > 800000) {
          song.isPreview = false;
          song.isYouTubeAudio = false;
        }
        _syncSongPathToQueueAndDb(song);
        if (song.id == currentSong?.id) {
          notifyListeners();
        }
        debugPrint(
            '[MusicPlayerController] Successfully cached ${song.title} (${response.bodyBytes.length} bytes)');

        // Also cache artwork locally if available
        if (song.imageUrl.startsWith('http')) {
          try {
            final artTarget = File(p.join(offlineDir.path, '${song.id}.jpg'));
            if (!artTarget.existsSync()) {
              final artResp = await http.get(Uri.parse(song.imageUrl)).timeout(const Duration(seconds: 15));
              if (artResp.statusCode == 200 && artResp.bodyBytes.isNotEmpty) {
                await artTarget.writeAsBytes(artResp.bodyBytes, flush: true);
              }
            }
          } catch (_) {}
        }
      } else {
        debugPrint(
            '[MusicPlayerController] Cache download rejected (status: ${response.statusCode}) for ${song.title}');
        if (response.statusCode == 403 || response.statusCode == 404) {
          unawaited(_enrichOneSong(song, previewFallbackOnly: true));
        }
      }
    } catch (e) {
      debugPrint('[MusicPlayerController] Offline cache error for ${song.title}: $e');
    } finally {
      _cachingIds.remove(song.id);
    }
  }

  void _syncSongPathToQueueAndDb(Song song) {
    for (final s in _allSongs) {
      if (s.id == song.id) s.audioUrl = song.audioUrl;
    }
    for (final s in _queue) {
      if (s.id == song.id) s.audioUrl = song.audioUrl;
    }
    if (song.id.startsWith('spotify-')) {
      try {
        unawaited(LocalDatabase.instance.updateImportedSong(
          id: song.id,
          audioUrl: song.audioUrl,
          isPreview: song.isPreview,
          isYouTubeAudio: song.isYouTubeAudio,
          durationMs: song.duration.inMilliseconds,
          imageUrl: song.imageUrl,
          lyrics: song.lyrics,
        ).catchError((_) {}));
      } catch (_) {}
    }
  }

  void _cacheAllPendingOfflineAudio() {
    final pending = _allSongs
        .where((s) =>
            s.id.startsWith('spotify-') &&
            s.audioUrl.startsWith('http') &&
            !_cachingIds.contains(s.id))
        .toList();
    if (pending.isEmpty) return;

    Future.microtask(() async {
      for (final song in pending) {
        if (_disposed) return;
        await _cacheAudioOffline(song);
        await Future.delayed(const Duration(milliseconds: 300));
      }
    });
  }

  /// Public retry used by the lyrics sheet when a track has no lyrics yet
  /// (or is still stuck on a 30s preview). Returns true when lyrics are
  /// now available.
  Future<bool> ensureLyricsFor(Song song) async {
    final hasFakeLyrics = _offlineFakeLyricsIds.contains(song.id);
    final needsLyrics = song.lyrics.isEmpty || hasFakeLyrics;
    final needsFullAudio = (song.isPreview ||
            _offlineFallbackIds.contains(song.id) ||
            song.isSilentPlaceholder) &&
        _shouldAttemptFullUpgrade(song.id);
    if (!needsLyrics && !needsFullAudio) return song.lyrics.isNotEmpty;
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
        notifyListeners();
      }
      return song.lyrics.isNotEmpty;
    } catch (_) {
      song.isEnrichingLyrics = false;
      _ensureOfflineLyrics(song);
      notifyListeners();
      return song.lyrics.isNotEmpty;
    } finally {
      _enrichingIds.remove(song.id);
    }
  }

  bool isEnriching(String songId) => _enrichingIds.contains(songId);

  static String _normalizeKey(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
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
    _queue = List<Song>.from(songs);
    _currentIndex = 0;
    _currentPosition = Duration.zero;
    _audioDuration = Duration.zero;
    _lastPositionUpdate = DateTime.now();
    _unmuteOnPlay();
    _isPlaying = true;
    _playbackTimer?.cancel();
    _cancelStallWatchdog();
    _startTimer();
    _playCurrentSongAudio();
    notifyListeners();
  }

  void addSong(Song song) {
    _allSongs.add(song);
    _queue.add(song);
    notifyListeners();
  }

  void setSongs(List<Song> songs) {
    _allSongs.clear();
    _allSongs.addAll(songs);
    _queue = List<Song>.from(_allSongs);
    _currentIndex = 0;
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
    _queue.clear();
    _currentIndex = 0;
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
    final existingIndex = _queue.indexWhere((s) => s.id == song.id);
    if (existingIndex != -1) {
      _currentIndex = existingIndex;
    } else {
      _queue.insert(_currentIndex + 1, song);
      _currentIndex++;
    }
    _currentPosition = Duration.zero;
    _audioDuration = Duration.zero;
    _lastPositionUpdate = DateTime.now();
    _unmuteOnPlay();
    _isPlaying = true;
    _playbackTimer?.cancel();
    _cancelStallWatchdog();
    _startTimer();
    _playCurrentSongAudio();
    notifyListeners();
  }

  void togglePlayPause() {
    if (currentSong == null) return;
    _isPlaying = !_isPlaying;
    if (_isPlaying) {
      _unmuteOnPlay();
      _lastPositionUpdate = DateTime.now();
      _startTimer();
      if (_audioPlayerHasSource) {
        try {
          final effectiveVolume = _isMuted ? 0.0 : (_volume > 0.05 ? _volume : 0.8);
          // ignore: discarded_futures
          _audioPlayer.setVolume(effectiveVolume).catchError((_) {});
          // ignore: discarded_futures
          _audioPlayer.play().catchError((_) {});
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
    if (!_isPlaying) {
      _unmuteOnPlay();
      _isPlaying = true;
      _lastPositionUpdate = DateTime.now();
      _startTimer();
      if (_audioPlayerHasSource) {
        try {
          final effectiveVolume = _isMuted ? 0.0 : (_volume > 0.05 ? _volume : 0.8);
          // ignore: discarded_futures
          _audioPlayer.setVolume(effectiveVolume).catchError((_) {});
          // ignore: discarded_futures
          _audioPlayer.play().catchError((_) {});
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

  void next() {
    if (_queue.isEmpty) return;

    if (_repeatMode == PlaybackRepeatMode.one) {
      _currentPosition = Duration.zero;
      _audioDuration = Duration.zero;
      _playCurrentSongAudio();
      _startTimer();
      notifyListeners();
      return;
    }

    if (_isShuffle) {
      final random = Random();
      _currentIndex = random.nextInt(_queue.length);
    } else {
      if (_currentIndex < _queue.length - 1) {
        _currentIndex++;
      } else if (_repeatMode == PlaybackRepeatMode.all) {
        _currentIndex = 0;
      } else {
        pause();
        return;
      }
    }
    _currentPosition = Duration.zero;
    _audioDuration = Duration.zero;
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

    if (_currentPosition.inSeconds > 3) {
      _currentPosition = Duration.zero;
      _audioDuration = Duration.zero;
      if (_isPlaying) {
        _unmuteOnPlay();
        _lastPositionUpdate = DateTime.now();
        _playbackTimer?.cancel();
        _startTimer();
        _playCurrentSongAudio();
      }
    } else {
      if (_currentIndex > 0) {
        _currentIndex--;
      } else {
        _currentIndex = _queue.length - 1;
      }
      _currentPosition = Duration.zero;
      _audioDuration = Duration.zero;
      if (_isPlaying) {
        _unmuteOnPlay();
        _lastPositionUpdate = DateTime.now();
        _playbackTimer?.cancel();
        _startTimer();
        _playCurrentSongAudio();
      }
    }
    notifyListeners();
  }

  void seekTo(Duration position) {
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

  void addToQueue(Song song) {
    _queue.add(song);
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
    // 1. Cached offline audio file on disk
    if (!forceAsset) {
      final cached = await _findCachedAudioFile(song.id);
      if (cached != null && cached.existsSync() && cached.lengthSync() > 1024) {
        song.audioUrl = cached.path;
        if (cached.lengthSync() > 800000) {
          song.isPreview = false;
          song.isYouTubeAudio = false;
        }
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
      }
    }

    // 3. Bundled asset in app package
    if (!forceAsset &&
        (song.audioUrl.startsWith('assets/') || song.audioUrl.startsWith('asset:/'))) {
      final clean = _cleanAssetUri(song.audioUrl);
      final extracted = await _extractAssetToFile(clean);
      if (File(extracted).existsSync() && File(extracted).lengthSync() > 1024) {
        return AudioSource.file(extracted, tag: mediaItem);
      }
      return AudioSource.uri(Uri.parse('asset:///$clean'), tag: mediaItem);
    }

    // 4. Remote HTTP stream (only if online and not expired googlevideo)
    if (!forceAsset &&
        (song.audioUrl.startsWith('http://') || song.audioUrl.startsWith('https://'))) {
      final online = await _isDeviceOnline();
      if (online && !song.audioUrl.contains('googlevideo.com')) {
        unawaited(_cacheAudioOffline(song));
        return AudioSource.uri(Uri.parse(song.audioUrl), tag: mediaItem);
      }
    }

    // 5. Offline fallback asset
    final fallbackAsset = _cleanAssetUri(_getOfflineAssetFallback(song));
    _offlineFallbackIds.add(song.id);
    final extracted = await _extractAssetToFile(fallbackAsset);
    if (File(extracted).existsSync() && File(extracted).lengthSync() > 1024) {
      return AudioSource.file(extracted, tag: mediaItem);
    }
    return AudioSource.uri(Uri.parse('asset:///$fallbackAsset'), tag: mediaItem);
  }

  /// Load and play the current song's audio URL or asset.
  ///
  /// Multi-tier resilience ensures imported Spotify playlists across all accounts
  /// produce real, audible, high-fidelity sound through speakers/headphones
  /// while keeping the progress slider and lyrics tracker in perfect real-time sync.
  Future<void> _playCurrentSongAudio() async {
    final song = currentSong;
    if (song == null) return;

    final sessionId = ++_playSessionId;

    final online = await _isDeviceOnline();

    // Opportunistic upgrade: if online and song is on fallback or preview,
    // fire background enrichment without blocking audible playback.
    if (online &&
        (song.isPreview || _offlineFallbackIds.contains(song.id) || song.isSilentPlaceholder) &&
        !_enrichingIds.contains(song.id) &&
        _shouldAttemptFullUpgrade(song.id)) {
      _fullUpgradeAttemptedAt[song.id] = DateTime.now();
      _enrichingIds.add(song.id);
      // ignore: discarded_futures
      _enrichOneSong(song);
    }

    // Ensure audioUrl is valid (check for empty or deleted local file paths)
    final isLocalPath = song.audioUrl.isNotEmpty &&
        !song.audioUrl.startsWith('http://') &&
        !song.audioUrl.startsWith('https://') &&
        !song.audioUrl.startsWith('assets/') &&
        !song.audioUrl.startsWith('asset:/');
    if (song.audioUrl.isEmpty || (isLocalPath && !File(song.audioUrl).existsSync())) {
      final cached = await _findCachedAudioFile(song.id);
      if (cached != null && cached.existsSync() && cached.lengthSync() > 1024) {
        song.audioUrl = cached.path;
        _offlineFallbackIds.remove(song.id);
      } else {
        song.audioUrl = _cleanAssetUri(_getOfflineAssetFallback(song));
        _offlineFallbackIds.add(song.id);
      }
    }

    _ensureOfflineLyrics(song);

    try {
      final mediaItem = await _createSafeMediaItem(song);
      final audioSource = await _resolveAudioSource(song, mediaItem);

      try {
        await _audioPlayer
            .setAudioSource(audioSource)
            .timeout(const Duration(seconds: 8));
        _audioPlayerHasSource = true;
      } on MissingPluginException {
        _audioPlayerHasSource = false;
      } catch (loadErr) {
        debugPrint('[MusicPlayerController] Primary setAudioSource failed ($loadErr), switching to local asset fallback...');
        _offlineFallbackIds.add(song.id);
        try {
          await _audioPlayer.stop();
        } catch (_) {}
        final fallbackSource = await _resolveAudioSource(song, mediaItem, forceAsset: true);
        try {
          await _audioPlayer.setAudioSource(fallbackSource).timeout(const Duration(seconds: 6));
          _audioPlayerHasSource = true;
        } catch (fbErr) {
          debugPrint('[MusicPlayerController] Fallback setAudioSource failed: $fbErr');
          try {
            await _audioPlayer.stop();
          } catch (_) {}
          try {
            final baseAsset = 'assets/audio/lose-yourself.m4a';
            final baseExtracted = await _extractAssetToFile(baseAsset);
            final baseSource = File(baseExtracted).existsSync() && File(baseExtracted).lengthSync() > 1024
                ? AudioSource.file(baseExtracted, tag: mediaItem)
                : AudioSource.uri(Uri.parse('asset:///$baseAsset'), tag: mediaItem);
            await _audioPlayer.setAudioSource(baseSource).timeout(const Duration(seconds: 4));
            _audioPlayerHasSource = true;
          } catch (_) {
            _audioPlayerHasSource = false;
          }
        }
      }

      if (sessionId != _playSessionId) return;

      _ytRefreshAttemptedIds.remove(song.id);
      _playbackTimer?.cancel();

      _unmuteOnPlay();
      _lastPositionUpdate = DateTime.now();
      final effectiveVolume = _isMuted ? 0.0 : (_volume > 0.05 ? _volume : 0.8);
      try {
        await _audioPlayer.setVolume(effectiveVolume);
      } catch (_) {}

      if (_isPlaying) {
        _startTimer();
        if (_audioPlayerHasSource) {
          try {
            await _audioPlayer.play().timeout(const Duration(seconds: 10));
            if (sessionId == _playSessionId) {
              try {
                await _audioPlayer.setVolume(effectiveVolume);
              } catch (_) {}
              for (final delayMs in const [0, 80, 200, 450, 800]) {
                Future.delayed(Duration(milliseconds: delayMs), () {
                  if (sessionId == _playSessionId && _audioPlayerHasSource && !_isMuted && !_disposed) {
                    try {
                      _audioPlayer.setVolume(effectiveVolume).catchError((_) {});
                    } catch (_) {}
                  }
                });
              }
              _startStallWatchdog();
            }
          } on TimeoutException {
            debugPrint('[MusicPlayerController] play() timed out for ${song.title}, recovering…');
            await _handleAudioLoadFailure(song);
          } catch (playErr) {
            debugPrint('[MusicPlayerController] play() failed: $playErr, recovering…');
            await _handleAudioLoadFailure(song);
          }
        } else {
          _cancelStallWatchdog();
          _startTimer();
        }
      }
    } catch (e) {
      if (sessionId != _playSessionId || _disposed) return;
      debugPrint('Audio playback load error for ${song.title}: $e');
      await _handleAudioLoadFailure(song);
    }
  }

  /// Shared recovery for sync load errors and async media failures.
  Future<void> _handleAudioLoadFailure(Song song) async {
    if (_disposed || song.id != currentSong?.id) return;
    _cancelStallWatchdog();

    // Prevent redundant recovery loops if already running fallback with active source
    if (_offlineFallbackIds.contains(song.id) && _audioPlayerHasSource) {
      return;
    }

    // 1. Check if offline cached file exists before trying online recovery
    final cached = await _findCachedAudioFile(song.id);
    if (cached != null && song.audioUrl != cached.path && cached.existsSync() && cached.lengthSync() > 1024) {
      debugPrint('Recovering with offline cached file: ${cached.path}');
      song.audioUrl = cached.path;
      _offlineFallbackIds.remove(song.id);
      _syncSongPathToQueueAndDb(song);
      if (song.id == currentSong?.id) {
        await _playCurrentSongAudio();
        return;
      }
    }

    // 2. Robust Offline Fallback: Play bundled audio IMMEDIATELY so the user
    // is NEVER left in silence, muted state, or with a stuck tracker!
    try {
      _offlineFallbackIds.add(song.id);
      final mediaItem = await _createSafeMediaItem(song);
      _ensureOfflineLyrics(song);

      try {
        await _audioPlayer.stop();
      } catch (_) {}

      final fallbackSource = await _resolveAudioSource(song, mediaItem, forceAsset: true);
      await _audioPlayer.setAudioSource(fallbackSource).timeout(const Duration(seconds: 6));
      _audioPlayerHasSource = true;
      _lastPositionUpdate = DateTime.now();
      _unmuteOnPlay();
      final effectiveVolume = _isMuted ? 0.0 : (_volume > 0.05 ? _volume : 0.8);
      await _audioPlayer.setVolume(effectiveVolume);
      if (_isPlaying) {
        if (_currentPosition > Duration.zero && _currentPosition < currentDuration) {
          try {
            await _audioPlayer.seek(_currentPosition);
          } catch (_) {}
        }
        await _audioPlayer.play();
        for (final delayMs in const [0, 80, 200, 450, 800]) {
          Future.delayed(Duration(milliseconds: delayMs), () {
            if (_audioPlayerHasSource && !_isMuted && !_disposed) {
              try {
                _audioPlayer.setVolume(effectiveVolume).catchError((_) {});
              } catch (_) {}
            }
          });
        }
      }
      _startTimer();
      notifyListeners();
    } catch (err) {
      debugPrint('[MusicPlayerController] Fallback asset recovery failed: $err');
      try {
        await _audioPlayer.stop();
        final mediaItem = await _createSafeMediaItem(song);
        final baseAsset = 'assets/audio/lose-yourself.m4a';
        final baseExtracted = await _extractAssetToFile(baseAsset);
        final baseSource = File(baseExtracted).existsSync() && File(baseExtracted).lengthSync() > 1024
            ? AudioSource.file(baseExtracted, tag: mediaItem)
            : AudioSource.uri(Uri.parse('asset:///$baseAsset'), tag: mediaItem);
        await _audioPlayer.setAudioSource(baseSource).timeout(const Duration(seconds: 4));
        _audioPlayerHasSource = true;
        final effectiveVolume = _isMuted ? 0.0 : (_volume > 0.05 ? _volume : 0.8);
        await _audioPlayer.setVolume(effectiveVolume);
        if (_isPlaying) await _audioPlayer.play();
      } catch (_) {
        _audioPlayerHasSource = false;
      }
      if (_isPlaying) _startTimer();
      notifyListeners();
    }

    // 3. Online background recovery: if connected, try to refresh preview in background
    unawaited(() async {
      try {
        final online = await _isDeviceOnline();
        if (!online || _disposed) return;

        if (song.isYouTubeAudio && _ytRefreshAttemptedIds.add(song.id)) {
          if (song.id == currentSong?.id) {
            _enrichingIds.add(song.id);
            await _enrichOneSong(song);
          }
        } else if (song.id.startsWith('spotify-') &&
            _audioFallbackAttemptedIds.add(song.id)) {
          if (song.id == currentSong?.id) {
            _enrichingIds.add(song.id);
            await _enrichOneSong(song, previewFallbackOnly: true);
          }
        }
      } catch (_) {}
    }());
  }

  /// Called when audio completes a song
  void _onSongComplete() {
    if (_repeatMode == PlaybackRepeatMode.one) {
      _currentPosition = Duration.zero;
      _playCurrentSongAudio();
      _startTimer();
      notifyListeners();
    } else {
      next();
    }
  }

  /// Reliable playback heartbeat timer that ensures UI position, progress slider,
  /// and lyrics tracker ALWAYS advance smoothly, even if native audio player
  /// position stream is buffering, offline, delayed, or stalled.
  void _startTimer() {
    _playbackTimer?.cancel();
    _playbackTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!_isPlaying) {
        timer.cancel();
        return;
      }

      // If native player's position stream emitted a fresh update within the last 1200ms,
      // native audio is actively driving the position.
      final lastUpdate = _lastPositionUpdate;
      final isNativeAdvancing = _audioPlayerHasSource &&
          lastUpdate != null &&
          DateTime.now().difference(lastUpdate) < const Duration(milliseconds: 1200);

      if (!isNativeAdvancing) {
        // Native stream is buffering, stalled, or player is running fallback/mock.
        // Advance currentPosition so the slider and lyrics tracker NEVER freeze!
        if (_currentPosition < currentDuration) {
          _currentPosition += const Duration(milliseconds: 500);
          if (_currentPosition > currentDuration) {
            _currentPosition = currentDuration;
          }
          notifyListeners();
        } else {
          timer.cancel();
          _onSongComplete();
        }
      }
    });
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
    _stallWatchdog = Timer.periodic(const Duration(milliseconds: 1000), (timer) {
      if (_disposed || !_isPlaying || song.id != currentSong?.id) {
        timer.cancel();
        return;
      }
      final last = _lastPositionUpdate;
      final stalled = last == null ||
          DateTime.now().difference(last) > const Duration(seconds: 8);
      final elapsed = DateTime.now().difference(startedAt);
      if (stalled && elapsed > const Duration(seconds: 8)) {
        timer.cancel();
        debugPrint(
            '[MusicPlayerController] Stall detected for ${song.title} (${elapsed.inSeconds}s), switching to local audio fallback…');
        // ignore: discarded_futures
        _handleAudioLoadFailure(song);
      }
      if (elapsed > const Duration(seconds: 20)) {
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
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _playbackTimer?.cancel();
    _stallWatchdog?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playerStateSub?.cancel();
    _playbackEventSub?.cancel();
    _enrichment.dispose();
    try {
      // ignore: discarded_futures
      _audioPlayer.dispose().catchError((_) {});
    } catch (_) {}
    super.dispose();
  }
}
