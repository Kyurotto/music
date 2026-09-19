import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'data/local_database.dart';
import 'theme/app_theme.dart';
import 'views/music_dashboard_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // On desktop platforms, initialise the FFI-based SQLite implementation
  // before any database access so the native library is loaded in time.
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  await LocalDatabase.instance.initialize();
  runApp(const MusicApp());
}

class MusicApp extends StatelessWidget {
  const MusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pulse Music Player & Dashboard',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const MusicDashboardView(),
    );
  }
}
