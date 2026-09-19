// lib/screens/apply_leave_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../services/admin_notification_service.dart';
import 'itinerary_screen.dart';

// ═══════════════════════════════════════════════════════════════
// ⭐ ROBUST FETCH — para siguradong mag-match kahit anong ID
//    ang ginagamit ng mobile (doc ID / auth UID / typed ID / email)
// ═══════════════════════════════════════════════════════════════
Future<List<Map<String, dynamic>>> _fetchEmployeeLeaves(
    String empKey) async {
  final key = empKey.trim();
  if (key.isEmpty) return [];

  final firestore = FirebaseFirestore.instance;
  final uniqueDocs = <String, Map<String, dynamic>>{};

  const identifierFields = [
    'employeeId',
    'employee_id',
    'employeeDocId',
    'employeeCode',
    'employeeAuthUid',
    'employeeEmail',
  ];

  for (final field in identifierFields) {
    try {
      final snap = await firestore
          .collection('leave_applications')
          .where(field, isEqualTo: key)
          .get();

      for (var doc in snap.docs) {
        uniqueDocs.putIfAbsent(
          doc.id,
              () => <String, dynamic>{...doc.data(), 'id': doc.id},
        );
      }
    } catch (e) {
      debugPrint('⚠️ [LeaveFetch] Query by "$field" failed: $e');
    }
  }

  debugPrint(
      '📋 [LeaveFetch] empKey="$key" → ${uniqueDocs.length} unique leave doc(s)');

  return uniqueDocs.values.toList();
}

class _ThemeColors {
  final bool isDark;
  const _ThemeColors(this.isDark);

  Color get bg => isDark ? const Color(0xFF0F0F10) : const Color(0xFFFFFFFF);
  Color get cardBg => isDark ? const Color(0xFF18181B) : const Color(0xFFFFFFFF);
  Color get cardFill =>
      isDark ? const Color(0xFF1F1F23) : const Color.fromRGBO(131, 131, 131, 0.07);

  Color get textBlack => isDark ? Colors.white : const Color(0xFF000000);
  Color get textGray =>
      isDark ? const Color(0xFFB0B0B0) : const Color(0xFF71717A);
  Color get textMuted =>
      isDark ? const Color(0xFF888888) : const Color(0xFF9CA3AF);

  Color get border =>
      isDark ? const Color(0xFF27272A) : const Color(0xFFE5E7EB);
  Color get darkBorder =>
      isDark ? const Color(0xFF3F3F46) : const Color(0xFF27272A);

  Color get navBg => isDark ? const Color(0xFF18181B) : Colors.white;
  Color get navUnselected =>
      isDark ? const Color(0xFF888888) : const Color(0xFF71717A);

  Color get softCard =>
      isDark ? const Color(0xFF1F1F23) : const Color(0xFFF8F8F8);
  Color get softBorder =>
      isDark ? const Color(0xFF3F3F46) : const Color(0xFFFFA500);
}

// ─── BRAND COLORS ─────────────────────────────────────────────
class _T {
  static const Color orange = Color(0xFFFF8A00);
  static const Color orangeBorder = Color(0xFFFFA500);
  static const Color orangeLight = Color(0xFFFA6A00);
  static const Color orangeHot = Color(0xFFF54900);
  static const Color neonGreen = Color(0xFFC4FF0A);

  static const Color green = Color(0xFF16A34A);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFDC2626);
  static const Color info = Color(0xFF2563EB);
  static const Color white = Color(0xFFFFFFFF);

  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [orange, orangeLight, orangeHot],
    stops: [0.0, 0.5, 1.0],
  );

  static const double r12 = 12;
  static const double r14 = 14;
  static const double r16 = 16;
  static const double r20 = 20;
}

// ─── LEAVE CREDIT POLICY ──────────────────────────────────────
const int kAnnualLeaveTotal = 18;
const int kSickLeaveTotal = 18;
const int kTotalLeaveCredits = kAnnualLeaveTotal + kSickLeaveTotal;

bool _isAnnual(String code) => code.toUpperCase() == 'VL';
bool _isSick(String code) => code.toUpperCase() == 'SL';

class _LeaveType {
  final String code;
  final String label;
  final IconData icon;
  const _LeaveType(this.code, this.label, this.icon);
}

const _leaveTypes = [
  _LeaveType('SL', 'Sick', Icons.medical_services_rounded),
  _LeaveType('VL', 'Vacation', Icons.beach_access_rounded),
  _LeaveType('EL', 'Emergency', Icons.warning_amber_rounded),
  _LeaveType('BL', 'Bereave', Icons.sentiment_very_dissatisfied_rounded),
  _LeaveType('ML', 'Maternity', Icons.child_friendly_rounded),
];

// ─── SAFE HELPERS ─────────────────────────────────────────────
int _safeInt(dynamic v, [int fallback = 0]) {
  if (v == null) return fallback;
  if (v is int) return v;
  if (v is double) return v.toInt();
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? fallback;
}

// ─── STATS MODEL ──────────────────────────────────────────────
class _LeaveStats {
  int usedAnnual = 0;
  int usedSick = 0;
  int usedOther = 0;
  int pendingCount = 0;

  int get totalCredits => kTotalLeaveCredits;
  int get usedTotal => usedAnnual + usedSick + usedOther;
  int get remaining => (totalCredits - usedTotal).clamp(0, totalCredits);
}

_LeaveStats _computeStats(List<Map<String, dynamic>> history) {
  final s = _LeaveStats();
  for (final h in history) {
    final status = (h['status'] ?? 'pending').toString().toLowerCase();
    final code = (h['leaveType'] ?? 'SL').toString();
    final days = _safeInt(h['days'], 1);

    if (status == 'approved') {
      if (_isSick(code)) {
        s.usedSick += days;
      } else if (_isAnnual(code)) {
        s.usedAnnual += days;
      } else {
        s.usedOther += days;
      }
    } else if (status == 'pending') {
      s.pendingCount++;
    }
  }
  return s;
}

// ═══════════════════════════════════════════════════════════════
//  LEAVE APPLICATION FORM
// ═══════════════════════════════════════════════════════════════
class LeaveApplicationFormScreen extends StatefulWidget {
  final String employeeId;
  final String employeeName;
  final VoidCallback? onBack;

  const LeaveApplicationFormScreen({
    super.key,
    required this.employeeId,
    required this.employeeName,
    this.onBack,
  });

  @override
  State<LeaveApplicationFormScreen> createState() =>
      _LeaveApplicationFormScreenState();
}

class _LeaveApplicationFormScreenState
    extends State<LeaveApplicationFormScreen> {
  int _selectedBottomIndex = 2;
  _LeaveStats _stats = _LeaveStats();
  List<Map<String, dynamic>> _leaveHistory = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchLeaveData();
  }

  void refreshData() {
    _fetchLeaveData();
  }

  // ⭐ UPDATED — gamit ang robust fetch
  Future<void> _fetchLeaveData() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final rawDocs = await _fetchEmployeeLeaves(widget.employeeId);

      final List<Map<String, dynamic>> history = [];
      for (var data in rawDocs) {
        history.add({
          'id': data['id'],
          'leaveType': data['leaveType'] ?? 'SL',
          'startDate': data['startDate'],
          'endDate': data['endDate'],
          'days': _safeInt(data['days'], 1),
          'status': data['status'] ?? 'pending',
          'reason': data['reason'] ?? '',
          'createdAt': data['createdAt'],
        });
      }

      history.sort((a, b) {
        final aTime = a['createdAt'] as Timestamp?;
        final bTime = b['createdAt'] as Timestamp?;
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });

      final stats = _computeStats(history);

      if (!mounted) return;
      setState(() {
        _leaveHistory = history;
        _stats = stats;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Error fetching leave history: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load leave data. Please try again.';
      });
    }
  }

  String _formatDate(dynamic dateStr) {
    if (dateStr == null) return 'N/A';
    try {
      if (dateStr is Timestamp) {
        return DateFormat('MMM d, yyyy').format(dateStr.toDate());
      }
      if (dateStr is String) {
        final dt = DateTime.parse(dateStr);
        return DateFormat('MMM d, yyyy').format(dt);
      }
      return 'N/A';
    } catch (_) {
      return dateStr.toString();
    }
  }

  String _leaveTypeLabel(String code) {
    const map = {
      'SL': 'Sick Leave',
      'VL': 'Vacation Leave',
      'EL': 'Emergency Leave',
      'BL': 'Bereavement Leave',
      'ML': 'Maternity/Paternity Leave',
    };
    return map[code] ?? code;
  }

  void _openLeaveForm() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LeaveFormScreen(
          employeeId: widget.employeeId,
          employeeName: widget.employeeName,
          onGoHome: () {
            refreshData();
            if (Navigator.canPop(context)) Navigator.pop(context);
          },
        ),
      ),
    ).then((_) => refreshData());
  }

  void _openItinerary() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ItineraryScreen(
          employeeId: widget.employeeId,
          employeeName: widget.employeeName,
          onGoHome: () {
            refreshData();
            if (Navigator.canPop(context)) Navigator.pop(context);
          },
        ),
      ),
    ).then((_) => refreshData());
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = _ThemeColors(isDark);

    return Scaffold(
      backgroundColor: tc.bg,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
              decoration: BoxDecoration(
                gradient: _T.brandGradient,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
                border: Border(
                  bottom: BorderSide(color: tc.darkBorder, width: 1.11),
                ),
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      if (widget.onBack != null) {
                        widget.onBack!();
                      } else if (Navigator.canPop(context)) {
                        Navigator.pop(context);
                      }
                    },
                    child: const Icon(Icons.arrow_back_ios_rounded,
                        color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text(
                      'Leave Application Form',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                  GestureDetector(
                    onTap: _openItinerary,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: _T.orangeBorder, width: 1.11),
                      ),
                      child: const Icon(Icons.assignment_rounded,
                          color: _T.orange, size: 18),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Center(
                  child: Column(
                    children: [
                      Text(_error!, style: const TextStyle(color: _T.error)),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: _fetchLeaveData,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    _statCard(
                      tc,
                      label: 'Total',
                      value: '${_stats.totalCredits}',
                      valueColor: tc.textBlack,
                      labelColor: tc.textGray,
                    ),
                    const SizedBox(width: 12),
                    _statCard(
                      tc,
                      label: 'Used',
                      value: '${_stats.usedTotal}',
                      valueColor: _T.neonGreen,
                      labelColor: tc.textGray,
                    ),
                    const SizedBox(width: 12),
                    _statCard(
                      tc,
                      label: 'Remaining',
                      value: '${_stats.remaining}',
                      valueColor: _T.orange,
                      labelColor: _T.orange,
                      isHighlighted: true,
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Leave History',
                    style: TextStyle(
                        color: tc.textBlack,
                        fontSize: 14,
                        fontWeight: FontWeight.w500)),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _leaveHistory.isEmpty
                    ? Center(
                  child: Text('No leave history yet.',
                      style: TextStyle(color: tc.textGray)),
                )
                    : ListView.builder(
                  itemCount: _leaveHistory.length,
                  itemBuilder: (ctx, index) {
                    final item = _leaveHistory[index];
                    final leaveType =
                    _leaveTypeLabel(item['leaveType']);
                    final start = _formatDate(item['startDate']);
                    final end = _formatDate(item['endDate']);
                    final days = item['days'];
                    final status =
                    (item['status'] ?? 'pending').toString();
                    final statusLower = status.toLowerCase();
                    final isApproved = statusLower == 'approved';
                    final isPending = statusLower == 'pending';

                    final badgeBg = isApproved
                        ? _T.neonGreen.withValues(alpha: 0.1)
                        : (isPending
                        ? _T.orange.withValues(alpha: 0.1)
                        : _T.error.withValues(alpha: 0.1));
                    final badgeBorder = isApproved
                        ? _T.neonGreen.withValues(alpha: 0.2)
                        : (isPending
                        ? _T.orange.withValues(alpha: 0.2)
                        : _T.error.withValues(alpha: 0.2));
                    final badgeText = isApproved
                        ? _T.neonGreen
                        : (isPending ? _T.orange : _T.error);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: tc.softCard,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: tc.softBorder, width: 1.11),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black
                                .withValues(alpha: 0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment:
                        CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                            children: [
                              Text(leaveType,
                                  style: TextStyle(
                                      color: tc.textBlack,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500)),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: badgeBg,
                                  borderRadius:
                                  BorderRadius.circular(12),
                                  border: Border.all(
                                      color: badgeBorder,
                                      width: 1.11),
                                ),
                                child: Text(
                                  isApproved
                                      ? 'Approved'
                                      : (isPending
                                      ? 'Pending'
                                      : 'Rejected'),
                                  style: TextStyle(
                                      color: badgeText,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                            children: [
                              Text('$start - $end',
                                  style: TextStyle(
                                      color: tc.textGray,
                                      fontSize: 12)),
                              Text('$days Days',
                                  style: TextStyle(
                                      color: tc.textBlack,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: tc.navBg,
        elevation: 2,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: _T.orange,
        unselectedItemColor: tc.navUnselected,
        currentIndex: _selectedBottomIndex,
        onTap: (index) => setState(() => _selectedBottomIndex = index),
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.grid_view_rounded), label: 'Home'),
          BottomNavigationBarItem(
              icon: Icon(Icons.history_rounded), label: 'Logs'),
          BottomNavigationBarItem(
              icon: Icon(Icons.calendar_today_rounded), label: 'Leave'),
          BottomNavigationBarItem(
              icon: Icon(Icons.person_rounded), label: 'Profile'),
        ],
      ),
    );
  }

  Widget _statCard(
      _ThemeColors tc, {
        required String label,
        required String value,
        required Color valueColor,
        required Color labelColor,
        bool isHighlighted = false,
      }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color:
          isHighlighted ? _T.orange.withValues(alpha: 0.2) : tc.softCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isHighlighted
                ? _T.orange.withValues(alpha: 0.2)
                : tc.softBorder,
            width: 1.11,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 3,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    color: valueColor,
                    fontSize: 20,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    color: labelColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  LEAVE HISTORY SCREEN
// ═══════════════════════════════════════════════════════════════
class LeaveHistoryScreen extends StatefulWidget {
  final String employeeId;
  final String employeeName;
  final VoidCallback? onGoHome;

  const LeaveHistoryScreen({
    super.key,
    required this.employeeId,
    required this.employeeName,
    this.onGoHome,
  });

  @override
  State<LeaveHistoryScreen> createState() => _LeaveHistoryScreenState();
}

class _LeaveHistoryScreenState extends State<LeaveHistoryScreen> {
  _LeaveStats _stats = _LeaveStats();
  List<Map<String, dynamic>> _leaveHistory = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchLeaveData();
  }

  // ⭐ UPDATED — gamit ang robust fetch
  Future<void> _fetchLeaveData() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final rawDocs = await _fetchEmployeeLeaves(widget.employeeId);

      final List<Map<String, dynamic>> history = [];
      for (var data in rawDocs) {
        history.add({
          'id': data['id'],
          'leaveType': data['leaveType'] ?? 'SL',
          'startDate': data['startDate'],
          'endDate': data['endDate'],
          'days': _safeInt(data['days'], 1),
          'status': data['status'] ?? 'pending',
          'reason': data['reason'] ?? '',
          'createdAt': data['createdAt'],
        });
      }

      history.sort((a, b) {
        final aTime = a['createdAt'] as Timestamp?;
        final bTime = b['createdAt'] as Timestamp?;
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });

      final stats = _computeStats(history);

      if (!mounted) return;
      setState(() {
        _leaveHistory = history;
        _stats = stats;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Error fetching leave history: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load leave data. Please try again.';
      });
    }
  }

  String _formatDate(dynamic dateStr) {
    if (dateStr == null) return 'N/A';
    try {
      if (dateStr is Timestamp) {
        return DateFormat('MMM d, yyyy').format(dateStr.toDate());
      }
      if (dateStr is String) {
        final dt = DateTime.parse(dateStr);
        return DateFormat('MMM d, yyyy').format(dt);
      }
      return 'N/A';
    } catch (_) {
      return dateStr.toString();
    }
  }

  String _leaveTypeLabel(String code) {
    const map = {
      'SL': 'Sick Leave',
      'VL': 'Vacation Leave',
      'EL': 'Emergency Leave',
      'BL': 'Bereavement Leave',
      'ML': 'Maternity/Paternity Leave',
    };
    return map[code] ?? code;
  }

  void _openLeaveApplicationForm() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LeaveApplicationFormScreen(
          employeeId: widget.employeeId,
          employeeName: widget.employeeName,
          onBack: () {
            if (Navigator.canPop(context)) Navigator.pop(context);
          },
        ),
      ),
    ).then((_) => _fetchLeaveData());
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = _ThemeColors(isDark);

    return Scaffold(
      backgroundColor: tc.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(tc),
            const SizedBox(height: 20),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    if (_loading)
                      const Center(child: CircularProgressIndicator())
                    else if (_error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Column(
                          children: [
                            Text(_error!,
                                style: const TextStyle(color: _T.error)),
                            const SizedBox(height: 8),
                            ElevatedButton(
                              onPressed: _fetchLeaveData,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    else
                      Row(
                        children: [
                          _statCard(
                            tc,
                            label: 'Total',
                            value: '${_stats.totalCredits}',
                            valueColor: tc.textBlack,
                            labelColor: tc.textGray,
                          ),
                          const SizedBox(width: 12),
                          _statCard(
                            tc,
                            label: 'Used',
                            value: '${_stats.usedTotal}',
                            valueColor: _T.neonGreen,
                            labelColor: tc.textGray,
                          ),
                          const SizedBox(width: 12),
                          _statCard(
                            tc,
                            label: 'Remaining',
                            value: '${_stats.remaining}',
                            valueColor: _T.orange,
                            labelColor: _T.orange,
                            isHighlighted: true,
                          ),
                        ],
                      ),
                    const SizedBox(height: 20),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Leave History',
                          style: TextStyle(
                              color: tc.textBlack,
                              fontSize: 14,
                              fontWeight: FontWeight.w500)),
                    ),
                    const SizedBox(height: 10),
                    if (_loading)
                      const Center(child: CircularProgressIndicator())
                    else if (_error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Column(
                          children: [
                            Text(_error!,
                                style: const TextStyle(color: _T.error)),
                            const SizedBox(height: 8),
                            ElevatedButton(
                              onPressed: _fetchLeaveData,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    else if (_leaveHistory.isEmpty)
                        Center(
                          child: Text('No leave history yet.',
                              style: TextStyle(color: tc.textGray)),
                        )
                      else
                        Column(
                          children: _leaveHistory.map((item) {
                            final leaveType = _leaveTypeLabel(item['leaveType']);
                            final start = _formatDate(item['startDate']);
                            final end = _formatDate(item['endDate']);
                            final days = item['days'];
                            final status =
                            (item['status'] ?? 'pending').toString();
                            final statusLower = status.toLowerCase();
                            final isApproved = statusLower == 'approved';
                            final isPending = statusLower == 'pending';
                            final badgeBg = isApproved
                                ? _T.neonGreen.withValues(alpha: 0.1)
                                : (isPending
                                ? _T.orange.withValues(alpha: 0.1)
                                : _T.error.withValues(alpha: 0.1));
                            final badgeBorder = isApproved
                                ? _T.neonGreen.withValues(alpha: 0.2)
                                : (isPending
                                ? _T.orange.withValues(alpha: 0.2)
                                : _T.error.withValues(alpha: 0.2));
                            final badgeText = isApproved
                                ? _T.neonGreen
                                : (isPending ? _T.orange : _T.error);

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: tc.softCard,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                    color: tc.softBorder, width: 1.11),
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                    Colors.black.withValues(alpha: 0.05),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(leaveType,
                                          style: TextStyle(
                                              color: tc.textBlack,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500)),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: badgeBg,
                                          borderRadius:
                                          BorderRadius.circular(12),
                                          border: Border.all(
                                              color: badgeBorder, width: 1.11),
                                        ),
                                        child: Text(
                                          isApproved
                                              ? 'Approved'
                                              : (isPending
                                              ? 'Pending'
                                              : 'Rejected'),
                                          style: TextStyle(
                                              color: badgeText,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w500),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('$start - $end',
                                          style: TextStyle(
                                              color: tc.textGray, fontSize: 12)),
                                      Text('$days Days',
                                          style: TextStyle(
                                              color: tc.textBlack,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500)),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(_ThemeColors tc) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      decoration: BoxDecoration(
        gradient: _T.brandGradient,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
        border: Border(
          bottom: BorderSide(color: tc.darkBorder, width: 1.11),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              if (widget.onGoHome != null) {
                widget.onGoHome!();
              } else if (Navigator.canPop(context)) {
                Navigator.pop(context);
              }
            },
            child: const Icon(Icons.arrow_back_ios_rounded,
                color: Colors.white, size: 20),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Text('Leave Form',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w500)),
          ),
          GestureDetector(
            onTap: _openLeaveApplicationForm,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _T.orangeBorder, width: 1.11),
              ),
              child: const Icon(Icons.add_rounded,
                  color: _T.orange, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(
      _ThemeColors tc, {
        required String label,
        required String value,
        required Color valueColor,
        required Color labelColor,
        bool isHighlighted = false,
      }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color:
          isHighlighted ? _T.orange.withValues(alpha: 0.2) : tc.softCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isHighlighted
                ? _T.orange.withValues(alpha: 0.2)
                : tc.softBorder,
            width: 1.11,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 3,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    color: valueColor,
                    fontSize: 20,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    color: labelColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  LEAVE FORM SCREEN
// ═══════════════════════════════════════════════════════════════
class LeaveFormScreen extends StatefulWidget {
  final String employeeId;
  final String employeeName;
  final VoidCallback? onGoHome;

  const LeaveFormScreen({
    super.key,
    required this.employeeId,
    required this.employeeName,
    this.onGoHome,
  });

  @override
  State<LeaveFormScreen> createState() => _LeaveFormScreenState();
}

class _LeaveFormScreenState extends State<LeaveFormScreen> {
  int _currentStep = 0;
  String? _selectedLeaveType;
  bool _isSubmitting = false;
  bool _isCertified = false;

  DateTime? _startDate;
  DateTime? _endDate;
  final _reasonCtrl = TextEditingController();

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  int get _leaveDays {
    if (_startDate == null || _endDate == null) return 0;
    return _endDate!.difference(_startDate!).inDays + 1;
  }

  String _fmt(DateTime? d) {
    if (d == null) return 'dd/mm/yyyy';
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[d.month]} ${d.day}, ${d.year}';
  }

  String get _leaveLabel {
    if (_selectedLeaveType == null) return '—';
    return _leaveTypes.firstWhere((l) => l.code == _selectedLeaveType).label;
  }

  String get _leaveDisplay => '$_leaveLabel ($_selectedLeaveType)';
  String get _durationDisplay => '$_leaveDays Days';
  String get _datesDisplay {
    if (_startDate == null || _endDate == null) return '—';
    return '${_fmt(_startDate)} - ${_fmt(_endDate)}';
  }

  String get _reasonDisplay =>
      _reasonCtrl.text.trim().isEmpty ? '—' : _reasonCtrl.text.trim();

  Future<void> _pickDate(bool isStart) async {
    final now = DateTime.now();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final ColorScheme pickerScheme = isDark
        ? const ColorScheme.dark(
      primary: _T.orange,
      onPrimary: Colors.white,
      surface: Color(0xFF1F1F23),
      onSurface: Colors.white,
      onSurfaceVariant: Color(0xFFB0B0B0),
      secondary: _T.orangeLight,
      onSecondary: Colors.white,
      tertiary: _T.orange,
    )
        : const ColorScheme.light(
      primary: _T.orange,
      onPrimary: Colors.white,
      surface: Colors.white,
      onSurface: Color(0xFF1F2937),
      onSurfaceVariant: Color(0xFF6B7280),
      secondary: _T.orangeLight,
      onSecondary: Colors.white,
      tertiary: _T.orange,
    );

    final pick = await showDatePicker(
      context: context,
      initialDate:
      isStart ? (_startDate ?? now) : (_endDate ?? _startDate ?? now),
      firstDate: now,
      lastDate: DateTime(now.year + 1),
      builder: (ctx, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: pickerScheme,
          dialogBackgroundColor: pickerScheme.surface,
          dialogTheme: DialogThemeData(
            backgroundColor: pickerScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          datePickerTheme: DatePickerThemeData(
            backgroundColor: pickerScheme.surface,
            surfaceTintColor: Colors.transparent,
            headerBackgroundColor: _T.orange,
            headerForegroundColor: Colors.white,
            dayForegroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return Colors.white;
              }
              if (states.contains(WidgetState.disabled)) {
                return pickerScheme.onSurface.withValues(alpha: 0.35);
              }
              return pickerScheme.onSurface;
            }),
            dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return _T.orange;
              }
              return Colors.transparent;
            }),
            todayForegroundColor: WidgetStateProperty.all(_T.orange),
            todayBorder: const BorderSide(color: _T.orange, width: 1.5),
            yearForegroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return Colors.white;
              }
              return pickerScheme.onSurface;
            }),
            yearBackgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return _T.orange;
              }
              return Colors.transparent;
            }),
            rangeSelectionBackgroundColor:
            _T.orange.withValues(alpha: 0.2),
            weekdayStyle: TextStyle(
              color: pickerScheme.onSurface.withValues(alpha: 0.7),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        child: child!,
      ),
    );
    if (pick == null || !mounted) return;
    setState(() {
      if (isStart) {
        _startDate = pick;
        if (_endDate != null && _endDate!.isBefore(pick)) _endDate = null;
      } else {
        _endDate = pick;
      }
    });
  }

  // ⭐ UPDATED — gamit ang robust fetch
  Future<bool> _hasEnoughBalance() async {
    if (_selectedLeaveType == null || _leaveDays <= 0) return true;
    try {
      final rawDocs = await _fetchEmployeeLeaves(widget.employeeId);

      int usedAnnual = 0, usedSick = 0;
      for (final data in rawDocs) {
        final status =
        (data['status'] ?? 'pending').toString().toLowerCase();
        if (status != 'approved') continue;
        final code = (data['leaveType'] ?? '').toString();
        final days = _safeInt(data['days'], 1);
        if (_isAnnual(code)) {
          usedAnnual += days;
        } else if (_isSick(code)) {
          usedSick += days;
        }
      }
      final annualRemaining = kAnnualLeaveTotal - usedAnnual;
      final sickRemaining = kSickLeaveTotal - usedSick;
      if (_isAnnual(_selectedLeaveType!) && _leaveDays > annualRemaining) {
        _showToast(
            'Insufficient Annual Leave. Remaining: $annualRemaining',
            _T.error);
        return false;
      }
      if (_isSick(_selectedLeaveType!) && _leaveDays > sickRemaining) {
        _showToast('Insufficient Sick Leave. Remaining: $sickRemaining',
            _T.error);
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('Balance check failed: $e');
      return true;
    }
  }

  void _goNext() async {
    if (_currentStep == 0 && _selectedLeaveType == null) {
      _showToast('Please select a leave type', _T.warning);
      return;
    }
    if (_currentStep == 1) {
      if (_startDate == null || _endDate == null) {
        _showToast('Please select dates', _T.warning);
        return;
      }
      if (_reasonCtrl.text.trim().isEmpty) {
        _showToast('Please enter a reason', _T.warning);
        return;
      }
    }
    if (_currentStep == 2 && !_isCertified) {
      _showToast('Please certify that all information is correct', _T.warning);
      return;
    }
    if (_currentStep < 2) {
      setState(() => _currentStep++);
    }
  }

  void _goBack() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    } else {
      if (widget.onGoHome != null) {
        widget.onGoHome!();
      } else if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    }
  }

  void _openLeaveApplicationForm() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LeaveApplicationFormScreen(
          employeeId: widget.employeeId,
          employeeName: widget.employeeName,
          onBack: () {
            if (Navigator.canPop(context)) Navigator.pop(context);
          },
        ),
      ),
    );
  }

  Future<void> _submitApplication() async {
    if (!_isCertified) {
      _showToast('Please certify that all information is correct', _T.warning);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final ok = await _hasEnoughBalance();
      if (!ok) {
        setState(() => _isSubmitting = false);
        return;
      }

      // ⭐ Save with multiple identifier fields
      await FirebaseFirestore.instance
          .collection('leave_applications')
          .add({
        'employeeId': widget.employeeId,
        'employee_id': widget.employeeId,
        'employeeDocId': widget.employeeId,
        'employeeAuthUid': widget.employeeId,
        'employeeName': widget.employeeName,
        'employee_name': widget.employeeName,
        'leaveType': _selectedLeaveType,
        'startDate': _startDate?.toIso8601String(),
        'endDate': _endDate?.toIso8601String(),
        'days': _leaveDays,
        'reason': _reasonCtrl.text.trim(),
        'status': 'pending',
        'certified': _isCertified,
        'createdBy': 'employee',
        'source': 'employee',
        'createdAt': FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 30));

      try {
        AdminNotificationService.instance.notifyLeaveRequest(
          employeeId: widget.employeeId,
          employeeName: widget.employeeName,
          leaveType: _selectedLeaveType ?? '—',
          dateRange: '${_fmt(_startDate)} — ${_fmt(_endDate)}',
        );
        debugPrint('✅ [LeaveForm] Admin notified of leave request');
      } catch (e) {
        debugPrint('⚠️ Admin leave notification failed: $e');
      }

      if (!mounted) return;
      setState(() => _isSubmitting = false);
      _showSuccessDialog();
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        _showToast('Failed to submit: ${e.toString()}', _T.error);
      }
    }
  }

  void _showSuccessDialog() {
    showDialog(
      barrierDismissible: false,
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        contentPadding: EdgeInsets.zero,
        content: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            gradient: _T.brandGradient,
            borderRadius: BorderRadius.circular(_T.r20),
            border: Border.all(color: const Color(0xFF27272A), width: 1.15),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 40,
                spreadRadius: -8,
                offset: const Offset(0, 20),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  color: _T.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: _T.neonGreen, width: 3),
                ),
                child: const Icon(Icons.check_circle_rounded,
                    color: _T.neonGreen, size: 72),
              ),
              const SizedBox(height: 24),
              const Text('Successfully added',
                  style: TextStyle(
                      color: _T.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w500,
                      height: 1.2),
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              const Text('Just wait for the HR Approval...',
                  style: TextStyle(
                      color: Color(0xFFDFDFDF), fontSize: 14, height: 1.5),
                  textAlign: TextAlign.center),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _T.white,
                    foregroundColor: _T.orange,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(_T.r12)),
                    elevation: 0,
                    side: BorderSide(color: _T.orange.withValues(alpha: 0.3)),
                  ),
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    if (mounted) {
                      setState(() {
                        _currentStep = 0;
                        _selectedLeaveType = null;
                        _startDate = null;
                        _endDate = null;
                        _reasonCtrl.clear();
                        _isCertified = false;
                        _isSubmitting = false;
                      });
                    }
                    widget.onGoHome?.call();
                  },
                  child: const Text('OK',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _saveAsDraft() {
    _showToast('Draft saved locally', _T.info);
  }

  void _showToast(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style:
          const TextStyle(color: _T.white, fontWeight: FontWeight.w600)),
      backgroundColor: color.withValues(alpha: 0.9),
      behavior: SnackBarBehavior.floating,
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(_T.r12)),
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 3),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = _ThemeColors(isDark);

    return Scaffold(
      backgroundColor: tc.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(tc),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    _buildHeroCard(),
                    const SizedBox(height: 20),
                    _buildStepper(tc),
                    const SizedBox(height: 24),
                    _buildStepContent(tc),
                    const SizedBox(height: 24),
                    _buildActions(tc),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(_ThemeColors tc) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: _goBack,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: tc.bg,
                borderRadius: BorderRadius.circular(_T.r12),
                border: Border.all(color: tc.darkBorder, width: 1.15),
              ),
              child: Icon(Icons.chevron_left_rounded,
                  color: tc.textGray, size: 22),
            ),
          ),
          const SizedBox(width: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Leave Form',
                  style: TextStyle(
                      color: tc.textBlack,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3)),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _openLeaveApplicationForm,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border:
                    Border.all(color: _T.orangeBorder, width: 1.11),
                  ),
                  child: const Icon(Icons.add_rounded,
                      color: _T.orange, size: 18),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeroCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: _T.brandGradient,
        borderRadius: BorderRadius.circular(_T.r16),
        border: Border.all(color: _T.orangeBorder, width: 1.15),
        boxShadow: [
          BoxShadow(
              color: _T.orange.withValues(alpha: 0.25),
              blurRadius: 20,
              offset: const Offset(0, 8)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(_T.r14),
              border:
              Border.all(color: Colors.white.withValues(alpha: 0.25)),
            ),
            child: const Icon(Icons.event_note_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('SELF SERVICE',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  )),
              const SizedBox(height: 2),
              const Text('Apply for Leave',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  )),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStepper(_ThemeColors tc) {
    const steps = ['Type', 'Details', 'Submit'];
    return Row(
      children: List.generate(steps.length * 2 - 1, (i) {
        if (i.isOdd) {
          final stepIndex = i ~/ 2;
          final passed = _currentStep > stepIndex;
          return Expanded(
            child: Container(
              height: 2,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color:
                passed ? _T.orange : tc.darkBorder.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          );
        }
        final stepIndex = i ~/ 2;
        final active = _currentStep == stepIndex;
        final done = _currentStep > stepIndex;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done
                    ? _T.orange
                    : active
                    ? Colors.transparent
                    : tc.cardFill,
                border: Border.all(
                  color: done || active
                      ? _T.orange
                      : tc.darkBorder.withValues(alpha: 0.2),
                  width: active ? 2 : 1.5,
                ),
                boxShadow: active || done
                    ? [
                  BoxShadow(
                      color: _T.orange.withValues(alpha: 0.3),
                      blurRadius: 10)
                ]
                    : [],
              ),
              child: Center(
                child: done
                    ? const Icon(Icons.check_rounded,
                    color: Colors.white, size: 16)
                    : Text('${stepIndex + 1}',
                    style: TextStyle(
                      color: active ? _T.orange : tc.textMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    )),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              steps[stepIndex],
              style: TextStyle(
                color: active
                    ? tc.textBlack
                    : done
                    ? _T.orange
                    : tc.textMuted,
                fontSize: 11,
                fontWeight: active ? FontWeight.w700 : FontWeight.normal,
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildStepContent(_ThemeColors tc) {
    switch (_currentStep) {
      case 0:
        return _buildStep1(tc);
      case 1:
        return _buildStep2(tc);
      case 2:
        return _buildStep3(tc);
      default:
        return const SizedBox();
    }
  }

  Widget _buildStep1(_ThemeColors tc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('SELECT LEAVE TYPE',
            style: TextStyle(
              color: tc.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            )),
        const SizedBox(height: 14),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.15,
          children: _leaveTypes.map((lt) {
            final sel = _selectedLeaveType == lt.code;
            return GestureDetector(
              onTap: () => setState(() => _selectedLeaveType = lt.code),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  gradient: sel ? _T.brandGradient : null,
                  color: sel ? null : tc.cardBg,
                  borderRadius: BorderRadius.circular(_T.r14),
                  border: Border.all(
                    color: sel
                        ? _T.orange
                        : tc.darkBorder.withValues(alpha: 0.15),
                    width: sel ? 1.5 : 1,
                  ),
                  boxShadow: sel
                      ? [
                    BoxShadow(
                        color: _T.orange.withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4))
                  ]
                      : [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 6,
                        offset: const Offset(0, 2))
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(lt.icon,
                        color: sel ? Colors.white : tc.textMuted, size: 22),
                    const SizedBox(height: 6),
                    Text(lt.code,
                        style: TextStyle(
                          color: sel ? Colors.white : tc.textBlack,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        )),
                    const SizedBox(height: 2),
                    Text(lt.label,
                        style: TextStyle(
                          color: sel
                              ? Colors.white.withValues(alpha: 0.85)
                              : tc.textGray,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        )),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildStep2(_ThemeColors tc) {
    return Column(
      children: [
        _buildWhiteCard(
          tc: tc,
          icon: Icons.calendar_today_rounded,
          title: 'Duration Details',
          child: Column(
            children: [
              _buildDatePicker(
                  tc, 'Start Date', _startDate, () => _pickDate(true)),
              const SizedBox(height: 12),
              _buildDatePicker(
                  tc, 'End Date', _endDate, () => _pickDate(false)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                      child: _buildInfoField(
                          tc, 'Total Days', '${_leaveDays.toStringAsFixed(0)}')),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _buildInfoField(tc, 'Total Hours',
                          '${(_leaveDays * 8).toStringAsFixed(1)}')),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildWhiteCard(
          tc: tc,
          icon: Icons.edit_note_rounded,
          title: 'Justification',
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: tc.cardFill,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: tc.darkBorder.withValues(alpha: 0.15)),
            ),
            child: TextField(
              controller: _reasonCtrl,
              maxLines: 4,
              style: TextStyle(color: tc.textBlack, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Enter reason for leave...',
                hintStyle: TextStyle(color: tc.textMuted, fontSize: 14),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStep3(_ThemeColors tc) {
    return Column(
      children: [
        _buildWhiteCard(
          tc: tc,
          title: 'Leave Information',
          editButton: true,
          onEdit: () => setState(() => _currentStep = 0),
          child: Column(
            children: [
              _infoRow(tc, 'Type of Leave', _leaveDisplay),
              const SizedBox(height: 12),
              _infoRow(tc, 'Duration', _durationDisplay),
              const SizedBox(height: 12),
              _infoRow(tc, 'Dates', _datesDisplay),
              const SizedBox(height: 12),
              _infoRow(tc, 'Reason', _reasonDisplay, isMultiLine: true),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildWhiteCard(
          tc: tc,
          title: 'Approver Information',
          editButton: true,
          onEdit: () => setState(() => _currentStep = 1),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tc.cardFill,
                  border: Border.all(
                      color: tc.darkBorder.withValues(alpha: 0.2), width: 2),
                ),
                child: Center(
                  child: Text('HR',
                      style: TextStyle(
                          color: tc.textGray,
                          fontSize: 16,
                          fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('HR',
                        style: TextStyle(
                            color: tc.textBlack,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                    Text('Human Resources',
                        style: TextStyle(
                            color: tc.textGray,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: tc.textMuted),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildWhiteCard(
          tc: tc,
          title: 'Approval Workflow',
          editButton: false,
          child: Column(
            children: [
              _workflowStep(
                tc: tc,
                stage: 'Stage 1',
                role: 'Immediate Supervisor',
                status: 'David Henderson (Pending)',
                isComplete: false,
              ),
              const SizedBox(height: 16),
              _workflowStep(
                tc: tc,
                stage: 'Final Stage',
                role: 'Department Head',
                status: 'Automatic routing upon Stage 1 approval',
                isComplete: false,
                isLast: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () => setState(() => _isCertified = !_isCertified),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 24,
                  height: 24,
                  margin: const EdgeInsets.only(top: 2),
                  decoration: BoxDecoration(
                    color: _isCertified ? _T.orange : tc.bg,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: _isCertified
                          ? _T.orange
                          : tc.darkBorder.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  ),
                  child: _isCertified
                      ? const Icon(Icons.check, color: Colors.white, size: 16)
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'I certify that all information provided above is true and that my reliever has been fully briefed on my pending tasks.',
                  style: TextStyle(
                      color: tc.textGray, fontSize: 12, height: 1.6),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWhiteCard({
    required _ThemeColors tc,
    required String title,
    required Widget child,
    IconData? icon,
    bool editButton = false,
    VoidCallback? onEdit,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tc.cardBg,
        borderRadius: BorderRadius.circular(_T.r16),
        border:
        Border.all(color: tc.darkBorder.withValues(alpha: 0.15), width: 1.15),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: _T.orange, size: 20),
                    const SizedBox(width: 10),
                  ],
                  Text(title,
                      style: TextStyle(
                          color: tc.textBlack,
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                ],
              ),
              if (editButton && onEdit != null)
                GestureDetector(
                  onTap: onEdit,
                  behavior: HitTestBehavior.opaque,
                  child: const Text('Edit',
                      style: TextStyle(
                          color: _T.orange,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildDatePicker(
      _ThemeColors tc, String label, DateTime? value, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  color: tc.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: tc.cardFill,
              borderRadius: BorderRadius.circular(_T.r12),
              border: Border.all(color: tc.darkBorder.withValues(alpha: 0.15)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _fmt(value),
                    style: TextStyle(
                      color: value != null ? tc.textBlack : tc.textMuted,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Icon(Icons.calendar_today_rounded,
                    color: tc.textMuted, size: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoField(_ThemeColors tc, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                color: tc.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: tc.cardFill,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: tc.darkBorder.withValues(alpha: 0.15)),
          ),
          child: Text(value,
              style: TextStyle(
                  color: tc.textBlack,
                  fontSize: 14,
                  fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }

  Widget _infoRow(_ThemeColors tc, String label, String value,
      {bool isMultiLine = false}) {
    return Row(
      crossAxisAlignment:
      isMultiLine ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 100,
          child: Text(label,
              style: TextStyle(
                  color: tc.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
                color: tc.textBlack,
                fontSize: 14,
                fontWeight: FontWeight.w600),
            maxLines: isMultiLine ? 3 : 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _workflowStep({
    required _ThemeColors tc,
    required String stage,
    required String role,
    required String status,
    required bool isComplete,
    bool isLast = false,
  }) {
    final int stepNumber = stage == 'Stage 1' ? 1 : 2;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isComplete ? _T.orange : tc.cardFill,
                border: Border.all(
                  color: isComplete
                      ? _T.orange
                      : tc.darkBorder.withValues(alpha: 0.15),
                  width: 2,
                ),
              ),
              child: isComplete
                  ? const Icon(Icons.check, color: Colors.white, size: 16)
                  : Center(
                child: Text('$stepNumber',
                    style: TextStyle(
                        color: tc.textGray,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
            ),
            if (!isLast)
              SizedBox(
                height: 32,
                child: VerticalDivider(
                  color: tc.darkBorder.withValues(alpha: 0.15),
                  width: 2,
                  thickness: 2,
                  indent: 4,
                  endIndent: 4,
                ),
              ),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(stage,
                  style: TextStyle(
                      color: tc.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(role,
                  style: TextStyle(
                      color: tc.textBlack,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
              Text(status,
                  style: TextStyle(
                      color: tc.textGray,
                      fontSize: 12,
                      fontWeight: FontWeight.w400)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActions(_ThemeColors tc) {
    final isLastStep = _currentStep == 2;

    return Column(
      children: [
        GestureDetector(
          onTap:
          isLastStep ? (_isSubmitting ? null : _submitApplication) : _goNext,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity,
            height: 54,
            decoration: BoxDecoration(
              gradient: _T.brandGradient,
              borderRadius: BorderRadius.circular(_T.r16),
              border: Border.all(color: _T.orangeBorder, width: 1.15),
              boxShadow: [
                BoxShadow(
                    color: _T.orange.withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 6)),
              ],
            ),
            child: Center(
              child: _isSubmitting
                  ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2.5),
              )
                  : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isLastStep ? 'Submit Application' : 'Continue',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    isLastStep
                        ? Icons.send_rounded
                        : Icons.arrow_forward_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (!isLastStep) ...[
          GestureDetector(
            onTap: _goBack,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: double.infinity,
              height: 50,
              decoration: BoxDecoration(
                color: tc.bg,
                borderRadius: BorderRadius.circular(_T.r16),
                border: Border.all(
                    color: tc.darkBorder.withValues(alpha: 0.15), width: 1.15),
              ),
              child: Center(
                child: Text('Back',
                    style: TextStyle(
                        color: tc.textGray,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ] else ...[
          GestureDetector(
            onTap: _isSubmitting ? null : _saveAsDraft,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: double.infinity,
              height: 50,
              decoration: BoxDecoration(
                color: tc.bg,
                borderRadius: BorderRadius.circular(_T.r16),
                border: Border.all(
                    color: tc.darkBorder.withValues(alpha: 0.15), width: 1.15),
              ),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.save_alt_rounded,
                        color: tc.textGray, size: 17),
                    const SizedBox(width: 8),
                    Text('Save as Draft',
                        style: TextStyle(
                            color: tc.textGray,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}