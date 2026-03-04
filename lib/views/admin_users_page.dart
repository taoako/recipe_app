import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/app_logger.dart';

/// Admin interface for searching users and managing their roles.
/// Roles: user (default) | moderator | admin
class AdminUsersPage extends StatefulWidget {
  const AdminUsersPage({super.key});

  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends State<AdminUsersPage> {
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String _roleFilter = 'all'; // all | user | moderator | admin

  static const _roles = ['all', 'user', 'moderator', 'admin'];

  static const _assignableRoles = ['user', 'moderator'];

  static const _gradient = LinearGradient(
    colors: [Color(0xFFFFA726), Color(0xFFFF7043)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Role helpers ────────────────────────────────────────────────────────────

  Color _roleColor(String role) => switch (role) {
    'admin' => const Color(0xFFFF7043),
    'moderator' => Colors.purple.shade600,
    _ => Colors.teal.shade600,
  };

  IconData _roleIcon(String role) => switch (role) {
    'admin' => Icons.admin_panel_settings,
    'moderator' => Icons.shield_outlined,
    _ => Icons.person_outline,
  };

  String _roleLabel(String role) => switch (role) {
    'admin' => 'Admin',
    'moderator' => 'Moderator',
    _ => 'User',
  };

  // ── Promote / demote ────────────────────────────────────────────────────────

  Future<void> _changeRole(
    String userId,
    String currentRole,
    String username,
  ) async {
    final selfId = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (userId == selfId) {
      _snack('You cannot change your own role.', Colors.orange);
      return;
    }

    String? selected = currentRole;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: _gradient,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.manage_accounts,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Change Role',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '@$username',
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.black54,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: _assignableRoles.map((role) {
              final isSelected = selected == role;
              final color = _roleColor(role);
              return GestureDetector(
                onTap: () => setInner(() => selected = role),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? color.withValues(alpha: 0.12)
                        : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? color : Colors.grey.shade200,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(_roleIcon(role), color: color, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _roleLabel(role),
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: color,
                              ),
                            ),
                            Text(
                              _roleDescription(role),
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.black45,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isSelected)
                        Icon(Icons.check_circle, color: color, size: 20),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: selected == currentRole
                  ? null
                  : () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF7043),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || selected == null || selected == currentRole) {
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'role': selected,
        'isAdmin': selected == 'admin',
      });

      await AppLogger.logInfo(
        LogEvent.adminAction,
        'Role changed: $username → $selected',
        metadata: {
          'action': 'change_role',
          'targetUserId': userId,
          'fromRole': currentRole,
          'toRole': selected,
        },
      );

      if (mounted) {
        _snack(
          'Role updated: $username is now ${_roleLabel(selected!)}',
          Colors.green,
        );
      }
    } catch (e) {
      if (mounted) _snack('Failed to change role.', Colors.red);
    }
  }

  String _roleDescription(String role) => switch (role) {
    'moderator' => 'Can review reported posts and send announcements',
    _ => 'Standard app user with no elevated permissions',
  };

  // ── Disable / Enable ────────────────────────────────────────────────────────────

  Future<void> _toggleDisable(
    String userId,
    String username,
    bool isCurrentlyDisabled,
  ) async {
    final action = isCurrentlyDisabled ? 'enable' : 'disable';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(isCurrentlyDisabled ? 'Enable Account' : 'Disable Account'),
        content: Text(
          isCurrentlyDisabled
              ? 'Allow @$username to log in again?'
              : 'Prevent @$username from logging in? Their data will be kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: isCurrentlyDisabled
                  ? Colors.green
                  : Colors.orange.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(isCurrentlyDisabled ? 'Enable' : 'Disable'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'isDisabled': !isCurrentlyDisabled,
      });
      await AppLogger.logInfo(
        LogEvent.adminAction,
        'Account ${action}d: $username',
        metadata: {'action': '${action}_account', 'targetUserId': userId},
      );
      if (mounted) {
        _snack(
          '@$username has been ${action}d.',
          isCurrentlyDisabled ? Colors.green : Colors.orange.shade700,
        );
      }
    } catch (e) {
      if (mounted) _snack('Failed to $action account: $e', Colors.red);
    }
  }

  // ── Delete user ───────────────────────────────────────────────────────────────

  Future<void> _deleteUser(String userId, String username) async {
    // Step 1: type-to-confirm dialog
    final confirmCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Row(
            children: [
              Icon(Icons.warning_rounded, color: Colors.red),
              SizedBox(width: 8),
              Text('Remove User'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This will permanently delete @$username\'s profile and all their data. This cannot be undone.',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              const Text(
                'Type the username to confirm:',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: confirmCtrl,
                decoration: InputDecoration(
                  hintText: username,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onChanged: (_) => setS(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: confirmCtrl.text.trim() == username
                  ? () => Navigator.pop(ctx, true)
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );
    confirmCtrl.dispose();
    if (confirmed != true) return;

    try {
      // Delete Firestore user document (auth account deletion requires
      // Admin SDK / Cloud Function — mark as deleted here for now)
      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'isDisabled': true,
        'isDeleted': true,
        'deletedAt': FieldValue.serverTimestamp(),
        'username': '[deleted]',
        'email': '',
        'profileImageUrl': '',
      });
      await AppLogger.logInfo(
        LogEvent.adminAction,
        'User account removed: $username',
        metadata: {'action': 'delete_user', 'targetUserId': userId},
      );
      if (mounted) _snack('@$username has been removed.', Colors.red);
    } catch (e) {
      if (mounted) _snack('Failed to remove user: $e', Colors.red);
    }
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      body: Column(
        children: [
          // ── Search + filter header ────────────────────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              children: [
                // Search bar
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search by username...',
                    prefixIcon: const Icon(
                      Icons.search,
                      color: Color(0xFFFF7043),
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                  onChanged: (v) =>
                      setState(() => _searchQuery = v.toLowerCase()),
                ),
                const SizedBox(height: 10),
                // Role filter chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _roles.map((role) {
                      final selected = _roleFilter == role;
                      final color = role == 'all'
                          ? Colors.grey.shade700
                          : _roleColor(role);
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(
                            role == 'all' ? 'All Roles' : _roleLabel(role),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: selected ? Colors.white : color,
                            ),
                          ),
                          avatar: role != 'all'
                              ? Icon(
                                  _roleIcon(role),
                                  size: 14,
                                  color: selected ? Colors.white : color,
                                )
                              : null,
                          selected: selected,
                          onSelected: (_) => setState(() => _roleFilter = role),
                          selectedColor: color,
                          backgroundColor: color.withValues(alpha: 0.08),
                          checkmarkColor: Colors.white,
                          side: BorderSide(
                            color: selected
                                ? color
                                : color.withValues(alpha: 0.3),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // ── User list ─────────────────────────────────────────────────────
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .orderBy('username')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                var docs = snapshot.data?.docs ?? [];

                // Filter by role
                if (_roleFilter != 'all') {
                  docs = docs
                      .where((d) => (d.data()['role'] ?? 'user') == _roleFilter)
                      .toList();
                }

                // Filter by search
                if (_searchQuery.isNotEmpty) {
                  docs = docs
                      .where(
                        (d) => (d.data()['username'] ?? '')
                            .toString()
                            .toLowerCase()
                            .contains(_searchQuery),
                      )
                      .toList();
                }

                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 54,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No users found',
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  itemCount: docs.length,
                  itemBuilder: (ctx, i) {
                    final data = docs[i].data();
                    final uid = docs[i].id;
                    final username = data['username']?.toString() ?? 'Unknown';
                    final email = data['email']?.toString() ?? '';
                    final role = data['role']?.toString() ?? 'user';
                    final profileImage =
                        data['profileImageUrl']?.toString() ?? '';
                    final isDisabled = data['isDisabled'] == true;

                    return _UserCard(
                      uid: uid,
                      username: username,
                      email: email,
                      role: role,
                      profileImage: profileImage,
                      roleColor: _roleColor(role),
                      roleIcon: _roleIcon(role),
                      roleLabel: _roleLabel(role),
                      isDisabled: isDisabled,
                      onChangeRole: () => _changeRole(uid, role, username),
                      onToggleDisable: () =>
                          _toggleDisable(uid, username, isDisabled),
                      onDelete: () => _deleteUser(uid, username),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  final String uid;
  final String username;
  final String email;
  final String role;
  final String profileImage;
  final Color roleColor;
  final IconData roleIcon;
  final String roleLabel;
  final bool isDisabled;
  final VoidCallback onChangeRole;
  final VoidCallback onToggleDisable;
  final VoidCallback onDelete;

  const _UserCard({
    required this.uid,
    required this.username,
    required this.email,
    required this.role,
    required this.profileImage,
    required this.roleColor,
    required this.roleIcon,
    required this.roleLabel,
    required this.isDisabled,
    required this.onChangeRole,
    required this.onToggleDisable,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final selfId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final isSelf = uid == selfId;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDisabled ? Colors.grey.shade100 : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: roleColor.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // Avatar
            CircleAvatar(
              radius: 26,
              backgroundColor: roleColor.withValues(alpha: 0.15),
              backgroundImage: profileImage.isNotEmpty
                  ? NetworkImage(profileImage)
                  : null,
              child: profileImage.isEmpty
                  ? Text(
                      username.isNotEmpty ? username[0].toUpperCase() : '?',
                      style: TextStyle(
                        color: roleColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '@$username',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2D2D2D),
                        ),
                      ),
                      if (isSelf) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'You',
                            style: TextStyle(fontSize: 10, color: Colors.grey),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (email.isNotEmpty)
                    Text(
                      email,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black38,
                      ),
                    ),
                ],
              ),
            ),

            // Role badge + change button
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: roleColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: roleColor.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(roleIcon, size: 12, color: roleColor),
                      const SizedBox(width: 4),
                      Text(
                        roleLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: roleColor,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isDisabled) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Text(
                      'DISABLED',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.red.shade700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
                if (!isSelf && role != 'admin') ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Change Role
                      GestureDetector(
                        onTap: onChangeRole,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFFA726), Color(0xFFFF7043)],
                            ),
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFFFF7043,
                                ).withValues(alpha: 0.3),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Text(
                            'Role',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      // Disable / Enable
                      GestureDetector(
                        onTap: onToggleDisable,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isDisabled
                                ? Colors.green.shade600
                                : Colors.orange.shade700,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            isDisabled ? Icons.lock_open : Icons.block,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      // Delete
                      GestureDetector(
                        onTap: onDelete,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.shade600,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.delete_outline,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
