import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../auth/login.dart';
import '../services/access_control_service.dart';
import '../services/app_logger.dart';
import 'access_denied_page.dart';
import 'moderator_reports_tab.dart';
import 'admin_announcements_page.dart';

/// Navigation shell for Moderator role.
///
/// Moderators see:
///   1. Reports   — review flagged posts
///   2. Announce  — send announcements to users
class ModeratorPage extends StatefulWidget {
  const ModeratorPage({super.key});

  @override
  State<ModeratorPage> createState() => _ModeratorPageState();
}

class _ModeratorPageState extends State<ModeratorPage> {
  int _selectedIndex = 0;
  bool _roleVerified = false;
  bool _accessDenied = false;

  @override
  void initState() {
    super.initState();
    _verifyModeratorRole();
  }

  /// Runtime session + role validation.
  Future<void> _verifyModeratorRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (_) => false,
        );
      }
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final role = AccessControlService.roleFromFirestore(doc.data());
      if (!AccessControlService.hasAccess(role, SystemFeature.reviewReports)) {
        AppLogger.logWarning(
          LogEvent.accessViolation,
          'Unauthorized user tried to access ModeratorPage',
          userId: user.uid,
          metadata: {'role': role.name},
        );
        if (mounted) setState(() => _accessDenied = true);
        return;
      }
    } catch (_) {
      // Firestore read failure — allow through; server rules enforce
    }
    if (mounted) setState(() => _roleVerified = true);
  }

  static const _destinations = [
    _NavDest(
      icon: Icons.report_outlined,
      selectedIcon: Icons.report_rounded,
      label: 'Reports',
    ),
    _NavDest(
      icon: Icons.campaign_outlined,
      selectedIcon: Icons.campaign_rounded,
      label: 'Announce',
    ),
  ];

  Widget _buildSelectedPage() {
    switch (_selectedIndex) {
      case 0:
        return const ModeratorReportsTab();
      case 1:
        return const AdminAnnouncementsPage();
      default:
        return const ModeratorReportsTab();
    }
  }

  static const _titles = ['Post Reports', 'Announcements'];

  // ── Logout ──────────────────────────────────────────────────────────────────
  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF7043),
              foregroundColor: Colors.white,
            ),
            child: const Text('SIGN OUT'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  // ── AppBar ──────────────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      elevation: 0,
      backgroundColor: Colors.transparent,
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF6A3DE8), Color(0xFF925CFE)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
      title: Text(
        _titles[_selectedIndex],
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 20,
        ),
      ),
      actions: [_buildModeratorAvatar(), const SizedBox(width: 8)],
    );
  }

  Widget _buildModeratorAvatar() {
    final user = FirebaseAuth.instance.currentUser;
    return GestureDetector(
      onTap: _logout,
      child: Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Tooltip(
          message: 'Sign out',
          child: CircleAvatar(
            radius: 16,
            backgroundColor: Colors.white24,
            backgroundImage: user?.photoURL != null
                ? NetworkImage(user!.photoURL!)
                : null,
            child: user?.photoURL == null
                ? const Icon(
                    Icons.shield_outlined,
                    color: Colors.white,
                    size: 18,
                  )
                : null,
          ),
        ),
      ),
    );
  }

  // ── Wide layout (NavigationRail) ────────────────────────────────────────────
  Widget _wideLayout() {
    return Row(
      children: [
        NavigationRail(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (i) => setState(() => _selectedIndex = i),
          labelType: NavigationRailLabelType.all,
          backgroundColor: Colors.white,
          selectedIconTheme: const IconThemeData(color: Color(0xFF6A3DE8)),
          unselectedIconTheme: const IconThemeData(color: Colors.grey),
          selectedLabelTextStyle: const TextStyle(
            color: Color(0xFF6A3DE8),
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
          leading: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6A3DE8), Color(0xFF925CFE)],
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.shield_outlined,
                color: Colors.white,
                size: 22,
              ),
            ),
          ),
          trailing: Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: IconButton(
                  tooltip: 'Sign out',
                  icon: const Icon(
                    Icons.logout_rounded,
                    color: Colors.grey,
                    size: 22,
                  ),
                  onPressed: _logout,
                ),
              ),
            ),
          ),
          destinations: _destinations.map((d) {
            return NavigationRailDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: Text(d.label),
            );
          }).toList(),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: _buildSelectedPage()),
      ],
    );
  }

  // ── Narrow layout (BottomNavigationBar) ─────────────────────────────────────
  Widget _narrowLayout() {
    return Column(
      children: [
        Expanded(child: _buildSelectedPage()),
        _buildBottomNav(),
      ],
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (i) => setState(() => _selectedIndex = i),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF6A3DE8),
        unselectedItemColor: Colors.grey.shade500,
        selectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 10,
        ),
        unselectedLabelStyle: const TextStyle(fontSize: 10),
        backgroundColor: Colors.white,
        elevation: 0,
        items: _destinations
            .map(
              (d) => BottomNavigationBarItem(
                icon: Icon(d.icon),
                activeIcon: Icon(d.selectedIcon),
                label: d.label,
              ),
            )
            .toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ── Access check ──────────────────────────────────────────────────────
    if (_accessDenied) {
      return const AccessDeniedPage(featureName: 'Moderator Panel');
    }
    if (!_roleVerified) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: _buildAppBar(),
      body: LayoutBuilder(
        builder: (ctx, constraints) {
          if (constraints.maxWidth >= 640) return _wideLayout();
          return _narrowLayout();
        },
      ),
    );
  }
}

// ── Helper data class ──────────────────────────────────────────────────────────

class _NavDest {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const _NavDest({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}
