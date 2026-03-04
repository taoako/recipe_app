import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:final_proj/firebase_options.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'onboarding.dart';
import 'auth/login.dart';
import 'main_page.dart';
import 'services/google_auth_service.dart';
import 'views/upload_page.dart';
import 'views/notification_page.dart';
import 'views/profile_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables before any service initialization
  await dotenv.load(fileName: '.env');

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await GoogleAuthService.initialize();

  // On web, Firestore uses IndexedDB persistence automatically.
  // Only set persistenceEnabled on non-web platforms.
  if (!kIsWeb) {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      sslEnabled: true,
    );
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "Cooking App",
      theme: ThemeData(primarySwatch: Colors.deepOrange),
      home: const OnboardingScreen(),
      routes: {
        '/login': (context) => const LoginScreen(),
        '/home': (context) => const MainPage(),
        '/upload': (context) => const UploadPage(),
        '/notification': (context) => const NotificationPage(),
        '/profile': (context) => ProfilePage(),
      },
    );
  }
}
