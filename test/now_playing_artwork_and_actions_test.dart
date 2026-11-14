import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music/controllers/music_player_controller.dart';
import 'package:music/models/song_model.dart';
import 'package:music/widgets/right_panel.dart';
import 'package:music/widgets/song_artwork_widget.dart';
import 'package:music/widgets/spotify_lyrics_sheet.dart';

void main() {
  final testSong = Song(
    id: 'test-song-1',
    title: 'Test Song Title',
    artist: 'Test Artist',
    album: 'Test Album',
    duration: const Duration(minutes: 3, seconds: 30),
    audioUrl: 'https://example.com/audio.mp3',
    imageUrl: '',
    plays: '100',
    genre: 'Rock',
    gradientColors: [const Color(0xFF6366F1), const Color(0xFF8B5CF6)],
    lyrics: [
      '[00:10.00]First line of test lyrics',
      '[00:20.00]Second line of test lyrics',
    ],
  );

  testWidgets('SpotifyLyricsSheet renders Image, Title, Artist, and Lyrics, Save, Download buttons', (
    WidgetTester tester,
  ) async {
    final controller = MusicPlayerController();
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SpotifyLyricsSheet(
              song: testSong,
              controller: controller,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify Cover Art Image is rendered
      expect(find.byType(SongArtworkWidget), findsOneWidget);

      // Verify Title and Artist are rendered below image
      expect(find.text('Test Song Title'), findsOneWidget);
      expect(find.text('Test Artist'), findsOneWidget);

      // Verify the 3 action buttons: Lyrics, Save, Download exist
      expect(find.text('Lyrics'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Download'), findsOneWidget);

      // Tapping Lyrics toggles to lyrics mode
      await tester.tap(find.text('Lyrics'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // In lyrics mode, lyrics lines are visible and Cover toggle button appears
      expect(find.text('First line of test lyrics'), findsOneWidget);
      expect(find.text('Cover'), findsOneWidget);

      // Tapping Cover toggles back to cover art view
      await tester.tap(find.text('Cover'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Lyrics'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Download'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    }
  });

  testWidgets('RightActivityPanel renders Title, Artist, and Lyrics, Save, Download buttons below artwork', (
    WidgetTester tester,
  ) async {
    final controller = MusicPlayerController();
    try {
      controller.playSong(testSong);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              height: 800,
              child: RightActivityPanel(
                controller: controller,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify Title and Artist exist
      expect(find.text('Test Song Title'), findsWidgets);
      expect(find.textContaining('Test Artist'), findsWidgets);

      // Verify the 3 action buttons: Lyrics, Save, Download
      expect(find.text('Lyrics'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Download'), findsOneWidget);

      // Tap Save button to toggle like
      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Saved'), findsOneWidget);

      // Elapse probe reachability timer
      await tester.pump(const Duration(seconds: 3));
    } finally {
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    }
  });
}
