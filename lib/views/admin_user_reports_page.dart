import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// Admin page to review, respond to, and resolve user-submitted bug/problem
/// reports. Reads from the `userReports` Firestore collection.
class AdminUserReportsPage extends StatefulWidget {
  const AdminUserReportsPage({super.key});

  @override
  State<AdminUserReportsPage> createState() => _AdminUserReportsPageState();
}

class _AdminUserReportsPageState extends State<AdminUserReportsPage> {
  String _statusFilter = 'all'; // all | open | in_progress | resolved | closed

  static const _statusOptions = [
    'all',
    'open',
    'in_progress',
    'resolved',
    'closed',
  ];

  // ── Style helpers ─────────────────────────────────────────────────────────

  Color _statusColor(String status) {
    switch (status) {
      case 'open':
        return Colors.orange;
      case 'in_progress':
        return Colors.blue;
      case 'resolved':
        return Colors.green;
      case 'closed':
        return Colors.grey;
      default:
        return Colors.orange;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'open':
        return Icons.fiber_new_rounded;
      case 'in_progress':
        return Icons.hourglass_top_rounded;
      case 'resolved':
        return Icons.check_circle_outline;
      case 'closed':
        return Icons.cancel_outlined;
      default:
        return Icons.fiber_new_rounded;
    }
  }

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'bug':
        return Icons.bug_report_outlined;
      case 'content_issue':
        return Icons.report_gmailerrorred_outlined;
      case 'account_problem':
        return Icons.manage_accounts_outlined;
      case 'feature_request':
        return Icons.lightbulb_outline;
      default:
        return Icons.help_outline;
    }
  }

  String _formatTs(dynamic ts) {
    if (ts == null) return '—';
    DateTime dt;
    if (ts is Timestamp) {
      dt = ts.toDate();
    } else {
      return ts.toString();
    }
    return DateFormat('MMM d, yyyy  HH:mm').format(dt.toLocal());
  }

  // ── Firestore query ───────────────────────────────────────────────────────

  Query<Map<String, dynamic>> get _query {
    return FirebaseFirestore.instance
        .collection('userReports')
        .orderBy('createdAt', descending: true)
        .limit(200);
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _applyFilters(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    if (_statusFilter == 'all') return docs;
    return docs.where((doc) {
      final data = doc.data();
      return data['status'] == _statusFilter;
    }).toList();
  }

  // ── Status update ─────────────────────────────────────────────────────────

  Future<void> _updateStatus(String docId, String newStatus) async {
    await FirebaseFirestore.instance
        .collection('userReports')
        .doc(docId)
        .update({
          'status': newStatus,
          'updatedAt': FieldValue.serverTimestamp(),
        });
  }

  // ── Admin reply ───────────────────────────────────────────────────────────

  Future<void> _showReplyDialog(String docId, String? existingReply) async {
    final controller = TextEditingController(text: existingReply ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.reply_rounded, color: Colors.deepOrange),
                    SizedBox(width: 8),
                    Text(
                      'Admin Response',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  maxLines: 5,
                  decoration: InputDecoration(
                    hintText: 'Write your response...',
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        final text = controller.text.trim();
                        if (text.isNotEmpty) Navigator.pop(ctx, text);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepOrange,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Send'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    controller.dispose();

    if (result != null && result.isNotEmpty) {
      await FirebaseFirestore.instance
          .collection('userReports')
          .doc(docId)
          .update({
            'adminReply': result,
            'repliedAt': FieldValue.serverTimestamp(),
            if (existingReply == null || existingReply.isEmpty)
              'status': 'in_progress',
          });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF7F8FC),
      child: Column(
        children: [
          // ── Filter bar ──────────────────────────────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                const Text(
                  'Status:',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _statusOptions.map((s) {
                        final selected = s == _statusFilter;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: GestureDetector(
                            onTap: () => setState(() => _statusFilter = s),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: selected
                                    ? _statusColor(s == 'all' ? 'open' : s)
                                    : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                s == 'all'
                                    ? 'ALL'
                                    : s.replaceAll('_', ' ').toUpperCase(),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: selected
                                      ? Colors.white
                                      : Colors.black87,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // ── Report list ─────────────────────────────────────────────────
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _query.snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Failed to load reports.\n${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red),
                    ),
                  );
                }

                final docs = _applyFilters(snapshot.data?.docs ?? []);
                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inbox_outlined,
                          size: 52,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No user reports found',
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final doc = docs[i];
                    final data = doc.data();
                    return _ReportCard(
                      docId: doc.id,
                      data: data,
                      statusColor: _statusColor,
                      statusIcon: _statusIcon,
                      categoryIcon: _categoryIcon,
                      formatTs: _formatTs,
                      onUpdateStatus: _updateStatus,
                      onReply: _showReplyDialog,
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

// ─── Single report card ───────────────────────────────────────────────────────

class _ReportCard extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> data;
  final Color Function(String) statusColor;
  final IconData Function(String) statusIcon;
  final IconData Function(String) categoryIcon;
  final String Function(dynamic) formatTs;
  final Future<void> Function(String, String) onUpdateStatus;
  final Future<void> Function(String, String?) onReply;

  const _ReportCard({
    required this.docId,
    required this.data,
    required this.statusColor,
    required this.statusIcon,
    required this.categoryIcon,
    required this.formatTs,
    required this.onUpdateStatus,
    required this.onReply,
  });

  @override
  State<_ReportCard> createState() => _ReportCardState();
}

class _ReportCardState extends State<_ReportCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final status = d['status'] as String? ?? 'open';
    final category = d['category'] as String? ?? 'other';
    final subject = d['subject'] as String? ?? '(no subject)';
    final description = d['description'] as String? ?? '';
    final userName = d['userName'] as String? ?? 'Unknown';
    final userEmail = d['userEmail'] as String? ?? '';
    final adminReply = d['adminReply'] as String? ?? '';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: widget.statusColor(status).withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  // Category icon
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: widget.statusColor(status).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      widget.categoryIcon(category),
                      color: widget.statusColor(status),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            // Status badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: widget.statusColor(status),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    widget.statusIcon(status),
                                    color: Colors.white,
                                    size: 12,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    status.replaceAll('_', ' ').toUpperCase(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Category badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                category.replaceAll('_', ' ').toUpperCase(),
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subject,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$userName  •  ${widget.formatTs(d['createdAt'])}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: Colors.grey,
                  ),
                ],
              ),
            ),
          ),

          // ── Expanded details ──────────────────────────────────────────
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // User info
                  if (userEmail.isNotEmpty)
                    _InfoRow(
                      icon: Icons.email_outlined,
                      label: 'Email',
                      value: userEmail,
                    ),
                  _InfoRow(
                    icon: Icons.person_outline,
                    label: 'User',
                    value: userName,
                  ),
                  const SizedBox(height: 10),

                  // Description
                  const Text(
                    'Description',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Text(
                      description.isEmpty ? '(no description)' : description,
                      style: const TextStyle(fontSize: 13, height: 1.5),
                    ),
                  ),

                  // Admin reply (if any)
                  if (adminReply.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Admin Response',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: Colors.deepOrange,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Text(
                        adminReply,
                        style: const TextStyle(fontSize: 13, height: 1.5),
                      ),
                    ),
                  ],

                  const SizedBox(height: 14),

                  // Action buttons
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      // Reply
                      _ActionButton(
                        icon: Icons.reply_rounded,
                        label: adminReply.isEmpty ? 'Reply' : 'Edit Reply',
                        color: Colors.blue,
                        onTap: () => widget.onReply(
                          widget.docId,
                          adminReply.isEmpty ? null : adminReply,
                        ),
                      ),
                      // Mark In Progress
                      if (status == 'open')
                        _ActionButton(
                          icon: Icons.hourglass_top_rounded,
                          label: 'In Progress',
                          color: Colors.blue,
                          onTap: () => widget.onUpdateStatus(
                            widget.docId,
                            'in_progress',
                          ),
                        ),
                      // Mark Resolved
                      if (status != 'resolved' && status != 'closed')
                        _ActionButton(
                          icon: Icons.check_circle_outline,
                          label: 'Resolve',
                          color: Colors.green,
                          onTap: () =>
                              widget.onUpdateStatus(widget.docId, 'resolved'),
                        ),
                      // Close
                      if (status != 'closed')
                        _ActionButton(
                          icon: Icons.cancel_outlined,
                          label: 'Close',
                          color: Colors.grey,
                          onTap: () =>
                              widget.onUpdateStatus(widget.docId, 'closed'),
                        ),
                      // Reopen
                      if (status == 'resolved' || status == 'closed')
                        _ActionButton(
                          icon: Icons.refresh_rounded,
                          label: 'Reopen',
                          color: Colors.orange,
                          onTap: () =>
                              widget.onUpdateStatus(widget.docId, 'open'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Small helpers ─────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.grey),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.black54,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
