import 'dart:async' show unawaited;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/access_control_service.dart';
import '../services/app_logger.dart';
import '../views/access_denied_page.dart';
import '../auth/login.dart';

// ─────────────────────────────────────────────────────────────────────────────
// RouteGuard — a wrapper widget that enforces RBAC before rendering a page.
// ─────────────────────────────────────────────────────────────────────────────

/// Wraps a child widget and ensures the current user has the required
/// [feature] permission before showing it.
///
/// Usage:
/// ```dart
/// RouteGuard(
///   feature: SystemFeature.manageUsers,
///   child: const AdminUsersPage(),
/// )
/// ```
///
/// If the user is unauthenticated → redirected to [LoginScreen].
/// If the user lacks permission → shown [AccessDeniedPage].
/// While checking → shows a loading indicator.
class RouteGuard extends StatefulWidget {
  const RouteGuard({super.key, required this.feature, required this.child});

  /// The feature this route requires access to.
  final SystemFeature feature;

  /// The page to display when access is granted.
  final Widget child;

  @override
  State<RouteGuard> createState() => _RouteGuardState();
}

class _RouteGuardState extends State<RouteGuard> {
  late Future<_GuardResult> _checkFuture;

  @override
  void initState() {
    super.initState();
    _checkFuture = _checkAccess();
  }

  Future<_GuardResult> _checkAccess() async {
    final firebaseUser = FirebaseAuth.instance.currentUser;

    // ── No authenticated session → login ─────────────────────────────────
    if (firebaseUser == null) {
      return _GuardResult.unauthenticated;
    }

    // ── Fetch role from Firestore ────────────────────────────────────────
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(firebaseUser.uid)
          .get();

      final data = doc.data();
      final role = AccessControlService.roleFromFirestore(data);

      // ── Check disabled ─────────────────────────────────────────────────
      if (data?['isDisabled'] == true) {
        return _GuardResult.disabled;
      }

      // ── Check permission ───────────────────────────────────────────────
      if (AccessControlService.hasAccess(role, widget.feature)) {
        return _GuardResult.allowed;
      }

      // ── Denied — log the violation ─────────────────────────────────────
      unawaited(
        AppLogger.logWarning(
          LogEvent.accessViolation,
          'Route guard denied: ${widget.feature.name}',
          userId: firebaseUser.uid,
          metadata: {'feature': widget.feature.name, 'role': role.name},
        ),
      );
      return _GuardResult.denied;
    } catch (_) {
      // If Firestore read fails, allow authenticated users through
      // to avoid blocking on network issues. Server-side Firestore rules
      // still enforce the real protection.
      return _GuardResult.allowed;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_GuardResult>(
      future: _checkFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        switch (snapshot.data ?? _GuardResult.unauthenticated) {
          case _GuardResult.allowed:
            return widget.child;

          case _GuardResult.unauthenticated:
            // Redirect to login
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (_) => false,
                );
              }
            });
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );

          case _GuardResult.disabled:
            return const AccessDeniedPage(
              message:
                  'Your account has been disabled. '
                  'Please contact the administrator for assistance.',
            );

          case _GuardResult.denied:
            return AccessDeniedPage(
              featureName: AccessControlService.featureLabel(widget.feature),
            );
        }
      },
    );
  }
}

enum _GuardResult { allowed, unauthenticated, disabled, denied }

// ─────────────────────────────────────────────────────────────────────────────
// AuthGuard — simpler guard that only checks authentication (not role).
// ─────────────────────────────────────────────────────────────────────────────

/// Wraps a child widget and ensures the user is authenticated.
///
/// Does NOT check role — use [RouteGuard] when a specific feature permission
/// is required.
class AuthGuard extends StatelessWidget {
  const AuthGuard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      // Schedule redirect after build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (_) => false,
        );
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return child;
  }
}
