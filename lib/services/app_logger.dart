import 'package:flutter/foundation.dart';

/// Centralized logger that only outputs in debug mode.
/// Prevents leaking sensitive information in production builds.
class AppLogger {
  AppLogger._();

  /// Log a debug-level message. Only prints in debug mode.
  static void debug(String message) {
    if (kDebugMode) {
      debugPrint('[DEBUG] $message');
    }
  }

  /// Log an informational message. Only prints in debug mode.
  static void info(String message) {
    if (kDebugMode) {
      debugPrint('[INFO] $message');
    }
  }

  /// Log a warning. Only prints in debug mode.
  static void warning(String message) {
    if (kDebugMode) {
      debugPrint('[WARN] $message');
    }
  }

  /// Log an error with optional stack trace. Only prints in debug mode.
  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    if (kDebugMode) {
      debugPrint('[ERROR] $message');
      if (error != null) debugPrint('  Exception: $error');
      if (stackTrace != null) debugPrint('  StackTrace: $stackTrace');
    }
  }
}
