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

### 📱 Responsive Hallmark Design
- **Adaptive Breakpoints**:
  - **Mobile Layout**: Ergonomic bottom navigation layer (`Home`, `Explore`, `Library`), sliding hamburger drawer, and sticky bottom playback bar.
  - **Desktop / Tablet Layout**: Persistent left sidebar, hero banner, right activity panel (Now Playing visualizer and lyrics), and responsive grid cards.
- **Hallmark Anti-AI-Slop System**: Deep `#121212` background palette, high-contrast typography, tactile press states, and zero RenderFlex layout overflows.



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
