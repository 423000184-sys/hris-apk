<<<<<<< HEAD
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
=======
import 'package:flutter/material.dart';
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
import 'admin_database.dart';
import 'admin_theme.dart';

class AdminAddEmployeePage extends StatefulWidget {
  final VoidCallback onRefreshNeeded;

  const AdminAddEmployeePage({super.key, required this.onRefreshNeeded});

  @override
  State<AdminAddEmployeePage> createState() => _AdminAddEmployeePageState();
}

class _AdminAddEmployeePageState extends State<AdminAddEmployeePage> {
  final _fKey = GlobalKey<FormState>();
<<<<<<< HEAD
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _birthdayCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _deptCtrl = TextEditingController();
  final _idCtrl = TextEditingController();
  final _nfcCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  bool _saving = false;

  Uint8List? _profileImageBytes;

  static const Color _bg = Color(0xFFF8F9FA);
  static const Color _cardBorder = Color(0xFFEBEAE6);
  static const Color _orange = Color(0xFFFF7A00);
  static const Color _textDark = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _birthdayCtrl.dispose();
    _phoneCtrl.dispose();
    _deptCtrl.dispose();
    _idCtrl.dispose();
    _nfcCtrl.dispose();
    _pinCtrl.dispose();
=======
  final _firstCtrl = TextEditingController();
  final _lastCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _roleCtrl = TextEditingController();
  final _deptCtrl = TextEditingController();
  final _nfcCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _saving = false;
  bool _passVis = false;

  @override
  void dispose() {
    _firstCtrl.dispose(); _lastCtrl.dispose(); _emailCtrl.dispose(); _roleCtrl.dispose();
    _deptCtrl.dispose(); _nfcCtrl.dispose(); _pinCtrl.dispose(); _passCtrl.dispose();
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
    super.dispose();
  }

  void _snack(String msg, {bool error = false}) {
<<<<<<< HEAD
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? AdminTheme.red : AdminTheme.green,
      ),
    );
  }

  String _getInitials(String firstName, String lastName) {
    String f = firstName.isNotEmpty ? firstName[0].toUpperCase() : '';
    String l = lastName.isNotEmpty ? lastName[0].toUpperCase() : '';
    return '$f$l'.isEmpty ? 'E' : '$f$l';
=======
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: error ? AdminTheme.red : AdminTheme.green));
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
  }

  @override
  Widget build(BuildContext context) {
<<<<<<< HEAD
    return Scaffold(
      backgroundColor: _bg,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _snack('Print report initiated...'),
        backgroundColor: _orange,
        child: const Icon(Icons.print, color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Add Employee',
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: _textDark),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Real-time verification of professional shifts and geofencing status.',
                      style: TextStyle(fontSize: 13, color: _muted),
                    ),
                  ],
                ),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _snack('CSV Exported'),
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
                      onPressed: _openAddDialog,
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Manual Entry'),
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
            Container(
              width: 320,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'DATE RANGE',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _muted, letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: const [
                        Text('Sept 1, 2025 - Sept 16, 2025', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: _textDark)),
                        Icon(Icons.calendar_month, size: 18, color: _muted),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _cardBorder),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFAFAFA),
                      border: Border(bottom: BorderSide(color: _cardBorder)),
                    ),
                    child: Row(
                      children: const [
                        Expanded(flex: 3, child: Text('EMPLOYEE NAME', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _muted))),
                        Expanded(flex: 2, child: Text('ROLE / DEPT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _muted))),
                        SizedBox(width: 50, child: Text('ACTIONS', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _muted))),
                      ],
                    ),
                  ),
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: AdminDatabase.getEmployees(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.all(32.0),
                          child: Center(child: CircularProgressIndicator(color: _orange)),
                        );
                      }

                      if (snapshot.hasError) {
                        return Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Text('Error loading employees: ${snapshot.error}', style: const TextStyle(color: Colors.red)),
                        );
                      }

                      final employees = snapshot.data ?? [];

                      if (employees.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.all(32.0),
                          child: Center(
                            child: Text('No registered employees found in database.', style: TextStyle(color: _muted)),
                          ),
                        );
                      }

                      return Column(
                        children: employees.map((emp) {
                          final firstName = emp['firstName'] ?? emp['first_name'] ?? '';
                          final lastName = emp['lastName'] ?? emp['last_name'] ?? '';
                          final fullName = '$firstName $lastName'.trim().isEmpty ? (emp['name'] ?? 'Unknown Staff') : '$firstName $lastName';
                          final empId = emp['nfcTagId'] ?? emp['id'] ?? 'N/A';
                          final role = emp['role'] ?? 'Staff';
                          final dept = emp['department'] ?? 'General';
                          final initials = _getInitials(firstName, lastName);

                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                            decoration: const BoxDecoration(
                              border: Border(bottom: BorderSide(color: _cardBorder)),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 18,
                                        backgroundColor: const Color(0xFFFFEDD5),
                                        child: Text(
                                          initials,
                                          style: const TextStyle(color: Color(0xFFEA580C), fontSize: 12, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(fullName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _textDark)),
                                          Text('NFC: $empId', style: const TextStyle(fontSize: 11, color: _muted)),
                                        ],
                                      )
                                    ],
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text('$role ($dept)', style: const TextStyle(fontSize: 13, color: _textDark)),
                                ),
                                SizedBox(
                                  width: 50,
                                  child: IconButton(
                                    alignment: Alignment.centerRight,
                                    icon: const Icon(Icons.more_vert, color: _muted, size: 18),
                                    onPressed: () {},
                                  ),
                                )
                              ],
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    color: const Color(0xFFFAFAFA),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('System Records Active', style: TextStyle(fontSize: 12, color: _muted)),
                        Row(
                          children: [
                            _pageBtn(Icons.chevron_left, false),
                            _pageNumberBtn('1', true),
                            _pageBtn(Icons.chevron_right, false),
                          ],
                        )
                      ],
                    ),
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openAddDialog() {
    _profileImageBytes = null;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 960),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F6F4),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _cardBorder),
            ),
            child: SingleChildScrollView(
              child: Form(
                key: _fKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Add New Employee',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _orange),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Employee Registration',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Onboard a new team member and configure their biometric access credentials.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 20),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        if (constraints.maxWidth > 750) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(width: 280, child: _buildProfileCard(setS)),
                              const SizedBox(width: 20),
                              Expanded(child: _buildRightColumn()),
                            ],
                          );
                        } else {
                          return Column(
                            children: [
                              _buildProfileCard(setS),
                              const SizedBox(height: 16),
                              _buildRightColumn(),
                            ],
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF475569),
                            side: const BorderSide(color: Color(0xFFCBD5E1)),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Cancel', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: _saving
                              ? null
                              : () async {
                            if (!_fKey.currentState!.validate()) return;
                            setS(() => _saving = true);

                            // ---- try/catch added: prevents the dialog from
                            // hanging on "saving" forever if AdminDatabase
                            // throws (network drop, Firestore rules, etc.)
                            // instead of just returning an error string, and
                            // guarantees the loading state always resets.
                            try {
                              final fullName = _nameCtrl.text.trim();
                              final parts = fullName.split(' ');
                              final firstName = parts.isNotEmpty ? parts.first : fullName;
                              final lastName = parts.length > 1 ? parts.sublist(1).join(' ') : 'Doe';

                              final err = await AdminDatabase.addEmployee(
                                firstName: firstName,
                                lastName: lastName,
                                email: _emailCtrl.text.trim(),
                                password: 'password123',
                                role: 'Staff',
                                department: _deptCtrl.text.trim(),
                                nfcTagId: _nfcCtrl.text.trim(),
                                pin: _pinCtrl.text.trim(),
                              );

                              if (!mounted) return;

                              if (err != null) {
                                // Handled error string returned by AdminDatabase
                                _snack(err, error: true);
                              } else {
                                Navigator.pop(ctx);
                                _snack('Employee saved & credentials deployed successfully!');
                                // Rebuild -> FutureBuilder above re-calls
                                // AdminDatabase.getEmployees(), so the new
                                // employee is pulled fresh from Firestore.
                                setState(() {});
                                // Tells the parent (Admin Employees page) to
                                // refresh its own list too, so the new hire
                                // shows up there permanently, not just here.
                                widget.onRefreshNeeded();
                              }
                            } catch (e) {
                              // Unhandled exception from the database call
                              if (!mounted) return;
                              _snack('Failed to add employee: $e', error: true);
                            } finally {
                              if (mounted) setS(() => _saving = false);
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _orange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            elevation: 0,
                          ),
                          child: _saving
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : const Text('Complete Onboarding', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileCard(StateSetter setS) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () async {
              FilePickerResult? result = await FilePicker.platform.pickFiles(
                type: FileType.image,
                allowMultiple: false,
              );

              if (result != null && result.files.single.bytes != null) {
                setS(() {
                  _profileImageBytes = result.files.single.bytes;
                });
                _snack('Profile picture updated successfully!');
              }
            },
            child: Container(
              width: double.infinity,
              height: 220,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: const Color(0xFFF3F4F6),
                image: _profileImageBytes != null
                    ? DecorationImage(
                  image: MemoryImage(_profileImageBytes!),
                  fit: BoxFit.cover,
                )
                    : null,
              ),
              child: Stack(
                children: [
                  if (_profileImageBytes == null)
                    const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.person_outline, size: 56, color: Color(0xFF9CA3AF)),
                          SizedBox(height: 8),
                          Text(
                            'Upload Photo',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF6B7280)),
                          ),
                        ],
                      ),
                    ),
                  const Positioned(
                    bottom: 8,
                    right: 8,
                    child: CircleAvatar(
                      backgroundColor: Colors.black54,
                      radius: 16,
                      child: Icon(Icons.camera_alt, color: Colors.white, size: 16),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text('Profile Identity', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _textDark)),
          const SizedBox(height: 4),
          const Text('Click image to upload/change employee photo.', style: TextStyle(fontSize: 11, color: _muted, height: 1.3)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Icon(Icons.info_outline, size: 14, color: Color(0xFF92400E)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Ensure the employee's name matches their government-issued ID for biometric verification compliance.",
                    style: TextStyle(fontSize: 10, color: Color(0xFF92400E), fontWeight: FontWeight.w500, height: 1.3),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightColumn() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(Icons.badge_outlined, size: 16, color: _orange),
                  SizedBox(width: 8),
                  Text('Personal Information', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _textDark)),
                ],
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  bool isWide = constraints.maxWidth > 400;
                  return Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: _buildInput('FULL NAME', _nameCtrl, 'Full Name')),
                          if (isWide) const SizedBox(width: 12),
                          if (isWide) Expanded(child: _buildInput('EMAIL ADDRESS', _emailCtrl, 'Email Address')),
                        ],
                      ),
                      if (!isWide) ...[
                        const SizedBox(height: 12),
                        _buildInput('EMAIL ADDRESS', _emailCtrl, 'Email Address'),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: _buildInput('BIRTHDAY', _birthdayCtrl, 'Birthday')),
                          if (isWide) const SizedBox(width: 12),
                          if (isWide) Expanded(child: _buildInput('PHONE NO.', _phoneCtrl, 'Phone No.')),
                        ],
                      ),
                      if (!isWide) ...[
                        const SizedBox(height: 12),
                        _buildInput('PHONE NO.', _phoneCtrl, 'Phone No.'),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: _buildInput('DEPARTMENT', _deptCtrl, 'Department')),
                          if (isWide) const SizedBox(width: 12),
                          if (isWide) Expanded(child: _buildInput('EMPLOYEE ID', _idCtrl, 'Employee ID')),
                        ],
                      ),
                      if (!isWide) ...[
                        const SizedBox(height: 12),
                        _buildInput('EMPLOYEE ID', _idCtrl, 'Employee ID'),
                      ],
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
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(Icons.fingerprint, size: 16, color: _orange),
                  SizedBox(width: 8),
                  Text('Biometric Credentials', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _textDark)),
                ],
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  bool isWide = constraints.maxWidth > 400;
                  return Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: _buildInput('KEYFOB SERIAL', _nfcCtrl, 'Keyfob Serial', suffixIcon: Icons.wifi)),
                          if (isWide) const SizedBox(width: 12),
                          if (isWide) Expanded(child: _buildInput('4-DIGIT PIN', _pinCtrl, '4-Digit PIN', obscure: true)),
                        ],
                      ),
                      if (!isWide) ...[
                        const SizedBox(height: 12),
                        _buildInput('4-DIGIT PIN', _pinCtrl, '4-Digit PIN', obscure: true),
                      ],
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildBadge('NFC Ready'),
                  const SizedBox(width: 8),
                  _buildBadge('Pin-pad Enabled'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInput(String label, TextEditingController controller, String hint, {bool obscure = false, IconData? suffixIcon}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF475569), letterSpacing: 0.5)),
        const SizedBox(height: 4),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          validator: (v) => v == null || v.isEmpty ? 'Required' : null,
          style: const TextStyle(fontSize: 12, color: Color(0xFF334155), fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: _muted),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            suffixIcon: suffixIcon != null ? Icon(suffixIcon, size: 14, color: const Color(0xFF64748B)) : null,
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: _orange, width: 1.5)),
            errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Colors.red, width: 1.5)),
            focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Colors.red, width: 1.5)),
          ),
        ),
      ],
    );
  }

  Widget _buildBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, size: 10, color: _orange),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Color(0xFF475569))),
        ],
      ),
    );
  }

  Widget _pageBtn(IconData icon, bool active) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 2),
    width: 28,
    height: 28,
    decoration: BoxDecoration(color: active ? _orange : Colors.transparent, borderRadius: BorderRadius.circular(6)),
    child: Icon(icon, size: 16, color: active ? Colors.white : _muted),
  );

  Widget _pageNumberBtn(String text, bool active) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 2),
    width: 28,
    height: 28,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: active ? _orange : Colors.transparent, borderRadius: BorderRadius.circular(6)),
    child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: active ? Colors.white : _textDark)),
  );
=======
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AdminTheme.s4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Register New Staff', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AdminTheme.text, letterSpacing: -0.3)),
        const SizedBox(height: AdminTheme.s4),
        Form(
          key: _fKey,
          child: Container(
            decoration: AdminTheme.card(),
            padding: const EdgeInsets.all(AdminTheme.s5),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextFormField(controller: _firstCtrl, decoration: const InputDecoration(labelText: 'First Name *'), validator: (v) => v!.isEmpty ? 'Field required' : null),
              TextFormField(controller: _lastCtrl, decoration: const InputDecoration(labelText: 'Last Name *'), validator: (v) => v!.isEmpty ? 'Field required' : null),
              TextFormField(controller: _emailCtrl, decoration: const InputDecoration(labelText: 'Email Address *'), validator: (v) => v!.contains('@') ? null : 'Provide valid email'),
              TextFormField(controller: _roleCtrl, decoration: const InputDecoration(labelText: 'Role / Designation *'), validator: (v) => v!.isEmpty ? 'Field required' : null),
              TextFormField(controller: _deptCtrl, decoration: const InputDecoration(labelText: 'Department *'), validator: (v) => v!.isEmpty ? 'Field required' : null),
              const SizedBox(height: AdminTheme.s3),
              TextFormField(controller: _nfcCtrl, decoration: const InputDecoration(labelText: 'Keyfob NFC Serial *'), validator: (v) => v!.isEmpty ? 'Field required' : null),
              TextFormField(controller: _pinCtrl, decoration: const InputDecoration(labelText: 'Backup Auth Security PIN *'), keyboardType: TextInputType.number, validator: (v) => v!.length >= 4 ? null : 'Minimum 4 digits required'),
              TextFormField(
                controller: _passCtrl,
                obscureText: !_passVis,
                decoration: InputDecoration(
                  labelText: 'Portal Password Setup *',
                  suffixIcon: IconButton(icon: Icon(_passVis ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => _passVis = !_passVis)),
                ),
                validator: (v) => v!.length >= 6 ? null : 'Minimum 6 character password required',
              ),
              const SizedBox(height: AdminTheme.s5),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: AdminTheme.orange, foregroundColor: AdminTheme.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                  icon: const Icon(Icons.person_add_rounded),
                  label: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: AdminTheme.white, strokeWidth: 2)) : const Text('Write Employee to Registry', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: _saving ? null : _submitAdd,
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Future<void> _submitAdd() async {
    if (!_fKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final err = await AdminDatabase.addEmployee(
      firstName: _firstCtrl.text.trim(),
      lastName: _lastCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      password: _passCtrl.text.trim(),
      role: _roleCtrl.text.trim(),
      department: _deptCtrl.text.trim(),
      nfcTagId: _nfcCtrl.text.trim(),
      pin: _pinCtrl.text.trim(),
    );

    setState(() => _saving = false);
    if (err != null) {
      _snack(err, error: true);
    } else {
      for (final c in [_firstCtrl, _lastCtrl, _emailCtrl, _roleCtrl, _deptCtrl, _nfcCtrl, _pinCtrl, _passCtrl]) {
        c.clear();
      }
      _snack('Employee saved & credentials deployed to Firebase Auth module!');
      widget.onRefreshNeeded();
    }
  }
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
}