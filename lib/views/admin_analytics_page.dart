import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../services/app_logger.dart';

/// Analytics + System Health dashboard for admins.
/// Reads from both `recipes`, `users`, `recipeAppeals`, and `app_logs`.
class AdminAnalyticsPage extends StatefulWidget {
  const AdminAnalyticsPage({super.key});

  @override
  State<AdminAnalyticsPage> createState() => _AdminAnalyticsPageState();
}

class _AdminAnalyticsPageState extends State<AdminAnalyticsPage> {
  bool _loading = true;
  String? _error;

  // ── Stat values ─────────────────────────────────────────────────────────────
  int _totalRecipes = 0;
  int _hiddenRecipes = 0;
  int _archivedRecipes = 0;
  int _totalUsers = 0;
  int _pendingAppeals = 0;
  int _pendingReports = 0;
  int _loginEventsToday = 0;
  int _newSignupsThisWeek = 0;
  int _errorsToday = 0;

  // ── Recent errors ────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _recentErrors = [];

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final weekTs = Timestamp.fromDate(now.subtract(const Duration(days: 7)));

      final db = FirebaseFirestore.instance;

      // Single-field count queries (no composite index needed) ─────────────
      final results = await Future.wait([
        // 0: total recipes
        db.collection('recipes').count().get(),
        // 1: hidden recipes (single equality — no composite index)
        db
            .collection('recipes')
            .where('isHidden', isEqualTo: true)
            .count()
            .get(),
        // 2: archived recipes (single equality)
        db
            .collection('recipes')
            .where('isArchived', isEqualTo: true)
            .count()
            .get(),
        // 3: total users
        db.collection('users').count().get(),
        // 4: pending appeals (single equality)
        db
            .collection('recipeAppeals')
            .where('status', isEqualTo: 'pending')
            .count()
            .get(),
        // 5: pending post reports (single equality)
        db
            .collection('postReports')
            .where('status', isEqualTo: 'pending')
            .count()
            .get(),
      ]);

      // Single time-range query on app_logs — avoids ALL composite indexes.
      // We query only by timestamp (single field) and filter client-side.
      final weekLogsSnap = await db
          .collection('app_logs')
          .where('timestamp', isGreaterThanOrEqualTo: weekTs)
          .orderBy('timestamp', descending: true)
          .limit(500)
          .get();

      final weekDocs = weekLogsSnap.docs.map((d) => d.data()).toList();

      int loginToday = 0;
      int signupsWeek = 0;
      int errorsToday = 0;
      final List<Map<String, dynamic>> recentErrors = [];

      for (final doc in weekDocs) {
        final ts = doc['timestamp'];
        final DateTime? dt = ts is Timestamp ? ts.toDate().toLocal() : null;
        final isToday = dt != null && !dt.isBefore(todayStart);

        if (doc['event'] == LogEvent.loginSuccess && isToday) loginToday++;
        if (doc['event'] == LogEvent.signupSuccess) signupsWeek++;
        if (doc['level'] == LogLevel.error) {
          if (isToday) errorsToday++;
          if (recentErrors.length < 10) recentErrors.add(doc);
        }
      }

      if (!mounted) return;
      setState(() {
        _totalRecipes = results[0].count ?? 0;
        _hiddenRecipes = results[1].count ?? 0;
        _archivedRecipes = results[2].count ?? 0;
        _totalUsers = results[3].count ?? 0;
        _pendingAppeals = results[4].count ?? 0;
        _pendingReports = results[5].count ?? 0;
        _loginEventsToday = loginToday;
        _newSignupsThisWeek = signupsWeek;
        _errorsToday = errorsToday;
        _recentErrors = recentErrors;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _formatTs(dynamic ts) {
    if (ts == null) return '—';
    if (ts is Timestamp) {
      return DateFormat('MMM d, HH:mm').format(ts.toDate().toLocal());
    }
    return ts.toString();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF7F8FC),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.cloud_off, size: 54, color: Colors.grey),
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _loadStats,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF7043),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              color: const Color(0xFFFF7043),
              onRefresh: _loadStats,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // ── Section: Content ──────────────────────────────────
                  _SectionHeader(
                    icon: Icons.restaurant_menu,
                    title: 'Content Overview',
                  ),
                  const SizedBox(height: 12),
                  _StatsGrid(
                    cards: [
                      _StatCard(
                        label: 'Total Recipes',
                        value: _totalRecipes,
                        icon: Icons.menu_book_outlined,
                        color: const Color(0xFFFF7043),
                      ),
                      _StatCard(
                        label: 'Hidden',
                        value: _hiddenRecipes,
                        icon: Icons.visibility_off_outlined,
                        color: Colors.orange.shade600,
                      ),
                      _StatCard(
                        label: 'Archived',
                        value: _archivedRecipes,
                        icon: Icons.archive_outlined,
                        color: Colors.blueGrey,
                      ),
                      _StatCard(
                        label: 'Pending Appeals',
                        value: _pendingAppeals,
                        icon: Icons.flag_outlined,
                        color: _pendingAppeals > 0
                            ? Colors.red.shade600
                            : Colors.green,
                      ),
                      _StatCard(
                        label: 'Reported Posts',
                        value: _pendingReports,
                        icon: Icons.report_outlined,
                        color: _pendingReports > 0
                            ? Colors.deepOrange.shade700
                            : Colors.green,
                      ),
                    ],
                  ),

                  const SizedBox(height: 28),

                  // ── Section: Users ────────────────────────────────────
                  _SectionHeader(
                    icon: Icons.people_outline,
                    title: 'User Activity',
                  ),
                  const SizedBox(height: 12),
                  _StatsGrid(
                    cards: [
                      _StatCard(
                        label: 'Total Users',
                        value: _totalUsers,
                        icon: Icons.group_outlined,
                        color: Colors.indigo,
                      ),
                      _StatCard(
                        label: 'Active Sessions\nToday',
                        value: _loginEventsToday,
                        icon: Icons.login_outlined,
                        color: Colors.teal,
                      ),
                      _StatCard(
                        label: 'New Sign-ups\nThis Week',
                        value: _newSignupsThisWeek,
                        icon: Icons.person_add_outlined,
                        color: Colors.green.shade600,
                      ),
                      _StatCard(
                        label: 'Errors Today',
                        value: _errorsToday,
                        icon: Icons.error_outline,
                        color: _errorsToday > 0
                            ? Colors.red.shade700
                            : Colors.green,
                      ),
                    ],
                  ),

                  const SizedBox(height: 28),

                  // ── Section: Recent Errors ────────────────────────────
                  _SectionHeader(
                    icon: Icons.bug_report_outlined,
                    title: 'Recent Errors',
                  ),
                  const SizedBox(height: 12),

                  if (_recentErrors.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            color: Colors.green.shade600,
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'No errors logged — system healthy!',
                            style: TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ...(_recentErrors.map(
                      (e) => _ErrorLogCard(data: e, formatTs: _formatTs),
                    )),

                  const SizedBox(height: 32),

                  // ── Refresh note ──────────────────────────────────────
                  Center(
                    child: Text(
                      'Pull down to refresh • Last updated ${DateFormat('HH:mm:ss').format(DateTime.now())}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
    );
  }
}

// ── Reusable widgets ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFFA726), Color(0xFFFF7043)],
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Color(0xFF2D2D2D),
          ),
        ),
      ],
    );
  }
}

class _StatsGrid extends StatelessWidget {
  final List<_StatCard> cards;
  const _StatsGrid({required this.cards});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.7,
      children: cards,
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    value.toString(),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.black54,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorLogCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String Function(dynamic) formatTs;

  const _ErrorLogCard({required this.data, required this.formatTs});

  @override
  Widget build(BuildContext context) {
    final event = data['event'] as String? ?? '';
    final message = data['message'] as String? ?? '';
    final ts = data['timestamp'];
    final userId = data['userId'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.error_outline,
              color: Colors.red.shade600,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        event.replaceAll('_', ' ').toUpperCase(),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade700,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      formatTs(ts),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black38,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                ),
                if (userId.isNotEmpty)
                  Text(
                    'UID: $userId',
                    style: const TextStyle(fontSize: 10, color: Colors.black38),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
