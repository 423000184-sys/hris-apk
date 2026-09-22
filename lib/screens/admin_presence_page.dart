// lib/screens/admin_presence_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'admin_theme.dart';
import 'admin_backup_list_page.dart';

class AdminPresencePage extends StatefulWidget {
  const AdminPresencePage({super.key});

  @override
  State<AdminPresencePage> createState() => _AdminPresencePageState();
}

class _AdminPresencePageState extends State<AdminPresencePage> {
  @override
  Widget build(BuildContext context) {
    final tc = AdminTheme.getColors(context);

    return Scaffold(
      backgroundColor: tc.background,
      appBar: AppBar(
        backgroundColor: tc.topBarBg,
        foregroundColor: tc.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Live Presence',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: tc.text,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => setState(() {}),
            icon: Icon(Icons.refresh_rounded, color: tc.textMuted, size: 20),
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: tc.border),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('employee_presence')
            .orderBy('lastUpdated', descending: true)
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return _errorState(tc, '${snap.error}');
          }
          if (!snap.hasData) {
            return Center(
              child: CircularProgressIndicator(
                color: tc.orange,
                strokeWidth: 2.5,
              ),
            );
          }

          final docs = snap.data!.docs;
          if (docs.isEmpty) return _emptyState(tc);

          int insideCount = 0;
          int outsideCount = 0;
          for (final d in docs) {
            final inRange = d.data()['inRange'] == true;
            if (inRange) {
              insideCount++;
            } else {
              outsideCount++;
            }
          }

          return Column(
            children: [
              _buildSummary(tc, insideCount, outsideCount, docs.length),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: tc.border,
                    indent: 16,
                  ),
                  itemBuilder: (_, i) => _tile(context, tc, docs[i]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSummary(
      AdminColors tc, int inside, int outside, int total) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tc.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _statBox(tc, '$total', 'Total', tc.text,
                Icons.people_rounded),
          ),
          Container(width: 1, height: 40, color: tc.border),
          Expanded(
            // ⭐ Now uses theme green (warm) instead of hardcoded #16A34A
            child: _statBox(tc, '$inside', 'IN RANGE',
                tc.green, Icons.check_circle_rounded),
          ),
          Container(width: 1, height: 40, color: tc.border),
          Expanded(
            // ⭐ Now uses theme red (warm) instead of hardcoded #EF4444
            child: _statBox(tc, '$outside', 'OUT',
                tc.red, Icons.cancel_rounded),
          ),
        ],
      ),
    );
  }

  Widget _statBox(
      AdminColors tc, String value, String label, Color color, IconData icon) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: color,
            height: 1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: tc.textMuted,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _tile(
      BuildContext context,
      AdminColors tc,
      QueryDocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data();
    final name = (data['employeeName'] ?? 'Unknown').toString();
    final inRange = data['inRange'] == true;
    final distance = (data['distanceMeters'] as num?)?.toDouble() ?? 0;
    final accuracy = (data['accuracyMeters'] as num?)?.toDouble();
    final ts = data['lastUpdated'];
    DateTime? lastUpdated;
    if (ts is Timestamp) lastUpdated = ts.toDate().toLocal();

    final isStale = lastUpdated == null ||
        DateTime.now().difference(lastUpdated).inMinutes > 10;

    // ⭐ Now uses theme green/red instead of hardcoded colors
    final accent = isStale
        ? tc.textMuted
        : (inRange ? tc.green : tc.red);

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AdminBackupListPage(
              employeeId: doc.id,
              employeeName: name,
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(color: accent, width: 2),
              ),
              child: Icon(
                isStale
                    ? Icons.hourglass_empty_rounded
                    : (inRange
                    ? Icons.check_rounded
                    : Icons.close_rounded),
                color: accent,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: tc.text,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          isStale
                              ? 'STALE'
                              : (inRange ? 'IN RANGE' : 'OUT'),
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: accent,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_rounded,
                        size: 11,
                        color: tc.muted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${distance.toStringAsFixed(0)}m from office',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: tc.textMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (accuracy != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          '· ±${accuracy.toStringAsFixed(0)}m',
                          style: TextStyle(
                            fontSize: 10,
                            color: tc.muted,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    lastUpdated == null
                        ? 'No data'
                        : 'Last check: ${_fmtTime(lastUpdated)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: tc.muted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: tc.muted,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  String _fmtTime(DateTime d) {
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return DateFormat('MMM d, hh:mm a').format(d);
  }

  Widget _emptyState(AdminColors tc) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: tc.orangeLight,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.location_off_rounded,
                size: 32,
                color: tc.orange,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No presence data',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: tc.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Live employee status will appear here\nonce they open their app.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: tc.textMuted,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorState(AdminColors tc, String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: tc.red),
            const SizedBox(height: 16),
            Text(
              'Error loading presence',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: tc.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              msg,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: tc.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}