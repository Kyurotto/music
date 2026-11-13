# Graph Report - music  (2026-11-13)

## Corpus Check
- 245 files · ~375,591 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 62 file(s) not represented in the graph (top: (none) 10, .xml 8, .xcconfig 8)

## Summary
- 2951 nodes · 3543 edges · 160 communities (116 shown, 44 thin omitted)
- Extraction: 99% EXTRACTED · 1% INFERRED · 0% AMBIGUOUS · INFERRED: 18 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `7b2e00df`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- music_player_controller.dart
- track_enrichment_service.dart
- local_database.dart
- spotify_import_service.dart
- music_dashboard_view.dart
- discovery_service.dart
- GeneratedPluginRegistrant.swift
- spotify_import_dialog.dart
- auth_service.dart
- song_model.dart
- animated_visualizer.dart
- settings_view.dart
- song_artwork_widget.dart
- discovery_sections.dart
- my_application.cc
- spotify_lyrics_sheet.dart
- utils.cpp
- discovery_playlist_page.dart
- radio_discovery_service.dart
- right_panel.dart
- app_theme.dart
- track_list_view.dart
- package:flutter_test/flutter_test.dart
- discovery_auto_refresh.dart
- State
- MainActivity.kt
- win32_window.cpp
- FlutterWindow
- sidebar_nav.dart
- component-cookbook.md
- radio_playlist_offline_download_test.dart
- main.dart
- Win32Window
- manifest.json
- artist_import_test.dart
- db_sync_daemon.py
- .MessageHandler
- StatelessWidget
- playlist_screen.dart
- @visibleForTesting
- Point
- ../theme/app_theme.dart
- code-review-graph
- code-review-graph
- code-review-graph
- equalizer_preset.dart
- crg-session-start.sh
- crg-update.sh
- Assets — sourcing canon for icons, logos, illustrations, photography, video
- macrostructures.md
- Theme — Lumen
- Theme — Hum
- Custom craft — how to hand-build hero artwork
- Custom theme — protocol
- Design flow (default)
- Recipes
- Study — extracting design DNA from a screenshot or URL
- hallmark/SKILL.md
- Hero enrichment — when, what, and how much
- Theme — Carnival
- Interaction and states
- Major (looks AI-generated)
- SettingsView
- Slop test — 58 gates + pre-emit self-critique
- Copy
- Critical (ships as slop)
- Typography
- Microinteraction tells
- Archetype index — load ONLY the picks you need
- Theme — Cobalt
- Theme - Grid
- just_audio_background.dart
- Responsive
- The six axes
- display_rate_service.dart
- Minor (small taste issues)
- Imagery kit — curated abstract assets, hosted, ready
- Genre — atmospheric
- Genre — modern-minimal
- Genre — playful
- § Multi-page flow — design.md first, then redesign
- Genre — editorial (default)
- Layout and space
- Motion
- design.md — opt-in portable design system
- Export formats
- Output contract & scope
- Colour
- audio_equalizer_service.dart
- MCP Tools: code-review-graph
- Floating nav on scroll — the cross-fade morph
- MCP Tools: code-review-graph
- Debug Issue
- Explore Codebase
- Refactor Safely
- Review Changes
- Debug Issue
- Explore Codebase
- Refactor Safely
- Review Changes
- MCP Tools: code-review-graph
- Debug Issue
- Explore Codebase
- Refactor Safely
- Review Changes
- MCP Tools: code-review-graph
- Debug Issue
- Explore Codebase
- Refactor Safely
- Review Changes
- MCP Tools: code-review-graph
- MCP Tools: code-review-graph
- MCP Tools: code-review-graph
- PlaylistScreen
- music
- Size
- f2-sticky-scroll-stack.md
- ft2-inline-rule-single-line.md
- dashboard_overflow_test.dart
- ft6-letter-close.md
- spotify_export_service.dart
- radio_playlist_offline_download_test.dart
- h6-photographic-fold.md
- h7-demo-video-clipped-by-viewport-edge.md
- h9-custom-illustration-centerpiece.md
- n13-inline-cmdk-pill.md
- s2-hanging.md
- s4-inline-no-break.md
- spotify_export_import_dialog.dart
- package:music/controllers/music_player_controller.dart
- package:flutter/material.dart
- AppDelegate
- DiscoveryTrack
- .claude/CLAUDE.md
- LaunchImage.imageset/README.md
- spotify_export_service_test.dart
- ios/RunnerTests/RunnerTests.swift
- artist_import_test.dart
- just_audio_background
- _PlayerAudioHandler
- FlutterMacOS
- AppDelegate
- RegisterGeneratedPlugins
- TrackInfo
- AudioPlayerPlatform
- AudioSourceMessage
- JustAudioPlatform
- _PlaybackEventMessageExtension
- _ValueStreamExtension
- RunnerTests
- equalizer_preset_test.dart
- n9-edge-aligned-minimal.md

## God Nodes (most connected - your core abstractions)
1. `Win32Window` - 21 edges
2. `Major (looks AI-generated)` - 20 edges
3. `Slop test — 58 gates + pre-emit self-critique` - 19 edges
4. `Theme — Hum` - 18 edges
5. `Critical (ships as slop)` - 17 edges
6. `Theme — Lumen` - 17 edges
7. `Recipes` - 16 edges
8. `MusicPlayerController` - 15 edges
9. `Microinteraction tells` - 14 edges
10. `Responsive` - 13 edges

## Surprising Connections (you probably didn't know these)
- `wWinMain()` --calls--> `CreateAndAttachConsole()`  [INFERRED]
  windows/runner/main.cpp → windows/runner/utils.cpp
- `MainActivity` --calls--> `DynamicsProcessingEqualizer`  [INFERRED]
  android/app/src/main/kotlin/com/example/music/MainActivity.kt → android/app/src/main/kotlin/com/example/music/DynamicsProcessingEqualizer.kt
- `my_application_activate()` --calls--> `fl_register_plugins()`  [INFERRED]
  linux/runner/my_application.cc → linux/flutter/generated_plugin_registrant.cc
- `main()` --calls--> `my_application_new()`  [INFERRED]
  linux/runner/main.cc → linux/runner/my_application.cc
- `FlutterWindow` --inherits--> `Win32Window`  [EXTRACTED]
  windows/runner/flutter_window.h → windows/runner/win32_window.h

## Import Cycles
- None detected.

## Communities (160 total, 44 thin omitted)

### Community 0 - "music_player_controller.dart"
Cohesion: 0.01
Nodes (293): _activateAudioSession, _activeDownloadWorkers, addedCount, addSong, addSongToPlaylist, addToQueue, _allowExplicit, allowExplicitSettingKey (+285 more)

### Community 1 - "track_enrichment_service.dart"
Cohesion: 0.02
Nodes (116): _alwaysSkipMarkers, _archiveCoolDownUntil, _archiveCreator, _archiveItemAudio, _archiveLength, _archiveSearch, _artistWordSet, artworkUrl (+108 more)

### Community 2 - "local_database.dart"
Cohesion: 0.02
Nodes (102): addTrackToPlaylist, audioCacheRevision, autoHealCachedImportedSongs, _cachedAudioFileMemo, _cachedAudioIndex, claimAnonymousPlaylists, _cleanImportedPlaylistsAndPreviews, cleanOrphanImportedSongs (+94 more)

### Community 3 - "spotify_import_service.dart"
Cohesion: 0.03
Nodes (64): album, artist, artworkUrl, _boolFlag, _browserUserAgent, _cleanArtistQuery, _client, _decodeJsonObject (+56 more)

### Community 4 - "music_dashboard_view.dart"
Cohesion: 0.02
Nodes (69): PlaybackRepeatMode, _albumGridDelegate, _authSub, build, _buildAvatarCircle, _buildCurrentTabContent, _buildFallback, _buildFavoritesTab (+61 more)

### Community 5 - "discovery_service.dart"
Cohesion: 0.04
Nodes (52): album, artist, artworkUrl, at, _cache, _cached, _CacheEntry, _cacheTtl (+44 more)

### Community 6 - "GeneratedPluginRegistrant.swift"
Cohesion: 0.15
Nodes (12): audio_service, audio_session, cloud_firestore, connectivity_plus, file_picker_darwin, firebase_auth, firebase_core, flutter_secure_storage_darwin (+4 more)

### Community 7 - "spotify_import_dialog.dart"
Cohesion: 0.05
Nodes (39): SpotifyImportResult, AuthView, _AuthViewState, build, _confirmPasswordController, createState, dispose, _emailController (+31 more)

### Community 8 - "auth_service.dart"
Cohesion: 0.05
Nodes (38): _authController, AuthService, backupEmail, copyWith, _currentUser, displayName, email, _emitAuth (+30 more)

### Community 9 - "song_model.dart"
Cohesion: 0.05
Nodes (38): album, artist, audioUrl, bundledTracks, duration, formatTime, genre, genres (+30 more)

### Community 10 - "animated_visualizer.dart"
Cohesion: 0.12
Nodes (14): barCount, barWidth, build, _controller, createState, didUpdateWidget, dispose, equalizerBands (+6 more)

### Community 11 - "settings_view.dart"
Cohesion: 0.04
Nodes (44): _allowExplicit, _autoCachePlayedSongs, _autoLyrics, _automix, _autoplay, build, _buildCard, _buildProfileCard (+36 more)

### Community 12 - "song_artwork_widget.dart"
Cohesion: 0.06
Nodes (28): artist, border, borderRadius, build, _buildImageWithFallback, _buildSpotifyProceduralArt, color, _effectiveArtist (+20 more)

### Community 13 - "discovery_sections.dart"
Cohesion: 0.06
Nodes (28): _applySection, _autoRefresher, build, _computeSignature, controller, createState, dispose, _fastLocateTracks (+20 more)

### Community 14 - "my_application.cc"
Cohesion: 0.08
Nodes (14): fl_register_plugins(), main(), first_frame_cb(), my_application_activate(), my_application_class_init(), my_application_dispose(), my_application_init(), my_application_local_command_line() (+6 more)

### Community 15 - "spotify_lyrics_sheet.dart"
Cohesion: 0.08
Nodes (22): build, controller, createState, dispose, _fetchingForId, _highlightedLineIndex, initState, _lastSeenSongId (+14 more)

### Community 16 - "utils.cpp"
Cohesion: 0.19
Nodes (4): wWinMain(), CreateAndAttachConsole(), GetCommandLineArguments(), Utf8FromUtf16()

### Community 17 - "discovery_playlist_page.dart"
Cohesion: 0.09
Nodes (18): DiscoverySection, build, _clock, controller, cover, duration, isCurrent, isPlaying (+10 more)

### Community 18 - "radio_discovery_service.dart"
Cohesion: 0.04
Nodes (44): accentColor, artistName, ArtistProfile, avatarUrls, backgroundColor, buildArtistRadio, _cachedGlobalRadios, _cachedOpmRadios (+36 more)

### Community 19 - "right_panel.dart"
Cohesion: 0.08
Nodes (22): MusicPlayerController, Song, BottomPlayerBar, build, _buildCompactPlayer, _buildDesktopPlayer, controller, onOpenLyrics (+14 more)

### Community 20 - "app_theme.dart"
Cohesion: 0.10
Nodes (18): accentAmber, accentGreen, accentPink, AppTheme, background, border, borderActive, cardGlowGradient (+10 more)

### Community 21 - "track_list_view.dart"
Cohesion: 0.06
Nodes (32): _attachToPageScroll, build, _buildInlineBadge, controller, createState, didChangeDependencies, didUpdateWidget, dispose (+24 more)

### Community 22 - "package:flutter_test/flutter_test.dart"
Cohesion: 0.17
Nodes (7): SpotifyImportService, main, main, main, main, service, main

### Community 23 - "discovery_auto_refresh.dart"
Cohesion: 0.11
Nodes (13): didChangeAppLifecycleState, DiscoveryAutoRefresher, dispose, _disposed, interval, _lastRefresh, markRefreshed, minGap (+5 more)

### Community 24 - "State"
Cohesion: 0.12
Nodes (22): DiscoverySections, DiscoverySectionsState, _CreatePlaylistDialog, _CreatePlaylistDialogState, _DailyMixCard, _DailyMixCardState, MusicDashboardView, _MusicDashboardViewState (+14 more)

### Community 26 - "win32_window.cpp"
Cohesion: 0.19
Nodes (5): Scale(), Win32Window::Win32Window(), WindowClassRegistrar, class_registered_, instance_

### Community 27 - "FlutterWindow"
Cohesion: 0.12
Nodes (4): FlutterWindow, flutter_controller_, FlutterWindow::FlutterWindow(), project_

### Community 28 - "sidebar_nav.dart"
Cohesion: 0.12
Nodes (13): badge, build, controller, icon, isSelected, label, _NavItem, onArtistSelected (+5 more)

### Community 29 - "component-cookbook.md"
Cohesion: 0.02
Nodes (40): C1 · Outlined chip, C2 · Inline form-as-CTA, C3 · Typographic link, C4 · Sticky bottom bar, F1 · Bento grid, F3 · Tabular spec sheet, F4 · Step sequence, F5 · Annotated screenshot (+32 more)

### Community 30 - "radio_playlist_offline_download_test.dart"
Cohesion: 0.18
Nodes (7): main, main, cacheDir, createdFiles, db, main, radioSong

### Community 32 - "main.dart"
Cohesion: 0.10
Nodes (7): build, firebaseEnabled, main, instance, loadImportedPlaylists, persistPlaylist, PlaylistPersistenceService

### Community 33 - "Win32Window"
Cohesion: 0.18
Nodes (5): RegisterPlugins(), Win32Window, child_content_, quit_on_close_, window_handle_

### Community 34 - "manifest.json"
Cohesion: 0.18
Nodes (10): background_color, description, display, icons, name, orientation, prefer_related_applications, short_name (+2 more)

### Community 35 - "artist_import_test.dart"
Cohesion: 0.14
Nodes (10): album, artist, main, millis, _track, main, main, jsonOk (+2 more)

### Community 36 - "db_sync_daemon.py"
Cohesion: 0.31
Nodes (3): run_sync(), save_db_bytes(), main()

### Community 38 - "StatelessWidget"
Cohesion: 0.15
Nodes (12): MusicApp, AuthGate, DiscoveryPlaylistPage, _Header, _SongRow, _DiscoveryRail, _LibraryPlaylistTile, _CoverCollage2x2 (+4 more)

### Community 39 - "playlist_screen.dart"
Cohesion: 0.05
Nodes (36): build, _buildCoverCell, _buildDownloadButton, _buildTrackBadge, _clock, _confirmDeletePlaylist, controller, createState (+28 more)

### Community 40 - "@visibleForTesting"
Cohesion: 0.25
Nodes (7): ensureOfflineLyricsForTesting, getOfflineAssetFallbackForTesting, handleSongCompleteForTesting, createAllTables, setDatabaseForTesting, gainAtFrequency, scaleBandsToRange

### Community 41 - "Point"
Cohesion: 0.50
Nodes (3): Point, x, y

### Community 42 - "../theme/app_theme.dart"
Cohesion: 0.18
Nodes (9): MusicPlaylist, build, createState, _isHovered, isSelected, onDelete, onPlay, onTap (+1 more)

### Community 47 - "equalizer_preset.dart"
Cohesion: 0.12
Nodes (12): all, bands, custom, customWithBands, description, EqualizerPreset, frequencyLabels, gainFactor (+4 more)

### Community 54 - "Assets — sourcing canon for icons, logos, illustrations, photography, video"
Cohesion: 0.05
Nodes (44): Abstract backgrounds, App mockups / device frames, Assets — sourcing canon for icons, logos, illustrations, photography, video, Avoid, Avoid, Avoid, Avoid, Avoid (+36 more)

### Community 55 - "macrostructures.md"
Cohesion: 0.04
Nodes (28): 01 · Bento Grid, 02 · Long Document, 03 · Marquee Hero, 04 · Stat-Led, 05 · Workbench, 06 · Conversational FAQ, 07 · Manifesto, 08 · Photographic (+20 more)

### Community 56 - "Theme — Lumen"
Cohesion: 0.06
Nodes (33): 1. Hand-built apparatus (no orb), 2. Lowercase headline with verb-landmark (no italics), 3. Mono eyebrow above every section, 4. Blueprint grid background (4% opacity), 5. Meter strip (below the hero), 6. Hairline cards with inner emission, 7. Three-stat row with Instrument Serif numerals + tabular-nums, Anti-patterns (theme-specific) (+25 more)

### Community 57 - "Theme — Hum"
Cohesion: 0.06
Nodes (32): 1. The button system — three variations, the press is the feedback, 2. Multi-accent section bands, 3. Color-shift card grid, 4. Streak / counter tick-up, 5. Character moment — one small reacting mark, 6. Big rounded everything, 7. Star-burst micro-celebration on success, Anti-patterns (theme-specific) (+24 more)

### Community 58 - "Custom craft — how to hand-build hero artwork"
Cohesion: 0.07
Nodes (30): A hand-built SVG with declarative animation, A worked example — the bakery loaf as a single div, Animation choices for SVG in 2026, Anti-patterns of CSS art, Anti-patterns of declarative animation, Anti-patterns of generated stills, Anti-patterns of hand-built SVG, Anti-patterns of Three.js / WebGL (+22 more)

### Community 59 - "Custom theme — protocol"
Cohesion: 0.07
Nodes (29): § A · The one follow-up question, B.1 · Anchor accent first, B.2 · Paper, B.3 · Ink, B.4 · Supporting greys, B.5 · Focus, B.6 · Accent-ink (overlay text colour on accent), B.7 · Verification (+21 more)

### Community 60 - "Design flow (default)"
Cohesion: 0.07
Nodes (28): 0. Pre-flight scan, 1. Design-context gate, 2.5. Check project memory, 2.6. Theme route — studied-DNA, catalog, or custom, 2. Pick a macrostructure FIRST, 3. Load the visual ruleset, 4. Decide on hero enrichment, 5. Preview (+20 more)

### Community 61 - "Recipes"
Cohesion: 0.07
Nodes (27): Accessibility ground truth, Button press, Command palette navigation, Copy-to-clipboard, Drag handle, Dropdown / menu, Form validation, Hard rules for default-on motion (+19 more)

### Community 62 - "Study — extracting design DNA from a screenshot or URL"
Cohesion: 0.08
Nodes (26): After the file is written, Emitting a `design.md` from `study`, Image-mode template, Junk-or-blocked detection, Limits and disclaimers, Refusal — when not to study, Remote URL safety, Source mode — image or URL (+18 more)

### Community 64 - "Hero enrichment — when, what, and how much"
Cohesion: 0.09
Nodes (23): Animation discipline (hero specifically), Common mistakes — and the fixes, E1 · Demo Video — Clipped-by-viewport-edge, E2 · Demo Video — Full-bleed muted loop with ghost overlay, E3 · Mock App Screenshot — Browser-framed split, E4 · Mock App Screenshot — Floating no-frame, E5 · Custom Illustration Centerpiece, E6 · Animated Loop — pure CSS / SVG / Motion (+15 more)

### Community 65 - "Theme — Carnival"
Cohesion: 0.09
Nodes (22): Anti-patterns (theme-specific), Axes (diversification), Build hint, Drop 01 · Cold Snap *(default)*, Drop 02 · Citrus Riot, Drop 03 · Diner Sign, Drop 04 · Studio Night, Drop 05 · Aqua Park (+14 more)

### Community 66 - "Interaction and states"
Cohesion: 0.10
Nodes (21): Bans, Computation, Contrast discipline, Don't, list, Dropdowns, tooltips, popovers, Focus rings, Forms, Heights and rhythm (+13 more)

### Community 67 - "Major (looks AI-generated)"
Cohesion: 0.10
Nodes (20): AI-illustration look, Animate-on-scroll on everything, Bounce and elastic easing, Centred everything, Eyebrow on every section, Generic emoji as feature icon, Glassmorphism without purpose, Hover-only affordances (+12 more)

### Community 69 - "Slop test — 58 gates + pre-emit self-critique"
Cohesion: 0.11
Nodes (19): Contrast & readability, Diversification gates, Hero enrichment gates, Honest copy · no fabricated content, Implementation gates, Input-state gate, Layout-safety gates, Microinteractions (+11 more)

### Community 70 - "Copy"
Cohesion: 0.11
Nodes (17): Austere, Banned opening lines (anti-patterns), Brutalist, Buttons, Copy, Editorial, Empty states, Error messages (+9 more)

### Community 71 - "Critical (ships as slop)"
Cohesion: 0.12
Nodes (17): Aurora-blob background, Card-in-card, Critical (ships as slop), Default-attractor sameness, Floating-orb decoration, Full-viewport centred hero, Inter-everywhere, Lazy-loaded LCP (+9 more)

### Community 72 - "Typography"
Cohesion: 0.12
Nodes (17): Banned defaults, Bans, Body text rules, Free body faces, Free display faces, Free mono / outlier faces, Headings rules, Hero headline sizing — match size to copy length (+9 more)

### Community 73 - "Microinteraction tells"
Cohesion: 0.14
Nodes (14): Animated hover gradients, Auto-rotating carousels with no pause, Bouncy overshoot easings on UI, Celebratory success toasts, Confirmation dialogs for reversible actions, Cursor follower dots, Focus rings that animate in, Microinteraction tells (+6 more)

### Community 74 - "Archetype index — load ONLY the picks you need"
Cohesion: 0.14
Nodes (14): Archetype index — load ONLY the picks you need, Component cookbook, CTAs / signups, Feature blocks, Footers, Heroes, Mobile collapse — per archetype, Navigation (+6 more)

### Community 75 - "Theme — Cobalt"
Cohesion: 0.14
Nodes (13): Anti-patterns, Axes (diversification), Build hint, How Cobalt differs from neighbouring themes, Macrostructure affinity, Macrostructure rejection, Motion, Reference register (+5 more)

### Community 76 - "Theme - Grid"
Cohesion: 0.14
Nodes (13): Axes (diversification), Build hint, Do-nots (this theme's own failure modes), How Grid differs from its neighbours, Material, Motion, Reference register, The marks kit (+5 more)

### Community 77 - "just_audio_background.dart"
Cohesion: 0.01
Nodes (122): androidEqualizerBandSetGain, androidEqualizerGetParameters, androidLoudnessEnhancerSetTargetGain, audioEffectSetEnabled, _audioHandler, _broadcastState, _broadcastStateIfActive, cancelStreamSubscriptions (+114 more)

### Community 78 - "Responsive"
Cohesion: 0.15
Nodes (13): Bans, Breakpoints, Clickable text — never wraps, Fluid scaling, Images, Internationalisation, Mobile — non-negotiable, Pointer and hover queries (+5 more)

### Community 79 - "The six axes"
Cohesion: 0.15
Nodes (13): 1. Section-heading placement, 2. Body composition, 3. Divider language, 4. Button voice, 5. Image treatment, 6. Reveal pattern, Anti-patterns of structural sameness, Domain → trio (offer these three; never default) (+5 more)

### Community 80 - "display_rate_service.dart"
Cohesion: 0.17
Nodes (7): _activeRefreshRate, _channel, DisplayRateService, initialize, _initialized, instance, _supportedRates

### Community 81 - "Minor (small taste issues)"
Cohesion: 0.18
Nodes (11): 100vw widths, Anti-patterns — the named tells, Double-hyphen dashes, Every section padded the same, How `hallmark audit` should report, Minor (small taste issues), Placeholder names, Startup-cliché product names (+3 more)

### Community 82 - "Imagery kit — curated abstract assets, hosted, ready"
Cohesion: 0.18
Nodes (11): Anti-patterns, Categories, Decoration, Empty state, Generation pipeline (out-of-band, one-time), Imagery kit — curated abstract assets, hosted, ready, Layered hero composition (the masterclass move), Manifest (placeholder until generation pass ships) (+3 more)

### Community 84 - "Genre — atmospheric"
Cohesion: 0.20
Nodes (10): Genre — atmospheric, Nav and footer voice, Reference register, Stamp signature, Themes that belong, Voice, Voice fixtures, What this genre allows (+2 more)

### Community 85 - "Genre — modern-minimal"
Cohesion: 0.18
Nodes (10): Genre — modern-minimal, Nav and footer voice, Reference register (for the LLM, not credited to anyone), Stamp signature, Themes that belong, Voice, Voice fixtures, What this genre allows (+2 more)

### Community 86 - "Genre — playful"
Cohesion: 0.20
Nodes (10): Genre — playful, Nav and footer voice, Reference register, Stamp signature, Themes that belong, Voice, Voice fixtures, What this genre allows (+2 more)

### Community 87 - "§ Multi-page flow — design.md first, then redesign"
Cohesion: 0.20
Nodes (10): 1. Read the project, then pause, 2. Produce `design.md` at the project root, 3. Redesign each page reading from `design.md`, 4. Diversification rule — INVERTED for multi-page, 5. When to amend `design.md` instead of overriding, `hallmark redesign`, § Multi-page flow — design.md first, then redesign, Non-destructive implementation rule (+2 more)

### Community 88 - "Genre — editorial (default)"
Cohesion: 0.22
Nodes (9): Genre — editorial (default), Nav and footer voice, Stamp signature, Themes that belong, Voice, Voice fixtures, What this genre allows, What this genre disallows (+1 more)

### Community 89 - "Layout and space"
Cohesion: 0.22
Nodes (9): Asymmetry techniques, Bans, Depth, Grids, Layout and space, Page-edge clipping, Principles, The spacing scale (+1 more)

### Community 90 - "Motion"
Cohesion: 0.22
Nodes (9): Bans, Durations, Easings, Motion, Page-load orchestration, Principles, Reduced motion, Scroll-linked motion (+1 more)

### Community 91 - "design.md — opt-in portable design system"
Cohesion: 0.25
Nodes (8): After the file is written, CTA — surface the offer in the Step 5 preview, design.md — opt-in portable design system, Format (the tight version), Scope, Triggers (phrase-only — no new verb), Two emission paths (default vs study), Why opt-in (not auto-emit)

### Community 92 - "Export formats"
Cohesion: 0.25
Nodes (7): Export formats, Format 1 — `tokens.css`, Format 2 — Tailwind v4 `@theme`, Format 3 — DTCG `tokens.json`, Format 4 — shadcn/ui CSS variables, Output rule, Token taxonomy — Hallmark's source of truth

### Community 93 - "Output contract & scope"
Cohesion: 0.50
Nodes (3): Output contract, Output contract & scope, Scope and limits

### Community 94 - "Colour"
Cohesion: 0.29
Nodes (7): Bans, Colour, Contrast, Dark mode recipe, Palette construction, Principles, Use of the accent

### Community 95 - "audio_equalizer_service.dart"
Cohesion: 0.06
Nodes (24): anchorFrequencies, _androidInitialized, _applyAndroidBands, applyBands, _applyNativeBands, _attachNative, AudioEqualizerService, dispose (+16 more)

### Community 96 - "MCP Tools: code-review-graph"
Cohesion: 0.33
Nodes (5): graphify, Key Tools, MCP Tools: code-review-graph, When to use graph tools FIRST, Workflow

### Community 97 - "Floating nav on scroll — the cross-fade morph"
Cohesion: 0.33
Nodes (6): Anti-patterns Hallmark refuses, Floating nav on scroll — the cross-fade morph, The four laws — non-negotiable, The property morph (10 properties, one curve), The scroll handler, The structure

### Community 98 - "MCP Tools: code-review-graph"
Cohesion: 0.33
Nodes (5): graphify, Key Tools, MCP Tools: code-review-graph, When to use graph tools FIRST, Workflow

### Community 99 - "Debug Issue"
Cohesion: 0.40
Nodes (4): Debug Issue, Steps, Tips, Token Efficiency Rules

### Community 100 - "Explore Codebase"
Cohesion: 0.40
Nodes (4): Explore Codebase, Steps, Tips, Token Efficiency Rules

### Community 101 - "Refactor Safely"
Cohesion: 0.40
Nodes (4): Refactor Safely, Safety Checks, Steps, Token Efficiency Rules

### Community 102 - "Review Changes"
Cohesion: 0.40
Nodes (4): Output Format, Review Changes, Steps, Token Efficiency Rules

### Community 103 - "Debug Issue"
Cohesion: 0.40
Nodes (4): Debug Issue, Steps, Tips, Token Efficiency Rules

### Community 104 - "Explore Codebase"
Cohesion: 0.40
Nodes (4): Explore Codebase, Steps, Tips, Token Efficiency Rules

### Community 105 - "Refactor Safely"
Cohesion: 0.40
Nodes (4): Refactor Safely, Safety Checks, Steps, Token Efficiency Rules

### Community 106 - "Review Changes"
Cohesion: 0.40
Nodes (4): Output Format, Review Changes, Steps, Token Efficiency Rules

### Community 107 - "MCP Tools: code-review-graph"
Cohesion: 0.40
Nodes (4): Key Tools, MCP Tools: code-review-graph, When to use graph tools FIRST, Workflow

### Community 108 - "Debug Issue"
Cohesion: 0.40
Nodes (4): Debug Issue, Steps, Tips, Token Efficiency Rules

### Community 109 - "Explore Codebase"
Cohesion: 0.40
Nodes (4): Explore Codebase, Steps, Tips, Token Efficiency Rules

### Community 110 - "Refactor Safely"
Cohesion: 0.40
Nodes (4): Refactor Safely, Safety Checks, Steps, Token Efficiency Rules

### Community 111 - "Review Changes"
Cohesion: 0.40
Nodes (4): Output Format, Review Changes, Steps, Token Efficiency Rules

### Community 112 - "MCP Tools: code-review-graph"
Cohesion: 0.40
Nodes (4): Key Tools, MCP Tools: code-review-graph, When to use graph tools FIRST, Workflow

### Community 113 - "Debug Issue"
Cohesion: 0.40
Nodes (4): Debug Issue, Steps, Tips, Token Efficiency Rules

### Community 114 - "Explore Codebase"
Cohesion: 0.40
Nodes (4): Explore Codebase, Steps, Tips, Token Efficiency Rules

### Community 115 - "Refactor Safely"
Cohesion: 0.40
Nodes (4): Refactor Safely, Safety Checks, Steps, Token Efficiency Rules

### Community 116 - "Review Changes"
Cohesion: 0.40
Nodes (4): Output Format, Review Changes, Steps, Token Efficiency Rules

### Community 117 - "MCP Tools: code-review-graph"
Cohesion: 0.40
Nodes (4): Key Tools, MCP Tools: code-review-graph, When to use graph tools FIRST, Workflow

### Community 118 - "MCP Tools: code-review-graph"
Cohesion: 0.40
Nodes (4): Key Tools, MCP Tools: code-review-graph, When to use graph tools FIRST, Workflow

### Community 119 - "MCP Tools: code-review-graph"
Cohesion: 0.40
Nodes (4): Key Tools, MCP Tools: code-review-graph, When to use graph tools FIRST, Workflow

### Community 120 - "PlaylistScreen"
Cohesion: 0.47
Nodes (5): _openSection, _buildExploreTab, _openPlaylist, PlaylistScreen, _PlaylistScreenState

### Community 122 - "Size"
Cohesion: 0.50
Nodes (3): Size, height, width

### Community 125 - "dashboard_overflow_test.dart"
Cohesion: 0.14
Nodes (9): errors, main, pumpDashboardWithoutPluginNoise, runZonedGuarded, errors, main, pumpDashboard, runZonedGuarded (+1 more)

### Community 127 - "spotify_export_service.dart"
Cohesion: 0.04
Nodes (43): _albumOf, _artistOf, _asList, _asMap, _asString, bytes, _decodeObject, _dedupeKey (+35 more)

### Community 128 - "radio_playlist_offline_download_test.dart"
Cohesion: 0.17
Nodes (4): db, main, db, main

### Community 135 - "spotify_export_import_dialog.dart"
Cohesion: 0.05
Nodes (35): SpotifyExportBundle, _applyBundle, build, _buildActions, _buildIntro, _buildPreview, _buildProgress, _bundle (+27 more)

### Community 136 - "package:music/controllers/music_player_controller.dart"
Cohesion: 0.21
Nodes (4): main, main, main, main

### Community 142 - "spotify_export_service_test.dart"
Cohesion: 0.11
Nodes (13): SpotifyExportException, SpotifyExportService, SpotifyImportException, archive, _encode, _file, id, main (+5 more)

### Community 143 - "ios/RunnerTests/RunnerTests.swift"
Cohesion: 0.38
Nodes (3): Flutter, SceneDelegate, UIKit

### Community 145 - "artist_import_test.dart"
Cohesion: 0.29
Nodes (6): artistLookupJson, artistSearchJson, artistService, brunoMarsId, jsonOk, main

### Community 146 - "just_audio_background"
Cohesion: 0.40
Nodes (4): Android setup, iOS setup, just_audio_background, Setup

### Community 148 - "FlutterMacOS"
Cohesion: 0.47
Nodes (3): Cocoa, FlutterMacOS, XCTest

## Knowledge Gaps
- **1465 isolated node(s):** `C:\Python314\python.exe`, `C:\Python314\python.exe`, `C:\Python314\python.exe`, `LocalUser`, `AuthService` (+1460 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 2339 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **44 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `MusicPlayerController` connect `right_panel.dart` to `music_player_controller.dart`, `music_dashboard_view.dart`, `playlist_screen.dart`, `spotify_export_import_dialog.dart`, `spotify_import_dialog.dart`, `settings_view.dart`, `discovery_sections.dart`, `spotify_lyrics_sheet.dart`, `discovery_playlist_page.dart`, `track_list_view.dart`, `sidebar_nav.dart`?**
  _High betweenness centrality (0.011) - this node is a cross-community bridge._
- **What connects `C:\Python314\python.exe`, `C:\Python314\python.exe`, `C:\Python314\python.exe` to the rest of the system?**
  _1465 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `music_player_controller.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.00641025641025641 - nodes in this community are weakly interconnected._
- **Why does `Win32Window` connect `Win32Window` to `.MessageHandler`, `Size`, `Point`, `string`, `win32_window.cpp`, `FlutterWindow`?**
  _High betweenness centrality (0.007) - this node is a cross-community bridge._
- **Should `track_enrichment_service.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.01694915254237288 - nodes in this community are weakly interconnected._
- **Why does `Anti-patterns — the named tells` connect `Minor (small taste issues)` to `Microinteraction tells`, `Major (looks AI-generated)`, `Critical (ships as slop)`, `hallmark/SKILL.md`?**
  _High betweenness centrality (0.006) - this node is a cross-community bridge._
- **Should `local_database.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.01834862385321101 - nodes in this community are weakly interconnected._