import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../models/song_model.dart';

enum PlaybackRepeatMode { off, all, one }

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
  bool _audioPlayerHasSource = false;
  int _playSessionId = 0;

  String _searchQuery = '';
  String _selectedGenre = 'All';
  int _currentNavIndex = 0; // 0: Home, 1: Explore, 2: Library, 3: Favorites

  MusicPlayerController() {
    _allSongs.addAll(SampleMusicData.sampleSongs);
    _playlists.addAll(SampleMusicData.initialPlaylists);
    _queue = List<Song>.from(_allSongs);

    _initAudioPlayer();
  }

  void _initAudioPlayer() {
    try {
      _audioPlayer.setVolume(_volume);

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

      // Listen to player completion for auto-next
      _playerStateSub = _audioPlayer.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          _onSongComplete();
        }
      });
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
      id: 'playlist-${DateTime.now().microsecondsSinceEpoch}',
      title: trimmedName,
      subtitle: 'Created by you',
      gradient: const [Color(0xFF11998E), Color(0xFF38EF7D)],
    ));
    notifyListeners();
    return true;
  }

  bool addSongToPlaylist(String playlistId, Song song) {
    final playlist = playlistById(playlistId);
    if (playlist == null || playlist.songIds.contains(song.id)) return false;
    playlist.songIds.add(song.id);
    notifyListeners();
    return true;
  }

  void playPlaylist(String playlistId) {
    final songs = songsForPlaylist(playlistId);
    if (songs.isEmpty) return;
    _queue = List<Song>.from(songs);
    _currentIndex = 0;
    _currentPosition = Duration.zero;
    _audioDuration = Duration.zero;
    _isPlaying = true;
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
    try { _audioPlayer.stop(); } catch (_) {}
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
    try { _audioPlayer.stop(); } catch (_) {}
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
    _isPlaying = true;
    _startTimer();
    _playCurrentSongAudio();
    notifyListeners();
  }

  void togglePlayPause() {
    if (currentSong == null) return;
    _isPlaying = !_isPlaying;
    if (_isPlaying) {
      if (_audioPlayerHasSource) {
        try { _audioPlayer.play(); } catch (_) {}
      } else {
        _startTimer();
      }
    } else {
      if (_audioPlayerHasSource) {
        try { _audioPlayer.pause(); } catch (_) {}
      }
      _playbackTimer?.cancel();
    }
    notifyListeners();
  }

  void play() {
    if (currentSong == null) return;
    if (!_isPlaying) {
      _isPlaying = true;
      if (_audioPlayerHasSource) {
        try { _audioPlayer.play(); } catch (_) {}
      } else {
        _startTimer();
      }
      notifyListeners();
    }
  }

  void pause() {
    if (_isPlaying) {
      _isPlaying = false;
      if (_audioPlayerHasSource) {
        try { _audioPlayer.pause(); } catch (_) {}
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
    if (_audioPlayerHasSource) {
      try { _audioPlayer.seek(_currentPosition); } catch (_) {}
    }
    notifyListeners();
  }

  void setVolume(double val) {
    _volume = val.clamp(0.0, 1.0);
    if (_volume > 0) {
      _isMuted = false;
    }
    try { _audioPlayer.setVolume(_isMuted ? 0.0 : _volume); } catch (_) {}
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
    try { _audioPlayer.setVolume(_isMuted ? 0.0 : _volume); } catch (_) {}
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

  /// Load and play the current song's audio URL or asset
  Future<void> _playCurrentSongAudio() async {
    final song = currentSong;
    if (song == null) return;

    final sessionId = ++_playSessionId;

    if (song.audioUrl.isNotEmpty) {
      try {
        if (song.audioUrl.startsWith('assets/')) {
          await _audioPlayer.setAsset(song.audioUrl);
        } else if (song.audioUrl.startsWith('http://') || song.audioUrl.startsWith('https://')) {
          await _audioPlayer.setUrl(song.audioUrl);
        }
        if (sessionId != _playSessionId) return;

        _audioPlayerHasSource = true;
        _playbackTimer?.cancel();
        await _audioPlayer.setVolume(_isMuted ? 0.0 : _volume);
        if (_isPlaying) {
          await _audioPlayer.play();
        }
      } catch (e) {
        if (sessionId != _playSessionId) return;
        debugPrint('Audio playback load error for ${song.title}: $e');
        _audioPlayerHasSource = false;
        if (_isPlaying) {
          _startTimer();
        }
      }
    } else {
      _audioPlayerHasSource = false;
      if (_isPlaying) {
        _startTimer();
      }
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

  @override
  void dispose() {
    _playbackTimer?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playerStateSub?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }
}
