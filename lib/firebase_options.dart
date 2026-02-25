import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'services/env_config.dart';

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// All sensitive values are loaded from environment variables (.env)
/// rather than being hardcoded in source code.
///
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static FirebaseOptions get web => FirebaseOptions(
    apiKey: EnvConfig.firebaseWebApiKey,
    appId: EnvConfig.firebaseWebAppId,
    messagingSenderId: EnvConfig.firebaseWebMessagingSenderId,
    projectId: EnvConfig.firebaseWebProjectId,
    authDomain: EnvConfig.firebaseWebAuthDomain,
    storageBucket: EnvConfig.firebaseWebStorageBucket,
    measurementId: EnvConfig.firebaseWebMeasurementId,
  );

  static FirebaseOptions get android => FirebaseOptions(
    apiKey: EnvConfig.firebaseAndroidApiKey,
    appId: EnvConfig.firebaseAndroidAppId,
    messagingSenderId: EnvConfig.firebaseAndroidMessagingSenderId,
    projectId: EnvConfig.firebaseAndroidProjectId,
    storageBucket: EnvConfig.firebaseAndroidStorageBucket,
  );

  static FirebaseOptions get ios => FirebaseOptions(
    apiKey: EnvConfig.firebaseIosApiKey,
    appId: EnvConfig.firebaseIosAppId,
    messagingSenderId: EnvConfig.firebaseIosMessagingSenderId,
    projectId: EnvConfig.firebaseIosProjectId,
    storageBucket: EnvConfig.firebaseIosStorageBucket,
    iosBundleId: EnvConfig.firebaseIosBundleId,
  );

  static FirebaseOptions get macos => FirebaseOptions(
    apiKey: EnvConfig.firebaseIosApiKey,
    appId: EnvConfig.firebaseIosAppId,
    messagingSenderId: EnvConfig.firebaseIosMessagingSenderId,
    projectId: EnvConfig.firebaseIosProjectId,
    storageBucket: EnvConfig.firebaseIosStorageBucket,
    iosBundleId: EnvConfig.firebaseIosBundleId,
  );

  static FirebaseOptions get windows => FirebaseOptions(
    apiKey: EnvConfig.firebaseWindowsApiKey,
    appId: EnvConfig.firebaseWindowsAppId,
    messagingSenderId: EnvConfig.firebaseWindowsMessagingSenderId,
    projectId: EnvConfig.firebaseWindowsProjectId,
    authDomain: EnvConfig.firebaseWindowsAuthDomain,
    storageBucket: EnvConfig.firebaseWindowsStorageBucket,
    measurementId: EnvConfig.firebaseWindowsMeasurementId,
  );
}
