// lib/screens/admin_demo_requests_screen.dart
// v2.0: 🎨 UI overhauled to match Password Change Requests page.
//       📊 Status chips with counts + search toolbar.
//       📇 Cards with initials avatar, orange border on pending.
//       📋 Detail bottom sheet with kv rows + actions.
//       🎭 Demo mode with sample data.
//       🔔 Supports initialFilter for email-issues alert deep-link.
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show HapticFeedback, Clipboard, ClipboardData;
import 'package:intl/intl.dart';
import '../services/demo_mode_service.dart';
import '../services/demo_request_service.dart';
import 'admin_theme.dart';

void _secureLog(String msg) {
  if (kDebugMode) debugPrint('[AdminDemoReq] $msg');
}

enum _StatusFilter { pending, approved, rejected, emailFailed, all }

class _ApproveOpts {
  final double validHours;
  final int maxUses;
  const _ApproveOpts(this.validHours, this.maxUses);
}

class AdminDemoRequestsScreen extends StatefulWidget {
  const AdminDemoRequestsScreen({
    super.key,
    this.embedded = false,
    this.onBack,
    this.initialFilter = 'pending',
  });

  final bool embedded;
  final VoidCallback? onBack;
  final String initialFilter;

  @override
  State<AdminDemoRequestsScreen> createState() =>
      _AdminDemoRequestsScreenState();
}

class _AdminDemoRequestsScreenState extends State<AdminDemoRequestsScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  String _query = '';
  _StatusFilter _statusFilter = _StatusFilter.pending;

  // 🔒 Rate limiting (mirrors password change page)
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

  @override
  void initState() {
    super.initState();
    _statusFilter = _parseFilter(widget.initialFilter);
  }

  @override
  void didUpdateWidget(covariant AdminDemoRequestsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialFilter != widget.initialFilter) {
      setState(() => _statusFilter = _parseFilter(widget.initialFilter));
    }
  }

  _StatusFilter _parseFilter(String s) {
    switch (s) {
      case 'approved':
        return _StatusFilter.approved;
      case 'rejected':
        return _StatusFilter.rejected;
      case 'emailFailed':
        return _StatusFilter.emailFailed;
      case 'all':
        return _StatusFilter.all;
      default:
        return _StatusFilter.pending;
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════
  // Helpers
  // ═══════════════════════════════════════════════════════════════
  bool _checkRateLimit() {
    final now = DateTime.now();
    _destructiveTimes.removeWhere((t) => now.difference(t) > _rateWindow);
    if (_destructiveTimes.length >= _maxDestructive) return false;
    _destructiveTimes.add(now);
    return true;
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

  void _showSnack(String msg, {Color? bg}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
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

  String _fmtExpiry(DateTime? dt) {
    if (dt == null) return '—';
    final diff = dt.difference(DateTime.now());
    if (diff.isNegative) return 'expired';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m left';
    if (diff.inHours < 24) return '${diff.inHours}h left';
    return '${diff.inDays}d left';
  }

  // ═══════════════════════════════════════════════════════════════
  // Demo data
  // ═══════════════════════════════════════════════════════════════
  List<Map<String, dynamic>> _getMockRequests() {
    final now = DateTime.now();
    return [
      {
        'id': 'demo_req_1',
        'name': 'Carlos Mendoza',
        'email': 'carlos.mendoza@example.com',
        'company': 'Acme Corp',
        'phone': '+63 917 555 0101',
        'reason': 'Evaluating for our HR team of 50 employees.',
        'status': 'pending',
        'requestedAt': Timestamp.fromDate(
            now.subtract(const Duration(minutes: 8))),
        'accessCode': null,
        'expiresAt': null,
        'maxUses': 1,
        'usedCount': 0,
        'rejectReason': '',
        'emailError': '',
      },
      {
        'id': 'demo_req_2',
        'name': 'Lucia Fernandez',
        'email': 'lucia.f@brightco.ph',
        'company': 'BrightCo Philippines',
        'phone': '+63 918 555 0202',
        'reason': 'Want to test attendance + payroll features.',
        'status': 'pending',
        'requestedAt': Timestamp.fromDate(
            now.subtract(const Duration(hours: 1, minutes: 20))),
        'accessCode': null,
        'expiresAt': null,
        'maxUses': 1,
        'usedCount': 0,
        'rejectReason': '',
        'emailError': '',
      },
      {
        'id': 'demo_req_3',
        'name': 'Rafael Torres',
        'email': 'r.torres@techstart.io',
        'company': 'TechStart IO',
        'phone': '+63 919 555 0303',
        'reason': 'CEO demo for investor presentation.',
        'status': 'approved',
        'requestedAt': Timestamp.fromDate(
            now.subtract(const Duration(hours: 4))),
        'accessCode': 'DEMO42',
        'expiresAt': Timestamp.fromDate(now.add(const Duration(hours: 2))),
        'maxUses': 3,
        'usedCount': 1,
        'rejectReason': '',
        'emailError': '',
      },
      {
        'id': 'demo_req_4',
        'name': 'Amara Reyes',
        'email': 'amara@localbiz.ph',
        'company': 'LocalBiz',
        'phone': '',
        'reason': 'Requested demo for small business trial.',
        'status': 'rejected',
        'requestedAt': Timestamp.fromDate(
            now.subtract(const Duration(days: 1, hours: 2))),
        'accessCode': null,
        'expiresAt': null,
        'maxUses': 1,
        'usedCount': 0,
        'rejectReason': 'Too many trial requests from this domain.',
        'emailError': '',
      },
      {
        'id': 'demo_req_5',
        'name': 'Ben Santos',
        'email': 'ben.santos@mailbox.com',
        'company': '',
        'phone': '',
        'reason': 'Testing for personal project.',
        'status': 'email_failed',
        'requestedAt': Timestamp.fromDate(
            now.subtract(const Duration(hours: 18))),
        'accessCode': null,
        'expiresAt': null,
        'maxUses': 1,
        'usedCount': 0,
        'rejectReason': '',
        'emailError': 'Gmail SMTP timeout — auto-marked after 5 minutes',
      },
    ];
  }

  // ═══════════════════════════════════════════════════════════════
  // Filtering
  // ═══════════════════════════════════════════════════════════════
  List<Map<String, dynamic>> _applyFilter(
      List<Map<String, dynamic>> input) {
    var list = List<Map<String, dynamic>>.from(input);

    switch (_statusFilter) {
      case _StatusFilter.pending:
        list = list
            .where((d) => (d['status'] ?? '') == 'pending')
            .toList();
        break;
      case _StatusFilter.approved:
        list =
            list.where((d) => d['status'] == 'approved').toList();
        break;
      case _StatusFilter.rejected:
        list =
            list.where((d) => d['status'] == 'rejected').toList();
        break;
      case _StatusFilter.emailFailed:
        list = list
            .where((d) =>
        d['status'] == 'email_failed' || d['status'] == 'sending')
            .toList();
        break;
      case _StatusFilter.all:
        break;
    }

    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list.where((d) {
        final name = (d['name'] ?? '').toString().toLowerCase();
        final email = (d['email'] ?? '').toString().toLowerCase();
        final company = (d['company'] ?? '').toString().toLowerCase();
        final reason = (d['reason'] ?? '').toString().toLowerCase();
        return name.contains(q) ||
            email.contains(q) ||
            company.contains(q) ||
            reason.contains(q);
      }).toList();
    }

    list.sort((a, b) {
      final at = (a['requestedAt'] as Timestamp?)?.toDate() ??
          DateTime(2000);
      final bt = (b['requestedAt'] as Timestamp?)?.toDate() ??
          DateTime(2000);
      return bt.compareTo(at);
    });

    return list;
  }

  // ═══════════════════════════════════════════════════════════════
  // Actions
  // ═══════════════════════════════════════════════════════════════
  Future<void> _confirmApprove({
    required AdminColors tc,
    required String requestId,
    required String name,
    required String email,
    required bool isExtension,
  }) async {
    if (_isDemo) {
      _demoBlock();
      return;
    }

    double validHours = 2;
    int maxUses = 1;

    final result = await showDialog<_ApproveOpts>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: tc.card,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: tc.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isExtension
                      ? Icons.autorenew_rounded
                      : Icons.verified_rounded,
                  color: tc.orange,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isExtension ? 'Regenerate Code?' : 'Approve Request?',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: tc.orangeLight,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: tc.orange.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          color: tc.text,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        email,
                        style: TextStyle(
                            color: tc.textMuted, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text('VALIDITY',
                    style: TextStyle(
                      color: tc.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    )),
                const SizedBox(height: 4),
                DropdownButtonFormField<double>(
                  initialValue: validHours,
                  dropdownColor: tc.card,
                  style: TextStyle(color: tc.text, fontSize: 13),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: tc.isDark
                        ? Colors.white.withValues(alpha: 0.04)
                        : const Color(0xFFF4F4F5),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: tc.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: tc.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                      BorderSide(color: tc.orange, width: 1.5),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: 0.5, child: Text('30 minutes')),
                    DropdownMenuItem(value: 1, child: Text('1 hour')),
                    DropdownMenuItem(value: 2, child: Text('2 hours')),
                    DropdownMenuItem(value: 4, child: Text('4 hours')),
                    DropdownMenuItem(value: 8, child: Text('8 hours')),
                    DropdownMenuItem(value: 24, child: Text('24 hours')),
                    DropdownMenuItem(value: 48, child: Text('48 hours')),
                    DropdownMenuItem(
                        value: 168, child: Text('7 days')),
                  ],
                  onChanged: (v) => setDlg(() => validHours = v ?? 2),
                ),
                const SizedBox(height: 10),
                Text('MAX USES',
                    style: TextStyle(
                      color: tc.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    )),
                const SizedBox(height: 4),
                DropdownButtonFormField<int>(
                  initialValue: maxUses,
                  dropdownColor: tc.card,
                  style: TextStyle(color: tc.text, fontSize: 13),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: tc.isDark
                        ? Colors.white.withValues(alpha: 0.04)
                        : const Color(0xFFF4F4F5),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: tc.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: tc.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                      BorderSide(color: tc.orange, width: 1.5),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: 1, child: Text('1 (single use)')),
                    DropdownMenuItem(value: 2, child: Text('2 uses')),
                    DropdownMenuItem(value: 3, child: Text('3 uses')),
                    DropdownMenuItem(value: 5, child: Text('5 uses')),
                    DropdownMenuItem(value: 10, child: Text('10 uses')),
                  ],
                  onChanged: (v) => setDlg(() => maxUses = v ?? 1),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: tc.orange.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: tc.orange.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.mail_outline_rounded,
                          size: 14, color: tc.orange),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'A 6-character code will be generated and emailed to $email.',
                          style: TextStyle(
                            fontSize: 11,
                            color: tc.orange,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel',
                  style: TextStyle(
                      color: tc.textMuted, fontWeight: FontWeight.w700)),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(
                ctx,
                _ApproveOpts(validHours, maxUses),
              ),
              icon: const Icon(Icons.check_rounded, size: 16),
              label: Text(isExtension ? 'Regenerate' : 'Approve & Send',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              style: FilledButton.styleFrom(backgroundColor: tc.orange),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;
    if (!_checkRateLimit()) {
      _showSnack('⚠️ Too fast. Please wait a few seconds.',
          bg: const Color(0xFFF59E0B));
      return;
    }

    try {
      await DemoRequestService.instance.approveRequest(
        requestId: requestId,
        adminUid: FirebaseAuth.instance.currentUser?.uid ?? 'admin',
        validHours: result.validHours.ceil(),
        maxUses: result.maxUses,
      );
      if (!kIsWeb) HapticFeedback.mediumImpact();
      if (!mounted) return;
      _showSnack(
        isExtension
            ? '✅ New code generated and emailed.'
            : '✅ Approved — code emailed to user.',
        bg: const Color(0xFF16A34A),
      );
    } catch (e) {
      _secureLog('Approve failed: $e');
      if (!mounted) return;
      _showSnack('❌ Failed: $e', bg: const Color(0xFFEF4444));
    }
  }

  Future<void> _confirmReject({
    required AdminColors tc,
    required String requestId,
    required String name,
  }) async {
    if (_isDemo) {
      _demoBlock();
      return;
    }

    final reasonCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: tc.card,
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reject demo request from $name?',
              style:
              TextStyle(fontSize: 13, color: tc.textMuted, height: 1.5),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              maxLength: 200,
              style: TextStyle(color: tc.text),
              cursorColor: tc.orange,
              decoration: InputDecoration(
                labelText: 'Reject reason (optional)',
                hintText: 'e.g. Suspicious account',
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

    if (ok != true) {
      reasonCtrl.dispose();
      return;
    }
    if (!_checkRateLimit()) {
      reasonCtrl.dispose();
      _showSnack('⚠️ Too fast. Please wait a few seconds.',
          bg: const Color(0xFFF59E0B));
      return;
    }

    try {
      await DemoRequestService.instance.rejectRequest(
        requestId: requestId,
        adminUid: FirebaseAuth.instance.currentUser?.uid ?? 'admin',
        reason: reasonCtrl.text.trim(),
      );
      if (!kIsWeb) HapticFeedback.mediumImpact();
      if (!mounted) return;
      _showSnack('🚫 Request rejected.');
    } catch (e) {
      _secureLog('Reject failed: $e');
      if (!mounted) return;
      _showSnack('⚠️ Failed: $e', bg: const Color(0xFFEF4444));
    } finally {
      reasonCtrl.dispose();
    }
  }

  void _copyCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    _showSnack('📋 Code copied: $code');
  }

  // ═══════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final tc = AdminTheme.getColors(context);

    final body = Column(
      children: [
        if (_isDemo) _buildDemoBanner(tc),
        _buildToolbar(tc),
        Expanded(
          child: _isDemo
              ? _buildDemoBody(tc)
              : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('demo_requests')
                .orderBy('requestedAt', descending: true)
                .limit(200)
                .snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return _errorState(tc, '${snap.error}');
              }
              if (!snap.hasData) {
                return _skeletonLoader(tc);
              }
              final docs = snap.data!.docs
                  .map((d) {
                final data = Map<String, dynamic>.from(d.data());
                data['id'] = d.id;
                return data;
              })
                  .toList();
              return _buildList(tc, docs);
            },
          ),
        ),
      ],
    );

    if (widget.embedded) return body;

    return Scaffold(
      backgroundColor: tc.background,
      appBar: AppBar(
        backgroundColor: tc.topBarBg,
        foregroundColor: tc.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: widget.onBack != null
            ? IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: tc.text),
          onPressed: widget.onBack,
        )
            : null,
        title: Text(
          'Demo Requests',
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
      body: body,
    );
  }

  Widget _buildList(AdminColors tc, List<Map<String, dynamic>> all) {
    final filtered = _applyFilter(all);
    if (filtered.isEmpty) return _emptyState(tc);

    return RefreshIndicator(
      color: tc.orange,
      onRefresh: () async {
        await Future.delayed(const Duration(milliseconds: 400));
        if (mounted) setState(() {});
      },
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        itemCount: filtered.length,
        itemBuilder: (_, i) => _buildCard(tc, filtered[i]),
      ),
    );
  }

  Widget _buildDemoBody(AdminColors tc) {
    final all = _getMockRequests();
    return _buildList(tc, all);
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
              'Demo Mode — showing sample requests. All actions are disabled.',
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

  // ═══════════════════════════════════════════════════════════════
  // Toolbar — search + status chips with counts
  // ═══════════════════════════════════════════════════════════════
  Widget _buildToolbar(AdminColors tc) {
    final all = _isDemo
        ? _getMockRequests()
        : _lastFetchedRequests; // populated during stream build

    final pendingCount =
        all.where((d) => (d['status'] ?? '') == 'pending').length;
    final approvedCount =
        all.where((d) => d['status'] == 'approved').length;
    final rejectedCount =
        all.where((d) => d['status'] == 'rejected').length;
    final failedCount = all
        .where((d) =>
    d['status'] == 'email_failed' || d['status'] == 'sending')
        .length;

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
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  hintText: 'Search by name, email, or reason...',
                  hintStyle:
                  TextStyle(color: tc.textMuted, fontSize: 13),
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
                    label: 'Email Issues',
                    count: failedCount,
                    filter: _StatusFilter.emailFailed),
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

  // Cache last fetched requests so the toolbar can show counts
  List<Map<String, dynamic>> _lastFetchedRequests = [];
  void _cacheFetched(List<Map<String, dynamic>> docs) {
    _lastFetchedRequests = docs;
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

  // ═══════════════════════════════════════════════════════════════
  // Card
  // ═══════════════════════════════════════════════════════════════
  Widget _buildCard(AdminColors tc, Map<String, dynamic> d) {
    final id = (d['id'] ?? '').toString();
    final name = (d['name'] ?? '').toString();
    final email = (d['email'] ?? '').toString();
    final company = (d['company'] ?? '').toString();
    final phone = (d['phone'] ?? '').toString();
    final reason = (d['reason'] ?? '').toString();
    final status = (d['status'] ?? '').toString();
    final code = (d['accessCode'] ?? '').toString();
    final maxUses = (d['maxUses'] ?? 1) as int;
    final usedCount = (d['usedCount'] ?? 0) as int;
    final rejectReason = (d['rejectReason'] ?? '').toString();
    final emailError = (d['emailError'] ?? '').toString();

    final requestedAt = (d['requestedAt'] as Timestamp?)?.toDate();
    final expiresAt = (d['expiresAt'] as Timestamp?)?.toDate();

    final statusColor = _statusColor(status, tc);
    final statusBg = statusColor.withValues(alpha: 0.12);
    final time = requestedAt != null ? _fmtTime(requestedAt) : '';
    final hasCode = code.isNotEmpty && status == 'approved';

    // Cache for toolbar counts
    if (!_isDemo && _lastFetchedRequests.isEmpty) {
      // We'll fill this in the stream builder
    }

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
          onTap: () => _showDetailSheet(tc, d),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header row: avatar + name/email + status badge ──
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
                          _initials(name.isEmpty ? '?' : name),
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
                            _sanitize(name.isEmpty ? 'Unknown' : name),
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
                            _sanitize(email),
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
                        _statusLabel(status),
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

                // ── Company / phone chips ──
                if (company.isNotEmpty || phone.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (company.isNotEmpty)
                        _infoChip(tc, Icons.business_rounded,
                            _sanitize(company)),
                      if (phone.isNotEmpty)
                        _infoChip(tc, Icons.phone_rounded,
                            _sanitize(phone)),
                    ],
                  ),
                ],

                // ── Reason box ──
                if (reason.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: tc.isDark
                          ? Colors.white.withValues(alpha: 0.03)
                          : const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: tc.border.withValues(alpha: 0.6), width: 1),
                    ),
                    child: Text(
                      _sanitize(reason),
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
                ],

                // ── Access code box (approved) ──
                if (hasCode) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: Colors.green.withValues(alpha: 0.4),
                          width: 1.2),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.vpn_key_rounded,
                            color: Colors.green, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'CODE:',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Colors.green,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          code,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Colors.green,
                            letterSpacing: 3,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () => _copyCode(code),
                          icon: const Icon(Icons.copy_rounded,
                              size: 18, color: Colors.green),
                          splashRadius: 18,
                          tooltip: 'Copy code',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.timer_rounded,
                          size: 11, color: tc.textMuted),
                      const SizedBox(width: 4),
                      Text(
                        '${_fmtExpiry(expiresAt)} · Used $usedCount/$maxUses',
                        style: TextStyle(
                          fontSize: 11,
                          color: tc.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],

                // ── Email error banner ──
                if ((status == 'email_failed' || status == 'sending') &&
                    emailError.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: Colors.orange.withValues(alpha: 0.4),
                          width: 1),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            size: 14, color: Colors.orange),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _sanitize('Email error: $emailError'),
                            style: TextStyle(
                              color: Colors.orange.shade800,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // ── Rejection reason ──
                if (status == 'rejected' && rejectReason.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: tc.red.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: tc.red.withValues(alpha: 0.3),
                          width: 1),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline_rounded,
                            size: 14, color: tc.red),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _sanitize('Reason: $rejectReason'),
                            style: TextStyle(
                              color: tc.red,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // ── Footer: time + action buttons ──
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
                        onTap: _isDemo
                            ? _demoBlock
                            : () => _confirmReject(
                          tc: tc,
                          requestId: id,
                          name: name,
                        ),
                      ),
                      const SizedBox(width: 6),
                      _smallButton(
                        tc,
                        label: 'Approve',
                        icon: Icons.check_rounded,
                        color: _isDemo ? tc.muted : Colors.green,
                        filled: !_isDemo,
                        onTap: _isDemo
                            ? _demoBlock
                            : () => _confirmApprove(
                          tc: tc,
                          requestId: id,
                          name: name,
                          email: email,
                          isExtension: false,
                        ),
                      ),
                    ] else if (status == 'approved') ...[
                      _smallButton(
                        tc,
                        label: 'Regenerate',
                        icon: Icons.autorenew_rounded,
                        color: _isDemo ? tc.muted : tc.orange,
                        onTap: _isDemo
                            ? _demoBlock
                            : () => _confirmApprove(
                          tc: tc,
                          requestId: id,
                          name: name,
                          email: email,
                          isExtension: true,
                        ),
                      ),
                    ] else
                      _smallButton(
                        tc,
                        label: 'Re-approve',
                        icon: Icons.refresh_rounded,
                        color: _isDemo ? tc.muted : Colors.green,
                        onTap: _isDemo
                            ? _demoBlock
                            : () => _confirmApprove(
                          tc: tc,
                          requestId: id,
                          name: name,
                          email: email,
                          isExtension: false,
                        ),
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

  Widget _infoChip(AdminColors tc, IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tc.isDark
            ? Colors.white.withValues(alpha: 0.03)
            : const Color(0xFFF4F4F5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: tc.border.withValues(alpha: 0.6), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: tc.textMuted),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              color: tc.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
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

  // ═══════════════════════════════════════════════════════════════
  // Detail sheet
  // ═══════════════════════════════════════════════════════════════
  void _showDetailSheet(AdminColors tc, Map<String, dynamic> d) {
    final id = (d['id'] ?? '').toString();
    final name = (d['name'] ?? '').toString();
    final email = (d['email'] ?? '').toString();
    final company = (d['company'] ?? '').toString();
    final phone = (d['phone'] ?? '').toString();
    final reason = (d['reason'] ?? '').toString();
    final status = (d['status'] ?? '').toString();
    final code = (d['accessCode'] ?? '').toString();
    final maxUses = (d['maxUses'] ?? 1) as int;
    final usedCount = (d['usedCount'] ?? 0) as int;
    final rejectReason = (d['rejectReason'] ?? '').toString();
    final emailError = (d['emailError'] ?? '').toString();

    final requestedAt = (d['requestedAt'] as Timestamp?)?.toDate();
    final expiresAt = (d['expiresAt'] as Timestamp?)?.toDate();

    final statusColor = _statusColor(status, tc);
    final statusBg = statusColor.withValues(alpha: 0.12);

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
                    child: Icon(Icons.science_rounded,
                        color: tc.orange, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Demo Access Request',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          requestedAt != null
                              ? 'Requested ${_fullTime(requestedAt)}'
                              : '—',
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
                      color: statusBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: statusColor.withValues(alpha: 0.4),
                          width: 1),
                    ),
                    child: Text(
                      _statusLabel(status),
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
              _kv(tc, 'Name', _sanitize(name.isEmpty ? '—' : name)),
              _kv(tc, 'Email', _sanitize(email.isEmpty ? '—' : email)),
              if (company.isNotEmpty)
                _kv(tc, 'Company', _sanitize(company)),
              if (phone.isNotEmpty) _kv(tc, 'Phone', _sanitize(phone)),
              _kv(tc, 'Reason',
                  _sanitize(reason.isEmpty ? '—' : reason)),

              if (status == 'approved' && code.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.10),
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
                            'ACCESS CODE',
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
                        code,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w900,
                          color: Colors.green,
                          letterSpacing: 10,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${_fmtExpiry(expiresAt)} · Used $usedCount/$maxUses',
                        style: TextStyle(
                          fontSize: 11,
                          color: tc.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextButton.icon(
                            onPressed: () => _copyCode(code),
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
                              _confirmApprove(
                                tc: tc,
                                requestId: id,
                                name: name,
                                email: email,
                                isExtension: true,
                              );
                            },
                            icon: const Icon(Icons.autorenew_rounded,
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
                ),
              ],

              if ((status == 'email_failed' || status == 'sending') &&
                  emailError.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: Colors.orange.withValues(alpha: 0.4),
                        width: 1.2),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          size: 16, color: Colors.orange),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _sanitize('Email error: $emailError'),
                          style: TextStyle(
                            color: Colors.orange.shade800,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (status == 'rejected' && rejectReason.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: tc.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: tc.red.withValues(alpha: 0.3), width: 1.2),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 16, color: tc.red),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _sanitize('Rejected: $rejectReason'),
                          style: TextStyle(
                            color: tc.red,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
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
                          await _confirmReject(
                            tc: tc,
                            requestId: id,
                            name: name,
                          );
                        },
                        icon: Icon(Icons.close_rounded,
                            size: 16,
                            color: _isDemo ? tc.muted : tc.red),
                        label: Text('Reject',
                            style: TextStyle(
                                color: _isDemo ? tc.muted : tc.red,
                                fontWeight: FontWeight.w700)),
                        style: OutlinedButton.styleFrom(
                          side:
                          BorderSide(color: _isDemo ? tc.border : tc.red),
                          padding: const EdgeInsets.symmetric(vertical: 12),
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
                          await _confirmApprove(
                            tc: tc,
                            requestId: id,
                            name: name,
                            email: email,
                            isExtension: false,
                          );
                        },
                        icon: Icon(Icons.check_rounded,
                            size: 16,
                            color: _isDemo ? tc.muted : Colors.white),
                        label: Text('Approve & Send',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: _isDemo ? tc.muted : Colors.white)),
                        style: FilledButton.styleFrom(
                          backgroundColor:
                          _isDemo ? tc.border : Colors.green,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ] else if (status == 'approved')
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isDemo
                            ? _demoBlock
                            : () {
                          Navigator.pop(ctx);
                          _confirmApprove(
                            tc: tc,
                            requestId: id,
                            name: name,
                            email: email,
                            isExtension: true,
                          );
                        },
                        icon: Icon(Icons.autorenew_rounded,
                            size: 16,
                            color: _isDemo ? tc.muted : tc.orange),
                        label: Text('Regenerate Code',
                            style: TextStyle(
                                color: _isDemo ? tc.muted : tc.orange,
                                fontWeight: FontWeight.w700)),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                              color: _isDemo ? tc.border : tc.orange),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isDemo
                            ? _demoBlock
                            : () {
                          Navigator.pop(ctx);
                          _confirmApprove(
                            tc: tc,
                            requestId: id,
                            name: name,
                            email: email,
                            isExtension: false,
                          );
                        },
                        icon: Icon(Icons.refresh_rounded,
                            size: 16,
                            color: _isDemo ? tc.muted : Colors.green),
                        label: Text('Re-approve',
                            style: TextStyle(
                                color: _isDemo ? tc.muted : Colors.green,
                                fontWeight: FontWeight.w700)),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                              color: _isDemo ? tc.border : Colors.green),
                          padding: const EdgeInsets.symmetric(vertical: 12),
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
                          color: tc.textMuted, fontWeight: FontWeight.w700)),
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

  // ═══════════════════════════════════════════════════════════════
  // Status helpers
  // ═══════════════════════════════════════════════════════════════
  String _statusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'PENDING';
      case 'approved':
        return 'APPROVED';
      case 'rejected':
        return 'REJECTED';
      case 'expired':
        return 'EXPIRED';
      case 'exhausted':
        return 'USED';
      case 'email_failed':
        return 'EMAIL FAILED';
      case 'sending':
        return 'SENDING';
      default:
        return status.toUpperCase();
    }
  }

  Color _statusColor(String status, AdminColors tc) {
    switch (status) {
      case 'approved':
        return Colors.green;
      case 'rejected':
        return tc.red;
      case 'email_failed':
      case 'sending':
        return Colors.orange;
      case 'expired':
      case 'exhausted':
        return tc.textMuted;
      default:
        return tc.orange;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // States
  // ═══════════════════════════════════════════════════════════════
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
        msg = 'No pending demo requests.\nAll caught up! 🎉';
        break;
      case _StatusFilter.approved:
        icon = Icons.verified_rounded;
        msg = 'No approved requests yet.';
        break;
      case _StatusFilter.rejected:
        icon = Icons.cancel_outlined;
        msg = 'No rejected requests.';
        break;
      case _StatusFilter.emailFailed:
        icon = Icons.mark_email_read_rounded;
        msg = 'No email delivery issues right now. 🎉';
        break;
      case _StatusFilter.all:
      default:
        icon = Icons.science_rounded;
        msg = 'No demo requests yet.\n'
            'New requests from the landing screen will appear here.';
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