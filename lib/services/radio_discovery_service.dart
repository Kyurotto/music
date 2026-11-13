import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/song_model.dart';
import '../theme/app_theme.dart';

/// Represents a Spotify-style Radio Station with artist highlights,
/// vibrant background styling, and a pre-curated or dynamic track list.
class RadioStation {
  final String id;
  final String title;
  final String artistName;
  final String subtitle;
  final Color backgroundColor;
  final List<Color> gradientColors;
  final List<String> avatarUrls;
  final List<Song> songs;
  final String heroImageUrl;

  const RadioStation({
    required this.id,
    required this.title,
    required this.artistName,
    required this.subtitle,
    required this.backgroundColor,
    required this.gradientColors,
    this.avatarUrls = const [],
    this.songs = const [],
    this.heroImageUrl = '',
  });

  /// Converts this radio station into a [MusicPlaylist] representation
  /// so it can be played, enqueued, or displayed in [PlaylistScreen].
  MusicPlaylist toPlaylist() {
    return MusicPlaylist(
      id: 'radio-$id',
      title: title,
      subtitle: subtitle,
      gradient: gradientColors,
      imageUrl: heroImageUrl.isNotEmpty
          ? heroImageUrl
          : (avatarUrls.isNotEmpty ? avatarUrls.first : ''),
      songIds: songs.map((s) => s.id).toList(),
    );
  }
}

/// Represents an artist in the Spotify-style Library and Sidebar
class ArtistProfile {
  final String name;
  final String imageUrl;
  final List<Color> gradientColors;
  final String subtitle;

  const ArtistProfile({
    required this.name,
    this.imageUrl = '',
    this.gradientColors = const [Color(0xFF334155), Color(0xFF64748B)],
    this.subtitle = 'Artist',
  });
}

/// Represents a Spotify-style Daily Mix with dual-tone header,
/// mix number badge (01, 02, etc.), artist subtitle, and curated songs.
class DailyMix {
  final String id;
  final String title;
  final String number;
  final Color accentColor;
  final List<Color> gradientColors;
  final String subtitle;
  final List<Song> songs;

  const DailyMix({
    required this.id,
    required this.title,
    required this.number,
    required this.accentColor,
    required this.gradientColors,
    required this.subtitle,
    this.songs = const [],
  });

  MusicPlaylist toPlaylist() {
    return MusicPlaylist(
      id: 'dailymix-$id',
      title: title,
      subtitle: subtitle,
      gradient: gradientColors,
      imageUrl: '',
      songIds: songs.map((s) => s.id).toList(),
    );
  }
}

/// Service providing curated and dynamic "Popular radio" stations
/// inspired by the Spotify Web Player radio feature.
class RadioDiscoveryService {
  final http.Client _client;
  final Map<String, RadioStation> _radioCache = {};
  List<RadioStation> _cachedTrendingRadios = [];
  List<RadioStation> _cachedOpmRadios = [];
  List<RadioStation> _cachedGlobalRadios = [];

  RadioDiscoveryService({http.Client? client}) : _client = client ?? http.Client();
  static final RadioDiscoveryService instance = RadioDiscoveryService();

  /// Curated Spotify Daily Mixes matching Screenshot 1
  List<DailyMix> getDailyMixes() {
    return [
      DailyMix(
        id: '01',
        title: 'Daily Mix 01',
        number: '01',
        accentColor: const Color(0xFF0D9488), // Cyan/Teal
        gradientColors: const [Color(0xFF0D9488), Color(0xFF14B8A6)],
        subtitle: 'Taylor Swift, Maroon 5, Bruno Mars and more',
        songs: [
          Song(
            id: 'dm-1-1',
            title: 'Blank Space',
            artist: 'Taylor Swift',
            album: '1989',
            duration: const Duration(minutes: 3, seconds: 51),
            genre: 'Pop',
            imageUrl: '',
            gradientColors: const [Color(0xFF0D9488), Color(0xFF14B8A6)],
            plays: '1.9B',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'dm-1-2',
            title: 'Just the Way You Are',
            artist: 'Bruno Mars',
            album: 'Doo-Wops & Hooligans',
            duration: const Duration(minutes: 3, seconds: 39),
            genre: 'Pop',
            imageUrl: '',
            gradientColors: const [Color(0xFF0D9488), Color(0xFF14B8A6)],
            plays: '2.3B',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'dm-1-3',
            title: 'Sugar',
            artist: 'Maroon 5',
            album: 'V',
            duration: const Duration(minutes: 3, seconds: 55),
            genre: 'Pop',
            imageUrl: '',
            gradientColors: const [Color(0xFF0D9488), Color(0xFF14B8A6)],
            plays: '1.8B',
            lyrics: const [],
            isPreview: false,
          ),
        ],
      ),
      DailyMix(
        id: '02',
        title: 'Daily Mix 02',
        number: '02',
        accentColor: const Color(0xFFCA8A04), // Yellow/Amber
        gradientColors: const [Color(0xFFCA8A04), Color(0xFFEAB308)],
        subtitle: 'Top Suzara, Sugarfree, Freestyle and more',
        songs: [
          Song(
            id: 'dm-2-1',
            title: 'Hari ng Sablay',
            artist: 'Sugarfree',
            album: 'Sa Wakas',
            duration: const Duration(minutes: 4, seconds: 12),
            genre: 'OPM',
            imageUrl: '',
            gradientColors: const [Color(0xFFCA8A04), Color(0xFFEAB308)],
            plays: '28.4M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'dm-2-2',
            title: 'Before I Let You Go',
            artist: 'Freestyle',
            album: 'Freestyle',
            duration: const Duration(minutes: 4, seconds: 40),
            genre: 'OPM',
            imageUrl: '',
            gradientColors: const [Color(0xFFCA8A04), Color(0xFFEAB308)],
            plays: '42.1M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'dm-2-3',
            title: 'Burnout',
            artist: 'Sugarfree',
            album: 'Dramamachine',
            duration: const Duration(minutes: 4, seconds: 20),
            genre: 'OPM',
            imageUrl: '',
            gradientColors: const [Color(0xFFCA8A04), Color(0xFFEAB308)],
            plays: '55.3M',
            lyrics: const [],
            isPreview: false,
          ),
        ],
      ),
      DailyMix(
        id: '03',
        title: 'Daily Mix 03',
        number: '03',
        accentColor: const Color(0xFFEA580C), // Orange
        gradientColors: const [Color(0xFFEA580C), Color(0xFFF97316)],
        subtitle: 'Ed Sheeran, Boyce Avenue, Coldplay and more',
        songs: [
          Song(
            id: 'dm-3-1',
            title: 'Yellow',
            artist: 'Coldplay',
            album: 'Parachutes',
            duration: const Duration(minutes: 4, seconds: 29),
            genre: 'Alternative',
            imageUrl: '',
            gradientColors: const [Color(0xFFEA580C), Color(0xFFF97316)],
            plays: '2.1B',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'dm-3-2',
            title: 'Shape of You',
            artist: 'Ed Sheeran',
            album: '÷',
            duration: const Duration(minutes: 3, seconds: 53),
            genre: 'Pop',
            imageUrl: '',
            gradientColors: const [Color(0xFFEA580C), Color(0xFFF97316)],
            plays: '3.6B',
            lyrics: const [],
            isPreview: false,
          ),
        ],
      ),
      DailyMix(
        id: '04',
        title: 'Daily Mix 04',
        number: '04',
        accentColor: const Color(0xFFC026D3), // Magenta/Purple
        gradientColors: const [Color(0xFFC026D3), Color(0xFFE879F9)],
        subtitle: 'fitterkarma, Adie, Wilbert Ross and more',
        songs: [
          Song(
            id: 'dm-4-1',
            title: 'Paraluman',
            artist: 'Adie',
            album: 'Paraluman',
            duration: const Duration(minutes: 5, seconds: 12),
            genre: 'OPM',
            imageUrl: '',
            gradientColors: const [Color(0xFFC026D3), Color(0xFFE879F9)],
            plays: '180.2M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'dm-4-2',
            title: 'Mahika',
            artist: 'Adie, Janine Berdin',
            album: 'Mahika',
            duration: const Duration(minutes: 3, seconds: 22),
            genre: 'OPM',
            imageUrl: '',
            gradientColors: const [Color(0xFFC026D3), Color(0xFFE879F9)],
            plays: '145.7M',
            lyrics: const [],
            isPreview: false,
          ),
        ],
      ),
      DailyMix(
        id: '05',
        title: 'Daily Mix 05',
        number: '05',
        accentColor: const Color(0xFF2563EB), // Blue
        gradientColors: const [Color(0xFF2563EB), Color(0xFF3B82F6)],
        subtitle: 'Staind, Doors, Daughtry and more',
        songs: [
          Song(
            id: 'dm-5-1',
            title: "It's Been Awhile",
            artist: 'Staind',
            album: 'Break the Cycle',
            duration: const Duration(minutes: 4, seconds: 25),
            genre: 'Rock',
            imageUrl: '',
            gradientColors: const [Color(0xFF2563EB), Color(0xFF3B82F6)],
            plays: '410.5M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'dm-5-2',
            title: 'Riders on the Storm',
            artist: 'The Doors',
            album: 'L.A. Woman',
            duration: const Duration(minutes: 7, seconds: 14),
            genre: 'Classic Rock',
            imageUrl: '',
            gradientColors: const [Color(0xFF2563EB), Color(0xFF3B82F6)],
            plays: '530.2M',
            lyrics: const [],
            isPreview: false,
          ),
        ],
      ),
    ];
  }

  /// Curated Spotify "Recents" tracks
  List<Song> getRecentDiscoveryReleases() {
    return [
      Song(
        id: 'recent-1',
        title: 'Makasarili Malambing',
        artist: 'Kristina Dawn, Hev Abi',
        album: 'Makasarili Malambing',
        duration: const Duration(minutes: 3, seconds: 44),
        genre: 'Hip-Hop',
        imageUrl: '',
        gradientColors: const [Color(0xFF7C3AED), Color(0xFFA855F7)],
        plays: '68.9M',
        lyrics: const [],
        isPreview: false,
      ),
      Song(
        id: 'recent-2',
        title: 'Ebeb',
        artist: 'Flow G',
        album: 'Ebeb',
        duration: const Duration(minutes: 4, seconds: 21),
        genre: 'Hip-Hop',
        imageUrl: '',
        gradientColors: const [Color(0xFF1E3A8A), Color(0xFF3B82F6)],
        plays: '45.2M',
        lyrics: const [],
        isPreview: false,
      ),
      Song(
        id: 'recent-3',
        title: 'Uhaw (Tayong Lahat)',
        artist: 'Dilaw',
        album: 'Sansinukob',
        duration: const Duration(minutes: 4, seconds: 1),
        genre: 'Indie Rock',
        imageUrl: '',
        gradientColors: const [Color(0xFF0284C7), Color(0xFF38BDF8)],
        plays: '175.9M',
        lyrics: const [],
        isPreview: false,
      ),
      Song(
        id: 'recent-4',
        title: 'TMA',
        artist: 'groundZERO Records, Tyler, Primera, ODP',
        album: 'TMA',
        duration: const Duration(minutes: 3, seconds: 18),
        genre: 'Hip-Hop',
        imageUrl: '',
        gradientColors: const [Color(0xFF1E3A8A), Color(0xFF3B82F6)],
        plays: '18.4M',
        lyrics: const [],
        isPreview: false,
      ),
      Song(
        id: 'recent-5',
        title: 'Paninindigan Kita',
        artist: 'Ben&Ben',
        album: 'Pebble House, Vol. 1',
        duration: const Duration(minutes: 5, seconds: 11),
        genre: 'Folk-Pop',
        imageUrl: '',
        gradientColors: const [Color(0xFFEA580C), Color(0xFFFB923C)],
        plays: '142.0M',
        lyrics: const [],
        isPreview: false,
      ),
    ];
  }

  /// Curated artists inspired by the Spotify library screen
  List<ArtistProfile> getCuratedArtists() {
    return const [
      ArtistProfile(
        name: 'Sugarfree',
        gradientColors: [Color(0xFF047857), Color(0xFF10B981)],
      ),
      ArtistProfile(
        name: 'Bruno Mars',
        gradientColors: [Color(0xFF374151), Color(0xFF4B5563)],
      ),
      ArtistProfile(
        name: 'MATÉO',
        gradientColors: [Color(0xFF1E293B), Color(0xFF334155)],
      ),
      ArtistProfile(
        name: 'Adie',
        gradientColors: [Color(0xFF1D4ED8), Color(0xFF3B82F6)],
      ),
      ArtistProfile(
        name: 'Tothapi',
        gradientColors: [Color(0xFF18181B), Color(0xFF27272A)],
      ),
    ];
  }

  /// Returns dynamic trending radios if fetched, or fallback radios initially
  List<RadioStation> getPopularRadios() {
    if (_cachedTrendingRadios.isNotEmpty) {
      return _cachedTrendingRadios;
    }
    return _fallbackPopularRadios();
  }

  /// Curated fallback Popular Radio stations matching the Spotify Web Player layout.
  List<RadioStation> _fallbackPopularRadios() {
    return [
      RadioStation(
        id: 'flow-g',
        title: 'Flow G Radio',
        artistName: 'Flow G',
        subtitle: 'With SUPAFLY, Lo ki, Hev Abi and more',
        backgroundColor: const Color(0xFF1E3A8A), // Deep Blue
        gradientColors: const [Color(0xFF1E3A8A), Color(0xFF3B82F6)],
        heroImageUrl: '',
        songs: [
          Song(
            id: 'radio-flowg-1',
            title: 'Ebeb',
            artist: 'Flow G',
            album: 'Ebeb',
            duration: const Duration(minutes: 4, seconds: 21),
            genre: 'Hip-Hop',
            imageUrl: '',
            gradientColors: const [Color(0xFF1E3A8A), Color(0xFF3B82F6)],
            plays: '45.2M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-flowg-2',
            title: 'TMA',
            artist: 'groundZERO Records, Tyler, Primera, ODP',
            album: 'TMA',
            duration: const Duration(minutes: 3, seconds: 18),
            genre: 'Hip-Hop',
            imageUrl: '',
            gradientColors: const [Color(0xFF1E3A8A), Color(0xFF3B82F6)],
            plays: '18.4M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-flowg-3',
            title: 'Rosas',
            artist: 'Yuridope, Skusta Clee',
            album: 'Rosas',
            duration: const Duration(minutes: 4, seconds: 10),
            genre: 'Hip-Hop',
            imageUrl: '',
            gradientColors: const [Color(0xFF1E3A8A), Color(0xFF3B82F6)],
            plays: '32.1M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-flowg-4',
            title: 'Since Day One',
            artist: 'Skusta Clee, Flow G',
            album: 'Since Day One',
            duration: const Duration(minutes: 3, seconds: 11),
            genre: 'Hip-Hop',
            imageUrl: '',
            gradientColors: const [Color(0xFF1E3A8A), Color(0xFF3B82F6)],
            plays: '52.7M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-flowg-5',
            title: 'Makasarili Malambing',
            artist: 'Kristina Dawn, Hev Abi',
            album: 'Makasarili Malambing',
            duration: const Duration(minutes: 3, seconds: 44),
            genre: 'R&B',
            imageUrl: '',
            gradientColors: const [Color(0xFF1E3A8A), Color(0xFF3B82F6)],
            plays: '68.9M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-flowg-6',
            title: 'Praning',
            artist: 'Flow G',
            album: 'Praning',
            duration: const Duration(minutes: 3, seconds: 35),
            genre: 'Hip-Hop',
            imageUrl: '',
            gradientColors: const [Color(0xFF1E3A8A), Color(0xFF3B82F6)],
            plays: '38.5M',
            lyrics: const [],
            isPreview: false,
          ),
        ],
      ),
      RadioStation(
        id: 'air-supply',
        title: 'Air Supply Radio',
        artistName: 'Air Supply',
        subtitle: 'With Chicago, Peter Cetera, Bread and more',
        backgroundColor: const Color(0xFF0F766E), // Teal
        gradientColors: const [Color(0xFF0F766E), Color(0xFF14B8A6)],
        heroImageUrl: '',
        songs: [
          Song(
            id: 'radio-as-1',
            title: 'All Out of Love',
            artist: 'Air Supply',
            album: 'Lost in Love',
            duration: const Duration(minutes: 4, seconds: 2),
            genre: 'Soft Rock',
            imageUrl: '',
            gradientColors: const [Color(0xFF0F766E), Color(0xFF14B8A6)],
            plays: '85.4M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-as-2',
            title: 'Making Love Out of Nothing at All',
            artist: 'Air Supply',
            album: 'Greatest Hits',
            duration: const Duration(minutes: 5, seconds: 41),
            genre: 'Soft Rock',
            imageUrl: '',
            gradientColors: const [Color(0xFF0F766E), Color(0xFF14B8A6)],
            plays: '112.0M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-as-3',
            title: 'Hard to Say I\'m Sorry',
            artist: 'Chicago',
            album: 'Chicago 16',
            duration: const Duration(minutes: 3, seconds: 52),
            genre: 'Soft Rock',
            imageUrl: '',
            gradientColors: const [Color(0xFF0F766E), Color(0xFF14B8A6)],
            plays: '94.2M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-as-4',
            title: 'Glory of Love',
            artist: 'Peter Cetera',
            album: 'Solitude / Solitaire',
            duration: const Duration(minutes: 4, seconds: 20),
            genre: 'Soft Rock',
            imageUrl: '',
            gradientColors: const [Color(0xFF0F766E), Color(0xFF14B8A6)],
            plays: '76.8M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-as-5',
            title: 'Make It With You',
            artist: 'Bread',
            album: 'On the Waters',
            duration: const Duration(minutes: 3, seconds: 15),
            genre: 'Soft Rock',
            imageUrl: '',
            gradientColors: const [Color(0xFF0F766E), Color(0xFF14B8A6)],
            plays: '62.4M',
            lyrics: const [],
            isPreview: false,
          ),
        ],
      ),
      RadioStation(
        id: 'lany',
        title: 'LANY Radio',
        artistName: 'LANY',
        subtitle: 'With Bazzi, elijah woods, Lauv and more',
        backgroundColor: const Color(0xFF059669), // Mint Green
        gradientColors: const [Color(0xFF059669), Color(0xFF10B981)],
        heroImageUrl: '',
        songs: [
          Song(
            id: 'radio-lany-1',
            title: 'ILYSB',
            artist: 'LANY',
            album: 'Make Out',
            duration: const Duration(minutes: 3, seconds: 31),
            genre: 'Indie Pop',
            imageUrl: '',
            gradientColors: const [Color(0xFF059669), Color(0xFF10B981)],
            plays: '142.3M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-lany-2',
            title: 'Mine',
            artist: 'Bazzi',
            album: 'COSMIC',
            duration: const Duration(minutes: 2, seconds: 14),
            genre: 'Pop',
            imageUrl: '',
            gradientColors: const [Color(0xFF059669), Color(0xFF10B981)],
            plays: '210.5M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-lany-3',
            title: '24/7/365',
            artist: 'elijah woods',
            album: 'bright',
            duration: const Duration(minutes: 2, seconds: 43),
            genre: 'Pop',
            imageUrl: '',
            gradientColors: const [Color(0xFF059669), Color(0xFF10B981)],
            plays: '88.1M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-lany-4',
            title: 'I Like Me Better',
            artist: 'Lauv',
            album: 'I met you when I was 18.',
            duration: const Duration(minutes: 3, seconds: 17),
            genre: 'Pop',
            imageUrl: '',
            gradientColors: const [Color(0xFF059669), Color(0xFF10B981)],
            plays: '315.6M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-lany-5',
            title: 'dna',
            artist: 'LANY',
            album: 'gg bb xx',
            duration: const Duration(minutes: 2, seconds: 58),
            genre: 'Indie Pop',
            imageUrl: '',
            gradientColors: const [Color(0xFF059669), Color(0xFF10B981)],
            plays: '95.0M',
            lyrics: const [],
            isPreview: false,
          ),
        ],
      ),
      RadioStation(
        id: 'ben-and-ben',
        title: 'Ben&Ben Radio',
        artistName: 'Ben&Ben',
        subtitle: 'With IV OF SPADES, Adie, Cup of Joe and more',
        backgroundColor: const Color(0xFFEA580C), // Warm Coral
        gradientColors: const [Color(0xFFEA580C), Color(0xFFFB923C)],
        heroImageUrl: '',
        songs: [
          Song(
            id: 'radio-bnb-1',
            title: 'Kathang Isip',
            artist: 'Ben&Ben',
            album: 'Leaves',
            duration: const Duration(minutes: 5, seconds: 18),
            genre: 'OPM / Folk Pop',
            imageUrl: '',
            gradientColors: const [Color(0xFFEA580C), Color(0xFFFB923C)],
            plays: '185.0M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-bnb-2',
            title: 'Leaves',
            artist: 'Ben&Ben',
            album: 'Leaves',
            duration: const Duration(minutes: 5, seconds: 10),
            genre: 'OPM / Folk Pop',
            imageUrl: '',
            gradientColors: const [Color(0xFFEA580C), Color(0xFFFB923C)],
            plays: '140.2M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-bnb-3',
            title: 'Mundo',
            artist: 'IV OF SPADES',
            album: 'CLAPCLAPCLAP!',
            duration: const Duration(minutes: 5, seconds: 49),
            genre: 'OPM / Funk',
            imageUrl: '',
            gradientColors: const [Color(0xFFEA580C), Color(0xFFFB923C)],
            plays: '162.7M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-bnb-4',
            title: 'Paraluman',
            artist: 'Adie',
            album: 'Paraluman',
            duration: const Duration(minutes: 5, seconds: 24),
            genre: 'OPM',
            imageUrl: '',
            gradientColors: const [Color(0xFFEA580C), Color(0xFFFB923C)],
            plays: '138.9M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-bnb-5',
            title: 'Tingin',
            artist: 'Cup of Joe, Janine Teñoso',
            album: 'Patutunguhan',
            duration: const Duration(minutes: 4, seconds: 12),
            genre: 'OPM',
            imageUrl: '',
            gradientColors: const [Color(0xFFEA580C), Color(0xFFFB923C)],
            plays: '115.4M',
            lyrics: const [],
            isPreview: false,
          ),
        ],
      ),
      RadioStation(
        id: 'cup-of-joe',
        title: 'Cup of Joe Radio',
        artistName: 'Cup of Joe',
        subtitle: 'With Dilaw, Over October, The Juans and more',
        backgroundColor: const Color(0xFF0284C7), // Cyan/Sky Blue
        gradientColors: const [Color(0xFF0284C7), Color(0xFF38BDF8)],
        heroImageUrl: '',
        songs: [
          Song(
            id: 'radio-coj-1',
            title: 'Estranghero',
            artist: 'Cup of Joe',
            album: 'Patutunguhan',
            duration: const Duration(minutes: 4, seconds: 5),
            genre: 'OPM',
            imageUrl: '',
            gradientColors: const [Color(0xFF0284C7), Color(0xFF38BDF8)],
            plays: '82.3M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-coj-2',
            title: 'Uhaw (Tayong Lahat)',
            artist: 'Dilaw',
            album: 'Sansinukob',
            duration: const Duration(minutes: 4, seconds: 1),
            genre: 'Indie Rock',
            imageUrl: '',
            gradientColors: const [Color(0xFF0284C7), Color(0xFF38BDF8)],
            plays: '175.9M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-coj-3',
            title: 'Istorya',
            artist: 'The Juans',
            album: 'Umaga',
            duration: const Duration(minutes: 4, seconds: 48),
            genre: 'OPM',
            imageUrl: '',
            gradientColors: const [Color(0xFF0284C7), Color(0xFF38BDF8)],
            plays: '67.0M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-coj-4',
            title: 'Ikaw Pa Rin Ang Pipiliin Ko',
            artist: 'Cup of Joe',
            album: 'Ikaw Pa Rin',
            duration: const Duration(minutes: 3, seconds: 55),
            genre: 'OPM',
            imageUrl: '',
            gradientColors: const [Color(0xFF0284C7), Color(0xFF38BDF8)],
            plays: '54.2M',
            lyrics: const [],
            isPreview: false,
          ),
        ],
      ),
      RadioStation(
        id: 'hev-abi',
        title: 'Hev Abi Radio',
        artistName: 'Hev Abi',
        subtitle: 'With Kristina Dawn, Flow G, Yuridope and more',
        backgroundColor: const Color(0xFF7C3AED), // Vibrant Purple
        gradientColors: const [Color(0xFF7C3AED), Color(0xFFA855F7)],
        heroImageUrl: '',
        songs: [
          Song(
            id: 'radio-hev-1',
            title: 'Makasarili Malambing',
            artist: 'Kristina Dawn, Hev Abi',
            album: 'Makasarili Malambing',
            duration: const Duration(minutes: 3, seconds: 44),
            genre: 'R&B / Hip-Hop',
            imageUrl: '',
            gradientColors: const [Color(0xFF7C3AED), Color(0xFFA855F7)],
            plays: '68.9M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-hev-2',
            title: 'Babaero',
            artist: 'Hev Abi',
            album: 'Kung Alam Mo Lang',
            duration: const Duration(minutes: 3, seconds: 28),
            genre: 'Hip-Hop',
            imageUrl: '',
            gradientColors: const [Color(0xFF7C3AED), Color(0xFFA855F7)],
            plays: '92.4M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-hev-3',
            title: 'Walang Alam',
            artist: 'Hev Abi',
            album: 'Kung Alam Mo Lang',
            duration: const Duration(minutes: 3, seconds: 12),
            genre: 'Hip-Hop',
            imageUrl: '',
            gradientColors: const [Color(0xFF7C3AED), Color(0xFFA855F7)],
            plays: '81.6M',
            lyrics: const [],
            isPreview: false,
          ),
        ],
      ),
    ];
  }

  /// Builds a dynamic Radio Station for any specific artist name
  RadioStation buildArtistRadio({
    required String artistName,
    required List<Song> existingSongs,
  }) {
    final pool = existingSongs.isNotEmpty
        ? existingSongs
        : [
            ..._fallbackPopularRadios().expand((s) => s.songs),
            ..._fallbackOpmRadios().expand((s) => s.songs),
            ..._fallbackGlobalRadios().expand((s) => s.songs),
          ];

    final artistSongs = pool
        .where((s) => s.artist.toLowerCase().contains(artistName.toLowerCase()))
        .toList();

    final pastel = getPastelColor(artistName);
    return RadioStation(
      id: 'artist-${artistName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '-')}',
      title: '$artistName Radio',
      artistName: artistName,
      subtitle: 'Popular tracks and recommendations for $artistName',
      backgroundColor: pastel,
      gradientColors: [pastel, pastel.withValues(alpha: 0.85)],
      songs: artistSongs.isNotEmpty ? artistSongs : pool.take(10).toList(),
    );
  }

  /// Generates authentic Spotify pastel background colors
  Color getPastelColor(String artistName) {
    final lower = artistName.toLowerCase().trim();
    if (lower.contains('flow g') || lower.contains('flow-g')) return const Color(0xFF8BB7F0); // Sky Blue
    if (lower.contains('air supply')) return const Color(0xFF8CECD4); // Mint
    if (lower.contains('lany')) return const Color(0xFFA5EAB7); // Pastel Green
    if (lower.contains('ben&ben') || lower.contains('ben & ben')) return const Color(0xFFF7A278); // Peach/Coral
    if (lower.contains('cup of joe')) return const Color(0xFF8DD8B5); // Sage/Mint
    if (lower.contains('hev abi')) return const Color(0xFFD6B4E8); // Lilac
    if (lower.contains('maroon 5') || lower.contains('maroon5')) return const Color(0xFFF87171); // Coral Red
    if (lower.contains('sugarfree')) return const Color(0xFFFDE047); // Pastel Yellow
    if (lower.contains('eraserheads')) return const Color(0xFFFB923C); // Pastel Orange
    if (lower.contains('coldplay')) return const Color(0xFF7DD3FC); // Light Sky
    if (lower.contains('dilaw')) return const Color(0xFFFCD34D); // Butter Yellow

    const palette = [
      Color(0xFF8BB7F0), // Sky Blue
      Color(0xFF8CECD4), // Mint
      Color(0xFFA5EAB7), // Pastel Green
      Color(0xFFF7A278), // Peach
      Color(0xFFD6B4E8), // Lilac
      Color(0xFFFDE047), // Buttercup Yellow
      Color(0xFFFDA4AF), // Rose Pink
      Color(0xFFBAE6FD), // Baby Blue
      Color(0xFFDDD6FE), // Soft Lavender
    ];
    return palette[lower.hashCode.abs() % palette.length];
  }

  /// Extracts collaborator artists from track titles, artist strings, and known presets
  List<String> extractCollaborators(String mainArtist, List<dynamic> rawTracks) {
    final lowerMain = mainArtist.toLowerCase().trim();

    // Spotify-exact presets for trending stations shown in user screenshots
    final presets = <String, List<String>>{
      'flow g': ['SUPAFLY', 'Lo ki', 'Hev Abi'],
      'flow-g': ['SUPAFLY', 'Lo ki', 'Hev Abi'],
      'air supply': ['Chicago', 'Peter Cetera', 'Bread'],
      'lany': ['Bazzi', 'elijah woods', 'Alex Crichton'],
      'ben&ben': ['IV OF SPADES', 'Adie', 'Cup of Joe'],
      'ben & ben': ['IV OF SPADES', 'Adie', 'Cup of Joe'],
      'cup of joe': ['Dilaw', 'Maki', 'Denise Julia'],
      'hev abi': ['Kristina Dawn', 'Flow G', 'Glock-9'],
      'sugarfree': ['Eraserheads', 'Soapdish', 'Orange & Lemons'],
      'maroon 5': ['Bruno Mars', 'Katy Perry', 'OneRepublic'],
      'maroon5': ['Bruno Mars', 'Katy Perry', 'OneRepublic'],
      'eraserheads': ['Rivermaya', 'Parokya Ni Edgar', 'Kamikazee'],
      'coldplay': ['The Fray', 'OneRepublic', 'Imagine Dragons'],
      'dilaw': ['Cup of Joe', 'Maki', 'SunKissed Lola'],
      'bruno mars': ['Anderson .Paak', 'Cardi B', 'Mark Ronson'],
      'adie': ['Janine Teñoso', 'Arthur Nery', 'Zack Tabudlo'],
    };

    for (final entry in presets.entries) {
      if (lowerMain.contains(entry.key) || entry.key.contains(lowerMain)) {
        return entry.value;
      }
    }

    final Set<String> names = {};
    for (final item in rawTracks) {
      if (item is! Map) continue;
      final title = (item['trackName']?.toString() ?? '').trim();
      final artist = (item['artistName']?.toString() ?? '').trim();

      // Check "(feat. X)" or "(with X)"
      final featMatch = RegExp(r'\((?:feat\.|with|ft\.)\s*([^)]+)\)', caseSensitive: false).firstMatch(title);
      if (featMatch != null) {
        final parts = featMatch.group(1)!.split(RegExp(r'[,&/]'));
        for (final p in parts) {
          final cleaned = p.trim();
          if (cleaned.isNotEmpty && !cleaned.toLowerCase().contains(lowerMain) && !lowerMain.contains(cleaned.toLowerCase())) {
            names.add(cleaned);
          }
        }
      }

      // Check artistName if it has multiple artists or differs from mainArtist
      if (artist.isNotEmpty && artist.toLowerCase() != lowerMain) {
        final parts = artist.split(RegExp(r'[,&/]'));
        for (final p in parts) {
          final cleaned = p.trim();
          if (cleaned.isNotEmpty && !cleaned.toLowerCase().contains(lowerMain) && !lowerMain.contains(cleaned.toLowerCase())) {
            names.add(cleaned);
          }
        }
      }

      if (names.length >= 3) break;
    }

    if (names.isEmpty) {
      return ['Similar Artists', 'Trending Hits'];
    }
    return names.take(3).toList();
  }

  /// Searches and builds a real-time, dynamic Spotify Radio Station
  /// for [query] using the public music catalog.
  Future<RadioStation> searchSpotifyRadio(
    String query, {
    http.Client? client,
    int limit = 35,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Search query cannot be empty');
    }

    final cacheKey = trimmed.toLowerCase();
    if (_radioCache.containsKey(cacheKey)) {
      return _radioCache[cacheKey]!;
    }

    final httpClient = client ?? _client;
    final uri = Uri.https('itunes.apple.com', '/search', {
      'term': trimmed,
      'media': 'music',
      'entity': 'song',
      'limit': '$limit',
    });

    http.Response response;
    try {
      response = await httpClient.get(
        uri,
        headers: {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'},
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      // If offline or network error, check if we have a fallback station across all categories
      final allFallbacks = [
        ..._fallbackPopularRadios(),
        ..._fallbackOpmRadios(),
        ..._fallbackGlobalRadios(),
      ];
      final fallback = allFallbacks.firstWhere(
        (s) => s.artistName.toLowerCase().contains(trimmed.toLowerCase()),
        orElse: () => buildArtistRadio(
          artistName: trimmed,
          existingSongs: allFallbacks.expand((s) => s.songs).toList(),
        ),
      );
      return fallback;
    }

    if (response.statusCode != 200) {
      throw Exception('Failed to load radio data from music catalog (HTTP ${response.statusCode})');
    }

    final Map<String, dynamic> decoded = jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
    final rawList = decoded['results'] as List<dynamic>? ?? [];

    if (rawList.isEmpty) {
      throw Exception('No songs found for radio search: "$trimmed"');
    }

    // Determine primary artist display name
    String resolvedArtistName = trimmed;
    for (final item in rawList) {
      if (item is Map && item['artistName'] != null) {
        final a = item['artistName'].toString().trim();
        if (a.toLowerCase().contains(trimmed.toLowerCase()) || trimmed.toLowerCase().contains(a.toLowerCase())) {
          resolvedArtistName = a;
          break;
        }
      }
    }

    final collaborators = extractCollaborators(resolvedArtistName, rawList);
    final subtitle = 'With ${collaborators.join(', ')} and more';

    // Collect 3 real artwork URLs for the 3 avatar circles
    final avatarUrls = <String>[];
    final seenArtworks = <String>{};
    for (final item in rawList) {
      if (item is! Map) continue;
      final art = (item['artworkUrl100']?.toString() ?? '').replaceAll('100x100bb', '600x600bb');
      if (art.isNotEmpty && !seenArtworks.contains(art)) {
        seenArtworks.add(art);
        avatarUrls.add(art);
      }
      if (avatarUrls.length >= 3) break;
    }

    final pastelColor = getPastelColor(resolvedArtistName);
    final songs = <Song>[];

    for (var i = 0; i < rawList.length; i++) {
      final t = rawList[i];
      if (t is! Map) continue;
      final title = (t['trackName']?.toString() ?? '').trim();
      if (title.isEmpty) continue;

      final trackId = t['trackId']?.toString() ?? '$i';
      final trackArtist = (t['artistName']?.toString() ?? resolvedArtistName).trim();
      final album = (t['collectionName']?.toString() ?? title).trim();
      final durationMs = (t['trackTimeMillis'] as num?)?.toInt() ?? 180000;
      final artwork = (t['artworkUrl100']?.toString() ?? '').replaceAll('100x100bb', '600x600bb');
      final preview = (t['previewUrl']?.toString() ?? '').trim();
      final genre = (t['primaryGenreName']?.toString() ?? 'Pop').trim();

      songs.add(
        Song(
          id: 'radio-dyn-$trackId',
          title: title,
          artist: trackArtist,
          album: album,
          duration: Duration(milliseconds: durationMs),
          genre: genre,
          imageUrl: artwork,
          gradientColors: [pastelColor, pastelColor.withValues(alpha: 0.85)],
          plays: '${(10 + (title.hashCode.abs() % 900) / 10).toStringAsFixed(1)}M',
          lyrics: const [],
          isPreview: preview.isNotEmpty,
        ),
      );
    }

    final station = RadioStation(
      id: 'dyn-${resolvedArtistName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '-')}',
      title: '$resolvedArtistName Radio',
      artistName: resolvedArtistName,
      subtitle: subtitle,
      backgroundColor: pastelColor,
      gradientColors: [pastelColor, pastelColor.withValues(alpha: 0.85)],
      avatarUrls: avatarUrls,
      songs: songs,
      heroImageUrl: avatarUrls.isNotEmpty ? avatarUrls.first : '',
    );

    _radioCache[cacheKey] = station;
    return station;
  }

  /// Asynchronously fetches trending Spotify radio stations (Flow G, Air Supply, LANY, Ben&Ben, etc.)
  Future<List<RadioStation>> fetchTrendingRadios({
    http.Client? client,
    List<String>? initialArtists,
  }) async {
    final artists = initialArtists ?? [
      'Flow G',
      'Air Supply',
      'LANY',
      'Ben&Ben',
      'Cup of Joe',
      'Hev Abi',
    ];

    final futures = artists.map((artist) async {
      try {
        return await searchSpotifyRadio(artist, client: client);
      } catch (e) {
        // Fall back gracefully to curated station if offline
        return _fallbackPopularRadios().firstWhere(
          (s) => s.artistName.toLowerCase().contains(artist.toLowerCase()),
          orElse: () => buildArtistRadio(artistName: artist, existingSongs: const []),
        );
      }
    });

    final results = await Future.wait(futures);
    _cachedTrendingRadios = results;
    return results;
  }

  /// Returns dynamic or curated OPM / Pinoy Rock Radio stations
  List<RadioStation> getOpmRadios() {
    if (_cachedOpmRadios.isNotEmpty) {
      return _cachedOpmRadios;
    }
    return _fallbackOpmRadios();
  }

  List<RadioStation> _fallbackOpmRadios() {
    return [
      RadioStation(
        id: 'opm-sugarfree',
        title: 'Sugarfree Radio',
        artistName: 'Sugarfree',
        subtitle: 'With Eraserheads, Soapdish, Orange & Lemons and more',
        backgroundColor: const Color(0xFFFDE047),
        gradientColors: const [Color(0xFFFDE047), Color(0xFFEAB308)],
        avatarUrls: const [],
        songs: [
          Song(
            id: 'radio-opm-sf-1',
            title: 'Hari ng Sablay',
            artist: 'Sugarfree',
            album: 'Sa Wakas',
            duration: const Duration(minutes: 4, seconds: 32),
            genre: 'OPM / Alternative Rock',
            imageUrl: '',
            gradientColors: const [Color(0xFFFDE047), Color(0xFFEAB308)],
            plays: '42.3M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-opm-sf-2',
            title: 'Burnout',
            artist: 'Sugarfree',
            album: 'Sa Wakas',
            duration: const Duration(minutes: 4, seconds: 15),
            genre: 'OPM / Alternative Rock',
            imageUrl: '',
            gradientColors: const [Color(0xFFFDE047), Color(0xFFEAB308)],
            plays: '78.5M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-opm-sf-3',
            title: 'Makita Kang Muli',
            artist: 'Sugarfree',
            album: 'Tala-Arawan',
            duration: const Duration(minutes: 4, seconds: 50),
            genre: 'OPM / Alternative Rock',
            imageUrl: '',
            gradientColors: const [Color(0xFFFDE047), Color(0xFFEAB308)],
            plays: '56.1M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-opm-sf-4',
            title: 'Mariposa',
            artist: 'Sugarfree',
            album: 'Sa Wakas',
            duration: const Duration(minutes: 3, seconds: 45),
            genre: 'OPM / Alternative Rock',
            imageUrl: '',
            gradientColors: const [Color(0xFFFDE047), Color(0xFFEAB308)],
            plays: '31.4M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-opm-sf-5',
            title: 'Tulog Na',
            artist: 'Sugarfree',
            album: 'Dramamachine',
            duration: const Duration(minutes: 4, seconds: 8),
            genre: 'OPM / Alternative Rock',
            imageUrl: '',
            gradientColors: const [Color(0xFFFDE047), Color(0xFFEAB308)],
            plays: '28.9M',
            lyrics: const [],
            isPreview: false,
          ),
        ],
      ),
      RadioStation(
        id: 'opm-eraserheads',
        title: 'Eraserheads Radio',
        artistName: 'Eraserheads',
        subtitle: 'With Rivermaya, Parokya Ni Edgar, Kamikazee and more',
        backgroundColor: const Color(0xFFFB923C),
        gradientColors: const [Color(0xFFFB923C), Color(0xFFEA580C)],
        avatarUrls: const [],
        songs: [
          Song(
            id: 'radio-opm-eheads-1',
            title: 'Ang Huling El Bimbo',
            artist: 'Eraserheads',
            album: 'Cutterpillow',
            duration: const Duration(minutes: 7, seconds: 28),
            genre: 'OPM / Alternative Rock',
            imageUrl: '',
            gradientColors: const [Color(0xFFFB923C), Color(0xFFEA580C)],
            plays: '198.4M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-opm-eheads-2',
            title: 'Ligaya',
            artist: 'Eraserheads',
            album: 'Ultraelectromagneticpop!',
            duration: const Duration(minutes: 4, seconds: 31),
            genre: 'OPM / Alternative Rock',
            imageUrl: '',
            gradientColors: const [Color(0xFFFB923C), Color(0xFFEA580C)],
            plays: '112.0M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-opm-eheads-3',
            title: 'With a Smile',
            artist: 'Eraserheads',
            album: 'Circus',
            duration: const Duration(minutes: 4, seconds: 24),
            genre: 'OPM / Alternative Rock',
            imageUrl: '',
            gradientColors: const [Color(0xFFFB923C), Color(0xFFEA580C)],
            plays: '135.6M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-opm-eheads-4',
            title: 'Magasin',
            artist: 'Eraserheads',
            album: 'Circus',
            duration: const Duration(minutes: 4, seconds: 11),
            genre: 'OPM / Alternative Rock',
            imageUrl: '',
            gradientColors: const [Color(0xFFFB923C), Color(0xFFEA580C)],
            plays: '95.8M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-opm-eheads-5',
            title: 'Pare Ko',
            artist: 'Eraserheads',
            album: 'Ultraelectromagneticpop!',
            duration: const Duration(minutes: 5, seconds: 25),
            genre: 'OPM / Alternative Rock',
            imageUrl: '',
            gradientColors: const [Color(0xFFFB923C), Color(0xFFEA580C)],
            plays: '88.3M',
            lyrics: const [],
            isPreview: false,
          ),
        ],
      ),
      RadioStation(
        id: 'opm-benben',
        title: 'Ben&Ben Radio',
        artistName: 'Ben&Ben',
        subtitle: 'With IV OF SPADES, Adie, Cup of Joe and more',
        backgroundColor: const Color(0xFFF7A278),
        gradientColors: const [Color(0xFFF7A278), Color(0xFFEA580C)],
        avatarUrls: const [],
        songs: [
          Song(
            id: 'radio-opm-bnb-1',
            title: 'Leaves',
            artist: 'Ben&Ben',
            album: 'Leaves',
            duration: const Duration(minutes: 5, seconds: 10),
            genre: 'OPM / Folk Pop',
            imageUrl: '',
            gradientColors: const [Color(0xFFF7A278), Color(0xFFEA580C)],
            plays: '140.2M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-opm-bnb-2',
            title: 'Kathang Isip',
            artist: 'Ben&Ben',
            album: 'Leaves',
            duration: const Duration(minutes: 5, seconds: 18),
            genre: 'OPM / Folk Pop',
            imageUrl: '',
            gradientColors: const [Color(0xFFF7A278), Color(0xFFEA580C)],
            plays: '185.0M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-opm-bnb-3',
            title: 'Pagtingin',
            artist: 'Ben&Ben',
            album: 'Limasawa Street',
            duration: const Duration(minutes: 3, seconds: 47),
            genre: 'OPM / Folk Pop',
            imageUrl: '',
            gradientColors: const [Color(0xFFF7A278), Color(0xFFEA580C)],
            plays: '172.5M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-opm-bnb-4',
            title: 'Araw-Araw',
            artist: 'Ben&Ben',
            album: 'Limasawa Street',
            duration: const Duration(minutes: 5, seconds: 13),
            genre: 'OPM / Folk Pop',
            imageUrl: '',
            gradientColors: const [Color(0xFFF7A278), Color(0xFFEA580C)],
            plays: '128.4M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-opm-bnb-5',
            title: 'Paninindigan Kita',
            artist: 'Ben&Ben',
            album: 'Paninindigan Kita',
            duration: const Duration(minutes: 5, seconds: 12),
            genre: 'OPM / Folk Pop',
            imageUrl: '',
            gradientColors: const [Color(0xFFF7A278), Color(0xFFEA580C)],
            plays: '98.1M',
            lyrics: const [],
            isPreview: false,
          ),
        ],
      ),
      RadioStation(
        id: 'opm-adie',
        title: 'Adie Radio',
        artistName: 'Adie',
        subtitle: 'With Janine Teñoso, Arthur Nery, Zack Tabudlo and more',
        backgroundColor: const Color(0xFF93C5FD),
        gradientColors: const [Color(0xFF93C5FD), Color(0xFF3B82F6)],
        avatarUrls: const [],
        songs: [
          Song(
            id: 'radio-opm-adie-1',
            title: 'Paraluman',
            artist: 'Adie',
            album: 'Senaryo',
            duration: const Duration(minutes: 5, seconds: 24),
            genre: 'OPM / Indie Pop',
            imageUrl: '',
            gradientColors: const [Color(0xFF93C5FD), Color(0xFF3B82F6)],
            plays: '138.9M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-opm-adie-2',
            title: 'Mahika',
            artist: 'Adie, Janine Teñoso',
            album: 'Senaryo',
            duration: const Duration(minutes: 3, seconds: 22),
            genre: 'OPM / Pop',
            imageUrl: '',
            gradientColors: const [Color(0xFF93C5FD), Color(0xFF3B82F6)],
            plays: '155.3M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-opm-adie-3',
            title: 'Tahanan',
            artist: 'Adie',
            album: 'Senaryo',
            duration: const Duration(minutes: 4, seconds: 53),
            genre: 'OPM / Indie Pop',
            imageUrl: '',
            gradientColors: const [Color(0xFF93C5FD), Color(0xFF3B82F6)],
            plays: '110.4M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-opm-adie-4',
            title: 'G.K.Y.A.M.',
            artist: 'Adie',
            album: 'Senaryo',
            duration: const Duration(minutes: 3, seconds: 31),
            genre: 'OPM / Indie Pop',
            imageUrl: '',
            gradientColors: const [Color(0xFF93C5FD), Color(0xFF3B82F6)],
            plays: '45.8M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-opm-adie-5',
            title: 'Kabado',
            artist: 'Adie',
            album: 'Senaryo',
            duration: const Duration(minutes: 4, seconds: 5),
            genre: 'OPM / Indie Pop',
            imageUrl: '',
            gradientColors: const [Color(0xFF93C5FD), Color(0xFF3B82F6)],
            plays: '62.7M',
            lyrics: const [],
            isPreview: false,
          ),
        ],
      ),
      RadioStation(
        id: 'opm-dilaw',
        title: 'Dilaw Radio',
        artistName: 'Dilaw',
        subtitle: 'With Cup of Joe, Maki, SunKissed Lola and more',
        backgroundColor: const Color(0xFFFCD34D),
        gradientColors: const [Color(0xFFFCD34D), Color(0xFFD97706)],
        avatarUrls: const [],
        songs: [
          Song(
            id: 'radio-opm-dilaw-1',
            title: 'Uhaw (Tayong Lahat)',
            artist: 'Dilaw',
            album: 'Sansinukob',
            duration: const Duration(minutes: 4, seconds: 1),
            genre: 'OPM / Indie Rock',
            imageUrl: '',
            gradientColors: const [Color(0xFFFCD34D), Color(0xFFD97706)],
            plays: '175.9M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-opm-dilaw-2',
            title: 'Janice',
            artist: 'Dilaw',
            album: 'Sansinukob',
            duration: const Duration(minutes: 5, seconds: 7),
            genre: 'OPM / Indie Rock',
            imageUrl: '',
            gradientColors: const [Color(0xFFFCD34D), Color(0xFFD97706)],
            plays: '52.3M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-opm-dilaw-3',
            title: 'Orasan',
            artist: 'Dilaw',
            album: 'Sansinukob',
            duration: const Duration(minutes: 4, seconds: 30),
            genre: 'OPM / Indie Rock',
            imageUrl: '',
            gradientColors: const [Color(0xFFFCD34D), Color(0xFFD97706)],
            plays: '41.1M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-opm-dilaw-4',
            title: '3019',
            artist: 'Dilaw',
            album: 'Sansinukob',
            duration: const Duration(minutes: 3, seconds: 48),
            genre: 'OPM / Indie Rock',
            imageUrl: '',
            gradientColors: const [Color(0xFFFCD34D), Color(0xFFD97706)],
            plays: '28.6M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-opm-dilaw-5',
            title: 'Kaloy',
            artist: 'Dilaw',
            album: 'Sansinukob',
            duration: const Duration(minutes: 4, seconds: 12),
            genre: 'OPM / Indie Rock',
            imageUrl: '',
            gradientColors: const [Color(0xFFFCD34D), Color(0xFFD97706)],
            plays: '19.4M',
            lyrics: const [],
            isPreview: false,
          ),
        ],
      ),
    ];
  }

  /// Fetches dynamic OPM Radio stations
  Future<List<RadioStation>> fetchOpmRadios({http.Client? client}) async {
    final artists = ['Sugarfree', 'Eraserheads', 'Ben&Ben', 'Adie', 'Dilaw'];
    final futures = artists.map((artist) async {
      try {
        return await searchSpotifyRadio(artist, client: client);
      } catch (_) {
        return _fallbackOpmRadios().firstWhere(
          (s) => s.artistName.toLowerCase().contains(artist.toLowerCase()),
          orElse: () => buildArtistRadio(artistName: artist, existingSongs: const []),
        );
      }
    });

    final results = await Future.wait(futures);
    _cachedOpmRadios = results;
    return results;
  }

  /// Returns dynamic or curated Global / Pop Radio stations
  List<RadioStation> getGlobalRadios() {
    if (_cachedGlobalRadios.isNotEmpty) {
      return _cachedGlobalRadios;
    }
    return _fallbackGlobalRadios();
  }

  List<RadioStation> _fallbackGlobalRadios() {
    return [
      RadioStation(
        id: 'global-maroon5',
        title: 'Maroon 5 Radio',
        artistName: 'Maroon 5',
        subtitle: 'With Bruno Mars, Katy Perry, OneRepublic and more',
        backgroundColor: const Color(0xFFF87171),
        gradientColors: const [Color(0xFFF87171), Color(0xFFEF4444)],
        avatarUrls: const [],
        songs: [
          Song(
            id: 'radio-global-m5-1',
            title: 'Sugar',
            artist: 'Maroon 5',
            album: 'V',
            duration: const Duration(minutes: 3, seconds: 55),
            genre: 'Pop',
            imageUrl: '',
            gradientColors: const [Color(0xFFF87171), Color(0xFFEF4444)],
            plays: '310.4M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-global-m5-2',
            title: 'Payphone',
            artist: 'Maroon 5, Wiz Khalifa',
            album: 'Overexposed',
            duration: const Duration(minutes: 3, seconds: 51),
            genre: 'Pop',
            imageUrl: '',
            gradientColors: const [Color(0xFFF87171), Color(0xFFEF4444)],
            plays: '280.1M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-global-m5-3',
            title: 'She Will Be Loved',
            artist: 'Maroon 5',
            album: 'Songs About Jane',
            duration: const Duration(minutes: 4, seconds: 17),
            genre: 'Pop / Rock',
            imageUrl: '',
            gradientColors: const [Color(0xFFF87171), Color(0xFFEF4444)],
            plays: '245.8M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-global-m5-4',
            title: 'Memories',
            artist: 'Maroon 5',
            album: 'JORDI',
            duration: const Duration(minutes: 3, seconds: 9),
            genre: 'Pop',
            imageUrl: '',
            gradientColors: const [Color(0xFFF87171), Color(0xFFEF4444)],
            plays: '265.3M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-global-m5-5',
            title: 'Maps',
            artist: 'Maroon 5',
            album: 'V',
            duration: const Duration(minutes: 3, seconds: 10),
            genre: 'Pop',
            imageUrl: '',
            gradientColors: const [Color(0xFFF87171), Color(0xFFEF4444)],
            plays: '190.2M',
            lyrics: const [],
            isPreview: false,
          ),
        ],
      ),
      RadioStation(
        id: 'global-brunomars',
        title: 'Bruno Mars Radio',
        artistName: 'Bruno Mars',
        subtitle: 'With Anderson .Paak, Silk Sonic, Mark Ronson and more',
        backgroundColor: const Color(0xFFFDE047),
        gradientColors: const [Color(0xFFFDE047), Color(0xFFEAB308)],
        avatarUrls: const [],
        songs: [
          Song(
            id: 'radio-global-bm-1',
            title: 'Just the Way You Are',
            artist: 'Bruno Mars',
            album: 'Doo-Wops & Hooligans',
            duration: const Duration(minutes: 3, seconds: 40),
            genre: 'Pop / R&B',
            imageUrl: '',
            gradientColors: const [Color(0xFFFDE047), Color(0xFFEAB308)],
            plays: '380.0M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-global-bm-2',
            title: 'That\'s What I Like',
            artist: 'Bruno Mars',
            album: '24K Magic',
            duration: const Duration(minutes: 3, seconds: 26),
            genre: 'Pop / R&B',
            imageUrl: '',
            gradientColors: const [Color(0xFFFDE047), Color(0xFFEAB308)],
            plays: '340.5M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-global-bm-3',
            title: 'When I Was Your Man',
            artist: 'Bruno Mars',
            album: 'Unorthodox Jukebox',
            duration: const Duration(minutes: 3, seconds: 33),
            genre: 'Pop / Ballad',
            imageUrl: '',
            gradientColors: const [Color(0xFFFDE047), Color(0xFFEAB308)],
            plays: '320.1M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-global-bm-4',
            title: 'Locked Out of Heaven',
            artist: 'Bruno Mars',
            album: 'Unorthodox Jukebox',
            duration: const Duration(minutes: 3, seconds: 53),
            genre: 'Pop / Rock',
            imageUrl: '',
            gradientColors: const [Color(0xFFFDE047), Color(0xFFEAB308)],
            plays: '290.7M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-global-bm-5',
            title: '24K Magic',
            artist: 'Bruno Mars',
            album: '24K Magic',
            duration: const Duration(minutes: 3, seconds: 46),
            genre: 'Funk / R&B',
            imageUrl: '',
            gradientColors: const [Color(0xFFFDE047), Color(0xFFEAB308)],
            plays: '275.4M',
            lyrics: const [],
            isPreview: false,
          ),
        ],
      ),
      RadioStation(
        id: 'global-lany',
        title: 'LANY Radio',
        artistName: 'LANY',
        subtitle: 'With Bazzi, elijah woods, Alex Crichton and more',
        backgroundColor: const Color(0xFFA5EAB7),
        gradientColors: const [Color(0xFFA5EAB7), Color(0xFF10B981)],
        avatarUrls: const [],
        songs: [
          Song(
            id: 'radio-global-lany-1',
            title: 'ILYSB',
            artist: 'LANY',
            album: 'Make Out',
            duration: const Duration(minutes: 3, seconds: 31),
            genre: 'Indie Pop',
            imageUrl: '',
            gradientColors: const [Color(0xFFA5EAB7), Color(0xFF10B981)],
            plays: '142.3M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-global-lany-2',
            title: 'Malibu Nights',
            artist: 'LANY',
            album: 'Malibu Nights',
            duration: const Duration(minutes: 4, seconds: 46),
            genre: 'Indie Pop',
            imageUrl: '',
            gradientColors: const [Color(0xFFA5EAB7), Color(0xFF10B981)],
            plays: '168.0M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-global-lany-3',
            title: 'Thick And Thin',
            artist: 'LANY',
            album: 'Malibu Nights',
            duration: const Duration(minutes: 3, seconds: 32),
            genre: 'Indie Pop',
            imageUrl: '',
            gradientColors: const [Color(0xFFA5EAB7), Color(0xFF10B981)],
            plays: '112.5M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-global-lany-4',
            title: 'dna',
            artist: 'LANY',
            album: 'gg bb xx',
            duration: const Duration(minutes: 2, seconds: 58),
            genre: 'Indie Pop',
            imageUrl: '',
            gradientColors: const [Color(0xFFA5EAB7), Color(0xFF10B981)],
            plays: '95.0M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-global-lany-5',
            title: 'Super Far',
            artist: 'LANY',
            album: 'LANY',
            duration: const Duration(minutes: 3, seconds: 23),
            genre: 'Indie Pop',
            imageUrl: '',
            gradientColors: const [Color(0xFFA5EAB7), Color(0xFF10B981)],
            plays: '124.7M',
            lyrics: const [],
            isPreview: false,
          ),
        ],
      ),
      RadioStation(
        id: 'global-coldplay',
        title: 'Coldplay Radio',
        artistName: 'Coldplay',
        subtitle: 'With The Fray, OneRepublic, Imagine Dragons and more',
        backgroundColor: const Color(0xFF7DD3FC),
        gradientColors: const [Color(0xFF7DD3FC), Color(0xFF0284C7)],
        avatarUrls: const [],
        songs: [
          Song(
            id: 'radio-global-cp-1',
            title: 'Yellow',
            artist: 'Coldplay',
            album: 'Parachutes',
            duration: const Duration(minutes: 4, seconds: 29),
            genre: 'Alternative Rock',
            imageUrl: '',
            gradientColors: const [Color(0xFF7DD3FC), Color(0xFF0284C7)],
            plays: '410.2M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-global-cp-2',
            title: 'Fix You',
            artist: 'Coldplay',
            album: 'X&Y',
            duration: const Duration(minutes: 4, seconds: 55),
            genre: 'Alternative Rock',
            imageUrl: '',
            gradientColors: const [Color(0xFF7DD3FC), Color(0xFF0284C7)],
            plays: '385.9M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-global-cp-3',
            title: 'The Scientist',
            artist: 'Coldplay',
            album: 'A Rush of Blood to the Head',
            duration: const Duration(minutes: 5, seconds: 9),
            genre: 'Alternative Rock',
            imageUrl: '',
            gradientColors: const [Color(0xFF7DD3FC), Color(0xFF0284C7)],
            plays: '360.4M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-global-cp-4',
            title: 'Viva La Vida',
            artist: 'Coldplay',
            album: 'Viva La Vida',
            duration: const Duration(minutes: 4, seconds: 2),
            genre: 'Alternative Rock',
            imageUrl: '',
            gradientColors: const [Color(0xFF7DD3FC), Color(0xFF0284C7)],
            plays: '420.0M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-global-cp-5',
            title: 'A Sky Full of Stars',
            artist: 'Coldplay',
            album: 'Ghost Stories',
            duration: const Duration(minutes: 4, seconds: 28),
            genre: 'Pop / Dance',
            imageUrl: '',
            gradientColors: const [Color(0xFF7DD3FC), Color(0xFF0284C7)],
            plays: '315.6M',
            lyrics: const [],
            isPreview: false,
          ),
        ],
      ),
      RadioStation(
        id: 'global-edsheeran',
        title: 'Ed Sheeran Radio',
        artistName: 'Ed Sheeran',
        subtitle: 'With Shawn Mendes, James Arthur, Lewis Capaldi and more',
        backgroundColor: const Color(0xFF86EFAC),
        gradientColors: const [Color(0xFF86EFAC), Color(0xFF16A34A)],
        avatarUrls: const [],
        songs: [
          Song(
            id: 'radio-global-es-1',
            title: 'Shape of You',
            artist: 'Ed Sheeran',
            album: '÷ (Divide)',
            duration: const Duration(minutes: 3, seconds: 53),
            genre: 'Pop',
            imageUrl: '',
            gradientColors: const [Color(0xFF86EFAC), Color(0xFF16A34A)],
            plays: '520.1M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-global-es-2',
            title: 'Perfect',
            artist: 'Ed Sheeran',
            album: '÷ (Divide)',
            duration: const Duration(minutes: 4, seconds: 23),
            genre: 'Pop / Ballad',
            imageUrl: '',
            gradientColors: const [Color(0xFF86EFAC), Color(0xFF16A34A)],
            plays: '460.8M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-global-es-3',
            title: 'Thinking Out Loud',
            artist: 'Ed Sheeran',
            album: 'x (Multiply)',
            duration: const Duration(minutes: 4, seconds: 41),
            genre: 'Pop / Soul',
            imageUrl: '',
            gradientColors: const [Color(0xFF86EFAC), Color(0xFF16A34A)],
            plays: '390.2M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-global-es-4',
            title: 'Photograph',
            artist: 'Ed Sheeran',
            album: 'x (Multiply)',
            duration: const Duration(minutes: 4, seconds: 18),
            genre: 'Pop',
            imageUrl: '',
            gradientColors: const [Color(0xFF86EFAC), Color(0xFF16A34A)],
            plays: '340.5M',
            lyrics: const [],
            isPreview: false,
          ),
          Song(
            id: 'radio-global-es-5',
            title: 'Bad Habits',
            artist: 'Ed Sheeran',
            album: '= (Equals)',
            duration: const Duration(minutes: 3, seconds: 51),
            genre: 'Pop / Dance',
            imageUrl: '',
            gradientColors: const [Color(0xFF86EFAC), Color(0xFF16A34A)],
            plays: '280.9M',
            lyrics: const [],
            isPreview: false,
          ),
        ],
      ),
    ];
  }

  /// Fetches dynamic Global / Pop Radio stations
  Future<List<RadioStation>> fetchGlobalRadios({http.Client? client}) async {
    final artists = ['Maroon 5', 'Bruno Mars', 'LANY', 'Coldplay', 'Ed Sheeran'];
    final futures = artists.map((artist) async {
      try {
        return await searchSpotifyRadio(artist, client: client);
      } catch (_) {
        return _fallbackGlobalRadios().firstWhere(
          (s) => s.artistName.toLowerCase().contains(artist.toLowerCase()),
          orElse: () => buildArtistRadio(artistName: artist, existingSongs: const []),
        );
      }
    });

    final results = await Future.wait(futures);
    _cachedGlobalRadios = results;
    return results;
  }

  /// Clears in-memory cache (useful for tests)
  void clearCache() {
    _radioCache.clear();
    _cachedTrendingRadios.clear();
    _cachedOpmRadios.clear();
    _cachedGlobalRadios.clear();
  }
}
