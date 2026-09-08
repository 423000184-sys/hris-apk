<<<<<<< HEAD
//lib/screens/admin_activity_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
=======
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'admin_theme.dart';
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1

class AdminActivityPage extends StatelessWidget {
  final List<Map<String, dynamic>> employees;
  final Map<String, List<Map<String, dynamic>>> userLogs;
  final String searchQuery;
<<<<<<< HEAD
  final List<Map<String, dynamic>> loginLogs;

  final VoidCallback? onCreateLeaveRequest;
=======
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1

  const AdminActivityPage({
    super.key,
    required this.employees,
    required this.userLogs,
    required this.searchQuery,
<<<<<<< HEAD
    this.loginLogs = const [],
    this.onCreateLeaveRequest,
  });

  String _getInitials(String name) {
    List<String> parts = name.trim().split(' ');
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    } else if (parts.isNotEmpty && parts[0].isNotEmpty) {
      return parts[0][0].toUpperCase();
    }
    return 'EMP';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    // 1. Filtered Employees para sa Search Query
    final filteredEmps = employees.where((e) {
      final name = '${e['firstName'] ?? ''} ${e['lastName'] ?? ''} ${e['name'] ?? ''}';
      return name.toLowerCase().contains(searchQuery.toLowerCase());
    }).toList();

    // 2. ACTUAL DYNAMIC COMPUTATION FOR METRICS

    // A. Actual Pending Leave Requests
    int actualPendingLeaveCount = 0;
    for (var emp in employees) {
      if (emp['leaveRequests'] is List) {
        final requests = emp['leaveRequests'] as List;
        actualPendingLeaveCount += requests.where((req) {
          final status = (req['status'] ?? '').toString().toLowerCase();
          return status == 'pending';
        }).length;
      } else {
        final status = (emp['leaveStatus'] ?? emp['status'] ?? '').toString().toLowerCase();
        if (status == 'pending' || status == 'pending leave') {
          actualPendingLeaveCount++;
        }
      }
    }

    // B. Actual On Leave Today
    int actualOnLeaveTodayCount = 0;
    for (var emp in employees) {
      final status = (emp['status'] ?? emp['workStatus'] ?? '').toString().toLowerCase();
      final bool isOnLeaveFlag = emp['isOnLeave'] == true;

      bool isLeaveToday = false;
      if (emp['leaveStartDate'] != null && emp['leaveEndDate'] != null) {
        DateTime? start = emp['leaveStartDate'] is Timestamp
            ? (emp['leaveStartDate'] as Timestamp).toDate()
            : DateTime.tryParse(emp['leaveStartDate'].toString());
        DateTime? end = emp['leaveEndDate'] is Timestamp
            ? (emp['leaveEndDate'] as Timestamp).toDate()
            : DateTime.tryParse(emp['leaveEndDate'].toString());

        if (start != null && end != null) {
          final todayPure = DateTime(now.year, now.month, now.day);
          final startPure = DateTime(start.year, start.month, start.day);
          final endPure = DateTime(end.year, end.month, end.day);
          if (todayPure.isAfter(startPure.subtract(const Duration(days: 1))) &&
              todayPure.isBefore(endPure.add(const Duration(days: 1)))) {
            isLeaveToday = true;
          }
        }
      }

      if (isOnLeaveFlag || status == 'on leave' || status == 'on_leave' || isLeaveToday) {
        actualOnLeaveTodayCount++;
      }
    }

    // C. Actual Total Attendance Percentage Calculation
    final totalEmployees = employees.length;
    double attendanceRate = totalEmployees > 0
        ? ((totalEmployees - actualOnLeaveTodayCount) / totalEmployees) * 100
        : 0.0;

    // 3. Consolidated Timeline Logs mula sa Actual Data
    List<Map<String, dynamic>> allTimelineLogs = [];
    for (var emp in employees) {
      final id = (emp['id'] ?? '').toString();
      final empName = emp['name'] ?? '${emp['firstName'] ?? ''} ${emp['lastName'] ?? ''}'.trim();
      final logs = userLogs[id] ?? [];
      for (var l in logs) {
        allTimelineLogs.add({
          'employee_name': empName.isEmpty ? 'System User' : empName,
          'type': l['type'] ?? 'interaction',
          'timestamp': l['timestamp'],
          'details': l['details'] ?? l['description'] ?? 'Activity logged',
        });
      }
    }

    // Sort timeline logs by newest timestamp
    allTimelineLogs.sort((a, b) {
      final tsA = a['timestamp'];
      final tsB = b['timestamp'];
      final dtA = tsA is Timestamp ? tsA.toDate() : (tsA is DateTime ? tsA : DateTime(1970));
      final dtB = tsB is Timestamp ? tsB.toDate() : (tsB is DateTime ? tsB : DateTime(1970));
      return dtB.compareTo(dtA);
    });

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. HEADER SECTION
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Activity & Leave Management',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF111827)),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Oversee biometric logs and process leave applications in real-time.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                  ),
                ],
              ),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: onCreateLeaveRequest,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Create Leave Request'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF7A00),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.filter_list, size: 16),
                    label: const Text('Filters'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF374151),
                      side: const BorderSide(color: Color(0xFFD1D5DB)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 2. METRIC CARDS (DYNAMIC / ACTUAL VALUES)
          Row(
            children: [
              Expanded(
                child: _metricCard(
                  'PENDING LEAVE',
                  '$actualPendingLeaveCount ${actualPendingLeaveCount == 1 ? 'Request' : 'Requests'}',
                  Icons.assignment_outlined,
                  isOrange: true,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _metricCard(
                  'ON LEAVE TODAY',
                  '$actualOnLeaveTodayCount Staff',
                  Icons.person_off_outlined,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _metricCard(
                  'TOTAL ATTENDANCE',
                  '${attendanceRate.toStringAsFixed(1)}%',
                  Icons.groups_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // 3. RECENT ACTIVITY CARD (FULL WIDTH)
          _recentActivityCard(allTimelineLogs),
          const SizedBox(height: 20),

          // 4. PENDING LEAVE REQUESTS TABLE
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Pending Leave Requests',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF111827)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: const [
                            Text('All Departments', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
                            SizedBox(width: 4),
                            Icon(Icons.keyboard_arrow_down, size: 14, color: Color(0xFF6B7280)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Table Titles
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  color: const Color(0xFFF8FAFC),
                  child: Row(
                    children: const [
                      Expanded(flex: 3, child: Text('EMPLOYEE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF6B7280)))),
                      Expanded(flex: 2, child: Text('TYPE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF6B7280)))),
                      Expanded(flex: 2, child: Text('DATES', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF6B7280)))),
                      SizedBox(width: 80, child: Text('ACTIONS', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF6B7280)))),
                    ],
                  ),
                ),

                // Table Rows
                if (filteredEmps.isEmpty)
                  _emptyState()
                else
                  ...filteredEmps.map((emp) {
                    final empName = emp['name'] ?? '${emp['firstName'] ?? ''} ${emp['lastName'] ?? ''}'.trim();
                    final dept = emp['department'] ?? emp['role'] ?? 'IT';
                    final leaveType = emp['leaveType'] ?? 'Annual Leave';
                    final leaveDates = emp['leaveDates'] ?? 'Oct 24 - Oct 28';
                    final duration = emp['duration'] ?? '5 Days';

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: const Color(0xFFFFEDD5),
                                  child: Text(
                                    _getInitials(empName),
                                    style: const TextStyle(color: Color(0xFFEA580C), fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        empName.isEmpty ? 'Unknown Staff' : empName,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF111827)),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(dept, style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)), overflow: TextOverflow.ellipsis),
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
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF3F4F6),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  leaveType,
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF374151)),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(leaveDates, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF111827))),
                                Text(duration, style: const TextStyle(fontSize: 10, color: Color(0xFF6B7280))),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: 80,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Container(
                                  width: 26,
                                  height: 26,
                                  decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(6)),
                                  child: const Icon(Icons.check, size: 14, color: Color(0xFFD97706)),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  width: 26,
                                  height: 26,
                                  decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(6)),
                                  child: const Icon(Icons.close, size: 14, color: Color(0xFFDC2626)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),

                // Table Footer
                Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Showing ${filteredEmps.length} of ${filteredEmps.length} pending requests', style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
                      Row(
                        children: [
                          _pageBtn(Icons.chevron_left),
                          const SizedBox(width: 4),
                          _pageBtn(Icons.chevron_right),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- RECENT ACTIVITY TIMELINE CARD ---
  Widget _recentActivityCard(List<Map<String, dynamic>> logs) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Recent Activity', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF111827))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFFFFEDD5), borderRadius: BorderRadius.circular(10)),
                child: const Text('Live', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFC2410C))),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (logs.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('No activity records available.', style: TextStyle(color: Color(0xFF6B7280), fontSize: 12)),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: logs.length > 5 ? 5 : logs.length,
              itemBuilder: (context, index) {
                final item = logs[index];
                final ts = item['timestamp'];
                final DateTime? dateObj = ts is Timestamp ? ts.toDate() : (ts is DateTime ? ts : null);
                final timeStr = dateObj != null ? DateFormat('h:mm a').format(dateObj) : 'Just now';

                final typeStr = item['type'].toString().toLowerCase();
                final isError = typeStr.contains('fail') || typeStr.contains('mismatch') || typeStr.contains('error');

                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            margin: const EdgeInsets.only(top: 4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isError ? Colors.red : (index == 0 ? const Color(0xFFFF7A00) : const Color(0xFFD1D5DB)),
                            ),
                          ),
                          if (index != (logs.length > 5 ? 4 : logs.length - 1))
                            Expanded(
                              child: Container(
                                width: 2,
                                color: const Color(0xFFF3F4F6),
                                margin: const EdgeInsets.symmetric(vertical: 4),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(item['employee_name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF111827))),
                                  Text(timeStr, style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${item['type'].toString().toUpperCase()} - ${item['details']}',
                                style: TextStyle(fontSize: 12, color: isError ? Colors.red : const Color(0xFF4B5563)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {},
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFE5E7EB)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('View Full Activity Log', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF374151))),
            ),
          ),
        ],
      ),
    );
  }

  // --- METRIC CARD WIDGET ---
  Widget _metricCard(String label, String value, IconData icon, {bool isOrange = false}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isOrange ? const Color(0xFFFF7A00) : const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: isOrange ? Colors.white : const Color(0xFF4B5563), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF6B7280), letterSpacing: 0.5)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF111827)), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pageBtn(IconData icon) => Container(
    width: 24,
    height: 24,
    decoration: BoxDecoration(
      color: Colors.white,
      shape: BoxShape.circle,
      border: Border.all(color: const Color(0xFFE5E7EB)),
    ),
    child: Icon(icon, size: 14, color: const Color(0xFF4B5563)),
  );

  Widget _emptyState() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(32),
    child: Column(
      children: const [
        Icon(Icons.data_usage_rounded, size: 32, color: Color(0xFF6B7280)),
        SizedBox(height: 8),
        Text('No tracking parameters match.', style: TextStyle(color: Color(0xFF6B7280), fontSize: 13)),
      ],
    ),
=======
  });

  @override
  Widget build(BuildContext context) {
    final filteredEmps = employees.where((e) {
      final name = '${e['firstName']} ${e['lastName']} ${e['name']}';
      return name.toLowerCase().contains(searchQuery.toLowerCase());
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AdminTheme.s4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('User Activity Auditing', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AdminTheme.text, letterSpacing: -0.3)),
        const SizedBox(height: AdminTheme.s4),
        if (filteredEmps.isEmpty) _emptyState() else ...filteredEmps.map((emp) {
          final id = (emp['id'] ?? '').toString();
          final logs = userLogs[id] ?? [];
          return _activityCard(emp, logs);
        }),
      ]),
    );
  }

  Widget _activityCard(Map<String, dynamic> emp, List<Map<String, dynamic>> logs) {
    final name = emp['name'] ?? '${emp['firstName'] ?? ''} ${emp['lastName'] ?? ''}'.trim();
    return Container(
      margin: const EdgeInsets.only(bottom: AdminTheme.s3),
      decoration: AdminTheme.card(),
      padding: const EdgeInsets.all(AdminTheme.s4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(name, style: const TextStyle(color: AdminTheme.text, fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: AdminTheme.s2),
        if (logs.isEmpty) const Text('No recent interaction records logged.', style: TextStyle(color: AdminTheme.muted, fontSize: 11)) else ...logs.take(4).map((l) {
          final ts = l['timestamp'];
          final time = ts is Timestamp ? DateFormat('MMM d, h:mm a').format(ts.toDate()) : '—';
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              const Icon(Icons.radio_button_checked_rounded, size: 10, color: AdminTheme.orange),
              const SizedBox(width: 8),
              Text((l['type'] ?? 'interaction').toString().toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
              const Spacer(),
              Text(time, style: const TextStyle(color: AdminTheme.muted, fontSize: 11)),
            ]),
          );
        }),
      ]),
    );
  }

  Widget _emptyState() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(AdminTheme.s6),
    decoration: AdminTheme.card(),
    child: const Column(children: [
      Icon(Icons.data_usage_rounded, size: 32, color: AdminTheme.muted),
      SizedBox(height: 8),
      Text('No tracking parameters match.', style: TextStyle(color: AdminTheme.muted, fontSize: AdminTheme.textBase)),
    ]),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
  );
}