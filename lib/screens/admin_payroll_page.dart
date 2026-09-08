import 'package:flutter/material.dart';
import 'admin_theme.dart';

<<<<<<< HEAD
class AdminPayrollPage extends StatefulWidget {
  final List<Map<String, dynamic>> employees;
  final Map<String, List<Map<String, dynamic>>> userLogs;
  final Function(Map<String, dynamic>) onSelectEmployee; // Idinagdag para maiwasan ang error
=======
class AdminPayrollPage extends StatelessWidget {
  final List<Map<String, dynamic>> employees;
  final Map<String, List<Map<String, dynamic>>> userLogs;
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1

  const AdminPayrollPage({
    super.key,
    required this.employees,
    required this.userLogs,
<<<<<<< HEAD
    required this.onSelectEmployee, // Required parameter na ngayon
  });

  @override
  State<AdminPayrollPage> createState() => _AdminPayrollPageState();
}

class _AdminPayrollPageState extends State<AdminPayrollPage> {
  String _selectedPayPeriod = 'Oct 01 - Oct 15, 2023';
  String _selectedDepartment = 'All Departments';
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    List<String> departments = ['All Departments'];
    for (var emp in widget.employees) {
      final dept = emp['department']?.toString();
      if (dept != null && dept.isNotEmpty && !departments.contains(dept)) {
        departments.add(dept);
      }
    }

    final filteredEmployees = widget.employees.where((emp) {
      final name = (emp['name'] ?? '${emp['firstName'] ?? ''} ${emp['lastName'] ?? ''}').toString().toLowerCase();
      final id = (emp['id'] ?? emp['employeeId'] ?? '').toString().toLowerCase();
      final dept = (emp['department'] ?? '').toString();

      final matchesSearch = name.contains(_searchQuery.toLowerCase()) || id.contains(_searchQuery.toLowerCase());
      final matchesDept = _selectedDepartment == 'All Departments' || dept == _selectedDepartment;

      return matchesSearch && matchesDept;
    }).toList();

    double totalNetDisbursement = 0;
    int pendingCount = 0;

    for (var emp in filteredEmployees) {
      double basicSalary = (emp['basicSalary'] as num?)?.toDouble() ?? 45000.0;
      double netPay = basicSalary * 0.9;
      totalNetDisbursement += netPay;

      final status = (emp['payrollStatus'] ?? 'Processed').toString().toLowerCase();
      if (status == 'pending' || status == 'on hold') {
        pendingCount++;
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24.0, 0.0, 24.0, 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // PAGE HEADER
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Payroll Management',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF11142D),
                      letterSpacing: -0.5,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Manage and review employee disbursements for the current period.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF6C727F)),
                  ),
                ],
              ),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.tune, size: 16, color: Color(0xFF11142D)),
                    label: const Text('Filters', style: TextStyle(color: Color(0xFF11142D), fontWeight: FontWeight.w600, fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFFE1E6ED)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.download, size: 16, color: Colors.white),
                    label: const Text('Export to CSV', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF8A00),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // STATS CARDS
          Row(
            children: [
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE1E6ED)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('TOTAL NET DISBURSEMENT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF6C727F), letterSpacing: 0.5)),
                          const SizedBox(height: 8),
                          Text('₱${_formatCurrency(totalNetDisbursement)}', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: Color(0xFF11142D))),
                          const SizedBox(height: 8),
                          Row(
                            children: const [
                              Icon(Icons.arrow_upward, size: 14, color: Color(0xFF10B981)),
                              SizedBox(width: 4),
                              Text('4.2% from last period', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF10B981))),
                            ],
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE1E6ED)),
                        ),
                        child: const Icon(Icons.account_balance_wallet_outlined, size: 40, color: Color(0xFFCBD5E1)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                flex: 1,
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFFA35200),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('PENDING APPROVALS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFFFECD0), letterSpacing: 0.5)),
                          const SizedBox(height: 4),
                          Text('$pendingCount Employees', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {},
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFC27803),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Review Now', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // FILTERS ROW
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE1E6ED)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedPayPeriod,
                    icon: const Icon(Icons.keyboard_arrow_down, size: 16, color: Color(0xFF6C727F)),
                    items: ['Oct 01 - Oct 15, 2023', 'Oct 16 - Oct 31, 2023'].map((period) {
                      return DropdownMenuItem(
                        value: period,
                        child: Text(period, style: const TextStyle(fontSize: 13, color: Color(0xFF11142D), fontWeight: FontWeight.w500)),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedPayPeriod = val);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE1E6ED)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedDepartment,
                    icon: const Icon(Icons.keyboard_arrow_down, size: 16, color: Color(0xFF6C727F)),
                    items: departments.map((dept) {
                      return DropdownMenuItem(
                        value: dept,
                        child: Text(dept, style: const TextStyle(fontSize: 13, color: Color(0xFF11142D), fontWeight: FontWeight.w500)),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedDepartment = val);
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // TABLE CONTAINER
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE1E6ED)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minWidth: constraints.maxWidth),
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                        dataRowMinHeight: 64,
                        dataRowMaxHeight: 72,
                        columnSpacing: 40,
                        columns: const [
                          DataColumn(label: Text('EMPLOYEE NAME & ID', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF6C727F)))),
                          DataColumn(label: Text('BASIC SALARY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF6C727F)))),
                          DataColumn(label: Text('DEDUCTIONS (TAX/SSS)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF6C727F)))),
                          DataColumn(label: Text('NET PAY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF6C727F)))),
                          DataColumn(label: Text('STATUS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF6C727F)))),
                          DataColumn(label: Text('ACTION', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF6C727F)))),
                        ],
                        rows: filteredEmployees.map((emp) {
                          final rawId = (emp['id'] ?? emp['employeeId'] ?? 'N/A').toString();
                          final displayId = rawId.length > 10 ? '${rawId.substring(0, 8)}...' : rawId;

                          final name = emp['name'] ?? '${emp['firstName'] ?? ''} ${emp['lastName'] ?? ''}';
                          final initials = _getInitials(name);

                          final double basicSalary = (emp['basicSalary'] as num?)?.toDouble() ?? 50000.0;
                          final double deduction = basicSalary * 0.09;
                          final double netPay = basicSalary - deduction;
                          final String status = (emp['payrollStatus'] ?? 'PROCESSED').toString().toUpperCase();

                          return DataRow(cells: [
                            DataCell(
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 18,
                                    backgroundColor: const Color(0xFFFFECD0),
                                    child: Text(initials, style: const TextStyle(color: Color(0xFFC27803), fontWeight: FontWeight.bold, fontSize: 12)),
                                  ),
                                  const SizedBox(width: 12),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF11142D))),
                                      Text('ID: $displayId', style: const TextStyle(fontSize: 11, color: Color(0xFF6C727F))),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            DataCell(Text('₱${_formatCurrency(basicSalary)}', style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13, color: Color(0xFF11142D)))),
                            DataCell(
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text('-₱${_formatCurrency(deduction)}', style: const TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w500, fontSize: 13)),
                                  const Text('SSS, PhilHealth, Pag-IBIG', style: TextStyle(fontSize: 10, color: Color(0xFF8C8F9A))),
                                ],
                              ),
                            ),
                            DataCell(Text('₱${_formatCurrency(netPay)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFFC27803)))),
                            DataCell(_buildStatusBadge(status)),
                            DataCell(
                              IconButton(
                                icon: const Icon(Icons.remove_red_eye_outlined, size: 16, color: Color(0xFF6C727F)),
                                onPressed: () {
                                  // Pinalitan para gamitin ang onSelectEmployee callback patungo sa dashboard state
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
          ),
          const SizedBox(height: 16),
          Text(
            'Showing ${filteredEmployees.length} of employees',
            style: const TextStyle(fontSize: 12, color: Color(0xFF6C727F)),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bgColor;
    Color textColor;

    if (status.contains('PROCESS')) {
      bgColor = const Color(0xFFE6F6EF);
      textColor = const Color(0xFF0D9488);
    } else if (status.contains('PEND')) {
      bgColor = const Color(0xFFFEF3C7);
      textColor = const Color(0xFFD97706);
    } else {
      bgColor = const Color(0xFFE0F2FE);
      textColor = const Color(0xFF0284C7);
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
          Container(width: 6, height: 6, decoration: BoxDecoration(color: textColor, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(status, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: textColor, letterSpacing: 0.5)),
        ],
      ),
    );
  }

  String _getInitials(String name) {
    List<String> parts = name.trim().split(' ');
    if (parts.length >= 2) {
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
=======
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AdminTheme.s4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Automated Shift Payroll Ledgers', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AdminTheme.text, letterSpacing: -0.3)),
        const SizedBox(height: AdminTheme.s4),
        ...employees.map((emp) {
          final id = (emp['id'] ?? '').toString();
          final totalScans = (userLogs[id] ?? []).length;
          final name = emp['name'] ?? '${emp['firstName'] ?? ''} ${emp['lastName'] ?? ''}';

          return Container(
            margin: const EdgeInsets.only(bottom: AdminTheme.s2),
            decoration: AdminTheme.card(),
            padding: const EdgeInsets.all(AdminTheme.s4),
            child: Row(children: [
              const Icon(Icons.monetization_on_rounded, color: AdminTheme.green, size: 24),
              const SizedBox(width: AdminTheme.s3),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: const TextStyle(color: AdminTheme.text, fontWeight: FontWeight.bold)),
                  Text('${emp['department']} · ${emp['role']}', style: const TextStyle(color: AdminTheme.muted, fontSize: 11)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('$totalScans Swipes', style: const TextStyle(fontWeight: FontWeight.w600)),
                const Text('Generated', style: TextStyle(color: AdminTheme.muted, fontSize: 10)),
              ]),
            ]),
          );
        }),
      ]),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
    );
  }
}