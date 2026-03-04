import 'dart:async' show unawaited;
import 'package:final_proj/auth/forgot_password_page.dart';
import 'package:final_proj/auth/signup.dart';
import 'package:final_proj/auth/email_verification_page.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../main_page.dart';
import '../views/admin_page.dart';
import '../views/moderator_page.dart';
import '../services/google_auth_service.dart';
import '../services/app_logger.dart';
import '../services/input_validator.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  String? _error;

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (!InputValidator.isValidEmail(email)) {
      setState(() => _error = 'Enter a valid email address');
      return;
    }

    final passwordError = InputValidator.validatePassword(password);
    if (passwordError != null) {
      setState(() => _error = passwordError);
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    // Log every login attempt (email masked for privacy)
    unawaited(
      AppLogger.logInfo(
        LogEvent.loginAttempt,
        'Login attempt',
        metadata: {
          'emailDomain': email.contains('@')
              ? email.split('@').last
              : 'unknown',
        },
      ),
    );

    try {
      final userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);

      if (!mounted) return;

      // Block login if email hasn't been verified yet
      if (!userCredential.user!.emailVerified) {
        await FirebaseAuth.instance.signOut();
        // Log access violation — account exists but email unverified
        unawaited(
          AppLogger.logWarning(
            LogEvent.accessViolation,
            'Login blocked: email not verified',
            userId: userCredential.user!.uid,
            metadata: {'reason': 'email_not_verified'},
          ),
        );
        if (!mounted) return;
        setState(
          () => _error =
              'Please verify your email before logging in. '
              'Check your inbox for the verification link.',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Email not verified. Tap to resend.'),
              backgroundColor: Colors.orange,
              action: SnackBarAction(
                label: 'Resend',
                textColor: Colors.white,
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EmailVerificationPage(email: email),
                    ),
                  );
                },
              ),
            ),
          );
        }
        return;
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userCredential.user!.uid)
          .get();

      final userData = userDoc.data();
      final isAdmin = userData?['isAdmin'] ?? false;
      final role = userData?['role']?.toString() ?? 'user';
      final isDisabled = userData?['isDisabled'] == true;

      if (isDisabled) {
        // Log blocked login attempt for disabled account
        unawaited(
          AppLogger.logWarning(
            LogEvent.loginBlocked,
            'Login blocked: account disabled',
            userId: userCredential.user!.uid,
            metadata: {'reason': 'account_disabled', 'method': 'email'},
          ),
        );
        await FirebaseAuth.instance.signOut();
        if (mounted) {
          setState(
            () => _error =
                'This account has been disabled. Please contact support.',
          );
        }
        return;
      }

      // Log successful login
      unawaited(
        AppLogger.logInfo(
          LogEvent.loginSuccess,
          'Login successful',
          userId: userCredential.user!.uid,
          metadata: {'role': role, 'method': 'email'},
        ),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) {
            if (isAdmin || role == 'admin') return const AdminPage();
            if (role == 'moderator') return const ModeratorPage();
            return const MainPage();
          },
        ),
      );
    } on FirebaseAuthException catch (e) {
      // Log login failure (no password, no sensitive info)
      unawaited(
        AppLogger.logWarning(
          LogEvent.loginFailure,
          'Login failed: ${e.code}',
          metadata: {'errorCode': e.code},
        ),
      );
      setState(() {
        switch (e.code) {
          case 'user-not-found':
          case 'wrong-password':
          case 'invalid-credential':
            _error = 'Incorrect email or password. Please try again.';
            break;
          case 'user-disabled':
            _error = 'This account has been disabled. Contact support.';
            break;
          case 'too-many-requests':
            _error = 'Too many failed attempts. Please try again later.';
            break;
          case 'invalid-email':
            _error = 'The email address is not valid.';
            break;
          default:
            _error = e.message ?? 'Login failed. Please try again.';
        }
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loginWithGoogle() async {
    setState(() {
      _isGoogleLoading = true;
      _error = null;
    });

    try {
      final userCredential = await GoogleAuthService.signInWithGoogle();

      // User cancelled the Google sign-in flow
      if (userCredential == null) {
        setState(() => _isGoogleLoading = false);
        return;
      }

      if (!mounted) return;

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userCredential.user!.uid)
          .get();

      final userData = userDoc.data();
      final isAdmin = userData?['isAdmin'] ?? false;
      final role = userData?['role']?.toString() ?? 'user';
      final isDisabled = userData?['isDisabled'] == true;

      if (isDisabled) {
        // Log blocked login attempt for disabled account
        unawaited(
          AppLogger.logWarning(
            LogEvent.loginBlocked,
            'Login blocked: account disabled',
            userId: userCredential.user!.uid,
            metadata: {'reason': 'account_disabled', 'method': 'google'},
          ),
        );
        await FirebaseAuth.instance.signOut();
        if (mounted) {
          setState(
            () => _error =
                'This account has been disabled. Please contact support.',
          );
        }
        return;
      }

      // Log successful Google sign-in
      unawaited(
        AppLogger.logInfo(
          LogEvent.loginSuccess,
          'Google sign-in successful',
          userId: userCredential.user!.uid,
          metadata: {'role': role, 'method': 'google'},
        ),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) {
            if (isAdmin || role == 'admin') return const AdminPage();
            if (role == 'moderator') return const ModeratorPage();
            return const MainPage();
          },
        ),
      );
    } catch (e) {
      // Persist Google sign-in failure to Firestore logs (not just console)
      unawaited(
        AppLogger.logWarning(
          LogEvent.loginFailure,
          'Google sign-in failed: ${e.toString().split('\n').first}',
          metadata: {'method': 'google'},
        ),
      );
      setState(() => _error = 'Google sign-in failed. Please try again.');
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 🔸 Logo Section
              Image.asset('assets/logo.png', height: screen.width * 0.3),
              const SizedBox(height: 20),

              const Text(
                "Welcome Back!",
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepOrange,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "Login to continue to your account",
                style: TextStyle(color: Colors.grey, fontSize: 15),
              ),
              const SizedBox(height: 40),

              // 🟠 Login Card
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 25,
                  vertical: 30,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.deepOrange.withOpacity(0.15),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Email Field
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.email_outlined),
                        labelText: "Email",
                        filled: true,
                        fillColor: Colors.orange.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Password Field
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.lock_outline),
                        labelText: "Password",
                        filled: true,
                        fillColor: Colors.orange.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Forgot Password
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const ForgotPasswordPage(),
                            ),
                          );
                        },
                        child: const Text(
                          "Forgot password?",
                          style: TextStyle(
                            color: Colors.deepOrange,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),

                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.red),
                          textAlign: TextAlign.center,
                        ),
                      ),

                    // 🔸 Login Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepOrange,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          elevation: 3,
                        ),
                        onPressed: _isLoading ? null : _login,
                        child: _isLoading
                            ? const CircularProgressIndicator(
                                color: Colors.white,
                              )
                            : const Text(
                                "Login",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ── Or divider ──
              Row(
                children: [
                  const Expanded(child: Divider(color: Colors.grey)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      "OR",
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const Expanded(child: Divider(color: Colors.grey)),
                ],
              ),
              const SizedBox(height: 20),

              // 🔵 Google Sign-In Button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  onPressed: (_isGoogleLoading || _isLoading)
                      ? null
                      : _loginWithGoogle,
                  icon: _isGoogleLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(
                          Icons.g_mobiledata,
                          size: 28,
                          color: Colors.red,
                        ),
                  label: const Text(
                    "Continue with Google",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // 🔹 Signup Redirect
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Don’t have an account? "),
                  GestureDetector(
                    onTap: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const SignUpScreen(),
                        ),
                      );
                    },
                    child: const Text(
                      "Sign Up",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.deepOrange,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
