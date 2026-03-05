import 'package:flutter/material.dart';
import '../auth/login.dart';

/// Shown when a user tries to access a page they do not have permission for.
///
/// Provides a clear message and buttons to go back or return to login.
class AccessDeniedPage extends StatelessWidget {
  const AccessDeniedPage({super.key, this.message, this.featureName});

  /// Optional custom message to display.
  final String? message;

  /// The feature that was denied (for display purposes).
  final String? featureName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Icon ────────────────────────────────────────────────────
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.lock_outline_rounded,
                  size: 48,
                  color: Colors.red.shade400,
                ),
              ),
              const SizedBox(height: 24),

              // ── Title ───────────────────────────────────────────────────
              const Text(
                'Access Denied',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2D3142),
                ),
              ),
              const SizedBox(height: 12),

              // ── Message ─────────────────────────────────────────────────
              Text(
                message ??
                    'You do not have permission to access '
                        '${featureName ?? 'this page'}.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  color: Color(0xFF6B7280),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'If you believe this is an error, please contact '
                'your system administrator.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF9CA3AF),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 32),

              // ── Actions ─────────────────────────────────────────────────
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Go back
                  OutlinedButton.icon(
                    onPressed: () {
                      if (Navigator.of(context).canPop()) {
                        Navigator.of(context).pop();
                      } else {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => const LoginScreen(),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.arrow_back_rounded, size: 18),
                    label: const Text('Go Back'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF6B7280),
                      side: const BorderSide(color: Color(0xFFD1D5DB)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Return to login
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                        (_) => false,
                      );
                    },
                    icon: const Icon(Icons.login_rounded, size: 18),
                    label: const Text('Return to Login'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF7043),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
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
