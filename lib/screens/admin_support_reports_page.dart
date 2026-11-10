// lib/screens/admin_support_reports_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'admin_theme.dart';
import '../services/admin_support_service.dart';

class AdminSupportReportsPage extends StatefulWidget {
  const AdminSupportReportsPage({super.key});
  @override
  State<AdminSupportReportsPage> createState() =>
      _AdminSupportReportsPageState();
}

class _AdminSupportReportsPageState extends State<AdminSupportReportsPage> {
  AdminColors get tc => AdminTheme.getColors(context);

  String _statusFilter = 'pending';
  String _categoryFilter = 'all';

  static const _statuses = ['pending', 'resolved', 'all'];
  static const _categories = [
    'all',
    'face_not_recognized',
    'camera_error',
    'liveness_failed',
    'no_enrollment',
    'fingerprint_not_recognized',
    'sensor_error',
    'lockout_issue',
    'geofence_issue',
    'security_issue',
    'other',
  ];

  String _categoryLabel(String c) {
    const map = {
      'face_not_recognized': 'Face not recognized',
      'camera_error': 'Camera problem',
      'liveness_failed': 'Liveness failed',
      'no_enrollment': 'No enrollment',
      'fingerprint_not_recognized': 'Fingerprint not recognized',
      'sensor_error': 'Sensor error',
      'lockout_issue': 'Locked out',
      'geofence_issue': 'Location issue',
      'security_issue': 'Security error',
      'other': 'Other',
    };
    return map[c] ?? c;
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? tc.red : tc.green,
      ),
    );
  }

  Future<String?> _adminUid() async {
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  // ── Action handlers ──
  Future<void> _doUnlock(Map<String, dynamic> r) async {
    final docId = r['employeeDocId']?.toString() ?? '';
    if (docId.isEmpty) return _toast('No employee document ID.', error: true);
    final uid = await _adminUid();
    if (uid == null) return _toast('Session expired.', error: true);

    final err = await AdminSupportService.instance
        .resetFingerprintLock(employeeDocId: docId, adminUid: uid);
    if (err == null) {
      _toast('Fingerprint unlocked for ${r['employeeName'] ?? 'employee'}.');
      await AdminSupportService.instance.notifyEmployee(
        employeeId: r['employeeId']?.toString() ?? docId,
        title: '🔓 Fingerprint Unlocked',
        message: 'Your fingerprint has been unlocked. Please try again.',
      );
      await _markResolved(r['id']?.toString() ?? '', 'Unlocked by admin.');
    } else {
      _toast('Failed: $err', error: true);
    }
  }

  Future<void> _doResetFingerprint(Map<String, dynamic> r) async {
    final docId = r['employeeDocId']?.toString() ?? '';
    if (docId.isEmpty) return _toast('No employee document ID.', error: true);
    final uid = await _adminUid();
    if (uid == null) return _toast('Session expired.', error: true);

    final err = await AdminSupportService.instance
        .forceFingerprintReEnrollment(employeeDocId: docId, adminUid: uid);
    if (err == null) {
      _toast('Fingerprint re-enrollment requested.');
      await AdminSupportService.instance.notifyEmployee(
        employeeId: r['employeeId']?.toString() ?? docId,
        title: '🔄 Re-register Fingerprint',
        message: 'Admin reset your fingerprint. Please register again.',
      );
      await _markResolved(r['id']?.toString() ?? '', 'Re-enrollment issued.');
    } else {
      _toast('Failed: $err', error: true);
    }
  }

  Future<void> _doResetFace(Map<String, dynamic> r) async {
    final docId = r['employeeDocId']?.toString() ?? '';
    if (docId.isEmpty) return _toast('No employee document ID.', error: true);
    final uid = await _adminUid();
    if (uid == null) return _toast('Session expired.', error: true);

    final err = await AdminSupportService.instance
        .forceFaceReEnrollment(employeeDocId: docId, adminUid: uid);
    if (err == null) {
      _toast('Face reset requested. Employee will be prompted to re-register.');
      await AdminSupportService.instance.notifyEmployee(
        employeeId: r['employeeId']?.toString() ?? docId,
        title: '🔄 Face Reset by Admin',
        message: 'Admin reset your face template. Please scan your face again to re-register.',
      );
      await _markResolved(r['id']?.toString() ?? '', 'Face re-enrollment issued.');
    } else {
      _toast('Failed: $err', error: true);
    }
  }

  Future<void> _doClearLockout(Map<String, dynamic> r) async {
    final docId = r['employeeDocId']?.toString() ?? '';
    if (docId.isEmpty) return _toast('No employee document ID.', error: true);
    final uid = await _adminUid();
    if (uid == null) return _toast('Session expired.', error: true);

    final err = await AdminSupportService.instance
        .clearBiometricLockout(employeeDocId: docId, adminUid: uid);
    if (err == null) {
      _toast('Lockout cleared.');
      await AdminSupportService.instance.notifyEmployee(
        employeeId: r['employeeId']?.toString() ?? docId,
        title: '✅ Lockout Cleared',
        message: 'Your biometric lockout has been cleared. '
            'Restart the app and try again.',
      );
      await _markResolved(r['id']?.toString() ?? '', 'Lockout cleared.');
    } else {
      _toast('Failed: $err', error: true);
    }
  }

  Future<void> _doReply(Map<String, dynamic> r) async {
    final ctrl = TextEditingController();
    final reply = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: tc.card,
        title: Text('Reply to ${r['employeeName'] ?? 'employee'}',
            style: TextStyle(color: tc.text)),
        content: TextField(
          controller: ctrl,
          minLines: 3,
          maxLines: 6,
          maxLength: 400,
          style: TextStyle(color: tc.text),
          decoration: InputDecoration(
            hintText: 'Message to employee...',
            hintStyle: TextStyle(color: tc.muted),
            filled: true,
            fillColor: tc.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: tc.muted)),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.pop(ctx, ctrl.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: tc.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (reply == null || reply.isEmpty) return;

    await AdminSupportService.instance.notifyEmployee(
      employeeId: r['employeeId']?.toString() ?? '',
      title: '📨 Admin Message',
      message: reply,
    );
    await _markResolved(r['id']?.toString() ?? '', reply);
    _toast('Reply sent.');
  }

  Future<void> _markResolved(String reportId, String reply) async {
    if (reportId.isEmpty) return;
    final uid = await _adminUid();
    if (uid == null) return;

    // 🔑 I-save ang resolve status
    await AdminSupportService.instance.resolveReport(
      reportId: reportId,
      adminUid: uid,
      reply: reply,
    );

    // 🔑 Bigyan ng Temporary Access ang Employee (para makapag-clock in kahit naka-block)
    try {
      // 🔑 GAMITIN ANG TAMANG COLLECTION (support_reports)
      final reportDoc = await FirebaseFirestore.instance
          .collection('support_reports') // ✅ TAMANG COLLECTION
          .doc(reportId)
          .get();

      final docId = reportDoc.data()?['employeeDocId']?.toString() ??
          reportDoc.data()?['employeeId']?.toString();

      if (docId != null && docId.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('employees')
            .doc(docId)
            .update({
          'adminClockInOverride': true,
          'adminClockInOverrideAt': FieldValue.serverTimestamp(),
        });
        _toast('Temporary clock-in access granted to employee.');
      } else {
        _toast('Resolved, but no employeeDocId found to override.', error: true);
      }
    } catch (e) {
      _toast('Resolved, but failed to grant override: $e', error: true);
    }
  }

  // ── Detail dialog ──
  void _showDetail(Map<String, dynamic> r) {
    final createdAt = r['createdAt'];
    String createdStr = 'N/A';
    if (createdAt is Timestamp) {
      createdStr =
          DateFormat('MMM d, yyyy · h:mm a').format(createdAt.toDate());
    }

    showDialog<void>(
      context: context,
      builder: (ctx) {
        final dTc = AdminTheme.getColors(ctx);
        return Dialog(
          backgroundColor: dTc.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          insetPadding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 12, 14),
                  child: Row(
                    children: [
                      Icon(Icons.support_agent_rounded,
                          color: dTc.orange, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _categoryLabel(
                              (r['subCategory'] ?? 'other').toString()),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: dTc.text,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close_rounded,
                            color: dTc.muted, size: 20),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                Divider(color: dTc.border, height: 1),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _row(dTc, 'Employee',
                            (r['employeeName'] ?? '—').toString()),
                        _row(dTc, 'Employee ID',
                            (r['employeeId'] ?? '—').toString()),
                        _row(dTc, 'Email',
                            (r['employeeEmail'] ?? '—').toString()),
                        _row(dTc, 'Device',
                            (r['deviceModel'] ?? '—').toString()),
                        _row(dTc, 'Stage', (r['stage'] ?? '—').toString()),
                        _row(dTc, 'Submitted', createdStr),
                        const SizedBox(height: 14),
                        _section(dTc, 'ISSUE'),
                        _box(dTc, (r['issueMessage'] ?? '—').toString()),
                        if ((r['additionalNotes'] ?? '')
                            .toString()
                            .isNotEmpty) ...[
                          const SizedBox(height: 14),
                          _section(dTc, 'NOTES FROM EMPLOYEE'),
                          _box(dTc,
                              (r['additionalNotes'] ?? '').toString()),
                        ],
                        if ((r['errorDetail'] ?? '')
                            .toString()
                            .isNotEmpty) ...[
                          const SizedBox(height: 14),
                          _section(dTc, 'ERROR DETAIL'),
                          _box(dTc, (r['errorDetail'] ?? '').toString(),
                              color: dTc.red.withValues(alpha: 0.08),
                              border: dTc.red.withValues(alpha: 0.3)),
                        ],
                      ],
                    ),
                  ),
                ),
                Divider(color: dTc.border, height: 1),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _actionChip(
                        dTc,
                        icon: Icons.lock_open_rounded,
                        label: 'Unlock',
                        onTap: () {
                          Navigator.pop(ctx);
                          _doUnlock(r);
                        },
                      ),
                      _actionChip(
                        dTc,
                        icon: Icons.face_retouching_natural_rounded,
                        label: 'Reset Face',
                        color: dTc.orange,
                        onTap: () {
                          Navigator.pop(ctx);
                          _doResetFace(r);
                        },
                      ),
                      _actionChip(
                        dTc,
                        icon: Icons.fingerprint_rounded,
                        label: 'Reset Fingerprint',
                        color: dTc.orange,
                        onTap: () {
                          Navigator.pop(ctx);
                          _doResetFingerprint(r);
                        },
                      ),
                      _actionChip(
                        dTc,
                        icon: Icons.timer_off_rounded,
                        label: 'Clear lockout',
                        onTap: () {
                          Navigator.pop(ctx);
                          _doClearLockout(r);
                        },
                      ),
                      _actionChip(
                        dTc,
                        icon: Icons.reply_rounded,
                        label: 'Reply',
                        color: dTc.orange,
                        onTap: () {
                          Navigator.pop(ctx);
                          _doReply(r);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _row(AdminColors dTc, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: dTc.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                color: dTc.text,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(AdminColors dTc, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
          color: dTc.muted,
        ),
      ),
    );
  }

  Widget _box(AdminColors dTc, String text,
      {Color? color, Color? border}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color ?? dTc.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border ?? dTc.border),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, color: dTc.text, height: 1.4),
      ),
    );
  }

  Widget _actionChip(
      AdminColors dTc, {
        required IconData icon,
        required String label,
        required VoidCallback onTap,
        Color? color,
      }) {
    final c = color ?? dTc.text;
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 14, color: c),
      label: Text(label,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, color: c)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: c.withValues(alpha: 0.3)),
        backgroundColor: c.withValues(alpha: 0.06),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }

  // ── Build ──
  @override
  Widget build(BuildContext context) {
    return Container(
      color: tc.background,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                const SizedBox(height: 20),
                _buildFilterBar(),
                const SizedBox(height: 16),
                _buildReportsList(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Icon(Icons.support_agent_rounded, size: 22, color: tc.orange),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Support Reports',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: tc.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Review employee issues and take action.',
                style: TextStyle(fontSize: 13, color: tc.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tc.border),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _filterDropdown(
            label: 'Status',
            value: _statusFilter,
            options: _statuses,
            labelFn: (v) => v.toUpperCase(),
            onChanged: (v) => setState(() => _statusFilter = v),
          ),
          _filterDropdown(
            label: 'Category',
            value: _categoryFilter,
            options: _categories,
            labelFn: (v) => v == 'all' ? 'All Categories' : _categoryLabel(v),
            onChanged: (v) => setState(() => _categoryFilter = v),
          ),
        ],
      ),
    );
  }

  Widget _filterDropdown({
    required String label,
    required String value,
    required List<String> options,
    required String Function(String) labelFn,
    required void Function(String) onChanged,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: tc.muted)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: tc.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: tc.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              dropdownColor: tc.card,
              style: TextStyle(fontSize: 12, color: tc.text),
              items: options
                  .map((o) => DropdownMenuItem(
                value: o,
                child: Text(labelFn(o)),
              ))
                  .toList(),
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReportsList() {
    // 🛠️ FIX: Tanggalin ang .orderBy() para hindi mag-error sa composite index
    // at para mabasa lahat ng naka-save na reports.
    final q = FirebaseFirestore.instance
        .collection(AdminSupportService.collection)
        .limit(100);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return _emptyState('Error loading reports: ${snap.error}');
        }
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 60),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        var docs = snap.data?.docs ?? [];

        // 🛠️ I-sort natin manually sa Dart base sa 'timestamp' o 'createdAt'
        docs = docs.toList()..sort((a, b) {
          final aData = a.data();
          final bData = b.data();
          final aTime = (aData['timestamp'] ?? aData['createdAt']) as Timestamp?;
          final bTime = (bData['timestamp'] ?? bData['createdAt']) as Timestamp?;
          if (aTime == null || bTime == null) return 0;
          return bTime.compareTo(aTime); // Descending (newest first)
        });

        // 🔑 Kunin ang data, isama ang 'metadata' kung meron man
        docs = docs.where((d) {
          final data = d.data();
          // Kung type == support_request, panatilihin
          return data['type'] == 'support_request';
        }).toList();

        // 🛠️ Apply the filters here instead of Firestore `.where()`
        if (_statusFilter != 'all') {
          docs = docs.where((d) {
            final data = d.data();
            final meta = data['metadata'] as Map<String, dynamic>? ?? {};
            final status = (data['status'] ?? meta['status'] ?? 'pending').toString().toLowerCase();
            return status == _statusFilter;
          }).toList();
        }

        if (_categoryFilter != 'all') {
          docs = docs.where((d) {
            final data = d.data();
            final meta = data['metadata'] as Map<String, dynamic>? ?? {};
            final cat = (data['subCategory'] ?? meta['subCategory'] ?? 'other').toString().toLowerCase();
            return cat == _categoryFilter;
          }).toList();
        }

        if (docs.isEmpty) {
          return _emptyState('No reports match these filters.');
        }

        return Column(
          children: docs.map((d) {
            final rawData = d.data();
            final meta = rawData['metadata'] as Map<String, dynamic>? ?? {};

            // 🔑 Pagsamahin ang root data at metadata para mabasa ng _reportCard
            final r = <String, dynamic>{
              'id': d.id,
              ...rawData,
              ...meta, // Isama ang metadata (status, subCategory, deviceModel, etc.)
            };

            return _reportCard(r);
          }).toList(),
        );
      },
    );
  }

  Widget _reportCard(Map<String, dynamic> r) {
    final cat = (r['subCategory'] ?? 'other').toString();
    final status = (r['status'] ?? 'pending').toString();
    final isPending = status == 'pending';
    final createdAt = r['createdAt'];
    String timeStr = '';
    if (createdAt is Timestamp) {
      timeStr = DateFormat('MMM d · h:mm a').format(createdAt.toDate());
    }
    final statusColor = isPending ? tc.orange : tc.green;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tc.border),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showDetail(r),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: statusColor.withValues(alpha: 0.15),
                  child: Icon(
                    isPending
                        ? Icons.report_problem_rounded
                        : Icons.check_circle_rounded,
                    color: statusColor,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              (r['employeeName'] ?? 'Unknown').toString(),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: tc.text,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              status.toUpperCase(),
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: statusColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _categoryLabel(cat),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: tc.orangeText,
                        ),
                      ),
                      if (timeStr.isNotEmpty)
                        Text(
                          timeStr,
                          style:
                          TextStyle(fontSize: 10, color: tc.muted),
                        ),
                    ],
                  ),
                ),
                if (isPending) ...[
                  IconButton(
                    tooltip: 'Unlock',
                    icon: Icon(Icons.lock_open_rounded,
                        size: 18, color: tc.green),
                    onPressed: () => _doUnlock(r),
                  ),
                  IconButton(
                    tooltip: 'Reset Face',
                    icon: Icon(Icons.face_retouching_natural_rounded,
                        size: 18, color: tc.orange),
                    onPressed: () => _doResetFace(r),
                  ),
                  IconButton(
                    tooltip: 'Reply',
                    icon: Icon(Icons.reply_rounded,
                        size: 18, color: tc.text),
                    onPressed: () => _doReply(r),
                  ),
                ],
                Icon(Icons.chevron_right_rounded, color: tc.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyState(String msg) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(Icons.inbox_rounded, size: 40, color: tc.muted),
          const SizedBox(height: 10),
          Text(msg,
              style: TextStyle(fontSize: 13, color: tc.muted),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}