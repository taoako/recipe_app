import 'dart:async' show unawaited;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../services/report_service.dart';
import 'recipe_detail_page.dart';
import '../model/recipe.dart';

/// Moderator view — shows only reported posts for review.
/// Moderators do NOT see all posts; they only see flagged ones.
class ModeratorReportsTab extends StatefulWidget {
  const ModeratorReportsTab({super.key});

  @override
  State<ModeratorReportsTab> createState() => _ModeratorReportsTabState();
}

class _ModeratorReportsTabState extends State<ModeratorReportsTab>
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Tab bar
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _tab,
            labelColor: const Color(0xFFFF7043),
            unselectedLabelColor: Colors.grey,
            indicatorColor: const Color(0xFFFF7043),
            tabs: const [
              Tab(icon: Icon(Icons.report_outlined), text: 'Pending'),
              Tab(icon: Icon(Icons.history_outlined), text: 'Reviewed'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: const [
              _ReportsListView(statusFilter: 'pending'),
              _ReportsListView(statusFilter: 'reviewed'),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Report list ───────────────────────────────────────────────────────────────

class _ReportsListView extends StatelessWidget {
  const _ReportsListView({required this.statusFilter});
  final String statusFilter; // 'pending' | 'reviewed'

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;

    // Fetch all reports ordered by createdAt, filter status client-side
    // to avoid compound queries that require composite indexes.
    final query = db
        .collection('postReports')
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
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () {
                      (ctx as Element).markNeedsBuild();
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF7043),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // Client-side filter by status
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
                      ? Icons.verified_outlined
                      : Icons.inbox_outlined,
                  size: 64,
                  color: Colors.grey.shade300,
                ),
                const SizedBox(height: 12),
                Text(
                  statusFilter == 'pending'
                      ? 'No pending reports'
                      : 'No reviewed reports yet',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  statusFilter == 'pending'
                      ? 'Everything looks clean!'
                      : 'Resolved reports will appear here.',
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
            final doc = docs[i];
            return _ReportCard(doc: doc, isPending: statusFilter == 'pending');
          },
        );
      },
    );
  }
}

// ── Individual Report Card ────────────────────────────────────────────────────

class _ReportCard extends StatefulWidget {
  const _ReportCard({required this.doc, required this.isPending});
  final DocumentSnapshot doc;
  final bool isPending;

  @override
  State<_ReportCard> createState() => _ReportCardState();
}

class _ReportCardState extends State<_ReportCard> {
  bool _acting = false;
  bool _expanded = false;
  Map<String, dynamic>? _recipeData;
  bool _loadingRecipe = false;

  String _formatTs(dynamic ts) {
    if (ts == null) return '—';
    if (ts is Timestamp) {
      return DateFormat('MMM d, HH:mm').format(ts.toDate().toLocal());
    }
    return ts.toString();
  }

  Color _statusColor(String? status) => switch (status) {
    'reviewed_valid' => Colors.green.shade600,
    'reviewed_dismissed' => Colors.grey,
    _ => Colors.orange.shade700,
  };

  String _statusLabel(String? status) => switch (status) {
    'reviewed_valid' => 'ACTION TAKEN',
    'reviewed_dismissed' => 'DISMISSED',
    _ => 'PENDING',
  };

  Future<void> _loadRecipeContent(String postId) async {
    if (_recipeData != null || _loadingRecipe || postId.isEmpty) return;
    setState(() => _loadingRecipe = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('recipes')
          .doc(postId)
          .get();
      if (snap.exists && mounted) {
        setState(() => _recipeData = snap.data()!..['id'] = snap.id);
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingRecipe = false);
  }

  Future<void> _handleAction({required bool hidePost}) async {
    if (_acting) return;
    setState(() => _acting = true);
    try {
      await ReportService.resolveReport(
        reportId: widget.doc.id,
        postId: (widget.doc.data() as Map<String, dynamic>)['postId'] ?? '',
        hidePost: hidePost,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              hidePost
                  ? 'Post hidden and report marked as valid.'
                  : 'Report dismissed.',
            ),
            backgroundColor: hidePost
                ? Colors.red.shade700
                : Colors.grey.shade700,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _viewPost(Map<String, dynamic> data) async {
    final postId = data['postId'] ?? '';
    if (postId.isEmpty) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('recipes')
          .doc(postId)
          .get();
      if (!snap.exists || !mounted) return;
      final recipeData = snap.data()!..['id'] = snap.id;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RecipeDetailPage(recipe: Recipe.fromJson(recipeData)),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not load post: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.doc.data() as Map<String, dynamic>;
    final status = data['status'] as String?;
    final isPending = widget.isPending;
    final coverUrl = data['postCoverImage'] as String? ?? '';
    final postId = data['postId'] as String? ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isPending ? 2 : 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: isPending ? Colors.white : Colors.grey.shade50,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: image + title + status badge
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: coverUrl.isNotEmpty
                      ? Image.network(
                          coverUrl,
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 64,
                            height: 64,
                            color: Colors.grey.shade200,
                            child: const Icon(
                              Icons.restaurant,
                              color: Colors.grey,
                            ),
                          ),
                        )
                      : Container(
                          width: 64,
                          height: 64,
                          color: Colors.grey.shade200,
                          child: const Icon(
                            Icons.restaurant,
                            color: Colors.grey,
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data['postTitle'] ?? '(Untitled)',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'by ${data['postAuthorName'] ?? '—'}',
                        style: const TextStyle(
                          fontSize: 12,
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
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.report_outlined,
                    size: 14,
                    color: Color(0xFFFF7043),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    ReportReason.label(data['reason'] ?? 'other'),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFFF7043),
                    ),
                  ),
                ],
              ),
            ),
            if ((data['description'] ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                data['description'],
                style: const TextStyle(fontSize: 13, color: Colors.black87),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.person_outline, size: 13, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  'Reported by ${data['reporterName'] ?? '—'}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const Spacer(),
                Text(
                  _formatTs(data['createdAt']),
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),

            // ── Expandable post content preview ────────────────────────────
            const SizedBox(height: 10),
            InkWell(
              onTap: () {
                setState(() => _expanded = !_expanded);
                if (_expanded) _loadRecipeContent(postId);
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade100),
                ),
                child: Row(
                  children: [
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: Colors.blue.shade700,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _expanded ? 'Hide Post Content' : 'View Post Content',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded) ...[
              const SizedBox(height: 10),
              if (_loadingRecipe)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (_recipeData != null)
                _PostContentPreview(recipe: _recipeData!)
              else
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Center(
                    child: Text(
                      'Post not found or has been deleted.',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ),
                ),
            ],

            if (isPending) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),
              Row(
                children: [
                  // View Full Post (opens detail page)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.open_in_new, size: 14),
                    label: const Text('Open Post'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blueGrey,
                      side: BorderSide(color: Colors.blueGrey.shade300),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    onPressed: () => unawaited(_viewPost(data)),
                  ),
                  const Spacer(),
                  // Dismiss
                  OutlinedButton(
                    onPressed: _acting
                        ? null
                        : () => _handleAction(hidePost: false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey.shade700,
                      side: BorderSide(color: Colors.grey.shade400),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    child: const Text('Dismiss'),
                  ),
                  const SizedBox(width: 8),
                  // Hide Post
                  ElevatedButton.icon(
                    icon: _acting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.visibility_off_outlined, size: 14),
                    label: const Text('Hide Post'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    onPressed: _acting
                        ? null
                        : () => _handleAction(hidePost: true),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 8),
              if ((data['reviewNote'] ?? '').isNotEmpty)
                Text(
                  'Note: ${data['reviewNote']}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              if (data['reviewedByName'] != null)
                Text(
                  'Reviewed by ${data['reviewedByName']} · ${_formatTs(data['reviewedAt'])}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Inline post content preview (shown inside report card) ────────────────────

class _PostContentPreview extends StatelessWidget {
  const _PostContentPreview({required this.recipe});
  final Map<String, dynamic> recipe;

  @override
  Widget build(BuildContext context) {
    final title = recipe['title'] ?? '';
    final description = recipe['description'] ?? '';
    final coverUrl = recipe['coverImageUrl'] ?? recipe['coverImage'] ?? '';
    final category = recipe['category'] ?? '';
    final duration = recipe['cookingDuration'];
    final ingredients = (recipe['ingredients'] as List<dynamic>?) ?? [];
    final steps = (recipe['steps'] as List<dynamic>?) ?? [];
    final isHidden = recipe['isHidden'] == true;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cover image
          if (coverUrl.isNotEmpty)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
              child: Image.network(
                coverUrl,
                width: double.infinity,
                height: 180,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 180,
                  color: Colors.grey.shade200,
                  child: const Center(
                    child: Icon(
                      Icons.broken_image,
                      size: 40,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Hidden badge
                if (isHidden)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.visibility_off,
                          size: 12,
                          color: Colors.red.shade600,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'HIDDEN',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),

                // Title
                if (title.isNotEmpty)
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2D2D2D),
                    ),
                  ),
                const SizedBox(height: 6),

                // Category & duration row
                if (category.isNotEmpty || duration != null)
                  Row(
                    children: [
                      if (category.isNotEmpty) ...[
                        Icon(
                          Icons.restaurant_menu,
                          size: 13,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          category,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      if (duration != null && duration > 0) ...[
                        Icon(
                          Icons.timer_outlined,
                          size: 13,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$duration min',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ],
                  ),
                if (category.isNotEmpty || duration != null)
                  const SizedBox(height: 10),

                // Description
                if (description.isNotEmpty) ...[
                  const Text(
                    'Description',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: Color(0xFF555555),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(fontSize: 13, color: Colors.black87),
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                ],

                // Ingredients
                if (ingredients.isNotEmpty) ...[
                  const Text(
                    'Ingredients',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: Color(0xFF555555),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: ingredients.take(10).map<Widget>((ing) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade100),
                        ),
                        child: Text(
                          ing.toString(),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.orange.shade800,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  if (ingredients.length > 10)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '+${ingredients.length - 10} more',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                ],

                // Steps
                if (steps.isNotEmpty) ...[
                  const Text(
                    'Steps',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: Color(0xFF555555),
                    ),
                  ),
                  const SizedBox(height: 4),
                  ...steps.take(5).toList().asMap().entries.map((entry) {
                    final step = entry.value;
                    final desc = step is Map
                        ? (step['description'] ?? step['text'] ?? '').toString()
                        : step.toString();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 20,
                            height: 20,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF7043),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${entry.key + 1}',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              desc,
                              style: const TextStyle(fontSize: 12),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  if (steps.length > 5)
                    Text(
                      '+${steps.length - 5} more steps',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
