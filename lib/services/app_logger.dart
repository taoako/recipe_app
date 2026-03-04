import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Log level constants
class LogLevel {
  static const String info = 'info';
  static const String warning = 'warning';
  static const String error = 'error';
}

/// Log event type constants — used for filtering in the admin logs viewer.
class LogEvent {
  static const String loginAttempt = 'login_attempt';
  static const String loginSuccess = 'login_success';
  static const String loginFailure = 'login_failure';
  static const String loginBlocked = 'login_blocked';
  static const String signupSuccess = 'signup_success';
  static const String signupFailure = 'signup_failure';
  static const String logout = 'logout';
  static const String passwordReset = 'password_reset';
  static const String accessViolation = 'access_violation';
  static const String adminAction = 'admin_action';
  static const String userAction = 'user_action';
  static const String recipeAction = 'recipe_action';
  static const String systemError = 'system_error';
  static const String imageUpload = 'image_upload';
}

class AppLogger {
  AppLogger._();

  static final _db = FirebaseFirestore.instance;

  // ─── Public API ──────────────────────────────────────────────────────────

  static void debug(String message) {
    if (kDebugMode) debugPrint('[DEBUG] $message');
  }

  static void info(String message) {
    if (kDebugMode) debugPrint('[INFO] $message');
  }

  static void warning(String message) {
    if (kDebugMode) debugPrint('[WARN] $message');
  }

  static void error(String message, [Object? err, StackTrace? stackTrace]) {
    if (kDebugMode) {
      debugPrint('[ERROR] $message');
      if (err != null) debugPrint('  Exception: $err');
      if (stackTrace != null) debugPrint('  StackTrace: $stackTrace');
    }
  }

  /// Persist a structured log entry to Firestore `app_logs` collection.
  ///
  /// [level]    – LogLevel.info / warning / error
  /// [event]    – LogEvent constant (e.g. LogEvent.loginSuccess)
  /// [message]  – Human-readable, no technical stack traces
  /// [userId]   – UID of the acting user (defaults to current user)
  /// [metadata] – Optional safe extra fields (NO passwords, NO tokens)
  static Future<void> persist(
    String level,
    String event,
    String message, {
    String? userId,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final uid =
          userId ?? FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';

      final entry = <String, dynamic>{
        'level': level,
        'event': event,
        'message': message,
        'userId': uid,
        'timestamp': FieldValue.serverTimestamp(),
      };

      if (metadata != null && metadata.isNotEmpty) {
        // Strip any accidental sensitive keys before storing
        final safe = Map<String, dynamic>.from(metadata)
          ..remove('password')
          ..remove('token')
          ..remove('secret')
          ..remove('oobCode')
          ..remove('apiKey');
        if (safe.isNotEmpty) entry['metadata'] = safe;
      }

      await _db.collection('app_logs').add(entry);

      if (kDebugMode) {
        debugPrint('[LOG:$level] [$event] $message');
      }
    } catch (e) {
      // Never crash the app because of logging
      if (kDebugMode) debugPrint('[LOG WRITE FAILED] $e');
    }
  }

  // ─── Convenience helpers ─────────────────────────────────────────────────

  static Future<void> logInfo(
    String event,
    String message, {
    String? userId,
    Map<String, dynamic>? metadata,
  }) => persist(
    LogLevel.info,
    event,
    message,
    userId: userId,
    metadata: metadata,
  );

  static Future<void> logWarning(
    String event,
    String message, {
    String? userId,
    Map<String, dynamic>? metadata,
  }) => persist(
    LogLevel.warning,
    event,
    message,
    userId: userId,
    metadata: metadata,
  );

  static Future<void> logError(
    String event,
    String message, {
    String? userId,
    Map<String, dynamic>? metadata,
  }) => persist(
    LogLevel.error,
    event,
    message,
    userId: userId,
    metadata: metadata,
  );
}
