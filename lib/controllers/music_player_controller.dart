import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../models/song_model.dart';

enum PlaybackRepeatMode { off, all, one }

class MusicPlayerController extends ChangeNotifier {
  final List<Song> _allSongs = [];
  late List<Song> _queue;
  int _currentIndex = 0;

  bool _isPlaying = false;
  Duration _currentPosition = Duration.zero;
  double _volume = 0.8;
  double _prevVolume = 0.8;
  bool _isMuted = false;
  bool _isShuffle = false;
  PlaybackRepeatMode _repeatMode = PlaybackRepeatMode.all;
  Timer? _playbackTimer;

  String _searchQuery = '';
  String _selectedGenre = 'All';
  int _currentNavIndex = 0; // 0: Home, 1: Explore, 2: Library, 3: Favorites

  MusicPlayerController() {
    _allSongs.addAll(SampleMusicData.sampleSongs);
    _queue = List<Song>.from(_allSongs);
  }

  // Getters
  List<Song> get allSongs => _allSongs;
  List<Song> get queue => _queue;
  int get currentIndex => _currentIndex;
  Song? get currentSong => (_queue.isNotEmpty && _currentIndex >= 0 && _currentIndex < _queue.length)
      ? _queue[_currentIndex]
      : null;
  bool get isPlaying => _isPlaying;
  Duration get currentPosition => _currentPosition;
  Duration get currentDuration => currentSong?.duration ?? Duration.zero;
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
    _isPlaying = false;
    _playbackTimer?.cancel();
    notifyListeners();
  }

  void clearSongs() {
    _allSongs.clear();
    _queue.clear();
    _currentIndex = 0;
    _currentPosition = Duration.zero;
    _isPlaying = false;
    _playbackTimer?.cancel();
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
    _isPlaying = true;
    _startTimer();
    notifyListeners();
  }

  void togglePlayPause() {
    if (currentSong == null) return;
    _isPlaying = !_isPlaying;
    if (_isPlaying) {
      _startTimer();
    } else {
      _playbackTimer?.cancel();
    }
    notifyListeners();
  }

  void play() {
    if (currentSong == null) return;
    if (!_isPlaying) {
      _isPlaying = true;
      _startTimer();
      notifyListeners();
    }
  }

  void pause() {
    if (_isPlaying) {
      _isPlaying = false;
      _playbackTimer?.cancel();
      notifyListeners();
    }
  }

  void next() {
    if (_queue.isEmpty) return;

    if (_repeatMode == PlaybackRepeatMode.one) {
      _currentPosition = Duration.zero;
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
    if (_isPlaying) {
      _startTimer();
    }
    notifyListeners();
  }

  void previous() {
    if (_queue.isEmpty) return;

    if (_currentPosition.inSeconds > 3) {
      _currentPosition = Duration.zero;
    } else {
      if (_currentIndex > 0) {
        _currentIndex--;
      } else {
        _currentIndex = _queue.length - 1;
      }
      _currentPosition = Duration.zero;
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
    notifyListeners();
  }

  void setVolume(double val) {
    _volume = val.clamp(0.0, 1.0);
    if (_volume > 0) {
      _isMuted = false;
    }
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

  void _startTimer() {
    _playbackTimer?.cancel();
    _playbackTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isPlaying) {
        timer.cancel();
        return;
      }
      if (_currentPosition < currentDuration) {
        _currentPosition += const Duration(seconds: 1);
        notifyListeners();
      } else {
        next();
      }
    });
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    super.dispose();
  }
}
