import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
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

  /// Session of the most recent successfully loaded source. Async media
  /// errors (e.g. Windows MediaFailed) carry no source identity, so this
  /// guards the error handler against reacting to a stale source after a
  /// newer load has already succeeded.
  int _loadedSessionId = 0;

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
  }

  void _initAudioPlayer() {
    try {
      // ignore: discarded_futures
      _audioPlayer.setVolume(_volume).catchError((_) {});

      // Listen to position updates from real audio player
      _positionSub = _audioPlayer.positionStream.listen((pos) {
        if (_audioPlayerHasSource && _isPlaying && pos > Duration.zero) {
          _currentPosition = pos;
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
        if (state.processingState == ProcessingState.completed) {
          _onSongComplete();
        }
      });

      // Async media failures (e.g. Windows MediaPlayer MediaFailed for a
      // rejected stream URL) arrive on the playback-event channel — just_audio
      // swallows them internally, so without this the UI would sit "muted" on
      // a dead source with no timer and no sound. Recover the same way as a
      // load error: refresh an expired YouTube URL once, else fall back.
      _playbackEventSub = _audioPlayer.playbackEventStream.listen(
        (_) {},
        onError: (Object e) {
          final song = currentSong;
          if (song == null || !_audioPlayerHasSource) return;
          if (_playSessionId != _loadedSessionId) return;
          _loadedSessionId = -1;
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
              audioUrl: s['audio_url'] as String? ?? '',
              isPreview: s['is_preview'] as bool? ?? false,
              isYouTubeAudio: s['is_youtube_audio'] as bool? ?? false,
            );
            _allSongs.add(song);
            if (!_queue.any((existing) => existing.id == songId)) {
              _queue.add(song);
            }
            hasChanges = true;
          } else {
            final existing = _allSongs[existingIdx];
            final dbAudio = s['audio_url'] as String? ?? '';
            if (existing.isSilentPlaceholder && dbAudio.isNotEmpty) {
              existing.audioUrl = dbAudio;
              existing.isPreview = s['is_preview'] as bool? ?? false;
              existing.isYouTubeAudio = s['is_youtube_audio'] as bool? ?? false;
              hasChanges = true;
            }
            final dbLyrics = (s['lyrics'] as List<dynamic>? ?? []).map((e) => e.toString()).toList();
            if (existing.lyrics.isEmpty && dbLyrics.isNotEmpty) {
              existing.lyrics = dbLyrics;
              hasChanges = true;
            }
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
        final toEnrich = _allSongs
            .where((s) => s.id.startsWith('spotify-') && (s.isSilentPlaceholder || s.isPreview))
            .toList();
        if (toEnrich.isNotEmpty) {
          _enrichImportedSongs(toEnrich);
        }
      }
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

  Song? _findLocalMatch(SpotifyImportedTrack imported) {
    final titleKey = _normalizeKey(imported.title);
    final artistKey = _normalizeKey(imported.artist);
    if (titleKey.isEmpty) return null;

    Song? artistMatched;
    for (final song in _allSongs) {
      if (_normalizeKey(song.title) != titleKey) continue;
      final songArtist = _normalizeKey(song.artist);
      if (songArtist == artistKey || songArtist.isEmpty || artistKey.isEmpty) {
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
      final needsAudio = s.isSilentPlaceholder ||
          (s.isPreview && _shouldAttemptFullUpgrade(s.id));
      final needsLyrics =
          s.lyrics.isEmpty && !_enrichedIds.contains(s.id);
      return needsAudio || needsLyrics;
    }).toList();
    for (final song in pending) {
      _enrichingIds.add(song.id);
      if (song.isPreview) {
        _fullUpgradeAttemptedAt[song.id] = DateTime.now();
      }
      // ignore: discarded_futures
      _enrichOneSong(song);
    }
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
      _enrichedIds.add(song.id);
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

    final shouldAttachAudio = enrichment.hasAudio &&
        (!song.hasAudio || (enrichment.isFullTrack && song.isPreview));
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
      if (enrichment.isFullTrack) {
        _fullUpgradeAttemptedAt.remove(song.id);
      }
      // Hot-swap mid-playback: silent -> real audio, or preview -> full.
      if (song.id == currentSong?.id && _isPlaying && !_audioPlayerHasSource) {
        _unmuteOnPlay();
        // ignore: discarded_futures
        _playCurrentSongAudio();
      } else if (song.id == currentSong?.id &&
          _isPlaying &&
          _audioPlayerHasSource &&
          enrichment.isFullTrack) {
        _unmuteOnPlay();
        // ignore: discarded_futures
        _playCurrentSongAudio().then((_) {
          if (resumePosition > Duration.zero) {
            seekTo(resumePosition);
          }
        });
      }
    }

    if (enrichment.hasLyrics && song.lyrics.isEmpty) {
      song.lyrics = enrichment.lyrics;
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
    }

    return changed;
  }

  /// Public retry used by the lyrics sheet when a track has no lyrics yet
  /// (or is still stuck on a 30s preview). Returns true when lyrics are
  /// now available.
  Future<bool> ensureLyricsFor(Song song) async {
    final needsLyrics = song.lyrics.isEmpty;
    final needsFullAudio = song.isPreview && _shouldAttemptFullUpgrade(song.id);
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
      _enrichedIds.add(song.id);
      final changed = _applyEnrichment(song, enrichment);
      song.isEnrichingLyrics = false;
      if (changed) notifyListeners();
      return song.lyrics.isNotEmpty;
    } catch (_) {
      song.isEnrichingLyrics = false;
      notifyListeners();
      return false;
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
    _unmuteOnPlay();
    _isPlaying = true;
    _playbackTimer?.cancel();
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
    _unmuteOnPlay();
    _isPlaying = true;
    _playbackTimer?.cancel();
    _playCurrentSongAudio();
    notifyListeners();
  }

  void togglePlayPause() {
    if (currentSong == null) return;
    _isPlaying = !_isPlaying;
    if (_isPlaying) {
      _unmuteOnPlay();
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
    }
    notifyListeners();
  }

  void play() {
    if (currentSong == null) return;
    if (!_isPlaying) {
      _unmuteOnPlay();
      _isPlaying = true;
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
      notifyListeners();
    }
  }

  void next() {
    if (_queue.isEmpty) return;

    if (_repeatMode == PlaybackRepeatMode.one) {
      _currentPosition = Duration.zero;
      _audioDuration = Duration.zero;
      _playCurrentSongAudio();
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
      _playbackTimer?.cancel();
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
        _playbackTimer?.cancel();
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
        _playbackTimer?.cancel();
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
  ///
  /// Imported Spotify tracks start with no audioUrl (Spotify grants no
  /// direct stream). Until enrichment resolves audio we stop any stale
  /// real-audio source and drive the UI with the simulated timer — and
  /// kick off a lookup so the track becomes audible instead of staying
  /// "muted".
  Future<void> _playCurrentSongAudio() async {
    final song = currentSong;
    if (song == null) return;

    final sessionId = ++_playSessionId;

    // Opportunistic upgrade: a playing 30s preview may now have a
    // full-length stream available. Retry on a cooldown (not once per
    // session) without blocking playback — the preview keeps playing and
    // hot-swaps when full audio resolves.
    if (song.isPreview &&
        !_enrichingIds.contains(song.id) &&
        _shouldAttemptFullUpgrade(song.id)) {
      _fullUpgradeAttemptedAt[song.id] = DateTime.now();
      _enrichingIds.add(song.id);
      // ignore: discarded_futures
      _enrichOneSong(song);
    }

    // No playable source yet: clear stale audio so the previous song
    // doesn't keep ringing. If this is the song the user wants to play,
    // prioritize and wait for enrichment right now so it plays immediately
    // with audible sound instead of silently running a fake timer.
    if (song.audioUrl.isEmpty) {
      _audioPlayerHasSource = false;
      try {
        await _audioPlayer.stop();
      } catch (_) {}
      _playbackTimer?.cancel();

      if (song.id == currentSong?.id) {
        if (!_enrichingIds.contains(song.id) && !_enrichedIds.contains(song.id)) {
          _enrichingIds.add(song.id);
          await _enrichOneSong(song);
        } else if (_enrichingIds.contains(song.id)) {
          // Wait for in-flight enrichment to complete instead of running a silent timer.
          for (var i = 0; i < 20; i++) {
            if (!_enrichingIds.contains(song.id) || song.hasAudio) break;
            await Future.delayed(const Duration(milliseconds: 300));
          }
        }
        if (sessionId != _playSessionId) return;
        if (song.hasAudio) {
          await _playCurrentSongAudio();
          return;
        }
      }

      if (_isPlaying) _startTimer();
      return;
    }

    try {
      if (song.audioUrl.startsWith('assets/')) {
        await _audioPlayer.setAsset(song.audioUrl);
      } else if (song.audioUrl.startsWith('http://') ||
          song.audioUrl.startsWith('https://')) {
        // No request headers: just_audio_windows has no native header
        // support, and the just_audio local proxy only answers GET —
        // adding headers would risk breaking Windows Media Player loads.
        await _audioPlayer.setUrl(song.audioUrl);
      } else {
        // Unknown scheme — treat as silent rather than crashing playback.
        _audioPlayerHasSource = false;
        try {
          await _audioPlayer.stop();
        } catch (_) {}
        if (_isPlaying) _startTimer();
        return;
      }
      if (sessionId != _playSessionId) return;

      _audioPlayerHasSource = true;
      _loadedSessionId = sessionId;
      _ytRefreshAttemptedIds.remove(song.id);
      _playbackTimer?.cancel();

      _unmuteOnPlay();
      final effectiveVolume = _isMuted ? 0.0 : (_volume > 0.05 ? _volume : 0.8);
      try {
        await _audioPlayer.setVolume(effectiveVolume);
      } catch (_) {}
      if (_isPlaying) {
        await _audioPlayer.play();
        // Windows Media Player / Android ExoPlayer can drop or reset the
        // stream volume while transitioning states asynchronously. Re-assert
        // immediately and after micro-delays to guarantee audible playback.
        if (sessionId == _playSessionId) {
          try {
            await _audioPlayer.setVolume(effectiveVolume);
          } catch (_) {}
          for (final delayMs in const [80, 200, 450, 800]) {
            Future.delayed(Duration(milliseconds: delayMs), () {
              if (sessionId == _playSessionId && _audioPlayerHasSource && !_isMuted) {
                try {
                  // ignore: discarded_futures
                  _audioPlayer.setVolume(effectiveVolume).catchError((_) {});
                } catch (_) {}
              }
            });
          }
        }
      }
    } catch (e) {
      if (sessionId != _playSessionId || _disposed) return;
      debugPrint('Audio playback load error for ${song.title}: $e');
      await _handleAudioLoadFailure(song);
    }
  }

  /// Shared recovery for sync load errors and async media failures.
  ///
  /// YouTube stream URLs expire after a few hours. When a saved one fails,
  /// resolve a fresh URL once and retry. If any imported full stream is still
  /// rejected by the native player, switch once to the compatible 30-second
  /// iTunes/Deezer fallback instead of leaving a moving-but-silent player.
  Future<void> _handleAudioLoadFailure(Song song) async {
    if (_disposed) return;
    if (song.isYouTubeAudio && _ytRefreshAttemptedIds.add(song.id)) {
      song.audioUrl = '';
      song.isYouTubeAudio = false;
      _audioPlayerHasSource = false;
      notifyListeners();
      if (song.id == currentSong?.id) {
        _enrichingIds.add(song.id);
        await _enrichOneSong(song);
        if (song.hasAudio && song.id == currentSong?.id) {
          await _playCurrentSongAudio();
          return;
        }
      }
    }

    if (song.id.startsWith('spotify-') &&
        _audioFallbackAttemptedIds.add(song.id)) {
      song.audioUrl = '';
      song.isPreview = false;
      song.isYouTubeAudio = false;
      _audioPlayerHasSource = false;
      notifyListeners();
      if (song.id == currentSong?.id) {
        _enrichingIds.add(song.id);
        await _enrichOneSong(song, previewFallbackOnly: true);
        if (song.hasAudio && song.id == currentSong?.id) {
          await _playCurrentSongAudio();
          return;
        }
      }
    }
    _audioPlayerHasSource = false;
    notifyListeners();
    if (_isPlaying) {
      _startTimer();
    }
  }

  /// Called when audio completes a song
  void _onSongComplete() {
    if (_repeatMode == PlaybackRepeatMode.one) {
      _currentPosition = Duration.zero;
      _playCurrentSongAudio();
      notifyListeners();
    } else {
      next();
    }
  }

  /// Reliable playback timer that drives UI position, progress, and song completion
  /// when real audio playback is not actively driving the stream
  void _startTimer() {
    _playbackTimer?.cancel();
    if (_audioPlayerHasSource) return;
    _playbackTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isPlaying || _audioPlayerHasSource) {
        timer.cancel();
        return;
      }
      if (_currentPosition < currentDuration) {
        _currentPosition += const Duration(seconds: 1);
        notifyListeners();
      } else {
        timer.cancel();
        _onSongComplete();
      }
    });
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
