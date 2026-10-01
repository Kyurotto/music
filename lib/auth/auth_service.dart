import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
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

  LocalUser copyWith({
    String? id,
    String? email,
    String? displayName,
    String? role,
    String? photoUrl,
  }) {
    return LocalUser(
      id: id ?? this.id,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      role: role ?? this.role,
      photoUrl: photoUrl ?? this.photoUrl,
    );
  }

  @override
  String toString() =>
      'LocalUser(id: $id, email: $email, name: $displayName, role: $role)';
}

class AuthService {
  AuthService._() {
    _initAuthListener();
  }

  static final instance = AuthService._();

  FirebaseAuth? get _auth {
    try {
      if (Firebase.apps.isEmpty) return null;
      return FirebaseAuth.instance;
    } catch (_) {
      return null;
    }
  }

  FirebaseFirestore? get _firestore {
    try {
      if (Firebase.apps.isEmpty) return null;
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
  final bool _socialSignInInProgress = false;

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
        if (id.contains('password')) return 'password';
      }
    } catch (_) {}
    return 'password';
  }

  /// True when a FirebaseAuthException looks like "no internet / offline"
  /// rather than a real credential rejection. These errors should fall back
  /// to the local SQLite account so Pulse Studio works without Wi-Fi/data.
  bool _isNetworkError(FirebaseAuthException e) {
    if (e.code == 'network-request-failed') return true;
    final msg = (e.message ?? '').toLowerCase();
    return msg.contains('network') ||
        msg.contains('socket') ||
        msg.contains('connection') ||
        msg.contains('host lookup') ||
        msg.contains('failed host') ||
        msg.contains('offline') ||
        msg.contains('unreachable') ||
        msg.contains('timed out') ||
        msg.contains('timeout') ||
        msg.contains('no address');
  }

  /// True when a Firebase *config* error means the backend is unavailable
  /// (not a credential rejection). Local fallback is safe here too.
  bool _isConfigError(FirebaseAuthException e) {
    if (e.code == 'configuration-not-found') return true;
    if (e.code == 'operation-not-allowed') return true;
    final msg = (e.message ?? '').toLowerCase();
    return msg.contains('configuration_not_found') ||
        msg.contains('configuration-not-found');
  }

  /// True when a non-Firebase exception looks like a connectivity failure
  /// (SocketException, HttpException, timeout, etc.).
  bool _isGenericNetworkError(Object e) {
    if (e is TimeoutException) return true;
    final s = e.toString().toLowerCase();
    return s.contains('network-request-failed') ||
        s.contains('socketexception') ||
        s.contains('timeoutexception') ||
        s.contains('host lookup') ||
        s.contains('failed host') ||
        s.contains('connection refused') ||
        s.contains('connection reset') ||
        s.contains('connection timed out') ||
        s.contains('network is unreachable') ||
        s.contains('no address associated') ||
        s.contains('timed out') ||
        s.contains('unreachable');
  }

  /// True when [userRow] is a local-only account: no Firebase UID and
  /// auth_provider is password. Local-only IDs are sequential integers
  /// ('2', '3', ...) from [LocalDatabase.getNextUserId]; Firebase UIDs are
  /// long alphanumeric strings and are never purely numeric.
  bool _isLocalOnlyAccount(Map<String, Object?> userRow) {
    final provider = (userRow['auth_provider'] as String? ?? '').toLowerCase();
    if (provider != 'password') return false;
    final id = (userRow['id'] as String? ?? '');
    if (id.isEmpty) return false;
    if (LocalDatabase.guestUserIds.contains(id)) return false;
    return int.tryParse(id) != null;
  }

  /// Creates + signs in a local-only SQLite account. No Firebase involved,
  /// so this works fully offline. Firestore sync is retried best-effort
  /// via [_loginAsLocalUser] when connectivity returns.
  Future<void> _registerLocally({
    required String cleanEmail,
    required String cleanName,
    required String password,
    bool persistSession = true,
  }) async {
    await LocalDatabase.instance.removeDefaultAdminIfSeeded();
    final passwordHash = LocalDatabase.hashPassword(password);
    final newUserId = await LocalDatabase.instance.getNextUserId();
    await LocalDatabase.instance.saveUser(
      id: newUserId,
      email: cleanEmail,
      displayName: cleanName,
      role: 'user',
      authProvider: 'password',
      passwordHash: passwordHash,
    );
    await LocalDatabase.instance.saveActiveSession(newUserId);
    await LocalDatabase.instance.setPersistSession(persistSession);
    await LocalDatabase.instance.claimAnonymousPlaylists(newUserId);
    final user = await LocalDatabase.instance.getUserById(newUserId);
    if (user != null) {
      await _loginAsLocalUser(user, persistSession: persistSession);
    }
  }

  /// Signs in against the local SQLite password hash. Throws
  /// [FirebaseAuthException] with friendly codes when it fails so the UI
  /// can reuse its existing error mapping.
  Future<void> _signInLocally({
    required String cleanEmail,
    required String password,
    bool persistSession = true,
  }) async {
    final verified = await LocalDatabase.instance.verifyLocalPassword(
      cleanEmail,
      password,
    );
    if (verified != null) {
      await _loginAsLocalUser(verified, persistSession: persistSession);
      return;
    }
    final exists = await LocalDatabase.instance.getUserByEmail(cleanEmail);
    if (exists != null) {
      throw FirebaseAuthException(
        code: 'wrong-password',
        message: 'Incorrect email address or password.',
      );
    }
    throw FirebaseAuthException(
      code: 'user-not-found',
      message: 'Account not found. Please register to create an account.',
    );
  }

  void _initAuthListener() {
    if (_listenerStarted) return;
    _listenerStarted = true;

    // Check local database for active session
    () async {
      try {
        // Honor "Remember me = off" from the last successful sign-in.
        // The session row is intentionally kept during the run (deleting
        // it at sign-in would corrupt claimAnonymousPlaylists' boundary,
        // which uses user_sessions as its clock); persistence is decided
        // here at startup instead. Firebase keeps its own persistence
        // independently of SQLite, so Firebase accounts must also be
        // signed out here — otherwise auth.currentUser would restore the
        // user even with no local session row.
        try {
          final persist = await LocalDatabase.instance.getPersistSession();
          if (!persist) {
            try {
              await _auth?.signOut();
            } catch (_) {}
            try {
              await LocalDatabase.instance.clearActiveSession();
            } catch (_) {}
            try {
              await LocalDatabase.instance.setPersistSession(true);
            } catch (_) {}
            _currentUser = null;
            _isInitialized = true;
            if (!_authController.isClosed) _authController.add(null);
            return;
          }
        } catch (_) {
          // Flag unreadable — fall through to normal restore.
        }

        final savedUserId = await LocalDatabase.instance
            .getActiveSessionUserId();
        if (savedUserId != null) {
          final localData = await LocalDatabase.instance.getUserById(
            savedUserId,
          );
          if (localData != null) {
            // Restore the saved session, but resolve the role from the
            // employees table (employees.user_id == users.id). Editing the
            // employee row in the database is the only way to grant admin.
            final resolvedRole = await LocalDatabase.instance
                .refreshUserRoleFromEmployees(savedUserId);
            _currentUser = LocalUser(
              id: localData['id'] as String,
              email: (localData['email'] as String? ?? '').trim(),
              displayName: (localData['display_name'] as String? ?? '').trim(),
              role: resolvedRole,
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
              LocalDatabase.instance
                  .saveUser(
                    id: u.uid,
                    email: email,
                    displayName: rawName.isNotEmpty
                        ? rawName
                        : email.split('@').first,
                    photoUrl: u.photoURL,
                    role: 'user',
                    authProvider: provider,
                  )
                  .catchError((_) {});
            }
          }
          auth.authStateChanges().listen((user) {
            if (user != null && user.email != null) {
              final email = user.email!;
              final provider = _firebaseProvider(user);
              final rawName = (user.displayName ?? '').trim();
              LocalDatabase.instance
                  .saveUser(
                    id: user.uid,
                    email: email,
                    displayName: rawName.isNotEmpty
                        ? rawName
                        : email.split('@').first,
                    photoUrl: user.photoURL,
                    role: 'user',
                    authProvider: provider,
                  )
                  .catchError((_) {});
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
      } catch (e) {
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
      }
    }();
  }

  Future<void> _loginAsLocalUser(
    Map<String, Object?> userData, {
    bool persistSession = true,
  }) async {
    final userId = userData['id'] as String;
    // Source of truth is employees.user_id -> users.id. Never trust the
    // cached users.role column; an employee row linked to this ID makes
    // the account admin/employee automatically.
    final resolvedRole =
        await LocalDatabase.instance.refreshUserRoleFromEmployees(userId);
    final localUser = LocalUser(
      id: userId,
      email: userData['email'] as String,
      displayName: userData['display_name'] as String,
      role: resolvedRole,
      photoUrl: userData['photo_url'] as String?,
    );
    await LocalDatabase.instance.saveActiveSession(localUser.id);
    await LocalDatabase.instance.setPersistSession(persistSession);
    await LocalDatabase.instance.claimAnonymousPlaylists(localUser.id);
    _currentUser = localUser;
    _authController.add(localUser);

    _upsertToFirestore(
      uid: localUser.id,
      email: localUser.email,
      displayName: localUser.displayName,
      photoUrl: localUser.photoUrl,
      provider: 'password',
    ).catchError((_) {});
  }

  /// Creates an account. Works offline: when Firebase is unreachable
  /// (no Wi-Fi/data, network-request-failed, or missing config) the account
  /// is created in local SQLite and syncs to Firestore later when online.

  Future<void> register({
    String? name,
    required String email,
    required String password,
    bool persistSession = true,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final cleanName = (name != null && name.trim().isNotEmpty)
        ? name.trim()
        : cleanEmail.split('@').first;
    const provider = 'password';
    final auth = _auth;

    await LocalDatabase.instance.removeDefaultAdminIfSeeded();

    final existingLocal = await LocalDatabase.instance.getUserByEmail(
      cleanEmail,
    );
    if (existingLocal != null) {
      throw FirebaseAuthException(
        code: 'email-already-in-use',
        message: 'The email address is already in use by another account.',
      );
    }

    // Hash locally — plaintext passwords are never written to SQLite.
    final passwordHash = LocalDatabase.hashPassword(password);

    if (auth != null) {
      try {
        final credential = await auth
            .createUserWithEmailAndPassword(
              email: cleanEmail,
              password: password,
            )
            .timeout(const Duration(seconds: 4));
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
        await LocalDatabase.instance.setPersistSession(persistSession);
        await LocalDatabase.instance.claimAnonymousPlaylists(fbUser.uid);
        // Keep users.role in sync with employees.user_id == users.id.
        await LocalDatabase.instance.refreshUserRoleFromEmployees(fbUser.uid);
        return;
      } on FirebaseAuthException catch (e) {
        if (e.code == 'email-already-in-use' ||
            e.code == 'invalid-email' ||
            e.code == 'weak-password') {
          rethrow;
        }
        // Offline (no Wi-Fi/data) or missing Firebase config: fall back to
        // a local-only account so Pulse Studio stays usable.
        if (_isNetworkError(e) || _isConfigError(e)) {
          debugPrint(
            '[AuthService] Firebase unavailable (${e.code}), using local registration.',
          );
        } else {
          rethrow;
        }
      } catch (e) {
        // SocketException / HttpException / timeout etc. -> offline mode.
        // Anything else (e.g. an updateDisplayName failure or a saveUser
        // ArgumentError after Firebase already created the account) must
        // rethrow: falling back to _registerLocally would create a second
        // local-only ID and diverge from the Firebase account.
        if (_isGenericNetworkError(e)) {
          debugPrint(
            '[AuthService] Network unavailable, using local registration: $e',
          );
        } else {
          rethrow;
        }
      }
    }

    await _registerLocally(
      cleanEmail: cleanEmail,
      cleanName: cleanName,
      password: password,
      persistSession: persistSession,
    );
  }

  /// Creates an account WITHOUT touching Firebase at all. Use for the
  /// explicit "Create offline account" button so it works instantly with
  /// Wi-Fi/data turned off. The account lives in local SQLite and is
  /// synced to Firestore best-effort on the next online sign-in.
  Future<void> registerOffline({
    String? name,
    required String email,
    required String password,
    bool persistSession = true,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    if (cleanEmail.isEmpty || !cleanEmail.contains('@')) {
      throw FirebaseAuthException(
        code: 'invalid-email',
        message: 'Enter a valid email address.',
      );
    }
    if (password.length < 6) {
      throw FirebaseAuthException(
        code: 'weak-password',
        message: 'Use a password with at least 6 characters.',
      );
    }
    final cleanName = (name != null && name.trim().isNotEmpty)
        ? name.trim()
        : cleanEmail.split('@').first;
    final existingLocal = await LocalDatabase.instance.getUserByEmail(
      cleanEmail,
    );
    if (existingLocal != null) {
      throw FirebaseAuthException(
        code: 'email-already-in-use',
        message: 'The email address is already in use by another account.',
      );
    }
    await _registerLocally(
      cleanEmail: cleanEmail,
      cleanName: cleanName,
      password: password,
      persistSession: persistSession,
    );
  }

  Future<void> signInWithEmail({
    required String email,
    required String password,
    bool persistSession = true,
  }) async {
    final cleanEmail = email.trim().toLowerCase();

    final auth = _auth;
    if (auth == null) {
      final verified = await LocalDatabase.instance.verifyLocalPassword(
        cleanEmail,
        password,
      );
      if (verified != null) {
        await _loginAsLocalUser(verified, persistSession: persistSession);
        return;
      }
      final exists = await LocalDatabase.instance.getUserByEmail(cleanEmail);
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
      final credential = await auth
          .signInWithEmailAndPassword(
            email: cleanEmail,
            password: password,
          )
          .timeout(const Duration(seconds: 4));
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
          final stored = await LocalDatabase.instance.getUserByEmail(
            cleanEmail,
          );
          final storedName = (stored?['display_name'] as String? ?? '').trim();
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
        await LocalDatabase.instance.setPersistSession(persistSession);
        await LocalDatabase.instance.claimAnonymousPlaylists(fbUser.uid);
        // Keep users.role in sync with employees.user_id == users.id.
        await LocalDatabase.instance.refreshUserRoleFromEmployees(fbUser.uid);
      } catch (e) {
        debugPrint('[AuthService] Local mirror skipped: $e');
      }
    } on FirebaseAuthException catch (e) {
      // user-disabled is authoritative — never fall back to the local hash.
      // A disabled account must stay signed out even if a stale local
      // SQLite hash still matches the old password.
      if (e.code == 'user-disabled') rethrow;

      // Firebase rejected the credentials authoritatively (wrong-password,
      // invalid-credential, user-not-found). These are NOT network errors —
      // the user's password was changed remotely or the account does not
      // exist remotely. Only fall back to the local hash for local-only
      // accounts (no Firebase UID, auth_provider password) that may have
      // been created offline. A mirrored Firebase account must never log
      // in with a stale local hash.
      final isCredentialError =
          e.code == 'wrong-password' ||
          e.code == 'invalid-credential' ||
          e.code == 'user-not-found';
      if (isCredentialError) {
        final local = await LocalDatabase.instance.getUserByEmail(cleanEmail);
        if (local != null && _isLocalOnlyAccount(local)) {
          // Local-only account (e.g. created while Firebase was
          // unavailable): verify against the local hash.
          final verified = await LocalDatabase.instance.verifyLocalPassword(
            cleanEmail,
            password,
          );
          if (verified != null) {
            await _loginAsLocalUser(verified, persistSession: persistSession);
            return;
          }
          throw FirebaseAuthException(
            code: 'wrong-password',
            message: 'Incorrect email address or password.',
          );
        }
        // Firebase-backed (or unknown) account: Firebase is authoritative.
        rethrow;
      }

      // Offline (no Wi-Fi/data) or missing Firebase config: fall back to
      // the local SQLite password so Pulse Studio stays usable.
      if (_isNetworkError(e) || _isConfigError(e)) {
        debugPrint(
          '[AuthService] Firebase unavailable (${e.code}), trying local sign-in.',
        );
        await _signInLocally(
          cleanEmail: cleanEmail,
          password: password,
          persistSession: persistSession,
        );
        return;
      }
      rethrow;
    } catch (e) {
      // Non-Firebase error (SocketException, timeout, platform): treat as
      // offline and fall back to local SQLite.
      debugPrint('[AuthService] Sign-in network error, trying local: $e');
      final verified = await LocalDatabase.instance.verifyLocalPassword(
        cleanEmail,
        password,
      );
      if (verified != null) {
        await _loginAsLocalUser(verified, persistSession: persistSession);
        return;
      }
      final exists = await LocalDatabase.instance.getUserByEmail(cleanEmail);
      if (exists != null) {
        throw FirebaseAuthException(
          code: 'wrong-password',
          message: 'Incorrect email address or password.',
        );
      }
      rethrow;
    }
  }

  /// Signs in WITHOUT touching Firebase at all. Use for the explicit
  /// "Sign in offline" button so it works instantly with Wi-Fi/data off.
  /// Verifies the email + password against the local SQLite hash created
  /// by [register] or [registerOffline].
  Future<void> signInOffline({
    required String email,
    required String password,
    bool persistSession = true,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    await _signInLocally(
      cleanEmail: cleanEmail,
      password: password,
      persistSession: persistSession,
    );
  }

  Future<void> recordActivity({
    required String screen,
    String? trackTitle,
  }) async {
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
    try {
      // Reset to the default so a stale "do not persist" flag from a
      // previous sign-in can't affect the next one.
      await LocalDatabase.instance.setPersistSession(true);
    } catch (_) {}
    _currentUser = null;
    _isInitialized = true;
    _authController.add(null);
    try {
      await _auth?.signOut();
    } catch (e) {
      debugPrint('[AuthService] signOut: $e');
    }
  }

  /// Re-reads the role from the employees table
  /// (employees.user_id == users.id) and updates the in-memory user.
  /// Call this after editing the database, or on screens that show the role.
  Future<String> refreshRoleFromDatabase() async {
    final uid = currentUserId;
    if (uid.isEmpty) return userRole;
    final resolved =
        await LocalDatabase.instance.refreshUserRoleFromEmployees(uid);
    if (_currentUser is LocalUser) {
      _currentUser = (_currentUser as LocalUser).copyWith(role: resolved);
      _authController.add(_currentUser);
    }
    return resolved;
  }

  /// Explicitly switches the user's role and connects/syncs with the employee admin database.
  Future<void> switchRole(String newRole) async {
    final uid = currentUserId;
    if (uid.isEmpty) return;
    final email = userEmail;
    final name = userDisplayName;

    // 1. Update local database and sync with employees table
    await LocalDatabase.instance.updateUserRole(
      userId: uid,
      role: newRole,
      email: email,
      displayName: name,
    );

    // 2. Update local in-memory user
    if (_currentUser is LocalUser) {
      _currentUser = (_currentUser as LocalUser).copyWith(role: newRole);
      _authController.add(_currentUser);
    }

    // 3. Best-effort sync to Firestore
    try {
      final firestore = _firestore;
      if (firestore != null) {
        await firestore.collection('users').doc(uid).set({
          'role': newRole,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (_) {}
  }

  Future<void> _upsertToFirestore({
    required String uid,
    required String email,
    required String displayName,
    String? photoUrl,
    required String provider,
    String? role,
  }) async {
    try {
      final firestore = _firestore;
      if (firestore == null) return;
      final document = firestore.collection('users').doc(uid);
      final snapshot = await document.get();
      await document.set({
        'email': email,
        'displayName': displayName,
        'photoUrl': photoUrl,
        'provider': provider,
        'role': ?role,
        'lastLoginAt': FieldValue.serverTimestamp(),
        if (!snapshot.exists && role == null) ...{
          'role': 'user',
          'createdAt': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));
    } catch (e) {
      // Firestore sync is best-effort only.
      debugPrint('[AuthService] Firestore sync skipped: $e');
    }
  }

  Future<void> _upsertUser(User user, {required String provider}) async {
    return _upsertToFirestore(
      uid: user.uid,
      email: user.email ?? '',
      displayName:
          user.displayName ?? user.email?.split('@').first ?? 'Music listener',
      photoUrl: user.photoURL,
      provider: provider,
    );
  }
}
