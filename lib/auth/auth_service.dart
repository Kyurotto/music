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

  FirebaseAuth? get _auth {
    try {
      return FirebaseAuth.instance;
    } catch (_) {
      return null;
    }
  }

  FirebaseFirestore? get _firestore {
    try {
      return FirebaseFirestore.instance;
    } catch (_) {
      return null;
    }
  }

  final _authController = StreamController<Object?>.broadcast();
  Object? _currentUser;
  bool _listenerStarted = false;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  Stream<Object?> get authChanges {
    _initAuthListener();
    return _authController.stream;
  }

  Object? get currentUser => _currentUser;

  String get userDisplayName {
    final user = _currentUser;
    if (user is LocalUser) return user.displayName;
    if (user is User) return user.displayName ?? user.email?.split('@').first ?? 'System Administrator';
    return 'System Administrator';
  }

  String get userEmail {
    final user = _currentUser;
    if (user is LocalUser) return user.email;
    if (user is User) return user.email ?? 'admin@pulsemusic.app';
    return 'admin@pulsemusic.app';
  }

  String get userRole {
    final user = _currentUser;
    if (user is LocalUser) return user.role;
    if (user is User) return 'User';
    return 'admin';
  }

  String get userInitials {
    final name = userDisplayName.trim();
    if (name.isEmpty) return 'PM';
    final parts = name.split(' ');
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }

  void _initAuthListener() {
    if (_listenerStarted) return;
    _listenerStarted = true;

    // Check local database for active session
    LocalDatabase.instance.getActiveSessionUserId().then((savedUserId) async {
      if (savedUserId != null) {
        final localData = await LocalDatabase.instance.getUserById(savedUserId);
        if (localData != null) {
          final savedName = (localData['display_name'] as String? ?? '').trim();
          final savedProvider = (localData['auth_provider'] as String? ?? '');
          final isPlaceholder = (savedProvider == 'google' || savedProvider == 'facebook') &&
              _isGenericName(savedName, savedProvider);
          if (isPlaceholder) {
            // Stale placeholder session (e.g. "Google User 12345") — drop it
            // so the user signs in again and gets the real account name.
            try {
              await LocalDatabase.instance.clearActiveSession();
              await LocalDatabase.instance.deleteUser(savedUserId);
            } catch (_) {}
          } else {
            _currentUser = LocalUser(
              id: localData['id'] as String,
              email: localData['email'] as String,
              displayName: localData['display_name'] as String,
              role: localData['role'] as String? ?? 'user',
              photoUrl: localData['photo_url'] as String?,
            );
            _isInitialized = true;
            _authController.add(_currentUser);
            return;
          }
        }
      }

      // If no local session, listen to Firebase Auth if initialized
      final auth = _auth;
      if (auth != null) {
        _currentUser = auth.currentUser;
        auth.authStateChanges().listen((user) {
          if (_currentUser is! LocalUser) {
            _currentUser = user;
            _authController.add(user);
          }
        });
      }
      _isInitialized = true;
      _authController.add(_currentUser);
    }).catchError((e) {
      debugPrint('[AuthService] Init local session error: $e');
      _isInitialized = true;
      final auth = _auth;
      if (auth != null) {
        _currentUser = auth.currentUser;
        auth.authStateChanges().listen((user) {
          if (_currentUser is! LocalUser) {
            _currentUser = user;
            _authController.add(user);
          }
        });
      }
      _authController.add(_currentUser);
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
    final auth = _auth;
    if (auth == null) {
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
      throw FirebaseAuthException(code: 'firebase-unavailable');
    }

    try {
      final credential = await auth.createUserWithEmailAndPassword(
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

    final auth = _auth;
    if (auth == null) {
      final localUser = await LocalDatabase.instance.getUserByEmail(cleanEmail);
      if (localUser != null) {
        await _loginAsLocalUser(localUser);
        return;
      }
      throw FirebaseAuthException(
        code: 'configuration-not-found',
        message: 'Account not found. Please register to create an account.',
      );
    }

    try {
      final credential = await auth.signInWithEmailAndPassword(
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
          message: 'Account not found. Please register to create an account.',
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

  final _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
  );

  /// True for auto-generated / placeholder names that must never
  /// overwrite a real profile name like "Juan Dela Cruz".
  bool _isGenericName(String name, String provider) {
    final n = name.trim().toLowerCase();
    if (n.isEmpty) return true;
    if (n == 'facebook user' || n == 'google user') return true;
    if (n == 'music listener' || n == 'user') return true;
    if (provider == 'google' && RegExp(r'^google user \d+$').hasMatch(n)) return true;
    if (provider == 'facebook' && RegExp(r'^facebook user \d+$').hasMatch(n)) return true;
    return false;
  }

  /// Fully automatic one-click sign-in-or-sign-up for a social provider.
  /// Reuses the most recent REAL (non-placeholder) account so the accurate
  /// profile name is kept. Never creates a fake name like "Google User 12345" —
  /// for a new account it gets the real profile from the provider instead.
  /// Never shows errors for this path.
  Future<void> signInWithProviderAuto({required String provider}) async {
    try {
      final saved = await LocalDatabase.instance.getUsersByProvider(provider);
      Map<String, Object?>? realAccount;
      final placeholderIds = <String>[];
      for (final row in saved) {
        final id = row['id'] as String?;
        if (id == null) continue;
        final name = (row['display_name'] as String? ?? '').trim();
        if (name.isNotEmpty && !_isGenericName(name, provider)) {
          realAccount ??= row; // first real account (most recent login)
        } else {
          placeholderIds.add(id);
        }
      }
      // Remove stale placeholder rows so they never resurface.
      for (final id in placeholderIds) {
        try {
          await LocalDatabase.instance.deleteUser(id);
        } catch (_) {}
      }
      if (realAccount != null) {
        await _loginAsLocalUser(realAccount);
        return;
      }
    } catch (e) {
      debugPrint('[AuthService] Saved account reuse note: $e');
    }
    // No real saved account: get the REAL profile (sign-in or auto sign-up).
    // Never generate a placeholder display name.
    if (provider == 'google') {
      await signInWithGoogle();
    } else {
      await signInWithFacebook();
    }
  }

  Future<void> signInWithRealProfile({
    required String email,
    required String displayName,
    String? photoUrl,
    required String provider,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    var cleanName = displayName.trim();
    if (cleanName.isEmpty) cleanName = cleanEmail.split('@').first;
    final userId = '$provider-${DateTime.now().millisecondsSinceEpoch}';

    var existingUser = await LocalDatabase.instance.getUserByEmail(cleanEmail);
    if (existingUser == null) {
      await LocalDatabase.instance.saveUser(
        id: userId,
        email: cleanEmail,
        displayName: cleanName,
        photoUrl: photoUrl,
        role: 'user',
        authProvider: provider,
      );
      existingUser = await LocalDatabase.instance.getUserById(userId);
    } else {
      // Accuracy guard: never overwrite a real stored name/photo with a
      // generic placeholder or a missing value from a failed profile read.
      final oldName = (existingUser['display_name'] as String? ?? '').trim();
      final oldPhoto = existingUser['photo_url'] as String?;
      final newIsGeneric = _isGenericName(cleanName, provider);
      final oldIsGeneric = _isGenericName(oldName, provider);
      final resolvedName = (newIsGeneric && !oldIsGeneric) ? oldName : cleanName;
      final resolvedPhoto = (photoUrl == null || photoUrl.isEmpty) ? oldPhoto : photoUrl;
      await LocalDatabase.instance.saveUser(
        id: existingUser['id'] as String,
        email: cleanEmail,
        displayName: resolvedName,
        photoUrl: resolvedPhoto,
        role: existingUser['role'] as String? ?? 'user',
        authProvider: provider,
      );
      existingUser = await LocalDatabase.instance.getUserById(existingUser['id'] as String);
    }

    if (existingUser != null) {
      await _loginAsLocalUser(existingUser);
    }
    // Cleanup: a real accurate profile just signed in - remove any stale
    // "Google User 12345" / "Facebook User" placeholder rows of the same
    // provider so they never resurface. Best-effort, never blocks login.
    final signedInId = existingUser?['id'];
    if (existingUser != null && !_isGenericName(cleanName, provider)) {
      try {
        final others = await LocalDatabase.instance.getUsersByProvider(provider);
        for (final row in others) {
          final otherId = row['id'] as String?;
          final otherName = (row['display_name'] as String? ?? '').trim();
          if (otherId != null &&
              otherId != signedInId &&
              _isGenericName(otherName, provider)) {
            await LocalDatabase.instance.deleteUser(otherId);
          }
        }
      } catch (e) {
        debugPrint('[AuthService] Placeholder cleanup note: $e');
      }
    }
  }

  /// Browser/IdP OAuth via Firebase (works on desktop/web where the
  /// native SDKs are unavailable). Returns true with the REAL accurate
  /// profile name when it succeeds, false otherwise. Never throws.
  Future<bool> _signInWithOAuthProvider(
    AuthProvider provider, {
    required String providerName,
  }) async {
    final auth = _auth;
    if (auth == null) return false;
    try {
      final userCredential = await auth.signInWithProvider(provider);
      final user = userCredential.user;
      if (user == null) return false;
      try {
        await _upsertUser(user, provider: providerName);
      } catch (e) {
        debugPrint('[AuthService] Firestore sync skipped: $e');
      }
      // Prefer the OAuth profile name Firebase received from Google/Facebook.
      final mirrored = await _mirrorFirebaseUserToLocal(
        user,
        provider: providerName,
        realName: user.displayName,
        realPhoto: user.photoURL,
        realEmail: user.email,
      );
      if (mirrored) return true;
      // Mirror failed: still keep the signed-in session so the user is
      // not logged out, but prefer any non-empty Firebase display name.
      _currentUser = user;
      _authController.add(user);
      return true;
    } catch (e) {
      debugPrint('[AuthService] OAuth $providerName note: $e');
      return false;
    }
  }

  /// One-click Google sign-in: existing account -> sign in,
  /// new account -> auto sign-up. Never throws for user cancellation.
  /// Returns true when signed in, false when the user cancelled.
  /// Throws only when native sign-in is unavailable/failed so the UI
  /// can offer the local one-tap fallback sheet.
  Future<bool> signInWithGoogle() async {
    GoogleSignInAccount? googleUser;
    try {
      googleUser = await _googleSignIn.signIn();
    } catch (e) {
      debugPrint('[AuthService] Google native unavailable, trying OAuth: $e');
      // Desktop/web: open the real Google picker in the browser so the
      // accurate account name is returned instead of a placeholder.
      final oauthOk = await _signInWithOAuthProvider(
        GoogleAuthProvider(),
        providerName: 'google',
      );
      if (oauthOk) return true;
      throw FirebaseAuthException(
        code: 'google-unavailable',
        message: 'Google sign-in is unavailable. Choose a saved account or add one.',
      );
    }
    if (googleUser == null) {
      // User dismissed the account selection dialog - silent cancel.
      return false;
    }

    // Best-effort Firebase credential link - never blocks local sign-in.
    final auth = _auth;
    if (auth != null) {
      try {
        final googleAuth = await googleUser.authentication;
        if (googleAuth.idToken != null) {
          final credential = GoogleAuthProvider.credential(
            idToken: googleAuth.idToken,
            accessToken: googleAuth.accessToken,
          );
          final userCredential = await auth.signInWithCredential(credential);
          // Firestore sync must never break login.
          try {
            await _upsertUser(userCredential.user!, provider: 'google');
          } catch (e) {
            debugPrint('[AuthService] Firestore sync skipped: $e');
          }
          // Mirror into local DB with the REAL Google profile fields so the
          // displayed name always matches the actual Google account.
          final mirrored = await _mirrorFirebaseUserToLocal(
            userCredential.user!,
            provider: 'google',
            realName: googleUser.displayName,
            realPhoto: googleUser.photoUrl,
            realEmail: googleUser.email,
          );
          if (mirrored) return true;
          // Mirror failed (e.g. no email): fall back to local profile sign-in
          // using the real Google account data below.
        }
      } catch (e) {
        debugPrint('[AuthService] Firebase credential sign-in note: $e');
        // Fall through to local profile sign-in below.
      }
    }

    // Capture the real Google user profile directly from Play Services.
    // Existing email -> sign in (keeping the accurate stored name),
    // new email -> auto sign-up - no extra taps, no errors.
    final realEmail = googleUser.email.trim().toLowerCase();
    if (realEmail.isEmpty || !realEmail.contains('@')) {
      throw FirebaseAuthException(
        code: 'invalid-email',
        message: 'Could not read your Google email. Please try again.',
      );
    }
    var realName = (googleUser.displayName != null && googleUser.displayName!.trim().isNotEmpty)
        ? googleUser.displayName!.trim()
        : '';
    final realPhoto = googleUser.photoUrl;
    // If Google returned no display name, reuse the accurate stored name
    // for this email instead of falling back to the email prefix.
    if (realName.isEmpty) {
      try {
        final stored = await LocalDatabase.instance.getUserByEmail(realEmail);
        final storedName = (stored?['display_name'] as String? ?? '').trim();
        if (storedName.isNotEmpty && !_isGenericName(storedName, 'google')) {
          realName = storedName;
        } else {
          realName = realEmail.split('@').first;
        }
      } catch (_) {
        realName = realEmail.split('@').first;
      }
    }

    await signInWithRealProfile(
      email: realEmail,
      displayName: realName,
      photoUrl: realPhoto,
      provider: 'google',
    );
    return true;
  }

  /// Mirror a Firebase [User] into the local database so the account shows
  /// up in the one-tap chooser and works offline. Never throws.
  /// [realName]/[realPhoto]/[realEmail] come straight from the native
  /// Google/Facebook SDK and always win over a missing/generic Firebase value.
  /// Returns true when the local profile was saved and set as the active user.
  Future<bool> _mirrorFirebaseUserToLocal(
    User user, {
    required String provider,
    String? realName,
    String? realPhoto,
    String? realEmail,
  }) async {
    try {
      var email = (realEmail ?? user.email ?? '').trim().toLowerCase();
      if (email.isEmpty || !email.contains('@')) {
        email = (user.email ?? '').trim().toLowerCase();
      }
      if (email.isEmpty || !email.contains('@')) return false;

      var name = (realName ?? user.displayName ?? '').trim();
      if (name.isEmpty || _isGenericName(name, provider)) {
        // Prefer the accurate stored local name over a missing/generic
        // Firebase display name.
        try {
          final stored = await LocalDatabase.instance.getUserByEmail(email);
          final storedName = (stored?['display_name'] as String? ?? '').trim();
          if (storedName.isNotEmpty && !_isGenericName(storedName, provider)) {
            name = storedName;
          } else if (name.isEmpty) {
            name = email.split('@').first;
          }
        } catch (_) {
          if (name.isEmpty) name = email.split('@').first;
        }
      }

      final photo = (realPhoto != null && realPhoto.isNotEmpty)
          ? realPhoto
          : user.photoURL;

      await signInWithRealProfile(
        email: email,
        displayName: name,
        photoUrl: photo,
        provider: provider,
      );
      // Keep the LocalUser (with the verified real name) as the active
      // session. Do NOT overwrite it with the raw Firebase User — that
      // object often has a null displayName and would show an email
      // prefix instead of the real Google/Facebook account name.
      return _currentUser is LocalUser;
    } catch (e) {
      debugPrint('[AuthService] Local mirror skipped: $e');
      return false;
    }
  }

  /// One-click Facebook sign-in: existing account -> sign in,
  /// new account -> auto sign-up. Returns false only when cancelled.
  Future<bool> signInWithFacebook() async {
    late final LoginResult result;
    try {
      result = await FacebookAuth.instance.login(
        permissions: ['email', 'public_profile'],
      );
    } catch (e) {
      debugPrint('[AuthService] Facebook native unavailable, trying OAuth: $e');
      final oauthOk = await _signInWithOAuthProvider(
        FacebookAuthProvider(),
        providerName: 'facebook',
      );
      if (oauthOk) return true;
      throw FirebaseAuthException(
        code: 'facebook-unavailable',
        message: 'Facebook sign-in is unavailable. Choose a saved account or add one.',
      );
    }

    if (result.status == LoginStatus.cancelled) {
      return false; // Silent cancel - no sheet, no snackbar.
    }
    if (result.status == LoginStatus.operationInProgress) {
      return false;
    }
    if (result.status != LoginStatus.success || result.accessToken == null) {
      debugPrint('[AuthService] Facebook native failed, trying OAuth: ${result.message}');
      final oauthOk = await _signInWithOAuthProvider(
        FacebookAuthProvider(),
        providerName: 'facebook',
      );
      if (oauthOk) return true;
      throw FirebaseAuthException(
        code: 'facebook-failed',
        message: 'Facebook sign-in did not complete. Choose a saved account or add one.',
      );
    }

    final accessToken = result.accessToken!;

    // Read the real Facebook profile FIRST so the accurate account name
    // is always available, even when the Firebase credential link succeeds.
    String fbEmail = '';
    String fbName = '';
    String? fbPhoto;
    String fbId = '';
    try {
      final userData = await FacebookAuth.instance.getUserData();
      fbId = (userData['id']?.toString() ?? '').trim();
      final rawEmail = (userData['email'] as String?)?.trim().toLowerCase() ?? '';
      fbEmail = rawEmail.contains('@') ? rawEmail : '';
      fbName = (userData['name'] as String?)?.trim() ?? '';
      final picture = userData['picture'];
      if (picture is Map) {
        final data = picture['data'];
        if (data is Map && data['url'] is String) fbPhoto = data['url'] as String;
      }
    } catch (e) {
      debugPrint('[AuthService] Facebook profile read note: $e');
    }

    // Best-effort Firebase credential link - never blocks local sign-in.
    final auth = _auth;
    if (auth != null) {
      try {
        final credential = FacebookAuthProvider.credential(accessToken.tokenString);
        final userCredential = await auth.signInWithCredential(credential);
        try {
          await _upsertUser(userCredential.user!, provider: 'facebook');
        } catch (e) {
          debugPrint('[AuthService] Firestore sync skipped: $e');
        }
        // Mirror with the REAL Facebook profile fields so the displayed
        // name always matches the actual Facebook account.
        final mirrored = await _mirrorFirebaseUserToLocal(
          userCredential.user!,
          provider: 'facebook',
          realName: fbName,
          realPhoto: fbPhoto,
          realEmail: fbEmail.isNotEmpty ? fbEmail : userCredential.user?.email,
        );
        if (mirrored) return true;
        // Mirror failed: fall through to local profile sign-in below.
      } catch (e) {
        debugPrint('[AuthService] Firebase Facebook credential note: $e');
        // Fall through to local profile sign-in below.
      }
    }
    // Unique, stable fallback when email permission is declined:
    // never collide multiple users on a shared placeholder.
    if (fbEmail.isEmpty) {
      final suffix = fbId.isNotEmpty
          ? fbId
          : DateTime.now().millisecondsSinceEpoch.toString();
      fbEmail = 'fb-$suffix@facebook.com';
    }
    // Accuracy: if Facebook returned no real name, reuse the accurate
    // stored name for this email instead of the "Facebook User" placeholder.
    if (_isGenericName(fbName, 'facebook')) {
      try {
        final stored = await LocalDatabase.instance.getUserByEmail(fbEmail);
        final storedName = (stored?['display_name'] as String? ?? '').trim();
        if (storedName.isNotEmpty && !_isGenericName(storedName, 'facebook')) {
          fbName = storedName;
        }
      } catch (_) {}
    }

    await signInWithRealProfile(
      email: fbEmail,
      displayName: fbName,
      photoUrl: fbPhoto,
      provider: 'facebook',
    );
    return true;
  }

  Future<void> recordActivity({required String screen, String? trackTitle}) async {
    final auth = _auth;
    final firestore = _firestore;
    if (auth == null || firestore == null) return;
    final user = auth.currentUser;
    if (user == null) return;
    await firestore.collection('user_activity').doc(user.uid).set({
      'userId': user.uid,
      'screen': screen,
      'trackTitle': trackTitle,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> signOut() async {
    await LocalDatabase.instance.clearActiveSession();
    _currentUser = null;
    _isInitialized = true;
    _authController.add(null);
    try {
      await _auth?.signOut();
      await _googleSignIn.signOut();
      await FacebookAuth.instance.logOut();
    } catch (e) {
      debugPrint('[AuthService] signOut: $e');
    }
  }

  Future<void> _upsertUser(User user, {required String provider}) async {
    try {
      final firestore = _firestore;
      if (firestore == null) return;
      final document = firestore.collection('users').doc(user.uid);
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
    } catch (e) {
      // Firestore sync is best-effort only - local sign-in already succeeded.
      debugPrint('[AuthService] Firestore sync skipped: $e');
    }
  }
}
