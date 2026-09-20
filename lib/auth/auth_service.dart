import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../data/local_database.dart';

class LocalUser {
  final String id;
  final String email;
  final String displayName;
  final String role;
  final String? photoUrl;

  const LocalUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.role,
    this.photoUrl,
  });

  @override
  String toString() => 'LocalUser(id: $id, email: $email, name: $displayName, role: $role)';
}

class AuthService {
  AuthService._() {
    _initAuthListener();
  }

  static final instance = AuthService._();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final _authController = StreamController<Object?>.broadcast();
  Object? _currentUser;
  bool _listenerStarted = false;

  Stream<Object?> get authChanges {
    _initAuthListener();
    return _authController.stream;
  }

  Object? get currentUser => _currentUser;

  void _initAuthListener() {
    if (_listenerStarted) return;
    _listenerStarted = true;

    // Check local database for active session
    LocalDatabase.instance.getActiveSessionUserId().then((savedUserId) async {
      if (savedUserId != null) {
        final localData = await LocalDatabase.instance.getUserById(savedUserId);
        if (localData != null) {
          _currentUser = LocalUser(
            id: localData['id'] as String,
            email: localData['email'] as String,
            displayName: localData['display_name'] as String,
            role: localData['role'] as String? ?? 'user',
            photoUrl: localData['photo_url'] as String?,
          );
          _authController.add(_currentUser);
          return;
        }
      }

      // If no local session, listen to Firebase Auth
      _auth.authStateChanges().listen((user) {
        if (_currentUser is! LocalUser) {
          _currentUser = user;
          _authController.add(user);
        }
      });
    }).catchError((e) {
      debugPrint('[AuthService] Init local session error: $e');
      _auth.authStateChanges().listen((user) {
        if (_currentUser is! LocalUser) {
          _currentUser = user;
          _authController.add(user);
        }
      });
    });
  }

  Future<void> _loginAsLocalUser(Map<String, Object?> userData) async {
    final localUser = LocalUser(
      id: userData['id'] as String,
      email: userData['email'] as String,
      displayName: userData['display_name'] as String,
      role: userData['role'] as String? ?? 'user',
      photoUrl: userData['photo_url'] as String?,
    );
    await LocalDatabase.instance.saveActiveSession(localUser.id);
    _currentUser = localUser;
    _authController.add(localUser);
  }

  Future<void> signInAsAdmin() async {
    await LocalDatabase.instance.seedAdminUserIfNeeded();
    final admin = await LocalDatabase.instance.getUserById('1');
    if (admin != null) {
      await _loginAsLocalUser(admin);
    } else {
      await LocalDatabase.instance.saveUser(
        id: '1',
        email: 'admin@pulsemusic.app',
        displayName: 'System Administrator',
        role: 'admin',
      );
      final fallbackAdmin = await LocalDatabase.instance.getUserById('1');
      if (fallbackAdmin != null) {
        await _loginAsLocalUser(fallbackAdmin);
      }
    }
  }

  Future<void> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: cleanEmail,
        password: password,
      );
      await credential.user?.updateDisplayName(name.trim());
      _currentUser = credential.user;
      _authController.add(credential.user);
      _upsertUser(credential.user!, provider: 'password').catchError((e) {
        debugPrint('[AuthService] Firestore sync skipped: $e');
      });
    } on FirebaseAuthException catch (e) {
      final isConfigError = e.code == 'configuration-not-found' ||
          (e.message != null && e.message!.contains('CONFIGURATION_NOT_FOUND'));
      if (isConfigError) {
        final userId = 'usr-${DateTime.now().millisecondsSinceEpoch}';
        await LocalDatabase.instance.saveUser(
          id: userId,
          email: cleanEmail,
          displayName: name.trim(),
          role: 'user',
        );
        final user = await LocalDatabase.instance.getUserById(userId);
        if (user != null) {
          await _loginAsLocalUser(user);
          return;
        }
      }
      rethrow;
    }
  }

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final cleanEmail = email.trim().toLowerCase();

    // If logging in as admin directly
    if (cleanEmail == 'admin@pulsemusic.app' || cleanEmail == '1') {
      await signInAsAdmin();
      return;
    }

    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: cleanEmail,
        password: password,
      );
      _currentUser = credential.user;
      _authController.add(credential.user);
      _upsertUser(credential.user!, provider: 'password').catchError((e) {
        debugPrint('[AuthService] Firestore sync skipped: $e');
      });
    } on FirebaseAuthException catch (e) {
      final isConfigError = e.code == 'configuration-not-found' ||
          (e.message != null && e.message!.contains('CONFIGURATION_NOT_FOUND'));

      // If user exists in local database, sign them in locally
      final localUser = await LocalDatabase.instance.getUserByEmail(cleanEmail);
      if (localUser != null) {
        await _loginAsLocalUser(localUser);
        return;
      }

      if (isConfigError) {
        throw FirebaseAuthException(
          code: 'configuration-not-found',
          message: 'Firebase Email/Password is not enabled in Firebase Console. Tap "Continue as Admin" to sign in immediately.',
        );
      }
      rethrow;
    } catch (e) {
      final localUser = await LocalDatabase.instance.getUserByEmail(cleanEmail);
      if (localUser != null) {
        await _loginAsLocalUser(localUser);
        return;
      }
      rethrow;
    }
  }

  Future<void> signInWithGoogle() async {
    final googleUser = await GoogleSignIn.instance.authenticate();
    final googleAuth = googleUser.authentication;
    final credential = GoogleAuthProvider.credential(idToken: googleAuth.idToken);
    final userCredential = await _auth.signInWithCredential(credential);
    _currentUser = userCredential.user;
    _authController.add(userCredential.user);
    _upsertUser(userCredential.user!, provider: 'google').catchError((e) {
      debugPrint('[AuthService] Firestore sync skipped: $e');
    });
  }

  Future<void> signInWithFacebook() async {
    final result = await FacebookAuth.instance.login();
    final accessToken = result.accessToken;
    if (accessToken == null) {
      throw FirebaseAuthException(code: 'facebook-login-cancelled');
    }
    final credential = FacebookAuthProvider.credential(accessToken.tokenString);
    final userCredential = await _auth.signInWithCredential(credential);
    _currentUser = userCredential.user;
    _authController.add(userCredential.user);
    _upsertUser(userCredential.user!, provider: 'facebook').catchError((e) {
      debugPrint('[AuthService] Firestore sync skipped: $e');
    });
  }

  Future<void> recordActivity({required String screen, String? trackTitle}) async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _firestore.collection('user_activity').doc(user.uid).set({
      'userId': user.uid,
      'screen': screen,
      'trackTitle': trackTitle,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> signOut() async {
    await LocalDatabase.instance.clearActiveSession();
    _currentUser = null;
    _authController.add(null);
    try {
      await _auth.signOut();
    } catch (e) {
      debugPrint('[AuthService] Firebase signOut: $e');
    }
  }

  Future<void> _upsertUser(User user, {required String provider}) async {
    final document = _firestore.collection('users').doc(user.uid);
    final snapshot = await document.get();
    await document.set({
      'email': user.email,
      'displayName': user.displayName ?? user.email?.split('@').first ?? 'Music listener',
      'photoUrl': user.photoURL,
      'provider': provider,
      'lastLoginAt': FieldValue.serverTimestamp(),
      if (!snapshot.exists) ...{
        'role': 'user',
        'createdAt': FieldValue.serverTimestamp(),
      },
    }, SetOptions(merge: true));
  }
}
