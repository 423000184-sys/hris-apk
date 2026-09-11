// lib/screens/admin_edit_employee_page.dart
import 'package:flutter/material.dart';
import 'admin_theme.dart';
import '../widgets/bootstrap_grid.dart';

class AdminEditEmployeePage extends StatefulWidget {
  final Map<String, dynamic> employeeData;

  const AdminEditEmployeePage({
    super.key,
    this.employeeData = const {},
  });

  @override
  State<AdminEditEmployeePage> createState() => _AdminEditEmployeePageState();
}

class _AdminEditEmployeePageState extends State<AdminEditEmployeePage> {
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _birthdayController;
  late TextEditingController _phoneController;
  late TextEditingController _employeeIdController;
  late TextEditingController _keyfobController;
  late TextEditingController _pinController;

  String _selectedDepartment = 'Information Tech Department';

  AdminColors get tc => AdminTheme.getColors(context);

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
        text: widget.employeeData['name'] ?? 'Joshua Bantang');
    _emailController = TextEditingController(
        text: widget.employeeData['email'] ?? 'R.A.C.O.M.A.@gmail.com');
    _birthdayController = TextEditingController(
        text: widget.employeeData['birthday'] ?? 'September 10, 2004');
    _phoneController = TextEditingController(
        text: widget.employeeData['phone'] ?? '09312115952');
    _employeeIdController = TextEditingController(
        text: widget.employeeData['id'] ??
            widget.employeeData['employeeId'] ??
            'EMP-2024-024');
    _keyfobController = TextEditingController(
        text: widget.employeeData['keyfob'] ?? 'SN: 8821-X99-05');
    _pinController = TextEditingController(
        text: widget.employeeData['pin'] ?? '• • • •');
    _selectedDepartment = widget.employeeData['department'] ??
        'Information Tech Department';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _birthdayController.dispose();
    _phoneController.dispose();
    _employeeIdController.dispose();
    _keyfobController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: tc.background,
      body: SingleChildScrollView(
        child: BsContainer(
          maxWidth: 1400,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // BREADCRUMB & TITLE
              LayoutBuilder(builder: (_, c) {
                final r = BsResponsive(c.maxWidth);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Add New Employee',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: tc.orange,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Edit Employee',
                      style: TextStyle(
                        fontSize: r.responsive<double>(
                          xs: 22, sm: 24, md: 26, lg: 28,
                        ),
                        fontWeight: FontWeight.w800,
                        color: tc.text,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                );
              }),
              const SizedBox(height: 24),

              // FORM GRID — responsive
              LayoutBuilder(builder: (_, c) {
                final r = BsResponsive(c.maxWidth);
                // Stack below lg (992px) — photo sa taas, form sa baba
                final stack = !r.up(BsSize.lg);

                final photoCard = _buildProfileCard();

                final formColumn = Column(
                  children: [
                    _buildPersonalInfoCard(),
                    const SizedBox(height: 24),
                    _buildBiometricCard(),
                    const SizedBox(height: 24),
                    _buildActionButtons(),
                  ],
                );

                if (stack) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      photoCard,
                      const SizedBox(height: 24),
                      formColumn,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 360, child: photoCard),
                    const SizedBox(width: 24),
                    Expanded(child: formColumn),
                  ],
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // PROFILE CARD (left column)
  // ══════════════════════════════════════════════════════════════
  Widget _buildProfileCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tc.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Photo
          Container(
            height: 240,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: tc.border),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                'https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&q=80&w=400',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: tc.surface,
                  child: Icon(Icons.person, size: 80, color: tc.muted),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Profile Identity',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: tc.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'This photo will be used for digital identification across the portal.',
            style: TextStyle(
              fontSize: 12,
              color: tc.muted,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: tc.orange.withValues(alpha: 0.08),
              border: Border.all(
                color: tc.orange.withValues(alpha: 0.3),
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('ℹ️', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Ensure the employee's name matches their government-issued ID for biometric verification compliance.",
                    style: TextStyle(
                      fontSize: 11,
                      color: tc.orange,
                      height: 1.4,
                    ),
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
  // PERSONAL INFORMATION CARD
  // ══════════════════════════════════════════════════════════════
  Widget _buildPersonalInfoCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tc.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🗂️', style: TextStyle(fontSize: 15)),
              const SizedBox(width: 8),
              Text(
                'Personal Information',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: tc.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Responsive field grid
          LayoutBuilder(builder: (_, c) {
            final narrow = c.maxWidth < 500;
            if (narrow) {
              return Column(
                children: [
                  _buildTextField('FULL NAME', _nameController),
                  const SizedBox(height: 16),
                  _buildTextField('EMAIL ADDRESS', _emailController),
                  const SizedBox(height: 16),
                  _buildTextField('BIRTHDAY', _birthdayController),
                  const SizedBox(height: 16),
                  _buildTextField('PHONE NO.', _phoneController),
                  const SizedBox(height: 16),
                  _buildDepartmentDropdown(),
                  const SizedBox(height: 16),
                  _buildTextField('EMPLOYEE ID', _employeeIdController),
                ],
              );
            }
            return Column(
              children: [
                Row(
                  children: [
                    Expanded(
                        child:
                        _buildTextField('FULL NAME', _nameController)),
                    const SizedBox(width: 16),
                    Expanded(
                        child: _buildTextField(
                            'EMAIL ADDRESS', _emailController)),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                        child: _buildTextField(
                            'BIRTHDAY', _birthdayController)),
                    const SizedBox(width: 16),
                    Expanded(
                        child: _buildTextField(
                            'PHONE NO.', _phoneController)),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: _buildDepartmentDropdown()),
                    const SizedBox(width: 16),
                    Expanded(
                        child: _buildTextField(
                            'EMPLOYEE ID', _employeeIdController)),
                  ],
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildDepartmentDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'DEPARTMENT',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: tc.muted,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: tc.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: tc.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedDepartment,
              isExpanded: true,
              dropdownColor: tc.card,
              icon: Icon(Icons.keyboard_arrow_down_rounded,
                  color: tc.muted, size: 18),
              items: [
                'Information Tech Department',
                'Engineering',
                'Human Resources'
              ].map((dept) {
                return DropdownMenuItem(
                  value: dept,
                  child: Text(
                    dept,
                    style: TextStyle(
                      fontSize: 13,
                      color: tc.text,
                    ),
                  ),
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
  // BIOMETRIC CREDENTIALS CARD
  // ══════════════════════════════════════════════════════════════
  Widget _buildBiometricCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tc.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🔑', style: TextStyle(fontSize: 15)),
              const SizedBox(width: 8),
              Text(
                'Biometric Credentials',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: tc.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          LayoutBuilder(builder: (_, c) {
            final narrow = c.maxWidth < 500;
            if (narrow) {
              return Column(
                children: [
                  _buildTextField('KEYFOB SERIAL', _keyfobController),
                  const SizedBox(height: 16),
                  _buildTextField('4-DIGIT PIN', _pinController),
                ],
              );
            }
            return Row(
              children: [
                Expanded(
                    child: _buildTextField(
                        'KEYFOB SERIAL', _keyfobController)),
                const SizedBox(width: 16),
                Expanded(
                    child: _buildTextField('4-DIGIT PIN', _pinController)),
              ],
            );
          }),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildBadge('✔', 'NFC Ready'),
              _buildBadge('✔', 'Pin-pad Enabled'),
            ],
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // ACTION BUTTONS — stack on xs
  // ══════════════════════════════════════════════════════════════
  Widget _buildActionButtons() {
    return LayoutBuilder(builder: (_, c) {
      final r = BsResponsive(c.maxWidth);
      final narrow = !r.up(BsSize.sm);

      final cancelBtn = OutlinedButton(
        onPressed: () => Navigator.pop(context),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: tc.border),
          padding:
          const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(
          'Cancel',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: tc.text,
          ),
        ),
      );

      final doneBtn = ElevatedButton(
        onPressed: () => Navigator.pop(context),
        style: ElevatedButton.styleFrom(
          backgroundColor: tc.orange,
          foregroundColor: tc.isDark ? tc.onOrange : Colors.white,
          elevation: 0,
          padding:
          const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: const Text(
          'Done',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      );

      if (narrow) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            doneBtn,
            const SizedBox(height: 12),
            cancelBtn,
          ],
        );
      }
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          cancelBtn,
          const SizedBox(width: 12),
          doneBtn,
        ],
      );
    });
  }

  // ══════════════════════════════════════════════════════════════
  // TEXT FIELD — theme-aware
  // ══════════════════════════════════════════════════════════════
  Widget _buildTextField(String label, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: tc.muted,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          style: TextStyle(
            fontSize: 13,
            color: tc.text,
            fontWeight: FontWeight.w500,
          ),
          cursorColor: tc.orange,
          decoration: InputDecoration(
            contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            filled: true,
            fillColor: tc.card,
            hintText: label,
            hintStyle: TextStyle(
              color: tc.muted,
              fontSize: 13,
              fontWeight: FontWeight.w400,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: tc.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: tc.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: tc.orange),
            ),
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════
  // BADGE — theme-aware
  // ══════════════════════════════════════════════════════════════
  Widget _buildBadge(String icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tc.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: tc.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            icon,
            style: TextStyle(fontSize: 11, color: tc.orange),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: tc.text,
            ),
          ),
        ],
      ),
    );
  }
}