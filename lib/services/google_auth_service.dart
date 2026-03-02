import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'app_logger.dart';

/// Service that handles Google Sign-In authentication with Firebase.
///
/// Used for both login (existing users) and registration (new users).
/// When a new user signs in with Google for the first time, a Firestore
/// user document is automatically created.
class GoogleAuthService {
  GoogleAuthService._();

  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static bool _initialized = false;

  static bool get _isGoogleSignInSupported {
    if (kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  /// Initialize Google sign-in SDK once.
  ///
  /// For web we rely on FirebaseAuth popup flow and do not need plugin init.
  static Future<void> initialize() async {
    if (_initialized) return;
    if (_isGoogleSignInSupported && !kIsWeb) {
      await GoogleSignIn.instance.initialize();
    }
    _initialized = true;
  }

  /// Ensures [GoogleSignIn.instance] is initialised exactly once.
  static Future<void> _ensureInitialized() async {
    await initialize();
  }

  /// Sign in with Google and return the [UserCredential].
  ///
  /// Returns `null` if the user cancels the sign-in flow.
  /// If this is the user's first sign-in, a Firestore user document is created.
  static Future<UserCredential?> signInWithGoogle() async {
    await _ensureInitialized();

    if (!_isGoogleSignInSupported) {
      throw UnsupportedError(
        'Google Sign-In is not supported on this platform.',
      );
    }

    if (kIsWeb) {
      try {
        final provider = GoogleAuthProvider();
        provider.setCustomParameters({'prompt': 'select_account'});
        final userCredential = await _auth.signInWithPopup(provider);

        final user = userCredential.user;
        if (user != null &&
            userCredential.additionalUserInfo?.isNewUser == true) {
          await _createUserDocument(user);
          AppLogger.info('New Google user document created: ${user.uid}');
        }

        return userCredential;
      } on FirebaseAuthException catch (e) {
        if (e.code == 'popup-closed-by-user' ||
            e.code == 'cancelled-popup-request') {
          return null;
        }
        rethrow;
      }
    }

    // Trigger the interactive Google Sign-In flow
    final GoogleSignInAccount googleUser;
    try {
      googleUser = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      // User cancelled or flow was interrupted — not an error
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted) {
        return null;
      }
      rethrow;
    }

    // Obtain the idToken from the Google sign-in
    final GoogleSignInAuthentication googleAuth = googleUser.authentication;

    // Create a Firebase credential using only the idToken
    final OAuthCredential credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
    );

    // Sign in to Firebase with the Google credential
    final UserCredential userCredential = await _auth.signInWithCredential(
      credential,
    );

    // If this is a brand-new user, create their Firestore profile
    final user = userCredential.user;
    if (user != null && userCredential.additionalUserInfo?.isNewUser == true) {
      await _createUserDocument(user);
      AppLogger.info('New Google user document created: ${user.uid}');
    }

    return userCredential;
  }

  /// Creates a Firestore user document for a first-time Google sign-in user.
  static Future<void> _createUserDocument(User user) async {
    final docRef = _db.collection('users').doc(user.uid);

    // Don't overwrite if document already exists (edge case)
    final existing = await docRef.get();
    if (existing.exists) return;

    await docRef.set({
      'username': user.displayName ?? 'User',
      'email': user.email ?? '',
      'profileImageUrl': user.photoURL ?? '',
      'followers': [],
      'following': [],
      'isAdmin': false,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Also set the display name on the Firebase Auth user if missing
    if (user.displayName == null || user.displayName!.isEmpty) {
      await user.updateDisplayName('User');
    }
  }

  /// Signs out from both Google and Firebase.
  static Future<void> signOut() async {
    await _ensureInitialized();
    await GoogleSignIn.instance.signOut();
    await _auth.signOut();
  }
}
