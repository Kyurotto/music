import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'data/local_database.dart';
import 'theme/app_theme.dart';
import 'views/auth_gate.dart';
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
  // Initialize Firebase on every platform so Google/Facebook OAuth can
  // return the real accurate profile. Guarded: local auth still works
  // when Firebase options are missing (e.g. desktop without config).
  try {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      await Firebase.initializeApp();
    } else if (kIsWeb || Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      await Firebase.initializeApp();
    }
  } catch (e) {
    debugPrint('[MusicApp] Firebase not configured, using local auth: $e');
  }
  runApp(const MusicApp(firebaseEnabled: true));
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
      // Always go through AuthGate when enabled (local session works on every platform).
      // When disabled (e.g. in tests), mount MusicDashboardView directly.
      home: firebaseEnabled ? const AuthGate() : const MusicDashboardView(),
    );
  }
}
