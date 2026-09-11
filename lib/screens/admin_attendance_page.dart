// lib/screens/admin_attendance_page.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'admin_theme.dart';
import 'admin_dashboard.dart';
import '../widgets/bootstrap_grid.dart';

class AdminAttendancePage extends StatefulWidget {
  final String title;
  final List<Map<String, dynamic>> logs;
  final Color accent;
  final String searchQuery;
  final VoidCallback onRefreshNeeded;
  final List<Map<String, dynamic>> locations;

  const AdminAttendancePage({
    super.key,
    required this.title,
    required this.logs,
    required this.accent,
    required this.searchQuery,
    required this.onRefreshNeeded,
    required this.locations,
  });

  @override
  State<AdminAttendancePage> createState() => _AdminAttendancePageState();
}

class _AdminAttendancePageState extends State<AdminAttendancePage> {
  // ══════════════════════════════════════════════════════════════
  // THEME ACCESSOR
  // ══════════════════════════════════════════════════════════════
  AdminColors get tc => AdminTheme.getColors(context);

  // Filter states
  String _selectedEventType = 'All Events';
  String _selectedDepartment = 'All Departments';
  DateTimeRange? _selectedDateRange;
  int _currentPage = 1;
  final int _rowsPerPage = 5;

  final List<String> _eventTypes = ['All Events', 'IN', 'OUT'];

  List<String> get _departments {
    final depts = widget.logs
        .map((log) => log['department']?.toString() ?? '')
        .where((d) => d.isNotEmpty)
        .toSet()
        .toList();
    return ['All Departments', ...depts];
  }

  List<Map<String, dynamic>> get _filteredLogs {
    var filtered = widget.logs.where((log) {
      final name = (log['employee_name'] ?? '').toString().toLowerCase();
      final id = (log['employee_id'] ?? '').toString().toLowerCase();
      final email = (log['email'] ?? '').toString().toLowerCase();
      final query = widget.searchQuery.toLowerCase();
      return name.contains(query) ||
          id.contains(query) ||
          email.contains(query);
    }).toList();

    if (_selectedEventType != 'All Events') {
      filtered = filtered.where((log) {
        final type = (log['type'] ?? 'IN').toString().toUpperCase();
        return type == _selectedEventType;
      }).toList();
    }

    if (_selectedDepartment != 'All Departments') {
      filtered = filtered.where((log) {
        final dept = (log['department'] ?? '').toString();
        return dept == _selectedDepartment;
      }).toList();
    }

    if (_selectedDateRange != null) {
      filtered = filtered.where((log) {
        final ts = log['timestamp'];
        if (ts == null) return false;
        DateTime dt;
        if (ts is Timestamp) {
          dt = ts.toDate();
        } else if (ts is DateTime) {
          dt = ts;
        } else {
          return false;
        }
        return dt.isAfter(
            _selectedDateRange!.start.subtract(const Duration(days: 1))) &&
            dt.isBefore(
                _selectedDateRange!.end.add(const Duration(days: 1)));
      }).toList();
    }

    filtered.sort((a, b) {
      final tsA = a['timestamp'];
      final tsB = b['timestamp'];
      if (tsA == null && tsB == null) return 0;
      if (tsA == null) return 1;
      if (tsB == null) return -1;

      DateTime dtA, dtB;
      if (tsA is Timestamp) {
        dtA = tsA.toDate();
      } else if (tsA is DateTime) {
        dtA = tsA;
      } else {
        return 0;
      }

      if (tsB is Timestamp) {
        dtB = tsB.toDate();
      } else if (tsB is DateTime) {
        dtB = tsB;
      } else {
        return 0;
      }

      return dtB.compareTo(dtA);
    });

    return filtered;
  }

  List<Map<String, dynamic>> get _paginatedLogs {
    final start = (_currentPage - 1) * _rowsPerPage;
    final end = start + _rowsPerPage;
    if (start >= _filteredLogs.length) return [];
    return _filteredLogs.sublist(start, end.clamp(0, _filteredLogs.length));
  }

  int get _totalPages => (_filteredLogs.length / _rowsPerPage).ceil();

  String _fmtTime(dynamic ts) {
    if (ts == null) return '--:--';
    DateTime? dt;
    if (ts is Timestamp) {
      dt = ts.toDate();
    } else if (ts is DateTime) {
      dt = ts;
    }
    if (dt == null) return '--:--';
    return DateFormat('hh:mm a').format(dt);
  }

  String _fmtDate(dynamic ts) {
    if (ts == null) return '—';
    DateTime? dt;
    if (ts is Timestamp) {
      dt = ts.toDate();
    } else if (ts is DateTime) {
      dt = ts;
    }
    if (dt == null) return '—';
    return DateFormat('MMM d, yyyy').format(dt);
  }

  Future<void> _pickDateRange() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _selectedDateRange,
      builder: (ctx, child) => Theme(
        data: AdminTheme.themeData(isDark),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _selectedDateRange = picked);
    }
  }

  void _openVerification(Map<String, dynamic> log) {
    final dashboard = context.findAncestorStateOfType<AdminDashboardState>();
    if (dashboard != null) {
      dashboard.openAttendanceVerification(
        log['id'] ?? '',
        log,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: tc.background,
      child: SingleChildScrollView(
        child: BsContainer(
          maxWidth: 1600,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPageHeader(),
              const SizedBox(height: 24),
              _buildFilterBar(),
              const SizedBox(height: 24),
              _buildTable(),
              const SizedBox(height: 24),
              _buildBottomCards(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // HEADER
  // ══════════════════════════════════════════════════════════════
  Widget _buildPageHeader() {
    return LayoutBuilder(
      builder: (_, c) {
        final r = BsResponsive(c.maxWidth);
        final narrow = !r.up(BsSize.md);

        final title = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: TextStyle(
                fontSize: r.responsive<double>(
                  xs: 22, sm: 26, md: 28, lg: 32,
                ),
                fontWeight: FontWeight.w700,
                color: tc.text,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Monitor real-time employee check-ins and check-outs across all departments.',
              style: TextStyle(
                fontSize: r.responsive<double>(xs: 13, md: 16),
                color: tc.textMuted,
              ),
            ),
          ],
        );

        final refreshBtn = _buildActionButton(
          icon: Icons.refresh_rounded,
          label: 'Refresh',
          onPressed: widget.onRefreshNeeded,
          bgColor: tc.card,
          textColor: tc.text,
          borderColor: tc.border,
        );

        final exportBtn = _buildActionButton(
          icon: Icons.download_rounded,
          label: 'Export Logs',
          onPressed: () {},
          bgColor: tc.orange,
          textColor: tc.isDark ? tc.onOrange : Colors.white,
          borderColor: tc.orange,
        );

        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              title,
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: refreshBtn),
                  const SizedBox(width: 12),
                  Expanded(child: exportBtn),
                ],
              ),
            ],
          );
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: title),
            Row(
              children: [
                refreshBtn,
                const SizedBox(width: 12),
                exportBtn,
              ],
            ),
          ],
        );
      },
    );
  }

  // ══════════════════════════════════════════════════════════════
  // FILTER BAR
  // ══════════════════════════════════════════════════════════════
  Widget _buildFilterBar() {
    return LayoutBuilder(
      builder: (_, c) {
        final r = BsResponsive(c.maxWidth);
        final narrow = !r.up(BsSize.lg);

        final dateField = _buildFilterField(
          label: 'DATE RANGE',
          child: InkWell(
            onTap: _pickDateRange,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: tc.card,
                border: Border.all(color: tc.border),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      _selectedDateRange == null
                          ? 'mm / dd / yyyy'
                          : '${DateFormat('MM/dd/yyyy').format(_selectedDateRange!.start)} - ${DateFormat('MM/dd/yyyy').format(_selectedDateRange!.end)}',
                      style: TextStyle(
                        color: tc.text,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(Icons.calendar_today, size: 16, color: tc.muted),
                ],
              ),
            ),
          ),
        );

        final eventField = _buildFilterField(
          label: 'EVENT TYPE',
          child: _buildDropdown<String>(
            value: _selectedEventType,
            items: _eventTypes,
            onChanged: (val) =>
                setState(() => _selectedEventType = val!),
          ),
        );

        final deptField = _buildFilterField(
          label: 'DEPARTMENT',
          child: _buildDropdown<String>(
            value: _selectedDepartment,
            items: _departments,
            onChanged: (val) =>
                setState(() => _selectedDepartment = val!),
          ),
        );

        final applyBtn = SizedBox(
          height: 48,
          child: ElevatedButton(
            onPressed: () => setState(() {}),
            style: ElevatedButton.styleFrom(
              backgroundColor: tc.surface,
              foregroundColor: tc.textMuted,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Apply Filters',
                style: TextStyle(fontSize: 14)),
          ),
        );

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: tc.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: tc.border),
          ),
          child: narrow
              ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              dateField,
              const SizedBox(height: 12),
              eventField,
              const SizedBox(height: 12),
              deptField,
              const SizedBox(height: 16),
              applyBtn,
            ],
          )
              : Row(
            children: [
              Expanded(flex: 2, child: dateField),
              const SizedBox(width: 16),
              Expanded(child: eventField),
              const SizedBox(width: 16),
              Expanded(child: deptField),
              const SizedBox(width: 16),
              applyBtn,
            ],
          ),
        );
      },
    );
  }

  Widget _buildDropdown<T>({
    required T value,
    required List<T> items,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      value: value,
      isExpanded: true,
      dropdownColor: tc.card,
      iconEnabledColor: tc.text,
      style: TextStyle(
        color: tc.text,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        filled: true,
        fillColor: tc.card,
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        isDense: true,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: tc.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: tc.orange, width: 1.4),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: tc.border),
        ),
      ),
      items: items
          .map((e) => DropdownMenuItem<T>(
        value: e,
        child: Text('$e', style: TextStyle(color: tc.text)),
      ))
          .toList(),
      onChanged: onChanged,
    );
  }

  // ══════════════════════════════════════════════════════════════
  // TABLE
  // ══════════════════════════════════════════════════════════════
  Widget _buildTable() {
    return LayoutBuilder(
      builder: (_, c) {
        final r = BsResponsive(c.maxWidth);
        final isMobile = !r.up(BsSize.md);

        return Container(
          decoration: BoxDecoration(
            color: tc.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: tc.border),
          ),
          child: Column(
            children: [
              if (!isMobile) _buildTableHeader(),
              if (_paginatedLogs.isEmpty)
                _buildEmptyState()
              else if (isMobile)
                ..._paginatedLogs.map((log) => _buildMobileCard(log))
              else
                ..._paginatedLogs.map((log) => _buildRow(log)),
              if (_paginatedLogs.isNotEmpty) _buildPagination(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: tc.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      child: Row(
        children: [
          _th('EMPLOYEE', flex: 2),
          _th('CONTACT', flex: 2),
          _th('DATE', flex: 1),
          _th('TIME', flex: 1),
          _th('EVENT', flex: 1),
          _th('ACTIONS', flex: 1, align: TextAlign.right),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(Icons.hourglass_empty, size: 64, color: tc.muted),
          const SizedBox(height: 16),
          Text(
            'No attendance records found',
            style: TextStyle(fontSize: 16, color: tc.muted),
          ),
        ],
      ),
    );
  }

  Widget _th(String label,
      {required int flex, TextAlign align = TextAlign.left}) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        textAlign: align,
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700, color: tc.textMuted),
      ),
    );
  }

  // ─── DESKTOP ROW ──────────────────────────────────────────
  Widget _buildRow(Map<String, dynamic> log) {
    final type = (log['type'] ?? 'IN').toString().toUpperCase();
    final isLogin = type == 'IN' || type == 'LOGIN';
    final name = (log['employee_name'] ?? 'Unknown Employee').toString();
    final email = (log['email'] ?? '').toString();
    final employeeId = (log['employee_id'] ?? '').toString();
    final dept = (log['department'] ?? '').toString();

    String initials = '?';
    if (name.isNotEmpty) {
      final parts = name.split(' ');
      if (parts.length >= 2) {
        initials = parts[0][0].toUpperCase() + parts[1][0].toUpperCase();
      } else {
        initials = name.substring(0, 1).toUpperCase();
      }
    }

    final displayEmail =
    email.isNotEmpty ? email : '$employeeId@company.com';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tc.border, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: tc.orange.withValues(alpha: 0.15),
                  child: Text(
                    initials,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: tc.orangeText,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: tc.text,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        dept.isNotEmpty ? dept : 'No Department',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: tc.textMuted,
                        ),
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
            child: Text(
              displayEmail,
              style: TextStyle(fontSize: 14, color: tc.text),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              _fmtDate(log['timestamp']),
              style: TextStyle(fontSize: 14, color: tc.text),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              _fmtTime(log['timestamp']),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: tc.text,
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: _buildEventPill(isLogin),
          ),
          Expanded(
            flex: 1,
            child: _buildActions(log),
          ),
        ],
      ),
    );
  }

  // ─── MOBILE CARD ───────────────────────────────────────────
  Widget _buildMobileCard(Map<String, dynamic> log) {
    final type = (log['type'] ?? 'IN').toString().toUpperCase();
    final isLogin = type == 'IN' || type == 'LOGIN';
    final name = (log['employee_name'] ?? 'Unknown Employee').toString();
    final email = (log['email'] ?? '').toString();
    final employeeId = (log['employee_id'] ?? '').toString();
    final dept = (log['department'] ?? '').toString();

    String initials = '?';
    if (name.isNotEmpty) {
      final parts = name.split(' ');
      if (parts.length >= 2) {
        initials = parts[0][0].toUpperCase() + parts[1][0].toUpperCase();
      } else {
        initials = name.substring(0, 1).toUpperCase();
      }
    }

    final displayEmail =
    email.isNotEmpty ? email : '$employeeId@company.com';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tc.border, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: tc.orange.withValues(alpha: 0.15),
                child: Text(
                  initials,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: tc.orangeText,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: tc.text,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dept.isNotEmpty ? dept : 'No Department',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: tc.textMuted,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      displayEmail,
                      style: TextStyle(fontSize: 12, color: tc.textMuted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              _buildActions(log),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.calendar_today_rounded,
                  size: 13, color: tc.textMuted),
              const SizedBox(width: 6),
              Text(
                _fmtDate(log['timestamp']),
                style: TextStyle(fontSize: 12, color: tc.textMuted),
              ),
              const SizedBox(width: 12),
              Icon(Icons.access_time_rounded,
                  size: 13, color: tc.textMuted),
              const SizedBox(width: 6),
              Text(
                _fmtTime(log['timestamp']),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: tc.text,
                ),
              ),
              const Spacer(),
              _buildEventPill(isLogin, compact: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEventPill(bool isLogin, {bool compact = false}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: isLogin ? tc.pillGreenBg : tc.pillBlueBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        isLogin ? 'IN' : 'OUT',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: isLogin ? tc.pillGreenTx : tc.pillBlueTx,
        ),
      ),
    );
  }

  Widget _buildActions(Map<String, dynamic> log) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        PopupMenuButton<String>(
          icon: Icon(Icons.more_vert, size: 20, color: tc.textMuted),
          color: tc.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: tc.border),
          ),
          tooltip: 'Actions',
          onSelected: (value) {
            switch (value) {
              case 'verify':
                _openVerification(log);
                break;
              case 'approve':
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content:
                    Text('Approved: ${log['employee_name'] ?? 'log'}'),
                    backgroundColor: tc.green,
                  ),
                );
                break;
              case 'flag':
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        'Flagged for review: ${log['employee_name'] ?? 'log'}'),
                    backgroundColor: tc.red,
                  ),
                );
                break;
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem<String>(
              value: 'verify',
              child: Row(
                children: [
                  Icon(Icons.fact_check_outlined,
                      size: 16, color: tc.orange),
                  const SizedBox(width: 10),
                  Text('View Verification',
                      style: TextStyle(color: tc.text, fontSize: 13)),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'approve',
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline,
                      size: 16, color: tc.green),
                  const SizedBox(width: 10),
                  Text('Approve',
                      style: TextStyle(color: tc.text, fontSize: 13)),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'flag',
              child: Row(
                children: [
                  Icon(Icons.flag_outlined, size: 16, color: tc.red),
                  const SizedBox(width: 10),
                  Text('Flag for Review',
                      style: TextStyle(color: tc.text, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
        IconButton(
          icon: Icon(Icons.arrow_forward_rounded,
              size: 18, color: tc.textMuted),
          tooltip: 'Open verification',
          onPressed: () => _openVerification(log),
        ),
      ],
    );
  }

  // ─── PAGINATION ────────────────────────────────────────────
  Widget _buildPagination() {
    return LayoutBuilder(builder: (_, c) {
      final r = BsResponsive(c.maxWidth);
      final narrow = !r.up(BsSize.md);

      final info = Text(
        'Showing ${_filteredLogs.isEmpty ? 0 : (_currentPage - 1) * _rowsPerPage + 1} to ${_currentPage * _rowsPerPage > _filteredLogs.length ? _filteredLogs.length : _currentPage * _rowsPerPage} of ${_filteredLogs.length} entries',
        style: TextStyle(fontSize: 13, color: tc.textMuted),
        overflow: TextOverflow.ellipsis,
      );

      final controls = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed:
            _currentPage > 1 ? () => setState(() => _currentPage--) : null,
            icon: Icon(
              Icons.chevron_left,
              size: 20,
              color: _currentPage > 1 ? tc.text : tc.muted,
            ),
          ),
          ...List.generate(_totalPages, (index) {
            final i = index + 1;
            final isActive = i == _currentPage;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isActive ? tc.orange : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: isActive ? null : Border.all(color: tc.border),
              ),
              child: InkWell(
                onTap: () => setState(() => _currentPage = i),
                child: Text(
                  '$i',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight:
                    isActive ? FontWeight.w700 : FontWeight.normal,
                    color: isActive
                        ? (tc.isDark ? tc.onOrange : Colors.white)
                        : tc.text,
                  ),
                ),
              ),
            );
          }),
          IconButton(
            onPressed: _currentPage < _totalPages
                ? () => setState(() => _currentPage++)
                : null,
            icon: Icon(
              Icons.chevron_right,
              size: 20,
              color: _currentPage < _totalPages ? tc.text : tc.muted,
            ),
          ),
        ],
      );

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: tc.surface,
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(12),
            bottomRight: Radius.circular(12),
          ),
        ),
        child: narrow
            ? Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            info,
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: controls,
            ),
          ],
        )
            : Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [info, controls],
        ),
      );
    });
  }

  // ══════════════════════════════════════════════════════════════
  // BOTTOM CARDS
  // ══════════════════════════════════════════════════════════════
  Widget _buildBottomCards() {
    return LayoutBuilder(builder: (_, c) {
      final r = BsResponsive(c.maxWidth);
      final stack = !r.up(BsSize.lg);

      if (stack) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildBiometricCard(),
            const SizedBox(height: 20),
            _buildAuditCard(),
          ],
        );
      }
      // ✅ FIX: `start` imbes na `stretch` — pareho naman may fixed height (300)
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _buildBiometricCard()),
          const SizedBox(width: 24),
          Expanded(child: _buildAuditCard()),
        ],
      );
    });
  }

  /// Biometric card with image + fallback gradient + LIVE badge
  Widget _buildBiometricCard() {
    return Container(
      height: 300,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/logo1.png',
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: tc.isDark
                        ? [
                      const Color(0xFF1F2937),
                      const Color(0xFF111827),
                      const Color(0xFF0F172A),
                    ]
                        : [
                      const Color(0xFF3B4A5F),
                      const Color(0xFF1F2937),
                      const Color(0xFF111827),
                    ],
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      top: -20,
                      right: -20,
                      child: Icon(
                        Icons.fingerprint,
                        size: 200,
                        color: Colors.white.withValues(alpha: 0.04),
                      ),
                    ),
                    Positioned(
                      bottom: -30,
                      left: -30,
                      child: Icon(
                        Icons.qr_code_2_rounded,
                        size: 180,
                        color: Colors.white.withValues(alpha: 0.04),
                      ),
                    ),
                    Positioned(
                      top: 40,
                      left: 40,
                      child: Icon(
                        Icons.face_retouching_natural,
                        size: 100,
                        color: Colors.white.withValues(alpha: 0.03),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          // Gradient overlay
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.4),
                  Colors.black.withValues(alpha: 0.85),
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),

          // LIVE badge
          Positioned(
            top: 16,
            right: 16,
            child: Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFF4CE346),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x804CE346),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'LIVE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Content
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: const [
                Text(
                  'Real-time Biometric Integration',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.2,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Every login and logout is synchronized instantly with central biometric hardware, ensuring 100% accurate timekeeping records for payroll processing.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuditCard() {
    final Color onOrange = tc.isDark ? tc.onOrange : const Color(0xFF623200);

    return Container(
      height: 300,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: tc.orange,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(Icons.security_rounded, size: 30, color: onOrange),
          Text(
            'Secure Audit Trail',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: onOrange,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Detailed logs track not only timestamps but also specific device IDs and location data for total administrative transparency.',
            style: TextStyle(
              fontSize: 14,
              color: onOrange.withValues(alpha: 0.9),
              height: 1.5,
            ),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: onOrange,
                foregroundColor: tc.orange,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
              child: const Text(
                'View Compliance Report',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // HELPERS
  // ══════════════════════════════════════════════════════════════

  Widget _buildFilterField({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: tc.textMuted,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    Color? bgColor,
    Color? textColor,
    Color? borderColor,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 14, color: textColor ?? tc.textMuted),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: textColor ?? tc.textMuted,
        ),
      ),
      style: OutlinedButton.styleFrom(
        backgroundColor: bgColor ?? tc.card,
        side: BorderSide(
          color: borderColor ?? tc.border,
          width: 1,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 0,
      ),
    );
  }
}