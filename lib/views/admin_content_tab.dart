import 'dart:async' show unawaited;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../model/recipe.dart';
import 'recipe_detail_page.dart';
import '../services/app_logger.dart';

/// Recipe moderation + appeals tab for the Admin shell.
class AdminContentTab extends StatefulWidget {
  const AdminContentTab({super.key});

  @override
  State<AdminContentTab> createState() => _AdminContentTabState();
}

class _AdminContentTabState extends State<AdminContentTab>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  bool _showHidden = false;
  bool _viewArchived = false;

  // ── theme colours ──────────────────────────────────────────────────────────
  static const _red = Color(0xFFFF5722);

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

  // ── action methods ─────────────────────────────────────────────────────────

  Future<void> _approveAppeal(DocumentSnapshot appealDoc) async {
    final data = appealDoc.data() as Map<String, dynamic>;
    final recipeId = data['recipeId']?.toString() ?? '';
    final authorId = data['authorId']?.toString() ?? '';
    if (recipeId.isEmpty || authorId.isEmpty) return;

    final recipeRef = FirebaseFirestore.instance
        .collection('recipes')
        .doc(recipeId);
    final appealRef = appealDoc.reference;
    final admin = FirebaseAuth.instance.currentUser;

    try {
      await FirebaseFirestore.instance.runTransaction((txn) async {
        final recipeSnap = await txn.get(recipeRef);
        if (!recipeSnap.exists) {
          txn.update(appealRef, {
            'status': 'invalid',
            'resolvedAt': FieldValue.serverTimestamp(),
            'note': 'Recipe no longer exists',
          });
          return;
        }
        txn.update(recipeRef, {'isHidden': false});
        txn.update(appealRef, {
          'status': 'approved',
          'resolvedAt': FieldValue.serverTimestamp(),
        });
      });

      await FirebaseFirestore.instance
          .collection('notifications')
          .doc(authorId)
          .collection('items')
          .add({
            'type': 'appeal_approved',
            'fromUserId': admin?.uid ?? '',
            'fromUsername': admin?.displayName ?? 'Admin',
            'fromUserImage': admin?.photoURL ?? '',
            'recipeId': recipeId,
            'recipeTitle': data['title'] ?? '',
            'recipeImage': data['coverImageUrl'] ?? '',
            'message':
                'Your appeal for "${data['title'] ?? ''}" was approved. The recipe is now visible again.',
            'createdAt': FieldValue.serverTimestamp(),
          });

      if (mounted) {
        _snack('Appeal approved & recipe unhidden', Colors.green);
      }
      unawaited(
        AppLogger.logInfo(
          LogEvent.adminAction,
          'Appeal approved: ${data['title'] ?? 'untitled'}',
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
    final admin = FirebaseAuth.instance.currentUser;

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
              'fromUserId': admin?.uid ?? '',
              'fromUsername': admin?.displayName ?? 'Admin',
              'fromUserImage': admin?.photoURL ?? '',
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
          'Appeal rejected: ${data['title'] ?? 'untitled'}',
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

  Future<void> _toggleHideRecipe(Recipe recipe) async {
    try {
      final newHidden = !recipe.isHidden;
      await FirebaseFirestore.instance
          .collection('recipes')
          .doc(recipe.id)
          .update({'isHidden': newHidden});

      if (recipe.authorId.isNotEmpty) {
        final admin = FirebaseAuth.instance.currentUser;
        final msg = newHidden
            ? 'Your post "${recipe.title}" has been hidden.'
            : 'Your post "${recipe.title}" has been unhidden.';
        await FirebaseFirestore.instance
            .collection('notifications')
            .doc(recipe.authorId)
            .collection('items')
            .add({
              'type': newHidden ? 'hidden' : 'unhidden',
              'fromUserId': admin?.uid ?? '',
              'fromUsername': admin?.displayName ?? 'Admin',
              'fromUserImage': admin?.photoURL ?? '',
              'recipeId': recipe.id,
              'recipeTitle': recipe.title,
              'recipeImage': recipe.coverImageUrl,
              'message': msg,
              'createdAt': FieldValue.serverTimestamp(),
            });
      }

      if (mounted) {
        _snack(newHidden ? 'Recipe hidden' : 'Recipe unhidden', Colors.green);
      }
      unawaited(
        AppLogger.logInfo(
          LogEvent.adminAction,
          '${newHidden ? 'Recipe hidden' : 'Recipe unhidden'}: ${recipe.title}',
          metadata: {
            'action': newHidden ? 'hide_recipe' : 'unhide_recipe',
            'recipeId': recipe.id,
            'authorId': recipe.authorId,
          },
        ),
      );
    } catch (e) {
      if (mounted) _snack('An error occurred.', Colors.red);
    }
  }

  Future<void> _restoreRecipe(Recipe recipe) async {
    try {
      await FirebaseFirestore.instance
          .collection('recipes')
          .doc(recipe.id)
          .update({'isArchived': false});

      if (recipe.authorId.isNotEmpty) {
        final admin = FirebaseAuth.instance.currentUser;
        await FirebaseFirestore.instance
            .collection('notifications')
            .doc(recipe.authorId)
            .collection('items')
            .add({
              'type': 'unarchived',
              'fromUserId': admin?.uid ?? '',
              'fromUsername': admin?.displayName ?? 'Admin',
              'fromUserImage': admin?.photoURL ?? '',
              'recipeId': recipe.id,
              'recipeTitle': recipe.title,
              'recipeImage': recipe.coverImageUrl,
              'message': 'Your post "${recipe.title}" was restored by admin.',
              'createdAt': FieldValue.serverTimestamp(),
            });
      }

      if (mounted) _snack('Recipe restored', Colors.green);
      unawaited(
        AppLogger.logInfo(
          LogEvent.adminAction,
          'Recipe restored: ${recipe.title}',
          metadata: {
            'action': 'restore_recipe',
            'recipeId': recipe.id,
            'authorId': recipe.authorId,
          },
        ),
      );
    } catch (e) {
      if (mounted) _snack('Failed to restore recipe.', Colors.red);
    }
  }

  Future<void> _deleteOrArchiveRecipe(Recipe recipe) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          recipe.isArchived ? 'Permanently Delete?' : 'Archive Recipe?',
        ),
        content: Text(
          recipe.isArchived
              ? 'This will permanently remove "${recipe.title}". This cannot be undone.'
              : 'Archiving will hide "${recipe.title}" from everyone. You can restore it later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(recipe.isArchived ? 'Delete' : 'Archive'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final admin = FirebaseAuth.instance.currentUser;
      final adminId = admin?.uid ?? '';
      final adminName = admin?.displayName ?? 'Admin';

      if (recipe.isArchived) {
        await FirebaseFirestore.instance
            .collection('recipes')
            .doc(recipe.id)
            .delete();
        if (recipe.authorId.isNotEmpty) {
          await FirebaseFirestore.instance
              .collection('notifications')
              .doc(recipe.authorId)
              .collection('items')
              .add({
                'type': 'deleted_permanent',
                'fromUserId': adminId,
                'fromUsername': adminName,
                'fromUserImage': admin?.photoURL ?? '',
                'recipeId': recipe.id,
                'recipeTitle': recipe.title,
                'recipeImage': recipe.coverImageUrl,
                'message':
                    'Your post "${recipe.title}" was permanently removed.',
                'createdAt': FieldValue.serverTimestamp(),
              });
        }
      } else {
        await FirebaseFirestore.instance
            .collection('recipes')
            .doc(recipe.id)
            .update({'isArchived': true});
        if (recipe.authorId.isNotEmpty) {
          await FirebaseFirestore.instance
              .collection('notifications')
              .doc(recipe.authorId)
              .collection('items')
              .add({
                'type': 'archived',
                'fromUserId': adminId,
                'fromUsername': adminName,
                'fromUserImage': admin?.photoURL ?? '',
                'recipeId': recipe.id,
                'recipeTitle': recipe.title,
                'recipeImage': recipe.coverImageUrl,
                'message': 'Your post "${recipe.title}" was archived by admin.',
                'createdAt': FieldValue.serverTimestamp(),
              });
        }
      }

      if (mounted) {
        _snack(
          recipe.isArchived ? 'Recipe permanently deleted' : 'Recipe archived',
          Colors.green,
        );
      }
      unawaited(
        AppLogger.logInfo(
          LogEvent.adminAction,
          recipe.isArchived
              ? 'Recipe permanently deleted: ${recipe.title}'
              : 'Recipe archived: ${recipe.title}',
          metadata: {
            'action': recipe.isArchived ? 'delete_recipe' : 'archive_recipe',
            'recipeId': recipe.id,
            'authorId': recipe.authorId,
          },
        ),
      );
    } catch (e) {
      if (mounted) _snack('Failed to process recipe.', Colors.red);
    }
  }

  void _snack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Tab bar ──────────────────────────────────────────────────────────
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _tab,
            labelColor: _red,
            unselectedLabelColor: Colors.grey,
            indicatorColor: _red,
            indicatorWeight: 3,
            tabs: const [
              Tab(icon: Icon(Icons.restaurant_menu), text: 'Recipes'),
              Tab(icon: Icon(Icons.flag_outlined), text: 'Appeals'),
            ],
          ),
        ),

        // ── Content switcher ─────────────────────────────────────────────────
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _RecipesView(
                showHidden: _showHidden,
                viewArchived: _viewArchived,
                onToggleHidden: (v) => setState(() => _showHidden = v),
                onToggleArchived: (v) => setState(() => _viewArchived = v),
                onHide: _toggleHideRecipe,
                onArchiveDelete: _deleteOrArchiveRecipe,
                onRestore: _restoreRecipe,
              ),
              _AppealsView(onApprove: _approveAppeal, onReject: _rejectAppeal),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Recipes sub-view
// ═══════════════════════════════════════════════════════════════════════════════

class _RecipesView extends StatelessWidget {
  final bool showHidden;
  final bool viewArchived;
  final ValueChanged<bool> onToggleHidden;
  final ValueChanged<bool> onToggleArchived;
  final Future<void> Function(Recipe) onHide;
  final Future<void> Function(Recipe) onArchiveDelete;
  final Future<void> Function(Recipe) onRestore;

  const _RecipesView({
    required this.showHidden,
    required this.viewArchived,
    required this.onToggleHidden,
    required this.onToggleArchived,
    required this.onHide,
    required this.onArchiveDelete,
    required this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Filter strip
        Container(
          color: Colors.orange.shade50,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              _FilterChipButton(
                label: 'Active',
                selected: !viewArchived && !showHidden,
                onTap: () {
                  onToggleArchived(false);
                  onToggleHidden(false);
                },
              ),
              const SizedBox(width: 8),
              _FilterChipButton(
                label: 'Hidden',
                selected: !viewArchived && showHidden,
                onTap: () {
                  onToggleArchived(false);
                  onToggleHidden(true);
                },
              ),
              const SizedBox(width: 8),
              _FilterChipButton(
                label: 'Archived',
                selected: viewArchived,
                onTap: () {
                  onToggleArchived(true);
                  onToggleHidden(false);
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('recipes')
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }

              final recipes = (snapshot.data?.docs ?? [])
                  .map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    data['id'] = doc.id;
                    return Recipe.fromJson(data);
                  })
                  .where(
                    (r) => viewArchived
                        ? r.isArchived
                        : (!r.isArchived &&
                              (showHidden ? r.isHidden : !r.isHidden)),
                  )
                  .toList();

              if (recipes.isEmpty) {
                return _EmptyState(
                  icon: Icons.restaurant_menu,
                  message: 'No recipes in this view',
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                itemCount: recipes.length,
                itemBuilder: (context, i) => _RecipeCard(
                  recipe: recipes[i],
                  onHide: onHide,
                  onArchiveDelete: onArchiveDelete,
                  onRestore: onRestore,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _RecipeCard extends StatelessWidget {
  final Recipe recipe;
  final Future<void> Function(Recipe) onHide;
  final Future<void> Function(Recipe) onArchiveDelete;
  final Future<void> Function(Recipe) onRestore;

  const _RecipeCard({
    required this.recipe,
    required this.onHide,
    required this.onArchiveDelete,
    required this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => RecipeDetailPage(recipe: recipe)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: recipe.coverImageUrl.isNotEmpty
                    ? Image.network(
                        recipe.coverImageUrl,
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _thumbPlaceholder(),
                      )
                    : _thumbPlaceholder(),
              ),
              const SizedBox(width: 12),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            recipe.title,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: recipe.isHidden
                                  ? Colors.grey
                                  : const Color(0xFF2D2D2D),
                              decoration: recipe.isHidden
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ),
                        if (recipe.isHidden)
                          _Badge('HIDDEN', Colors.orange.shade700),
                        if (recipe.isArchived)
                          _Badge('ARCHIVED', Colors.grey.shade600),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'By ${recipe.authorName} · ${recipe.category}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),

              // Actions
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Color(0xFFFF7043)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                onSelected: (v) {
                  switch (v) {
                    case 'hide':
                    case 'unhide':
                      onHide(recipe);
                      break;
                    case 'archive':
                    case 'delete':
                      onArchiveDelete(recipe);
                      break;
                    case 'restore':
                      onRestore(recipe);
                      break;
                  }
                },
                itemBuilder: (_) => [
                  if (!recipe.isArchived)
                    PopupMenuItem(
                      value: recipe.isHidden ? 'unhide' : 'hide',
                      child: Row(
                        children: [
                          Icon(
                            recipe.isHidden
                                ? Icons.visibility
                                : Icons.visibility_off,
                            size: 18,
                            color: Colors.orange,
                          ),
                          const SizedBox(width: 8),
                          Text(recipe.isHidden ? 'Unhide' : 'Hide'),
                        ],
                      ),
                    ),
                  if (!recipe.isArchived)
                    const PopupMenuItem(
                      value: 'archive',
                      child: Row(
                        children: [
                          Icon(
                            Icons.archive_outlined,
                            size: 18,
                            color: Colors.blueGrey,
                          ),
                          SizedBox(width: 8),
                          Text('Archive'),
                        ],
                      ),
                    ),
                  if (recipe.isArchived) ...[
                    const PopupMenuItem(
                      value: 'restore',
                      child: Row(
                        children: [
                          Icon(Icons.restore, size: 18, color: Colors.green),
                          SizedBox(width: 8),
                          Text('Restore'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_forever,
                            size: 18,
                            color: Colors.red,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Delete Permanently',
                            style: TextStyle(color: Colors.red),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumbPlaceholder() => Container(
    width: 60,
    height: 60,
    decoration: BoxDecoration(
      color: Colors.orange.shade50,
      borderRadius: BorderRadius.circular(10),
    ),
    child: const Icon(Icons.image_not_supported_outlined, color: Colors.orange),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// Appeals sub-view
// ═══════════════════════════════════════════════════════════════════════════════

class _AppealsView extends StatelessWidget {
  final Future<void> Function(DocumentSnapshot) onApprove;
  final Future<void> Function(DocumentSnapshot) onReject;

  const _AppealsView({required this.onApprove, required this.onReject});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('recipeAppeals')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return _EmptyState(
            icon: Icons.flag_outlined,
            message: 'No appeals found',
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: docs.length,
          itemBuilder: (_, i) => _AppealCard(
            doc: docs[i],
            onApprove: onApprove,
            onReject: onReject,
          ),
        );
      },
    );
  }
}

class _AppealCard extends StatelessWidget {
  final DocumentSnapshot doc;
  final Future<void> Function(DocumentSnapshot) onApprove;
  final Future<void> Function(DocumentSnapshot) onReject;

  const _AppealCard({
    required this.doc,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final data = doc.data() as Map<String, dynamic>;
    final status = data['status']?.toString() ?? 'pending';
    final isPending = status == 'pending';

    final badgeColor = switch (status) {
      'approved' => Colors.green,
      'rejected' => Colors.red,
      'invalid' => Colors.grey,
      _ => Colors.orange,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withValues(alpha: 0.10),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    data['title'] ?? '(Untitled)',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _Badge(status.toUpperCase(), badgeColor),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Reason: ${data['reason'] ?? '—'}',
              style: const TextStyle(fontSize: 13, color: Colors.black87),
            ),
            if (data['note'] != null) ...[
              const SizedBox(height: 4),
              Text(
                'Note: ${data['note']}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
            if (isPending) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => onApprove(doc),
                      icon: const Icon(Icons.check_circle_outline, size: 16),
                      label: const Text('Approve'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.green,
                        side: const BorderSide(color: Colors.green),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => onReject(doc),
                      icon: const Icon(Icons.cancel_outlined, size: 16),
                      label: const Text('Reject'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
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

// ── Shared helpers ─────────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChipButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFF7043) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? const Color(0xFFFF7043) : Colors.grey.shade300,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: const Color(0xFFFF7043).withValues(alpha: 0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.orange.shade200),
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(fontSize: 16, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}
