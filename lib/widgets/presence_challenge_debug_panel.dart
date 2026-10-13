// lib/widgets/presence_challenge_debug_panel.dart
// ═══════════════════════════════════════════════════════════════════
// PRESENCE CHALLENGE DEBUG PANEL
//
// ⚠️ DEBUG ONLY — hindi ito kasama sa production build (kDebugMode guard).
// Ilagay sa MainScreen para makita:
//   • Live state ng PresenceChallengeService
//   • Firestore state ng today's challenges
//   • Manual triggers (force schedule, force check, clear)
// ═══════════════════════════════════════════════════════════════════
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import '../models/employee.dart';
import '../services/presence_challenge_service.dart';

class PresenceChallengeDebugPanel extends StatefulWidget {
  final Employee? employee;
  const PresenceChallengeDebugPanel({super.key, this.employee});

  @override
  State<PresenceChallengeDebugPanel> createState() =>
      _PresenceChallengeDebugPanelState();
}

class _PresenceChallengeDebugPanelState
    extends State<PresenceChallengeDebugPanel> {
  bool _open = false;
  Timer? _refresh;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _firestoreSub;
  List<Map<String, dynamic>> _todaysChallenges = [];
  String? _lastAction;
  final List<String> _logLines = [];

  @override
  void initState() {
    super.initState();
    if (!kDebugMode) return;
    _refresh = Timer.periodic(const Duration(seconds: 3), (_) => _tick());
    _startFirestoreListener();
    _log('Debug panel initialized');
  }

  @override
  void dispose() {
    _refresh?.cancel();
    _firestoreSub?.cancel();
    super.dispose();
  }

  String get _employeeId {
    final emp = widget.employee;
    if (emp == null) return '';
    return emp.employeeId.isNotEmpty ? emp.employeeId : emp.id;
  }

  String _todayStr() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  void _log(String msg) {
    final ts = DateTime.now().toIso8601String().substring(11, 19);
    _logLines.insert(0, '[$ts] $msg');
    if (_logLines.length > 30) _logLines.removeLast();
    if (mounted) setState(() {});
    debugPrint('[DebugPanel] $msg');
  }

  void _tick() {
    if (!mounted) return;
    setState(() {}); // refresh service debug info
  }

  void _startFirestoreListener() {
    if (_employeeId.isEmpty) {
      _log('⚠️ No employeeId — Firestore listener skipped');
      return;
    }
    _firestoreSub?.cancel();
    _firestoreSub = FirebaseFirestore.instance
        .collection('presence_challenges')
        .where('employeeId', isEqualTo: _employeeId)
        .where('date', isEqualTo: _todayStr())
        .snapshots()
        .listen(
          (snap) {
        if (!mounted) return;
        final list = snap.docs.map((d) {
          final data = d.data();
          data['_id'] = d.id;
          return data;
        }).toList();
        list.sort((a, b) => (a['dueAt'] as Timestamp?)
            ?.compareTo(b['dueAt'] as Timestamp? ??
            Timestamp.fromMillisecondsSinceEpoch(0)) ??
            0);
        setState(() => _todaysChallenges = list);
        _log('📥 Firestore: ${list.length} challenge(s) today');
      },
      onError: (e) => _log('❌ Firestore listener error: $e'),
    );
  }

  Future<void> _forceSchedule() async {
    if (_employeeId.isEmpty) {
      _log('❌ Cannot schedule — no employeeId');
      return;
    }
    _log('🎯 Force scheduling...');
    try {
      await PresenceChallengeService.instance.scheduleForToday(
        employeeId: _employeeId,
        clockInAt: DateTime.now(),
      );
      _log('✅ scheduleForToday() called');
    } catch (e) {
      _log('❌ scheduleForToday failed: $e');
    }
  }

  Future<void> _forceCheck() async {
    _log('🔄 Force check triggered...');
    try {
      // Use debug trigger if available
      await PresenceChallengeService.instance.forceCheckNow();
      _log('✅ checkNow() called');
    } catch (e) {
      _log('❌ checkNow failed: $e');
    }
  }

  Future<void> _clearToday() async {
    _log('🗑️ Deleting today\'s challenges...');
    try {
      final snap = await FirebaseFirestore.instance
          .collection('presence_challenges')
          .where('employeeId', isEqualTo: _employeeId)
          .where('date', isEqualTo: _todayStr())
          .get();

      if (snap.docs.isEmpty) {
        _log('ℹ️ Nothing to delete');
        return;
      }

      final batch = FirebaseFirestore.instance.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
      _log('✅ Deleted ${snap.docs.length} doc(s)');
    } catch (e) {
      _log('❌ Delete failed: $e');
    }
  }

  Future<void> _forceTriggerOnDue() async {
    _log('⚡ Force-firing onDue callback...');
    try {
      // Manually query pending+due and call callback
      final now = DateTime.now();
      final snap = await FirebaseFirestore.instance
          .collection('presence_challenges')
          .where('employeeId', isEqualTo: _employeeId)
          .where('date', isEqualTo: _todayStr())
          .where('status', isEqualTo: 'pending')
          .get();

      if (snap.docs.isEmpty) {
        _log('ℹ️ No pending challenge to fire');
        return;
      }

      final first = snap.docs.first;
      final data = first.data();
      final ch = PresenceChallenge(
        id: first.id,
        employeeId: data['employeeId'] as String,
        dueAt: (data['dueAt'] as Timestamp).toDate(),
        expiresAt: (data['expiresAt'] as Timestamp).toDate(),
      );

      final cb = PresenceChallengeService.instance.onDue;
      if (cb == null) {
        _log('❌ onDue callback is NULL!');
        return;
      }
      _log('✅ Firing onDue for ${ch.id}');
      cb(ch);
    } catch (e) {
      _log('❌ Force trigger failed: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();

    return Stack(
      children: [
        // ─── Toggle button ───
        Positioned(
          top: 60,
          right: 8,
          child: SafeArea(
            child: FloatingActionButton.small(
              heroTag: 'debug_challenge_toggle',
              backgroundColor:
              _open ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
              onPressed: () => setState(() => _open = !_open),
              child: Icon(
                _open ? Icons.close : Icons.bug_report,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ),

        // ─── Panel ───
        if (_open)
          Positioned.fill(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 110, 8, 80),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xEE0A0A0A),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF16A34A),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        _buildHeader(),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildServiceState(),
                                const SizedBox(height: 10),
                                _buildFirestoreState(),
                                const SizedBox(height: 10),
                                _buildActions(),
                                const SizedBox(height: 10),
                                _buildLog(),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFF16A34A), width: 1),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.bug_report, color: Color(0xFF16A34A), size: 18),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'CHALLENGE DEBUG',
              style: TextStyle(
                color: Color(0xFF16A34A),
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
          ),
          Text(
            'empId: ${_employeeId.isEmpty ? "(none)" : _employeeId}',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceState() {
    final info = PresenceChallengeService.instance.debugInfo();
    final testMode = info['testMode'] == true;
    return _section(
      title: 'SERVICE STATE',
      color: const Color(0xFF60A5FA),
      children: [
        _kv('testMode', testMode ? 'TRUE ⚡' : 'false',
            valueColor: testMode ? const Color(0xFFFBBF24) : Colors.white70),
        _kv('challengesPerDay', '${info['challengesPerDay']}'),
        _kv('activeEmployeeId', '${info['activeEmployeeId'] ?? "(none)"}'),
        _kv('pendingCount', '${info['pendingCount']}',
            valueColor: (info['pendingCount'] as int? ?? 0) > 0
                ? const Color(0xFF4ADE80)
                : Colors.white70),
        _kv('promptedCount', '${info['promptedCount']}'),
        _kv('tickActive', '${info['tickActive']}',
            valueColor: info['tickActive'] == true
                ? const Color(0xFF4ADE80)
                : const Color(0xFFDC2626)),
        _kv('onDue hooked',
            PresenceChallengeService.instance.onDue != null ? 'YES' : 'NO',
            valueColor: PresenceChallengeService.instance.onDue != null
                ? const Color(0xFF4ADE80)
                : const Color(0xFFDC2626)),
      ],
    );
  }

  Widget _buildFirestoreState() {
    final now = DateTime.now();
    return _section(
      title: 'FIRESTORE (${_todaysChallenges.length} today)',
      color: const Color(0xFFA78BFA),
      children: [
        if (_todaysChallenges.isEmpty)
          const Text(
            'Walang challenges for today.\n→ Hindi ka pa nag-clock-in OR\n→ Hindi tumakbo ang scheduleForToday()',
            style: TextStyle(color: Colors.white54, fontSize: 11, height: 1.5),
          )
        else
          ..._todaysChallenges.map((c) {
            final dueAt = (c['dueAt'] as Timestamp?)?.toDate();
            final expiresAt = (c['expiresAt'] as Timestamp?)?.toDate();
            final status = c['status']?.toString() ?? '?';
            final attempts = c['attempts'] ?? 0;

            final isDue = dueAt != null && !now.isBefore(dueAt);
            final isExpired = expiresAt != null && now.isAfter(expiresAt);
            final isActive = isDue && !isExpired;

            final statusColor = switch (status) {
              'passed' => const Color(0xFF4ADE80),
              'missed' => const Color(0xFFDC2626),
              'cancelled' => Colors.white38,
              _ => isActive
                  ? const Color(0xFFFBBF24)
                  : const Color(0xFF60A5FA),
            };

            return Container(
              margin: const EdgeInsets.symmetric(vertical: 3),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: statusColor, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        status.toUpperCase(),
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const Spacer(),
                      Text(
                        isActive
                            ? '⚡ DUE NOW'
                            : isExpired
                            ? 'expired'
                            : 'waiting',
                        style: TextStyle(
                          color: isActive
                              ? const Color(0xFFFBBF24)
                              : Colors.white54,
                          fontSize: 9,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'id: ${c['_id']}',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 9,
                      fontFamily: 'monospace',
                    ),
                  ),
                  Text(
                    'due: ${dueAt?.toIso8601String().substring(11, 19) ?? "?"} '
                        'exp: ${expiresAt?.toIso8601String().substring(11, 19) ?? "?"}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 9,
                      fontFamily: 'monospace',
                    ),
                  ),
                  Text(
                    'attempts: $attempts',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 9,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _buildActions() {
    return _section(
      title: 'ACTIONS',
      color: const Color(0xFFFBBF24),
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _btn('⚡ Force Schedule', const Color(0xFF16A34A), _forceSchedule),
            _btn('🔄 Force Check', const Color(0xFF3B82F6), _forceCheck),
            _btn('🎯 Fire onDue', const Color(0xFFA855F7), _forceTriggerOnDue),
            _btn('🗑️ Clear Today', const Color(0xFFDC2626), _clearToday),
          ],
        ),
      ],
    );
  }

  Widget _buildLog() {
    return _section(
      title: 'LOG (latest 30)',
      color: const Color(0xFF94A3B8),
      children: [
        if (_logLines.isEmpty)
          const Text('(no logs yet)',
              style: TextStyle(color: Colors.white38, fontSize: 10))
        else
          ..._logLines.map((l) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Text(
              l,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 9.5,
                fontFamily: 'monospace',
                height: 1.3,
              ),
            ),
          )),
      ],
    );
  }

  Widget _section({
    required String title,
    required Color color,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    );
  }

  Widget _kv(String key, String value, {Color valueColor = Colors.white}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(
              key,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: valueColor,
                fontSize: 10,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _btn(String label, Color bg, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}