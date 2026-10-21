// lib/screens/admin_password_change_requests_page.dart
// v1.2: 🔗 OneSignal Push Notifications integrated for Approve, Regenerate, and Reject.
import 'dart:async';
import 'dart:convert';
import 'dart:math' show Random;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show HapticFeedback, Clipboard, ClipboardData;
import 'package:intl/intl.dart';
import '../models/admin_notification.dart';
import '../services/admin_notification_service.dart';
import '../services/security_hardening_service.dart';
import '../services/demo_mode_service.dart';
import '../services/onesignal_sender.dart'; // 🆕 Added
import 'admin_theme.dart';

void _secureLog(String msg) {
  if (kDebugMode) debugPrint('[PwdReqPage] $msg');
}

enum _StatusFilter { all, pending, approved, rejected }

class PasswordChangeRequestsPage extends StatefulWidget {
  final String? initialRequestId;
  const PasswordChangeRequestsPage({super.key, this.initialRequestId});

  @override
  State<PasswordChangeRequestsPage> createState() =>
      _PasswordChangeRequestsPageState();
}

class _PasswordChangeRequestsPageState
    extends State<PasswordChangeRequestsPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  String _query = '';
  _StatusFilter _statusFilter = _StatusFilter.pending;

  final List<DateTime> _destructiveTimes = [];
  static const int _maxDestructive = 5;
  static const Duration _rateWindow = Duration(seconds: 30);

  bool get _isDemo {
    try {
      return DemoModeService.instance.isEnabled;
    } catch (_) {
      return false;
    }
  }

  void _demoBlock() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Action disabled in Demo Mode.'),
        backgroundColor: Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
        margin: EdgeInsets.all(16),
      ),
    );
  }

  List<AdminNotification> _getMockRequests() {
    final now = DateTime.now();
    return [
      AdminNotification(
        id: 'demo_pwd_1',
        type: 'password_change',
        title: 'Password change requested',
        message: 'John Doe forgot their PIN and is requesting a reset.',
        timestamp: now.subtract(const Duration(minutes: 12)),
        read: false,
        priority: 'high',
        employeeName: 'John Doe',
        employeeId: 'DEMO-001',
        employeeIdentifier: 'DEMO-001',
        employeeEmail: 'john.doe@demo.local',
        reason: 'Forgot old PIN, cannot access account',
        status: 'pending',
        metadata: const {},
      ),
      AdminNotification(
        id: 'demo_pwd_2',
        type: 'password_change',
        title: 'Password change requested',
        message: 'Jane Smith needs PIN reset after switching phones.',
        timestamp: now.subtract(const Duration(hours: 2)),
        read: false,
        priority: 'high',
        employeeName: 'Jane Smith',
        employeeId: 'DEMO-002',
        employeeIdentifier: 'DEMO-002',
        employeeEmail: 'jane.smith@demo.local',
        reason: 'Changed device, old PIN no longer works',
        status: 'pending',
        metadata: const {},
      ),
      AdminNotification(
        id: 'demo_pwd_3',
        type: 'password_change',
        title: 'Password change requested',
        message: 'Mike Johnson requested a new PIN.',
        timestamp: now.subtract(const Duration(hours: 5)),
        read: true,
        priority: 'normal',
        employeeName: 'Mike Johnson',
        employeeId: 'DEMO-003',
        employeeIdentifier: 'DEMO-003',
        employeeEmail: 'mike.johnson@demo.local',
        reason: 'Suspected PIN leak',
        status: 'approved',
        metadata: const {
          'approvedByEmail': 'admin@demo.local',
          'newPin': '4821',
        },
      ),
      AdminNotification(
        id: 'demo_pwd_4',
        type: 'password_change',
        title: 'Password change requested',
        message: 'Sarah Lee requested a PIN reset.',
        timestamp: now.subtract(const Duration(days: 1)),
        read: true,
        priority: 'normal',
        employeeName: 'Sarah Lee',
        employeeId: 'DEMO-004',
        employeeIdentifier: 'DEMO-004',
        employeeEmail: 'sarah.lee@demo.local',
        reason: 'Tried too many times, locked out',
        status: 'rejected',
        metadata: const {
          'rejectReason': 'Contact HR in person',
        },
      ),
    ];
  }

  @override
  void initState() {
    super.initState();
    if (!_isDemo) {
      _logAudit('page_opened', 'Admin opened password change requests page');
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _logAudit(String action, String details) async {
    if (_isDemo) return;
    try {
      final empId =
      await SecurityHardeningService.instance.getCurrentEmployeeId();
      if (empId == null) return;
      await FirebaseFirestore.instance.collection('admin_audit_logs').add({
        'action': action,
        'details': details,
        'adminId': empId,
        'stage': 'password_change_requests_page',
        'platform': kIsWeb ? 'web' : 'mobile',
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      _secureLog('Audit log failed: $e');
    }
  }

  bool _checkRateLimit() {
    final now = DateTime.now();
    _destructiveTimes.removeWhere((t) => now.difference(t) > _rateWindow);
    if (_destructiveTimes.length >= _maxDestructive) return false;
    _destructiveTimes.add(now);
    return true;
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
        Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String _sanitize(String input) {
    if (input.isEmpty) return input;
    var s = input;
    s = s.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');
    s = s.replaceAll(
        RegExp(r'[\u200B-\u200F\u202A-\u202E\u2066-\u2069\uFEFF]'), '');
    if (s.length > 500) s = '${s.substring(0, 500)}…';
    return s;
  }

  String _generateNewPin() {
    final rnd = Random.secure();
    return (rnd.nextInt(9000) + 1000).toString();
  }

  String _randomSalt() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return base64Url.encode(bytes);
  }

  String _saltedHash(String pin, String salt) {
    final bytes = utf8.encode('$salt:$pin');
    return sha256.convert(bytes).toString();
  }

  // ═══════════════════════════════════════════════════════════════
  // APPROVE REQUEST (With OneSignal Push)
  // ═══════════════════════════════════════════════════════════════
  Future<void> _approveRequest(AdminNotification n) async {
    if (_isDemo) {
      _demoBlock();
      return;
    }
    if (!_checkRateLimit()) {
      _showSnack('⚠️ Too fast. Please wait a few seconds.');
      return;
    }

    try {
      final adminId =
      await SecurityHardeningService.instance.getCurrentEmployeeId();
      final adminEmail =
          FirebaseAuth.instance.currentUser?.email?.toLowerCase().trim() ??
              'unknown';

      final newPin = _generateNewPin();
      final salt = _randomSalt();
      final hash = _saltedHash(newPin, salt);

      final empDocId = n.employeeId ?? n.metadata['employeeId']?.toString();
      if (empDocId == null || empDocId.isEmpty) {
        _showSnack('⚠️ Employee ID not found.');
        return;
      }

      final empDoc = await FirebaseFirestore.instance
          .collection('employees')
          .doc(empDocId)
          .get();
      if (!empDoc.exists) {
        _showSnack('⚠️ Employee not found: $empDocId');
        return;
      }

      await FirebaseFirestore.instance
          .collection('employees')
          .doc(empDocId)
          .set({
        'pin': newPin,
        'pinHash': hash,
        'pinSalt': salt,
        'pinUpdatedAt': FieldValue.serverTimestamp(),
        'pinUpdatedBy': adminEmail,
        'requiresPinChange': true,
        'pinChangeAllowed': false,
        'pinChangeApprovalToken': null,
        'pinChangeApprovedAt': FieldValue.serverTimestamp(),
        'pinChangeApprovedBy': adminId,
        'pinChangeRejected': false,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await FirebaseFirestore.instance
          .collection('admin_notifications')
          .doc(n.id)
          .update({
        'status': 'approved',
        'read': true,
        'metadata.approvedBy': adminId,
        'metadata.approvedByEmail': adminEmail,
        'metadata.approvedAt': FieldValue.serverTimestamp(),
        'metadata.newPin': newPin,
        'metadata.pinGeneratedAt': FieldValue.serverTimestamp(),
      });

      // 1. Save to In-App Database
      try {
        await FirebaseFirestore.instance
            .collection('employee_notifications')
            .add({
          'employeeId': empDocId,
          'title': '🔐 Password Reset — Your New PIN',
          'message': 'Your PIN has been reset by admin.\n\nYOUR NEW PIN: $newPin\n\nUse this PIN on your next login.',
          'type': 'password_change_approved',
          'newPin': newPin,
          'requestId': n.id,
          'priority': 'high',
          'read': false,
          'timestamp': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        _secureLog('⚠️ Employee notification failed: $e');
      }

      // 2. Send OneSignal Push Notification
      try {
        await OneSignalSender.instance.sendToEmployee(
          employeeId: empDocId,
          title: '🔐 Password Reset',
          message: 'Your PIN has been reset. New PIN: $newPin',
          type: 'password_change_approved',
        );
      } catch (e) {
        _secureLog('⚠️ OneSignal push failed: $e');
      }

      try {
        await FirebaseFirestore.instance
            .collection('activity_logs')
            .add({
          'type': 'password_change_approved',
          'action': 'Password Changed by Admin',
          'employeeId': empDocId,
          'employee_id': n.employeeIdentifier ?? empDocId,
          'employee_name': n.employeeName ?? 'Unknown',
          'approvedBy': adminEmail,
          'requestId': n.id,
          'pinChanged': true,
          'timestamp': FieldValue.serverTimestamp(),
        });
      } catch (_) {}

      await _logAudit(
        'password_change_approved',
        'Approved & reset PIN for '
            '${n.employeeName ?? n.employeeId ?? "unknown"}',
      );

      if (!kIsWeb) HapticFeedback.mediumImpact();

      if (mounted) _showNewPinDialog(n, newPin);
    } catch (e, st) {
      _secureLog('❌ Approve failed: $e\n$st');
      _showSnack('⚠️ Failed: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // REGENERATE PIN (With OneSignal Push)
  // ═══════════════════════════════════════════════════════════════
  Future<void> _regeneratePinForApproved(AdminNotification n) async {
    if (_isDemo) {
      _demoBlock();
      return;
    }
    if (!_checkRateLimit()) {
      _showSnack('⚠️ Too fast. Please wait a few seconds.');
      return;
    }

    try {
      final adminId =
      await SecurityHardeningService.instance.getCurrentEmployeeId();
      final adminEmail =
          FirebaseAuth.instance.currentUser?.email?.toLowerCase().trim() ??
              'unknown';

      final newPin = _generateNewPin();
      final salt = _randomSalt();
      final hash = _saltedHash(newPin, salt);

      final empDocId = n.employeeId ?? n.metadata['employeeId']?.toString();
      if (empDocId == null || empDocId.isEmpty) {
        _showSnack('⚠️ Employee ID not found.');
        return;
      }

      final empDoc = await FirebaseFirestore.instance
          .collection('employees')
          .doc(empDocId)
          .get();
      if (!empDoc.exists) {
        _showSnack('⚠️ Employee not found: $empDocId');
        return;
      }

      await FirebaseFirestore.instance
          .collection('employees')
          .doc(empDocId)
          .set({
        'pin': newPin,
        'pinHash': hash,
        'pinSalt': salt,
        'pinUpdatedAt': FieldValue.serverTimestamp(),
        'pinUpdatedBy': adminEmail,
        'requiresPinChange': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await FirebaseFirestore.instance
          .collection('admin_notifications')
          .doc(n.id)
          .update({
        'metadata.newPin': newPin,
        'metadata.pinGeneratedAt': FieldValue.serverTimestamp(),
        'metadata.pinRegeneratedBy': adminId,
      });

      // 1. Save to In-App Database
      try {
        await FirebaseFirestore.instance
            .collection('employee_notifications')
            .add({
          'employeeId': empDocId,
          'title': '🔐 New PIN Generated',
          'message': 'Admin generated a new PIN for you.\n\nYOUR NEW PIN: $newPin\n\nUse this on your next login.',
          'type': 'password_change_approved',
          'newPin': newPin,
          'requestId': n.id,
          'priority': 'high',
          'read': false,
          'timestamp': FieldValue.serverTimestamp(),
        });
      } catch (_) {}

      // 2. Send OneSignal Push Notification
      try {
        await OneSignalSender.instance.sendToEmployee(
          employeeId: empDocId,
          title: '🔐 New PIN Generated',
          message: 'Admin generated a new PIN for you: $newPin',
          type: 'password_change_approved',
        );
      } catch (e) {
        _secureLog('⚠️ OneSignal push failed: $e');
      }

      await _logAudit(
        'password_pin_regenerated',
        'Regenerated PIN for ${n.employeeName ?? "unknown"} (notif=${n.id})',
      );

      if (!kIsWeb) HapticFeedback.mediumImpact();
      if (mounted) _showNewPinDialog(n, newPin);
    } catch (e) {
      _secureLog('❌ Regenerate failed: $e');
      _showSnack('⚠️ Failed: $e');
    }
  }

  void _showNewPinDialog(AdminNotification n, String newPin) {
    final tc = AdminTheme.getColors(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (ctx) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          backgroundColor: tc.card,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_rounded,
                    color: Colors.green, size: 32),
              ),
              const SizedBox(height: 16),
              const Text(
                'Password Reset Successful',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'New PIN for ${n.employeeName ?? "employee"}:',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: tc.textMuted),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 20),
                decoration: BoxDecoration(
                  color: tc.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: tc.orange.withValues(alpha: 0.4),
                      width: 1.5),
                ),
                child: Column(
                  children: [
                    Text(
                      newPin,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 44,
                        fontWeight: FontWeight.w900,
                        color: tc.orange,
                        letterSpacing: 10,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: newPin));
                        _showSnack('📋 PIN copied to clipboard');
                      },
                      icon: Icon(Icons.copy_rounded,
                          size: 16, color: tc.orange),
                      label: Text(
                        'Copy PIN',
                        style: TextStyle(
                          color: tc.orange,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.send_rounded,
                        color: Colors.green, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Auto-notified sa employee app — lalabas agad ang PIN sa kanilang device.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: tc.text,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  if (mounted) setState(() {});
                },
                style: FilledButton.styleFrom(
                  backgroundColor: tc.orange,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('Done — Employee Notified',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // REJECT REQUEST (With OneSignal Push)
  // ═══════════════════════════════════════════════════════════════
  Future<void> _rejectRequest(AdminNotification n, String reason) async {
    if (_isDemo) {
      _demoBlock();
      return;
    }
    if (!_checkRateLimit()) {
      _showSnack('⚠️ Too fast. Please wait a few seconds.');
      return;
    }

    try {
      final adminId =
      await SecurityHardeningService.instance.getCurrentEmployeeId();
      final adminEmail =
          FirebaseAuth.instance.currentUser?.email?.toLowerCase().trim() ??
              'unknown';

      await FirebaseFirestore.instance
          .collection('admin_notifications')
          .doc(n.id)
          .update({
        'status': 'rejected',
        'read': true,
        'metadata.rejectedBy': adminId,
        'metadata.rejectedAt': FieldValue.serverTimestamp(),
        'metadata.rejectReason':
        reason.isEmpty ? 'No reason provided' : reason,
      });

      final empDocId = n.employeeId ?? n.metadata['employeeId']?.toString();
      if (empDocId != null && empDocId.isNotEmpty) {
        try {
          await FirebaseFirestore.instance
              .collection('employees')
              .doc(empDocId)
              .set({
            'pinChangeAllowed': false,
            'pinChangeRejected': true,
            'pinChangeRejectReason':
            reason.isEmpty ? 'No reason provided' : reason,
            'pinChangeRejectedAt': FieldValue.serverTimestamp(),
            'requiresPinChange': false,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

          // 1. Save to In-App Database
          await FirebaseFirestore.instance
              .collection('employee_notifications')
              .add({
            'employeeId': empDocId,
            'title': '❌ Password Change Rejected',
            'message': reason.isEmpty
                ? 'Your password change request was rejected.'
                : 'Your password change request was rejected: $reason',
            'type': 'password_change_rejected',
            'requestId': n.id,
            'reason': reason,
            'priority': 'high',
            'read': false,
            'timestamp': FieldValue.serverTimestamp(),
          });

          // 2. Send OneSignal Push Notification
          try {
            await OneSignalSender.instance.sendToEmployee(
              employeeId: empDocId,
              title: '❌ Password Change Rejected',
              message: reason.isEmpty
                  ? 'Your password change request was rejected.'
                  : 'Your password change request was rejected: $reason',
              type: 'password_change_rejected',
            );
          } catch (e) {
            _secureLog('⚠️ OneSignal push failed: $e');
          }

          await FirebaseFirestore.instance
              .collection('activity_logs')
              .add({
            'type': 'password_change_rejected',
            'action': 'Password Change Rejected',
            'employeeId': empDocId,
            'employee_id': n.employeeIdentifier ?? empDocId,
            'employee_name': n.employeeName ?? 'Unknown',
            'rejectedBy': adminEmail,
            'reason': reason,
            'requestId': n.id,
            'timestamp': FieldValue.serverTimestamp(),
          });
        } catch (e) {
          _secureLog('⚠️ Failed to update employee doc (reject): $e');
        }
      }

      await _logAudit(
        'password_change_rejected',
        'Rejected password change for '
            '${n.employeeName ?? n.employeeId ?? "unknown"}',
      );

      if (!kIsWeb) HapticFeedback.mediumImpact();
      _showSnack('🚫 Request rejected.');
    } catch (e) {
      _secureLog('Reject failed: $e');
      _showSnack('⚠️ Failed to reject request.');
    }
  }

  Future<void> _resetStatusToPending(AdminNotification n) async {
    if (_isDemo) {
      _demoBlock();
      return;
    }
    if (!_checkRateLimit()) {
      _showSnack('⚠️ Too fast. Please wait a few seconds.');
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('admin_notifications')
          .doc(n.id)
          .update({
        'status': 'pending',
        'read': false,
        'metadata.approvedBy': null,
        'metadata.approvedAt': null,
        'metadata.newPin': null,
        'metadata.rejectedBy': null,
        'metadata.rejectedAt': null,
        'metadata.rejectReason': null,
      });

      final empDocId = n.employeeId ?? n.metadata['employeeId']?.toString();
      if (empDocId != null && empDocId.isNotEmpty) {
        try {
          await FirebaseFirestore.instance
              .collection('employees')
              .doc(empDocId)
              .set({
            'pinChangeAllowed': false,
            'pinChangeRejected': false,
            'pinChangeRejectReason': null,
            'requiresPinChange': false,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } catch (_) {}
      }

      await _logAudit(
        'password_change_reset',
        'Reset to pending: '
            '${n.employeeName ?? n.employeeId ?? "unknown"}',
      );
      _showSnack('↩️ Reset to pending.');
    } catch (e) {
      _secureLog('Reset failed: $e');
    }
  }

  List<AdminNotification> _applyFilter(List<AdminNotification> input) {
    var list = List<AdminNotification>.from(input);

    switch (_statusFilter) {
      case _StatusFilter.pending:
        list = list
            .where((n) => (n.status ?? 'pending') == 'pending')
            .toList();
        break;
      case _StatusFilter.approved:
        list = list.where((n) => n.status == 'approved').toList();
        break;
      case _StatusFilter.rejected:
        list = list.where((n) => n.status == 'rejected').toList();
        break;
      case _StatusFilter.all:
        break;
    }

    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list.where((n) {
        return n.title.toLowerCase().contains(q) ||
            n.message.toLowerCase().contains(q) ||
            (n.employeeName?.toLowerCase().contains(q) ?? false) ||
            (n.employeeIdentifier?.toLowerCase().contains(q) ?? false) ||
            (n.reason?.toLowerCase().contains(q) ?? false);
      }).toList();
    }

    list.sort((a, b) {
      final at = a.timestamp ?? DateTime(2000);
      final bt = b.timestamp ?? DateTime(2000);
      return bt.compareTo(at);
    });

    return list;
  }

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
          'Password Change Requests',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: tc.text,
          ),
        ),
        actions: [
          IconButton(
            tooltip: _isDemo ? 'Refresh disabled in Demo' : 'Refresh',
            icon: Icon(Icons.refresh_rounded,
                color: _isDemo ? tc.muted : tc.textMuted, size: 20),
            onPressed: _isDemo ? null : () => setState(() {}),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isDemo
          ? _buildDemoBody(tc)
          : StreamBuilder<List<AdminNotification>>(
        stream:
        AdminNotificationService.instance.streamAll(limit: 200),
        builder: (context, snap) {
          if (snap.hasError) {
            return _errorState(tc, '${snap.error}');
          }
          if (!snap.hasData) {
            return _skeletonLoader(tc);
          }

          final pwdRequests = (snap.data ?? [])
              .where((n) => n.type == 'password_change')
              .toList();

          final filtered = _applyFilter(pwdRequests);

          return Column(
            children: [
              _buildToolbar(tc, pwdRequests),
              Expanded(
                child: filtered.isEmpty
                    ? _emptyState(tc)
                    : RefreshIndicator(
                  color: tc.orange,
                  onRefresh: () async {
                    await Future.delayed(
                        const Duration(milliseconds: 400));
                    if (mounted) setState(() {});
                  },
                  child: ListView.builder(
                    padding:
                    const EdgeInsets.fromLTRB(12, 8, 12, 24),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) =>
                        _buildCard(tc, filtered[i]),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDemoBody(AdminColors tc) {
    final all = _getMockRequests();
    final filtered = _applyFilter(all);

    return Column(
      children: [
        _buildDemoBanner(tc),
        _buildToolbar(tc, all),
        Expanded(
          child: filtered.isEmpty
              ? _emptyState(tc)
              : ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            itemCount: filtered.length,
            itemBuilder: (_, i) => _buildCard(tc, filtered[i]),
          ),
        ),
      ],
    );
  }

  Widget _buildDemoBanner(AdminColors tc) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: tc.orange.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tc.orange.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(Icons.science_rounded, color: tc.orange, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Demo Mode — showing sample requests. Approve, reject, and reset actions are disabled.',
              style: TextStyle(
                fontSize: 11,
                color: tc.orange,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(AdminColors tc, List<AdminNotification> all) {
    final pendingCount =
        all.where((n) => (n.status ?? 'pending') == 'pending').length;
    final approvedCount =
        all.where((n) => n.status == 'approved').length;
    final rejectedCount =
        all.where((n) => n.status == 'rejected').length;

    return Container(
      decoration: BoxDecoration(
        color: tc.topBarBg,
        border: Border(bottom: BorderSide(color: tc.border, width: 1)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: tc.isDark
                    ? Colors.white.withValues(alpha: 0.04)
                    : const Color(0xFFF4F4F5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: tc.border, width: 1),
              ),
              child: TextField(
                controller: _searchCtrl,
                style: TextStyle(
                  color: tc.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                cursorColor: tc.orange,
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  hintText: 'Search by name, ID, or reason...',
                  hintStyle: TextStyle(color: tc.textMuted, fontSize: 13),
                  prefixIcon: Icon(Icons.search_rounded,
                      color: tc.textMuted, size: 18),
                  prefixIconConstraints:
                  const BoxConstraints(minWidth: 36, minHeight: 36),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                    icon: Icon(Icons.close_rounded,
                        size: 16, color: tc.textMuted),
                    onPressed: () {
                      _searchCtrl.clear();
                      _onSearchChanged('');
                    },
                    splashRadius: 18,
                  )
                      : null,
                  border: InputBorder.none,
                ),
                onChanged: _onSearchChanged,
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                _statusChip(tc,
                    label: 'Pending',
                    count: pendingCount,
                    filter: _StatusFilter.pending),
                const SizedBox(width: 8),
                _statusChip(tc,
                    label: 'Approved',
                    count: approvedCount,
                    filter: _StatusFilter.approved),
                const SizedBox(width: 8),
                _statusChip(tc,
                    label: 'Rejected',
                    count: rejectedCount,
                    filter: _StatusFilter.rejected),
                const SizedBox(width: 8),
                _statusChip(tc,
                    label: 'All',
                    count: all.length,
                    filter: _StatusFilter.all),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(
      AdminColors tc, {
        required String label,
        required int count,
        required _StatusFilter filter,
      }) {
    final active = _statusFilter == filter;
    return GestureDetector(
      onTap: () => setState(() => _statusFilter = filter),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? tc.orange.withValues(alpha: 0.15)
              : (tc.isDark
              ? Colors.white.withValues(alpha: 0.04)
              : const Color(0xFFF4F4F5)),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active ? tc.orange : tc.border.withValues(alpha: 0.6),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: active ? tc.orange : tc.text,
                fontSize: 12.5,
                fontWeight: active ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              constraints: const BoxConstraints(minWidth: 18),
              decoration: BoxDecoration(
                color: active
                    ? tc.orange
                    : (tc.isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.black.withValues(alpha: 0.06)),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                count > 99 ? '99+' : '$count',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: active ? Colors.white : tc.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _query = value.trim());
    });
  }

  Widget _buildCard(AdminColors tc, AdminNotification n) {
    final status = n.status ?? 'pending';
    final statusColor = _statusColor(status, tc);
    final statusBg = _statusBg(status, tc);
    final time = n.timestamp != null ? _fmtTime(n.timestamp!) : '';
    final savedPin = n.metadata['newPin']?.toString();
    final hasPin = savedPin != null && savedPin.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: status == 'pending'
              ? tc.orange.withValues(alpha: 0.4)
              : tc.border,
          width: status == 'pending' ? 1.5 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showDetailSheet(tc, n),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: tc.orange.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: tc.orange.withValues(alpha: 0.35),
                            width: 1),
                      ),
                      child: Center(
                        child: Text(
                          _initials(n.employeeName ?? '?'),
                          style: TextStyle(
                            color: tc.orange,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _sanitize(n.employeeName ?? 'Unknown Employee'),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: tc.text,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _sanitize(
                                n.employeeIdentifier ?? n.employeeId ?? '—'),
                            style: TextStyle(
                              fontSize: 11.5,
                              color: tc.textMuted,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: statusColor.withValues(alpha: 0.4),
                            width: 1),
                      ),
                      child: Text(
                        status.toUpperCase(),
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: statusColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if ((n.reason ?? '').isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: tc.isDark
                          ? Colors.white.withValues(alpha: 0.03)
                          : const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: tc.border.withValues(alpha: 0.6),
                          width: 1),
                    ),
                    child: Text(
                      _sanitize(n.reason!),
                      style: TextStyle(
                        fontSize: 12.5,
                        color: tc.text,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                if (status == 'approved') ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: hasPin
                          ? Colors.green.withValues(alpha: 0.1)
                          : Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: hasPin
                            ? Colors.green.withValues(alpha: 0.4)
                            : Colors.orange.withValues(alpha: 0.4),
                        width: 1.2,
                      ),
                    ),
                    child: hasPin
                        ? Row(
                      children: [
                        const Icon(Icons.vpn_key_rounded,
                            color: Colors.green, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'NEW PIN:',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Colors.green,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          savedPin,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: Colors.green,
                            letterSpacing: 4,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () {
                            Clipboard.setData(
                                ClipboardData(text: savedPin));
                            _showSnack('📋 PIN copied');
                          },
                          icon: const Icon(Icons.copy_rounded,
                              size: 18, color: Colors.green),
                          splashRadius: 18,
                          tooltip: 'Copy PIN',
                        ),
                      ],
                    )
                        : Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            color: Colors.orange, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'No PIN saved yet',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.orange,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _isDemo
                              ? _demoBlock
                              : () => _regeneratePinForApproved(n),
                          icon: const Icon(Icons.refresh_rounded,
                              size: 14, color: Colors.orange),
                          label: const Text(
                            'Generate PIN',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.orange,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.access_time_rounded,
                        size: 12, color: tc.textMuted),
                    const SizedBox(width: 4),
                    Text(
                      time,
                      style: TextStyle(
                        fontSize: 11,
                        color: tc.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    if (status == 'pending') ...[
                      _smallButton(
                        tc,
                        label: 'Reject',
                        icon: Icons.close_rounded,
                        color: _isDemo ? tc.muted : tc.red,
                        onTap: _isDemo ? _demoBlock : () => _confirmReject(tc, n),
                      ),
                      const SizedBox(width: 6),
                      _smallButton(
                        tc,
                        label: 'Approve & Reset',
                        icon: Icons.check_rounded,
                        color: _isDemo ? tc.muted : Colors.green,
                        filled: !_isDemo,
                        onTap: _isDemo ? _demoBlock : () => _confirmApprove(tc, n),
                      ),
                    ] else if (status == 'approved' && hasPin) ...[
                      _smallButton(
                        tc,
                        label: 'Show PIN',
                        icon: Icons.visibility_rounded,
                        color: _isDemo ? tc.muted : tc.orange,
                        onTap: _isDemo ? _demoBlock : () => _showNewPinDialog(n, savedPin),
                      ),
                      const SizedBox(width: 6),
                      _smallButton(
                        tc,
                        label: 'Regenerate',
                        icon: Icons.refresh_rounded,
                        color: _isDemo ? tc.muted : Colors.green,
                        filled: !_isDemo,
                        onTap: _isDemo ? _demoBlock : () => _regeneratePinForApproved(n),
                      ),
                    ] else if (status == 'approved') ...[
                      _smallButton(
                        tc,
                        label: 'Generate PIN',
                        icon: Icons.vpn_key_rounded,
                        color: _isDemo ? tc.muted : Colors.green,
                        filled: !_isDemo,
                        onTap: _isDemo ? _demoBlock : () => _regeneratePinForApproved(n),
                      ),
                    ] else
                      _smallButton(
                        tc,
                        label: 'View',
                        icon: Icons.arrow_forward_rounded,
                        color: tc.orange,
                        onTap: () => _showDetailSheet(tc, n),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _smallButton(
      AdminColors tc, {
        required String label,
        required IconData icon,
        required Color color,
        required VoidCallback onTap,
        bool filled = false,
      }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: filled ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: filled ? Colors.white : color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: filled ? Colors.white : color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.isEmpty ? '?' : parts.first[0].toUpperCase();
    }
    final a = parts.first.isEmpty ? '' : parts.first[0];
    final b = parts.last.isEmpty ? '' : parts.last[0];
    return '$a$b'.toUpperCase();
  }

  void _showDetailSheet(AdminColors tc, AdminNotification n) {
    final status = n.status ?? 'pending';
    final statusColor = _statusColor(status, tc);
    final meta = n.metadata;
    final savedPin = meta['newPin']?.toString();
    final hasPin = savedPin != null && savedPin.isNotEmpty;

    showModalBottomSheet(
      context: context,
      backgroundColor: tc.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: tc.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: tc.orange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(
                          color: tc.orange.withValues(alpha: 0.4),
                          width: 1),
                    ),
                    child: Icon(Icons.lock_reset_rounded,
                        color: tc.orange, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Password Change Request',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Requested ${n.timestamp != null ? _fullTime(n.timestamp!) : "—"}',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: tc.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _statusBg(status, tc),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: statusColor.withValues(alpha: 0.4),
                          width: 1),
                    ),
                    child: Text(
                      status.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: statusColor,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _kv(tc, 'Employee', _sanitize(n.employeeName ?? '—')),
              _kv(tc, 'Employee ID',
                  _sanitize(n.employeeIdentifier ?? n.employeeId ?? '—')),
              if ((n.employeeEmail ?? '').isNotEmpty)
                _kv(tc, 'Email', _sanitize(n.employeeEmail!)),
              _kv(tc, 'Reason',
                  _sanitize(n.reason ?? meta['reason']?.toString() ?? '—')),

              if (status == 'approved') ...[
                const SizedBox(height: 4),
                _kv(tc, 'Approved By',
                    _sanitize(meta['approvedByEmail']?.toString() ??
                        meta['approvedBy']?.toString() ??
                        '—')),
                _kv(
                  tc,
                  'Approved At',
                  meta['approvedAt'] is Timestamp
                      ? _fullTime(
                      (meta['approvedAt'] as Timestamp).toDate())
                      : '—',
                ),
                const SizedBox(height: 12),
                if (hasPin)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Colors.green.withValues(alpha: 0.4),
                          width: 1.5),
                    ),
                    child: Column(
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.vpn_key_rounded,
                                color: Colors.green, size: 14),
                            SizedBox(width: 6),
                            Text(
                              'NEW PIN',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: Colors.green,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          savedPin,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w900,
                            color: Colors.green,
                            letterSpacing: 10,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            TextButton.icon(
                              onPressed: () {
                                Clipboard.setData(
                                    ClipboardData(text: savedPin));
                                _showSnack('📋 PIN copied');
                              },
                              icon: const Icon(Icons.copy_rounded,
                                  size: 14, color: Colors.green),
                              label: const Text(
                                'Copy',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            TextButton.icon(
                              onPressed: _isDemo
                                  ? _demoBlock
                                  : () {
                                Navigator.pop(ctx);
                                _regeneratePinForApproved(n);
                              },
                              icon: const Icon(Icons.refresh_rounded,
                                  size: 14, color: Colors.orange),
                              label: const Text(
                                'Regenerate',
                                style: TextStyle(
                                  color: Colors.orange,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Colors.orange.withValues(alpha: 0.4),
                          width: 1.2),
                    ),
                    child: Column(
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.warning_amber_rounded,
                                color: Colors.orange, size: 16),
                            SizedBox(width: 6),
                            Text(
                              'PIN NOT SAVED',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: Colors.orange,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Approved before PIN generation was added.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: tc.textMuted,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed: _isDemo
                              ? _demoBlock
                              : () {
                            Navigator.pop(ctx);
                            _regeneratePinForApproved(n);
                          },
                          icon: const Icon(Icons.vpn_key_rounded,
                              size: 16),
                          label: const Text('Generate New PIN',
                              style:
                              TextStyle(fontWeight: FontWeight.w700)),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.orange,
                            padding:
                            const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],

              if (status == 'rejected') ...[
                const SizedBox(height: 4),
                _kv(tc, 'Rejected By',
                    _sanitize(meta['rejectedBy']?.toString() ?? '—')),
                _kv(
                  tc,
                  'Rejected At',
                  meta['rejectedAt'] is Timestamp
                      ? _fullTime(
                      (meta['rejectedAt'] as Timestamp).toDate())
                      : '—',
                ),
                _kv(tc, 'Reject Reason',
                    _sanitize(meta['rejectReason']?.toString() ?? '—')),
              ],

              const SizedBox(height: 20),
              Row(
                children: [
                  if (status == 'pending') ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isDemo
                            ? _demoBlock
                            : () async {
                          Navigator.pop(ctx);
                          await _confirmReject(tc, n);
                        },
                        icon: Icon(Icons.close_rounded,
                            size: 16, color: _isDemo ? tc.muted : tc.red),
                        label: Text('Reject',
                            style: TextStyle(
                                color: _isDemo ? tc.muted : tc.red,
                                fontWeight: FontWeight.w700)),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                              color: _isDemo ? tc.border : tc.red),
                          padding:
                          const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _isDemo
                            ? _demoBlock
                            : () async {
                          Navigator.pop(ctx);
                          await _confirmApprove(tc, n);
                        },
                        icon: Icon(Icons.check_rounded,
                            size: 16,
                            color: _isDemo ? tc.muted : Colors.white),
                        label: Text('Approve & Reset',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: _isDemo ? tc.muted : Colors.white)),
                        style: FilledButton.styleFrom(
                          backgroundColor:
                          _isDemo ? tc.border : Colors.green,
                          padding:
                          const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ] else
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isDemo
                            ? _demoBlock
                            : () {
                          Navigator.pop(ctx);
                          _resetStatusToPending(n);
                        },
                        icon: Icon(Icons.undo_rounded,
                            size: 16, color: _isDemo ? tc.muted : tc.orange),
                        label: Text('Reset to Pending',
                            style: TextStyle(
                                color: _isDemo ? tc.muted : tc.orange,
                                fontWeight: FontWeight.w700)),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                              color: _isDemo ? tc.border : tc.orange),
                          padding:
                          const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Close',
                      style: TextStyle(
                          color: tc.textMuted,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kv(AdminColors tc, String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              k,
              style: TextStyle(
                fontSize: 12,
                color: tc.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: TextStyle(
                fontSize: 12.5,
                color: tc.text,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmApprove(AdminColors tc, AdminNotification n) async {
    if (_isDemo) {
      _demoBlock();
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: tc.card,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.check_circle_rounded,
                  color: Colors.green, size: 20),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Approve & Reset PIN?',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: Text(
          'Approve the request of '
              '${n.employeeName ?? "this employee"}?\n\n'
              'A new 4-digit PIN will be generated and AUTO-SENT to their app.',
          style: TextStyle(
            fontSize: 13,
            color: tc.textMuted,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: TextStyle(
                    color: tc.textMuted, fontWeight: FontWeight.w700)),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.check_rounded, size: 16),
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
            label: const Text('Approve & Reset',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (ok == true) {
      await _approveRequest(n);
    }
  }

  Future<void> _confirmReject(AdminColors tc, AdminNotification n) async {
    if (_isDemo) {
      _demoBlock();
      return;
    }

    final reasonCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: tc.card,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: tc.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.cancel_rounded, color: tc.red, size: 20),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Reject Request?',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tell ${n.employeeName ?? "the employee"} why this request '
                  'is being rejected.',
              style: TextStyle(
                fontSize: 13,
                color: tc.textMuted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              maxLength: 200,
              decoration: InputDecoration(
                labelText: 'Reject reason (optional)',
                hintText: 'e.g. Please contact HR in person',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: TextStyle(
                    color: tc.textMuted, fontWeight: FontWeight.w700)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: tc.red),
            child: const Text('Reject',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (ok == true) {
      await _rejectRequest(n, reasonCtrl.text.trim());
    }

    reasonCtrl.dispose();
  }

  Color _statusColor(String status, AdminColors tc) {
    switch (status) {
      case 'approved':
        return Colors.green;
      case 'rejected':
        return tc.red;
      default:
        return tc.orange;
    }
  }

  Color _statusBg(String status, AdminColors tc) {
    return _statusColor(status, tc).withValues(alpha: 0.12);
  }

  String _fmtTime(DateTime d) {
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d').format(d);
  }

  String _fullTime(DateTime d) =>
      DateFormat('MMM d, yyyy · hh:mm a').format(d);

  Widget _skeletonLoader(AdminColors tc) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (int i = 0; i < 5; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            height: 140,
            decoration: BoxDecoration(
              color: tc.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: tc.border, width: 1),
            ),
          ),
      ],
    );
  }

  Widget _emptyState(AdminColors tc) {
    String msg;
    IconData icon;
    switch (_statusFilter) {
      case _StatusFilter.pending:
        icon = Icons.check_circle_outline_rounded;
        msg = 'No pending password change requests.\nAll caught up! 🎉';
        break;
      case _StatusFilter.approved:
        icon = Icons.verified_rounded;
        msg = 'No approved requests yet.';
        break;
      case _StatusFilter.rejected:
        icon = Icons.cancel_outlined;
        msg = 'No rejected requests.';
        break;
      case _StatusFilter.all:
      default:
        icon = Icons.lock_reset_rounded;
        msg = 'No password change requests yet.\n'
            'Requests submitted from the login screen will appear here.';
        break;
    }

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
              child: Icon(icon, size: 32, color: tc.orange),
            ),
            const SizedBox(height: 16),
            Text(
              _query.isNotEmpty ? 'No matches found' : 'No requests',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: tc.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _query.isNotEmpty ? 'Try a different search term.' : msg,
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
              'Error loading requests',
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