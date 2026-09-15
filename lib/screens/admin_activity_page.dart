// lib/screens/admin_activity_page.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'admin_theme.dart';
import 'admin_create_leave_request_page.dart';
import '../services/employee_notification_service.dart';

class AdminActivityPage extends StatefulWidget {
  final List<Map<String, dynamic>> employees;
  final Map<String, List<Map<String, dynamic>>> userLogs;
  final String searchQuery;
  final List<Map<String, dynamic>> loginLogs;
  final VoidCallback? onCreateLeaveRequest;

  const AdminActivityPage({
    super.key,
    required this.employees,
    required this.userLogs,
    required this.searchQuery,
    this.loginLogs = const [],
    this.onCreateLeaveRequest,
  });

  @override
  State<AdminActivityPage> createState() => _AdminActivityPageState();
}

class _AdminActivityPageState extends State<AdminActivityPage> {
  AdminColors get tc => AdminTheme.getColors(context);

  StreamSubscription<QuerySnapshot>? _leaveSub;
  List<Map<String, dynamic>> _pendingLeaveApplications = [];
  bool _loadingApplications = true;
  String? _streamError;

  int _debugTotalDocs = 0;
  int _debugPendingCount = 0;
  final List<String> _debugStatuses = [];

  @override
  void initState() {
    super.initState();
    _listenToPendingLeaves();
  }

  @override
  void dispose() {
    _leaveSub?.cancel();
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
        for (final doc in snapshot.docs) {
          final data = doc.data();
          statuses.add(
              '${doc.id} → status="${data['status'] ?? '(missing)'}" | '
                  'name="${data['employeeName'] ?? '(no name)'}"');
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
        if (!mounted) return;
        setState(() {
          _loadingApplications = false;
          _streamError = e.toString();
        });
      },
    );
  }

  Future<void> _approveLeaveRequest(
      BuildContext context,
      Map<String, dynamic> request,
      Map<String, dynamic> employee,
      bool isFromEmployeeCollection,
      ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: tc.card,
        title: Text('Approve Leave Request', style: TextStyle(color: tc.text)),
        content: Text('Approve leave request for ${_empName(employee)}?',
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

    try {
      if (isFromEmployeeCollection) {
        await FirebaseFirestore.instance
            .collection('leave_applications')
            .doc(request['id'])
            .update({
          'status': 'approved',
          'approvedAt': FieldValue.serverTimestamp(),
          'reviewedBy': 'admin',
        });
      } else {
        final empId = employee['id'];
        final leaveRequests = (employee['leaveRequests'] as List?) ?? [];
        final updatedRequests = leaveRequests.map((req) {
          if (req['id'] == request['id']) {
            return {...req, 'status': 'approved'};
          }
          return req;
        }).toList();
        await FirebaseFirestore.instance
            .collection('employees')
            .doc(empId.toString())
            .update({'leaveRequests': updatedRequests});
      }

      if (!mounted) return;

      // ✅ AUTO-NOTIFY EMPLOYEE — LEAVE APPROVED
      try {
        final empId = (request['employeeId'] ??
            employee['id'] ??
            employee['employeeId'] ??
            '')
            .toString();
        final leaveType = _leaveTypeDisplay(request['leaveType'] ?? 'Leave');
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
          debugPrint('✅ [ActivityPage] Employee notified of approval');
        }
      } catch (e) {
        debugPrint('⚠️ [ActivityPage] Approval notification failed: $e');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: const Text('Leave request approved!'),
            backgroundColor: tc.green),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: tc.red),
      );
    }
  }

  Future<void> _rejectLeaveRequest(
      BuildContext context,
      Map<String, dynamic> request,
      Map<String, dynamic> employee,
      bool isFromEmployeeCollection,
      ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: tc.card,
        title: Text('Reject Leave Request', style: TextStyle(color: tc.text)),
        content: Text('Reject leave request for ${_empName(employee)}?',
            style: TextStyle(color: tc.text)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: TextStyle(color: tc.muted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: tc.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      if (isFromEmployeeCollection) {
        await FirebaseFirestore.instance
            .collection('leave_applications')
            .doc(request['id'])
            .update({
          'status': 'rejected',
          'rejectedAt': FieldValue.serverTimestamp(),
          'reviewedBy': 'admin',
        });
      } else {
        final empId = employee['id'];
        final leaveRequests = (employee['leaveRequests'] as List?) ?? [];
        final updatedRequests = leaveRequests.map((req) {
          if (req['id'] == request['id']) {
            return {...req, 'status': 'rejected'};
          }
          return req;
        }).toList();
        await FirebaseFirestore.instance
            .collection('employees')
            .doc(empId.toString())
            .update({'leaveRequests': updatedRequests});
      }

      if (!mounted) return;

      // ✅ AUTO-NOTIFY EMPLOYEE — LEAVE REJECTED
      try {
        final empId = (request['employeeId'] ??
            employee['id'] ??
            employee['employeeId'] ??
            '')
            .toString();
        final leaveType = _leaveTypeDisplay(request['leaveType'] ?? 'Leave');
        final start = _formatDate(request['dateFrom'] ?? request['startDate']);
        final end = _formatDate(request['dateTo'] ?? request['endDate']);

        if (empId.isNotEmpty) {
          await EmployeeNotificationService.instance.send(
            type: 'reminder',
            title: '❌ Leave Rejected',
            message:
            'Hindi na-approve ang iyong $leaveType request ($start – $end). Makipag-ugnayan sa HR.',
            employeeId: empId,
            priority: 'high',
          );
          debugPrint('✅ [ActivityPage] Employee notified of rejection');
        }
      } catch (e) {
        debugPrint('⚠️ [ActivityPage] Rejection notification failed: $e');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: const Text('Leave request rejected.'),
            backgroundColor: tc.orange),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: tc.red),
      );
    }
  }

  // ══════════════════════════════════════════════════════════════
  // HELPERS
  // ══════════════════════════════════════════════════════════════
  String _getInitials(String name) {
    final parts = name.trim().split(' ');
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
      return name.toString().trim();
    }
    final first = (employee['firstName'] ?? '').toString().trim();
    final last = (employee['lastName'] ?? '').toString().trim();
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
    return types[code] ?? code;
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
    if (dt == null) return 'N/A';
    return DateFormat('MMM d, yyyy').format(dt);
  }

  Map<String, dynamic> _normalizeAppDoc(Map<String, dynamic> app) {
    return {
      'id': app['id'],
      'employeeName': app['employeeName'] ?? '',
      'position': app['position'] ?? '',
      'department': app['department'] ?? '',
      'dateFrom': _toDateTime(app['startDate']),
      'dateTo': _toDateTime(app['endDate']),
      'totalDays': app['days'] ?? 0,
      'totalHours': app['hours'] ?? 0,
      'leaveType': app['leaveType'] ?? 'Others',
      'reason': app['reason'] ?? '',
      'status': app['status'] ?? 'pending',
      'createdAt': _toDateTime(app['createdAt']) ?? DateTime.now(),
    };
  }

  // ══════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final allPendingRequests = <Map<String, dynamic>>[];

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
          'name': app['employeeName'] ?? 'Unknown Employee',
          'department': 'N/A',
        },
      );
      allPendingRequests.add({
        'employee': employee,
        'request': _normalizeAppDoc(app),
        'employeeName': app['employeeName'] ?? _empName(employee),
        'isFromEmployeeCollection': true,
        'source': 'employee',
      });
    }

    allPendingRequests.sort((a, b) {
      final dtA = _toDateTime(a['request']['createdAt']) ?? DateTime(1970);
      final dtB = _toDateTime(b['request']['createdAt']) ?? DateTime(1970);
      return dtB.compareTo(dtA);
    });

    final q = widget.searchQuery.toLowerCase();
    final filteredRequests = q.isEmpty
        ? allPendingRequests
        : allPendingRequests
        .where((i) => i['employeeName'].toString().toLowerCase().contains(q))
        .toList();

    final actualPendingLeaveCount = allPendingRequests.length;

    int actualOnLeaveTodayCount = 0;
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

    final totalEmployees = widget.employees.length;
    final attendanceRate = totalEmployees > 0
        ? ((totalEmployees - actualOnLeaveTodayCount) / totalEmployees) * 100
        : 0.0;

    final allTimelineLogs = <Map<String, dynamic>>[];
    for (var emp in widget.employees) {
      final id = (emp['id'] ?? '').toString();
      final empName = _empName(emp);
      final logs = widget.userLogs[id] ?? [];
      for (var l in logs) {
        allTimelineLogs.add({
          'employee_name': empName.isEmpty ? 'System User' : empName,
          'type': l['type'] ?? 'interaction',
          'timestamp': l['timestamp'],
          'details': l['details'] ?? l['description'] ?? 'Activity logged',
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
                _buildPageHeader(),
                const SizedBox(height: 24),
                _buildMetricGrid(
                  actualPendingLeaveCount,
                  actualOnLeaveTodayCount,
                  attendanceRate,
                ),
                const SizedBox(height: 20),
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
          onPressed: () {},
          icon: const Icon(Icons.filter_list, size: 16),
          label: const Text('Filters'),
          style: OutlinedButton.styleFrom(
            foregroundColor: tc.text,
            side: BorderSide(color: tc.border),
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
      int pendingCount, int onLeaveCount, double attendanceRate) {
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
        if (!_loadingApplications && _streamError == null)
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: tc.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('All Departments',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: tc.text)),
          const SizedBox(width: 4),
          Icon(Icons.keyboard_arrow_down, size: 14, color: tc.muted),
        ],
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
              'Showing $shown of $total pending requests',
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
    final empName = item['employeeName'];
    final isFromEmployee = item['isFromEmployeeCollection'] ?? false;
    final source = item['source'] ?? 'admin';
    final dept = emp['department'] ?? emp['role'] ?? 'IT';

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
                        dept.toString(),
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
                  bgColor: tc.pillWarnBg,
                  iconColor: tc.pillWarnTx,
                  onTap: () => _approveLeaveRequest(
                      context, req, emp, isFromEmployee),
                ),
                const SizedBox(width: 6),
                _actionButton(
                  icon: Icons.close,
                  bgColor: tc.pillErrBg,
                  iconColor: tc.pillErrTx,
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
    final empName = item['employeeName'];
    final isFromEmployee = item['isFromEmployeeCollection'] ?? false;
    final source = item['source'] ?? 'admin';
    final dept = emp['department'] ?? emp['role'] ?? 'IT';

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
                      dept.toString(),
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
                  icon: Icon(Icons.close, size: 14, color: tc.pillErrTx),
                  label: Text(
                    'Reject',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: tc.pillErrTx),
                  ),
                  style: OutlinedButton.styleFrom(
                    side:
                    BorderSide(color: tc.pillErrTx.withValues(alpha: 0.3)),
                    backgroundColor: tc.pillErrBg,
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
                  icon:
                  const Icon(Icons.check, size: 14, color: Colors.white),
                  label: const Text(
                    'Approve',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: tc.green,
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
    final displayLogs = logs.length > 5 ? logs.sublist(0, 5) : logs;

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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Flexible(
                child: Text(
                  'Recent Activity',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: tc.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10)),
                child: Text('Live',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: tc.orangeText)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (displayLogs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('No activity records available.',
                    style: TextStyle(color: tc.muted, fontSize: 12)),
              ),
            )
          else
            Column(
              children: displayLogs.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;
                final dt = _toDateTime(item['timestamp']);
                final timeStr =
                dt != null ? DateFormat('h:mm a').format(dt) : 'Just now';
                final typeStr = item['type'].toString().toLowerCase();
                final isError = typeStr.contains('fail') ||
                    typeStr.contains('mismatch') ||
                    typeStr.contains('error');

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
                          color: isError
                              ? tc.red
                              : (index == 0 ? tc.orange : tc.muted),
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
                                    item['employee_name'],
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                        color: tc.text),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(timeStr,
                                    style: TextStyle(
                                        fontSize: 11, color: tc.muted)),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${item['type'].toString().toUpperCase()} - ${item['details']}',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: isError ? tc.red : tc.textMuted),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {},
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: tc.border),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: Text('View Full Activity Log',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: tc.text)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricCard(String label, String value, IconData icon,
      {bool isOrange = false}) {
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
        Icon(Icons.data_usage_rounded, size: 32, color: tc.muted),
        const SizedBox(height: 8),
        Text(
          _streamError != null
              ? 'Stream error — check terminal for details.'
              : _debugTotalDocs == 0
              ? 'No leave applications in database yet.'
              : 'No pending leave requests.',
          style: TextStyle(color: tc.muted, fontSize: 13),
          textAlign: TextAlign.center,
        ),
        if (_debugStatuses.isNotEmpty && _debugPendingCount == 0) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: tc.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: tc.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Found ${_debugStatuses.length} doc(s) but none are "pending":',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: tc.muted),
                ),
                const SizedBox(height: 6),
                ..._debugStatuses.take(3).map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    s.length > 80 ? '${s.substring(0, 80)}...' : s,
                    style: TextStyle(fontSize: 9, color: tc.muted),
                  ),
                )),
              ],
            ),
          ),
        ],
      ],
    ),
  );
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