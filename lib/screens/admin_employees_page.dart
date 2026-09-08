import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'admin_database.dart';
import 'admin_theme.dart';
import 'admin_add_employee_page.dart';

// Pinahihintulutan ang mouse dragging at scrolling sa Web/Desktop
class CustomAppScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };
}

class AdminEmployeesPage extends StatefulWidget {
  final List<Map<String, dynamic>> employees;
  final String searchQuery;
  final VoidCallback onRefreshNeeded;
  final VoidCallback? onAddEmployee;

  const AdminEmployeesPage({
    super.key,
    required this.employees,
    required this.searchQuery,
    required this.onRefreshNeeded,
    this.onAddEmployee,
  });

  @override
  State<AdminEmployeesPage> createState() => _AdminEmployeesPageState();
}

class _AdminEmployeesPageState extends State<AdminEmployeesPage> {
  final ScrollController _scrollController = ScrollController();

  // Controllers para sa Edit
  final _editFirstCtrl = TextEditingController();
  final _editLastCtrl = TextEditingController();
  final _editRoleCtrl = TextEditingController();
  final _editDeptCtrl = TextEditingController();
  final _editEmailCtrl = TextEditingController();
  final _editPhoneCtrl = TextEditingController();
  final _editPassCtrl = TextEditingController();
  final _editKeyfobCtrl = TextEditingController();
  final _editPinCtrl = TextEditingController();
  bool _editSaving = false;
  bool _editPassVis = false;
  bool _isEditingEmployee = false;

  // Controllers para sa Add Employee
  final _addFirstCtrl = TextEditingController();
  final _addLastCtrl = TextEditingController();
  final _addEmailCtrl = TextEditingController();
  final _addPhoneCtrl = TextEditingController();
  final _addRoleCtrl = TextEditingController();
  final _addDeptCtrl = TextEditingController();
  final _addPassCtrl = TextEditingController();
  bool _addSaving = false;
  bool _addPassVis = false;
  bool _isAddingEmployee = false;

  final _filterCtrl = TextEditingController();
  String _filterText = '';
  String _department = 'All Departments';
  String _sort = 'A-Z';
  int _page = 0;
  static const int _pageSize = 5;

  Map<String, dynamic>? _selectedProfileEmp;

  static const Color _bg = Color(0xFFF7F6F4);
  static const Color _panel = Color(0xFFFFFFFF);
  static const Color _orange = Color(0xFFFF7A00);
  static const Color _text = Color(0xFF1E1E1E);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _cardBorder = Color(0xFFEBEAE6);
  static const Color _proBg = Color(0xFFFFEEC2);
  static const Color _proText = Color(0xFFB45309);
  static const Color _green = Color(0xFF10B981);
  static const Color _featuredAvatarBlue = Color(0xFF3B82F6);
  static const Color _standardAvatarDark = Color(0xFF111827);

  @override
  void initState() {
    super.initState();
    final q = widget.searchQuery;
    _filterCtrl.text = q;
    _filterText = q;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _editFirstCtrl.dispose();
    _editLastCtrl.dispose();
    _editRoleCtrl.dispose();
    _editDeptCtrl.dispose();
    _editEmailCtrl.dispose();
    _editPhoneCtrl.dispose();
    _editPassCtrl.dispose();
    _editKeyfobCtrl.dispose();
    _editPinCtrl.dispose();

    _addFirstCtrl.dispose();
    _addLastCtrl.dispose();
    _addEmailCtrl.dispose();
    _addPhoneCtrl.dispose();
    _addRoleCtrl.dispose();
    _addDeptCtrl.dispose();
    _addPassCtrl.dispose();

    _filterCtrl.dispose();
    super.dispose();
  }

  String _s(dynamic v, [String fallback = '—']) {
    if (v == null) return fallback;
    final str = v.toString().trim();
    return str.isEmpty ? fallback : str;
  }

  bool _match(String text) => _s(text).toLowerCase().contains(_s(_filterText).toLowerCase());

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? AdminTheme.red : AdminTheme.green,
      ),
    );
  }

  String _nameOf(Map<String, dynamic> e) {
    final name = _s(e['name'], '');
    if (name.isNotEmpty && name != '—') return name;
    final full = '${_s(e['firstName'], '')} ${_s(e['lastName'], '')}'.trim();
    return full.isNotEmpty ? full : 'Unnamed Employee';
  }

  bool _isPro(Map<String, dynamic> e) {
    final v = e['pro'] ?? e['isPro'];
    if (v is bool) return v;
    return _s(v).toLowerCase() == 'true';
  }

  Future<void> _generateAndDownloadPdf(Map<String, dynamic> emp) async {
    final pdf = pw.Document();

    final name = _nameOf(emp);
    final role = _s(emp['role'], 'No Role Specified');
    final dept = _s(emp['department'], 'Unassigned');
    final email = _s(emp['email'], 'No Email Registered');
    final phone = _s(emp['phone'], _s(emp['mobile'], 'No Phone Registered'));
    final id = _s(emp['id'], 'N/A');
    final joiningDate = _s(emp['joiningDate'], _s(emp['created_at'], 'Not Specified'));
    final nfcId = _s(emp['nfcId'], _s(emp['nfc_id'], 'NOT ASSIGNED'));
    final activeStatus = _s(emp['status'], 'ACTIVE').toUpperCase();

    int annualLeaveUsed = 0;
    int sickLeaveUsed = 0;
    final rawLeaves = emp['leaves'] ?? emp['leaveRequests'] ?? emp['leave_requests'];
    if (rawLeaves is List) {
      for (var item in rawLeaves) {
        if (item is Map<String, dynamic>) {
          final status = _s(item['status'], '').toUpperCase();
          final type = _s(item['type'] ?? item['leaveType'], '').toUpperCase();
          final days = int.tryParse(item['days']?.toString() ?? '1') ?? 1;

          if (status == 'APPROVED' || status == 'ACCEPTED') {
            if (type.contains('SICK')) {
              sickLeaveUsed += days;
            } else {
              annualLeaveUsed += days;
            }
          }
        }
      }
    }
    annualLeaveUsed = annualLeaveUsed.clamp(0, 18);
    sickLeaveUsed = sickLeaveUsed.clamp(0, 18);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Padding(
            padding: const pw.EdgeInsets.all(24),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Header(
                  level: 0,
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('EMPLOYEE PROFILE REPORT', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
                      pw.Text('Status: $activeStatus', style: pw.TextStyle(fontSize: 12, color: PdfColors.orange)),
                    ],
                  ),
                ),
                pw.SizedBox(height: 20),
                pw.Text('Basic Information', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.Divider(),
                pw.SizedBox(height: 10),
                pw.Row(children: [pw.Text('Name: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)), pw.Text(name)]),
                pw.SizedBox(height: 5),
                pw.Row(children: [pw.Text('Employee ID: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)), pw.Text(id)]),
                pw.SizedBox(height: 5),
                pw.Row(children: [pw.Text('Role: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)), pw.Text(role)]),
                pw.SizedBox(height: 5),
                pw.Row(children: [pw.Text('Department: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)), pw.Text(dept)]),
                pw.SizedBox(height: 5),
                pw.Row(children: [pw.Text('Email: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)), pw.Text(email)]),
                pw.SizedBox(height: 5),
                pw.Row(children: [pw.Text('Phone: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)), pw.Text(phone)]),
                pw.SizedBox(height: 5),
                pw.Row(children: [pw.Text('Joining Date: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)), pw.Text(joiningDate)]),
                pw.SizedBox(height: 20),
                pw.Text('Security Credentials', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.Divider(),
                pw.SizedBox(height: 10),
                pw.Row(children: [pw.Text('NFC/KEYFOB ID: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)), pw.Text(nfcId)]),
                pw.SizedBox(height: 20),
                pw.Text('Leave Balance Overview', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.Divider(),
                pw.SizedBox(height: 10),
                pw.Row(children: [
                  pw.Text('Annual Leave: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text('${18 - annualLeaveUsed} Days Left ($annualLeaveUsed / 18 Used)'),
                ]),
                pw.SizedBox(height: 5),
                pw.Row(children: [
                  pw.Text('Sick Leave: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text('${18 - sickLeaveUsed} Days Left ($sickLeaveUsed / 18 Used)'),
                ]),
              ],
            ),
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Profile_${name.replaceAll(' ', '_')}.pdf',
    );
  }

  Widget _avatarContent(Map<String, dynamic> emp, String initial,
      {required double size, required double fontSize, Color textColor = Colors.white}) {
    final photoUrl = _s(emp['photoUrl'], '').isNotEmpty
        ? _s(emp['photoUrl'], '')
        : _s(emp['photo'], '');

    if (photoUrl.isNotEmpty && photoUrl != '—') {
      return Image.network(
        photoUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _avatarFallback(initial, fontSize, textColor),
      );
    }
    return _avatarFallback(initial, fontSize, textColor);
  }

  Widget _avatarFallback(String initial, double fontSize, Color textColor) => Center(
    child: Text(
      initial,
      style: TextStyle(color: textColor, fontSize: fontSize, fontWeight: FontWeight.w700),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_isEditingEmployee && _selectedProfileEmp != null) {
      return _buildEditEmployeePage(_selectedProfileEmp!);
    }

    if (_isAddingEmployee) {
      return _buildAddEmployeePage();
    }

    if (_selectedProfileEmp != null) {
      return _buildEmployeeProfilePage(_selectedProfileEmp!);
    }

    final departments = <String>{
      'All Departments',
      ...widget.employees.map((e) => _s(e['department'], '')).where((d) => d.isNotEmpty && d != '—'),
    }.toList();

    final effectiveDepartment = departments.contains(_department) ? _department : 'All Departments';
    if (effectiveDepartment != _department) {
      _department = effectiveDepartment;
    }

    var filtered = widget.employees.where((e) {
      final hay = '${_nameOf(e)} ${_s(e['role'])} ${_s(e['id'])} ${_s(e['department'])}';
      final matchesText = _match(hay);
      final matchesDept = effectiveDepartment == 'All Departments' || _s(e['department']) == effectiveDepartment;
      return matchesText && matchesDept;
    }).toList();

    filtered.sort((a, b) {
      final cmp = _nameOf(a).toLowerCase().compareTo(_nameOf(b).toLowerCase());
      return _sort == 'A-Z' ? cmp : -cmp;
    });

    final total = filtered.length;
    final totalPages = total == 0 ? 1 : (total / _pageSize).ceil();
    if (_page >= totalPages) _page = totalPages - 1;
    if (_page < 0) _page = 0;
    final start = _page * _pageSize;
    final end = (start + _pageSize).clamp(0, total);
    final pageItems = total == 0 ? <Map<String, dynamic>>[] : filtered.sublist(start, end);

    return Container(
      color: _bg,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return ScrollConfiguration(
            behavior: CustomAppScrollBehavior(),
            child: Scrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              trackVisibility: true,
              thickness: 8.0,
              radius: const Radius.circular(8),
              child: SingleChildScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _header(),
                        const SizedBox(height: 20),
                        _filterBar(departments),
                        const SizedBox(height: 20),
                        if (pageItems.isEmpty)
                          _emptyState()
                        else
                          _directoryGrid(pageItems, showQuickInvite: _page == 0),
                        const SizedBox(height: 16),
                        if (total > 0) _pagination(start, end, total, totalPages),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAddEmployeePage() {
    return Container(
      color: _bg,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextButton.icon(
              onPressed: () => setState(() => _isAddingEmployee = false),
              icon: const Icon(Icons.arrow_back_rounded, color: _muted),
              label: const Text('Back to Directory', style: TextStyle(color: _muted, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 12),
            const Text(
              'Add New Employee',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: _text),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(controller: _addFirstCtrl, decoration: const InputDecoration(labelText: 'First Name')),
                  const SizedBox(height: 16),
                  TextField(controller: _addLastCtrl, decoration: const InputDecoration(labelText: 'Last Name')),
                  const SizedBox(height: 16),
                  TextField(controller: _addEmailCtrl, decoration: const InputDecoration(labelText: 'Email Address')),
                  const SizedBox(height: 16),
                  TextField(controller: _addPhoneCtrl, decoration: const InputDecoration(labelText: 'Phone Number')),
                  const SizedBox(height: 16),
                  TextField(controller: _addRoleCtrl, decoration: const InputDecoration(labelText: 'Role / Designation')),
                  const SizedBox(height: 16),
                  TextField(controller: _addDeptCtrl, decoration: const InputDecoration(labelText: 'Department')),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _addPassCtrl,
                    obscureText: !_addPassVis,
                    decoration: InputDecoration(
                      labelText: 'Account Password',
                      suffixIcon: IconButton(
                        icon: Icon(_addPassVis ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _addPassVis = !_addPassVis),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                    onPressed: _addSaving
                        ? null
                        : () async {
                      final firstName = _addFirstCtrl.text.trim();
                      final lastName = _addLastCtrl.text.trim();
                      final email = _addEmailCtrl.text.trim();

                      if (firstName.isEmpty || lastName.isEmpty || email.isEmpty) {
                        _snack('First name, last name, and email are required.', error: true);
                        return;
                      }

                      setState(() => _addSaving = true);

                      try {
                        final data = {
                          'firstName': firstName,
                          'lastName': lastName,
                          'name': '$firstName $lastName',
                          'email': email,
                          'phone': _addPhoneCtrl.text.trim(),
                          'role': _addRoleCtrl.text.trim(),
                          'department': _addDeptCtrl.text.trim(),
                          'password': _addPassCtrl.text.trim(),
                          'status': 'active',
                        };

                        final err = await AdminDatabase.updateEmployee(
                          DateTime.now().millisecondsSinceEpoch.toString(),
                          data,
                        );

                        if (!mounted) return;

                        if (err != null) {
                          _snack('Failed to add employee: $err', error: true);
                        } else {
                          _snack('Employee successfully added!');
                          _addFirstCtrl.clear();
                          _addLastCtrl.clear();
                          _addEmailCtrl.clear();
                          _addPhoneCtrl.clear();
                          _addRoleCtrl.clear();
                          _addDeptCtrl.clear();
                          _addPassCtrl.clear();
                          setState(() => _isAddingEmployee = false);
                          widget.onRefreshNeeded();
                        }
                      } catch (e) {
                        if (!mounted) return;
                        _snack('Failed to add employee: $e', error: true);
                      } finally {
                        if (mounted) setState(() => _addSaving = false);
                      }
                    },
                    child: _addSaving
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Save Employee', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _editField(String label, TextEditingController controller, {bool readOnly = false}) {
    return TextField(
      controller: controller,
      readOnly: readOnly,
      style: const TextStyle(
        fontSize: 13,
        color: Colors.black,
        fontWeight: FontWeight.w500,
      ),
      cursorColor: _orange,
      decoration: InputDecoration(
        hintText: label,
        hintStyle: const TextStyle(
          color: Color(0xFF9CA3AF),
          fontSize: 13,
          fontWeight: FontWeight.w400,
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _orange, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildEditEmployeePage(Map<String, dynamic> emp) {
    final photoUrl = _s(emp['photoUrl'], '').isNotEmpty ? _s(emp['photoUrl'], '') : _s(emp['photo'], '');
    final empId = _s(emp['id'], 'EMP-2024-024');

    return Container(
      color: _bg,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextButton.icon(
              onPressed: () => setState(() => _isEditingEmployee = false),
              icon: const Icon(Icons.arrow_back_rounded, color: _muted),
              label: const Text('Back to Profile', style: TextStyle(color: _muted, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 12),
            const Text(
              'Edit Employee',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: _text),
            ),
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 320,
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _cardBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 240,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.grey.shade200,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: photoUrl.isNotEmpty && photoUrl != '—'
                                ? Image.network(photoUrl, fit: BoxFit.cover)
                                : const Icon(Icons.person, size: 80, color: Colors.grey),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text('Profile Identity', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _text)),
                        const SizedBox(height: 8),
                        const Text(
                          'This photo will be used for digital identification across the portal.',
                          style: TextStyle(fontSize: 12, color: _muted),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _cardBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.person_outline, color: _orange, size: 20),
                                SizedBox(width: 8),
                                Text('Personal Information', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _text)),
                              ],
                            ),
                            const SizedBox(height: 20),
                            Row(
                              children: [
                                Expanded(child: _editField('FULL NAME / First Name', _editFirstCtrl)),
                                const SizedBox(width: 16),
                                Expanded(child: _editField('EMAIL ADDRESS', _editEmailCtrl)),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(child: _editField('ROLE / DESIGNATION', _editRoleCtrl)),
                                const SizedBox(width: 16),
                                Expanded(child: _editField('PHONE NO.', _editPhoneCtrl)),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(child: _editField('DEPARTMENT', _editDeptCtrl)),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _editField(
                                    'EMPLOYEE ID',
                                    TextEditingController(text: empId),
                                    readOnly: true,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _cardBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.fingerprint, color: _orange, size: 20),
                                SizedBox(width: 8),
                                Text('Biometric Credentials', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _text)),
                              ],
                            ),
                            const SizedBox(height: 20),
                            Row(
                              children: [
                                Expanded(child: _editField('KEYFOB SERIAL', _editKeyfobCtrl)),
                                const SizedBox(width: 16),
                                Expanded(child: _editField('4-DIGIT PIN', _editPinCtrl)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton(
                            onPressed: () => setState(() => _isEditingEmployee = false),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                              side: const BorderSide(color: _cardBorder),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text('Cancel', style: TextStyle(color: _text)),
                          ),
                          const SizedBox(width: 16),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _orange,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              elevation: 0,
                            ),
                            onPressed: _editSaving
                                ? null
                                : () async {
                              setState(() => _editSaving = true);
                              final data = {
                                'firstName': _editFirstCtrl.text.trim(),
                                'lastName': _editLastCtrl.text.trim(),
                                'name': '${_editFirstCtrl.text.trim()} ${_editLastCtrl.text.trim()}',
                                'email': _editEmailCtrl.text.trim(),
                                'phone': _editPhoneCtrl.text.trim(),
                                'role': _editRoleCtrl.text.trim(),
                                'department': _editDeptCtrl.text.trim(),
                                'nfcId': _editKeyfobCtrl.text.trim(),
                                'pin': _editPinCtrl.text.trim(),
                              };
                              final err = await AdminDatabase.updateEmployee(_s(emp['id']), data);
                              setState(() => _editSaving = false);
                              if (err != null) {
                                _snack('Update failed: $err', error: true);
                              } else {
                                _snack('Employee profile updated!');
                                setState(() {
                                  _isEditingEmployee = false;
                                  _selectedProfileEmp = {...emp, ...data};
                                });
                                widget.onRefreshNeeded();
                              }
                            },
                            child: _editSaving
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : const Text('Done', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmployeeProfilePage(Map<String, dynamic> emp) {
    final name = _nameOf(emp);
    final role = _s(emp['role'], 'No Role Specified');
    final dept = _s(emp['department'], 'Unassigned');
    final email = _s(emp['email'], 'No Email Registered');
    final phone = _s(emp['phone'], _s(emp['mobile'], 'No Phone Registered'));
    final id = _s(emp['id'], 'N/A');
    final joiningDate = _s(emp['joiningDate'], _s(emp['created_at'], 'Not Specified'));
    final nfcId = _s(emp['nfcId'], _s(emp['nfc_id'], 'NOT ASSIGNED'));
    final activeStatus = _s(emp['status'], 'ACTIVE').toUpperCase();

    final rawLogs = emp['attendance'] ?? emp['attendanceLogs'] ?? emp['logs'];
    List<Map<String, dynamic>> attendanceList = [];

    if (rawLogs is List) {
      for (var item in rawLogs) {
        if (item is Map<String, dynamic>) {
          final timeIn = _s(item['timeIn'] ?? item['time_in'], '');
          final timeOut = _s(item['timeOut'] ?? item['time_out'], '');

          if (timeIn.isNotEmpty && timeIn != '—' && timeOut.isNotEmpty && timeOut != '—') {
            attendanceList.add(item);
          }
        }
      }
    }

    int annualLeaveUsed = 0;
    int sickLeaveUsed = 0;

    final rawLeaves = emp['leaves'] ?? emp['leaveRequests'] ?? emp['leave_requests'];
    if (rawLeaves is List) {
      for (var item in rawLeaves) {
        if (item is Map<String, dynamic>) {
          final status = _s(item['status'], '').toUpperCase();
          final type = _s(item['type'] ?? item['leaveType'], '').toUpperCase();
          final days = int.tryParse(item['days']?.toString() ?? '1') ?? 1;

          if (status == 'APPROVED' || status == 'ACCEPTED') {
            if (type.contains('SICK')) {
              sickLeaveUsed += days;
            } else {
              annualLeaveUsed += days;
            }
          }
        }
      }
    }

    annualLeaveUsed = annualLeaveUsed.clamp(0, 18);
    sickLeaveUsed = sickLeaveUsed.clamp(0, 18);

    return Container(
      color: _bg,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextButton.icon(
              onPressed: () => setState(() => _selectedProfileEmp = null),
              icon: const Icon(Icons.arrow_back_rounded, color: _muted),
              label: const Text('Back to Directory', style: TextStyle(color: _muted, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 12),
            const Text(
              'Employee Profile',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: _text),
            ),
            const SizedBox(height: 24),
            LayoutBuilder(builder: (context, c) {
              final isMobile = c.maxWidth < 850;
              return IntrinsicHeight(
                child: Flex(
                  direction: isMobile ? Axis.vertical : Axis.horizontal,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: isMobile ? 0 : 7,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _cardBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: activeStatus == 'ACTIVE' ? const Color(0xFFFFECE0) : Colors.grey.shade200,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        activeStatus,
                                        style: TextStyle(
                                          color: activeStatus == 'ACTIVE' ? _orange : _muted,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                    Text('ID: $id', style: const TextStyle(color: _muted, fontSize: 13, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Text(name, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: _text)),
                                const SizedBox(height: 4),
                                Text(role, style: const TextStyle(fontSize: 15, color: _orange, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 32),
                                Row(
                                  children: [
                                    Expanded(child: _profileDetailItem(icon: Icons.apartment_rounded, title: 'Department', value: dept)),
                                    Expanded(child: _profileDetailItem(icon: Icons.email_outlined, title: 'Work Email', value: email)),
                                  ],
                                ),
                                const SizedBox(height: 28),
                                Row(
                                  children: [
                                    Expanded(child: _profileDetailItem(icon: Icons.phone_outlined, title: 'Phone Extension', value: phone)),
                                    Expanded(child: _profileDetailItem(icon: Icons.calendar_today_outlined, title: 'Joining Date', value: joiningDate)),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 36),
                            Row(
                              children: [
                                ElevatedButton.icon(
                                  onPressed: () => _openEditDialog(emp),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _orange,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    elevation: 0,
                                  ),
                                  icon: const Icon(Icons.edit_outlined, size: 18),
                                  label: const Text('Edit Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                ),
                                const SizedBox(width: 16),
                                OutlinedButton.icon(
                                  onPressed: () => _generateAndDownloadPdf(emp),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: _text,
                                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                    side: const BorderSide(color: _cardBorder),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  icon: const Icon(Icons.download_rounded, size: 18),
                                  label: const Text('Download Profile', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (isMobile) const SizedBox(height: 20) else const SizedBox(width: 20),
                    Expanded(
                      flex: isMobile ? 0 : 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _cardBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.shield_outlined, size: 20, color: _muted),
                                SizedBox(width: 8),
                                Text('Security Credentials', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _text)),
                              ],
                            ),
                            const SizedBox(height: 24),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('NFC/KEYFOB ID', style: TextStyle(fontSize: 11, color: _muted, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                                  const SizedBox(height: 12),
                                  Text(nfcId, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: _text)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _profileDetailItem({required IconData icon, required String title, required String value}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: _featuredAvatarBlue, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 12, color: _muted, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _text), overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }

  Widget _header() {
    return LayoutBuilder(builder: (_, c) {
      final narrow = c.maxWidth < 640;
      final title = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Employee Directory', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: _text)),
          const SizedBox(height: 4),
          Text('Manage and monitor ${widget.employees.length} active workforce members.',
              style: const TextStyle(color: _muted, fontSize: 13)),
        ],
      );

      final button = ElevatedButton.icon(
        onPressed: () {
          if (widget.onAddEmployee != null) {
            widget.onAddEmployee!();
          } else {
            setState(() {
              _isAddingEmployee = true;
            });
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: _orange,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
        ),
        icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
        label: const Text('Add New Employee', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
      );

      final wipeButton = ElevatedButton.icon(
        onPressed: () => _confirmWipeAllLogs(),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red.shade600,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
        ),
        icon: const Icon(Icons.delete_sweep_rounded, size: 18),
        label: const Text('Clear All Logs', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
      );

      if (narrow) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          title,
          const SizedBox(height: 14),
          wipeButton,
          const SizedBox(height: 10),
          button,
        ]);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: title),
        wipeButton,
        const SizedBox(width: 12),
        button,
      ]);
    });
  }

  Widget _filterBar(List<String> departments) {
    return LayoutBuilder(builder: (_, c) {
      final narrow = c.maxWidth < 700;
      final search = Container(
        height: 40,
        decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(8), border: Border.all(color: _cardBorder)),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          const Icon(Icons.search_rounded, size: 18, color: _muted),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _filterCtrl,
              onChanged: (v) => setState(() {
                _filterText = v;
                _page = 0;
              }),
              style: const TextStyle(color: _text, fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'Filter by name, role, or ID...',
                hintStyle: TextStyle(color: _muted, fontSize: 13),
                border: InputBorder.none,
                isDense: true,
                filled: true,
                fillColor: _panel,
              ),
            ),
          ),
        ]),
      );

      final deptDropdown = _pillDropdown(
        value: _department,
        items: departments,
        onChanged: (v) => setState(() {
          _department = v ?? 'All Departments';
          _page = 0;
        }),
      );

      final sortDropdown = _pillDropdown(
        value: _sort,
        items: const ['A-Z', 'Z-A'],
        prefix: 'Sort: ',
        onChanged: (v) => setState(() => _sort = v ?? 'A-Z'),
      );

      if (narrow) {
        return Column(children: [
          search,
          const SizedBox(height: 10),
          Row(children: [Expanded(child: deptDropdown), const SizedBox(width: 10), Expanded(child: sortDropdown)]),
        ]);
      }
      return Row(children: [
        Expanded(child: search),
        const SizedBox(width: 12),
        Expanded(child: deptDropdown),
        const SizedBox(width: 12),
        Expanded(child: sortDropdown),
      ]);
    });
  }

  Widget _pillDropdown({
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    String prefix = '',
  }) {
    final safeValue = items.contains(value) ? value : (items.isNotEmpty ? items.first : null);

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _cardBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: safeValue,
          isExpanded: true,
          dropdownColor: Colors.white,
          focusColor: Colors.transparent,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: _muted, size: 18),
          style: const TextStyle(color: _text, fontSize: 13, fontWeight: FontWeight.w500),
          items: items.map((d) {
            return DropdownMenuItem<String>(
              value: d,
              child: Text(
                '$prefix$d',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF1E1E1E),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _directoryGrid(List<Map<String, dynamic>> items, {required bool showQuickInvite}) {
    return LayoutBuilder(builder: (_, c) {
      final cols = c.maxWidth > 900 ? 3 : (c.maxWidth > 600 ? 2 : 1);
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          mainAxisExtent: 320,
        ),
        itemCount: items.length,
        itemBuilder: (_, index) => _employeeCard(items[index]),
      );
    });
  }

  Widget _employeeCard(Map<String, dynamic> emp, {bool showButton = true}) {
    final name = _nameOf(emp);
    final initials = name.trim().isEmpty
        ? '?'
        : name.trim().split(RegExp(r'\s+')).map((p) => p[0]).take(2).join().toUpperCase();
    final role = _s(emp['role'], 'Staff Member');
    final dept = _s(emp['department'], 'General');
    final email = _s(emp['email'], '—');

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 320),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _cardBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: _standardAvatarDark,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: _avatarContent(emp, initials, size: 60, fontSize: 18),
                ),
                const SizedBox(height: 16),
                Text(
                  name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _text),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  role,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _muted, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 20),
                const Spacer(),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.only(top: 14),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: _cardBorder)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('🏢 $dept', style: const TextStyle(color: _muted, fontSize: 12), overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 8),
                      Text('✉ $email', style: const TextStyle(color: _muted, fontSize: 12), overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              _roundedIconButton(
                icon: Icons.assignment_ind_outlined,
                onTap: () => setState(() => _selectedProfileEmp = emp),
                tooltip: 'View Profile',
              ),
              const SizedBox(height: 8),
              _roundedIconButton(
                icon: Icons.phone_outlined,
                onTap: () {
                  final phone = _s(emp['phone'], _s(emp['mobile'], 'No phone registered'));
                  _snack('Contact number: $phone');
                },
                tooltip: 'Contact Employee',
              ),
              const SizedBox(height: 4),
              PopupMenuButton<String>(
                color: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                icon: const Icon(Icons.more_vert_rounded, color: _muted, size: 20),
                onSelected: (v) {
                  if (v == 'profile') {
                    setState(() => _selectedProfileEmp = emp);
                  } else if (v == 'delete') {
                    _confirmDelete(_s(emp['id']), name);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'profile',
                    child: Row(
                      children: [
                        Icon(Icons.person_outline_rounded, size: 16, color: _text),
                        SizedBox(width: 8),
                        Text('View Profile', style: TextStyle(color: _text, fontSize: 13)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline_rounded, size: 16, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Terminate', style: TextStyle(color: Colors.red, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _roundedIconButton({required IconData icon, required VoidCallback onTap, String? tooltip}) {
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFFAFAFA),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Icon(icon, size: 18, color: const Color(0xFF374151)),
          ),
        ),
      ),
    );
  }

  Widget _pagination(int start, int end, int total, int totalPages) {
    return Container(
      padding: const EdgeInsets.only(top: 16),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: _cardBorder))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Showing ${start + 1} to $end of $total employees', style: const TextStyle(color: _muted, fontSize: 12)),
          Row(children: [
            _pageArrow(Icons.chevron_left_rounded, _page > 0, () => setState(() => _page--)),
            const SizedBox(width: 4),
            for (int i = 0; i < totalPages; i++) ...[
              _pageNumber(i),
              if (i != totalPages - 1) const SizedBox(width: 4),
            ],
            const SizedBox(width: 4),
            _pageArrow(Icons.chevron_right_rounded, _page < totalPages - 1, () => setState(() => _page++)),
          ]),
        ],
      ),
    );
  }

  Widget _pageArrow(IconData icon, bool enabled, VoidCallback onTap) => InkWell(
    onTap: enabled ? onTap : null,
    borderRadius: BorderRadius.circular(6),
    child: Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(6), border: Border.all(color: _cardBorder)),
      child: Icon(icon, size: 16, color: enabled ? _text : _muted),
    ),
  );

  Widget _pageNumber(int i) {
    final sel = i == _page;
    return InkWell(
      onTap: () => setState(() => _page = i),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: sel ? _orange : _panel, borderRadius: BorderRadius.circular(6), border: Border.all(color: sel ? _orange : _cardBorder)),
        child: Text('${i + 1}', style: TextStyle(color: sel ? Colors.white : _text, fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    );
  }

  void _openEditDialog(Map<String, dynamic> emp) {
    _editFirstCtrl.text = _s(emp['firstName'], '');
    _editLastCtrl.text = _s(emp['lastName'], '');
    _editRoleCtrl.text = _s(emp['role'], '');
    _editDeptCtrl.text = _s(emp['department'], '');
    _editEmailCtrl.text = _s(emp['email'], '');
    _editPhoneCtrl.text = _s(emp['phone'], _s(emp['mobile'], ''));
    _editPassCtrl.text = _s(emp['password'], '');
    _editKeyfobCtrl.text = _s(emp['nfcId'], _s(emp['nfc_id'], ''));
    _editPinCtrl.text = _s(emp['pin'], '');
    _editPassVis = false;

    setState(() {
      _isEditingEmployee = true;
    });
  }

  void _confirmDelete(String docId, String name) => showDialog(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: Colors.white,
      title: const Text('Confirm Record Deletion'),
      content: Text('Are you sure you want to completely erase the database file for $name? This action cannot be undone.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
          onPressed: () async {
            Navigator.pop(context);
            final err = await AdminDatabase.deleteEmployee(docId);
            if (err != null) {
              _snack('Deletion failed: $err', error: true);
            } else {
              _snack('Profile record deleted.');
              widget.onRefreshNeeded();
            }
          },
          child: const Text('Delete Permanently'),
        ),
      ],
    ),
  );

  void _confirmWipeAllLogs() => showDialog(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: Colors.white,
      title: const Text('Wipe Everything?'),
      content: const Text(
        'This will permanently delete ALL activity, attendance, clock-in/out, leave, and location records. This cannot be undone.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
          onPressed: () async {
            Navigator.pop(context);
            final err = await AdminDatabase.wipeEverything();
            if (err != null) {
              _snack('Wipe failed: $err', error: true);
            } else {
              _snack('All logs cleared.');
              widget.onRefreshNeeded();
            }
          },
          child: const Text('Delete Everything'),
        ),
      ],
    ),
  );

  Widget _emptyState() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(32),
    decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: _cardBorder)),
    child: const Column(children: [
      Icon(Icons.data_usage_rounded, size: 32, color: _muted),
      SizedBox(height: 8),
      Text('No records match search parameters.', style: TextStyle(color: _muted, fontSize: 14)),
    ]),
  );
}