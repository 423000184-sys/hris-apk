// lib/screens/admin_add_employee_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'admin_database.dart';
import 'admin_theme.dart';
import '../services/face_matcher.dart';
import '../widgets/bootstrap_grid.dart';

class AdminAddEmployeePage extends StatefulWidget {
  final VoidCallback onRefreshNeeded;

  const AdminAddEmployeePage({super.key, required this.onRefreshNeeded});

  @override
  State<AdminAddEmployeePage> createState() => _AdminAddEmployeePageState();
}

class _AdminAddEmployeePageState extends State<AdminAddEmployeePage> {
  final _fKey = GlobalKey<FormState>();
  bool _saving = false;

  Uint8List? _profileImageBytes;

  late Future<List<Map<String, dynamic>>> _employeesFuture;

  AdminColors get tc => AdminTheme.getColors(context);

  @override
  void initState() {
    super.initState();
    _employeesFuture = AdminDatabase.getEmployees();
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? tc.red : tc.green,
      ),
    );
  }

  String _getInitials(String firstName, String lastName) {
    String f = firstName.isNotEmpty ? firstName[0].toUpperCase() : '';
    String l = lastName.isNotEmpty ? lastName[0].toUpperCase() : '';
    return '$f$l'.isEmpty ? 'E' : '$f$l';
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          height: constraints.maxHeight,
          child: Container(
            color: tc.background,
            child: Stack(
              children: [
                Positioned.fill(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(32.0),
                    child: BsContainer(
                      maxWidth: 1600,
                      padding: EdgeInsets.zero,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildPageHeader(),
                          const SizedBox(height: 24),
                          _buildFilterCard(),
                          const SizedBox(height: 24),
                          _buildEmployeesTable(),
                          const SizedBox(height: 100),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 24,
                  right: 24,
                  child: FloatingActionButton(
                    onPressed: () => _snack('Print report initiated...'),
                    backgroundColor: tc.orange,
                    foregroundColor: tc.onOrange,
                    elevation: 4,
                    child: const Icon(Icons.print_rounded),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ══════════════════════════════════════════════════════════════
  // PAGE HEADER
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
              'Add Employee',
              style: TextStyle(
                fontSize: r.responsive<double>(xs: 22, sm: 26, md: 28, lg: 32),
                fontWeight: FontWeight.w700,
                color: tc.text,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Real-time verification of professional shifts and geofencing status.',
              style: TextStyle(
                fontSize: r.responsive<double>(xs: 13, md: 16),
                color: tc.textMuted,
              ),
            ),
          ],
        );

        final exportBtn = OutlinedButton.icon(
          onPressed: () => _snack('CSV Exported'),
          icon: Icon(Icons.download_rounded, size: 16, color: tc.text),
          label: Text(
            'Export CSV',
            style: TextStyle(
                color: tc.text, fontWeight: FontWeight.w700, fontSize: 14),
          ),
          style: OutlinedButton.styleFrom(
            backgroundColor: tc.card,
            side: BorderSide(color: tc.border),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            elevation: 0,
          ),
        );

        final manualBtn = ElevatedButton.icon(
          onPressed: _openAddDialog,
          icon: Icon(Icons.add_rounded, size: 16, color: tc.onOrange),
          label: Text(
            'Manual Entry',
            style: TextStyle(
                color: tc.onOrange, fontWeight: FontWeight.w700, fontSize: 14),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: tc.orange,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            elevation: 0,
          ),
        );

        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              title,
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: exportBtn),
                  const SizedBox(width: 12),
                  Expanded(child: manualBtn),
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
                exportBtn,
                const SizedBox(width: 12),
                manualBtn,
              ],
            ),
          ],
        );
      },
    );
  }

  // ══════════════════════════════════════════════════════════════
  // FILTER CARD
  // ══════════════════════════════════════════════════════════════
  Widget _buildFilterCard() {
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
          Text(
            'DATE RANGE',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: tc.textMuted,
                letterSpacing: 0.5),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: tc.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: tc.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Sept 1, 2025 - Sept 16, 2025',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: tc.text),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.calendar_month_rounded,
                    size: 20, color: tc.textMuted),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // EMPLOYEES TABLE
  // ══════════════════════════════════════════════════════════════
  Widget _buildEmployeesTable() {
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
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _employeesFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Padding(
                      padding: const EdgeInsets.all(48.0),
                      child: Center(
                          child:
                          CircularProgressIndicator(color: tc.orange)),
                    );
                  }
                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Text(
                          'Error loading employees: ${snapshot.error}',
                          style: TextStyle(color: tc.red)),
                    );
                  }
                  final employees = snapshot.data ?? [];
                  if (employees.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(48.0),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.people_outline_rounded,
                                size: 48, color: tc.muted),
                            const SizedBox(height: 12),
                            Text(
                                'No registered employees found in database.',
                                style: TextStyle(
                                    color: tc.muted, fontSize: 14)),
                          ],
                        ),
                      ),
                    );
                  }
                  return Column(
                    children: employees.asMap().entries.map((entry) {
                      final index = entry.key;
                      final emp = entry.value;
                      final isLast = index == employees.length - 1;
                      return isMobile
                          ? _buildEmployeeMobileCard(emp, isLast: isLast)
                          : _buildEmployeeRow(emp, isLast: isLast);
                    }).toList(),
                  );
                },
              ),
              _buildTableFooter(),
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
            topLeft: Radius.circular(12), topRight: Radius.circular(12)),
        border: Border(bottom: BorderSide(color: tc.borderWarm, width: 1)),
      ),
      child: Row(
        children: [
          _th('EMPLOYEE NAME', flex: 3),
          _th('ROLE / DEPT', flex: 2),
          SizedBox(
            width: 60,
            child: Text('ACTIONS',
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: tc.textMuted,
                    letterSpacing: 0.5)),
          ),
        ],
      ),
    );
  }

  Widget _buildTableFooter() {
    return LayoutBuilder(builder: (_, c) {
      final r = BsResponsive(c.maxWidth);
      final narrow = !r.up(BsSize.sm);
      final info = Text('System Records Active',
          style: TextStyle(fontSize: 13, color: tc.textMuted));
      final controls = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _pageBtn(Icons.chevron_left_rounded, false),
          const SizedBox(width: 6),
          _pageNumberBtn('1', true),
          const SizedBox(width: 6),
          _pageBtn(Icons.chevron_right_rounded, false),
        ],
      );
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: tc.surface,
          borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(12),
              bottomRight: Radius.circular(12)),
          border: Border(top: BorderSide(color: tc.borderWarm, width: 1)),
        ),
        child: narrow
            ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [info, const SizedBox(height: 12), controls])
            : Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [info, controls]),
      );
    });
  }

  Widget _th(String label, {required int flex}) {
    return Expanded(
      flex: flex,
      child: Text(label,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: tc.textMuted,
              letterSpacing: 0.5)),
    );
  }

  Widget _buildEmployeeRow(Map<String, dynamic> emp, {bool isLast = false}) {
    final firstName = emp['firstName'] ?? emp['first_name'] ?? '';
    final lastName = emp['lastName'] ?? emp['last_name'] ?? '';
    final fullName = '$firstName $lastName'.trim().isEmpty
        ? (emp['name'] ?? 'Unknown Staff')
        : '$firstName $lastName';
    final empId = emp['nfcTagId'] ?? emp['id'] ?? 'N/A';
    final displayId = empId.toString().length > 12
        ? '${empId.toString().substring(0, 12)}...'
        : empId.toString();
    final role = emp['role'] ?? 'Staff';
    final dept = emp['department'] ?? 'General';
    final initials = _getInitials(firstName, lastName);
    final hasFace = emp['faceEmbedding'] != null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
          border: isLast
              ? null
              : Border(bottom: BorderSide(color: tc.border, width: 0.5))),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: tc.orange.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: tc.orange.withValues(alpha: 0.3), width: 1),
                  ),
                  child: Center(
                      child: Text(initials,
                          style: TextStyle(
                              color: tc.orangeText,
                              fontSize: 13,
                              fontWeight: FontWeight.w700))),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(fullName,
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                    color: tc.text),
                                overflow: TextOverflow.ellipsis),
                          ),
                          if (hasFace) ...[
                            const SizedBox(width: 6),
                            Icon(Icons.verified_user_rounded,
                                size: 14, color: tc.green),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text('ID: $displayId',
                          style: TextStyle(
                              fontSize: 12, color: tc.textMuted),
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
              flex: 2,
              child: Text('$role ($dept)',
                  style: TextStyle(
                      fontSize: 14,
                      color: tc.text,
                      fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis)),
          SizedBox(
              width: 60,
              child: Align(
                  alignment: Alignment.centerRight,
                  child: _buildActionsMenu(fullName))),
        ],
      ),
    );
  }

  Widget _buildEmployeeMobileCard(Map<String, dynamic> emp,
      {bool isLast = false}) {
    final firstName = emp['firstName'] ?? emp['first_name'] ?? '';
    final lastName = emp['lastName'] ?? emp['last_name'] ?? '';
    final fullName = '$firstName $lastName'.trim().isEmpty
        ? (emp['name'] ?? 'Unknown Staff')
        : '$firstName $lastName';
    final empId = emp['nfcTagId'] ?? emp['id'] ?? 'N/A';
    final displayId = empId.toString().length > 12
        ? '${empId.toString().substring(0, 12)}...'
        : empId.toString();
    final role = emp['role'] ?? 'Staff';
    final dept = emp['department'] ?? 'General';
    final initials = _getInitials(firstName, lastName);
    final hasFace = emp['faceEmbedding'] != null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          border: isLast
              ? null
              : Border(bottom: BorderSide(color: tc.border, width: 0.5))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: tc.orange.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(
                  color: tc.orange.withValues(alpha: 0.3), width: 1),
            ),
            child: Center(
                child: Text(initials,
                    style: TextStyle(
                        color: tc.orangeText,
                        fontSize: 14,
                        fontWeight: FontWeight.w700))),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(fullName,
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: tc.text),
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (hasFace) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.verified_user_rounded,
                          size: 14, color: tc.green),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text('ID: $displayId',
                    style: TextStyle(fontSize: 12, color: tc.textMuted),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Text('$role ($dept)',
                    style: TextStyle(
                        fontSize: 13,
                        color: tc.text,
                        fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          _buildActionsMenu(fullName),
        ],
      ),
    );
  }

  Widget _buildActionsMenu(String fullName) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert_rounded, color: tc.textMuted, size: 20),
      color: tc.card,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: tc.border)),
      tooltip: 'Actions',
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          value: 'edit',
          child: Row(children: [
            Icon(Icons.edit_outlined, size: 16, color: tc.orange),
            const SizedBox(width: 10),
            Text('Edit', style: TextStyle(color: tc.text, fontSize: 13))
          ]),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(children: [
            Icon(Icons.delete_outline_rounded, size: 16, color: tc.red),
            const SizedBox(width: 10),
            Text('Delete', style: TextStyle(color: tc.text, fontSize: 13))
          ]),
        ),
      ],
      onSelected: (value) => _snack('$value: $fullName'),
    );
  }

  Widget _pageBtn(IconData icon, bool active) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 2),
    width: 32,
    height: 32,
    decoration: BoxDecoration(
        color: active ? tc.orange : Colors.transparent,
        borderRadius: BorderRadius.circular(6)),
    child:
    Icon(icon, size: 18, color: active ? tc.onOrange : tc.textMuted),
  );

  Widget _pageNumberBtn(String text, bool active) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 2),
    width: 32,
    height: 32,
    alignment: Alignment.center,
    decoration: BoxDecoration(
        color: active ? tc.orange : Colors.transparent,
        borderRadius: BorderRadius.circular(6)),
    child: Text(text,
        style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: active ? tc.onOrange : tc.text)),
  );

  // ══════════════════════════════════════════════════════════════
  // ADD DIALOG
  // ══════════════════════════════════════════════════════════════
  void _openAddDialog() {
    _profileImageBytes = null;
    _saving = false;

    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final birthdayCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final deptCtrl = TextEditingController();
    final idCtrl = TextEditingController();
    final nfcCtrl = TextEditingController();
    final pinCtrl = TextEditingController();
    // ✅ BAGONG: salary controller
    final salaryCtrl = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) {
          final dialogTc = AdminTheme.getColors(ctx);

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: EdgeInsets.all(BsResponsive.of(ctx).isXs ? 8 : 16),
            child: Container(
              constraints: BoxConstraints(
                  maxWidth: 960,
                  maxHeight: MediaQuery.of(ctx).size.height * 0.95),
              padding: EdgeInsets.all(BsResponsive.of(ctx).isXs ? 16 : 28),
              decoration: BoxDecoration(
                color: dialogTc.background,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: dialogTc.border),
              ),
              child: SingleChildScrollView(
                child: Form(
                  key: _fKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Add New Employee',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: dialogTc.orange)),
                      const SizedBox(height: 4),
                      Text('Employee Registration',
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: dialogTc.text)),
                      const SizedBox(height: 4),
                      Text(
                          'Onboard a new team member and configure their biometric access credentials.',
                          style: TextStyle(
                              fontSize: 12, color: dialogTc.muted)),
                      const SizedBox(height: 20),

                      LayoutBuilder(
                        builder: (context, constraints) {
                          final stack = !BsResponsive(constraints.maxWidth)
                              .up(BsSize.md);
                          if (stack) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildProfileCard(ctx, setS, dialogTc),
                                const SizedBox(height: 20),
                                _buildRightColumn(
                                    ctx,
                                    dialogTc,
                                    nameCtrl,
                                    emailCtrl,
                                    birthdayCtrl,
                                    phoneCtrl,
                                    deptCtrl,
                                    idCtrl,
                                    nfcCtrl,
                                    pinCtrl,
                                    salaryCtrl),
                              ],
                            );
                          }
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                  width: 280,
                                  child: _buildProfileCard(ctx, setS, dialogTc)),
                              const SizedBox(width: 20),
                              Expanded(
                                  child: _buildRightColumn(
                                      ctx,
                                      dialogTc,
                                      nameCtrl,
                                      emailCtrl,
                                      birthdayCtrl,
                                      phoneCtrl,
                                      deptCtrl,
                                      idCtrl,
                                      nfcCtrl,
                                      pinCtrl,
                                      salaryCtrl)),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 24),

                      LayoutBuilder(
                        builder: (context, constraints) {
                          final stack = BsResponsive(constraints.maxWidth).isXs;

                          final cancelBtn = OutlinedButton(
                            onPressed:
                            _saving ? null : () => Navigator.pop(ctx),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: dialogTc.text,
                              side: BorderSide(color: dialogTc.border),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text('Cancel',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                          );

                          final submitBtn = ElevatedButton(
                            onPressed: _saving
                                ? null
                                : () async {
                              if (_fKey.currentState == null ||
                                  !_fKey.currentState!.validate()) {
                                return;
                              }
                              if (!ctx.mounted) return;
                              setS(() => _saving = true);

                              try {
                                final fullName = nameCtrl.text.trim();
                                final parts = fullName.split(' ');
                                final firstName = parts.isNotEmpty
                                    ? parts.first
                                    : fullName;
                                final lastName = parts.length > 1
                                    ? parts.sublist(1).join(' ')
                                    : 'Doe';

                                final err =
                                await AdminDatabase.addEmployee(
                                  firstName: firstName,
                                  lastName: lastName,
                                  email: emailCtrl.text.trim(),
                                  password: 'password123',
                                  role: 'Staff',
                                  department: deptCtrl.text.trim(),
                                  nfcTagId: nfcCtrl.text.trim(),
                                  pin: pinCtrl.text.trim(),
                                );

                                if (!ctx.mounted) return;

                                if (err != null) {
                                  _snack(err, error: true);
                                  setS(() => _saving = false);
                                  return;
                                }

                                // ✅ BAGONG: I-save ang salary + status + phone + birthday
                                final capturedEmail = emailCtrl.text.trim();
                                final salaryValue = double.tryParse(
                                    salaryCtrl.text
                                        .replaceAll(',', '')
                                        .trim()) ??
                                    0.0;

                                try {
                                  final q = await FirebaseFirestore.instance
                                      .collection('employees')
                                      .where('email',
                                      isEqualTo: capturedEmail)
                                      .limit(1)
                                      .get();

                                  if (q.docs.isNotEmpty) {
                                    final docRef = q.docs.first.reference;
                                    final extraData = <String, dynamic>{
                                      'basicSalary': salaryValue,
                                      'payrollStatus': 'Processed',
                                    };
                                    final phone = phoneCtrl.text.trim();
                                    final bday = birthdayCtrl.text.trim();
                                    if (phone.isNotEmpty) {
                                      extraData['phone'] = phone;
                                    }
                                    if (bday.isNotEmpty) {
                                      extraData['birthday'] = bday;
                                    }
                                    await docRef.update(extraData);
                                    debugPrint(
                                        '✅ Extra data saved: $extraData');
                                  }
                                } catch (e) {
                                  debugPrint('⚠️ Extra data save failed: $e');
                                }

                                // Close dialog
                                final capturedBytes = _profileImageBytes;
                                Navigator.pop(ctx);
                                if (mounted) {
                                  _snack(capturedBytes != null
                                      ? 'Employee saved! Processing face in background...'
                                      : 'Employee saved successfully.');
                                  setState(() {
                                    _employeesFuture =
                                        AdminDatabase.getEmployees();
                                  });
                                  widget.onRefreshNeeded();
                                }

                                // Background face setup
                                if (capturedBytes != null) {
                                  _processFaceInBackground(
                                      capturedEmail, capturedBytes);
                                }
                              } catch (e) {
                                if (!ctx.mounted) return;
                                _snack('Failed to add employee: $e',
                                    error: true);
                                setS(() => _saving = false);
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: dialogTc.orange,
                              foregroundColor: dialogTc.onOrange,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              elevation: 0,
                            ),
                            child: _saving
                                ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    color: dialogTc.onOrange,
                                    strokeWidth: 2))
                                : const Text('Complete Onboarding',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                          );

                          if (stack) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                submitBtn,
                                const SizedBox(height: 12),
                                cancelBtn
                              ],
                            );
                          }
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              cancelBtn,
                              const SizedBox(width: 12),
                              submitBtn
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ).then((_) {
      nameCtrl.dispose();
      emailCtrl.dispose();
      birthdayCtrl.dispose();
      phoneCtrl.dispose();
      deptCtrl.dispose();
      idCtrl.dispose();
      nfcCtrl.dispose();
      pinCtrl.dispose();
      salaryCtrl.dispose();
    });
  }

  Future<void> _processFaceInBackground(
      String email, Uint8List imageBytes) async {
    try {
      debugPrint('🔒 Starting background face setup for $email');

      final query = await FirebaseFirestore.instance
          .collection('employees')
          .where('email', isEqualTo: email)
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 10));

      if (query.docs.isEmpty) {
        debugPrint('⚠️ Employee not found by email — face setup skipped');
        return;
      }

      final empDoc = query.docs.first;
      final empId = empDoc.id;

      try {
        final photoUrl = await FaceMatcher.uploadEmployeePhoto(
          empId,
          imageBytes,
        ).timeout(const Duration(seconds: 15));

        if (photoUrl != null) {
          await empDoc.reference
              .update({'photoUrl': photoUrl})
              .timeout(const Duration(seconds: 10));
          debugPrint('✅ Photo uploaded: $photoUrl');
        }
      } catch (e) {
        debugPrint('⚠️ Photo upload failed: $e');
      }

      try {
        final embedding = await FaceMatcher.generateEmbedding(imageBytes)
            .timeout(const Duration(seconds: 10));

        if (embedding.isNotEmpty) {
          await FaceMatcher.saveEmbedding(empId, embedding)
              .timeout(const Duration(seconds: 10));
          debugPrint('✅ Face embedding saved for $empId');
        }
      } catch (e) {
        debugPrint('⚠️ Embedding failed: $e');
      }

      debugPrint('✅ Background face setup complete');
    } catch (e) {
      debugPrint('❌ Background face setup error: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════
  // PROFILE CARD
  // ══════════════════════════════════════════════════════════════
  Widget _buildProfileCard(
      BuildContext ctx, StateSetter setS, AdminColors dialogTc) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dialogTc.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: dialogTc.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () async {
              FilePickerResult? result = await FilePicker.platform.pickFiles(
                  type: FileType.image, allowMultiple: false);
              if (result != null && result.files.single.bytes != null) {
                if (ctx.mounted) {
                  setS(() {
                    _profileImageBytes = result.files.single.bytes;
                  });
                  _snack('Profile picture loaded.');
                }
              }
            },
            child: Container(
              width: double.infinity,
              height: 220,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: dialogTc.surface,
                image: _profileImageBytes != null
                    ? DecorationImage(
                    image: MemoryImage(_profileImageBytes!),
                    fit: BoxFit.cover)
                    : null,
              ),
              child: Stack(
                children: [
                  if (_profileImageBytes == null)
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.person_outline_rounded,
                              size: 56, color: dialogTc.muted),
                          const SizedBox(height: 8),
                          Text('Upload Photo',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: dialogTc.muted)),
                          const SizedBox(height: 4),
                          Text('(used for face recognition)',
                              style: TextStyle(
                                  fontSize: 10, color: dialogTc.muted)),
                        ],
                      ),
                    ),
                  const Positioned(
                    bottom: 8,
                    right: 8,
                    child: CircleAvatar(
                        backgroundColor: Colors.black54,
                        radius: 16,
                        child: Icon(Icons.camera_alt_rounded,
                            color: Colors.white, size: 16)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text('Profile Identity',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: dialogTc.text)),
          const SizedBox(height: 4),
          Text('Click image to upload/change employee photo.',
              style: TextStyle(
                  fontSize: 11, color: dialogTc.muted, height: 1.3)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: dialogTc.pillWarnBg,
              borderRadius: BorderRadius.circular(8),
              border:
              Border.all(color: dialogTc.pillWarnTx.withValues(alpha: 0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 14, color: dialogTc.pillWarnTx),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Ensure the employee's name matches their government-issued ID. Photo will be used for biometric verification.",
                    style: TextStyle(
                        fontSize: 10,
                        color: dialogTc.pillWarnTx,
                        fontWeight: FontWeight.w500,
                        height: 1.3),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // RIGHT COLUMN — may Salary field na
  // ══════════════════════════════════════════════════════════════
  Widget _buildRightColumn(
      BuildContext ctx,
      AdminColors dialogTc,
      TextEditingController nameCtrl,
      TextEditingController emailCtrl,
      TextEditingController birthdayCtrl,
      TextEditingController phoneCtrl,
      TextEditingController deptCtrl,
      TextEditingController idCtrl,
      TextEditingController nfcCtrl,
      TextEditingController pinCtrl,
      TextEditingController salaryCtrl,
      ) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: dialogTc.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: dialogTc.border)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.badge_outlined, size: 16, color: dialogTc.orange),
                const SizedBox(width: 8),
                Text('Personal Information',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: dialogTc.text))
              ]),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 500;
                  if (narrow) {
                    return Column(
                      children: [
                        _buildInput(
                            'FULL NAME', nameCtrl, 'Full Name', dialogTc),
                        const SizedBox(height: 12),
                        _buildInput('EMAIL ADDRESS', emailCtrl,
                            'Email Address', dialogTc),
                        const SizedBox(height: 12),
                        _buildInput(
                            'BIRTHDAY', birthdayCtrl, 'Birthday', dialogTc),
                        const SizedBox(height: 12),
                        _buildInput(
                            'PHONE NO.', phoneCtrl, 'Phone No.', dialogTc),
                        const SizedBox(height: 12),
                        _buildInput(
                            'DEPARTMENT', deptCtrl, 'Department', dialogTc),
                        const SizedBox(height: 12),
                        _buildInput(
                            'EMPLOYEE ID', idCtrl, 'Employee ID', dialogTc),
                        const SizedBox(height: 12),
                        // ✅ BAGONG field
                        _buildInput('BASIC SALARY (₱)', salaryCtrl,
                            'e.g. 25000', dialogTc,
                            keyboardType: TextInputType.number),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      Row(children: [
                        Expanded(
                            child: _buildInput(
                                'FULL NAME', nameCtrl, 'Full Name', dialogTc)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: _buildInput('EMAIL ADDRESS', emailCtrl,
                                'Email Address', dialogTc))
                      ]),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(
                            child: _buildInput(
                                'BIRTHDAY', birthdayCtrl, 'Birthday', dialogTc)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: _buildInput(
                                'PHONE NO.', phoneCtrl, 'Phone No.', dialogTc))
                      ]),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(
                            child: _buildInput('DEPARTMENT', deptCtrl,
                                'Department', dialogTc)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: _buildInput(
                                'EMPLOYEE ID', idCtrl, 'Employee ID', dialogTc))
                      ]),
                      const SizedBox(height: 12),
                      // ✅ BAGONG field — full width
                      _buildInput('BASIC SALARY (₱)', salaryCtrl,
                          'e.g. 25000', dialogTc,
                          keyboardType: TextInputType.number),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: dialogTc.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: dialogTc.border)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.fingerprint, size: 16, color: dialogTc.orange),
                const SizedBox(width: 8),
                Text('Biometric Credentials',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: dialogTc.text))
              ]),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 500;
                  if (narrow) {
                    return Column(
                      children: [
                        _buildInput('KEYFOB SERIAL', nfcCtrl, 'Keyfob Serial',
                            dialogTc,
                            suffixIcon: Icons.wifi),
                        const SizedBox(height: 12),
                        _buildInput('4-DIGIT PIN', pinCtrl, '4-Digit PIN',
                            dialogTc,
                            obscure: true),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(
                          child: _buildInput('KEYFOB SERIAL', nfcCtrl,
                              'Keyfob Serial', dialogTc,
                              suffixIcon: Icons.wifi)),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _buildInput(
                              '4-DIGIT PIN', pinCtrl, '4-Digit PIN', dialogTc,
                              obscure: true)),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildBadge('NFC Ready', dialogTc),
                  _buildBadge('Pin-pad Enabled', dialogTc),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInput(
      String label,
      TextEditingController controller,
      String hint,
      AdminColors dialogTc, {
        bool obscure = false,
        IconData? suffixIcon,
        TextInputType? keyboardType,
      }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: dialogTc.muted,
                letterSpacing: 0.5)),
        const SizedBox(height: 4),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          style: TextStyle(
              fontSize: 12, color: dialogTc.text, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: dialogTc.muted),
            filled: true,
            fillColor: dialogTc.surface,
            contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            suffixIcon: suffixIcon != null
                ? Icon(suffixIcon, size: 14, color: dialogTc.muted)
                : null,
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: dialogTc.border)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: dialogTc.orange, width: 1.5)),
          ),
        ),
      ],
    );
  }

  Widget _buildBadge(String text, AdminColors dialogTc) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: dialogTc.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: dialogTc.border)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, size: 11, color: dialogTc.orange),
          const SizedBox(width: 5),
          Text(text,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: dialogTc.text)),
        ],
      ),
    );
  }
}