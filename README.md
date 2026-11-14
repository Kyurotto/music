# 🎵 Pulse Studio

<p align="center">
  <img src="https://raw.githubusercontent.com/Kyurotto/music/main/assets/icon/icon.png" alt="Pulse Studio Logo" width="100" height="100" onerror="this.style.display='none'"/>
</p>

<p align="center">
  <strong>A high-fidelity, cross-platform music streaming player and studio built with Flutter.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter" alt="Flutter">
  <img src="https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart" alt="Dart">
  <img src="https://img.shields.io/badge/Platform-Windows%20%7C%20Android%20%7C%20iOS%20%7C%20Web-4CAF50" alt="Platform Support">
  <img src="https://img.shields.io/badge/Tests-235%2B%20Passed-brightgreen" alt="Tests">
  <img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License">
</p>

---

## 🌟 Overview

**Pulse Studio** is a modern music player and streaming application designed with Spotify-grade dark aesthetics, tactile interactive controls, and a robust offline-first architecture. It features synchronized scrolling lyrics, a 10-band graphic equalizer, multi-platform Spotify and YouTube link importing with automated full-track resolution, SQLite offline persistence, and seamless responsive support across mobile and desktop devices.

---

## ✨ Key Features

### 🎧 Now Playing & Immersive Lyrics Experience
- **Dynamic Album Artwork**: High-resolution cover art showcase with ambient glow tailored to the track's dominant palette.
- **Synchronized Real-Time Lyrics**: Auto-scrolling lyrics with millisecond timestamp synchronization, tap-to-seek, and line-pinning to prevent cursor fighting.
- **Cover Art & Lyrics Flip-Toggle**: Switch between full album cover art and interactive lyrics mode with one tap.
- **Quick Action Row**:
  - **Lyrics**: Toggles synchronized lyric display.
  - **Save**: Saves and bookmarks tracks to your personal Library and Favorites.
  - **Download**: Instant offline download with real-time status indicators (*Download*, *Saving…*, *Downloaded*).

### 🎛️ Audio Engine & Acoustic Tuning
- **High-Performance Audio Pipeline**: Powered by `just_audio`, `audio_session`, and `just_audio_windows`.
- **10-Band Graphic Equalizer**: Custom sound shaping with interactive frequency sliders, bass boost, and presets (*Rock, Pop, Bass Boost, Vocal Boost, Electronic, Classical, Flat*).
- **Dynamic Visualizer**: Real-time multi-bar frequency animation synced to playback.
- **Gapless Playback & Normalization**: Continuous playback with volume leveling, crossfade support, and lockscreen/notification transport controls via `just_audio_background`.
- **Intelligent Playback Guard**: Stall watchdog with automatic recovery, silent retries, and explicit-content filtering.

### 🔗 Spotify & Multi-Platform Import Engine
- **Universal Link Import**: Import Spotify playlists, artist top tracks, and individual songs directly using Spotify URLs, URIs, or embed links.
- **Multi-Source Audio Resolver**: Automated full-track audio location engine scouring high-quality web audio providers (YouTube, Archive.org, Saavn, JioSaavn, iTunes) with smart metadata deduplication.
- **Playlist Export & Backup**: Portable playlist database backup and JSON import/export functionality.

### 💾 Offline-First Storage & Cache Management
- **Concurrent Offline Downloader**: 3-worker multi-threaded background downloader for songs and complete radio stations.
- **SQLite Database (`sqflite`)**: Local relational storage for playlists, downloaded tracks, playback metrics, and listening history.
- **Dedicated Cache Manager**: View and manage local storage usage with one-tap cache purging and offline mode toggle in Settings.

### 👤 Account Management & Spotify Drawer Navigation
- **Spotify-Grade Mobile Drawer**:
  - **User Profile Card**: Green avatar badge with user initials, username, and "View profile" shortcut.
  - **+ Add account**: Seamless account switcher and multi-profile login.
  - **Listening stats**: Detailed metrics on top artists, genres, total listening time, and weekly activity.
  - **Recents**: Playback history tracking recently played songs and radio stations.
  - **Your Updates**: Dedicated in-app announcement sheet detailing the latest features and updates.
  - **Settings and privacy**: Quick access to audio preferences, streaming quality, equalizer, and account credentials.
- **Authentication**: Local Salted SHA-256 secure authentication with optional Firebase Authentication and Cloud Firestore cloud sync.

### 📱 Responsive Hallmark Design
- **Adaptive Breakpoints**:
  - **Mobile Layout**: Ergonomic bottom navigation layer (`Home`, `Explore`, `Library`), sliding hamburger drawer, and sticky bottom playback bar.
  - **Desktop / Tablet Layout**: Persistent left sidebar, hero banner, right activity panel (Now Playing visualizer and lyrics), and responsive grid cards.
- **Hallmark Anti-AI-Slop System**: Deep `#121212` background palette, high-contrast typography, tactile press states, and zero RenderFlex layout overflows.

---

## 🏛️ Architecture & Project Structure

The codebase is organized into clean, modular layers following standard Flutter architectural best practices:

```
lib/
├── auth/                 # Authentication service, user models, role management
│   ├── auth_service.dart
│   └── user_model.dart
├── controllers/          # Business logic and state controllers
│   └── music_player_controller.dart   # Main controller managing player, queue, cache, and downloads
├── data/                 # SQLite database and schema migrations
│   ├── local_database.dart
│   └── sample_music_data.dart
├── models/               # Data classes and entity definitions
│   ├── song_model.dart
│   ├── playlist_model.dart
│   ├── equalizer_preset.dart
│   └── listening_history.dart
├── services/             # Background services and network engines
│   ├── spotify_import_service.dart
│   ├── track_enrichment_service.dart
│   ├── radio_discovery_service.dart
│   ├── local_audio_cache_service.dart
│   └── spotify_export_service.dart
├── theme/                # Design tokens, gradients, and typography
│   └── app_theme.dart
├── views/                # Full screens and route entrypoints
│   ├── music_dashboard_view.dart      # Main dashboard view
│   ├── settings_view.dart             # Settings, storage, audio preferences
│   ├── profile_view.dart              # User profile details
│   ├── accounts_view.dart             # Multi-account manager
│   ├── listening_stats_view.dart      # Listening analytics
│   ├── recents_view.dart              # Playback history
│   └── auth_gate.dart                 # Authentication routing gate
└── widgets/              # Reusable UI components
    ├── spotify_lyrics_sheet.dart      # Now Playing artwork & synced lyrics sheet
    ├── right_panel.dart               # Desktop Now Playing activity panel
    ├── sidebar_nav.dart               # Spotify-styled drawer & desktop navigation
    ├── bottom_player_bar.dart         # Mini player bar with progress scrub & volume
    ├── song_artwork_widget.dart       # Cached album artwork with ambient glow
    └── animated_visualizer.dart       # Real-time audio frequency visualizer
```

---

## 🚀 Getting Started

### Prerequisites
- **Flutter SDK**: `>= 3.12.0` ([Install Flutter](https://docs.flutter.dev/get-started/install))
- **Dart SDK**: `>= 3.12.0`
- **Platform Toolchain**:
  - Windows: Visual Studio 2022 (with Desktop development with C++)
  - Android: Android Studio & Android SDK
  - macOS / iOS: Xcode (for macOS/iOS targets)

### Installation

1. **Clone the repository**:
   ```bash
   git clone https://github.com/Kyurotto/music.git
   cd music
   ```

2. **Install dependencies**:
   ```bash
   flutter pub get
   ```

3. **Run the application**:
   - On Windows Desktop:
     ```bash
     flutter run -d windows
     ```
   - On Android:
     ```bash
     flutter run -d android
     ```
   - On Chrome / Web:
     ```bash
     flutter run -d chrome
     ```

---

## 🧪 Testing

Pulse Studio is backed by a suite of over **235+ automated tests** verifying audio playback logic, Spotify and YouTube link resolution, offline cache operations, equalizer state transitions, and responsive UI layout boundaries:

```bash
# Run the complete test suite
flutter test

# Run specific feature tests
flutter test test/bottom_nav_and_settings_drawer_test.dart
flutter test test/now_playing_artwork_and_actions_test.dart
flutter test test/dashboard_overflow_test.dart
flutter test test/widget_test.dart
```

To run static code analysis:
```bash
flutter analyze
```

---

## 🛠️ Technology Stack

| Component | Library / Tool |
| :--- | :--- |
| **Framework** | [Flutter](https://flutter.dev) (Dart 3.x) |
| **Audio Core** | `just_audio`, `audio_session`, `just_audio_background` |
| **Local Database** | `sqflite`, `sqlite3_flutter_libs` |
| **State Management** | `ChangeNotifier` / `ValueNotifier` Controller Pattern |
| **Cloud Services** | `firebase_core`, `firebase_auth`, `cloud_firestore` *(optional)* |
| **Network & Media** | `http`, `connectivity_plus`, `cached_network_image` |
| **Security** | `crypto` (Salted SHA-256), `flutter_secure_storage` |

---

## 📄 License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

---
  
<p align="center">
  Crafted with care for <strong>Pulse Studio</strong> 🎧
</p>
