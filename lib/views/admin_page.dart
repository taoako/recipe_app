import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../auth/login.dart';
import '../services/access_control_service.dart';
import '../services/app_logger.dart';
import 'access_denied_page.dart';
import 'admin_analytics_page.dart';
import 'admin_users_page.dart';
import 'admin_incident_response_page.dart';
import 'admin_logs_page.dart';
import 'admin_user_reports_page.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  int _selectedIndex = 0;
  bool _roleVerified = false;
  bool _accessDenied = false;

  @override
  void initState() {
    super.initState();
    _verifyAdminRole();
  }

  /// Runtime session + role validation.
  Future<void> _verifyAdminRole() async {
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
      if (role != AppRole.admin) {
        AppLogger.logWarning(
          LogEvent.accessViolation,
          'Non-admin tried to access AdminPage',
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

  // ── nav destinations ──────────────────────────────────────────────────────
  static const _destinations = [
    _NavDest(
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard_rounded,
      label: 'Dashboard',
    ),
    _NavDest(
      icon: Icons.people_outline,
      selectedIcon: Icons.people_rounded,
      label: 'Users',
    ),
    _NavDest(
      icon: Icons.security_outlined,
      selectedIcon: Icons.security_rounded,
      label: 'Incidents',
    ),
    _NavDest(
      icon: Icons.feedback_outlined,
      selectedIcon: Icons.feedback_rounded,
      label: 'Reports',
    ),
    _NavDest(
      icon: Icons.history_edu_outlined,
      selectedIcon: Icons.history_edu_rounded,
      label: 'Logs',
    ),
  ];

  static const _pages = <Widget>[
    AdminAnalyticsPage(),
    AdminUsersPage(),
    AdminIncidentResponsePage(),
    AdminUserReportsPage(),
    AdminLogsPage(),
  ];

  static const _titles = [
    'Dashboard',
    'User Management',
    'Incident Response',
    'User Reports',
    'System Logs',
  ];

  static const _gradientStart = Color(0xFFFFA726);
  static const _gradientEnd = Color(0xFFFF5722);

  // ── logout ─────────────────────────────────────────────────────────────────
  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Sign Out',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                const Text('Are you sure you want to sign out?'),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF5722),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Sign Out'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (confirm != true) return;
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  // ── build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // ── Access check ──────────────────────────────────────────────────────
    if (_accessDenied) {
      return const AccessDeniedPage(
        featureName: 'System Configuration (Admin Panel)',
      );
    }
    if (!_roleVerified) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 640;
        return Scaffold(
          backgroundColor: const Color(0xFFF7F8FC),
          appBar: _buildAppBar(),
          body: wide ? _wideLayout() : _narrowLayout(),
          bottomNavigationBar: wide ? null : _buildBottomNav(),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      automaticallyImplyLeading: false,
      elevation: 0,
      backgroundColor: Colors.transparent,
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_gradientStart, _gradientEnd],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.admin_panel_settings_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _titles[_selectedIndex],
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Admin Console',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: GestureDetector(
            onTap: _logout,
            child: Row(
              children: [
                _buildAdminAvatar(),
                const SizedBox(width: 6),
                const Icon(Icons.logout_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAdminAvatar() {
    final user = FirebaseAuth.instance.currentUser;
    final photo = user?.photoURL;
    final name = user?.displayName ?? 'A';
    return CircleAvatar(
      radius: 16,
      backgroundColor: Colors.white.withValues(alpha: 0.3),
      backgroundImage: (photo != null && photo.isNotEmpty)
          ? NetworkImage(photo)
          : null,
      child: (photo == null || photo.isEmpty)
          ? Text(
              name.isNotEmpty ? name[0].toUpperCase() : 'A',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            )
          : null,
    );
  }

  Widget _wideLayout() {
    return Row(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [_gradientStart, _gradientEnd],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            boxShadow: [
              BoxShadow(
                color: Color(0x33FF5722),
                blurRadius: 12,
                offset: Offset(4, 0),
              ),
            ],
          ),
          child: NavigationRail(
            backgroundColor: Colors.transparent,
            selectedIndex: _selectedIndex,
            onDestinationSelected: (i) => setState(() => _selectedIndex = i),
            labelType: NavigationRailLabelType.all,
            minWidth: 80,
            selectedIconTheme: const IconThemeData(
              color: Colors.white,
              size: 24,
            ),
            unselectedIconTheme: IconThemeData(
              color: Colors.white.withValues(alpha: 0.55),
              size: 22,
            ),
            selectedLabelTextStyle: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
            unselectedLabelTextStyle: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 11,
            ),
            indicatorColor: Colors.white.withValues(alpha: 0.2),
            indicatorShape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            useIndicator: true,
            destinations: _destinations
                .map(
                  (d) => NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(d.label),
                    padding: const EdgeInsets.symmetric(vertical: 4),
                  ),
                )
                .toList(),
          ),
        ),
        const VerticalDivider(thickness: 0, width: 0),
        Expanded(
          child: IndexedStack(index: _selectedIndex, children: _pages),
        ),
      ],
    );
  }

  Widget _narrowLayout() {
    return IndexedStack(index: _selectedIndex, children: _pages);
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 12,
            offset: Offset(0, -3),
          ),
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (i) => setState(() => _selectedIndex = i),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFFFF7043),
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
