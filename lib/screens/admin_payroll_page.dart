// lib/screens/admin_payroll_page.dart
import 'package:flutter/material.dart';
import 'admin_theme.dart';
import '../widgets/bootstrap_grid.dart';

class AdminPayrollPage extends StatefulWidget {
  final List<Map<String, dynamic>> employees;
  final Map<String, List<Map<String, dynamic>>> userLogs;
  final Function(Map<String, dynamic>) onSelectEmployee;

  const AdminPayrollPage({
    super.key,
    required this.employees,
    required this.userLogs,
    required this.onSelectEmployee,
  });

  @override
  State<AdminPayrollPage> createState() => _AdminPayrollPageState();
}

class _AdminPayrollPageState extends State<AdminPayrollPage> {
  AdminColors get tc => AdminTheme.getColors(context);

  String _selectedPayPeriod = 'Oct 01 - Oct 15, 2023';
  String _selectedDepartment = 'All Departments';
  final String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final departments = <String>['All Departments'];
    for (var emp in widget.employees) {
      final dept = emp['department']?.toString();
      if (dept != null && dept.isNotEmpty && !departments.contains(dept)) {
        departments.add(dept);
      }
    }

    final filteredEmployees = widget.employees.where((emp) {
      final name = (emp['name'] ??
          '${emp['firstName'] ?? ''} ${emp['lastName'] ?? ''}')
          .toString()
          .toLowerCase();
      final id =
      (emp['id'] ?? emp['employeeId'] ?? '').toString().toLowerCase();
      final dept = (emp['department'] ?? '').toString();

      final matchesSearch = name.contains(_searchQuery.toLowerCase()) ||
          id.contains(_searchQuery.toLowerCase());
      final matchesDept = _selectedDepartment == 'All Departments' ||
          dept == _selectedDepartment;

      return matchesSearch && matchesDept;
    }).toList();

    double totalNetDisbursement = 0;
    int pendingCount = 0;

    for (var emp in filteredEmployees) {
      final basicSalary =
          (emp['basicSalary'] as num?)?.toDouble() ?? 45000.0;
      final netPay = basicSalary * 0.9;
      totalNetDisbursement += netPay;

      final status =
      (emp['payrollStatus'] ?? 'Processed').toString().toLowerCase();
      if (status == 'pending' || status == 'on hold') {
        pendingCount++;
      }
    }

    return Container(
      color: tc.background,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: BsContainer(
          maxWidth: 1600,
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildPageHeader(),
              const SizedBox(height: 20),
              _buildStatsRow(totalNetDisbursement, pendingCount),
              const SizedBox(height: 20),
              _buildFiltersRow(departments),
              const SizedBox(height: 16),
              _buildTable(filteredEmployees),
              const SizedBox(height: 16),
              Text(
                'Showing ${filteredEmployees.length} of employees',
                style: TextStyle(fontSize: 12, color: tc.muted),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // PAGE HEADER — responsive: nags-stack sa mobile
  // ══════════════════════════════════════════════════════════════
  Widget _buildPageHeader() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 800.0;
        final narrow = w < 720;

        final titleWidget = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Payroll Management',
              style: TextStyle(
                fontSize: narrow ? 20 : 24,
                fontWeight: FontWeight.w800,
                color: tc.text,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Manage and review employee disbursements for the current period.',
              style: TextStyle(fontSize: 13, color: tc.muted),
            ),
          ],
        );

        final filtersBtn = OutlinedButton.icon(
          onPressed: () {},
          icon: Icon(Icons.tune, size: 16, color: tc.text),
          label: Text('Filters',
              style: TextStyle(
                  color: tc.text,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
          style: OutlinedButton.styleFrom(
            backgroundColor: tc.card,
            side: BorderSide(color: tc.border),
            padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
        );

        final exportBtn = ElevatedButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.download, size: 16, color: Colors.white),
          label: const Text('Export to CSV',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
          style: ElevatedButton.styleFrom(
            backgroundColor: tc.orange,
            elevation: 0,
            padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
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
                  Expanded(child: exportBtn),
                  const SizedBox(width: 10),
                  filtersBtn,
                ],
              ),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: titleWidget),
            const SizedBox(width: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                filtersBtn,
                const SizedBox(width: 10),
                exportBtn,
              ],
            ),
          ],
        );
      },
    );
  }

  // ══════════════════════════════════════════════════════════════
  // STATS — Wrap-based, responsive (2/3 + 1/3 ratio)
  // ══════════════════════════════════════════════════════════════
  Widget _buildStatsRow(double totalNetDisbursement, int pendingCount) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 800.0;
        final isWide = w >= 900;
        const gap = 20.0;

        final totalCard = _buildTotalCard(totalNetDisbursement);
        final pendingCard = _buildPendingCard(pendingCount);

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 2, child: totalCard),
              const SizedBox(width: gap),
              Expanded(flex: 1, child: pendingCard),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            totalCard,
            const SizedBox(height: gap),
            pendingCard,
          ],
        );
      },
    );
  }

  Widget _buildTotalCard(double total) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tc.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('TOTAL NET DISBURSEMENT',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: tc.muted,
                        letterSpacing: 0.5)),
                const SizedBox(height: 8),
                Text(
                  '₱${_formatCurrency(total)}',
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: tc.text),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_upward, size: 14, color: tc.green),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text('4.2% from last period',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: tc.green),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: tc.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: tc.border),
            ),
            child: Icon(Icons.account_balance_wallet_outlined,
                size: 36, color: tc.muted),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingCard(int pendingCount) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFA35200),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('PENDING APPROVALS',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFFFECD0),
                  letterSpacing: 0.5)),
          const SizedBox(height: 4),
          Text('$pendingCount Employees',
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Colors.white),
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFC27803),
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Review Now',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // FILTERS — Wrap-based para hindi mag-overflow sa mobile
  // ══════════════════════════════════════════════════════════════
  Widget _buildFiltersRow(List<String> departments) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        Container(
          padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          height: 42,
          decoration: BoxDecoration(
            color: tc.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: tc.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedPayPeriod,
              dropdownColor: tc.card,
              icon: Icon(Icons.keyboard_arrow_down,
                  size: 16, color: tc.muted),
              items: const [
                'Oct 01 - Oct 15, 2023',
                'Oct 16 - Oct 31, 2023'
              ].map((period) {
                return DropdownMenuItem(
                  value: period,
                  child: Text(period,
                      style: TextStyle(
                          fontSize: 13,
                          color: tc.text,
                          fontWeight: FontWeight.w500)),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() => _selectedPayPeriod = val);
                }
              },
            ),
          ),
        ),
        Container(
          padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          height: 42,
          decoration: BoxDecoration(
            color: tc.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: tc.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedDepartment,
              dropdownColor: tc.card,
              icon: Icon(Icons.keyboard_arrow_down,
                  size: 16, color: tc.muted),
              items: departments.map((dept) {
                return DropdownMenuItem(
                  value: dept,
                  child: Text(dept,
                      style: TextStyle(
                          fontSize: 13,
                          color: tc.text,
                          fontWeight: FontWeight.w500)),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() => _selectedDepartment = val);
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════
  // TABLE
  // ══════════════════════════════════════════════════════════════
  Widget _buildTable(List<Map<String, dynamic>> filteredEmployees) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tc.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : 800.0;
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: w),
                child: DataTable(
                  headingRowColor:
                  WidgetStateProperty.all(tc.surface),
                  dataRowMinHeight: 64,
                  dataRowMaxHeight: 72,
                  columnSpacing: 32,
                  columns: [
                    _col('EMPLOYEE NAME & ID'),
                    _col('BASIC SALARY'),
                    _col('DEDUCTIONS (TAX/SSS)'),
                    _col('NET PAY'),
                    _col('STATUS'),
                    _col('ACTION'),
                  ],
                  rows: filteredEmployees.map((emp) {
                    final rawId =
                    (emp['id'] ?? emp['employeeId'] ?? 'N/A').toString();
                    final displayId = rawId.length > 10
                        ? '${rawId.substring(0, 8)}...'
                        : rawId;

                    final name = emp['name'] ??
                        '${emp['firstName'] ?? ''} ${emp['lastName'] ?? ''}';
                    final initials = _getInitials(name);

                    final double basicSalary =
                        (emp['basicSalary'] as num?)?.toDouble() ?? 50000.0;
                    final double deduction = basicSalary * 0.09;
                    final double netPay = basicSalary - deduction;
                    final String status =
                    (emp['payrollStatus'] ?? 'PROCESSED')
                        .toString()
                        .toUpperCase();

                    return DataRow(cells: [
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor:
                              tc.orange.withValues(alpha: 0.15),
                              child: Text(initials,
                                  style: TextStyle(
                                      color: tc.orangeText,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12)),
                            ),
                            const SizedBox(width: 12),
                            ConstrainedBox(
                              constraints:
                              const BoxConstraints(maxWidth: 180),
                              child: Column(
                                crossAxisAlignment:
                                CrossAxisAlignment.start,
                                mainAxisAlignment:
                                MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(name,
                                      style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                          color: tc.text),
                                      overflow: TextOverflow.ellipsis),
                                  Text('ID: $displayId',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: tc.muted)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      DataCell(Text('₱${_formatCurrency(basicSalary)}',
                          style: TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                              color: tc.text))),
                      DataCell(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('-₱${_formatCurrency(deduction)}',
                                style: TextStyle(
                                    color: tc.red,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 13)),
                            Text('SSS, PhilHealth, Pag-IBIG',
                                style: TextStyle(
                                    fontSize: 10, color: tc.muted)),
                          ],
                        ),
                      ),
                      DataCell(Text('₱${_formatCurrency(netPay)}',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: tc.orangeText))),
                      DataCell(_buildStatusBadge(status)),
                      DataCell(
                        IconButton(
                          icon: Icon(Icons.remove_red_eye_outlined,
                              size: 16, color: tc.muted),
                          onPressed: () {
                            widget.onSelectEmployee(emp);
                          },
                        ),
                      ),
                    ]);
                  }).toList(),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  DataColumn _col(String label) => DataColumn(
    label: Text(label,
        style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: tc.muted)),
  );

  Widget _buildStatusBadge(String status) {
    Color bgColor;
    Color textColor;

    if (status.contains('PROCESS')) {
      bgColor = tc.pillGreenBg;
      textColor = tc.pillGreenTx;
    } else if (status.contains('PEND')) {
      bgColor = tc.pillWarnBg;
      textColor = tc.pillWarnTx;
    } else {
      bgColor = tc.pillBlueBg;
      textColor = tc.pillBlueTx;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 6,
              height: 6,
              decoration:
              BoxDecoration(color: textColor, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(status,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                  letterSpacing: 0.5)),
        ],
      ),
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    } else if (parts.isNotEmpty && parts[0].isNotEmpty) {
      return parts[0][0].toUpperCase();
    }
    return 'HR';
  }

  String _formatCurrency(double amount) {
    return amount.toStringAsFixed(2).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]},',
    );
  }
}