import 'package:flutter/material.dart';

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

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.employeeData['name'] ?? 'Joshua Bantang');
    _emailController = TextEditingController(text: widget.employeeData['email'] ?? 'R.A.C.O.M.A.@gmail.com');
    _birthdayController = TextEditingController(text: widget.employeeData['birthday'] ?? 'September 10, 2004');
    _phoneController = TextEditingController(text: widget.employeeData['phone'] ?? '09312115952');
    _employeeIdController = TextEditingController(text: widget.employeeData['id'] ?? widget.employeeData['employeeId'] ?? 'EMP-2024-024');
    _keyfobController = TextEditingController(text: widget.employeeData['keyfob'] ?? 'SN: 8821-X99-05');
    _pinController = TextEditingController(text: widget.employeeData['pin'] ?? '• • • •');
    _selectedDepartment = widget.employeeData['department'] ?? 'Information Tech Department';
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
      backgroundColor: const Color(0xFFF7F8FA),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(30),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1300),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // BREADCRUMB & TITLE
              const Text(
                'Add New Employee',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFFF8A00)),
              ),
              const SizedBox(height: 4),
              const Text(
                'Edit Employee',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF11142D)),
              ),
              const SizedBox(height: 24),

              // FORM GRID
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // LEFT COLUMN: PROFILE CARD
                  SizedBox(
                    width: 360,
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE1E6ED)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            height: 280,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFE1E6ED)),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                'https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&q=80&w=400',
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text('Profile Identity', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF11142D))),
                          const SizedBox(height: 6),
                          const Text('This photo will be used for digital identification across the portal.', style: TextStyle(fontSize: 12, color: Color(0xFF6C727F), height: 1.4)),
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF9F0),
                              border: Border.all(color: const Color(0xFFFFE0B2)),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text('ℹ️', style: TextStyle(fontSize: 14)),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    "Ensure the employee's name matches their government-issued ID for biometric verification compliance.",
                                    style: TextStyle(fontSize: 11, color: Color(0xFF92400E), height: 1.4),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),

                  // RIGHT COLUMN: INPUT SECTIONS
                  Expanded(
                    child: Column(
                      children: [
                        // PERSONAL INFORMATION CARD
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE1E6ED)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: const [
                                  Text('🗂️', style: TextStyle(fontSize: 15)),
                                  SizedBox(width: 8),
                                  Text('Personal Information', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF11142D))),
                                ],
                              ),
                              const SizedBox(height: 20),
                              Row(
                                children: [
                                  Expanded(child: _buildTextField('FULL NAME', _nameController)),
                                  const SizedBox(width: 16),
                                  Expanded(child: _buildTextField('EMAIL ADDRESS', _emailController)),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(child: _buildTextField('BIRTHDAY', _birthdayController)),
                                  const SizedBox(width: 16),
                                  Expanded(child: _buildTextField('PHONE NO.', _phoneController)),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('DEPARTMENT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF6C727F), letterSpacing: 0.5)),
                                        const SizedBox(height: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 14),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: const Color(0xFFE1E6ED)),
                                          ),
                                          child: DropdownButtonHideUnderline(
                                            child: DropdownButton<String>(
                                              value: _selectedDepartment,
                                              isExpanded: true,
                                              items: ['Information Tech Department', 'Engineering', 'Human Resources'].map((dept) {
                                                return DropdownMenuItem(value: dept, child: Text(dept, style: const TextStyle(fontSize: 13, color: Color(0xFF11142D))));
                                              }).toList(),
                                              onChanged: (val) {
                                                if (val != null) setState(() => _selectedDepartment = val);
                                              },
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(child: _buildTextField('EMPLOYEE ID', _employeeIdController)),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // BIOMETRIC CREDENTIALS CARD
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE1E6ED)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: const [
                                  Text('🔑', style: TextStyle(fontSize: 15)),
                                  SizedBox(width: 8),
                                  Text('Biometric Credentials', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF11142D))),
                                ],
                              ),
                              const SizedBox(height: 20),
                              Row(
                                children: [
                                  Expanded(child: _buildTextField('KEYFOB SERIAL', _keyfobController)),
                                  const SizedBox(width: 16),
                                  Expanded(child: _buildTextField('4-DIGIT PIN', _pinController)),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  _buildBadge('✔', 'NFC Ready'),
                                  const SizedBox(width: 8),
                                  _buildBadge('✔', 'Pin-pad Enabled'),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // ACTION BUTTONS
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFFE1E6ED)),
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: const Text('Cancel', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF11142D))),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton(
                              onPressed: () {
                                // I-save o isumite dito ang mga binagong impormasyon
                                Navigator.pop(context);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFF8A00),
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: const Text('Done', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
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
      ),
    );
  }

  // ================================================================
  // TEXT FIELD
  // ================================================================
  //
  // Placeholder (hint) text = WHITE, shown on a dark box while empty.
  // Typed text = BLACK. The box background switches from dark to
  // white once there's text in the field, so black text stays
  // readable. AnimatedBuilder listens to the controller so this
  // updates live as the user types.
  // ================================================================

  Widget _buildTextField(String label, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF6C727F),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final bool hasText = controller.text.isNotEmpty;

            return TextField(
              controller: controller,

              // TYPED TEXT = BLACK
              style: const TextStyle(
                fontSize: 13,
                color: Colors.black,
                fontWeight: FontWeight.w500,
              ),

              cursorColor: const Color(0xFFFF8A00),

              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),

                // BACKGROUND: dark while empty, white once typed
                filled: true,
                fillColor: hasText ? Colors.white : const Color(0xFF1E1E1E),

                // PLACEHOLDER = WHITE
                hintText: label,
                hintStyle: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                ),

                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: hasText ? const Color(0xFFE1E6ED) : const Color(0xFF1E1E1E),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: hasText ? const Color(0xFFE1E6ED) : const Color(0xFF1E1E1E),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFFF8A00)),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildBadge(String icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE1E6ED)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: const TextStyle(fontSize: 11, color: Color(0xFFD97706))),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF334155))),
        ],
      ),
    );
  }
}