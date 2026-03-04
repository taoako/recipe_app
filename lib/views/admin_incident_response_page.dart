import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../services/app_logger.dart';

/// Incident Response Plan — admin-only security management page.
///
/// Collections:
///   incidents/{id}  — security incident records
///   incidents/{id}/timeline/{tid}  — timeline entries per incident
class AdminIncidentResponsePage extends StatefulWidget {
  const AdminIncidentResponsePage({super.key});

  @override
  State<AdminIncidentResponsePage> createState() =>
      _AdminIncidentResponsePageState();
}

class _AdminIncidentResponsePageState extends State<AdminIncidentResponsePage> {
  static const _phases = ['detection', 'containment', 'recovery', 'closed'];
  static const _severities = ['critical', 'high', 'medium', 'low'];

  Color _phaseColor(String phase) => switch (phase) {
    'detection' => Colors.red.shade600,
    'containment' => Colors.orange.shade700,
    'recovery' => Colors.blue.shade600,
    'closed' => Colors.green.shade600,
    _ => Colors.grey,
  };

  IconData _phaseIcon(String phase) => switch (phase) {
    'detection' => Icons.search_outlined,
    'containment' => Icons.shield_outlined,
    'recovery' => Icons.restore_outlined,
    'closed' => Icons.check_circle_outline,
    _ => Icons.help_outline,
  };

  Color _severityColor(String sev) => switch (sev) {
    'critical' => Colors.red.shade800,
    'high' => Colors.orange.shade800,
    'medium' => Colors.amber.shade700,
    _ => Colors.green.shade700,
  };

  String _formatTs(dynamic ts) {
    if (ts == null) return '—';
    if (ts is Timestamp) {
      return DateFormat('MMM d, y HH:mm').format(ts.toDate().toLocal());
    }
    return ts.toString();
  }

  // ── Create Incident dialog ─────────────────────────────────────────────────
  Future<void> _showCreateDialog() async {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final sysCtrl = TextEditingController();
    String severity = 'high';

    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'dismiss',
      transitionDuration: const Duration(milliseconds: 250),
      transitionBuilder: (ctx, anim, _, child) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.15),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
        child: FadeTransition(opacity: anim, child: child),
      ),
      pageBuilder: (ctx, _, __) {
        return StatefulBuilder(
          builder: (ctx, setS) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Color(0xFFFF7043)),
                SizedBox(width: 8),
                Text('Create Incident'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Incident Title *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Description / What happened?',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: sysCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Affected System / Area',
                      hintText: 'e.g. Authentication, Database, API',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Severity',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: _severities
                        .map(
                          (s) => ChoiceChip(
                            label: Text(s.toUpperCase()),
                            selected: severity == s,
                            selectedColor: _severityColor(
                              s,
                            ).withValues(alpha: 0.2),
                            labelStyle: TextStyle(
                              color: severity == s
                                  ? _severityColor(s)
                                  : Colors.grey.shade700,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                            onSelected: (_) => setS(() => severity = s),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('CANCEL'),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.add_alarm_outlined, size: 16),
                label: const Text('CREATE'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF7043),
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  if (titleCtrl.text.trim().isEmpty) return;
                  final admin = FirebaseAuth.instance.currentUser;
                  await FirebaseFirestore.instance.collection('incidents').add({
                    'title': titleCtrl.text.trim(),
                    'description': descCtrl.text.trim(),
                    'affectedSystem': sysCtrl.text.trim(),
                    'severity': severity,
                    'phase': 'detection',
                    'status': 'open',
                    'createdBy': admin?.uid ?? '',
                    'createdByName': admin?.displayName ?? 'Admin',
                    'detectedAt': FieldValue.serverTimestamp(),
                    'resolvedAt': null,
                  });
                  AppLogger.logWarning(
                    LogEvent.adminAction,
                    'Incident created: ${titleCtrl.text.trim()}',
                    metadata: {'severity': severity},
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Update Phase dialog ────────────────────────────────────────────────────
  Future<void> _updatePhase(DocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    String phase = data['phase'] ?? 'detection';
    final noteCtrl = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Update Phase'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioGroup<String>(
                groupValue: phase,
                onChanged: (v) => setS(() => phase = v ?? phase),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: _phases
                      .map(
                        (p) => RadioListTile<String>(
                          value: p,
                          title: Row(
                            children: [
                              Icon(
                                _phaseIcon(p),
                                color: _phaseColor(p),
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                p[0].toUpperCase() + p.substring(1),
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: _phaseColor(p),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'Action taken / Note',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () async {
                final admin = FirebaseAuth.instance.currentUser;
                final updates = <String, dynamic>{
                  'phase': phase,
                  if (phase == 'closed') ...{
                    'status': 'resolved',
                    'resolvedAt': FieldValue.serverTimestamp(),
                  },
                };
                await doc.reference.update(updates);

                if (noteCtrl.text.trim().isNotEmpty) {
                  await doc.reference.collection('timeline').add({
                    'note': noteCtrl.text.trim(),
                    'phase': phase,
                    'by': admin?.displayName ?? 'Admin',
                    'at': FieldValue.serverTimestamp(),
                  });
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF7043),
                foregroundColor: Colors.white,
              ),
              child: const Text('UPDATE'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Incident Detail Sheet ──────────────────────────────────────────────────
  void _showDetail(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        builder: (ctx, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        data['title'] ?? 'Incident',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    _PhaseBadge(
                      phase: data['phase'] ?? 'detection',
                      color: _phaseColor(data['phase'] ?? 'detection'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 24),
              Expanded(
                child: ListView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    _DetailRow(
                      icon: Icons.warning_amber_rounded,
                      label: 'Severity',
                      value: (data['severity'] ?? '—').toUpperCase(),
                      valueColor: _severityColor(data['severity'] ?? 'low'),
                    ),
                    _DetailRow(
                      icon: Icons.computer_outlined,
                      label: 'Affected System',
                      value: data['affectedSystem'] ?? '—',
                    ),
                    _DetailRow(
                      icon: Icons.person_outline,
                      label: 'Reported By',
                      value: data['createdByName'] ?? '—',
                    ),
                    _DetailRow(
                      icon: Icons.schedule_outlined,
                      label: 'Detected At',
                      value: _formatTs(data['detectedAt']),
                    ),
                    if (data['resolvedAt'] != null)
                      _DetailRow(
                        icon: Icons.check_circle_outline,
                        label: 'Resolved At',
                        value: _formatTs(data['resolvedAt']),
                      ),
                    const SizedBox(height: 16),
                    if ((data['description'] ?? '').isNotEmpty) ...[
                      const Text(
                        'Description',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Text(data['description']),
                      ),
                      const SizedBox(height: 20),
                    ],
                    const Text(
                      'Timeline',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    StreamBuilder<QuerySnapshot>(
                      stream: doc.reference
                          .collection('timeline')
                          .orderBy('at')
                          .snapshots(),
                      builder: (ctx, snap) {
                        if (!snap.hasData || snap.data!.docs.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'No timeline entries yet.',
                              style: TextStyle(color: Colors.grey),
                            ),
                          );
                        }
                        return Column(
                          children: snap.data!.docs.map((t) {
                            final td = t.data() as Map<String, dynamic>;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    _phaseIcon(td['phase'] ?? ''),
                                    size: 16,
                                    color: _phaseColor(
                                      td['phase'] ?? 'detection',
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          td['note'] ?? '',
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                        Text(
                                          '${td['by'] ?? ''} · ${_formatTs(td['at'])}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                    if (data['phase'] != 'closed')
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.update_outlined),
                          label: const Text('Update Phase / Add Note'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF7043),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _updatePhase(doc);
                          },
                        ),
                      ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFFFF7043),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_alarm_outlined),
        label: const Text('New Incident'),
        onPressed: _showCreateDialog,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Intro banner ──────────────────────────────────────────────────
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF7043), Color(0xFFFF5252)],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              children: [
                Icon(Icons.security, color: Colors.white, size: 36),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Incident Response',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Track and manage security incidents through Detection → Containment → Recovery.',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Phase legend ──────────────────────────────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: _phases.map((p) {
                return Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _phaseColor(p).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _phaseColor(p).withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_phaseIcon(p), size: 14, color: _phaseColor(p)),
                      const SizedBox(width: 4),
                      Text(
                        p[0].toUpperCase() + p.substring(1),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _phaseColor(p),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),

          // ── Incident list ─────────────────────────────────────────────────
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('incidents')
                  .orderBy('detectedAt', descending: true)
                  .snapshots(),
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snap.hasData || snap.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.verified_user_outlined,
                          size: 64,
                          color: Colors.green.shade300,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'No incidents recorded',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'The system appears healthy.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                  itemCount: snap.data!.docs.length,
                  itemBuilder: (ctx, i) {
                    final doc = snap.data!.docs[i];
                    final data = doc.data() as Map<String, dynamic>;
                    final phase = data['phase'] ?? 'detection';
                    final severity = data['severity'] ?? 'low';
                    final isClosed = phase == 'closed';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: isClosed ? 0 : 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: isClosed
                            ? BorderSide(color: Colors.grey.shade200)
                            : BorderSide.none,
                      ),
                      color: isClosed ? Colors.grey.shade50 : Colors.white,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => _showDetail(doc),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _severityColor(
                                        severity,
                                      ).withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      severity.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: _severityColor(severity),
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  _PhaseBadge(
                                    phase: phase,
                                    color: _phaseColor(phase),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                data['title'] ?? '—',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: isClosed
                                      ? Colors.grey
                                      : Colors.black87,
                                  decoration: isClosed
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                              if ((data['affectedSystem'] ?? '').isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    'System: ${data['affectedSystem']}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.person_outline,
                                    size: 13,
                                    color: Colors.grey,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    data['createdByName'] ?? '—',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Icon(
                                    Icons.schedule_outlined,
                                    size: 13,
                                    color: Colors.grey,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _formatTs(data['detectedAt']),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
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

// ── Small helper widgets ───────────────────────────────────────────────────────

class _PhaseBadge extends StatelessWidget {
  const _PhaseBadge({required this.phase, required this.color});
  final String phase;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        phase[0].toUpperCase() + phase.substring(1),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: valueColor ?? Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
