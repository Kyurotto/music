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

  /// True while an explicit social sign-in (Google/Facebook/OAuth) is in
  /// flight. Background Firebase `authStateChanges` events are still
  /// persisted to SQLite, but never emitted to the UI during that window:
  /// emitting a raw Firebase `User` first and the mirrored `LocalUser`
  /// second rebuilds `AuthGate` twice and unmounts the login form while its
  /// own `await` is still using its `BuildContext`, which trips
  /// `'_dependents.isEmpty'` in framework.dart. The explicit sign-in method
  /// emits exactly one mirrored `LocalUser` when it finishes instead.
  bool _socialSignInInProgress = false;

  void _emitAuth(Object? user) {
    _currentUser = user;
    if (!_authController.isClosed) _authController.add(user);
  }

  bool get isInitialized => _isInitialized;

  Stream<Object?> get authChanges {
    _initAuthListener();
    return _authController.stream;
  }

  Object? get currentUser => _currentUser;

  String get currentUserId {
    final user = _currentUser;
    if (user is LocalUser) return user.id;
    if (user is User) return user.uid;
    return '';
  }

  String get userDisplayName {
    final user = _currentUser;
    if (user is LocalUser) {
      final n = user.displayName.trim();
      return n.isNotEmpty ? user.displayName : 'Guest';
    }
    if (user is User) {
      final n = (user.displayName ?? '').trim();
      if (n.isNotEmpty) return n;
      final e = (user.email ?? '').trim();
      if (e.isNotEmpty && e.contains('@')) return e.split('@').first;
      return 'Guest';
    }
    return 'Guest';
  }

  String get userEmail {
    final user = _currentUser;
    if (user is LocalUser) return user.email;
    if (user is User) return (user.email ?? '').trim();
    return '';
  }

  String get userRole {
    final user = _currentUser;
    if (user is LocalUser) return user.role;
    if (user is User) return 'user';
    return 'guest';
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

  /// Maps Firebase providerData to our local auth_provider column.
  /// Email/password stays 'password' even for gmail.com addresses.
  String _firebaseProvider(User user) {
    try {
      for (final info in user.providerData) {
        final id = (info.providerId).toLowerCase();
        if (id.contains('google')) return 'google';
        if (id.contains('facebook')) return 'facebook';
        if (id.contains('password')) return 'password';
      }
    } catch (_) {}
    return 'password';
  }

  void _initAuthListener() {
    if (_listenerStarted) return;
    _listenerStarted = true;

    // Check local database for active session
    LocalDatabase.instance.getActiveSessionUserId().then((savedUserId) async {
      if (savedUserId != null) {
        final localData = await LocalDatabase.instance.getUserById(savedUserId);
        if (localData != null) {
          // Restore the saved session exactly as stored — never rewrite
          // it to a different account.
          _currentUser = LocalUser(
            id: localData['id'] as String,
            email: (localData['email'] as String? ?? '').trim(),
            displayName:
                (localData['display_name'] as String? ?? '').trim(),
            role: localData['role'] as String? ?? 'user',
            photoUrl: localData['photo_url'] as String?,
          );
          _isInitialized = true;
          _authController.add(_currentUser);
          return;
        }
      }

      // If no local session, listen to Firebase Auth if initialized
      final auth = _auth;
      if (auth != null) {
        _currentUser = auth.currentUser;
        if (auth.currentUser != null) {
          final u = auth.currentUser!;
          final email = (u.email ?? '').trim();
          if (email.isNotEmpty) {
            // Email/password accounts stay 'password' even for gmail.com.
            // Only use google/facebook when Firebase providerData says so.
            final provider = _firebaseProvider(u);
            final rawName = (u.displayName ?? '').trim();
            LocalDatabase.instance.saveUser(
              id: u.uid,
              email: email,
              displayName:
                  rawName.isNotEmpty ? rawName : email.split('@').first,
              photoUrl: u.photoURL,
              role: 'user',
              authProvider: provider,
            ).catchError((_) {});
          }
        }
        auth.authStateChanges().listen((user) {
          if (user != null && user.email != null) {
            final email = user.email!;
            final provider = _firebaseProvider(user);
            final rawName = (user.displayName ?? '').trim();
            LocalDatabase.instance.saveUser(
              id: user.uid,
              email: email,
              displayName:
                  rawName.isNotEmpty ? rawName : email.split('@').first,
              photoUrl: user.photoURL,
              role: 'user',
              authProvider: provider,
            ).catchError((_) {});
          }
          // Never yank the UI out from under an in-flight social sign-in.
          // The sign-in method emits its single mirrored LocalUser itself.
          if (_socialSignInInProgress) return;
          if (_currentUser is! LocalUser) {
            _emitAuth(user);
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
          if (_socialSignInInProgress) return;
          if (_currentUser is! LocalUser) {
            _emitAuth(user);
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
    await LocalDatabase.instance.seedDefaultUserIfNeeded();
    final user = await LocalDatabase.instance.getUserByEmail('johnlaurencenovicio@gmail.com');
    if (user != null) {
      await _loginAsLocalUser(user);
    }
  }

  Future<void> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final cleanName =
        name.trim().isNotEmpty ? name.trim() : cleanEmail.split('@').first;
    const provider = 'password';
    final auth = _auth;

    await LocalDatabase.instance.removeDefaultAdminIfSeeded();

    final existingLocal = await LocalDatabase.instance.getUserByEmail(cleanEmail);
    final userId = existingLocal != null
        ? (existingLocal['id'] as String)
        : await LocalDatabase.instance.getNextUserId();
    // Hash locally — plaintext passwords are never written to SQLite.
    final passwordHash = LocalDatabase.hashPassword(password);

    if (auth != null) {
      try {
        final credential = await auth.createUserWithEmailAndPassword(
          email: cleanEmail,
          password: password,
        );
        await credential.user?.updateDisplayName(cleanName);
        _currentUser = credential.user;
        _authController.add(credential.user);
        _upsertUser(credential.user!, provider: provider).catchError((e) {
          debugPrint('[AuthService] Firestore sync skipped: $e');
        });
        final fbUser = credential.user!;
        await LocalDatabase.instance.saveUser(
          id: fbUser.uid,
          email: cleanEmail,
          displayName: cleanName,
          role: 'user',
          authProvider: provider,
          passwordHash: passwordHash,
        );
        await LocalDatabase.instance.saveActiveSession(fbUser.uid);
        await LocalDatabase.instance.claimAnonymousPlaylists(fbUser.uid);
        return;
      } catch (e) {
        debugPrint('[AuthService] Firebase register fallback to local: $e');
      }
    }

    // Always create and save in LocalDatabase so registration never fails and always appears in SQLite
    await LocalDatabase.instance.saveUser(
      id: userId,
      email: cleanEmail,
      displayName: cleanName,
      role: 'user',
      authProvider: provider,
      passwordHash: passwordHash,
    );
    await LocalDatabase.instance.saveActiveSession(userId);
    await LocalDatabase.instance.claimAnonymousPlaylists(userId);
    final user = await LocalDatabase.instance.getUserById(userId);
    if (user != null) {
      await _loginAsLocalUser(user);
      return;
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
      final verified =
          await LocalDatabase.instance.verifyLocalPassword(cleanEmail, password);
      if (verified != null) {
        await _loginAsLocalUser(verified);
        return;
      }
      final exists =
          await LocalDatabase.instance.getUserByEmail(cleanEmail);
      if (exists != null) {
        throw FirebaseAuthException(
          code: 'wrong-password',
          message: 'Incorrect email address or password.',
        );
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
      // Mirror Firebase account into local SQLite so it appears in
      // pulse_music.db (SQLite viewer) + keep session so the app shows
      // the real user (e.g. John Laurence) instead of the default.
      try {
        final fbUser = credential.user!;
        var displayName = (fbUser.displayName ?? '').trim();
        if (displayName.isEmpty) {
          final stored =
              await LocalDatabase.instance.getUserByEmail(cleanEmail);
          final storedName =
              (stored?['display_name'] as String? ?? '').trim();
          displayName = storedName.isNotEmpty
              ? storedName
              : cleanEmail.split('@').first;
        }
        await LocalDatabase.instance.saveUser(
          id: fbUser.uid,
          email: cleanEmail,
          displayName: displayName,
          role: 'user',
          authProvider: 'password',
          passwordHash: LocalDatabase.hashPassword(password),
        );
        await LocalDatabase.instance.saveActiveSession(fbUser.uid);
        await LocalDatabase.instance.claimAnonymousPlaylists(fbUser.uid);
      } catch (e) {
        debugPrint('[AuthService] Local mirror skipped: $e');
      }
    } on FirebaseAuthException catch (e) {
      final isConfigError = e.code == 'configuration-not-found' ||
          (e.message != null && e.message!.contains('CONFIGURATION_NOT_FOUND'));

      // If user exists in local database, verify the stored hash before
      // signing them in locally — never log in on email alone.
      final verified =
          await LocalDatabase.instance.verifyLocalPassword(cleanEmail, password);
      if (verified != null) {
        await _loginAsLocalUser(verified);
        return;
      }
      final exists =
          await LocalDatabase.instance.getUserByEmail(cleanEmail);
      if (exists != null) {
        throw FirebaseAuthException(
          code: 'wrong-password',
          message: 'Incorrect email address or password.',
        );
      }

      if (isConfigError) {
        throw FirebaseAuthException(
          code: 'configuration-not-found',
          message: 'Account not found. Please register to create an account.',
        );
      }
      rethrow;
    } catch (e) {
      final verified =
          await LocalDatabase.instance.verifyLocalPassword(cleanEmail, password);
      if (verified != null) {
        await _loginAsLocalUser(verified);
        return;
      }
      final exists =
          await LocalDatabase.instance.getUserByEmail(cleanEmail);
      if (exists != null) {
        throw FirebaseAuthException(
          code: 'wrong-password',
          message: 'Incorrect email address or password.',
        );
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
    if (n.startsWith('google.user') || n.startsWith('facebook.user')) return true;
    if (n.startsWith('google-user') || n.startsWith('facebook-user')) return true;
    if (provider == 'google' && RegExp(r'^google(\.|\s|-)?user.*$').hasMatch(n)) return true;
    if (provider == 'facebook' && RegExp(r'^facebook(\.|\s|-)?user.*$').hasMatch(n)) return true;
    return false;
  }

  /// Fully automatic one-click sign-in-or-sign-up for a social provider.
  /// One real email == one stable account: an existing saved account is
  /// reused, a typed email signs in or creates exactly that account.
  /// Throws a friendly FirebaseAuthException only when there is no saved
  /// account, no typed email, and the native/OAuth flow is unavailable —
  /// the UI turns that into a "type your email first" hint. Never invents
  /// a different/fake account.
  Future<void> signInWithProviderAuto({
    required String provider,
    String? preferredEmail,
    String? preferredName,
    bool forceNewAccount = false,
  }) async {
    final cleanEmail = (preferredEmail ?? '').trim().toLowerCase();
    final cleanName = (preferredName ?? '').trim();

    // 1. If user entered an email, always use exactly that account.
    if (cleanEmail.isNotEmpty && cleanEmail.contains('@')) {
      final displayName =
          cleanName.isNotEmpty ? cleanName : cleanEmail.split('@').first;
      await signInWithRealProfile(
        email: cleanEmail,
        displayName: displayName,
        provider: provider,
      );
      return;
    }

    // 2. Otherwise reuse the most recent real saved account of this provider,
    // so repeated taps sign into the SAME account instead of creating
    // a different one each time.
    if (!forceNewAccount) {
      try {
        final saved = await LocalDatabase.instance.getUsersByProvider(provider);
        for (final row in saved) {
          final name = (row['display_name'] as String? ?? '').trim();
          final email = (row['email'] as String? ?? '').trim().toLowerCase();
          if (name.isNotEmpty &&
              email.contains('@') &&
              !_isGenericName(name, provider)) {
            await _loginAsLocalUser(row);
            return;
          }
        }
      } catch (e) {
        debugPrint('[AuthService] Saved account reuse note: $e');
      }
    }

    // 3. Otherwise, use the native SDK / OAuth for the real profile.
    try {
      final success = provider == 'google'
          ? await signInWithGoogle(isCreatingNewAccount: forceNewAccount)
          : await signInWithFacebook(isCreatingNewAccount: forceNewAccount);
      if (success) return;
    } catch (_) {}

    // No saved account, no typed email, native/OAuth unavailable:
    // ask the user for their email instead of inventing an account.
    final label = provider == 'google' ? 'Gmail' : 'Facebook email';
    throw FirebaseAuthException(
      code: '$provider-unavailable',
      message:
          'Type your $label address in the email field above, then tap Continue with ${provider == 'google' ? 'Google' : 'Facebook'}.',
    );
  }

  /// Persists exactly one stable account per real email. A new email creates
  /// one row; an existing email reuses its row (same id) and keeps its
  /// original auth provider and role — a Google tap never converts a
  /// password account into a different Google account or vice versa.
  Future<void> signInWithRealProfile({
    required String email,
    required String displayName,
    String? photoUrl,
    required String provider,
  }) async {
    var cleanEmail = email.trim().toLowerCase();
    var cleanName = displayName.trim();

    // Reject placeholder/invalid emails instead of mapping them onto
    // someone else's account.
    if (cleanEmail.isEmpty ||
        !cleanEmail.contains('@') ||
        cleanEmail.startsWith('google.user') ||
        cleanEmail.startsWith('facebook.user') ||
        cleanEmail.startsWith('fb-')) {
      throw FirebaseAuthException(
        code: 'invalid-email',
        message: 'Enter a valid email address.',
      );
    }

    // Never persist a generic placeholder name; use the email prefix.
    if (cleanName.isEmpty || _isGenericName(cleanName, provider)) {
      cleanName = cleanEmail.split('@').first;
    }
    if (cleanName.isEmpty) cleanName = '$provider-user';

    var existingUser = await LocalDatabase.instance.getUserByEmail(cleanEmail);
    if (existingUser == null) {
      final userId = await LocalDatabase.instance.getNextUserId();
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
      // generic placeholder or a missing value from a failed profile read,
      // and never flip the original auth provider or role.
      final oldName = (existingUser['display_name'] as String? ?? '').trim();
      final oldPhoto = existingUser['photo_url'] as String?;
      final newIsGeneric = _isGenericName(cleanName, provider);
      final oldIsGeneric = _isGenericName(oldName, provider);
      final resolvedName = (newIsGeneric && !oldIsGeneric)
          ? oldName
          : (newIsGeneric ? cleanEmail.split('@').first : cleanName);
      final resolvedPhoto = (photoUrl == null || photoUrl.isEmpty) ? oldPhoto : photoUrl;
      await LocalDatabase.instance.saveUser(
        id: existingUser['id'] as String,
        email: cleanEmail,
        displayName: resolvedName,
        photoUrl: resolvedPhoto,
        role: existingUser['role'] as String? ?? 'user',
        authProvider:
            existingUser['auth_provider'] as String? ?? provider,
      );
      existingUser = await LocalDatabase.instance.getUserById(existingUser['id'] as String);
    }

    if (existingUser != null) {
      await _loginAsLocalUser(existingUser);
      debugPrint('[AuthService] Saved $provider user: $cleanEmail as $cleanName');
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
    _socialSignInInProgress = true;
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
      _emitAuth(user);
      return true;
    } catch (e) {
      debugPrint('[AuthService] OAuth $providerName note: $e');
      return false;
    } finally {
      _socialSignInInProgress = false;
    }
  }

  /// One-click Google sign-in: existing account -> sign in,
  /// new account -> auto sign-up. Never throws for user cancellation.
  /// Returns true when signed in, false when the user cancelled.
  /// Throws only when native sign-in is unavailable/failed so the UI
  /// can offer the local one-tap fallback sheet.
  Future<bool> signInWithGoogle({bool isCreatingNewAccount = false}) async {
    GoogleSignInAccount? googleUser;
    _socialSignInInProgress = true;
    try {
      try {
        if (isCreatingNewAccount) {
          try {
            await _googleSignIn.signOut();
          } catch (_) {}
        }
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
    if (realName.isEmpty || _isGenericName(realName, 'google') || realName.startsWith('google.user')) {
      try {
        final stored = await LocalDatabase.instance.getUserByEmail(realEmail);
        final storedName = (stored?['display_name'] as String? ?? '').trim();
        if (storedName.isNotEmpty &&
            !_isGenericName(storedName, 'google') &&
            !storedName.startsWith('google.user')) {
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
    } finally {
      _socialSignInInProgress = false;
    }
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
      if (email.isEmpty ||
          !email.contains('@') ||
          email.startsWith('google.user') ||
          email.startsWith('facebook.user')) {
        email = (user.email ?? '').trim().toLowerCase();
      }
      // No valid email: do NOT invent a different account. The caller keeps
      // the Firebase session; a row is created once a real email is known.
      if (email.isEmpty ||
          !email.contains('@') ||
          email.startsWith('google.user') ||
          email.startsWith('facebook.user')) {
        return false;
      }

      var name = (realName ?? user.displayName ?? '').trim();
      if (name.isEmpty ||
          _isGenericName(name, provider) ||
          name.startsWith('google.user') ||
          name.startsWith('facebook.user')) {
        try {
          final stored = await LocalDatabase.instance.getUserByEmail(email);
          final storedName = (stored?['display_name'] as String? ?? '').trim();
          if (storedName.isNotEmpty &&
              !_isGenericName(storedName, provider) &&
              !storedName.startsWith('google.user') &&
              !storedName.startsWith('facebook.user')) {
            name = storedName;
          } else {
            name = email.split('@').first;
          }
        } catch (_) {
          name = email.split('@').first;
        }
      }
      // Final guard: never persist a generic placeholder.
      if (name.isEmpty ||
          _isGenericName(name, provider) ||
          name.startsWith('google.user') ||
          name.startsWith('facebook.user')) {
        name = email.split('@').first;
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
  Future<bool> signInWithFacebook({bool isCreatingNewAccount = false}) async {
    _socialSignInInProgress = true;
    try {
      if (isCreatingNewAccount) {
        try {
          await FacebookAuth.instance.logOut();
        } catch (_) {}
      }
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
    try {
      final userData = await FacebookAuth.instance.getUserData();
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
    // Without a real Facebook email there is no account to sign into —
    // throw instead of signing into a different person's account.
    if (fbEmail.isEmpty || fbEmail.startsWith('fb-') || fbEmail.startsWith('facebook.user')) {
      throw FirebaseAuthException(
        code: 'facebook-failed',
        message:
            'Facebook did not share an email address. Type your email above, then tap Continue with Facebook.',
      );
    }
    // Accuracy: if Facebook returned no real name, reuse the accurate
    // stored name for this email instead of a generic placeholder.
    if (fbName.isEmpty || _isGenericName(fbName, 'facebook') || fbName.startsWith('facebook.user')) {
      try {
        final stored = await LocalDatabase.instance.getUserByEmail(fbEmail);
        final storedName = (stored?['display_name'] as String? ?? '').trim();
        if (storedName.isNotEmpty &&
            !_isGenericName(storedName, 'facebook') &&
            !storedName.startsWith('facebook.user')) {
          fbName = storedName;
        } else {
          fbName = fbEmail.split('@').first;
        }
      } catch (_) {
        fbName = fbEmail.split('@').first;
      }
    }

    await signInWithRealProfile(
      email: fbEmail,
      displayName: fbName,
      photoUrl: fbPhoto,
      provider: 'facebook',
    );
    return true;
    } finally {
      _socialSignInInProgress = false;
    }
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
