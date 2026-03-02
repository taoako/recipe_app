import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../services/app_logger.dart';

/// Admin-only screen that streams and displays all `app_logs` entries
/// from Firestore in real time, with level and event-type filtering.
class AdminLogsPage extends StatefulWidget {
  const AdminLogsPage({super.key});

  @override
  State<AdminLogsPage> createState() => _AdminLogsPageState();
}

class _AdminLogsPageState extends State<AdminLogsPage> {
  String _levelFilter = 'all'; // all | info | warning | error
  String _eventFilter = 'all'; // all | login_attempt | login_success | ...

  static const _levelOptions = ['all', 'info', 'warning', 'error'];
  static const _eventOptions = [
    'all',
    LogEvent.loginAttempt,
    LogEvent.loginSuccess,
    LogEvent.loginFailure,
    LogEvent.signupSuccess,
    LogEvent.signupFailure,
    LogEvent.accessViolation,
    LogEvent.adminAction,
    LogEvent.userAction,
    LogEvent.systemError,
  ];

  // ── style helpers ──────────────────────────────────────────────────────────

  Color _levelColor(String level) {
    switch (level) {
      case LogLevel.error:
        return Colors.red.shade700;
      case LogLevel.warning:
        return Colors.orange.shade700;
      default:
        return Colors.green.shade700;
    }
  }

  Color _levelBg(String level) {
    switch (level) {
      case LogLevel.error:
        return Colors.red.shade50;
      case LogLevel.warning:
        return Colors.orange.shade50;
      default:
        return Colors.green.shade50;
    }
  }

  IconData _levelIcon(String level) {
    switch (level) {
      case LogLevel.error:
        return Icons.error_outline;
      case LogLevel.warning:
        return Icons.warning_amber_outlined;
      default:
        return Icons.info_outline;
    }
  }

  Color _eventColor(String event) {
    switch (event) {
      case LogEvent.loginSuccess:
      case LogEvent.signupSuccess:
        return Colors.green;
      case LogEvent.loginFailure:
      case LogEvent.signupFailure:
        return Colors.red;
      case LogEvent.accessViolation:
        return Colors.deepOrange;
      case LogEvent.adminAction:
        return Colors.purple;
      case LogEvent.loginAttempt:
        return Colors.blue;
      default:
        return Colors.grey;
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
    return DateFormat('MMM d, yyyy  HH:mm:ss').format(dt.toLocal());
  }

  // ── Firestore query ─────────────────────────────────────────────────────────

  Query<Map<String, dynamic>> get _query {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('app_logs')
        .orderBy('timestamp', descending: true)
        .limit(200);

    if (_levelFilter != 'all') {
      q = q.where('level', isEqualTo: _levelFilter);
    }
    if (_eventFilter != 'all') {
      q = q.where('event', isEqualTo: _eventFilter);
    }
    return q;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 6,
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFFA726), Color(0xFFFF7043)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: const Text(
          'System Logs',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // ── Filter bar ─────────────────────────────────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                const Text(
                  'Level:',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: DropdownButton<String>(
                    value: _levelFilter,
                    isDense: true,
                    underline: const SizedBox(),
                    items: _levelOptions
                        .map(
                          (l) => DropdownMenuItem(
                            value: l,
                            child: Text(
                              l.toUpperCase(),
                              style: TextStyle(
                                fontSize: 12,
                                color: l == 'all'
                                    ? Colors.black
                                    : _levelColor(l),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _levelFilter = v);
                    },
                  ),
                ),
                const SizedBox(width: 14),
                const Text(
                  'Event:',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(width: 6),
                Flexible(
                  flex: 3,
                  child: DropdownButton<String>(
                    value: _eventFilter,
                    isDense: true,
                    underline: const SizedBox(),
                    isExpanded: true,
                    items: _eventOptions
                        .map(
                          (e) => DropdownMenuItem(
                            value: e,
                            child: Text(
                              e == 'all'
                                  ? 'ALL'
                                  : e.replaceAll('_', ' ').toUpperCase(),
                              style: TextStyle(
                                fontSize: 11,
                                color: e == 'all'
                                    ? Colors.black
                                    : _eventColor(e),
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _eventFilter = v);
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  tooltip: 'Refresh',
                  onPressed: () => setState(() {}),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // ── Log list ────────────────────────────────────────────────────────
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
                      'Failed to load logs.\nCheck Firestore rules.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red),
                    ),
                  );
                }

                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.article_outlined,
                          size: 52,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No log entries found',
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, i) {
                    final data = docs[i].data();
                    final level = data['level'] as String? ?? 'info';
                    final event = data['event'] as String? ?? '';
                    final message = data['message'] as String? ?? '';
                    final userId = data['userId'] as String? ?? '';
                    final ts = data['timestamp'];
                    final meta =
                        data['metadata'] as Map<String, dynamic>? ?? {};

                    return Container(
                      decoration: BoxDecoration(
                        color: _levelBg(level),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _levelColor(level).withValues(alpha: 0.25),
                        ),
                      ),
                      child: ExpansionTile(
                        leading: Icon(
                          _levelIcon(level),
                          color: _levelColor(level),
                          size: 22,
                        ),
                        tilePadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 2,
                        ),
                        title: Row(
                          children: [
                            // Level badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _levelColor(level),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                level.toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            // Event badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _eventColor(
                                  event,
                                ).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: _eventColor(
                                    event,
                                  ).withValues(alpha: 0.4),
                                ),
                              ),
                              child: Text(
                                event.replaceAll('_', ' ').toUpperCase(),
                                style: TextStyle(
                                  color: _eventColor(event),
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            message,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.black87,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Expanded details
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Divider(height: 12),
                                _DetailRow(
                                  icon: Icons.access_time,
                                  label: 'Timestamp',
                                  value: _formatTs(ts),
                                ),
                                _DetailRow(
                                  icon: Icons.person_outline,
                                  label: 'User ID',
                                  value: userId.isEmpty ? '—' : userId,
                                ),
                                if (meta.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  const Text(
                                    'Metadata',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black54,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  ...meta.entries.map(
                                    (entry) => _DetailRow(
                                      icon: Icons.label_outline,
                                      label: entry.key,
                                      value: entry.value.toString(),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
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

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
