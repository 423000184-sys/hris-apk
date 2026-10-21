// lib/screens/admin_activity_page.dart
// v2.3: 🔗 OneSignal Push Notifications integrated for Leave & Client Meeting Approvals.
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_datepicker/datepicker.dart';
import 'admin_theme.dart';
import 'admin_create_leave_request_page.dart';
import 'admin_database.dart';
import '../services/employee_notification_service.dart';
import '../services/admin_audit_service.dart';
import '../services/admin_auth_service.dart';
import '../services/demo_mode_service.dart';
import '../services/onesignal_sender.dart'; // 🆕 Added for push notifications

class AdminActivityPage extends StatefulWidget {
  final List<Map<String, dynamic>> employees;
  final Map<String, List<Map<String, dynamic>>> userLogs;
  final String searchQuery;
  final List<Map<String, dynamic>> loginLogs;
  final VoidCallback? onCreateLeaveRequest;
  final VoidCallback? onAssignClientMeeting;

  const AdminActivityPage({
    super.key,
    required this.employees,
    required this.userLogs,
    required this.searchQuery,
    this.loginLogs = const [],
    this.onCreateLeaveRequest,
    this.onAssignClientMeeting,
  });

  @override
  State<AdminActivityPage> createState() => _AdminActivityPageState();
}

class _AdminActivityPageState extends State<AdminActivityPage> {
  AdminColors get tc => AdminTheme.getColors(context);

  bool get _isDemo {
    try {
      return DemoModeService.instance.isEnabled;
    } catch (_) {
      return false;
    }
  }

  final _SecurityGuard _guard = _SecurityGuard();
  final Set<String> _inFlight = <String>{};

  StreamSubscription<QuerySnapshot>? _leaveSub;
  List<Map<String, dynamic>> _pendingLeaveApplications = [];
  bool _loadingApplications = true;
  String? _streamError;

  int _debugTotalDocs = 0;
  int _debugPendingCount = 0;
  final List<String> _debugStatuses = [];

  StreamSubscription<QuerySnapshot>? _clientMeetingSub;
  List<Map<String, dynamic>> _allClientMeetings = [];
  List<Map<String, dynamic>> _pendingClientMeetings = [];
  bool _loadingClientMeetings = true;

  String _selectedDepartment = 'All Departments';
  String _selectedLeaveType = 'All Types';
  DateTimeRange? _selectedDateRange;

  static const List<String> _leaveTypeOptions = [
    'All Types', 'SL', 'VL', 'EL', 'BL', 'ML', 'Others',
  ];

  void _demoBlock() {
    _toast('Action disabled in Demo Mode.', error: true);
  }

  List<Map<String, dynamic>> _getMockPendingLeaves() {
    final now = DateTime.now();
    return [
      {
        'employee': {'name': 'John Doe', 'department': 'Operation'},
        'request': {
          'id': 'demo_leave_1',
          'leaveType': 'VL',
          'dateFrom': now.add(const Duration(days: 2)),
          'dateTo': now.add(const Duration(days: 4)),
          'totalDays': 3,
          'reason': 'Family vacation',
          'status': 'pending',
          'createdAt': now.subtract(const Duration(hours: 2)),
        },
        'employeeName': 'John Doe',
        'isFromEmployeeCollection': true,
        'source': 'employee',
      },
      {
        'employee': {'name': 'Jane Smith', 'department': 'Accounting'},
        'request': {
          'id': 'demo_leave_2',
          'leaveType': 'SL',
          'dateFrom': now.subtract(const Duration(days: 1)),
          'dateTo': now.subtract(const Duration(days: 1)),
          'totalDays': 1,
          'reason': 'Medical checkup',
          'status': 'pending',
          'createdAt': now.subtract(const Duration(hours: 5)),
        },
        'employeeName': 'Jane Smith',
        'isFromEmployeeCollection': true,
        'source': 'employee',
      },
    ];
  }

  List<Map<String, dynamic>> _getMockClientMeetings() {
    final now = DateTime.now();
    return [
      {
        'id': 'demo_cm_1',
        'employee_id': 'DEMO-001',
        'employee_name': 'John Doe',
        'location_name': 'Makati Office',
        'status': 'pending_hr_approval',
        'timestamp': now.subtract(const Duration(minutes: 30)),
        'gps_accuracy_meters': 15.0,
        'is_verified_at_client': true,
        'assigned_client_name': 'Acme Corp',
        'assigned_purpose': 'Quarterly review',
      },
      {
        'id': 'demo_cm_2',
        'employee_id': 'DEMO-003',
        'employee_name': 'Mike Johnson',
        'location_name': 'BGC Tower',
        'status': 'pending_hr_approval',
        'timestamp': now.subtract(const Duration(hours: 1)),
        'gps_accuracy_meters': 80.0,
        'is_verified_at_client': false,
        'assigned_client_name': 'Global Tech',
        'assigned_purpose': 'Initial presentation',
      }
    ];
  }

  static String _sanitize(dynamic raw, {int maxLen = 120}) {
    if (raw == null) return '';
    var s = raw.toString();
    s = s.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');
    s = s.replaceAll(RegExp(r'[\r\n\t]+'), ' ');
    s = s.replaceAll(
        RegExp(r'[\u200B-\u200F\u202A-\u202E\u2066-\u2069]'), '');
    if (s.length > maxLen) s = '${s.substring(0, maxLen)}…';
    return s.trim();
  }

  static bool _isValidDocId(String id) {
    if (id.isEmpty || id.length > 1500) return false;
    if (id == '.' || id == '..') return false;
    if (id.contains('/')) return false;
    return true;
  }

  static bool _isPlausibleTimestamp(DateTime? dt) {
    if (dt == null) return false;
    final now = DateTime.now();
    final lower = DateTime(2020);
    final upper = now.add(const Duration(days: 1));
    return dt.isAfter(lower) && dt.isBefore(upper);
  }

  String _safeError(Object e) {
    if (kDebugMode) return e.toString();
    return 'Something went wrong. Please try again.';
  }

  Future<User?> _currentAdmin() async {
    try {
      final u = FirebaseAuth.instance.currentUser;
      if (u == null) return null;
      await u.getIdToken(true);
      return u;
    } catch (_) {
      return null;
    }
  }

  void _toast(String msg, {bool success = false, bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_sanitize(msg, maxLen: 200)),
        backgroundColor:
        error ? tc.red : (success ? tc.green : tc.orange),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    if (!_isDemo) {
      _listenToPendingLeaves();
      _listenToClientMeetings();
    } else {
      _loadingApplications = false;
      _loadingClientMeetings = false;
    }
  }

  @override
  void dispose() {
    _leaveSub?.cancel();
    _clientMeetingSub?.cancel();
    _inFlight.clear();
    super.dispose();
  }

  void _listenToPendingLeaves() {
    _leaveSub?.cancel();
    _leaveSub = FirebaseFirestore.instance
        .collection('leave_applications')
        .snapshots()
        .listen(
          (snapshot) {
        final statuses = <String>[];
        if (kDebugMode) {
          for (final doc in snapshot.docs) {
            final data = doc.data();
            statuses.add(
                '${doc.id} → status="${data['status'] ?? '(missing)'}" | '
                    'name="${data['employeeName'] ?? '(no name)'}"');
          }
        }

        final pendingDocs = snapshot.docs.where((doc) {
          final status =
          (doc.data()['status'] ?? '').toString().toLowerCase().trim();
          return status == 'pending';
        }).toList();

        final apps = pendingDocs
            .map((doc) => <String, dynamic>{'id': doc.id, ...doc.data()})
            .toList();

        apps.sort((a, b) {
          final dtA = _toDateTime(a['createdAt']) ?? DateTime(1970);
          final dtB = _toDateTime(b['createdAt']) ?? DateTime(1970);
          return dtB.compareTo(dtA);
        });

        if (!mounted) return;
        setState(() {
          _pendingLeaveApplications = apps;
          _loadingApplications = false;
          _streamError = null;
          _debugTotalDocs = snapshot.docs.length;
          _debugPendingCount = pendingDocs.length;
          _debugStatuses
            ..clear()
            ..addAll(statuses);
        });
      },
      onError: (e) {
        debugPrint('⚠️ leave stream error: $e');
        if (!mounted) return;
        setState(() {
          _loadingApplications = false;
          _streamError = _safeError(e);
        });
      },
    );
  }

  void _listenToClientMeetings() {
    _clientMeetingSub?.cancel();
    _clientMeetingSub = FirebaseFirestore.instance
        .collection('attendance_logs')
        .where('type', isEqualTo: 'client_meeting')
        .snapshots()
        .listen(
          (snapshot) {
        final all = snapshot.docs
            .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
            .where((e) {
          final empId =
          (e['employee_id'] ?? e['employeeId'] ?? '').toString();
          return !_isInvalidEmployeeId(empId);
        }).toList();

        final pending = all.where((e) {
          final s = (e['status'] ?? '').toString().toLowerCase().trim();
          return s == 'pending_hr_approval' || s == 'pending';
        }).toList();

        int cmp(Map<String, dynamic> a, Map<String, dynamic> b) {
          final dtA = _toDateTime(a['timestamp'] ?? a['createdAt']) ??
              DateTime(1970);
          final dtB = _toDateTime(b['timestamp'] ?? b['createdAt']) ??
              DateTime(1970);
          return dtB.compareTo(dtA);
        }

        all.sort(cmp);
        pending.sort(cmp);

        if (!mounted) return;
        setState(() {
          _allClientMeetings = all;
          _pendingClientMeetings = pending;
          _loadingClientMeetings = false;
        });
      },
      onError: (e) {
        debugPrint('⚠️ clientMeetings stream error: $e');
        if (!mounted) return;
        setState(() => _loadingClientMeetings = false);
      },
    );
  }

  List<Map<String, dynamic>> _applyFilters(
      List<Map<String, dynamic>> list) {
    var filtered = list;

    if (_selectedDepartment != 'All Departments') {
      filtered = filtered.where((item) {
        final emp = item['employee'] as Map<String, dynamic>;
        final dept =
        _sanitize(emp['department'] ?? emp['role'] ?? '', maxLen: 60);
        return dept == _selectedDepartment;
      }).toList();
    }

    if (_selectedLeaveType != 'All Types') {
      filtered = filtered.where((item) {
        final req = item['request'] as Map<String, dynamic>;
        final type = (req['leaveType'] ?? 'Others').toString().trim();
        return type == _selectedLeaveType;
      }).toList();
    }

    if (_selectedDateRange != null) {
      final start = DateTime(
        _selectedDateRange!.start.year,
        _selectedDateRange!.start.month,
        _selectedDateRange!.start.day,
      );
      final end = DateTime(
        _selectedDateRange!.end.year,
        _selectedDateRange!.end.month,
        _selectedDateRange!.end.day,
        23, 59, 59,
      );
      filtered = filtered.where((item) {
        final req = item['request'] as Map<String, dynamic>;
        final dt = _toDateTime(req['dateFrom'] ?? req['startDate']);
        if (dt == null) return false;
        return dt.isAfter(start.subtract(const Duration(seconds: 1))) &&
            dt.isBefore(end.add(const Duration(seconds: 1)));
      }).toList();
    }

    return filtered;
  }

  Future<String?> _promptRejectionReason({
    required String title,
    required String subtitle,
  }) async {
    final ctrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: tc.card,
        title: Text(title, style: TextStyle(color: tc.text)),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(subtitle, style: TextStyle(color: tc.text)),
              const SizedBox(height: 12),
              TextFormField(
                controller: ctrl,
                maxLength: 300,
                minLines: 2,
                maxLines: 4,
                style: TextStyle(color: tc.text),
                decoration: InputDecoration(
                  hintText: 'Dahilan ng pag-reject (required)…',
                  hintStyle: TextStyle(color: tc.muted),
                  filled: true,
                  fillColor: tc.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.length < 5) {
                    return 'Minimum 5 characters ang dahilan.';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              // ✅ FIX: Unfocus bago i-pop ang dialog para maiwasan ang assertion error sa Web
              FocusScope.of(ctx).unfocus();
              Navigator.pop(ctx);
            },
            child: Text('Cancel', style: TextStyle(color: tc.muted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: tc.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              // ✅ FIX: Unfocus bago i-pop ang dialog
              FocusScope.of(ctx).unfocus();
              Navigator.pop(ctx, _sanitize(ctrl.text, maxLen: 300));
            },
            child: const Text('Confirm Reject'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return result;
  }

  Future<void> _openFilterDialog() async {
    String tempDept = _selectedDepartment;
    String tempType = _selectedLeaveType;
    DateTimeRange? tempRange = _selectedDateRange;

    final applied = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setS) {
            final dialogTc = AdminTheme.getColors(ctx);

            return Dialog(
              backgroundColor: dialogTc.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              insetPadding: const EdgeInsets.all(24),
              child: Container(
                width: 500,
                constraints: const BoxConstraints(maxHeight: 700),
                padding: const EdgeInsets.all(20),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.filter_list_rounded,
                              color: dialogTc.orange, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Filter Activity',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: dialogTc.text,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.close_rounded,
                                color: dialogTc.muted, size: 20),
                            onPressed: () =>
                                Navigator.pop(dialogCtx, false),
                            tooltip: 'Close',
                          ),
                        ],
                      ),
                      Divider(color: dialogTc.border, height: 24),
                      Text('DEPARTMENT',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: dialogTc.muted,
                              letterSpacing: 0.6)),
                      const SizedBox(height: 6),
                      Container(
                        padding:
                        const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: dialogTc.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: dialogTc.border),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: tempDept,
                            isExpanded: true,
                            dropdownColor: dialogTc.card,
                            icon: Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: dialogTc.muted,
                                size: 20),
                            style: TextStyle(
                                color: dialogTc.text, fontSize: 13),
                            items: _departments.map((d) {
                              return DropdownMenuItem<String>(
                                value: d,
                                child: Text(_sanitize(d, maxLen: 60)),
                              );
                            }).toList(),
                            onChanged: (v) => setS(() {
                              if (v != null) tempDept = v;
                            }),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text('LEAVE TYPE',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: dialogTc.muted,
                              letterSpacing: 0.6)),
                      const SizedBox(height: 6),
                      Container(
                        padding:
                        const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: dialogTc.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: dialogTc.border),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: tempType,
                            isExpanded: true,
                            dropdownColor: dialogTc.card,
                            icon: Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: dialogTc.muted,
                                size: 20),
                            style: TextStyle(
                                color: dialogTc.text, fontSize: 13),
                            items: _leaveTypeOptions.map((t) {
                              final label = t == 'All Types'
                                  ? t
                                  : _leaveTypeDisplay(t);
                              return DropdownMenuItem<String>(
                                value: t,
                                child: Text(label),
                              );
                            }).toList(),
                            onChanged: (v) => setS(() {
                              if (v != null) tempType = v;
                            }),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text('DATE RANGE (Leave Start Date)',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: dialogTc.muted,
                              letterSpacing: 0.6)),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: () async {
                          DateTimeRange? tempRange2 = tempRange;

                          final picked = await showDialog<bool>(
                            context: ctx,
                            barrierDismissible: true,
                            builder: (dateCtx) {
                              final dateTc =
                              AdminTheme.getColors(dateCtx);
                              return Dialog(
                                backgroundColor: dateTc.card,
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                  BorderRadius.circular(16),
                                ),
                                insetPadding:
                                const EdgeInsets.all(24),
                                child: Container(
                                  width: 640,
                                  height: 620,
                                  padding: const EdgeInsets.fromLTRB(
                                      20, 20, 20, 16),
                                  child: Column(
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                              Icons.date_range_rounded,
                                              color: dateTc.orange,
                                              size: 22),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              'Select Date Range',
                                              style: TextStyle(
                                                fontSize: 18,
                                                fontWeight:
                                                FontWeight.w700,
                                                color: dateTc.text,
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            icon: Icon(
                                                Icons.close_rounded,
                                                color: dateTc.muted,
                                                size: 20),
                                            onPressed: () =>
                                                Navigator.pop(
                                                    dateCtx, false),
                                          ),
                                        ],
                                      ),
                                      Divider(
                                          color: dateTc.border,
                                          height: 20),
                                      Expanded(
                                        child: SfDateRangePicker(
                                          view: DateRangePickerView.month,
                                          selectionMode:
                                          DateRangePickerSelectionMode.range,
                                          initialSelectedRange:
                                          tempRange != null
                                              ? PickerDateRange(
                                            tempRange!.start,
                                            tempRange!.end,
                                          )
                                              : null,
                                          minDate: DateTime(2020),
                                          maxDate: DateTime.now(),
                                          showActionButtons: false,
                                          enablePastDates: true,
                                          onSelectionChanged:
                                              (DateRangePickerSelectionChangedArgs args) {
                                            if (args.value is PickerDateRange) {
                                              final range = args.value as PickerDateRange;
                                              if (range.startDate != null) {
                                                tempRange2 = DateTimeRange(
                                                  start: range.startDate!,
                                                  end: range.endDate ?? range.startDate!,
                                                );
                                              }
                                            }
                                          },
                                          backgroundColor: dateTc.card,
                                          headerStyle: DateRangePickerHeaderStyle(
                                            backgroundColor: dateTc.card,
                                            textStyle: TextStyle(
                                              color: dateTc.text,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 15,
                                            ),
                                          ),
                                          monthCellStyle: DateRangePickerMonthCellStyle(
                                            textStyle: TextStyle(
                                              color: dateTc.text,
                                              fontSize: 13,
                                            ),
                                            todayTextStyle: TextStyle(
                                              color: dateTc.orange,
                                              fontWeight: FontWeight.w700,
                                            ),
                                            trailingDatesTextStyle: TextStyle(
                                              color: dateTc.muted.withValues(alpha: 0.5),
                                            ),
                                            leadingDatesTextStyle: TextStyle(
                                              color: dateTc.muted.withValues(alpha: 0.5),
                                            ),
                                          ),
                                          monthViewSettings: DateRangePickerMonthViewSettings(
                                            viewHeaderStyle: DateRangePickerViewHeaderStyle(
                                              textStyle: TextStyle(
                                                color: dateTc.muted,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                          rangeSelectionColor: dateTc.orange.withValues(alpha: 0.25),
                                          startRangeSelectionColor: dateTc.orange,
                                          endRangeSelectionColor: dateTc.orange,
                                          todayHighlightColor: dateTc.orange,
                                          selectionColor: dateTc.orange,
                                          selectionTextStyle: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      Divider(
                                          color: dateTc.border,
                                          height: 20),
                                      Row(
                                        children: [
                                          if (tempRange != null)
                                            TextButton.icon(
                                              onPressed: () {
                                                tempRange2 = null;
                                                Navigator.pop(
                                                    dateCtx, true);
                                              },
                                              icon: Icon(
                                                  Icons.clear_rounded,
                                                  size: 14,
                                                  color: dateTc.muted),
                                              label: Text(
                                                'CLEAR',
                                                style: TextStyle(
                                                  color: dateTc.muted,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                          const Spacer(),
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(
                                                    dateCtx, false),
                                            child: Text(
                                              'CANCEL',
                                              style: TextStyle(
                                                color: dateTc.muted,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          ElevatedButton(
                                            onPressed: () =>
                                                Navigator.pop(
                                                    dateCtx, true),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: dateTc.orange,
                                              foregroundColor: Colors.white,
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 22,
                                                  vertical: 12),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              elevation: 0,
                                            ),
                                            child: const Text(
                                              'APPLY',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 12,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );

                          if (picked == true) {
                            setS(() => tempRange = tempRange2);
                          }
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 14),
                          decoration: BoxDecoration(
                            color: dialogTc.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: tempRange != null
                                  ? dialogTc.orange
                                  : dialogTc.border,
                              width: tempRange != null ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  tempRange == null
                                      ? 'Select date range'
                                      : '${DateFormat('MMM d, yyyy').format(tempRange!.start)} - '
                                      '${DateFormat('MMM d, yyyy').format(tempRange!.end)}',
                                  style: TextStyle(
                                    color: tempRange != null
                                        ? dialogTc.text
                                        : dialogTc.muted,
                                    fontSize: 13,
                                    fontWeight: tempRange != null
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (tempRange != null)
                                InkWell(
                                  onTap: () =>
                                      setS(() => tempRange = null),
                                  child: Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: Icon(Icons.clear_rounded,
                                        size: 16,
                                        color: dialogTc.muted),
                                  ),
                                )
                              else
                                Icon(Icons.calendar_today_rounded,
                                    size: 16, color: dialogTc.muted),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Divider(color: dialogTc.border, height: 1),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: () {
                              setS(() {
                                tempDept = 'All Departments';
                                tempType = 'All Types';
                                tempRange = null;
                              });
                            },
                            icon: Icon(Icons.refresh_rounded,
                                size: 14, color: dialogTc.muted),
                            label: Text(
                              'RESET',
                              style: TextStyle(
                                color: dialogTc.muted,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () =>
                                Navigator.pop(dialogCtx, false),
                            child: Text(
                              'CANCEL',
                              style: TextStyle(
                                color: dialogTc.muted,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: () =>
                                Navigator.pop(dialogCtx, true),
                            icon: const Icon(Icons.check_rounded,
                                size: 14, color: Colors.white),
                            label: const Text(
                              'APPLY FILTERS',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                letterSpacing: 0.5,
                                color: Colors.white,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: dialogTc.orange,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              elevation: 0,
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
    );

    if (applied == true) {
      setState(() {
        _selectedDepartment = tempDept;
        _selectedLeaveType = tempType;
        _selectedDateRange = tempRange;
      });
    }
  }

  // ══════════════════════════════════════════════════════════════
  // APPROVE CLIENT MEETING (With OneSignal Push)
  // ══════════════════════════════════════════════════════════════
  Future<void> _approveClientMeeting(Map<String, dynamic> meeting) async {
    if (_isDemo) return _demoBlock();

    final id = (meeting['id'] ?? '').toString();

    if (!_isValidDocId(id)) {
      _toast('Invalid meeting reference.', error: true);
      return;
    }
    if (_inFlight.contains(id)) return;
    if (!_guard.tryAcquire('approve_cm')) {
      _toast('Masyadong mabilis. Please wait a moment.', error: true);
      return;
    }

    _inFlight.add(id);
    try {
      final admin = await _currentAdmin();
      if (admin == null) {
        _toast('Session expired. Please sign in again.', error: true);
        return;
      }

      final empName = _resolveDisplayName(meeting);
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: tc.card,
          title: Text('Approve Client Meeting',
              style: TextStyle(color: tc.text)),
          content: Text('Approve client meeting ni $empName?',
              style: TextStyle(color: tc.text)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Cancel', style: TextStyle(color: tc.muted)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: tc.green,
                foregroundColor: Colors.white,
              ),
              child: const Text('Approve'),
            ),
          ],
        ),
      );
      if (confirm != true) return;

      final err = await AdminDatabase.approveClientMeeting(id);
      if (!mounted) return;

      if (err == null) {
        unawaited(AdminAuditService.instance.log(
          action: 'approve_client_meeting',
          targetId: id,
          targetType: 'client_meeting',
          adminUid: admin?.uid,
          metadata: {'employee_name': empName},
        ));

        try {
          final empId = _sanitize(
            meeting['employee_id'] ?? meeting['employeeId'] ?? '',
            maxLen: 64,
          );
          if (empId.isNotEmpty && !_isInvalidEmployeeId(empId)) {
            await EmployeeNotificationService.instance.send(
              type: 'reminder',
              title: '✅ Client Meeting Approved',
              message:
              'Approved na ang iyong client meeting sa '
                  '${_sanitize(meeting['location_name'] ?? 'N/A', maxLen: 80)}.',
              employeeId: empId,
              priority: 'high',
            );

            // 🆕 ONESIGNAL PUSH NOTIFICATION
            await OneSignalSender.instance.sendToEmployee(
              employeeId: empId,
              title: '✅ Client Meeting Approved',
              message: 'Approved na ang iyong client meeting sa ${_sanitize(meeting['location_name'] ?? 'N/A', maxLen: 80)}.',
              type: 'reminder',
            );
          }
        } catch (e) {
          debugPrint('⚠️ notify approval failed: $e');
        }

        _toast('Client meeting approved!', success: true);
      } else {
        _toast(_safeError(err), error: true);
      }
    } catch (e) {
      debugPrint('❌ approve CM: $e');
      if (mounted) _toast(_safeError(e), error: true);
    } finally {
      _inFlight.remove(id);
    }
  }

  // ══════════════════════════════════════════════════════════════
  // REJECT CLIENT MEETING (With OneSignal Push)
  // ══════════════════════════════════════════════════════════════
  Future<void> _rejectClientMeeting(Map<String, dynamic> meeting) async {
    if (_isDemo) return _demoBlock();

    final id = (meeting['id'] ?? '').toString();
    if (!_isValidDocId(id)) {
      _toast('Invalid meeting reference.', error: true);
      return;
    }
    if (_inFlight.contains(id)) return;
    if (!_guard.tryAcquire('reject_cm')) {
      _toast('Masyadong mabilis. Please wait a moment.', error: true);
      return;
    }

    _inFlight.add(id);
    try {
      final admin = await _currentAdmin();
      if (admin == null) {
        _toast('Session expired. Please sign in again.', error: true);
        return;
      }

      final empName = _resolveDisplayName(meeting);
      final reason = await _promptRejectionReason(
        title: 'Reject Client Meeting',
        subtitle: 'I-reject ang client meeting ni $empName?',
      );
      if (reason == null) return;

      final err = await AdminDatabase.rejectClientMeeting(id);
      if (!mounted) return;

      if (err == null) {
        unawaited(AdminAuditService.instance.log(
          action: 'reject_client_meeting',
          targetId: id,
          targetType: 'client_meeting',
          adminUid: admin?.uid,
          metadata: {'employee_name': empName, 'reason': reason},
        ));

        try {
          final empId = _sanitize(
            meeting['employee_id'] ?? meeting['employeeId'] ?? '',
            maxLen: 64,
          );
          if (empId.isNotEmpty && !_isInvalidEmployeeId(empId)) {
            await EmployeeNotificationService.instance.send(
              type: 'reminder',
              title: '❌ Client Meeting Rejected',
              message:
              'Hindi na-approve ang iyong client meeting. Reason: $reason',
              employeeId: empId,
              priority: 'high',
            );

            // 🆕 ONESIGNAL PUSH NOTIFICATION
            await OneSignalSender.instance.sendToEmployee(
              employeeId: empId,
              title: '❌ Client Meeting Rejected',
              message: 'Hindi na-approve ang iyong client meeting. Reason: $reason',
              type: 'reminder',
            );
          }
        } catch (e) {
          debugPrint('⚠️ notify rejection failed: $e');
        }

        _toast('Client meeting rejected.', success: false);
      } else {
        _toast(_safeError(err), error: true);
      }
    } catch (e) {
      debugPrint('❌ reject CM: $e');
      if (mounted) _toast(_safeError(e), error: true);
    } finally {
      _inFlight.remove(id);
    }
  }

  // ══════════════════════════════════════════════════════════════
  // APPROVE LEAVE REQUEST (With OneSignal Push)
  // ══════════════════════════════════════════════════════════════
  Future<void> _approveLeaveRequest(
      BuildContext context,
      Map<String, dynamic> request,
      Map<String, dynamic> employee,
      bool isFromEmployeeCollection,
      ) async {
    if (_isDemo) return _demoBlock();

    final reqId = (request['id'] ?? '').toString();
    if (!_isValidDocId(reqId)) {
      _toast('Invalid request reference.', error: true);
      return;
    }
    if (_inFlight.contains('L_$reqId')) return;
    if (!_guard.tryAcquire('approve_leave')) {
      _toast('Masyadong mabilis. Please wait.', error: true);
      return;
    }

    _inFlight.add('L_$reqId');
    try {
      final admin = await _currentAdmin();
      if (admin == null) {
        _toast('Session expired. Please sign in again.', error: true);
        return;
      }

      final employeeAuthUid = (employee['authUid'] ??
          employee['uid'] ??
          employee['id'] ??
          '')
          .toString();
      if (employeeAuthUid.isNotEmpty && employeeAuthUid == admin.uid) {
        _toast('Hindi mo pwedeng i-approve ang sarili mong request.',
            error: true);
        return;
      }

      final empName = _empName(employee);
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: tc.card,
          title: Text('Approve Leave Request',
              style: TextStyle(color: tc.text)),
          content: Text('Approve leave request for $empName?',
              style: TextStyle(color: tc.text)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Cancel', style: TextStyle(color: tc.muted)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: tc.green,
                foregroundColor: Colors.white,
              ),
              child: const Text('Approve'),
            ),
          ],
        ),
      );
      if (confirm != true) return;

      if (isFromEmployeeCollection) {
        await FirebaseFirestore.instance
            .collection('leave_applications')
            .doc(reqId)
            .update({
          'status': 'approved',
          'approvedAt': FieldValue.serverTimestamp(),
          'reviewedBy': admin.uid ?? 'admin',
        });
      } else {
        final empId = (employee['id'] ?? '').toString();
        if (!_isValidDocId(empId)) {
          throw Exception('Invalid employee ID');
        }
        final leaveRequests = (employee['leaveRequests'] as List?) ?? [];
        final updatedRequests = leaveRequests.map((req) {
          if (req['id'] == request['id']) {
            return {...req, 'status': 'approved'};
          }
          return req;
        }).toList();
        await FirebaseFirestore.instance
            .collection('employees')
            .doc(empId)
            .update({'leaveRequests': updatedRequests});
      }

      if (!mounted) return;

      unawaited(AdminAuditService.instance.log(
        action: 'approve_leave',
        targetId: reqId,
        targetType: 'leave_application',
        adminUid: admin?.uid,
        metadata: {
          'employee_name': empName,
          'employee_id':
          (request['employeeId'] ?? employee['id'] ?? '').toString(),
          'leave_type': request['leaveType'] ?? '',
        },
      ));

      try {
        final empId = _sanitize(
          request['employeeId'] ??
              employee['id'] ??
              employee['employeeId'] ??
              '',
          maxLen: 64,
        );
        final leaveType =
        _leaveTypeDisplay(request['leaveType'] ?? 'Leave');
        final start = _formatDate(request['dateFrom'] ?? request['startDate']);
        final end = _formatDate(request['dateTo'] ?? request['endDate']);
        if (empId.isNotEmpty) {
          await EmployeeNotificationService.instance.send(
            type: 'reminder',
            title: '✅ Leave Approved',
            message:
            'Approved na ang iyong $leaveType request ($start – $end).',
            employeeId: empId,
            priority: 'high',
          );

          // 🆕 ONESIGNAL PUSH NOTIFICATION
          await OneSignalSender.instance.sendToEmployee(
            employeeId: empId,
            title: '✅ Leave Approved',
            message: 'Approved na ang iyong $leaveType request ($start – $end).',
            type: 'reminder',
          );
        }
      } catch (e) {
        debugPrint('⚠️ Approval notification failed: $e');
      }

      if (!mounted) return;
      _toast('Leave request approved!', success: true);
    } catch (e) {
      debugPrint('❌ approve leave: $e');
      if (mounted) _toast(_safeError(e), error: true);
    } finally {
      _inFlight.remove('L_$reqId');
    }
  }

  // ══════════════════════════════════════════════════════════════
  // REJECT LEAVE REQUEST (With OneSignal Push)
  // ══════════════════════════════════════════════════════════════
  Future<void> _rejectLeaveRequest(
      BuildContext context,
      Map<String, dynamic> request,
      Map<String, dynamic> employee,
      bool isFromEmployeeCollection,
      ) async {
    if (_isDemo) return _demoBlock();

    final reqId = (request['id'] ?? '').toString();
    if (!_isValidDocId(reqId)) {
      _toast('Invalid request reference.', error: true);
      return;
    }
    if (_inFlight.contains('L_$reqId')) return;
    if (!_guard.tryAcquire('reject_leave')) {
      _toast('Masyadong mabilis.', error: true);
      return;
    }

    _inFlight.add('L_$reqId');
    try {
      final admin = await _currentAdmin();
      if (admin == null) {
        _toast('Session expired. Please sign in again.', error: true);
        return;
      }

      final empName = _empName(employee);
      final reason = await _promptRejectionReason(
        title: 'Reject Leave Request',
        subtitle: 'I-reject ang leave request ni $empName?',
      );
      if (reason == null) return;

      if (isFromEmployeeCollection) {
        await FirebaseFirestore.instance
            .collection('leave_applications')
            .doc(reqId)
            .update({
          'status': 'rejected',
          'rejectedAt': FieldValue.serverTimestamp(),
          'rejectionReason': reason,
          'reviewedBy': admin.uid ?? 'admin',
        });
      } else {
        final empId = (employee['id'] ?? '').toString();
        if (!_isValidDocId(empId)) {
          throw Exception('Invalid employee ID');
        }
        final leaveRequests = (employee['leaveRequests'] as List?) ?? [];
        final updatedRequests = leaveRequests.map((req) {
          if (req['id'] == request['id']) {
            return {
              ...req,
              'status': 'rejected',
              'rejectionReason': reason,
            };
          }
          return req;
        }).toList();
        await FirebaseFirestore.instance
            .collection('employees')
            .doc(empId)
            .update({'leaveRequests': updatedRequests});
      }

      if (!mounted) return;

      unawaited(AdminAuditService.instance.log(
        action: 'reject_leave',
        targetId: reqId,
        targetType: 'leave_application',
        adminUid: admin?.uid,
        metadata: {
          'employee_name': empName,
          'reason': reason,
        },
      ));

      try {
        final empId = _sanitize(
          request['employeeId'] ??
              employee['id'] ??
              employee['employeeId'] ??
              '',
          maxLen: 64,
        );
        final leaveType =
        _leaveTypeDisplay(request['leaveType'] ?? 'Leave');
        final start = _formatDate(request['dateFrom'] ?? request['startDate']);
        final end = _formatDate(request['dateTo'] ?? request['endDate']);
        if (empId.isNotEmpty) {
          await EmployeeNotificationService.instance.send(
            type: 'reminder',
            title: '❌ Leave Rejected',
            message:
            'Hindi na-approve ang iyong $leaveType request ($start – $end). Reason: $reason',
            employeeId: empId,
            priority: 'high',
          );

          // 🆕 ONESIGNAL PUSH NOTIFICATION
          await OneSignalSender.instance.sendToEmployee(
            employeeId: empId,
            title: '❌ Leave Rejected',
            message: 'Hindi na-approve ang iyong $leaveType request ($start – $end). Reason: $reason',
            type: 'reminder',
          );
        }
      } catch (e) {
        debugPrint('⚠️ Rejection notification failed: $e');
      }

      if (!mounted) return;
      _toast('Leave request rejected.', success: false);
    } catch (e) {
      debugPrint('❌ reject leave: $e');
      if (mounted) _toast(_safeError(e), error: true);
    } finally {
      _inFlight.remove('L_$reqId');
    }
  }

  // ══════════════════════════════════════════════════════════════
  // HELPERS
  // ══════════════════════════════════════════════════════════════
  String _getInitials(String name) {
    final clean = _sanitize(name, maxLen: 80);
    final parts = clean.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    } else if (parts.isNotEmpty && parts[0].isNotEmpty) {
      return parts[0][0].toUpperCase();
    }
    return 'EMP';
  }

  String _empName(Map<String, dynamic> employee) {
    final dynamic name = employee['name'];
    if (name != null && name.toString().trim().isNotEmpty) {
      return _sanitize(name, maxLen: 80);
    }
    final first = _sanitize(employee['firstName'] ?? '', maxLen: 40);
    final last = _sanitize(employee['lastName'] ?? '', maxLen: 40);
    final full = '$first $last'.trim();
    return full.isEmpty ? 'Unknown' : full;
  }

  String _leaveTypeDisplay(String code) {
    const types = {
      'SL': 'Sick Leave',
      'VL': 'Vacation Leave',
      'EL': 'Emergency',
      'BL': 'Bereavement',
      'ML': 'Maternity/Paternity',
      'Others': 'Others',
    };
    return types[code] ?? _sanitize(code, maxLen: 40);
  }

  DateTime? _toDateTime(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  String _formatDate(dynamic date) {
    final dt = _toDateTime(date);
    if (dt == null || !_isPlausibleTimestamp(dt)) return 'N/A';
    return DateFormat('MMM d, yyyy').format(dt);
  }

  Map<String, dynamic> _normalizeAppDoc(Map<String, dynamic> app) {
    return {
      'id': app['id'],
      'employeeName': _sanitize(app['employeeName'] ?? '', maxLen: 80),
      'position': _sanitize(app['position'] ?? '', maxLen: 60),
      'department': _sanitize(app['department'] ?? '', maxLen: 60),
      'dateFrom': _toDateTime(app['startDate']),
      'dateTo': _toDateTime(app['endDate']),
      'totalDays': app['days'] ?? 0,
      'totalHours': app['hours'] ?? 0,
      'leaveType': app['leaveType'] ?? 'Others',
      'reason': _sanitize(app['reason'] ?? '', maxLen: 300),
      'status': app['status'] ?? 'pending',
      'createdAt': _toDateTime(app['createdAt']) ?? DateTime.now(),
    };
  }

  List<String> get _departments {
    if (_isDemo) {
      return ['All Departments', 'Operation', 'Accounting', 'HR/Admin'];
    }
    final depts = <String>{};
    for (final emp in widget.employees) {
      final dept = _sanitize(
          emp['department'] ?? emp['role'] ?? '', maxLen: 60);
      if (dept.isNotEmpty && dept != '—') depts.add(dept);
    }
    final sorted = depts.toList()..sort();
    return ['All Departments', ...sorted];
  }

  int get _activeFilterCount {
    int c = 0;
    if (_selectedDepartment != 'All Departments') c++;
    if (_selectedLeaveType != 'All Types') c++;
    if (_selectedDateRange != null) c++;
    return c;
  }

  bool get _hasActiveFilters => _activeFilterCount > 0;

  bool _isInvalidEmployeeId(String empId) {
    if (empId.isEmpty) return true;
    final lower = empId.toLowerCase().trim();
    if (lower.startsWith('guest_')) return true;
    if (lower.startsWith('auth_')) return true;
    return false;
  }

  String _resolveDisplayName(Map<String, dynamic> record) {
    final rawName = _sanitize(
      record['employee_name'] ?? record['employeeName'] ?? 'Unknown',
      maxLen: 80,
    );

    if (!rawName.toLowerCase().contains('guest') &&
        !rawName.toLowerCase().contains('unidentified')) {
      return rawName;
    }

    final empId = _sanitize(
      record['employee_id'] ?? record['employeeId'] ?? '',
      maxLen: 64,
    );
    if (empId.isNotEmpty) {
      for (final emp in widget.employees) {
        final id = (emp['id'] ?? '').toString();
        final eid = (emp['employeeId'] ?? '').toString();
        if (id == empId || eid == empId) return _empName(emp);
      }
    }
    return rawName;
  }

  Map<String, dynamic> _computeActualAttendance(DateTime now) {
    final todayStr = DateFormat('yyyy-MM-dd').format(now);
    final Set<String> attendedEmpIds = {};
    final Map<String, DateTime> firstClockInToday = {};

    for (final entry in widget.userLogs.entries) {
      final empId = entry.key;
      final logs = entry.value;

      for (final log in logs) {
        String logDateStr = (log['date'] ?? '').toString().trim();

        if (logDateStr.isEmpty) {
          final ts = _toDateTime(log['timestamp'] ?? log['created_at']);
          if (ts != null) {
            logDateStr = DateFormat('yyyy-MM-dd').format(ts);
          }
        }

        if (logDateStr != todayStr) continue;

        final type = (log['type'] ?? '').toString().toUpperCase().trim();
        final isClockIn = type == 'IN' ||
            type == 'CLOCK_IN' ||
            type == 'CLOCK IN' ||
            type == 'LOGIN' ||
            type == 'TIME IN' ||
            type == 'TIME_IN';

        if (!isClockIn) continue;

        attendedEmpIds.add(empId);

        final ts = _toDateTime(log['timestamp'] ?? log['time']);
        if (ts != null && _isPlausibleTimestamp(ts)) {
          final existing = firstClockInToday[empId];
          if (existing == null || ts.isBefore(existing)) {
            firstClockInToday[empId] = ts;
          }
        }

        break;
      }
    }

    return {
      'count': attendedEmpIds.length,
      'ids': attendedEmpIds,
      'firstClockIn': firstClockInToday,
    };
  }

  Map<String, dynamic> _computeFraudBadge(Map<String, dynamic> m) {
    final isMocked = m['gps_is_mocked'] == true;
    final isVerified = m['is_verified_at_client'] == true;
    final severity = (m['anti_fraud_severity'] ?? 'clean').toString();

    if (isMocked || severity == 'critical') {
      return {
        'bg': tc.red.withValues(alpha: 0.15),
        'fg': tc.red,
        'icon': Icons.dangerous_rounded,
        'label': '🚨 FAKE GPS',
      };
    } else if (isVerified) {
      return {
        'bg': tc.green.withValues(alpha: 0.15),
        'fg': tc.green,
        'icon': Icons.verified_rounded,
        'label': '✅ VERIFIED',
      };
    } else if (severity == 'high') {
      return {
        'bg': tc.red.withValues(alpha: 0.12),
        'fg': tc.red,
        'icon': Icons.warning_rounded,
        'label': '⚠️ HIGH RISK',
      };
    } else {
      return {
        'bg': tc.orange.withValues(alpha: 0.15),
        'fg': tc.orangeText,
        'icon': Icons.help_outline_rounded,
        'label': '⚠️ UNVERIFIED',
      };
    }
  }

  Widget _fraudBadge({
    required IconData icon,
    required String label,
    required Color bg,
    required Color fg,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: fg),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              _sanitize(label, maxLen: 60),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _fraudDetailLine({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 6),
          Text(
            '$label:',
            style: TextStyle(fontSize: 10, color: tc.muted),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _sanitize(value, maxLen: 80),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    List<Map<String, dynamic>> allPendingRequests = [];

    if (_isDemo) {
      allPendingRequests = _getMockPendingLeaves();
    } else {
      for (var emp in widget.employees) {
        final requests = (emp['leaveRequests'] as List?) ?? [];
        for (var req in requests) {
          final status = (req['status'] ?? '').toString().toLowerCase().trim();
          if (status == 'pending') {
            allPendingRequests.add({
              'employee': emp,
              'request': req,
              'employeeName': _empName(emp),
              'isFromEmployeeCollection': false,
              'source': 'admin',
            });
          }
        }
      }

      for (var app in _pendingLeaveApplications) {
        final empId = (app['employeeId'] ?? '').toString();
        final employee = widget.employees.firstWhere(
              (e) => (e['id'] ?? '').toString() == empId,
          orElse: () => {
            'id': empId,
            'name': _sanitize(app['employeeName'] ?? 'Unknown Employee',
                maxLen: 80),
            'department': 'N/A',
          },
        );
        allPendingRequests.add({
          'employee': employee,
          'request': _normalizeAppDoc(app),
          'employeeName': _sanitize(
              app['employeeName'] ?? _empName(employee),
              maxLen: 80),
          'isFromEmployeeCollection': true,
          'source': 'employee',
        });
      }
    }

    allPendingRequests.sort((a, b) {
      final dtA = _toDateTime(a['request']['createdAt']) ?? DateTime(1970);
      final dtB = _toDateTime(b['request']['createdAt']) ?? DateTime(1970);
      return dtB.compareTo(dtA);
    });

    final q = widget.searchQuery.toLowerCase();
    var filteredRequests = q.isEmpty
        ? allPendingRequests
        : allPendingRequests
        .where(
            (i) => i['employeeName'].toString().toLowerCase().contains(q))
        .toList();

    filteredRequests = _applyFilters(filteredRequests);

    final actualPendingLeaveCount = allPendingRequests.length;

    int actualOnLeaveTodayCount = 0;
    int totalEmployees = _isDemo ? 26 : widget.employees.length;
    int actualAttendanceCount = 0;
    double attendanceRate = 0.0;

    if (_isDemo) {
      actualOnLeaveTodayCount = 3;
      actualAttendanceCount = 24;
      attendanceRate = 92.3;
    } else {
      for (var emp in widget.employees) {
        final status =
        (emp['status'] ?? emp['workStatus'] ?? '').toString().toLowerCase();
        final bool isOnLeaveFlag = emp['isOnLeave'] == true;
        bool isLeaveToday = false;
        final start = _toDateTime(emp['leaveStartDate']);
        final end = _toDateTime(emp['leaveEndDate']);
        if (start != null && end != null) {
          final todayPure = DateTime(now.year, now.month, now.day);
          final startPure = DateTime(start.year, start.month, start.day);
          final endPure = DateTime(end.year, end.month, end.day);
          if (!todayPure.isBefore(startPure) && !todayPure.isAfter(endPure)) {
            isLeaveToday = true;
          }
        }
        if (isOnLeaveFlag ||
            status == 'on leave' ||
            status == 'on_leave' ||
            isLeaveToday) {
          actualOnLeaveTodayCount++;
        }
      }

      final attendanceData = _computeActualAttendance(now);
      actualAttendanceCount = attendanceData['count'] as int;
      attendanceRate = totalEmployees > 0
          ? (actualAttendanceCount / totalEmployees) * 100
          : 0.0;
    }

    final List<Map<String, dynamic>> displayPendingMeetings = _isDemo
        ? _getMockClientMeetings()
        : _pendingClientMeetings;

    final List<Map<String, dynamic>> allTimelineLogs = [];
    if (_isDemo) {
      allTimelineLogs.addAll(_getMockClientMeetings());
      for (var m in allTimelineLogs) {
        m['details'] = 'Client Meeting — ${m['location_name']}';
      }
    } else {
      for (var cm in _allClientMeetings) {
        final empId = (cm['employee_id'] ?? cm['employeeId'] ?? '').toString();
        if (_isInvalidEmployeeId(empId)) continue;

        final empName = _resolveDisplayName(cm);
        final ts = cm['timestamp'] ?? cm['createdAt'];
        final location = _sanitize(cm['location_name'] ?? '', maxLen: 80);
        final status = (cm['status'] ?? '').toString();

        allTimelineLogs.add({
          'id': cm['id'],
          'employee_name': empName,
          'employee_id': empId,
          'type': 'client_meeting',
          'timestamp': ts,
          'location_name': location,
          'status': status,
          'details':
          'Client Meeting — ${location.isEmpty ? 'Unknown location' : location}',
        });
      }
    }

    allTimelineLogs.sort((a, b) {
      final dtA = _toDateTime(a['timestamp']) ?? DateTime(1970);
      final dtB = _toDateTime(b['timestamp']) ?? DateTime(1970);
      return dtB.compareTo(dtA);
    });

    return Container(
      color: tc.background,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_isDemo) ...[
                  _buildDemoBanner(),
                  const SizedBox(height: 24),
                ],
                _buildPageHeader(),
                const SizedBox(height: 24),

                if (_hasActiveFilters) ...[
                  _buildActiveFilterChips(),
                  const SizedBox(height: 16),
                ],

                _buildMetricGrid(
                  actualPendingLeaveCount,
                  actualOnLeaveTodayCount,
                  attendanceRate,
                  actualAttendanceCount,
                  totalEmployees,
                ),
                const SizedBox(height: 20),
                if (_loadingClientMeetings ||
                    displayPendingMeetings.isNotEmpty) ...[
                  _buildClientMeetingsTable(displayPendingMeetings),
                  const SizedBox(height: 20),
                ],
                _recentActivityCard(allTimelineLogs),
                const SizedBox(height: 20),
                _buildPendingTable(
                  filteredRequests,
                  allPendingRequests.length,
                ),
                const SizedBox(height: 60),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDemoBanner() {
    return Container(
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Demo Mode Active',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: tc.orange,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Showing sample data. Approving and rejecting requests are disabled.',
                  style: TextStyle(
                    fontSize: 11,
                    color: tc.textMuted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveFilterChips() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tc.orange.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.filter_alt_rounded, size: 16, color: tc.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (_selectedDepartment != 'All Departments')
                  _filterChip(
                    label: _sanitize(_selectedDepartment, maxLen: 60),
                    onRemove: () => setState(
                            () => _selectedDepartment = 'All Departments'),
                  ),
                if (_selectedLeaveType != 'All Types')
                  _filterChip(
                    label: _leaveTypeDisplay(_selectedLeaveType),
                    onRemove: () =>
                        setState(() => _selectedLeaveType = 'All Types'),
                  ),
                if (_selectedDateRange != null)
                  _filterChip(
                    label:
                    '${DateFormat('MMM d').format(_selectedDateRange!.start)} - '
                        '${DateFormat('MMM d').format(_selectedDateRange!.end)}',
                    onRemove: () =>
                        setState(() => _selectedDateRange = null),
                  ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () {
              setState(() {
                _selectedDepartment = 'All Departments';
                _selectedLeaveType = 'All Types';
                _selectedDateRange = null;
              });
            },
            icon: Icon(Icons.clear_all_rounded,
                size: 14, color: tc.orange),
            label: Text(
              'CLEAR ALL',
              style: TextStyle(
                color: tc.orange,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required VoidCallback onRemove,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: tc.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tc.orange.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: tc.orangeText,
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(10),
            child: Icon(Icons.close_rounded,
                size: 14, color: tc.orangeText),
          ),
        ],
      ),
    );
  }

  Widget _buildPageHeader() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 800.0;
        final narrow = w < 768;

        final titleWidget = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Activity & Leave Management',
              style: TextStyle(
                fontSize: narrow ? 20 : 24,
                fontWeight: FontWeight.w800,
                color: tc.text,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Oversee biometric logs and process leave applications in real-time.',
              style: TextStyle(fontSize: narrow ? 12 : 13, color: tc.muted),
            ),
          ],
        );

        final assignBtn = ElevatedButton.icon(
          onPressed: () {
            if (widget.onAssignClientMeeting != null) {
              widget.onAssignClientMeeting!();
            } else {
              debugPrint(
                  '⚠️ onAssignClientMeeting callback not provided — '
                      'button does nothing.');
            }
          },
          icon: const Icon(Icons.assignment_ind_rounded, size: 16),
          label: const Text('Assign Client Meeting'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3B82F6),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            elevation: 0,
          ),
        );

        final createBtn = ElevatedButton.icon(
          onPressed: widget.onCreateLeaveRequest ??
                  () {
                Navigator.push(
                  context,
                  adminRoute(
                    AdminCreateLeaveRequestPage(
                      employees: widget.employees,
                      onBack: () => Navigator.pop(context),
                    ),
                  ),
                );
              },
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Create Leave Request'),
          style: ElevatedButton.styleFrom(
            backgroundColor: tc.orange,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            elevation: 0,
          ),
        );

        final filterBtn = OutlinedButton.icon(
          onPressed: _openFilterDialog,
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.filter_list, size: 16),
              if (_hasActiveFilters)
                Positioned(
                  top: -4,
                  right: -4,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: tc.orange,
                      shape: BoxShape.circle,
                      border: Border.all(color: tc.card, width: 1.5),
                    ),
                    child: Text(
                      '$_activeFilterCount',
                      style: const TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          label: Text(
            _hasActiveFilters
                ? 'Filters ($_activeFilterCount)'
                : 'Filters',
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: _hasActiveFilters ? tc.orange : tc.text,
            side: BorderSide(
              color: _hasActiveFilters ? tc.orange : tc.border,
              width: _hasActiveFilters ? 1.5 : 1,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );

        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              titleWidget,
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: createBtn),
                  const SizedBox(width: 10),
                  filterBtn,
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(width: double.infinity, child: assignBtn),
            ],
          );
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: titleWidget),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                assignBtn,
                const SizedBox(width: 10),
                createBtn,
                const SizedBox(width: 10),
                filterBtn,
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildMetricGrid(
      int pendingCount,
      int onLeaveCount,
      double attendanceRate,
      int attendedCount,
      int totalEmployees,
      ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 800.0;
        final int cols = w >= 768 ? 3 : 1;
        const double gap = 16;
        final double itemWidth = (w - (cols - 1) * gap) / cols;

        final cards = <Widget>[
          _metricCard(
            'PENDING LEAVE',
            '$pendingCount ${pendingCount == 1 ? 'Request' : 'Requests'}',
            Icons.assignment_outlined,
            isOrange: true,
          ),
          _metricCard(
            'ON LEAVE TODAY',
            '$onLeaveCount Staff',
            Icons.person_off_outlined,
          ),
          _metricCard(
            'TOTAL ATTENDANCE',
            '${attendanceRate.toStringAsFixed(1)}%',
            Icons.groups_outlined,
            subtitle: '$attendedCount of $totalEmployees clocked in today',
          ),
        ];

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: cards
              .map((c) => SizedBox(width: itemWidth, child: c))
              .toList(),
        );
      },
    );
  }

  Widget _buildClientMeetingsTable(List<Map<String, dynamic>> meetings) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 800.0;
        final isMobile = w < 768;

        return Container(
          decoration: BoxDecoration(
            color: tc.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: tc.border),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Icon(Icons.business_center_rounded,
                        size: 18, color: tc.orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Pending Client Meetings',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: tc.text),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: tc.orange.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${meetings.length}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: tc.orangeText,
                        ),
                      ),
                    ),
                    if (_loadingClientMeetings) ...[
                      const SizedBox(width: 10),
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
                  ],
                ),
              ),
              if (meetings.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: 32, color: tc.muted),
                      const SizedBox(height: 8),
                      Text(
                        'Walang pending client meeting approvals.',
                        style: TextStyle(color: tc.muted, fontSize: 13),
                      ),
                    ],
                  ),
                )
              else
                ...meetings.map((m) => isMobile
                    ? _buildClientMeetingMobileCard(m)
                    : _buildClientMeetingRow(m)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildClientMeetingRow(Map<String, dynamic> m) {
    final empName = _resolveDisplayName(m);
    final empId = _sanitize(
        m['employee_id'] ?? m['employeeId'] ?? '', maxLen: 64);
    final location =
    _sanitize(m['location_name'] ?? 'N/A', maxLen: 80);
    final dt = _toDateTime(m['timestamp'] ?? m['createdAt']);
    final dateStr =
    dt != null ? DateFormat('MMM d, yyyy · h:mm a').format(dt) : 'N/A';

    final accuracy = (m['gps_accuracy_meters'] as num?)?.toDouble();
    final isVerified = m['is_verified_at_client'] == true;
    final distanceM = (m['distance_from_client_m'] as num?)?.toDouble();
    final matchedName =
    _sanitize(m['matched_client_name'] ?? '', maxLen: 60);
    final flags = (m['anti_fraud_flags'] as List?)?.cast<String>() ?? [];

    final assignmentId = m['assignment_id']?.toString();
    final assignedClient =
    _sanitize(m['assigned_client_name'] ?? '', maxLen: 60);
    final assignedPurpose =
    _sanitize(m['assigned_purpose'] ?? '', maxLen: 150);
    final hasAssignment = assignmentId != null && assignmentId.isNotEmpty;

    final badge = _computeFraudBadge(m);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tc.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: tc.orange.withValues(alpha: 0.15),
                      child: Text(
                        _getInitials(empName),
                        style: TextStyle(
                            color: tc.orangeText,
                            fontSize: 11,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            empName,
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: tc.text),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            empId.isEmpty ? 'Client Meeting' : 'ID: $empId',
                            style: TextStyle(fontSize: 11, color: tc.muted),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    Icon(Icons.location_on_rounded,
                        size: 12, color: tc.orangeText),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        location,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: tc.text),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  dateStr,
                  style: TextStyle(fontSize: 11, color: tc.muted),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(
                width: 80,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _actionButton(
                      icon: Icons.check,
                      bgColor: _isDemo ? tc.surface : tc.pillWarnBg,
                      iconColor: _isDemo ? tc.muted : tc.pillWarnTx,
                      onTap: () => _approveClientMeeting(m),
                    ),
                    const SizedBox(width: 6),
                    _actionButton(
                      icon: Icons.close,
                      bgColor: _isDemo ? tc.surface : tc.pillErrBg,
                      iconColor: _isDemo ? tc.muted : tc.pillErrTx,
                      onTap: () => _rejectClientMeeting(m),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (hasAssignment)
                _fraudBadge(
                  icon: Icons.assignment_turned_in_rounded,
                  label: '📋 ${assignedClient.isEmpty ? 'Assigned' : assignedClient}',
                  bg: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                  fg: const Color(0xFF3B82F6),
                ),
              if (!hasAssignment)
                _fraudBadge(
                  icon: Icons.assignment_late_rounded,
                  label: '⚠️ No Assignment',
                  bg: tc.orange.withValues(alpha: 0.12),
                  fg: tc.orangeText,
                ),
              _fraudBadge(
                icon: badge['icon'] as IconData,
                label: badge['label'] as String,
                bg: badge['bg'] as Color,
                fg: badge['fg'] as Color,
              ),
              if (accuracy != null)
                _fraudBadge(
                  icon: Icons.gps_fixed_rounded,
                  label: 'GPS ±${accuracy.toStringAsFixed(0)}m',
                  bg: accuracy > 200
                      ? tc.red.withValues(alpha: 0.1)
                      : tc.surface,
                  fg: accuracy > 200 ? tc.red : tc.muted,
                ),
              if (isVerified && matchedName.isNotEmpty)
                _fraudBadge(
                  icon: Icons.business_rounded,
                  label: matchedName,
                  bg: tc.green.withValues(alpha: 0.1),
                  fg: tc.green,
                ),
              if (!isVerified && matchedName.isNotEmpty && distanceM != null)
                _fraudBadge(
                  icon: Icons.straighten_rounded,
                  label:
                  '${distanceM.toStringAsFixed(0)}m from $matchedName',
                  bg: tc.orange.withValues(alpha: 0.08),
                  fg: tc.orangeText,
                ),
              if (flags.contains('stale_location'))
                _fraudBadge(
                  icon: Icons.timer_off_rounded,
                  label: 'Stale location',
                  bg: tc.orange.withValues(alpha: 0.1),
                  fg: tc.orangeText,
                ),
              if (flags.contains('no_location'))
                _fraudBadge(
                  icon: Icons.location_off_rounded,
                  label: 'No GPS',
                  bg: tc.red.withValues(alpha: 0.1),
                  fg: tc.red,
                ),
            ],
          ),
          if (assignedPurpose.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 11, color: tc.muted),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    assignedPurpose,
                    style: TextStyle(
                        fontSize: 10,
                        color: tc.muted,
                        fontStyle: FontStyle.italic),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildClientMeetingMobileCard(Map<String, dynamic> m) {
    final empName = _resolveDisplayName(m);
    final empId = _sanitize(
        m['employee_id'] ?? m['employeeId'] ?? '', maxLen: 64);
    final location =
    _sanitize(m['location_name'] ?? 'N/A', maxLen: 80);
    final dt = _toDateTime(m['timestamp'] ?? m['createdAt']);
    final dateStr =
    dt != null ? DateFormat('MMM d, yyyy · h:mm a').format(dt) : 'N/A';

    final isMocked = m['gps_is_mocked'] == true;
    final accuracy = (m['gps_accuracy_meters'] as num?)?.toDouble();
    final isVerified = m['is_verified_at_client'] == true;
    final distanceM = (m['distance_from_client_m'] as num?)?.toDouble();
    final matchedName =
    _sanitize(m['matched_client_name'] ?? '', maxLen: 60);
    final severity = (m['anti_fraud_severity'] ?? 'clean').toString();

    final assignmentId = m['assignment_id']?.toString();
    final assignedClient =
    _sanitize(m['assigned_client_name'] ?? '', maxLen: 60);
    final assignedPurpose =
    _sanitize(m['assigned_purpose'] ?? '', maxLen: 150);
    final hasAssignment = assignmentId != null && assignmentId.isNotEmpty;

    final badge = _computeFraudBadge(m);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tc.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: tc.orange.withValues(alpha: 0.15),
                child: Text(
                  _getInitials(empName),
                  style: TextStyle(
                      color: tc.orangeText,
                      fontSize: 12,
                      fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      empName,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: tc.text),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (empId.isNotEmpty)
                      Text(
                        'ID: $empId',
                        style: TextStyle(fontSize: 11, color: tc.muted),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: badge['bg'] as Color,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(badge['icon'] as IconData,
                        size: 11, color: badge['fg'] as Color),
                    const SizedBox(width: 4),
                    Text(
                      badge['label'] as String,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: badge['fg'] as Color),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (hasAssignment) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF3B82F6).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: const Color(0xFF3B82F6).withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.assignment_turned_in_rounded,
                      size: 12, color: Color(0xFF3B82F6)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Assigned: ${assignedClient.isEmpty ? '—' : assignedClient}',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF3B82F6)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: tc.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: tc.orange.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.assignment_late_rounded,
                      size: 12, color: tc.orangeText),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'No Assignment — nag-improvise employee',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: tc.orangeText),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.location_on_rounded,
                  size: 12, color: tc.orangeText),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  location,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: tc.text),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.access_time_rounded, size: 12, color: tc.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(dateStr,
                    style: TextStyle(fontSize: 11, color: tc.muted),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          if (assignedPurpose.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 12, color: tc.muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Purpose: $assignedPurpose',
                    style: TextStyle(
                        fontSize: 11,
                        color: tc.muted,
                        fontStyle: FontStyle.italic),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          if (accuracy != null ||
              distanceM != null ||
              matchedName.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: tc.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isMocked || severity == 'high'
                      ? tc.red.withValues(alpha: 0.3)
                      : tc.border,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (accuracy != null)
                    _fraudDetailLine(
                      icon: Icons.gps_fixed_rounded,
                      label: 'GPS accuracy',
                      value: '±${accuracy.toStringAsFixed(0)}m',
                      color: accuracy > 200 ? tc.red : tc.text,
                    ),
                  if (matchedName.isNotEmpty)
                    _fraudDetailLine(
                      icon: Icons.business_rounded,
                      label: 'Matched client',
                      value: matchedName,
                      color: isVerified ? tc.green : tc.orangeText,
                    ),
                  if (distanceM != null)
                    _fraudDetailLine(
                      icon: Icons.straighten_rounded,
                      label: 'Distance',
                      value: '${distanceM.toStringAsFixed(0)}m',
                      color: tc.text,
                    ),
                  if (isMocked)
                    _fraudDetailLine(
                      icon: Icons.warning_amber_rounded,
                      label: 'Mock GPS',
                      value: 'DETECTED',
                      color: tc.red,
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _rejectClientMeeting(m),
                  icon: Icon(Icons.close, size: 14, color: _isDemo ? tc.muted : tc.pillErrTx),
                  label: Text('Reject',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _isDemo ? tc.muted : tc.pillErrTx)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                        color: (_isDemo ? tc.border : tc.pillErrTx).withValues(alpha: 0.3)),
                    backgroundColor: _isDemo ? tc.surface : tc.pillErrBg,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _approveClientMeeting(m),
                  icon: Icon(Icons.check, size: 14, color: _isDemo ? tc.muted : Colors.white),
                  label: Text('Approve',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _isDemo ? tc.muted : Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isDemo ? tc.border : tc.green,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPendingTable(
      List<Map<String, dynamic>> filteredRequests, int totalPending) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 800.0;
        final isMobile = w < 768;

        return Container(
          decoration: BoxDecoration(
            color: tc.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: tc.border),
          ),
          child: Column(
            children: [
              _buildPendingTableHeader(isMobile),
              if (!isMobile) _buildPendingTableColumnHeaders(),
              if (filteredRequests.isEmpty)
                _emptyState()
              else
                ...filteredRequests.map((item) => isMobile
                    ? _buildRequestMobileCard(item)
                    : _buildRequestRow(item)),
              _buildPendingTableFooter(filteredRequests.length, totalPending),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPendingTableHeader(bool isMobile) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: isMobile
          ? Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _pendingTableTitleRow(),
          const SizedBox(height: 12),
          _departmentDropdown(),
        ],
      )
          : Row(
        children: [
          Expanded(child: _pendingTableTitleRow()),
          const SizedBox(width: 12),
          _departmentDropdown(),
        ],
      ),
    );
  }

  Widget _pendingTableTitleRow() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            'Pending Leave Requests',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: tc.text),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        if (_loadingApplications)
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        if (_streamError != null)
          Tooltip(
            message: _streamError!,
            child: Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Icon(Icons.error_outline, size: 14, color: tc.red),
            ),
          ),
        if (kDebugMode &&
            !_loadingApplications &&
            _streamError == null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: tc.surface,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '$_debugTotalDocs in DB · $_debugPendingCount pending',
              style: TextStyle(fontSize: 9, color: tc.muted),
            ),
          ),
      ],
    );
  }

  Widget _departmentDropdown() {
    return InkWell(
      onTap: _openFilterDialog,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _selectedDepartment != 'All Departments'
              ? tc.orange.withValues(alpha: 0.12)
              : tc.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _selectedDepartment != 'All Departments'
                ? tc.orange.withValues(alpha: 0.4)
                : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _sanitize(_selectedDepartment, maxLen: 60),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _selectedDepartment != 'All Departments'
                    ? tc.orangeText
                    : tc.text,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down,
                size: 14,
                color: _selectedDepartment != 'All Departments'
                    ? tc.orangeText
                    : tc.muted),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingTableColumnHeaders() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: tc.surface,
      child: Row(
        children: [
          _th('EMPLOYEE', flex: 3),
          _th('TYPE', flex: 2),
          _th('DATES', flex: 2),
          _th('DAYS', flex: 1),
          SizedBox(
            width: 80,
            child: Text(
              'ACTIONS',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: tc.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingTableFooter(int shown, int total) {
    return Padding(
      padding: const EdgeInsets.all(14.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              _hasActiveFilters
                  ? 'Showing $shown of $total (filtered)'
                  : 'Showing $shown of $total pending requests',
              style: TextStyle(fontSize: 11, color: tc.muted),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 24, height: 24, child: _PageBtn()),
              SizedBox(width: 4),
              SizedBox(width: 24, height: 24, child: _PageBtn()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _th(String label, {required int flex}) => Expanded(
    flex: flex,
    child: Text(label,
        style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: tc.muted)),
  );

  Widget _buildRequestRow(Map<String, dynamic> item) {
    final emp = item['employee'];
    final req = item['request'];
    final empName = _sanitize(item['employeeName'] ?? '', maxLen: 80);
    final isFromEmployee = item['isFromEmployeeCollection'] ?? false;
    final source = item['source'] ?? 'admin';
    final dept =
    _sanitize(emp['department'] ?? emp['role'] ?? 'IT', maxLen: 60);

    final leaveTypeDisplay = _leaveTypeDisplay(req['leaveType'] ?? 'Others');
    final fromStr = _formatDate(req['dateFrom']);
    final toStr = _formatDate(req['dateTo']);
    final daysStr = (req['totalDays'] ?? req['days'] ?? 0).toString();

    final isFromEmployeeSource = source == 'employee';
    final sourceLabel = isFromEmployeeSource ? 'Self' : 'Admin';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tc.border)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: tc.orange.withValues(alpha: 0.15),
                  child: Text(
                    _getInitials(empName),
                    style: TextStyle(
                        color: tc.orangeText,
                        fontSize: 11,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              empName.isEmpty ? 'Unknown Staff' : empName,
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: tc.text),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: isFromEmployeeSource
                                  ? tc.pillGreenBg
                                  : tc.pillBlueBg,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              sourceLabel,
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.w600,
                                color: isFromEmployeeSource
                                    ? tc.pillGreenTx
                                    : tc.pillBlueTx,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        dept,
                        style: TextStyle(fontSize: 11, color: tc.muted),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: tc.surface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  leaveTypeDisplay,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: tc.text),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '$fromStr - $toStr',
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.bold, color: tc.text),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              '$daysStr day${daysStr != '1' ? 's' : ''}',
              style: TextStyle(fontSize: 11, color: tc.muted),
            ),
          ),
          SizedBox(
            width: 80,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                _actionButton(
                  icon: Icons.check,
                  bgColor: _isDemo ? tc.surface : tc.pillWarnBg,
                  iconColor: _isDemo ? tc.muted : tc.pillWarnTx,
                  onTap: () => _approveLeaveRequest(
                      context, req, emp, isFromEmployee),
                ),
                const SizedBox(width: 6),
                _actionButton(
                  icon: Icons.close,
                  bgColor: _isDemo ? tc.surface : tc.pillErrBg,
                  iconColor: _isDemo ? tc.muted : tc.pillErrTx,
                  onTap: () => _rejectLeaveRequest(
                      context, req, emp, isFromEmployee),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestMobileCard(Map<String, dynamic> item) {
    final emp = item['employee'];
    final req = item['request'];
    final empName = _sanitize(item['employeeName'] ?? '', maxLen: 80);
    final isFromEmployee = item['isFromEmployeeCollection'] ?? false;
    final source = item['source'] ?? 'admin';
    final dept =
    _sanitize(emp['department'] ?? emp['role'] ?? 'IT', maxLen: 60);

    final leaveTypeDisplay = _leaveTypeDisplay(req['leaveType'] ?? 'Others');
    final fromStr = _formatDate(req['dateFrom']);
    final toStr = _formatDate(req['dateTo']);
    final daysStr = (req['totalDays'] ?? req['days'] ?? 0).toString();

    final isFromEmployeeSource = source == 'employee';
    final sourceLabel = isFromEmployeeSource ? 'Self' : 'Admin';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tc.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: tc.orange.withValues(alpha: 0.15),
                child: Text(
                  _getInitials(empName),
                  style: TextStyle(
                      color: tc.orangeText,
                      fontSize: 12,
                      fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            empName.isEmpty ? 'Unknown Staff' : empName,
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: tc.text),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: isFromEmployeeSource
                                ? tc.pillGreenBg
                                : tc.pillBlueBg,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            sourceLabel,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: isFromEmployeeSource
                                  ? tc.pillGreenTx
                                  : tc.pillBlueTx,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dept,
                      style: TextStyle(fontSize: 11, color: tc.muted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: tc.surface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  leaveTypeDisplay,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: tc.text),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$daysStr day${daysStr != '1' ? 's' : ''}',
                style: TextStyle(
                    fontSize: 11,
                    color: tc.muted,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.calendar_today_outlined, size: 12, color: tc.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '$fromStr - $toStr',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: tc.text),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _rejectLeaveRequest(
                      context, req, emp, isFromEmployee),
                  icon: Icon(Icons.close, size: 14, color: _isDemo ? tc.muted : tc.pillErrTx),
                  label: Text(
                    'Reject',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _isDemo ? tc.muted : tc.pillErrTx),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                        color: (_isDemo ? tc.border : tc.pillErrTx).withValues(alpha: 0.3)),
                    backgroundColor: _isDemo ? tc.surface : tc.pillErrBg,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _approveLeaveRequest(
                      context, req, emp, isFromEmployee),
                  icon: Icon(Icons.check, size: 14, color: _isDemo ? tc.muted : Colors.white),
                  label: Text(
                    'Approve',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _isDemo ? tc.muted : Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isDemo ? tc.border : tc.green,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required Color bgColor,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 14, color: iconColor),
      ),
    );
  }

  Widget _recentActivityCard(List<Map<String, dynamic>> logs) {
    final displayLogs = logs.length > 10 ? logs.sublist(0, 10) : logs;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tc.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.business_center_rounded,
                  size: 16, color: tc.orange),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Recent Client Meetings',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: tc.text,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: tc.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Live',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: tc.orangeText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (displayLogs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.event_busy_rounded,
                        size: 32, color: tc.muted),
                    const SizedBox(height: 8),
                    Text(
                      'No client meeting records available.',
                      style: TextStyle(color: tc.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            )
          else
            Column(
              children: displayLogs.asMap().entries.map((entry) {
                final item = entry.value;
                final dt = _toDateTime(item['timestamp']);
                final timeStr =
                dt != null ? DateFormat('h:mm a').format(dt) : 'Just now';
                final dateStr =
                dt != null ? DateFormat('MMM d, yyyy').format(dt) : '';
                final status = (item['status'] ?? '').toString();
                final isApproved = status == 'approved';
                final isRejected = status == 'rejected';

                final statusColor = isRejected
                    ? tc.red
                    : isApproved
                    ? tc.green
                    : tc.orange;
                final statusLabel = isRejected
                    ? 'Rejected'
                    : isApproved
                    ? 'Approved'
                    : 'Pending';

                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: statusColor,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _sanitize(
                                      item['employee_name'] ?? 'Unknown',
                                      maxLen: 80,
                                    ),
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                        color: tc.text),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color:
                                    statusColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    statusLabel,
                                    style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: statusColor),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(timeStr,
                                    style: TextStyle(
                                        fontSize: 11, color: tc.muted)),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _sanitize(item['details'] ?? '', maxLen: 120),
                              style: TextStyle(
                                  fontSize: 12, color: tc.textMuted),
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (dateStr.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  dateStr,
                                  style: TextStyle(
                                      fontSize: 10, color: tc.muted),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _metricCard(
      String label,
      String value,
      IconData icon, {
        bool isOrange = false,
        String? subtitle,
      }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tc.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isOrange ? tc.orange : tc.surface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon,
                color: isOrange ? Colors.white : tc.textMuted, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: tc.muted,
                        letterSpacing: 0.5)),
                const SizedBox(height: 2),
                Text(value,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: tc.text),
                    overflow: TextOverflow.ellipsis),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                        fontSize: 10,
                        color: tc.muted,
                        fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(32),
    child: Column(
      children: [
        Icon(
          _hasActiveFilters
              ? Icons.filter_alt_off_rounded
              : Icons.data_usage_rounded,
          size: 32,
          color: tc.muted,
        ),
        const SizedBox(height: 8),
        Text(
          _streamError != null
              ? 'Stream error — please contact IT support.'
              : _hasActiveFilters
              ? 'No pending requests match your filters.'
              : _debugTotalDocs == 0
              ? 'No leave applications in database yet.'
              : 'No pending leave requests.',
          style: TextStyle(color: tc.muted, fontSize: 13),
          textAlign: TextAlign.center,
        ),
        if (_hasActiveFilters) ...[
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () {
              setState(() {
                _selectedDepartment = 'All Departments';
                _selectedLeaveType = 'All Types';
                _selectedDateRange = null;
              });
            },
            icon: Icon(Icons.clear_all_rounded,
                size: 14, color: tc.orange),
            label: Text(
              'Clear filters',
              style: TextStyle(
                color: tc.orange,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

class _SecurityGuard {
  final Map<String, DateTime> _lastCall = {};
  static const Duration _minInterval = Duration(seconds: 2);

  bool tryAcquire(String key) {
    final now = DateTime.now();
    final last = _lastCall[key];
    if (last != null && now.difference(last) < _minInterval) {
      return false;
    }
    _lastCall[key] = now;
    return true;
  }
}

class _PageBtn extends StatelessWidget {
  const _PageBtn();
  @override
  Widget build(BuildContext context) {
    final tc = AdminTheme.getColors(context);
    return Container(
      decoration: BoxDecoration(
        color: tc.card,
        shape: BoxShape.circle,
        border: Border.all(color: tc.border),
      ),
      child: Icon(Icons.chevron_left, size: 14, color: tc.textMuted),
    );
  }
}