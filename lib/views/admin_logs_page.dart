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
    LogEvent.loginBlocked,
    LogEvent.signupSuccess,
    LogEvent.signupFailure,
    LogEvent.logout,
    LogEvent.passwordReset,
    LogEvent.accessViolation,
    LogEvent.adminAction,
    LogEvent.userAction,
    LogEvent.recipeAction,
    LogEvent.imageUpload,
    LogEvent.systemError,
    LogEvent.bruteForceDetected,
    LogEvent.accountLocked,
    LogEvent.twoFactorSent,
    LogEvent.twoFactorSuccess,
    LogEvent.twoFactorFailure,
    LogEvent.captchaCompleted,
    LogEvent.captchaFailed,
    LogEvent.adminReAuth,
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
      case LogEvent.twoFactorSuccess:
      case LogEvent.captchaCompleted:
        return Colors.green;
      case LogEvent.loginFailure:
      case LogEvent.signupFailure:
      case LogEvent.twoFactorFailure:
      case LogEvent.captchaFailed:
        return Colors.red;
      case LogEvent.loginBlocked:
      case LogEvent.accessViolation:
      case LogEvent.bruteForceDetected:
      case LogEvent.accountLocked:
        return Colors.deepOrange;
      case LogEvent.adminAction:
      case LogEvent.adminReAuth:
        return Colors.purple;
      case LogEvent.loginAttempt:
        return Colors.blue;
      case LogEvent.logout:
        return Colors.blueGrey;
      case LogEvent.passwordReset:
        return Colors.teal;
      case LogEvent.recipeAction:
        return Colors.indigo;
      case LogEvent.imageUpload:
        return Colors.cyan;
      case LogEvent.twoFactorSent:
        return Colors.amber;
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
  // Fetch all recent logs and filter client-side to avoid composite index
  // requirements for level + event + orderBy combinations.

  Query<Map<String, dynamic>> get _query {
    return FirebaseFirestore.instance
        .collection('app_logs')
        .orderBy('timestamp', descending: true)
        .limit(500);
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _applyFilters(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return docs.where((doc) {
      final data = doc.data();
      if (_levelFilter != 'all' && data['level'] != _levelFilter) return false;
      if (_eventFilter != 'all' && data['event'] != _eventFilter) return false;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF7F8FC),
      child: Column(
        children: [
          // ── Filter bar ─────────────────────────────────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text(
                  'Level:',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 120,
                  child: DropdownButton<String>(
                    value: _levelFilter,
                    isDense: true,
                    isExpanded: true,
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
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _levelFilter = v);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Event:',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(width: 6),
                Expanded(
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
                const SizedBox(width: 6),
                InkWell(
                  onTap: () => setState(() {}),
                  borderRadius: BorderRadius.circular(20),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.refresh, size: 20),
                  ),
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

                final docs = _applyFilters(snapshot.data?.docs ?? []);
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

                    return _LogEntryTile(
                      level: level,
                      event: event,
                      message: message,
                      userId: userId,
                      ts: ts,
                      meta: meta,
                      levelColor: _levelColor(level),
                      levelBg: _levelBg(level),
                      levelIcon: _levelIcon(level),
                      eventColor: _eventColor(event),
                      formatTs: _formatTs,
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

/// Custom stateful tile that expands on tap — avoids ExpansionTile's
/// internal InkWell / Tooltip which crash on Flutter web with
/// "Cannot hit test a render box that has never been laid out".
class _LogEntryTile extends StatefulWidget {
  final String level;
  final String event;
  final String message;
  final String userId;
  final dynamic ts;
  final Map<String, dynamic> meta;
  final Color levelColor;
  final Color levelBg;
  final IconData levelIcon;
  final Color eventColor;
  final String Function(dynamic) formatTs;

  const _LogEntryTile({
    required this.level,
    required this.event,
    required this.message,
    required this.userId,
    required this.ts,
    required this.meta,
    required this.levelColor,
    required this.levelBg,
    required this.levelIcon,
    required this.eventColor,
    required this.formatTs,
  });

  @override
  State<_LogEntryTile> createState() => _LogEntryTileState();
}

class _LogEntryTileState extends State<_LogEntryTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: widget.levelBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: widget.levelColor.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header (tap to expand) ─────────────────────────────────────
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(widget.levelIcon, color: widget.levelColor, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            // Level badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: widget.levelColor,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                widget.level.toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            // Event badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: widget.eventColor.withValues(
                                  alpha: 0.15,
                                ),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: widget.eventColor.withValues(
                                    alpha: 0.4,
                                  ),
                                ),
                              ),
                              child: Text(
                                widget.event.replaceAll('_', ' ').toUpperCase(),
                                style: TextStyle(
                                  color: widget.eventColor,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.message,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black87,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: Colors.grey,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),

          // ── Expandable details ─────────────────────────────────────────
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 12),
                  _DetailRow(
                    icon: Icons.access_time,
                    label: 'Timestamp',
                    value: widget.formatTs(widget.ts),
                  ),
                  _DetailRow(
                    icon: Icons.person_outline,
                    label: 'User ID',
                    value: widget.userId.isEmpty ? '—' : widget.userId,
                  ),
                  if (widget.meta.isNotEmpty) ...[
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
                    ...widget.meta.entries.map(
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
