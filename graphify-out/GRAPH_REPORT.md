# Graph Report - music  (2026-10-26)

## Corpus Check
- 222 files · ~325,822 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 60 file(s) not represented in the graph (top: (none) 9, .xml 8, .xcconfig 8)

## Summary
- 2286 nodes · 2671 edges · 142 communities (103 shown, 39 thin omitted)
- Extraction: 99% EXTRACTED · 1% INFERRED · 0% AMBIGUOUS · INFERRED: 17 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `fdf570ca`
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
- album_card.dart
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
- artist_import_test.dart
- main.dart
- Win32Window
- manifest.json
- imported_playlist_database_test.dart
- db_sync_daemon.py
- .MessageHandler
- discovery_service_test.dart
- package:flutter/material.dart
- @visibleForTesting
- Point
- Size
- code-review-graph
- code-review-graph
- code-review-graph
- SpotifyImportException
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
- auth_gate.dart
- Slop test — 58 gates + pre-emit self-critique
- Copy
- Critical (ships as slop)
- Typography
- Microinteraction tells
- Archetype index — load ONLY the picks you need
- Theme — Cobalt
- Theme - Grid
- equalizer_preset.dart
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
- dashboard_overflow_test.dart
- Colour
- Macrostructures
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
- Output contract & scope
- music
- c1-outlined-chip.md
- c3-typographic-link.md
- c4-sticky-bottom-bar.md
- f3-tabular-spec-sheet.md
- ft4-dense-typographic.md
- ft5-statement.md
- ft6-letter-close.md
- h3-quote-led.md
- h7-demo-video-clipped-by-viewport-edge.md
- h9-custom-illustration-centerpiece.md
- n1b-saas-three-section.md
- n3-side-rail.md
- n5-floating-pill.md
- n7-brutal-slab.md
- n8-terminal-command.md
- s4-inline-no-break.md
- t1-pull-quote-with-marginalia.md
- t4-numbered-stat-strip.md
- .claude/CLAUDE.md
- LaunchImage.imageset/README.md

## God Nodes (most connected - your core abstractions)
1. `Win32Window` - 21 edges
2. `Major (looks AI-generated)` - 20 edges
3. `Slop test — 58 gates + pre-emit self-critique` - 19 edges
4. `Theme — Hum` - 18 edges
5. `Critical (ships as slop)` - 17 edges
6. `Theme — Lumen` - 17 edges
7. `Recipes` - 16 edges
8. `Microinteraction tells` - 14 edges
9. `MusicPlayerController` - 13 edges
10. `Responsive` - 13 edges

## Surprising Connections (you probably didn't know these)
- `wWinMain()` --calls--> `CreateAndAttachConsole()`  [INFERRED]
  windows/runner/main.cpp → windows/runner/utils.cpp
- `my_application_activate()` --calls--> `fl_register_plugins()`  [INFERRED]
  linux/runner/my_application.cc → linux/flutter/generated_plugin_registrant.cc
- `main()` --calls--> `my_application_new()`  [INFERRED]
  linux/runner/main.cc → linux/runner/my_application.cc
- `FlutterWindow` --inherits--> `Win32Window`  [EXTRACTED]
  windows/runner/flutter_window.h → windows/runner/win32_window.h
- `wWinMain()` --calls--> `GetCommandLineArguments()`  [INFERRED]
  windows/runner/main.cpp → windows/runner/utils.cpp

## Import Cycles
- None detected.

## Communities (142 total, 39 thin omitted)

### Community 0 - "music_player_controller.dart"
Cohesion: 0.01
Nodes (189): _activateAudioSession, addedCount, addSong, addSongToPlaylist, addToQueue, _allSongs, _applyEnrichment, _artworkLookupMemo (+181 more)

### Community 1 - "track_enrichment_service.dart"
Cohesion: 0.02
Nodes (103): _alwaysSkipMarkers, _archiveCoolDownUntil, _archiveCreator, _archiveItemAudio, _archiveLength, _archiveSearch, artworkUrl, browserUserAgent (+95 more)

### Community 2 - "local_database.dart"
Cohesion: 0.02
Nodes (76): addTrackToPlaylist, claimAnonymousPlaylists, _cleanImportedPlaylistsAndPreviews, _cleanOrphanImportedSongs, clearActiveSession, close, _constantTimeEquals, _createAccountTables (+68 more)

### Community 3 - "spotify_import_service.dart"
Cohesion: 0.03
Nodes (60): album, artist, artworkUrl, _browserUserAgent, _cleanArtistQuery, _client, _decodeJsonObject, _deepFindMap (+52 more)

### Community 4 - "music_dashboard_view.dart"
Cohesion: 0.03
Nodes (49): PlaybackRepeatMode, _albumGridDelegate, _authSub, build, _buildCurrentTabContent, _buildExploreTab, _buildFavoritesTab, _buildHeaderWithActions (+41 more)

### Community 5 - "discovery_service.dart"
Cohesion: 0.04
Nodes (52): album, artist, artworkUrl, at, _cache, _cached, _CacheEntry, _cacheTtl (+44 more)

### Community 6 - "GeneratedPluginRegistrant.swift"
Cohesion: 0.05
Nodes (23): audio_service, audio_session, cloud_firestore, Cocoa, connectivity_plus, firebase_auth, firebase_core, Flutter (+15 more)

### Community 7 - "spotify_import_dialog.dart"
Cohesion: 0.10
Nodes (19): SpotifyImportResult, build, _confirmImport, controller, createState, dispose, _error, _formKey (+11 more)

### Community 8 - "auth_service.dart"
Cohesion: 0.05
Nodes (38): _authController, AuthService, backupEmail, copyWith, _currentUser, displayName, email, _emitAuth (+30 more)

### Community 9 - "song_model.dart"
Cohesion: 0.05
Nodes (34): album, artist, audioUrl, duration, formatTime, genre, genres, gradient (+26 more)

### Community 10 - "animated_visualizer.dart"
Cohesion: 0.12
Nodes (14): barCount, barWidth, build, _controller, createState, didUpdateWidget, dispose, equalizerBands (+6 more)

### Community 11 - "settings_view.dart"
Cohesion: 0.05
Nodes (37): _allowExplicit, _autoLyrics, _automix, _autoplay, build, _buildCard, _buildProfileCard, _buildSectionHeader (+29 more)

### Community 12 - "song_artwork_widget.dart"
Cohesion: 0.06
Nodes (28): artist, border, borderRadius, build, _buildImageWithFallback, _buildSpotifyProceduralArt, color, _effectiveArtist (+20 more)

### Community 13 - "discovery_sections.dart"
Cohesion: 0.06
Nodes (27): _applySection, _autoRefresher, build, _computeSignature, controller, createState, dispose, _fastLocateTracks (+19 more)

### Community 14 - "my_application.cc"
Cohesion: 0.08
Nodes (14): fl_register_plugins(), main(), first_frame_cb(), my_application_activate(), my_application_class_init(), my_application_dispose(), my_application_init(), my_application_local_command_line() (+6 more)

### Community 15 - "spotify_lyrics_sheet.dart"
Cohesion: 0.08
Nodes (20): build, controller, createState, dispose, _fetchingForId, _highlightedLineIndex, initState, _lastSeenSongId (+12 more)

### Community 16 - "utils.cpp"
Cohesion: 0.19
Nodes (4): wWinMain(), CreateAndAttachConsole(), GetCommandLineArguments(), Utf8FromUtf16()

### Community 17 - "discovery_playlist_page.dart"
Cohesion: 0.08
Nodes (20): DiscoverySection, build, _clock, controller, cover, DiscoveryPlaylistPage, duration, isCurrent (+12 more)

### Community 18 - "album_card.dart"
Cohesion: 0.18
Nodes (9): MusicPlaylist, build, createState, _isHovered, isSelected, onDelete, onPlay, onTap (+1 more)

### Community 19 - "right_panel.dart"
Cohesion: 0.08
Nodes (21): MusicPlayerController, Song, BottomPlayerBar, build, _buildCompactPlayer, _buildDesktopPlayer, controller, onOpenLyrics (+13 more)

### Community 20 - "app_theme.dart"
Cohesion: 0.10
Nodes (18): accentAmber, accentGreen, accentPink, AppTheme, background, border, borderActive, cardGlowGradient (+10 more)

### Community 21 - "track_list_view.dart"
Cohesion: 0.10
Nodes (20): build, controller, createState, emptySubtitle, emptyTitle, index, isCompact, isCurrent (+12 more)

### Community 22 - "package:flutter_test/flutter_test.dart"
Cohesion: 0.12
Nodes (8): SpotifyImportService, buildTestWidget, main, main, main, service, main, main

### Community 23 - "discovery_auto_refresh.dart"
Cohesion: 0.11
Nodes (13): didChangeAppLifecycleState, DiscoveryAutoRefresher, dispose, _disposed, interval, _lastRefresh, markRefreshed, minGap (+5 more)

### Community 24 - "State"
Cohesion: 0.15
Nodes (16): DiscoverySections, DiscoverySectionsState, _CreatePlaylistDialog, _CreatePlaylistDialogState, MusicDashboardView, _MusicDashboardViewState, AlbumCard, _AlbumCardState (+8 more)

### Community 26 - "win32_window.cpp"
Cohesion: 0.19
Nodes (5): Scale(), Win32Window::Win32Window(), WindowClassRegistrar, class_registered_, instance_

### Community 27 - "FlutterWindow"
Cohesion: 0.12
Nodes (4): FlutterWindow, flutter_controller_, FlutterWindow::FlutterWindow(), project_

### Community 28 - "sidebar_nav.dart"
Cohesion: 0.08
Nodes (24): MusicApp, AuthGate, _Header, _SongRow, _DiscoveryRail, _StorageLegend, HeroBanner, badge (+16 more)

### Community 29 - "component-cookbook.md"
Cohesion: 0.03
Nodes (32): C2 · Inline form-as-CTA, F1 · Bento grid, F2 · Sticky-scroll stack, F4 · Step sequence, F5 · Annotated screenshot, F6 · Product card grid, Ft1 · Mast-headed, Ft2 · Inline-rule single line (+24 more)

### Community 30 - "artist_import_test.dart"
Cohesion: 0.16
Nodes (9): artistLookupJson, artistSearchJson, artistService, brunoMarsId, jsonOk, main, jsonOk, main (+1 more)

### Community 32 - "main.dart"
Cohesion: 0.17
Nodes (3): build, firebaseEnabled, main

### Community 33 - "Win32Window"
Cohesion: 0.18
Nodes (5): RegisterPlugins(), Win32Window, child_content_, quit_on_close_, window_handle_

### Community 34 - "manifest.json"
Cohesion: 0.18
Nodes (10): background_color, description, display, icons, name, orientation, prefer_related_applications, short_name (+2 more)

### Community 36 - "db_sync_daemon.py"
Cohesion: 0.31
Nodes (3): run_sync(), save_db_bytes(), main()

### Community 38 - "discovery_service_test.dart"
Cohesion: 0.22
Nodes (5): album, artist, main, millis, _track

### Community 40 - "@visibleForTesting"
Cohesion: 0.40
Nodes (4): ensureOfflineLyricsForTesting, getOfflineAssetFallbackForTesting, createAllTables, setDatabaseForTesting

### Community 41 - "Point"
Cohesion: 0.50
Nodes (3): Point, x, y

### Community 42 - "Size"
Cohesion: 0.50
Nodes (3): Size, height, width

### Community 54 - "Assets — sourcing canon for icons, logos, illustrations, photography, video"
Cohesion: 0.05
Nodes (44): Abstract backgrounds, App mockups / device frames, Assets — sourcing canon for icons, logos, illustrations, photography, video, Avoid, Avoid, Avoid, Avoid, Avoid (+36 more)

### Community 55 - "macrostructures.md"
Cohesion: 0.05
Nodes (21): 01 · Bento Grid, 02 · Long Document, 03 · Marquee Hero, 04 · Stat-Led, 05 · Workbench, 06 · Conversational FAQ, 07 · Manifesto, 08 · Photographic (+13 more)

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

### Community 68 - "auth_gate.dart"
Cohesion: 0.10
Nodes (19): AuthView, _AuthViewState, build, _confirmPasswordController, createState, dispose, _emailController, _formKey (+11 more)

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

### Community 77 - "equalizer_preset.dart"
Cohesion: 0.14
Nodes (10): all, bands, description, EqualizerPreset, frequencyLabels, gainFactor, getByName, icon (+2 more)

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
Cohesion: 0.20
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

### Community 93 - "dashboard_overflow_test.dart"
Cohesion: 0.25
Nodes (4): errors, main, pumpDashboardWithoutPluginNoise, runZonedGuarded

### Community 94 - "Colour"
Cohesion: 0.29
Nodes (7): Bans, Colour, Contrast, Dark mode recipe, Palette construction, Principles, Use of the accent

### Community 95 - "Macrostructures"
Cohesion: 0.29
Nodes (7): Diversification rule (mandatory), Hero polish patterns, How to pick, Macrostructures, Nav and footer voice, SaaS page sequence, The 21 macrostructures — index

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

### Community 120 - "Output contract & scope"
Cohesion: 0.50
Nodes (3): Output contract, Output contract & scope, Scope and limits

## Knowledge Gaps
- **935 isolated node(s):** `C:\Python314\python.exe`, `C:\Python314\python.exe`, `C:\Python314\python.exe`, `LocalUser`, `AuthService` (+930 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 1768 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **39 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Anti-patterns — the named tells` connect `Minor (small taste issues)` to `Microinteraction tells`, `Major (looks AI-generated)`, `Critical (ships as slop)`, `hallmark/SKILL.md`?**
  _High betweenness centrality (0.014) - this node is a cross-community bridge._
- **What connects `C:\Python314\python.exe`, `C:\Python314\python.exe`, `C:\Python314\python.exe` to the rest of the system?**
  _935 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `music_player_controller.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.009950248756218905 - nodes in this community are weakly interconnected._
- **Why does `MusicPlayerController` connect `right_panel.dart` to `music_player_controller.dart`, `music_dashboard_view.dart`, `spotify_import_dialog.dart`, `settings_view.dart`, `discovery_sections.dart`, `spotify_lyrics_sheet.dart`, `discovery_playlist_page.dart`, `track_list_view.dart`, `sidebar_nav.dart`?**
  _High betweenness centrality (0.014) - this node is a cross-community bridge._
- **Should `track_enrichment_service.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.018691588785046728 - nodes in this community are weakly interconnected._
- **Why does `Assets — sourcing canon for icons, logos, illustrations, photography, video` connect `Assets — sourcing canon for icons, logos, illustrations, photography, video` to `hallmark/SKILL.md`?**
  _High betweenness centrality (0.013) - this node is a cross-community bridge._
- **Should `local_database.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.024390243902439025 - nodes in this community are weakly interconnected._