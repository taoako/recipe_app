import 'dart:async' show unawaited;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'app_logger.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Role-Based Access Control (RBAC) Service
// ─────────────────────────────────────────────────────────────────────────────

/// Defines every role recognised by the application.
///
/// Ordering matters: [guest] < [user] < [moderator] < [admin].
enum AppRole { guest, user, moderator, admin }

/// Every protectable system feature / resource.
enum SystemFeature {
  // ── Public ──────────────────────────────────────────────────────────────
  viewHomepage,
  userRegistration,
  login,

  // ── Authenticated users ────────────────────────────────────────────────
  userDashboard,
  editProfile,
  submitData, // upload recipes
  viewOwnRecords, // own recipes, liked posts, followers
  viewNotifications,
  searchRecipes,
  viewRecipeDetail,
  viewOtherProfile,
  reportProblem,

  // ── Moderator ──────────────────────────────────────────────────────────
  reviewReports, // flagged-post review
  sendAnnouncements, // announcements to users
  // ── Administrator ──────────────────────────────────────────────────────
  viewAllRecords, // all content tab
  manageUsers, // user management (roles, disable, delete)
  systemConfiguration, // admin analytics dashboard
  viewLogs, // system logs
  deleteRecords, // remove any recipe
  incidentResponse, // incident response panel
  viewUserReports, // user-submitted bug reports
}

/// Central access-control service that answers **"can role X do Y?"**.
///
/// The permission matrix is kept in a single, auditable constant map.
class AccessControlService {
  AccessControlService._(); // no instances

  // ═══════════════════════════════════════════════════════════════════════════
  // Permission matrix  (ACL)
  //
  //   Key   = SystemFeature
  //   Value = set of roles that are ALLOWED
  // ═══════════════════════════════════════════════════════════════════════════
  static const Map<SystemFeature, Set<AppRole>> _acl = {
    // ── Public (guest + user + moderator + admin) ────────────────────────
    SystemFeature.viewHomepage: {
      AppRole.guest,
      AppRole.user,
      AppRole.moderator,
      AppRole.admin,
    },
    SystemFeature.userRegistration: {AppRole.guest},
    SystemFeature.login: {
      AppRole.guest,
      AppRole.user,
      AppRole.moderator,
      AppRole.admin,
    },

    // ── Authenticated (user + moderator + admin) ─────────────────────────
    SystemFeature.userDashboard: {
      AppRole.user,
      AppRole.moderator,
      AppRole.admin,
    },
    SystemFeature.editProfile: {AppRole.user, AppRole.moderator, AppRole.admin},
    SystemFeature.submitData: {AppRole.user, AppRole.moderator, AppRole.admin},
    SystemFeature.viewOwnRecords: {
      AppRole.user,
      AppRole.moderator,
      AppRole.admin,
    },
    SystemFeature.viewNotifications: {
      AppRole.user,
      AppRole.moderator,
      AppRole.admin,
    },
    SystemFeature.searchRecipes: {
      AppRole.user,
      AppRole.moderator,
      AppRole.admin,
    },
    SystemFeature.viewRecipeDetail: {
      AppRole.user,
      AppRole.moderator,
      AppRole.admin,
    },
    SystemFeature.viewOtherProfile: {
      AppRole.user,
      AppRole.moderator,
      AppRole.admin,
    },
    SystemFeature.reportProblem: {
      AppRole.user,
      AppRole.moderator,
      AppRole.admin,
    },

    // ── Moderator (moderator + admin) ────────────────────────────────────
    SystemFeature.reviewReports: {AppRole.moderator, AppRole.admin},
    SystemFeature.sendAnnouncements: {AppRole.moderator, AppRole.admin},

    // ── Administrator only ───────────────────────────────────────────────
    SystemFeature.viewAllRecords: {AppRole.admin},
    SystemFeature.manageUsers: {AppRole.admin},
    SystemFeature.systemConfiguration: {AppRole.admin},
    SystemFeature.viewLogs: {AppRole.admin},
    SystemFeature.deleteRecords: {AppRole.admin},
    SystemFeature.incidentResponse: {AppRole.admin},
    SystemFeature.viewUserReports: {AppRole.admin},
  };

  // ═══════════════════════════════════════════════════════════════════════════
  // Core check
  // ═══════════════════════════════════════════════════════════════════════════

  /// Returns `true` when [role] is allowed to use [feature].
  static bool hasAccess(AppRole role, SystemFeature feature) {
    return _acl[feature]?.contains(role) ?? false;
  }

  /// Throws an [AccessDeniedException] if the role is not allowed.
  static void enforce(AppRole role, SystemFeature feature) {
    if (!hasAccess(role, feature)) {
      throw AccessDeniedException(role: role, feature: feature);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Role resolution helpers
  // ═══════════════════════════════════════════════════════════════════════════

  /// Resolve the [AppRole] from a Firestore user document's data map.
  ///
  /// Falls back to [AppRole.user] when the document has no explicit `role`.
  /// The legacy `isAdmin` boolean is also honoured.
  static AppRole roleFromFirestore(Map<String, dynamic>? data) {
    if (data == null) return AppRole.guest;
    final roleStr = data['role']?.toString().toLowerCase();
    final isAdmin = data['isAdmin'] == true;

    if (isAdmin || roleStr == 'admin') return AppRole.admin;
    if (roleStr == 'moderator') return AppRole.moderator;
    if (roleStr == 'user' || roleStr == null) return AppRole.user;
    return AppRole.user;
  }

  /// Convert an [AppRole] to its Firestore string representation.
  static String roleToString(AppRole role) {
    switch (role) {
      case AppRole.guest:
        return 'guest';
      case AppRole.user:
        return 'user';
      case AppRole.moderator:
        return 'moderator';
      case AppRole.admin:
        return 'admin';
    }
  }

  /// Fetch the current Firebase user's role from Firestore.
  ///
  /// Returns [AppRole.guest] when there is no authenticated user.
  static Future<AppRole> getCurrentUserRole() async {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) return AppRole.guest;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(firebaseUser.uid)
          .get();
      return roleFromFirestore(doc.data());
    } catch (_) {
      return AppRole.user; // authenticated but Firestore read failed
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Validation + logging
  // ═══════════════════════════════════════════════════════════════════════════

  /// Validates access and logs an access-violation when denied.
  ///
  /// Returns `true` if permitted, `false` otherwise.
  static Future<bool> validateAccess(SystemFeature feature) async {
    final role = await getCurrentUserRole();
    final allowed = hasAccess(role, feature);

    if (!allowed) {
      unawaited(
        AppLogger.logWarning(
          LogEvent.accessViolation,
          'Access denied: ${feature.name} for role ${role.name}',
          userId: FirebaseAuth.instance.currentUser?.uid,
          metadata: {'feature': feature.name, 'role': role.name},
        ),
      );
    }

    return allowed;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Human-readable helpers (for UI)
  // ═══════════════════════════════════════════════════════════════════════════

  /// A friendly label for [role].
  static String roleLabel(AppRole role) {
    switch (role) {
      case AppRole.guest:
        return 'Guest';
      case AppRole.user:
        return 'User';
      case AppRole.moderator:
        return 'Moderator';
      case AppRole.admin:
        return 'Administrator';
    }
  }

  /// A friendly label for [feature].
  static String featureLabel(SystemFeature feature) {
    switch (feature) {
      case SystemFeature.viewHomepage:
        return 'View Homepage';
      case SystemFeature.userRegistration:
        return 'User Registration';
      case SystemFeature.login:
        return 'Login';
      case SystemFeature.userDashboard:
        return 'User Dashboard';
      case SystemFeature.editProfile:
        return 'Edit Profile';
      case SystemFeature.submitData:
        return 'Submit Data (Upload Recipes)';
      case SystemFeature.viewOwnRecords:
        return 'View Own Records';
      case SystemFeature.viewNotifications:
        return 'View Notifications';
      case SystemFeature.searchRecipes:
        return 'Search Recipes';
      case SystemFeature.viewRecipeDetail:
        return 'View Recipe Detail';
      case SystemFeature.viewOtherProfile:
        return 'View Other User Profile';
      case SystemFeature.reportProblem:
        return 'Report a Problem';
      case SystemFeature.reviewReports:
        return 'Review Flagged Reports';
      case SystemFeature.sendAnnouncements:
        return 'Send Announcements';
      case SystemFeature.viewAllRecords:
        return 'View All Records';
      case SystemFeature.manageUsers:
        return 'Manage Users';
      case SystemFeature.systemConfiguration:
        return 'System Configuration (Analytics)';
      case SystemFeature.viewLogs:
        return 'View Logs';
      case SystemFeature.deleteRecords:
        return 'Delete Records';
      case SystemFeature.incidentResponse:
        return 'Incident Response';
      case SystemFeature.viewUserReports:
        return 'View User Reports';
    }
  }

  /// Returns the full ACL matrix for display purposes.
  static Map<SystemFeature, Set<AppRole>> get aclMatrix => _acl;
}

// ─────────────────────────────────────────────────────────────────────────────
// Exception
// ─────────────────────────────────────────────────────────────────────────────

class AccessDeniedException implements Exception {
  const AccessDeniedException({required this.role, required this.feature});

  final AppRole role;
  final SystemFeature feature;

  @override
  String toString() =>
      'AccessDeniedException: ${role.name} cannot access ${feature.name}';
}
