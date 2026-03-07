import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otp/otp.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'app_logger.dart';

/// Centralized security service for account lockout, brute-force detection,
/// 2FA verification, admin re-authentication, and CAPTCHA.
class SecurityService {
  SecurityService._();

  static final _db = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  // ΓöÇΓöÇ Account lockout constants ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ
  static const int maxLoginAttempts = 5;
  static const Duration lockoutDuration = Duration(minutes: 15);
  static const Duration bruteForceWindow = Duration(minutes: 10);

  // ΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉ
  // ACCOUNT LOCKOUT
  // ΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉ

  /// Check if account is locked. Returns remaining lockout duration or null.
  static Future<Duration?> checkAccountLockout(String email) async {
    try {
      final normalizedEmail = email.trim().toLowerCase();
      final doc = await _db
          .collection('login_attempts')
          .doc(normalizedEmail)
          .get();

      if (!doc.exists) return null;

      final data = doc.data()!;
      final attempts = data['failedAttempts'] as int? ?? 0;
      final lockedUntil = data['lockedUntil'] as Timestamp?;

      if (lockedUntil != null) {
        final lockEnd = lockedUntil.toDate();
        if (DateTime.now().isBefore(lockEnd)) {
          return lockEnd.difference(DateTime.now());
        } else {
          // Lock expired ΓÇö reset
          await _db.collection('login_attempts').doc(normalizedEmail).update({
            'failedAttempts': 0,
            'lockedUntil': null,
          });
          return null;
        }
      }

      if (attempts >= maxLoginAttempts) {
        // Should have been locked, lock now
        final lockEnd = DateTime.now().add(lockoutDuration);
        await _db.collection('login_attempts').doc(normalizedEmail).update({
          'lockedUntil': Timestamp.fromDate(lockEnd),
        });

        // Log brute force detection
        unawaited(
          AppLogger.logWarning(
            LogEvent.bruteForceDetected,
            'Brute force attack detected ΓÇö account locked: $normalizedEmail',
            metadata: {
              'email': normalizedEmail,
              'failedAttempts': attempts,
              'lockedUntilMinutes': lockoutDuration.inMinutes,
            },
          ),
        );

        // Auto-create incident
        unawaited(_createBruteForceIncident(normalizedEmail, attempts));

        return lockoutDuration;
      }

      return null;
    } catch (e) {
      // Firestore permission denied or network error ΓÇö skip lockout check
      return null;
    }
  }

  /// Record a failed login attempt for the given email.
  static Future<int> recordFailedAttempt(String email) async {
    try {
      final normalizedEmail = email.trim().toLowerCase();
      final docRef = _db.collection('login_attempts').doc(normalizedEmail);
      final doc = await docRef.get();

      int currentAttempts = 0;
      if (doc.exists) {
        final data = doc.data()!;
        currentAttempts = data['failedAttempts'] as int? ?? 0;

        // Check if attempts are within the brute force window
        final lastAttempt = data['lastAttemptAt'] as Timestamp?;
        if (lastAttempt != null) {
          final elapsed = DateTime.now().difference(lastAttempt.toDate());
          if (elapsed > bruteForceWindow) {
            // Window expired, reset counter
            currentAttempts = 0;
          }
        }
      }

      currentAttempts++;

      await docRef.set({
        'email': normalizedEmail,
        'failedAttempts': currentAttempts,
        'lastAttemptAt': FieldValue.serverTimestamp(),
        if (currentAttempts >= maxLoginAttempts)
          'lockedUntil': Timestamp.fromDate(
            DateTime.now().add(lockoutDuration),
          ),
      }, SetOptions(merge: true));

      // Log the failed attempt
      unawaited(
        AppLogger.logWarning(
          LogEvent.loginFailure,
          'Failed login attempt ($currentAttempts/$maxLoginAttempts)',
          metadata: {
            'email': normalizedEmail,
            'attemptNumber': currentAttempts,
            'maxAttempts': maxLoginAttempts,
          },
        ),
      );

      if (currentAttempts >= maxLoginAttempts) {
        unawaited(
          AppLogger.logWarning(
            LogEvent.bruteForceDetected,
            'Brute force detected ΓÇö too many failed attempts',
            metadata: {
              'email': normalizedEmail,
              'lockedForMinutes': lockoutDuration.inMinutes,
            },
          ),
        );
        unawaited(
          AppLogger.logError(
            LogEvent.accountLocked,
            'Account locked after $currentAttempts consecutive failed login attempts',
            metadata: {
              'email': normalizedEmail,
              'failedAttempts': currentAttempts,
              'lockedForMinutes': lockoutDuration.inMinutes,
            },
          ),
        );
        unawaited(_createBruteForceIncident(normalizedEmail, currentAttempts));
      }

      return currentAttempts;
    } catch (e) {
      // Firestore permission denied ΓÇö can't track attempts
      return 0;
    }
  }

  /// Reset failed attempts after successful login.
  static Future<void> resetFailedAttempts(String email) async {
    try {
      final normalizedEmail = email.trim().toLowerCase();
      await _db.collection('login_attempts').doc(normalizedEmail).set({
        'email': normalizedEmail,
        'failedAttempts': 0,
        'lockedUntil': null,
        'lastSuccessAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Silently fail ΓÇö don't crash for logging
    }
  }

  /// Auto-create a security incident for brute force detection.
  static Future<void> _createBruteForceIncident(
    String email,
    int attempts,
  ) async {
    try {
      await _db.collection('incidents').add({
        'title': 'Brute Force Attack Detected',
        'description':
            'Multiple failed login attempts detected for account: $email. '
            '$attempts failed attempts were recorded within '
            '${bruteForceWindow.inMinutes} minutes. The account has been '
            'temporarily locked for ${lockoutDuration.inMinutes} minutes.',
        'affectedSystem': 'Authentication',
        'severity': attempts >= 10 ? 'critical' : 'high',
        'phase': 'detection',
        'status': 'open',
        'createdBy': 'system',
        'createdByName': 'Security System',
        'detectedAt': FieldValue.serverTimestamp(),
        'resolvedAt': null,
        'autoGenerated': true,
        'metadata': {
          'email': email,
          'failedAttempts': attempts,
          'lockoutMinutes': lockoutDuration.inMinutes,
        },
      });
    } catch (e) {
      // Silently fail ΓÇö don't crash the app for logging
    }
  }

  // ΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉ
  // 2FA ΓÇö TOTP (Authenticator App: Google Authenticator, Microsoft Authenticator)
  // ΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉ

  static const String _totpIssuer = 'INGRNTS';

  /// Generate a random TOTP secret (base32-encoded, 32 characters).
  static String _generateTOTPSecret() {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    final rng = Random.secure();
    return List.generate(
      32,
      (_) => alphabet[rng.nextInt(alphabet.length)],
    ).join();
  }

  /// Build the otpauth:// URI for QR code scanning.
  static String _buildTOTPUri(String secret, String email) {
    final issuer = Uri.encodeComponent(_totpIssuer);
    final account = Uri.encodeComponent(email);
    return 'otpauth://totp/$issuer:$account'
        '?secret=$secret&issuer=$issuer&algorithm=SHA1&digits=6&period=30';
  }

  /// Verify a TOTP code against a secret. Allows ┬▒1 time-step (30 s) drift.
  static bool _verifyTOTP(String secret, String code) {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (int i = -1; i <= 1; i++) {
      final generated = OTP.generateTOTPCodeString(
        secret,
        now + (i * 30000),
        algorithm: Algorithm.SHA1,
        isGoogle: true,
      );
      if (generated == code.trim()) return true;
    }
    return false;
  }

  /// Create a new TOTP secret for a user and store it in Firestore.
  /// Returns the base32-encoded secret.
  static Future<String> setupTOTP(String userId) async {
    final secret = _generateTOTPSecret();
    await _db.collection('2fa_codes').doc(userId).set({
      'totpSecret': secret,
      'setupAt': FieldValue.serverTimestamp(),
      'verified': false,
    });
    return secret;
  }

  /// Get the stored TOTP secret for a user, or null if not set up.
  static Future<String?> getTOTPSecret(String userId) async {
    final doc = await _db.collection('2fa_codes').doc(userId).get();
    if (!doc.exists) return null;
    return doc.data()?['totpSecret'] as String?;
  }

  /// Confirm TOTP setup by verifying the first code from authenticator.
  static Future<bool> confirmTOTPSetup(String userId, String code) async {
    final secret = await getTOTPSecret(userId);
    if (secret == null) return false;

    if (_verifyTOTP(secret, code)) {
      await _db.collection('2fa_codes').doc(userId).update({'verified': true});
      await _db.collection('users').doc(userId).update({
        'twoFactorEnabled': true,
      });

      unawaited(
        AppLogger.logInfo(
          LogEvent.twoFactorSuccess,
          'TOTP setup completed ΓÇö authenticator app linked',
          userId: userId,
        ),
      );
      return true;
    }
    return false;
  }

  /// Disable TOTP 2FA for a user ΓÇö removes the secret and the flag.
  static Future<void> disableTOTP(String userId) async {
    await _db.collection('2fa_codes').doc(userId).delete();
    await _db.collection('users').doc(userId).update({
      'twoFactorEnabled': false,
    });

    unawaited(
      AppLogger.logInfo(
        LogEvent.settingsChange,
        '2FA disabled by user ΓÇö authenticator unlinked',
        userId: userId,
      ),
    );
  }

  // ΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉ
  // ADMIN RE-AUTHENTICATION
  // ΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉ

  /// Re-authenticate the current admin by verifying their password.
  /// Returns true if successful.
  static Future<bool> reAuthenticateAdmin(String password) async {
    try {
      final user = _auth.currentUser;
      if (user == null || user.email == null) return false;

      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: password,
      );

      await user.reauthenticateWithCredential(credential);

      unawaited(
        AppLogger.logInfo(
          LogEvent.adminAction,
          'Admin re-authentication successful',
          userId: user.uid,
        ),
      );

      return true;
    } on FirebaseAuthException {
      unawaited(
        AppLogger.logWarning(
          LogEvent.accessViolation,
          'Admin re-authentication failed',
          userId: _auth.currentUser?.uid,
        ),
      );
      return false;
    }
  }

  // ΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉ
  // CAPTCHA (Google reCAPTCHA v2 via WebView on mobile, fallback on desktop)
  // ΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉ

  /// reCAPTCHA v2 site key ΓÇö replace with your own from
  /// https://www.google.com/recaptcha/admin for production.
  /// The key below is Google's public TEST key (always passes).
  static const String _recaptchaSiteKey =
      '6LeIxAcTAAAAAJcZVRqyHh71UMIEGNQ_MXjiZKhI';

  /// Whether the current platform supports WebView (Android / iOS).
  static bool get _supportsWebView {
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  /// HTML page that hosts the reCAPTCHA v2 "I'm not a robot" widget.
  static String get _recaptchaHtml =>
      '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <script src="https://www.google.com/recaptcha/api.js" async defer></script>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      display: flex; justify-content: center; align-items: center;
      min-height: 100vh; background: #fafafa; font-family: sans-serif;
    }
    .wrapper { text-align: center; }
    .g-recaptcha { display: inline-block; }
    .msg { margin-top: 16px; font-size: 14px; color: #4caf50; display: none; }
  </style>
</head>
<body>
  <div class="wrapper">
    <div class="g-recaptcha"
         data-sitekey="$_recaptchaSiteKey"
         data-callback="onSuccess"></div>
    <p class="msg" id="msg">&#10003; Verified! ClosingΓÇª</p>
  </div>
  <script>
    function onSuccess(token) {
      document.getElementById('msg').style.display = 'block';
      if (window.RecaptchaFlutter) {
        RecaptchaFlutter.postMessage(token);
      }
    }
  </script>
</body>
</html>
''';

  // ΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉ
  // FIRST LOGIN DETECTION
  // ΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉ

  /// Check if this is the user's first login (no previous successful login).
  static Future<bool> isFirstLogin(String userId) async {
    final doc = await _db.collection('users').doc(userId).get();
    if (!doc.exists) return true;
    final data = doc.data()!;
    return data['hasLoggedInBefore'] != true;
  }

  /// Mark user as having completed first login successfully.
  static Future<void> markFirstLoginComplete(String userId) async {
    await _db.collection('users').doc(userId).update({
      'hasLoggedInBefore': true,
      'firstLoginAt': FieldValue.serverTimestamp(),
    });
  }

  // ΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉ
  // PASSWORD POLICY VALIDATION
  // ΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉ

  /// Returns a map of each password requirement and whether it's met.
  static Map<String, bool> checkPasswordRequirements(String password) {
    return {
      'At least 8 characters': password.length >= 8,
      'At least one uppercase letter (A-Z)': RegExp(
        r'[A-Z]',
      ).hasMatch(password),
      'At least one lowercase letter (a-z)': RegExp(
        r'[a-z]',
      ).hasMatch(password),
      'At least one number (0-9)': RegExp(r'[0-9]').hasMatch(password),
      'At least one special character (!@#\$%^&*)': RegExp(
        r'[!@#$%^&*(),.?":{}|<>]',
      ).hasMatch(password),
    };
  }

  /// Returns true if all password requirements are met.
  static bool isPasswordStrong(String password) {
    return checkPasswordRequirements(password).values.every((v) => v);
  }

  // ΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉ
  // UI HELPERS ΓÇö Dialogs
  // ΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉ

  /// Show the 2FA dialog. If TOTP is already set up AND verified ΓåÆ verify.
  /// If TOTP is NOT set up or was never verified ΓåÆ show the setup flow (QR code).
  /// Returns true if the user passes 2FA.
  static Future<bool> show2FADialog(
    BuildContext context,
    String userId,
    String email,
  ) async {
    final doc = await _db.collection('2fa_codes').doc(userId).get();
    final data = doc.exists ? doc.data() : null;
    final secret = data?['totpSecret'] as String?;
    final verified = data?['verified'] == true;

    if (secret == null || secret.isEmpty || !verified) {
      // No TOTP set up, or previous setup was never completed ΓÇö run setup flow
      if (!context.mounted) return false;
      return _show2FASetupDialog(context, userId, email);
    }

    // TOTP exists and was verified ΓÇö just ask for a code
    if (!context.mounted) return false;
    return _show2FAVerifyDialog(context, userId, secret);
  }

  // ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ
  // TOTP SETUP DIALOG ΓÇö QR code + manual key + first-code verification
  // ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ

  static Future<bool> _show2FASetupDialog(
    BuildContext context,
    String userId,
    String email,
  ) async {
    final secret = await setupTOTP(userId);
    final uri = _buildTOTPUri(secret, email);
    final codeController = TextEditingController();
    String? error;
    bool isVerifying = false;
    bool secretVisible = false;

    if (!context.mounted) return false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Title
                    const Row(
                      children: [
                        Icon(Icons.qr_code_2, color: Colors.deepOrange),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Set Up Authenticator',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 17,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Instructions
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.blue,
                            size: 18,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Scan the QR code below with Google Authenticator '
                              'or Microsoft Authenticator, then enter the '
                              '6-digit code to complete setup.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // QR Code
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: QrImageView(
                        data: uri,
                        version: QrVersions.auto,
                        size: 200,
                        backgroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Manual key toggle
                    GestureDetector(
                      onTap: () => setS(() => secretVisible = !secretVisible),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            secretVisible
                                ? Icons.visibility_off
                                : Icons.visibility,
                            size: 14,
                            color: Colors.deepOrange,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            secretVisible
                                ? 'Hide manual key'
                                : 'Can\'t scan? Show manual key',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.deepOrange,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (secretVisible) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                secret,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'monospace',
                                  letterSpacing: 2,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy, size: 18),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: secret));
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(
                                    content: Text('Key copied to clipboard'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),

                    // Code input
                    TextField(
                      controller: codeController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 8,
                      ),
                      decoration: InputDecoration(
                        hintText: '000000',
                        counterText: '',
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        error!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ],
                    const SizedBox(height: 16),

                    // Actions
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () async {
                            await _db
                                .collection('2fa_codes')
                                .doc(userId)
                                .delete();
                            if (ctx.mounted) Navigator.pop(ctx, false);
                          },
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: isVerifying
                              ? null
                              : () async {
                                  final code = codeController.text.trim();
                                  if (code.length != 6) {
                                    setS(
                                      () => error = 'Enter the 6-digit code.',
                                    );
                                    return;
                                  }

                                  setS(() {
                                    isVerifying = true;
                                    error = null;
                                  });

                                  final verified = await confirmTOTPSetup(
                                    userId,
                                    code,
                                  );

                                  if (verified) {
                                    if (ctx.mounted) {
                                      Navigator.pop(ctx, true);
                                    }
                                  } else {
                                    setS(() {
                                      isVerifying = false;
                                      error =
                                          'Invalid code. Make sure you '
                                          'scanned the QR code and '
                                          'try again.';
                                    });
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepOrange,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: isVerifying
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Verify & Enable'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    codeController.dispose();
    return result ?? false;
  }

  // ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ
  // TOTP VERIFY DIALOG ΓÇö simple code input for returning users
  // ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ

  static Future<bool> _show2FAVerifyDialog(
    BuildContext context,
    String userId,
    String secret,
  ) async {
    if (!context.mounted) return false;

    final result = await Navigator.of(context, rootNavigator: true).push<bool>(
      PageRouteBuilder<bool>(
        settings: const RouteSettings(name: '/two-factor-verify'),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, __, ___) => _TwoFactorVerifyPage(
          userId: userId,
          secret: secret,
        ),
      ),
    );

    return result ?? false;
  }

  /// Show admin re-authentication dialog. Returns true if password is correct.
  static Future<bool> showReAuthDialog(BuildContext context) async {
    final passwordController = TextEditingController();
    String? error;
    bool isVerifying = false;
    bool obscure = true;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.deepOrange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.shield,
                          color: Colors.deepOrange,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Admin Verification',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              'Enter your password to continue',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.shade200),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.amber, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'This action requires admin verification for security purposes.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passwordController,
                    obscureText: obscure,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscure ? Icons.visibility_off : Icons.visibility,
                          size: 20,
                        ),
                        onPressed: () => setS(() => obscure = !obscure),
                      ),
                      hintText: 'Enter your password',
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      error!,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: isVerifying
                            ? null
                            : () async {
                                if (passwordController.text.isEmpty) {
                                  setS(() => error = 'Password is required');
                                  return;
                                }

                                setS(() {
                                  isVerifying = true;
                                  error = null;
                                });

                                final success = await reAuthenticateAdmin(
                                  passwordController.text,
                                );

                                if (success) {
                                  if (ctx.mounted) {
                                    Navigator.pop(ctx, true);
                                  }
                                } else {
                                  setS(() {
                                    isVerifying = false;
                                    error =
                                        'Incorrect password. Please try again.';
                                  });
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepOrange,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: isVerifying
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Verify'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    passwordController.dispose();
    return result ?? false;
  }

  /// Show CAPTCHA verification.
  /// On Android / iOS ΓåÆ opens a full-screen reCAPTCHA v2 WebView page.
  /// On desktop / unsupported ΓåÆ shows a simple math challenge dialog.
  static Future<bool> showCaptchaDialog(BuildContext context) async {
    if (_supportsWebView) {
      final passed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => const _RecaptchaPage()),
      );
      return passed ?? false;
    } else {
      // Fallback for desktop / web
      return _showMathCaptchaDialog(context);
    }
  }

  /// Fallback math CAPTCHA for platforms without WebView support.
  static Future<bool> _showMathCaptchaDialog(BuildContext context) async {
    final rng = Random.secure();
    int a = rng.nextInt(20) + 1;
    int b = rng.nextInt(20) + 1;
    final ops = ['+', '-', '├ù'];
    String op = ops[rng.nextInt(ops.length)];
    int answer = _mathAnswer(a, b, op);

    final controller = TextEditingController();
    String? error;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.smart_toy_outlined, color: Colors.deepOrange),
                      SizedBox(width: 10),
                      Text(
                        'Security Check',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Solve to verify you\'re not a bot.',
                    style: TextStyle(fontSize: 13, color: Colors.black54),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFA726), Color(0xFFFF7043)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: Text(
                        'What is $a $op $b?',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    keyboardType: const TextInputType.numberWithOptions(
                      signed: true,
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Your answer',
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      error!,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () {
                      setS(() {
                        a = rng.nextInt(20) + 1;
                        b = rng.nextInt(20) + 1;
                        op = ops[rng.nextInt(ops.length)];
                        answer = _mathAnswer(a, b, op);
                        controller.clear();
                        error = null;
                      });
                    },
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text(
                      'New challenge',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          final parsed = int.tryParse(controller.text.trim());
                          if (parsed == null) {
                            setS(() => error = 'Please enter a valid number');
                            return;
                          }
                          if (parsed == answer) {
                            Navigator.pop(ctx, true);
                          } else {
                            setS(() {
                              error = 'Incorrect. Try again!';
                              a = rng.nextInt(20) + 1;
                              b = rng.nextInt(20) + 1;
                              op = ops[rng.nextInt(ops.length)];
                              answer = _mathAnswer(a, b, op);
                              controller.clear();
                            });
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepOrange,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Submit'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    controller.dispose();
    return result ?? false;
  }

  static int _mathAnswer(int a, int b, String op) {
    switch (op) {
      case '+':
        return a + b;
      case '-':
        return a - b;
      case '├ù':
        return a * b;
      default:
        return a + b;
    }
  }
}

class _TwoFactorVerifyPage extends StatefulWidget {
  const _TwoFactorVerifyPage({required this.userId, required this.secret});

  final String userId;
  final String secret;

  @override
  State<_TwoFactorVerifyPage> createState() => _TwoFactorVerifyPageState();
}

class _TwoFactorVerifyPageState extends State<_TwoFactorVerifyPage> {
  late final TextEditingController _codeController;
  late final FocusNode _otpFocusNode;

  String? _error;
  bool _isVerifying = false;
  bool _didComplete = false;

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController();
    _otpFocusNode = FocusNode();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        FocusScope.of(context).requestFocus(_otpFocusNode);
      }
    });
  }

  @override
  void dispose() {
    _codeController.dispose();
    _otpFocusNode.dispose();
    super.dispose();
  }

  Future<void> _handleVerify() async {
    if (_isVerifying || _didComplete) return;

    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code.');
      return;
    }

    setState(() {
      _isVerifying = true;
      _error = null;
    });

    final valid = SecurityService._verifyTOTP(widget.secret, code);
    if (!mounted || _didComplete) return;

    if (valid) {
      _didComplete = true;
      unawaited(
        AppLogger.logInfo(
          LogEvent.twoFactorSuccess,
          '2FA TOTP verification successful',
          userId: widget.userId,
        ),
      );
      Navigator.of(context).pop(true);
      return;
    }

    unawaited(
      AppLogger.logWarning(
        LogEvent.twoFactorFailure,
        '2FA TOTP verification failed - invalid code',
        userId: widget.userId,
      ),
    );

    setState(() {
      _isVerifying = false;
      _error = 'Invalid code. Check your authenticator app and try again.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.25),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                elevation: 12,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.security, color: Colors.deepOrange),
                          SizedBox(width: 10),
                          Text(
                            '2-Step Verification',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 17,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.phone_android, color: Colors.deepOrange),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Open your authenticator app and enter the 6-digit code.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _codeController,
                        focusNode: _otpFocusNode,
                        autofocus: false,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        textAlign: TextAlign.center,
                        onSubmitted: (_) => _handleVerify(),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 8,
                        ),
                        decoration: InputDecoration(
                          hintText: '000000',
                          counterText: '',
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _error!,
                          style: const TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: (_isVerifying || _didComplete)
                                ? null
                                : () {
                                    _didComplete = true;
                                    Navigator.of(context).pop(false);
                                  },
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: (_isVerifying || _didComplete)
                                ? null
                                : _handleVerify,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepOrange,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _isVerifying
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Verify'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉ
// Full-screen reCAPTCHA page (mobile only)
// ΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉ

class _RecaptchaPage extends StatefulWidget {
  const _RecaptchaPage();

  @override
  State<_RecaptchaPage> createState() => _RecaptchaPageState();
}

class _RecaptchaPageState extends State<_RecaptchaPage> {
  late final WebViewController _controller;
  bool _verified = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'RecaptchaFlutter',
        onMessageReceived: (_) {
          setState(() => _verified = true);
          Future.delayed(const Duration(milliseconds: 800), () {
            if (mounted) Navigator.pop(context, true);
          });
        },
      )
      ..loadHtmlString(SecurityService._recaptchaHtml);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Security Check'),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context, false),
        ),
      ),
      body: Column(
        children: [
          if (_verified)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Colors.green.shade50,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle, color: Colors.green),
                  SizedBox(width: 8),
                  Text(
                    'Verified! RedirectingΓÇª',
                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
    );
  }
}
