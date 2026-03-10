import 'dart:async' show unawaited;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../services/app_logger.dart';

/// Moderator view for reviewing user recipe appeals.
/// Users can appeal hidden posts; moderators can approve (unhide) or reject.
class ModeratorAppealsTab extends StatefulWidget {
  const ModeratorAppealsTab({super.key});

  @override
  State<ModeratorAppealsTab> createState() => _ModeratorAppealsTabState();
}

class _ModeratorAppealsTabState extends State<ModeratorAppealsTab>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  Future<void> _approveAppeal(DocumentSnapshot appealDoc) async {
    final data = appealDoc.data() as Map<String, dynamic>;
    final recipeId = data['recipeId']?.toString() ?? '';
    final authorId = data['authorId']?.toString() ?? '';
    if (recipeId.isEmpty) return;

    final recipeRef = FirebaseFirestore.instance
        .collection('recipes')
        .doc(recipeId);
    final moderator = FirebaseAuth.instance.currentUser;

    try {
      // Unhide the recipe and mark appeal as approved
      final recipeSnap = await recipeRef.get();
      if (!recipeSnap.exists) {
        await appealDoc.reference.update({
          'status': 'invalid',
          'resolvedAt': FieldValue.serverTimestamp(),
          'note': 'Recipe no longer exists',
        });
        if (mounted) _snack('Recipe no longer exists.', Colors.orange);
        return;
      }

      await recipeRef.update({'isHidden': false});
      await appealDoc.reference.update({
        'status': 'approved',
        'resolvedAt': FieldValue.serverTimestamp(),
      });

      // Notify the author
      if (authorId.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('notifications')
            .doc(authorId)
            .collection('items')
            .add({
              'type': 'appeal_approved',
              'fromUserId': moderator?.uid ?? '',
              'fromUsername': moderator?.displayName ?? 'Moderator',
              'fromUserImage': moderator?.photoURL ?? '',
              'recipeId': recipeId,
              'recipeTitle': data['title'] ?? '',
              'recipeImage': data['coverImageUrl'] ?? '',
              'message':
                  'Your appeal for "${data['title'] ?? ''}" was approved. The recipe is now visible again.',
              'createdAt': FieldValue.serverTimestamp(),
            });
      }

      if (mounted) _snack('Appeal approved & recipe unhidden', Colors.green);
      unawaited(
        AppLogger.logInfo(
          LogEvent.adminAction,
          'Moderator approved appeal: ${data['title'] ?? 'untitled'}',
          metadata: {
            'action': 'approve_appeal',
            'recipeId': recipeId,
            'authorId': authorId,
          },
        ),
      );
    } catch (e) {
      if (mounted) _snack('Failed to approve appeal.', Colors.red);
    }
  }

  Future<void> _rejectAppeal(DocumentSnapshot appealDoc) async {
    final data = appealDoc.data() as Map<String, dynamic>;
    final recipeId = data['recipeId']?.toString() ?? '';
    final authorId = data['authorId']?.toString() ?? '';
    final moderator = FirebaseAuth.instance.currentUser;

    try {
      await appealDoc.reference.update({
        'status': 'rejected',
        'resolvedAt': FieldValue.serverTimestamp(),
      });

      if (authorId.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('notifications')
            .doc(authorId)
            .collection('items')
            .add({
              'type': 'appeal_rejected',
              'fromUserId': moderator?.uid ?? '',
              'fromUsername': moderator?.displayName ?? 'Moderator',
              'fromUserImage': moderator?.photoURL ?? '',
              'recipeId': recipeId,
              'recipeTitle': data['title'] ?? '',
              'recipeImage': data['coverImageUrl'] ?? '',
              'message':
                  'Your appeal for "${data['title'] ?? ''}" was rejected.',
              'createdAt': FieldValue.serverTimestamp(),
            });
      }

      if (mounted) _snack('Appeal rejected', Colors.orange);
      unawaited(
        AppLogger.logInfo(
          LogEvent.adminAction,
          'Moderator rejected appeal: ${data['title'] ?? 'untitled'}',
          metadata: {
            'action': 'reject_appeal',
            'recipeId': recipeId,
            'authorId': authorId,
          },
        ),
      );
    } catch (e) {
      if (mounted) _snack('Failed to reject appeal.', Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _tab,
            labelColor: const Color(0xFF6A3DE8),
            unselectedLabelColor: Colors.grey,
            indicatorColor: const Color(0xFF6A3DE8),
            tabs: const [
              Tab(icon: Icon(Icons.pending_actions), text: 'Pending'),
              Tab(icon: Icon(Icons.history_outlined), text: 'Resolved'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _AppealsListView(
                statusFilter: 'pending',
                onApprove: _approveAppeal,
                onReject: _rejectAppeal,
              ),
              _AppealsListView(
                statusFilter: 'resolved',
                onApprove: _approveAppeal,
                onReject: _rejectAppeal,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Appeals list ──────────────────────────────────────────────────────────────

class _AppealsListView extends StatelessWidget {
  const _AppealsListView({
    required this.statusFilter,
    required this.onApprove,
    required this.onReject,
  });

  final String statusFilter; // 'pending' | 'resolved'
  final Future<void> Function(DocumentSnapshot) onApprove;
  final Future<void> Function(DocumentSnapshot) onReject;

  @override
  Widget build(BuildContext context) {
    final query = FirebaseFirestore.instance
        .collection('recipeAppeals')
        .orderBy('createdAt', descending: true)
        .limit(200);

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
                  const SizedBox(height: 8),
                  Text(
                    snap.error.toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
                ],
              ),
            ),
          );
        }

        final allDocs = snap.data!.docs;
        final docs = statusFilter == 'pending'
            ? allDocs.where((d) {
                final s =
                    (d.data() as Map<String, dynamic>)['status'] as String?;
                return s == 'pending';
              }).toList()
            : allDocs.where((d) {
                final s =
                    (d.data() as Map<String, dynamic>)['status'] as String?;
                return s != null && s != 'pending';
              }).toList();

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  statusFilter == 'pending'
                      ? Icons.thumb_up_outlined
                      : Icons.inbox_outlined,
                  size: 64,
                  color: Colors.grey.shade300,
                ),
                const SizedBox(height: 12),
                Text(
                  statusFilter == 'pending'
                      ? 'No pending appeals'
                      : 'No resolved appeals yet',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  statusFilter == 'pending'
                      ? 'All clear!'
                      : 'Resolved appeals will appear here.',
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (ctx, i) {
            return _AppealCard(
              doc: docs[i],
              isPending: statusFilter == 'pending',
              onApprove: onApprove,
              onReject: onReject,
            );
          },
        );
      },
    );
  }
}

// ── Individual Appeal Card ────────────────────────────────────────────────────

class _AppealCard extends StatefulWidget {
  const _AppealCard({
    required this.doc,
    required this.isPending,
    required this.onApprove,
    required this.onReject,
  });

  final DocumentSnapshot doc;
  final bool isPending;
  final Future<void> Function(DocumentSnapshot) onApprove;
  final Future<void> Function(DocumentSnapshot) onReject;

  @override
  State<_AppealCard> createState() => _AppealCardState();
}

class _AppealCardState extends State<_AppealCard> {
  bool _acting = false;

  String _formatTs(dynamic ts) {
    if (ts == null) return '—';
    if (ts is Timestamp) {
      return DateFormat('MMM d, HH:mm').format(ts.toDate().toLocal());
    }
    return ts.toString();
  }

  Color _statusColor(String? status) => switch (status) {
    'approved' => Colors.green.shade600,
    'rejected' => Colors.red.shade600,
    'invalid' => Colors.grey,
    _ => Colors.orange.shade700,
  };

  String _statusLabel(String? status) => switch (status) {
    'approved' => 'APPROVED',
    'rejected' => 'REJECTED',
    'invalid' => 'INVALID',
    _ => 'PENDING',
  };

  Future<void> _handleApprove() async {
    if (_acting) return;
    setState(() => _acting = true);
    try {
      await widget.onApprove(widget.doc);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _handleReject() async {
    if (_acting) return;
    setState(() => _acting = true);
    try {
      await widget.onReject(widget.doc);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.doc.data() as Map<String, dynamic>;
    final status = data['status'] as String?;
    final title = data['title'] ?? '(Untitled)';
    final reason = data['reason'] ?? '—';
    final note = data['note'] as String?;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: widget.isPending ? 2 : 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: widget.isPending ? Colors.white : Colors.grey.shade50,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title + status badge
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6A3DE8).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.gavel_rounded,
                    size: 24,
                    color: Color(0xFF6A3DE8),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatTs(data['createdAt']),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor(status).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _statusLabel(status),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: _statusColor(status),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Reason
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.purple.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.comment_outlined,
                    size: 14,
                    color: Colors.purple.shade400,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      reason,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.purple.shade700,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            if (note != null && note.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Note: $note',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.black54,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],

            if (widget.isPending) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _acting ? null : _handleApprove,
                      icon: _acting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.green,
                              ),
                            )
                          : const Icon(Icons.visibility_outlined, size: 14),
                      label: const Text('Unhide Post'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.green.shade700,
                        side: BorderSide(color: Colors.green.shade400),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _acting ? null : _handleReject,
                      icon: const Icon(Icons.close_rounded, size: 14),
                      label: const Text('Reject'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                        side: BorderSide(color: Colors.red.shade400),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
