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
  String toString() => 'LocalUser(id: $id, email: $email, name: $displayName, role: $role)';
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

  void _initAuthListener() {
    if (_listenerStarted) return;
    _listenerStarted = true;

    // Check local database for active session
    LocalDatabase.instance.getActiveSessionUserId().then((savedUserId) async {
      if (savedUserId != null) {
        final localData = await LocalDatabase.instance.getUserById(savedUserId);
        if (localData != null) {
          // Restore the saved session, but resolve the role from the
          // employees table (employees.user_id == users.id). Editing the
          // employee row in the database is the only way to grant admin.
          final resolvedRole = await LocalDatabase.instance
              .refreshUserRoleFromEmployees(savedUserId);
          _currentUser = LocalUser(
            id: localData['id'] as String,
            email: (localData['email'] as String? ?? '').trim(),
            displayName:
                (localData['display_name'] as String? ?? '').trim(),
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



  Future<void> register({
    String? name,
    required String email,
    required String password,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final cleanName = (name != null && name.trim().isNotEmpty)
        ? name.trim()
        : cleanEmail.split('@').first;
    const provider = 'password';
    final auth = _auth;

    await LocalDatabase.instance.removeDefaultAdminIfSeeded();

    final existingLocal = await LocalDatabase.instance.getUserByEmail(cleanEmail);
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
        // Keep users.role in sync with employees.user_id == users.id.
        await LocalDatabase.instance.refreshUserRoleFromEmployees(fbUser.uid);
        return;
      } on FirebaseAuthException catch (e) {
        if (e.code == 'email-already-in-use' ||
            e.code == 'invalid-email' ||
            e.code == 'weak-password') {
          rethrow;
        }
        final isConfigError = e.code == 'configuration-not-found' ||
            e.code == 'operation-not-allowed' ||
            (e.message != null && e.message!.contains('CONFIGURATION_NOT_FOUND'));
        if (!isConfigError) {
          rethrow;
        }
        debugPrint('[AuthService] Firebase config error, using local registration: $e');
      } catch (e) {
        debugPrint('[AuthService] Firebase registration error, using local registration: $e');
      }
    }

    final newUserId = await LocalDatabase.instance.getNextUserId();
    await LocalDatabase.instance.saveUser(
      id: newUserId,
      email: cleanEmail,
      displayName: cleanName,
      role: 'user',
      authProvider: provider,
      passwordHash: passwordHash,
    );
    await LocalDatabase.instance.saveActiveSession(newUserId);
    await LocalDatabase.instance.claimAnonymousPlaylists(newUserId);
    final user = await LocalDatabase.instance.getUserById(newUserId);
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
        // Keep users.role in sync with employees.user_id == users.id.
        await LocalDatabase.instance.refreshUserRoleFromEmployees(fbUser.uid);
      } catch (e) {
        debugPrint('[AuthService] Local mirror skipped: $e');
      }
    } on FirebaseAuthException catch (e) {
      // Firebase rejected the credentials authoritatively (wrong-password,
      // invalid-credential, user-disabled). These are NOT config errors —
      // the user's password was changed remotely, or the account was
      // disabled. Do NOT fall back to a potentially stale local hash.
      final isCredentialError = e.code == 'wrong-password' ||
          e.code == 'invalid-credential' ||
          e.code == 'user-disabled' ||
          e.code == 'user-not-found';
      if (isCredentialError) {
        // If the account was registered locally (e.g., when Firebase was unavailable),
        // we should try to verify their password against the local database.
        final verified = await LocalDatabase.instance.verifyLocalPassword(cleanEmail, password);
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

      final isConfigError = e.code == 'configuration-not-found' ||
          e.code == 'operation-not-allowed' ||
          (e.message != null && e.message!.contains('CONFIGURATION_NOT_FOUND'));

      // Only fall back to local password when Firebase is *unavailable*
      // (config error), not when it *rejected* the credentials.
      if (isConfigError) {
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
      rethrow;
    } catch (e) {
      // Non-Firebase error (network, platform): fall back to local only
      // for config/availability failures, same logic as above.
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
        if (role != null) 'role': role,
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
      displayName: user.displayName ?? user.email?.split('@').first ?? 'Music listener',
      photoUrl: user.photoURL,
      provider: provider,
    );
  }
}
