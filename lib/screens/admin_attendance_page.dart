import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'admin_database.dart';
import 'admin_theme.dart';
<<<<<<< HEAD
import 'admin_dashboard.dart';
=======
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1

class AdminAttendancePage extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> logs;
  final Color accent;
  final String searchQuery;
  final VoidCallback onRefreshNeeded;
<<<<<<< HEAD
  final List<Map<String, dynamic>> locations;
=======
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1

  const AdminAttendancePage({
    super.key,
    required this.title,
    required this.logs,
    required this.accent,
    required this.searchQuery,
    required this.onRefreshNeeded,
<<<<<<< HEAD
    this.locations = const [],
  });

  // UI Colors
  static const Color _bg = Color(0xFFF8F9FA);
  static const Color _cardBorder = Color(0xFFEBEAE6);
  static const Color _orange = Color(0xFFFF7A00);
  static const Color _textDark = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);

  String _getInitials(String name) {
    List<String> parts = name.trim().split(' ');
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    } else if (parts.isNotEmpty && parts[0].isNotEmpty) {
      return parts[0][0].toUpperCase();
    }
    return 'EMP';
  }

  // Finds the location ping closest in time to the given log timestamp for
  // this employee, so the verification view can show a real lat/lng instead
  // of always "Not recorded". Tries a few common field-name variants since
  // the exact schema isn't guaranteed; returns null (never fabricates) if
  // nothing matches.
  Map<String, dynamic>? _matchLocation(String employeeId, String employeeEmail, dynamic ts) {
    if (locations.isEmpty) return null;
    final DateTime? logTime = ts is Timestamp ? ts.toDate() : (ts is DateTime ? ts : null);

    final candidates = locations.where((l) {
      final locEmpId = (l['employeeId'] ?? l['employee_id'] ?? l['userId'] ?? l['uid'] ?? '').toString();
      final locEmail = (l['email'] ?? '').toString().toLowerCase();
      if (employeeId.isNotEmpty && locEmpId == employeeId) return true;
      if (employeeEmail.isNotEmpty && locEmail == employeeEmail.toLowerCase()) return true;
      return false;
    }).toList();

    if (candidates.isEmpty) return null;
    if (logTime == null || candidates.length == 1) return candidates.first;

    candidates.sort((a, b) {
      final ta = a['timestamp'];
      final tb = b['timestamp'];
      final da = ta is Timestamp ? ta.toDate() : (ta is DateTime ? ta : null);
      final db = tb is Timestamp ? tb.toDate() : (tb is DateTime ? tb : null);
      if (da == null) return 1;
      if (db == null) return -1;
      return da.difference(logTime).abs().compareTo(db.difference(logTime).abs());
    });
    return candidates.first;
  }

  @override
  Widget build(BuildContext context) {
    // Real login/logout logs only — no sample/fallback data. If there are
    // no logs yet, the table below shows the proper empty state instead.
    final List<Map<String, dynamic>> sourceLogs = logs;

    return Scaffold(
      backgroundColor: _bg,
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: AdminDatabase.getEmployees(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: _orange));
          }

          final List<Map<String, dynamic>> actualEmployees = snapshot.data ?? [];

          final Map<String, Map<String, dynamic>> employeeMap = {};
          for (var emp in actualEmployees) {
            final emailKey = (emp['email'] ?? '').toString().toLowerCase();
            final nameKey = (emp['name'] ?? emp['employee_name'] ?? '').toString().toLowerCase();

            if (emailKey.isNotEmpty) employeeMap[emailKey] = emp;
            if (nameKey.isNotEmpty) employeeMap[nameKey] = emp;
          }

          List<Map<String, dynamic>> displayLogs = sourceLogs.map((log) {
            final logEmail = (log['email'] ?? '').toString().toLowerCase();
            final logName = (log['employee_name'] ?? log['name'] ?? '').toString().toLowerCase();

            final matchedEmployee = employeeMap[logEmail] ?? employeeMap[logName] ?? {};
            final employeeId = (log['employeeId'] ?? matchedEmployee['id'] ?? '').toString();
            final resolvedEmail = (matchedEmployee['email'] ?? log['email'] ?? 'No email').toString();

            final matchedLocation = _matchLocation(employeeId, resolvedEmail, log['timestamp']);

            return {
              'id': log['id'] ?? '',
              'employeeId': employeeId,
              'employee_name': matchedEmployee['name'] ?? log['employee_name'] ?? log['name'] ?? 'System User',
              'role': matchedEmployee['role'] ?? matchedEmployee['position'] ?? log['role'] ?? 'Employee',
              'email': resolvedEmail,
              'timestamp': log['timestamp'],
              'type': log['type'] ?? 'LOGIN',
              // ---- Real data for the verification detail view (no
              // fabrication — fields stay absent/null if truly not on
              // record, and AdminAttendanceVerificationPage already shows
              // "Not recorded" for anything missing). ----
              'department': matchedEmployee['department'],
              'photoUrl': matchedEmployee['photoPath'] ?? matchedEmployee['photoUrl'],
              'deviceInfo': log['device'] ?? log['deviceInfo'],
              if (matchedLocation != null) 'latitude': matchedLocation['latitude'],
              if (matchedLocation != null) 'longitude': matchedLocation['longitude'],
              if (matchedLocation != null)
                'locationName': matchedLocation['address'] ?? matchedLocation['locationName'] ?? matchedLocation['name'],
            };
          }).toList();

          final filtered = displayLogs.where((log) {
            final text = '${log['employee_name']} ${log['type']} ${log['email']} ${log['role']}';
            return text.toLowerCase().contains(searchQuery.toLowerCase());
          }).toList();

          return SingleChildScrollView(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. HEADER SECTION
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Attendance Logs',
                          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: _textDark),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Monitor real-time employee check-ins and check-outs across all departments.',
                          style: TextStyle(fontSize: 13, color: _muted),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Exporting logs to CSV...')),
                            );
                          },
                          icon: const Icon(Icons.download, size: 16),
                          label: const Text('Export CSV'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _textDark,
                            side: const BorderSide(color: Color(0xFFD1D5DB)),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: onRefreshNeeded,
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('Refresh Data'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _orange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            elevation: 0,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // 2. FILTER BAR CARD
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _cardBorder),
                  ),
                  child: Row(
                    children: [
                      Expanded(child: _buildFilterInput('DATE RANGE', 'mm/dd/yyyy', isInput: true)),
                      const SizedBox(width: 16),
                      Expanded(child: _buildFilterInput('EVENT TYPE', 'All Events')),
                      const SizedBox(width: 16),
                      Expanded(child: _buildFilterInput('DEPARTMENT', 'All Departments')),
                      const SizedBox(width: 16),
                      ElevatedButton(
                        onPressed: () {},
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE5E7EB),
                          foregroundColor: const Color(0xFF4B5563),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Apply Filters', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // 3. TABLE CARD
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _cardBorder),
                  ),
                  child: Column(
                    children: [
                      // Table Header
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        decoration: const BoxDecoration(
                          color: Color(0xFFF8FAFC),
                          border: Border(bottom: BorderSide(color: _cardBorder)),
                        ),
                        child: const Row(
                          children: [
                            Expanded(flex: 3, child: Text('EMPLOYEE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _muted))),
                            Expanded(flex: 3, child: Text('CONTACT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _muted))),
                            Expanded(flex: 2, child: Text('DATE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _muted))),
                            Expanded(flex: 2, child: Text('TIME', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _muted))),
                            Expanded(flex: 2, child: Text('EVENT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _muted))),
                            SizedBox(width: 50, child: Text('ACTIONS', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _muted))),
                          ],
                        ),
                      ),

                      // Table Body
                      if (filtered.isEmpty)
                        _emptyState()
                      else
                        ...filtered.map((log) {
                          final ts = log['timestamp'];
                          final DateTime? dateObj = ts is Timestamp ? ts.toDate() : (ts is DateTime ? ts : null);

                          final dateStr = dateObj != null ? DateFormat('MMM d, y').format(dateObj) : '—';
                          final timeStr = dateObj != null ? DateFormat('hh:mm a').format(dateObj) : '—';

                          final name = log['employee_name'].toString();
                          final role = log['role'].toString();
                          final email = log['email'].toString();

                          final eventType = log['type'].toString().toUpperCase();
                          final isLogin = eventType.contains('IN') || eventType.contains('LOGIN');
                          final logId = (log['id'] ?? '').toString();

                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                            decoration: const BoxDecoration(
                              border: Border(bottom: BorderSide(color: _cardBorder)),
                            ),
                            child: Row(
                              children: [
                                // Empleyado
                                Expanded(
                                  flex: 3,
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 18,
                                        backgroundColor: const Color(0xFFFFEDD5),
                                        child: Text(
                                          _getInitials(name),
                                          style: const TextStyle(color: Color(0xFFEA580C), fontSize: 12, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _textDark), overflow: TextOverflow.ellipsis),
                                            Text(role, style: const TextStyle(fontSize: 11, color: _muted), overflow: TextOverflow.ellipsis),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // Contact / Email
                                Expanded(
                                  flex: 3,
                                  child: Text(email, style: const TextStyle(fontSize: 13, color: Color(0xFF374151)), overflow: TextOverflow.ellipsis),
                                ),

                                // Petsa
                                Expanded(
                                  flex: 2,
                                  child: Text(dateStr, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF374151))),
                                ),

                                // Oras
                                Expanded(
                                  flex: 2,
                                  child: Text(timeStr, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF374151))),
                                ),

                                // Event Status
                                Expanded(
                                  flex: 2,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isLogin ? const Color(0xFFDCFCE7) : const Color(0xFFDBEAFE),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        isLogin ? 'LOGIN' : 'LOGOUT',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          color: isLogin ? const Color(0xFF16A34A) : const Color(0xFF2563EB),
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),

                                // Actions — opens the REAL, shared verification view
                                // embedded inside AdminDashboard's own top bar/sidebar
                                // (AdminDashboardState.openAttendanceVerification),
                                // instead of pushing a separate chromeless route.
                                SizedBox(
                                  width: 50,
                                  child: PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert, color: _muted, size: 18),
                                    color: Colors.white,
                                    elevation: 4,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      side: const BorderSide(color: Color(0xFFE5E7EB)),
                                    ),
                                    onSelected: (value) async {
                                      if (value == 'verify') {
                                        final dashboardState = context.findAncestorStateOfType<AdminDashboardState>();
                                        if (dashboardState != null) {
                                          dashboardState.openAttendanceVerification(logId, log);
                                        } else {
                                          // Fallback: this page wasn't opened inside
                                          // AdminDashboard for some reason — warn
                                          // instead of silently pushing a chromeless
                                          // route again.
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('Could not find AdminDashboard to open verification in.')),
                                          );
                                        }
                                      } else if (value == 'delete' && logId.isNotEmpty) {
                                        final err = await AdminDatabase.deleteLog(logId);
                                        if (err == null) onRefreshNeeded();
                                      }
                                    },
                                    itemBuilder: (BuildContext context) => [
                                      const PopupMenuItem(
                                        value: 'verify',
                                        child: Text('View Verification', style: TextStyle(color: _textDark, fontSize: 12)),
                                      ),
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Text('Delete Record', style: TextStyle(color: Colors.red, fontSize: 12)),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),

                      // Table Pagination Footer
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        color: const Color(0xFFF8FAFC),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Showing 1 to ${filtered.length} of ${displayLogs.length} entries',
                              style: const TextStyle(fontSize: 12, color: _muted),
                            ),
                            Row(
                              children: [
                                _pageBtn(Icons.chevron_left, false),
                                _pageNumberBtn('1', true),
                                _pageNumberBtn('2', false),
                                _pageBtn(Icons.chevron_right, false),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // 4. BOTTOM SYSTEM CARDS
                LayoutBuilder(
                  builder: (context, constraints) {
                    bool isWide = constraints.maxWidth > 750;
                    return isWide
                        ? Row(
                      children: [
                        Expanded(flex: 2, child: _biometricCard()),
                        const SizedBox(width: 20),
                        Expanded(flex: 1, child: _auditTrailCard()),
                      ],
                    )
                        : Column(
                      children: [
                        _biometricCard(),
                        const SizedBox(height: 20),
                        _auditTrailCard(),
                      ],
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFilterInput(String label, String hint, {bool isInput = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _muted, letterSpacing: 0.5),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(hint, style: const TextStyle(fontSize: 13, color: Color(0xFF374151))),
              Icon(isInput ? Icons.calendar_today : Icons.keyboard_arrow_down, size: 16, color: _muted),
            ],
          ),
        ),
      ],
    );
  }

  Widget _emptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(40),
      child: const Column(
        children: [
          Icon(Icons.history_toggle_off_rounded, size: 36, color: _muted),
          SizedBox(height: 8),
          Text('No attendance logs or login events found.', style: TextStyle(color: _muted, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _biometricCard() {
    return Container(
      height: 180,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.fingerprint, color: _orange, size: 32),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Real-time Biometric Integration', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              SizedBox(height: 6),
              Text(
                'Every login and logout is synchronized instantly with central biometric hardware, ensuring 100% accurate timekeeping records for payroll.',
                style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12, height: 1.4),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _auditTrailCard() {
    return Container(
      height: 180,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _orange,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, color: Colors.white, size: 32),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Secure Audit Trail', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
              SizedBox(height: 6),
              Text(
                'Detailed logs track not only timestamps but also specific device IDs and location data for total administrative transparency.',
                style: TextStyle(color: Color(0xFFFFEDD5), fontSize: 12, height: 1.4),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pageBtn(IconData icon, bool active) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 2),
    width: 28,
    height: 28,
    decoration: BoxDecoration(
      color: active ? _orange : Colors.white,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: active ? _orange : const Color(0xFFE5E7EB)),
    ),
    child: Icon(icon, size: 16, color: active ? Colors.white : _muted),
  );

  Widget _pageNumberBtn(String text, bool active) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 2),
    width: 28,
    height: 28,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: active ? _orange : Colors.white,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: active ? _orange : const Color(0xFFE5E7EB)),
    ),
    child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: active ? Colors.white : _textDark)),
=======
  });

  @override
  Widget build(BuildContext context) {
    final filtered = logs.where((l) {
      final name = '${l['employee_name']} ${l['type']} ${l['email']}';
      return name.toLowerCase().contains(searchQuery.toLowerCase());
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AdminTheme.s4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AdminTheme.text, letterSpacing: -0.3)),
        const SizedBox(height: AdminTheme.s4),
        if (filtered.isEmpty) _emptyState() else ...filtered.map((log) {
          final ts = log['timestamp'];
          final time = ts is Timestamp ? DateFormat('MMM d, y h:mm a').format(ts.toDate()) : '—';
          final name = log['employee_name'] ?? log['name'] ?? 'System Sync';

          return Container(
            margin: const EdgeInsets.only(bottom: AdminTheme.s2),
            decoration: AdminTheme.card(),
            padding: const EdgeInsets.all(AdminTheme.s3),
            child: Row(children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(color: accent.withOpacity(0.1), borderRadius: BorderRadius.circular(AdminTheme.radius)),
                child: Icon(Icons.history_toggle_off_rounded, color: accent, size: 20),
              ),
              const SizedBox(width: AdminTheme.s3),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name.toString(), style: const TextStyle(color: AdminTheme.text, fontSize: 13, fontWeight: FontWeight.w600)),
                  Text(time, style: const TextStyle(color: AdminTheme.muted, fontSize: 11)),
                ]),
              ),
              IconButton(icon: const Icon(Icons.delete_outline_rounded, color: AdminTheme.red, size: 18), onPressed: () async {
                final err = await AdminDatabase.deleteLog((log['id'] ?? '').toString());
                if (err == null) {
                  onRefreshNeeded();
                }
              }),
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
      Text('No transaction logs written inside this module.', style: TextStyle(color: AdminTheme.muted, fontSize: AdminTheme.textBase)),
    ]),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
  );
}