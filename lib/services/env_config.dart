import 'package:flutter_dotenv/flutter_dotenv.dart';

class EnvConfig {
  EnvConfig._();

  /// Reads a required env variable. Throws [StateError] if missing.
  static String _require(String key) {
    final value = dotenv.env[key];
    if (value == null || value.isEmpty) {
      throw StateError('Missing required environment variable: $key');
    }
    return value;
  }

  /// Reads an optional env variable, returning [fallback] when absent.
  static String _optional(String key, [String fallback = '']) {
    return dotenv.env[key] ?? fallback;
  }

  // ── Firebase Web ──────────────────────────────────────────────
  static String get firebaseWebApiKey => _require('FIREBASE_WEB_API_KEY');
  static String get firebaseWebAppId => _require('FIREBASE_WEB_APP_ID');
  static String get firebaseWebMessagingSenderId =>
      _require('FIREBASE_WEB_MESSAGING_SENDER_ID');
  static String get firebaseWebProjectId => _require('FIREBASE_WEB_PROJECT_ID');
  static String get firebaseWebAuthDomain =>
      _require('FIREBASE_WEB_AUTH_DOMAIN');
  static String get firebaseWebStorageBucket =>
      _require('FIREBASE_WEB_STORAGE_BUCKET');
  static String get firebaseWebMeasurementId =>
      _optional('FIREBASE_WEB_MEASUREMENT_ID');

  // ── Firebase Android ──────────────────────────────────────────
  static String get firebaseAndroidApiKey =>
      _require('FIREBASE_ANDROID_API_KEY');
  static String get firebaseAndroidAppId => _require('FIREBASE_ANDROID_APP_ID');
  static String get firebaseAndroidMessagingSenderId =>
      _require('FIREBASE_ANDROID_MESSAGING_SENDER_ID');
  static String get firebaseAndroidProjectId =>
      _require('FIREBASE_ANDROID_PROJECT_ID');
  static String get firebaseAndroidStorageBucket =>
      _require('FIREBASE_ANDROID_STORAGE_BUCKET');

  // ── Firebase iOS / macOS ──────────────────────────────────────
  static String get firebaseIosApiKey => _require('FIREBASE_IOS_API_KEY');
  static String get firebaseIosAppId => _require('FIREBASE_IOS_APP_ID');
  static String get firebaseIosMessagingSenderId =>
      _require('FIREBASE_IOS_MESSAGING_SENDER_ID');
  static String get firebaseIosProjectId => _require('FIREBASE_IOS_PROJECT_ID');
  static String get firebaseIosStorageBucket =>
      _require('FIREBASE_IOS_STORAGE_BUCKET');
  static String get firebaseIosBundleId => _require('FIREBASE_IOS_BUNDLE_ID');

  // ── Firebase Windows ──────────────────────────────────────────
  static String get firebaseWindowsApiKey =>
      _require('FIREBASE_WINDOWS_API_KEY');
  static String get firebaseWindowsAppId => _require('FIREBASE_WINDOWS_APP_ID');
  static String get firebaseWindowsMessagingSenderId =>
      _require('FIREBASE_WINDOWS_MESSAGING_SENDER_ID');
  static String get firebaseWindowsProjectId =>
      _require('FIREBASE_WINDOWS_PROJECT_ID');
  static String get firebaseWindowsAuthDomain =>
      _require('FIREBASE_WINDOWS_AUTH_DOMAIN');
  static String get firebaseWindowsStorageBucket =>
      _require('FIREBASE_WINDOWS_STORAGE_BUCKET');
  static String get firebaseWindowsMeasurementId =>
      _optional('FIREBASE_WINDOWS_MEASUREMENT_ID');

  // ── Cloudinary ────────────────────────────────────────────────
  static String get cloudinaryCloudName => _require('CLOUDINARY_CLOUD_NAME');
  static String get cloudinaryUploadPreset =>
      _require('CLOUDINARY_UPLOAD_PRESET');
}
