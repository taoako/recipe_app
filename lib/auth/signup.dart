import 'dart:async' show unawaited;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'login.dart';
import 'email_verification_page.dart';
import '../main_page.dart';
import '../views/admin_page.dart';
import '../services/google_auth_service.dart';
import '../services/app_logger.dart';
import '../services/input_validator.dart';
import '../services/security_service.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _acceptedPolicy = false;
  bool _obscurePassword = true;
  String? _error;

  // Real-time password requirements tracking
  Map<String, bool> _passwordRequirements = {
    'At least 8 characters': false,
    'At least one uppercase letter (A-Z)': false,
    'At least one lowercase letter (a-z)': false,
    'At least one number (0-9)': false,
    'At least one special character (!@#\$%^&*)': false,
  };
  bool _showPasswordRequirements = false;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_onPasswordChanged);
  }

  void _onPasswordChanged() {
    setState(() {
      _passwordRequirements = SecurityService.checkPasswordRequirements(
        _passwordController.text,
      );
      _showPasswordRequirements = _passwordController.text.isNotEmpty;
    });
  }

  @override
  void dispose() {
    _passwordController.removeListener(_onPasswordChanged);
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    if (!_acceptedPolicy) {
      setState(
        () =>
            _error = 'You must accept the Terms of Service and Privacy Policy',
      );
      return;
    }

    final username = _usernameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    final usernameError = InputValidator.validateUsername(username);
    if (usernameError != null) {
      setState(() => _error = usernameError);
      return;
    }

    if (!InputValidator.isValidEmail(email)) {
      setState(() => _error = 'Enter a valid email address');
      return;
    }

    final passwordError = InputValidator.validatePassword(password);
    if (passwordError != null) {
      setState(() => _error = passwordError);
      return;
    }

    // ── CAPTCHA verification before sign-up ──
    if (!mounted) return;
    final captchaPassed = await SecurityService.showCaptchaDialog(context);
    if (!captchaPassed) {
      unawaited(
        AppLogger.logWarning(
          LogEvent.captchaFailed,
          'CAPTCHA failed during signup',
          metadata: {'email': email},
        ),
      );
      if (mounted) {
        setState(
          () => _error = 'CAPTCHA verification failed. Please try again.',
        );
      }
      return;
    }
    unawaited(
      AppLogger.logInfo(
        LogEvent.captchaCompleted,
        'CAPTCHA passed during signup',
        metadata: {'email': email},
      ),
    );

    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);

      final user = credential.user;
      if (user != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'username': username,
          'email': email,
          'emailVerified': false,
        });
        await user.updateDisplayName(username);
        // Send verification email with an explicit HTTPS action URL so the
        // email contains a real clickable link instead of the app deep-link scheme.
        await user.sendEmailVerification(
          ActionCodeSettings(
            url: 'https://ingrdnts-f505f.firebaseapp.com',
            handleCodeInApp: false,
          ),
        );
        // Log signup success
        unawaited(
          AppLogger.logInfo(
            LogEvent.signupSuccess,
            'New account registered',
            userId: user.uid,
            metadata: {'username': username},
          ),
        );
      }

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => EmailVerificationPage(email: email),
        ),
      );
    } on FirebaseAuthException catch (e) {
      // Log signup failure
      unawaited(
        AppLogger.logWarning(
          LogEvent.signupFailure,
          'Signup failed: ${e.code}',
          metadata: {'errorCode': e.code},
        ),
      );
      setState(() {
        switch (e.code) {
          case 'email-already-in-use':
            _error =
                'An account with this email already exists. Please log in.';
            break;
          case 'invalid-email':
            _error = 'The email address is not valid.';
            break;
          case 'weak-password':
            _error = 'Password is too weak. Use at least 8 characters.';
            break;
          case 'operation-not-allowed':
            _error = 'Email/password sign-up is not enabled. Contact support.';
            break;
          default:
            _error = e.message ?? 'Sign-up failed. Please try again.';
        }
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _signUpWithGoogle() async {
    if (!_acceptedPolicy) {
      setState(
        () =>
            _error = 'You must accept the Terms of Service and Privacy Policy',
      );
      return;
    }

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

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => isAdmin ? const AdminPage() : const MainPage(),
        ),
      );
    } catch (e) {
      AppLogger.error('Google sign-up failed', e);
      setState(() => _error = 'Google sign-up failed. Please try again.');
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  // ── Policy dialog ─────────────────────────────────────────────────────────

  void _showPolicyDialog(BuildContext context, String title, String content) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: Colors.deepOrange,
          ),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Text(
              content,
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Close',
              style: TextStyle(
                color: Colors.deepOrange,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const String _termsOfService = '''
Terms of Service — Ingrdnts Recipe App

Effective Date: March 2026

1. Acceptance of Terms
By creating an account or using the Ingrdnts app, you agree to these Terms of Service. If you do not agree, do not use the app.

2. User Accounts
• You must provide accurate information when creating an account.
• You are responsible for keeping your login credentials secure.
• You must be at least 13 years old to create an account.
• One person may only maintain one account.

3. User-Generated Content
• You retain ownership of recipes and content you post.
• By posting, you grant Ingrdnts a non-exclusive license to display your content within the app.
• You must not post content that is offensive, illegal, plagiarized, or violates others' intellectual property.
• Moderators and administrators may remove content that violates these terms.

4. Prohibited Conduct
• Harassment, hate speech, or bullying of other users.
• Posting spam, misleading, or fraudulent content.
• Attempting to gain unauthorized access to other accounts or system resources.
• Circumventing security features or moderation actions.
• Impersonating other users or public figures.

5. Account Suspension & Termination
• Administrators may disable or delete accounts that violate these terms.
• Repeated violations may result in permanent removal from the platform.

6. Disclaimers
• Recipes are user-submitted and not verified for safety or accuracy.
• Follow food safety guidelines — Ingrdnts is not liable for adverse outcomes from recipes.
• The app is provided "as is" without warranties of any kind.

7. Changes to Terms
We may update these terms from time to time. Continued use after changes constitutes acceptance of the new terms.
''';

  static const String _privacyAndPasswordPolicy = '''
Privacy & Password Policy — Ingrdnts Recipe App

Effective Date: March 2026

── Privacy Policy ──

1. Information We Collect
• Account details: username, email address, profile image.
• Content you create: recipes, comments, reports.
• Usage data: login times, interactions (follows, likes), and activity logs.

2. How We Use Your Information
• To provide and personalize the app experience.
• To enforce community guidelines and moderate content.
• To maintain security and prevent abuse.
• Activity logs are stored for administrative and security purposes.

3. Data Sharing
• We do not sell your personal data to third parties.
• Data may be shared with Firebase (Google) for authentication and storage services.
• We may disclose data if required by law.

4. Data Retention
• Your data is retained while your account is active.
• You may request account deletion by contacting an administrator.
• Activity logs may be retained for security auditing purposes.

5. Your Rights
• You can update your profile information at any time.
• You can request access to or deletion of your data.

── Password Policy ──

To keep your account secure, passwords must meet the following requirements:

• Minimum 8 characters in length.
• At least one uppercase letter (A-Z).
• At least one lowercase letter (a-z).
• At least one number (0-9).
• At least one special character (!@#\$%^&* etc.).

Password Tips:
• Never share your password with anyone.
• Use a unique password not used on other websites.
• Change your password immediately if you suspect unauthorized access.
• Avoid using personal information (name, birthday) in your password.
''';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFFF7043), Color(0xFFFFA726)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
              child: Container(
                padding: const EdgeInsets.all(25),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(25),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Center(
                      child: Text(
                        "Create Account",
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.deepOrange,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Center(
                      child: Text(
                        "Sign up to start sharing your recipes",
                        style: TextStyle(color: Colors.black54, fontSize: 14),
                      ),
                    ),
                    const SizedBox(height: 30),

                    // Username
                    TextField(
                      controller: _usernameController,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.person_outline),
                        hintText: "Username",
                        filled: true,
                        fillColor: Colors.grey[100],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Email
                    TextField(
                      controller: _emailController,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.email_outlined),
                        hintText: "Email",
                        filled: true,
                        fillColor: Colors.grey[100],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Password
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                        ),
                        hintText: "Password",
                        filled: true,
                        fillColor: Colors.grey[100],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),

                    // ── Real-time password requirements ─────────────────────
                    if (_showPasswordRequirements) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Password Requirements:',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.black54,
                              ),
                            ),
                            const SizedBox(height: 6),
                            ..._passwordRequirements.entries.map(
                              (entry) => Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  children: [
                                    Icon(
                                      entry.value
                                          ? Icons.check_circle
                                          : Icons.cancel,
                                      size: 16,
                                      color: entry.value
                                          ? Colors.green
                                          : Colors.red.shade300,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        entry.key,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: entry.value
                                              ? Colors.green.shade700
                                              : Colors.red.shade400,
                                          fontWeight: entry.value
                                              ? FontWeight.w600
                                              : FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),

                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),

                    // ── Policy checkbox ──────────────────────────────────────
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: Checkbox(
                            value: _acceptedPolicy,
                            activeColor: Colors.deepOrange,
                            onChanged: (v) =>
                                setState(() => _acceptedPolicy = v ?? false),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Wrap(
                            children: [
                              const Text(
                                'I agree to the ',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: Colors.black54,
                                ),
                              ),
                              GestureDetector(
                                onTap: () => _showPolicyDialog(
                                  context,
                                  'Terms of Service',
                                  _termsOfService,
                                ),
                                child: const Text(
                                  'Terms of Service',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: Colors.deepOrange,
                                    fontWeight: FontWeight.w600,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                              const Text(
                                ' and ',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: Colors.black54,
                                ),
                              ),
                              GestureDetector(
                                onTap: () => _showPolicyDialog(
                                  context,
                                  'Privacy & Password Policy',
                                  _privacyAndPasswordPolicy,
                                ),
                                child: const Text(
                                  'Privacy & Password Policy',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: Colors.deepOrange,
                                    fontWeight: FontWeight.w600,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Sign Up Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepOrange,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          elevation: 3,
                        ),
                        onPressed: _isLoading ? null : _signUp,
                        child: _isLoading
                            ? const CircularProgressIndicator(
                                color: Colors.white,
                              )
                            : const Text(
                                "Sign Up",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
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

                    // 🔵 Google Sign-Up Button
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
                            : _signUpWithGoogle,
                        icon: _isGoogleLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
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

                    // Back to Login
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text("Already have an account? "),
                        TextButton(
                          onPressed: () {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const LoginScreen(),
                              ),
                            );
                          },
                          child: const Text(
                            "Login",
                            style: TextStyle(
                              color: Colors.deepOrange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
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
  }
}
