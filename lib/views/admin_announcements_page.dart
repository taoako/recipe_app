import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/app_logger.dart';

/// Send a global push notification to all users (or a specific role)
/// by writing to each user's `notifications/{uid}/items` sub-collection.
class AdminAnnouncementsPage extends StatefulWidget {
  const AdminAnnouncementsPage({super.key});

  @override
  State<AdminAnnouncementsPage> createState() => _AdminAnnouncementsPageState();
}

class _AdminAnnouncementsPageState extends State<AdminAnnouncementsPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();

  String _targetAudience = 'all'; // all | user | moderator | editor
  bool _sending = false;
  String? _lastResult;
  bool _lastSuccess = false;

  static const _audiences = [
    ('all', 'Everyone', Icons.public),
    ('user', 'Regular Users', Icons.person_outline),
    ('moderator', 'Moderators', Icons.shield_outlined),
    ('editor', 'Editors', Icons.edit_outlined),
  ];

  static const _gradient = LinearGradient(
    colors: [Color(0xFFFFA726), Color(0xFFFF7043)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendAnnouncement() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _sending = true;
      _lastResult = null;
    });

    try {
      final admin = FirebaseAuth.instance.currentUser;
      final adminId = admin?.uid ?? '';
      final adminName = admin?.displayName ?? 'Admin';
      final adminPhoto = admin?.photoURL ?? '';

      final db = FirebaseFirestore.instance;
      final title = _titleCtrl.text.trim();
      final body = _bodyCtrl.text.trim();

      // Fetch target users
      Query<Map<String, dynamic>> usersQuery = db.collection('users');
      if (_targetAudience != 'all') {
        usersQuery = usersQuery.where('role', isEqualTo: _targetAudience);
      }
      final usersSnap = await usersQuery.get();

      if (usersSnap.docs.isEmpty) {
        setState(() {
          _sending = false;
          _lastSuccess = false;
          _lastResult = 'No users matched the selected audience.';
        });
        return;
      }

      // Write in batches of 500 (Firestore limit)
      final batch = db.batch();
      int count = 0;
      var batchCount = 0;

      for (final userDoc in usersSnap.docs) {
        final uid = userDoc.id;
        if (uid == adminId) continue; // skip self

        final notifRef = db
            .collection('notifications')
            .doc(uid)
            .collection('items')
            .doc();

        batch.set(notifRef, {
          'type': 'announcement',
          'fromUserId': adminId,
          'fromUsername': adminName,
          'fromUserImage': adminPhoto,
          'title': title,
          'message': body,
          'createdAt': FieldValue.serverTimestamp(),
          'isRead': false,
        });

        count++;
        batchCount++;

        // Flush batch every 400 writes to stay under limit
        if (batchCount >= 400) {
          await batch.commit();
          batchCount = 0;
        }
      }

      if (batchCount > 0) await batch.commit();

      // Log admin action
      await AppLogger.logInfo(
        LogEvent.adminAction,
        'Global announcement sent: $title',
        metadata: {
          'action': 'send_announcement',
          'audience': _targetAudience,
          'recipientCount': count,
          'title': title,
        },
      );

      if (!mounted) return;
      setState(() {
        _sending = false;
        _lastSuccess = true;
        _lastResult = 'Announcement sent to $count users!';
      });

      _titleCtrl.clear();
      _bodyCtrl.clear();
    } catch (e) {
      if (!mounted) return;
      AppLogger.error('Failed to send announcement', e);
      setState(() {
        _sending = false;
        _lastSuccess = false;
        _lastResult = 'Error: ${e.toString()}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header card ─────────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: _gradient,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF7043).withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.campaign_outlined,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Global Announcements',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'Push notifications to all users',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Compose form ─────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Compose Announcement',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2D2D2D),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Title
                    TextFormField(
                      controller: _titleCtrl,
                      decoration: _inputDecoration(
                        label: 'Title',
                        hint: 'e.g. System Maintenance Scheduled',
                        icon: Icons.title,
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 14),

                    // Body
                    TextFormField(
                      controller: _bodyCtrl,
                      maxLines: 4,
                      maxLength: 500,
                      decoration: _inputDecoration(
                        label: 'Message',
                        hint:
                            'e.g. The app will be down for maintenance from 2–4 AM...',
                        icon: Icons.message_outlined,
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),

                    // Audience selector
                    const Text(
                      'Target Audience',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF555555),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _audiences.map((a) {
                        final selected = _targetAudience == a.$1;
                        return GestureDetector(
                          onTap: () => setState(() => _targetAudience = a.$1),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: selected
                                  ? const Color(0xFFFF7043)
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: selected
                                    ? const Color(0xFFFF7043)
                                    : Colors.grey.shade300,
                              ),
                              boxShadow: selected
                                  ? [
                                      BoxShadow(
                                        color: const Color(
                                          0xFFFF7043,
                                        ).withValues(alpha: 0.3),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : [],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  a.$3,
                                  size: 14,
                                  color: selected
                                      ? Colors.white
                                      : Colors.grey.shade600,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  a.$2,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: selected
                                        ? Colors.white
                                        : Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),

                    // Send button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: _sending ? null : _sendAnnouncement,
                        icon: _sending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.send_rounded),
                        label: Text(
                          _sending ? 'Sending...' : 'Send Announcement',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF7043),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(
                            0xFFFF7043,
                          ).withValues(alpha: 0.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 4,
                          shadowColor: const Color(
                            0xFFFF7043,
                          ).withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Result banner ────────────────────────────────────────────────
            if (_lastResult != null) ...[
              const SizedBox(height: 16),
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _lastSuccess
                      ? Colors.green.shade50
                      : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _lastSuccess
                        ? Colors.green.shade200
                        : Colors.red.shade200,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _lastSuccess
                          ? Icons.check_circle_outline
                          : Icons.error_outline,
                      color: _lastSuccess
                          ? Colors.green.shade600
                          : Colors.red.shade600,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _lastResult!,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _lastSuccess
                              ? Colors.green.shade700
                              : Colors.red.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 28),

            // ── Guidelines card ──────────────────────────────────────────────
            _GuidelinesCard(),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, color: const Color(0xFFFF7043)),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFFF7043), width: 2),
      ),
      filled: true,
      fillColor: Colors.grey.shade50,
    );
  }
}

class _GuidelinesCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline, color: Colors.orange.shade700),
              const SizedBox(width: 8),
              Text(
                'Announcement Guidelines',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.orange.shade800,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...[
            'Keep messages concise and clear.',
            'Avoid sending too frequently — users may disable notifications.',
            'Use "Everyone" for app-wide updates (maintenance, launches).',
            'Use role-specific targeting for relevant feature updates.',
          ].map(
            (tip) => Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.circle, size: 6, color: Colors.orange.shade600),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tip,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.orange.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
