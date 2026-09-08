import 'package:flutter/material.dart';

class AdminUpdateEmployeesPage extends StatefulWidget {
  const AdminUpdateEmployeesPage({Key? key}) : super(key: key);

  @override
  State<AdminUpdateEmployeesPage> createState() =>
      _AdminUpdateEmployeesPageState();
}

class _AdminUpdateEmployeesPageState
    extends State<AdminUpdateEmployeesPage> {
  // ============================================================
  // CONTROLLERS
  // ============================================================

  final TextEditingController _fullNameController =
  TextEditingController(text: 'APRIL');

  final TextEditingController _emailController =
  TextEditingController(text: 'aprilv.deguia@gmail.com');

  final TextEditingController _roleController =
  TextEditingController(text: 'IT/HR');

  final TextEditingController _phoneController =
  TextEditingController();

  final TextEditingController _departmentController =
  TextEditingController();

  final TextEditingController _employeeIdController =
  TextEditingController(text: '6GTNG99JgYjFYOKYbFws');

  final TextEditingController _keyfobController =
  TextEditingController(text: 'SN: 8821-X99-05');

  final TextEditingController _pinController =
  TextEditingController(text: '••••');

  final TextEditingController _searchController =
  TextEditingController();

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _roleController.dispose();
    _phoneController.dispose();
    _departmentController.dispose();
    _employeeIdController.dispose();
    _keyfobController.dispose();
    _pinController.dispose();
    _searchController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: Row(
        children: [
          // ==========================================================
          // SIDEBAR
          // ==========================================================

          Container(
            width: 240,
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(
                right: BorderSide(
                  color: Color(0xFFE1E6ED),
                ),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --------------------------------------------------
                    // BRAND
                    // --------------------------------------------------

                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF8A00),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: const Text(
                              'R',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),

                          const SizedBox(width: 12),

                          Column(
                            crossAxisAlignment:
                            CrossAxisAlignment.start,
                            children: const [
                              Text(
                                'R.A.C.O.M.A.',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFFFF8A00),
                                  letterSpacing: 0.5,
                                ),
                              ),
                              Text(
                                'HRIS',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF6C727F),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // --------------------------------------------------
                    // NAVIGATION
                    // --------------------------------------------------

                    Padding(
                      padding:
                      const EdgeInsets.symmetric(horizontal: 12),
                      child: Column(
                        children: [
                          _buildNavItem(
                            '🏠',
                            'Overview',
                            false,
                          ),
                          _buildNavItem(
                            '👥',
                            'Employees',
                            true,
                          ),
                          _buildNavItem(
                            '➕',
                            'Add Employee',
                            false,
                          ),
                          _buildNavItem(
                            '📅',
                            'Attendance',
                            false,
                          ),
                          _buildNavItem(
                            '🔔',
                            'Activity',
                            false,
                          ),
                          _buildNavItem(
                            '📍',
                            'Tracking',
                            false,
                          ),
                          _buildNavItem(
                            '💰',
                            'Payroll',
                            false,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // ------------------------------------------------------
                // CLOCK SYSTEM STATUS
                // ------------------------------------------------------

                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F4F9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment:
                      MainAxisAlignment.spaceBetween,
                      children: const [
                        Text(
                          'Clock System Status',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF11142D),
                          ),
                        ),
                        CircleAvatar(
                          radius: 4,
                          backgroundColor: Color(0xFF10B981),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ==========================================================
          // MAIN AREA
          // ==========================================================

          Expanded(
            child: Column(
              children: [
                // ======================================================
                // TOP NAVBAR
                // ======================================================

                Container(
                  height: 70,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 30,
                  ),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      bottom: BorderSide(
                        color: Color(0xFFE1E6ED),
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment:
                    MainAxisAlignment.spaceBetween,
                    children: [
                      // LEFT
                      Row(
                        children: const [
                          Text(
                            'R.A.C.O.M.A.',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFFF8A00),
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Admin',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF6C727F),
                            ),
                          ),
                        ],
                      ),

                      // RIGHT
                      Row(
                        children: [
                          // SEARCH
                          Container(
                            width: 220,
                            height: 38,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius:
                              BorderRadius.circular(20),
                              border: Border.all(
                                color: const Color(0xFFE1E6ED),
                              ),
                            ),
                            child: TextField(
                              controller: _searchController,

                              // SEARCH TEXT = BLACK
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.black,
                              ),

                              cursorColor:
                              const Color(0xFFFF8A00),

                              decoration:
                              const InputDecoration(
                                hintText: 'Search logs...',
                                hintStyle: TextStyle(
                                  color: Color(0xFF6C727F),
                                  fontSize: 13,
                                ),
                                prefixIcon: Icon(
                                  Icons.search,
                                  size: 16,
                                  color: Color(0xFF6C727F),
                                ),
                                border: InputBorder.none,
                                contentPadding:
                                EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(width: 16),

                          const Icon(
                            Icons.notifications_outlined,
                            size: 20,
                            color: Color(0xFF6C727F),
                          ),

                          const SizedBox(width: 18),

                          const Icon(
                            Icons.help_outline,
                            size: 20,
                            color: Color(0xFF6C727F),
                          ),

                          const SizedBox(width: 18),

                          Container(
                            width: 32,
                            height: 32,
                            decoration:
                            const BoxDecoration(
                              color: Color(0xFF11142D),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.person,
                              size: 17,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // ======================================================
                // CONTENT BODY
                // ======================================================

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(30),
                    child: Center(
                      child: Container(
                        constraints:
                        const BoxConstraints(
                          maxWidth: 1100,
                        ),
                        child: Column(
                          crossAxisAlignment:
                          CrossAxisAlignment.start,
                          children: [
                            // ------------------------------------------------
                            // BACK TO PROFILE
                            // ------------------------------------------------

                            GestureDetector(
                              onTap: () {
                                Navigator.pop(context);
                              },
                              child: Row(
                                mainAxisSize:
                                MainAxisSize.min,
                                children: const [
                                  Icon(
                                    Icons.arrow_back,
                                    size: 14,
                                    color: Color(0xFF11142D),
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    'Back to Profile',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight:
                                      FontWeight.w600,
                                      color:
                                      Color(0xFF11142D),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 14),

                            // ------------------------------------------------
                            // TITLE
                            // ------------------------------------------------

                            const Text(
                              'Edit Employee',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF11142D),
                              ),
                            ),

                            const SizedBox(height: 20),

                            // =================================================
                            // FORM GRID
                            // =================================================

                            Row(
                              crossAxisAlignment:
                              CrossAxisAlignment.start,
                              children: [
                                // =============================================
                                // LEFT PROFILE CARD
                                // =============================================

                                SizedBox(
                                  width: 320,
                                  child: Container(
                                    padding:
                                    const EdgeInsets.all(20),
                                    decoration:
                                    BoxDecoration(
                                      color: Colors.white,
                                      border: Border.all(
                                        color: const Color(
                                          0xFFE1E6ED,
                                        ),
                                      ),
                                      borderRadius:
                                      BorderRadius.circular(
                                        16,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                      children: [
                                        // PROFILE IMAGE
                                        Container(
                                          width:
                                          double.infinity,
                                          height: 260,
                                          decoration:
                                          BoxDecoration(
                                            color:
                                            const Color(
                                              0xFFE2E8F0,
                                            ),
                                            borderRadius:
                                            BorderRadius
                                                .circular(
                                              12,
                                            ),
                                            border:
                                            Border.all(
                                              color:
                                              const Color(
                                                0xFFE1E6ED,
                                              ),
                                            ),
                                          ),
                                          alignment:
                                          Alignment.center,
                                          child: const Icon(
                                            Icons.person,
                                            size: 90,
                                            color: Color(
                                              0xFF94A3B8,
                                            ),
                                          ),
                                        ),

                                        const SizedBox(
                                          height: 16,
                                        ),

                                        const Text(
                                          'Profile Identity',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight:
                                            FontWeight.w700,
                                            color: Color(
                                              0xFF11142D,
                                            ),
                                          ),
                                        ),

                                        const SizedBox(
                                          height: 6,
                                        ),

                                        const Text(
                                          'This photo will be used for digital identification across the portal.',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Color(
                                              0xFF6C727F,
                                            ),
                                            height: 1.4,
                                          ),
                                        ),

                                        const SizedBox(
                                          height: 16,
                                        ),

                                        // WARNING
                                        Container(
                                          padding:
                                          const EdgeInsets
                                              .all(12),
                                          decoration:
                                          BoxDecoration(
                                            color:
                                            const Color(
                                              0xFFFFF9F0,
                                            ),
                                            border: Border.all(
                                              color:
                                              const Color(
                                                0xFFFFE0B2,
                                              ),
                                            ),
                                            borderRadius:
                                            BorderRadius
                                                .circular(
                                              8,
                                            ),
                                          ),
                                          child: Row(
                                            crossAxisAlignment:
                                            CrossAxisAlignment
                                                .start,
                                            children: const [
                                              Text(
                                                'ℹ️',
                                                style:
                                                TextStyle(
                                                  fontSize: 14,
                                                ),
                                              ),
                                              SizedBox(
                                                width: 10,
                                              ),
                                              Expanded(
                                                child: Text(
                                                  "Ensure the employee's name matches their government-issued ID for biometric verification compliance.",
                                                  style:
                                                  TextStyle(
                                                    fontSize: 11,
                                                    color: Color(
                                                      0xFF92400E,
                                                    ),
                                                    height: 1.4,
                                                  ),
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

                                // =============================================
                                // RIGHT SIDE
                                // =============================================

                                Expanded(
                                  child: Column(
                                    children: [
                                      // =======================================
                                      // PERSONAL INFORMATION
                                      // =======================================

                                      Container(
                                        padding:
                                        const EdgeInsets
                                            .all(24),
                                        decoration:
                                        BoxDecoration(
                                          color: Colors.white,
                                          border: Border.all(
                                            color: const Color(
                                              0xFFE1E6ED,
                                            ),
                                          ),
                                          borderRadius:
                                          BorderRadius
                                              .circular(
                                            16,
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                          CrossAxisAlignment
                                              .start,
                                          children: [
                                            // HEADER
                                            Row(
                                              children: const [
                                                Icon(
                                                  Icons
                                                      .person_outline,
                                                  size: 18,
                                                  color: Color(
                                                    0xFFFF8A00,
                                                  ),
                                                ),
                                                SizedBox(
                                                  width: 8,
                                                ),
                                                Text(
                                                  'Personal Information',
                                                  style:
                                                  TextStyle(
                                                    fontSize: 15,
                                                    fontWeight:
                                                    FontWeight
                                                        .w700,
                                                    color: Color(
                                                      0xFF11142D,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),

                                            const SizedBox(
                                              height: 18,
                                            ),

                                            // ROW 1
                                            Row(
                                              children: [
                                                Expanded(
                                                  child:
                                                  _buildInputGroup(
                                                    'FULL NAME / First Name',
                                                    _fullNameController,
                                                  ),
                                                ),
                                                const SizedBox(
                                                  width: 16,
                                                ),
                                                Expanded(
                                                  child:
                                                  _buildInputGroup(
                                                    'EMAIL ADDRESS',
                                                    _emailController,
                                                  ),
                                                ),
                                              ],
                                            ),

                                            const SizedBox(
                                              height: 14,
                                            ),

                                            // ROW 2
                                            Row(
                                              children: [
                                                Expanded(
                                                  child:
                                                  _buildInputGroup(
                                                    'ROLE / DESIGNATION',
                                                    _roleController,
                                                  ),
                                                ),
                                                const SizedBox(
                                                  width: 16,
                                                ),
                                                Expanded(
                                                  child:
                                                  _buildInputGroup(
                                                    'PHONE NO.',
                                                    _phoneController,
                                                  ),
                                                ),
                                              ],
                                            ),

                                            const SizedBox(
                                              height: 14,
                                            ),

                                            // ROW 3
                                            Row(
                                              children: [
                                                Expanded(
                                                  child:
                                                  _buildInputGroup(
                                                    'DEPARTMENT',
                                                    _departmentController,
                                                  ),
                                                ),
                                                const SizedBox(
                                                  width: 16,
                                                ),
                                                Expanded(
                                                  child:
                                                  _buildInputGroup(
                                                    'EMPLOYEE ID',
                                                    _employeeIdController,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),

                                      const SizedBox(
                                        height: 20,
                                      ),

                                      // =======================================
                                      // BIOMETRIC CREDENTIALS
                                      // =======================================

                                      Container(
                                        padding:
                                        const EdgeInsets
                                            .all(24),
                                        decoration:
                                        BoxDecoration(
                                          color: Colors.white,
                                          border: Border.all(
                                            color: const Color(
                                              0xFFE1E6ED,
                                            ),
                                          ),
                                          borderRadius:
                                          BorderRadius
                                              .circular(
                                            16,
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                          CrossAxisAlignment
                                              .start,
                                          children: [
                                            // HEADER
                                            Row(
                                              children: const [
                                                Icon(
                                                  Icons
                                                      .fingerprint,
                                                  size: 18,
                                                  color: Color(
                                                    0xFFFF8A00,
                                                  ),
                                                ),
                                                SizedBox(
                                                  width: 8,
                                                ),
                                                Text(
                                                  'Biometric Credentials',
                                                  style:
                                                  TextStyle(
                                                    fontSize: 15,
                                                    fontWeight:
                                                    FontWeight
                                                        .w700,
                                                    color: Color(
                                                      0xFF11142D,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),

                                            const SizedBox(
                                              height: 18,
                                            ),

                                            // INPUTS
                                            Row(
                                              children: [
                                                Expanded(
                                                  child:
                                                  _buildInputGroup(
                                                    'KEYFOB SERIAL',
                                                    _keyfobController,
                                                  ),
                                                ),
                                                const SizedBox(
                                                  width: 16,
                                                ),
                                                Expanded(
                                                  child:
                                                  _buildInputGroup(
                                                    '4-DIGIT PIN',
                                                    _pinController,
                                                  ),
                                                ),
                                              ],
                                            ),

                                            const SizedBox(
                                              height: 14,
                                            ),

                                            // BADGES
                                            Row(
                                              children: [
                                                _buildBadge(
                                                  'NFC Ready',
                                                ),
                                                const SizedBox(
                                                  width: 8,
                                                ),
                                                _buildBadge(
                                                  'Pin-pad Enabled',
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),

                                      const SizedBox(
                                        height: 24,
                                      ),

                                      // =======================================
                                      // BUTTONS
                                      // =======================================

                                      Row(
                                        mainAxisAlignment:
                                        MainAxisAlignment
                                            .end,
                                        children: [
                                          // CANCEL
                                          SizedBox(
                                            height: 40,
                                            child:
                                            OutlinedButton(
                                              style:
                                              OutlinedButton
                                                  .styleFrom(
                                                side:
                                                const BorderSide(
                                                  color: Color(
                                                    0xFFE1E6ED,
                                                  ),
                                                ),
                                                padding:
                                                const EdgeInsets
                                                    .symmetric(
                                                  horizontal: 24,
                                                ),
                                                shape:
                                                RoundedRectangleBorder(
                                                  borderRadius:
                                                  BorderRadius
                                                      .circular(
                                                    8,
                                                  ),
                                                ),
                                              ),
                                              onPressed: () {
                                                Navigator.pop(
                                                  context,
                                                );
                                              },
                                              child: const Text(
                                                'Cancel',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight:
                                                  FontWeight
                                                      .w600,
                                                  color: Color(
                                                    0xFF11142D,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),

                                          const SizedBox(
                                            width: 12,
                                          ),

                                          // DONE
                                          SizedBox(
                                            height: 40,
                                            child:
                                            ElevatedButton(
                                              style:
                                              ElevatedButton
                                                  .styleFrom(
                                                backgroundColor:
                                                const Color(
                                                  0xFFFF8A00,
                                                ),
                                                foregroundColor:
                                                Colors.white,
                                                elevation: 0,
                                                padding:
                                                const EdgeInsets
                                                    .symmetric(
                                                  horizontal: 28,
                                                ),
                                                shape:
                                                RoundedRectangleBorder(
                                                  borderRadius:
                                                  BorderRadius
                                                      .circular(
                                                    8,
                                                  ),
                                                ),
                                              ),
                                              onPressed: () {
                                                // SAVE ACTION
                                              },
                                              child: const Text(
                                                'Done',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight:
                                                  FontWeight
                                                      .w600,
                                                  color:
                                                  Colors.white,
                                                ),
                                              ),
                                            ),
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
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ================================================================
  // NAVIGATION ITEM
  // ================================================================

  Widget _buildNavItem(
      String icon,
      String title,
      bool isActive,
      ) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 2,
      ),
      child: Material(
        color: isActive
            ? const Color(0xFFFF8A00)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {},
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            child: Row(
              children: [
                Text(
                  icon,
                  style: const TextStyle(
                    fontSize: 14,
                  ),
                ),

                const SizedBox(width: 12),

                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isActive
                        ? Colors.white
                        : const Color(0xFF6C727F),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ================================================================
  // INPUT GROUP
  // ================================================================
  //
  // Placeholder text = WHITE (shown on the dark box while empty).
  // Typed text = BLACK. Because black text on a black box would be
  // invisible, the box background switches to white once there is
  // text in the field. AnimatedBuilder listens to the controller so
  // the field rebuilds live as the user types.
  // ================================================================

  Widget _buildInputGroup(
      String label,
      TextEditingController controller,
      ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // LABEL
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

        // INPUT
        SizedBox(
          height: 42,
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final bool hasText = controller.text.isNotEmpty;

              return TextField(
                controller: controller,

                // ========================================================
                // TYPED TEXT = BLACK
                // ========================================================

                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.black,
                  fontWeight: FontWeight.w500,
                ),

                cursorColor: const Color(0xFFFF8A00),

                decoration: InputDecoration(
                  // ======================================================
                  // BACKGROUND:
                  // black while empty, white once there's text
                  // (keeps black typed text readable)
                  // ======================================================

                  filled: true,
                  fillColor: hasText
                      ? Colors.white
                      : const Color(0xFF1E1E1E),

                  // ======================================================
                  // PLACEHOLDER = WHITE
                  // ======================================================

                  hintText: label,

                  hintStyle: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                  ),

                  // ======================================================
                  // PADDING
                  // ======================================================

                  contentPadding:
                  const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 0,
                  ),

                  // ======================================================
                  // NORMAL BORDER
                  // ======================================================

                  enabledBorder: OutlineInputBorder(
                    borderRadius:
                    BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: hasText
                          ? const Color(0xFFE1E6ED)
                          : const Color(0xFF1E1E1E),
                      width: 1,
                    ),
                  ),

                  // ======================================================
                  // FOCUSED BORDER
                  // ======================================================

                  focusedBorder: OutlineInputBorder(
                    borderRadius:
                    BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: Color(0xFFFF8A00),
                      width: 1.5,
                    ),
                  ),

                  // ======================================================
                  // ERROR BORDER
                  // ======================================================

                  errorBorder: OutlineInputBorder(
                    borderRadius:
                    BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: Colors.red,
                      width: 1,
                    ),
                  ),

                  // ======================================================
                  // FOCUSED ERROR BORDER
                  // ======================================================

                  focusedErrorBorder:
                  OutlineInputBorder(
                    borderRadius:
                    BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: Colors.red,
                      width: 1.5,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ================================================================
  // BADGE
  // ================================================================

  Widget _buildBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF11142D),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.check,
            size: 14,
            color: Color(0xFF10B981),
          ),

          const SizedBox(width: 6),

          Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}