import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'data/local_database.dart';
import 'theme/app_theme.dart';
import 'views/music_dashboard_view.dart';
import 'views/auth_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // On desktop platforms, initialise the FFI-based SQLite implementation
  // before any database access so the native library is loaded in time.
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  await LocalDatabase.instance.initialize();
  final firebaseEnabled = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  if (firebaseEnabled) {
    await Firebase.initializeApp();
  }
  runApp(MusicApp(firebaseEnabled: firebaseEnabled));
}

class MusicApp extends StatelessWidget {
  const MusicApp({super.key, this.firebaseEnabled = false});

  final bool firebaseEnabled;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pulse Music Player & Dashboard',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: firebaseEnabled ? const AuthGate() : const MusicDashboardView(),
    );
  }
}
