import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

// ============================================================
// R.A.C.O.M.A. Admin — Create Leave Request
// ============================================================

const Color kOrange = Color(0xFFFF7A00);
const Color kOrangeLight = Color(0xFFFFF7ED);
const Color kBg = Color(0xFFF8F9FA);
const Color kBorder = Color(0xFFEBEAE6);
const Color kTextDark = Color(0xFF111827);
const Color kTextGray = Color(0xFF6B7280);
const Color kTextGray2 = Color(0xFF374151);
const Color kGreen = Color(0xFF16A34A);

class AdminCreateLeaveRequestPage extends StatefulWidget {
  final List<Map<String, dynamic>> employees;
  final VoidCallback? onBack;

  const AdminCreateLeaveRequestPage({
    super.key,
    this.employees = const [],
    this.onBack,
  });

  @override
  State<AdminCreateLeaveRequestPage> createState() =>
      _AdminCreateLeaveRequestPageState();
}

class _AdminCreateLeaveRequestPageState
    extends State<AdminCreateLeaveRequestPage> {
  // ============================================================
  // TEXT CONTROLLERS
  // ============================================================

  final TextEditingController _nameController =
  TextEditingController();

  final TextEditingController _positionController =
  TextEditingController();

  final TextEditingController _departmentController =
  TextEditingController();

  final TextEditingController _relieverController =
  TextEditingController();

  final TextEditingController _fromDateController =
  TextEditingController();

  final TextEditingController _toDateController =
  TextEditingController();

  final TextEditingController _daysController =
  TextEditingController(text: "0");

  final TextEditingController _hoursController =
  TextEditingController(text: "0");

  final TextEditingController _returnDateController =
  TextEditingController();

  final TextEditingController _returnTimeController =
  TextEditingController();

  final TextEditingController _reasonController =
  TextEditingController();

  // ============================================================
  // DATE / TIME VALUES
  // ============================================================

  DateTime? _dateFrom;
  DateTime? _dateTo;
  DateTime? _returnDate;
  TimeOfDay? _returnTime;

  double _totalDays = 0;
  double _totalHours = 0;

  // ============================================================
  // LEAVE TYPES
  // ============================================================

  final List<Map<String, String>> _leaveTypes = const [
    {
      "code": "SL",
      "desc": "Sick Leave",
    },
    {
      "code": "VL",
      "desc": "Vacation Leave",
    },
    {
      "code": "EL",
      "desc": "Emergency",
    },
    {
      "code": "BL",
      "desc": "Bereavement",
    },
    {
      "code": "ML",
      "desc": "Maternity/Paternity",
    },
    {
      "code": "Others",
      "desc": "Specify below",
    },
  ];

  String _selectedLeaveType = "SL";

  // ============================================================
  // EMPLOYEE
  // ============================================================

  String? _selectedEmployeeId;

  bool _isSubmitting = false;

  // ============================================================
  // EMPLOYEE NAME HELPER
  // ============================================================

  String _empName(Map<String, dynamic> employee) {
    final dynamic name = employee['name'];

    if (name != null && name.toString().trim().isNotEmpty) {
      return name.toString().trim();
    }

    final String first =
    (employee['firstName'] ?? '').toString().trim();

    final String last =
    (employee['lastName'] ?? '').toString().trim();

    final String fullName =
    '$first $last'.trim();

    return fullName.isEmpty
        ? 'Unknown'
        : fullName;
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _nameController.dispose();
    _positionController.dispose();
    _departmentController.dispose();
    _relieverController.dispose();
    _fromDateController.dispose();
    _toDateController.dispose();
    _daysController.dispose();
    _hoursController.dispose();
    _returnDateController.dispose();
    _returnTimeController.dispose();
    _reasonController.dispose();

    super.dispose();
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kBg,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildBackLink(),

            const SizedBox(height: 8),

            _buildPageHeading(),

            const SizedBox(height: 24),

            _buildFormCard(),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // BACK LINK
  // ============================================================

  Widget _buildBackLink() {
    return InkWell(
      onTap: widget.onBack ??
              () {
            Navigator.of(context).maybePop();
          },
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.arrow_back,
            size: 14,
            color: kOrange,
          ),
          SizedBox(width: 6),
          Text(
            "Back to Activity & Leave",
            style: TextStyle(
              color: kOrange,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // PAGE HEADING
  // ============================================================

  Widget _buildPageHeading() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Create Leave Request",
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: kTextDark,
          ),
        ),
        SizedBox(height: 2),
        Text(
          "Application for Leave of Absence",
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: kOrange,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // FORM CARD
  // ============================================================

  Widget _buildFormCard() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(
          color: kBorder,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // INSTRUCTION
          _buildInstructionBox(),

          const SizedBox(height: 24),

          // EMPLOYEE INFORMATION
          _sectionLabel(
            "EMPLOYEE INFORMATION",
          ),

          const SizedBox(height: 16),

          _buildEmployeeInformation(),

          const SizedBox(height: 32),

          // LEAVE DETAILS
          _sectionLabel(
            "LEAVE DETAILS",
          ),

          const SizedBox(height: 16),

          _buildLeaveDetails(),

          const SizedBox(height: 20),

          // RETURN TO WORK
          _buildReturnToWork(),

          const SizedBox(height: 32),

          // LEAVE APPLIED FOR
          _sectionLabel(
            "LEAVE APPLIED FOR",
          ),

          const SizedBox(height: 16),

          _buildLeaveTypes(),

          const SizedBox(height: 20),

          // REASON
          _buildReasonField(),

          const SizedBox(height: 28),

          // SUBMIT
          _buildSubmitButton(),
        ],
      ),
    );
  }

  // ============================================================
  // INSTRUCTION BOX
  // ============================================================

  Widget _buildInstructionBox() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 14,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4FF),
        borderRadius: BorderRadius.circular(6),
        border: const Border(
          left: BorderSide(
            color: kOrange,
            width: 4,
          ),
        ),
      ),
      child: const Text(
        "INSTRUCTION: This form should be filled out BEFORE an "
            "employee goes on leave. In case of emergency or illness, "
            "this form must be filled out IMMEDIATELY upon return for "
            "work. Sick leave applications will only be honored "
            "provided it is a duty certified by licensed Physician.",
        style: TextStyle(
          fontSize: 12,
          height: 1.5,
          color: Colors.black,
        ),
      ),
    );
  }

  // ============================================================
  // SECTION LABEL
  // ============================================================

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        color: kOrange,
        letterSpacing: 0.5,
      ),
    );
  }

  // ============================================================
  // EMPLOYEE INFORMATION
  // ============================================================

  Widget _buildEmployeeInformation() {
    return _ResponsiveGrid(
      children: [
        _labeledField(
          "Name of Employee",
          _buildNameField(),
        ),

        _labeledField(
          "Designation / Position",
          _textField(
            _positionController,
            "Enter job title",
          ),
        ),

        _labeledField(
          "Section / Department",
          _textField(
            _departmentController,
            "Enter department",
          ),
        ),

        _labeledField(
          "Name of Reliever (Optional)",
          _textField(
            _relieverController,
            "Who will cover your duties?",
          ),
        ),
      ],
    );
  }

  // ============================================================
  // NAME FIELD
  //
  // ADMIN CAN TYPE THE NAME.
  // If the typed name matches an employee from the list,
  // the employee document ID is automatically detected.
  // ============================================================

  Widget _buildNameField() {
    return TextField(
      controller: _nameController,
      style: const TextStyle(
        fontSize: 13,
        color: kTextDark,
      ),
      decoration: _inputDecoration(
        "Enter full name",
      ),
      onChanged: (value) {
        _tryFindEmployee(value);
      },
    );
  }

  // ============================================================
  // FIND EMPLOYEE FROM TYPED NAME
  // ============================================================

  void _tryFindEmployee(String value) {
    final String typedName =
    value.trim().toLowerCase();

    if (typedName.isEmpty) {
      setState(() {
        _selectedEmployeeId = null;
      });
      return;
    }

    for (final employee in widget.employees) {
      final String employeeName =
      _empName(employee).trim().toLowerCase();

      if (employeeName == typedName) {
        setState(() {
          _selectedEmployeeId =
              (employee['id'] ?? '').toString();
        });

        return;
      }
    }

    setState(() {
      _selectedEmployeeId = null;
    });
  }

  // ============================================================
  // LEAVE DETAILS
  // ============================================================

  Widget _buildLeaveDetails() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(
          color: const Color(0xFFE2E8F0),
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: _ResponsiveGrid(
        children: [
          // ------------------------------------------------------
          // INCLUSIVE DATES
          // ------------------------------------------------------

          _labeledField(
            "Inclusive Dates",
            Row(
              children: [
                Expanded(
                  child: _editableDateField(
                    label: "From",
                    controller:
                    _fromDateController,
                    onDateSelected: (date) {
                      setState(() {
                        _dateFrom = date;
                        _fromDateController.text =
                            _fmtDate(date);
                      });

                      _calculateTotalDays();
                    },
                  ),
                ),

                const SizedBox(width: 10),

                Expanded(
                  child: _editableDateField(
                    label: "To",
                    controller:
                    _toDateController,
                    onDateSelected: (date) {
                      setState(() {
                        _dateTo = date;
                        _toDateController.text =
                            _fmtDate(date);
                      });

                      _calculateTotalDays();
                    },
                  ),
                ),
              ],
            ),
          ),

          // ------------------------------------------------------
          // TOTAL TIME OUT
          // ------------------------------------------------------

          _labeledField(
            "Total Time Out",
            Row(
              children: [
                Expanded(
                  child: _numberField(
                    "Days",
                    _daysController,
                    onChanged: (value) {
                      setState(() {
                        _totalDays =
                            double.tryParse(value) ?? 0;
                      });
                    },
                  ),
                ),

                const SizedBox(width: 10),

                Expanded(
                  child: _numberField(
                    "Hours",
                    _hoursController,
                    onChanged: (value) {
                      setState(() {
                        _totalHours =
                            double.tryParse(value) ?? 0;
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // EDITABLE DATE FIELD
  // ============================================================

  Widget _editableDateField({
    required String label,
    required TextEditingController controller,
    required void Function(DateTime) onDateSelected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: kTextGray,
          ),
        ),

        const SizedBox(height: 4),

        TextField(
          controller: controller,
          keyboardType: TextInputType.datetime,
          style: const TextStyle(
            fontSize: 13,
            color: kTextDark,
          ),
          decoration: _inputDecoration(
            "mm/dd/yyyy",
            suffixIcon: IconButton(
              tooltip: "Select date",
              icon: const Icon(
                Icons.calendar_today_outlined,
                size: 18,
              ),
              onPressed: () {
                _pickDate(
                  onDateSelected,
                );
              },
            ),
          ),
          onChanged: (value) {
            final date =
            _parseDate(value);

            if (date != null) {
              if (controller ==
                  _fromDateController) {
                _dateFrom = date;
              }

              if (controller ==
                  _toDateController) {
                _dateTo = date;
              }

              _calculateTotalDays();
            }
          },
        ),
      ],
    );
  }

  // ============================================================
  // DATE PICKER
  // ============================================================

  Future<void> _pickDate(
      void Function(DateTime) onPicked,
      ) async {
    final DateTime initialDate =
    DateTime.now();

    final DateTime? picked =
    await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (picked != null) {
      onPicked(picked);
    }
  }

  // ============================================================
  // DATE PARSER
  // ============================================================

  DateTime? _parseDate(String value) {
    final String input = value.trim();

    if (input.isEmpty) {
      return null;
    }

    final RegExp regex =
    RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$');

    final Match? match =
    regex.firstMatch(input);

    if (match == null) {
      return null;
    }

    final int? month =
    int.tryParse(match.group(1)!);

    final int? day =
    int.tryParse(match.group(2)!);

    final int? year =
    int.tryParse(match.group(3)!);

    if (month == null ||
        day == null ||
        year == null) {
      return null;
    }

    try {
      final DateTime date =
      DateTime(year, month, day);

      if (date.year != year ||
          date.month != month ||
          date.day != day) {
        return null;
      }

      return date;
    } catch (_) {
      return null;
    }
  }

  // ============================================================
  // CALCULATE DAYS
  // ============================================================

  void _calculateTotalDays() {
    if (_dateFrom == null ||
        _dateTo == null) {
      return;
    }

    if (_dateTo!.isBefore(_dateFrom!)) {
      setState(() {
        _totalDays = 0;
        _daysController.text = "0";
      });

      return;
    }

    final int days =
        _dateTo!
            .difference(_dateFrom!)
            .inDays +
            1;

    setState(() {
      _totalDays = days.toDouble();

      _daysController.text =
          days.toString();
    });
  }

  // ============================================================
  // RETURN TO WORK
  // ============================================================

  Widget _buildReturnToWork() {
    return _ResponsiveGrid(
      children: [
        _labeledField(
          "Return to Work Date",
          _buildReturnDateField(),
        ),

        _labeledField(
          "Return to Work Time",
          _buildReturnTimeField(),
        ),
      ],
    );
  }

  // ============================================================
  // RETURN DATE
  // ============================================================

  Widget _buildReturnDateField() {
    return TextField(
      controller: _returnDateController,
      keyboardType: TextInputType.datetime,
      style: const TextStyle(
        fontSize: 13,
        color: kTextDark,
      ),
      decoration: _inputDecoration(
        "mm/dd/yyyy",
        suffixIcon: IconButton(
          tooltip: "Select date",
          icon: const Icon(
            Icons.calendar_today_outlined,
            size: 18,
          ),
          onPressed: () {
            _pickDate(
                  (date) {
                setState(() {
                  _returnDate = date;

                  _returnDateController.text =
                      _fmtDate(date);
                });
              },
            );
          },
        ),
      ),
      onChanged: (value) {
        _returnDate =
            _parseDate(value);
      },
    );
  }

  // ============================================================
  // RETURN TIME
  // ============================================================

  Widget _buildReturnTimeField() {
    return TextField(
      controller: _returnTimeController,
      keyboardType: TextInputType.datetime,
      style: const TextStyle(
        fontSize: 13,
        color: kTextDark,
      ),
      decoration: _inputDecoration(
        "--:--",
        suffixIcon: IconButton(
          tooltip: "Select time",
          icon: const Icon(
            Icons.access_time_outlined,
            size: 18,
          ),
          onPressed: () {
            _pickTime();
          },
        ),
      ),
      onChanged: (value) {
        _returnTime =
            _parseTime(value);
      },
    );
  }

  // ============================================================
  // TIME PICKER
  // ============================================================

  Future<void> _pickTime() async {
    final TimeOfDay? picked =
    await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );

    if (picked != null) {
      setState(() {
        _returnTime = picked;

        _returnTimeController.text =
            picked.format(context);
      });
    }
  }

  // ============================================================
  // TIME PARSER
  // ============================================================

  TimeOfDay? _parseTime(String value) {
    final String input =
    value.trim().toLowerCase();

    if (input.isEmpty) {
      return null;
    }

    // Supports:
    // 8:00
    // 08:00
    // 8:00 AM
    // 08:30 PM

    final RegExp regex = RegExp(
      r'^(\d{1,2}):(\d{2})(?:\s*(am|pm))?$',
      caseSensitive: false,
    );

    final Match? match =
    regex.firstMatch(input);

    if (match == null) {
      return null;
    }

    int hour =
        int.tryParse(match.group(1)!) ?? -1;

    final int minute =
        int.tryParse(match.group(2)!) ?? -1;

    final String? period =
    match.group(3)?.toLowerCase();

    if (minute < 0 || minute > 59) {
      return null;
    }

    if (period != null) {
      if (hour < 1 || hour > 12) {
        return null;
      }

      if (period == "pm" && hour != 12) {
        hour += 12;
      }

      if (period == "am" && hour == 12) {
        hour = 0;
      }
    } else {
      if (hour < 0 || hour > 23) {
        return null;
      }
    }

    return TimeOfDay(
      hour: hour,
      minute: minute,
    );
  }

  // ============================================================
  // NUMBER FIELD
  // ============================================================

  Widget _numberField(
      String label,
      TextEditingController controller, {
        required void Function(String) onChanged,
      }) {
    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: kTextGray,
          ),
        ),

        const SizedBox(height: 4),

        TextField(
          controller: controller,
          keyboardType:
          const TextInputType.numberWithOptions(
            decimal: true,
          ),
          style: const TextStyle(
            fontSize: 13,
            color: kTextDark,
          ),
          decoration:
          _inputDecoration("0"),
          onChanged: onChanged,
        ),
      ],
    );
  }

  // ============================================================
  // LEAVE TYPES
  // ============================================================

  Widget _buildLeaveTypes() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: _leaveTypes.map(
            (type) {
          final bool selected =
              _selectedLeaveType ==
                  type["code"];

          return InkWell(
            onTap: () {
              setState(() {
                _selectedLeaveType =
                type["code"]!;
              });
            },
            borderRadius:
            BorderRadius.circular(8),
            child: Container(
              width: 130,
              padding:
              const EdgeInsets.symmetric(
                vertical: 12,
                horizontal: 10,
              ),
              decoration: BoxDecoration(
                color: selected
                    ? kOrangeLight
                    : Colors.white,
                border: Border.all(
                  color: selected
                      ? kOrange
                      : const Color(
                    0xFFE2E8F0,
                  ),
                ),
                borderRadius:
                BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Text(
                    type["code"]!,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight:
                      FontWeight.w700,
                      color: kTextDark,
                    ),
                  ),

                  const SizedBox(height: 2),

                  Text(
                    type["desc"]!,
                    textAlign:
                    TextAlign.center,
                    style:
                    const TextStyle(
                      fontSize: 10,
                      color: kTextGray,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ).toList(),
    );
  }

  // ============================================================
  // REASON
  // ============================================================

  Widget _buildReasonField() {
    return _labeledField(
      "Reason",
      TextField(
        controller: _reasonController,
        maxLines: 4,
        style: const TextStyle(
          fontSize: 13,
          color: kTextDark,
        ),
        decoration: _inputDecoration(
          "State reason for leave...",
        ),
      ),
    );
  }

  // ============================================================
  // SUBMIT BUTTON
  // ============================================================

  Widget _buildSubmitButton() {
    return Align(
      alignment: Alignment.centerRight,
      child: ElevatedButton(
        onPressed:
        _isSubmitting
            ? null
            : _submitLeaveRequest,
        style: ElevatedButton.styleFrom(
          backgroundColor: kOrange,
          foregroundColor: Colors.white,
          disabledBackgroundColor:
          kOrange.withOpacity(0.6),
          padding:
          const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 14,
          ),
          shape:
          RoundedRectangleBorder(
            borderRadius:
            BorderRadius.circular(8),
          ),
        ),
        child: _isSubmitting
            ? const SizedBox(
          width: 16,
          height: 16,
          child:
          CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white,
          ),
        )
            : const Text(
          "Submit Leave Request",
          style: TextStyle(
            fontSize: 13,
            fontWeight:
            FontWeight.w600,
          ),
        ),
      ),
    );
  }

  // ============================================================
  // SUBMIT LEAVE REQUEST
  // ============================================================

  Future<void> _submitLeaveRequest() async {
    // ----------------------------------------------------------
    // Parse manually typed dates
    // ----------------------------------------------------------

    final DateTime? parsedFrom =
    _parseDate(
      _fromDateController.text,
    );

    final DateTime? parsedTo =
    _parseDate(
      _toDateController.text,
    );

    final DateTime? parsedReturnDate =
    _parseDate(
      _returnDateController.text,
    );

    final TimeOfDay? parsedReturnTime =
    _parseTime(
      _returnTimeController.text,
    );

    _dateFrom = parsedFrom;
    _dateTo = parsedTo;
    _returnDate = parsedReturnDate;
    _returnTime = parsedReturnTime;

    // ----------------------------------------------------------
    // Find employee document ID
    // ----------------------------------------------------------

    _tryFindEmployee(
      _nameController.text,
    );

    // ----------------------------------------------------------
    // Validate employee
    // ----------------------------------------------------------

    if (_nameController.text.trim().isEmpty) {
      _showError(
        "Please enter the employee name.",
      );
      return;
    }

    if (_selectedEmployeeId == null ||
        _selectedEmployeeId!.isEmpty) {
      _showError(
        "Employee name was not found. "
            "Please type the exact employee name.",
      );
      return;
    }

    // ----------------------------------------------------------
    // Validate dates
    // ----------------------------------------------------------

    if (_dateFrom == null) {
      _showError(
        "Please enter a valid From date.",
      );
      return;
    }

    if (_dateTo == null) {
      _showError(
        "Please enter a valid To date.",
      );
      return;
    }

    if (_dateTo!.isBefore(_dateFrom!)) {
      _showError(
        "The To date cannot be earlier than the From date.",
      );
      return;
    }

    // ----------------------------------------------------------
    // Calculate days one more time
    // ----------------------------------------------------------

    _totalDays =
        _dateTo!
            .difference(_dateFrom!)
            .inDays +
            1;

    final double enteredHours =
        double.tryParse(
          _hoursController.text.trim(),
        ) ??
            0;

    _totalHours = enteredHours;

    _daysController.text =
        _totalDays.toString();

    // ----------------------------------------------------------
    // Loading
    // ----------------------------------------------------------

    setState(() {
      _isSubmitting = true;
    });

    // ----------------------------------------------------------
    // Request data
    // ----------------------------------------------------------

    final String requestId =
        FirebaseFirestore.instance
            .collection('_')
            .doc()
            .id;

    final Map<String, dynamic>
    requestData = {
      "id": requestId,

      "employeeName":
      _nameController.text.trim(),

      "position":
      _positionController.text.trim(),

      "department":
      _departmentController.text.trim(),

      "reliever":
      _relieverController.text.trim(),

      "dateFrom":
      Timestamp.fromDate(_dateFrom!),

      "dateTo":
      Timestamp.fromDate(_dateTo!),

      "totalDays":
      _totalDays,

      "totalHours":
      _totalHours,

      "returnDate":
      _returnDate != null
          ? Timestamp.fromDate(
        _returnDate!,
      )
          : null,

      "returnTime":
      _returnTime != null
          ? "${_returnTime!.hour.toString().padLeft(2, '0')}:"
          "${_returnTime!.minute.toString().padLeft(2, '0')}"
          : null,

      "leaveType":
      _selectedLeaveType,

      "reason":
      _reasonController.text.trim(),

      "status":
      "pending",

      "createdAt":
      Timestamp.now(),
    };

    // ----------------------------------------------------------
    // SAVE TO FIRESTORE
    // ----------------------------------------------------------

    try {
      await FirebaseFirestore.instance
          .collection("employees")
          .doc(_selectedEmployeeId)
          .update({
        "leaveRequests":
        FieldValue.arrayUnion([
          requestData,
        ]),
      });

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            "Leave request submitted.",
          ),
          backgroundColor: kGreen,
        ),
      );

      Navigator.of(context)
          .maybePop(true);

      widget.onBack?.call();
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            "Failed to submit: $e",
          ),
          backgroundColor:
          Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  // ============================================================
  // ERROR MESSAGE
  // ============================================================

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
        Colors.redAccent,
      ),
    );
  }

  // ============================================================
  // TEXT FIELD
  // ============================================================

  Widget _textField(
      TextEditingController controller,
      String hint, {
        TextInputType? keyboardType,
      }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(
        fontSize: 13,
        color: kTextDark,
      ),
      decoration:
      _inputDecoration(hint),
    );
  }

  // ============================================================
  // LABELED FIELD
  // ============================================================

  Widget _labeledField(
      String label,
      Widget field,
      ) {
    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight:
            FontWeight.w600,
            color: kTextGray2,
          ),
        ),

        const SizedBox(height: 6),

        field,
      ],
    );
  }

  // ============================================================
  // INPUT DECORATION
  // ============================================================

  InputDecoration _inputDecoration(
      String hint, {
        Widget? suffixIcon,
      }) {
    return InputDecoration(
      hintText: hint,

      hintStyle:
      const TextStyle(
        color: Color(0xFF9CA3AF),
        fontSize: 13,
      ),

      suffixIcon:
      suffixIcon,

      filled: true,

      fillColor:
      Colors.white,

      contentPadding:
      const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 12,
      ),

      border:
      OutlineInputBorder(
        borderRadius:
        BorderRadius.circular(8),
        borderSide:
        const BorderSide(
          color: Color(
            0xFFD1D5DB,
          ),
        ),
      ),

      enabledBorder:
      OutlineInputBorder(
        borderRadius:
        BorderRadius.circular(8),
        borderSide:
        const BorderSide(
          color: Color(
            0xFFD1D5DB,
          ),
        ),
      ),

      focusedBorder:
      OutlineInputBorder(
        borderRadius:
        BorderRadius.circular(8),
        borderSide:
        const BorderSide(
          color: kOrange,
          width: 1.2,
        ),
      ),
    );
  }

  // ============================================================
  // DATE FORMAT
  // ============================================================

  String _fmtDate(DateTime date) {
    return "${date.month.toString().padLeft(2, '0')}/"
        "${date.day.toString().padLeft(2, '0')}/"
        "${date.year}";
  }
}

// ============================================================
// RESPONSIVE GRID
// ============================================================

class _ResponsiveGrid
    extends StatelessWidget {
  final List<Widget> children;

  const _ResponsiveGrid({
    required this.children,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return LayoutBuilder(
      builder: (
          BuildContext context,
          BoxConstraints constraints,
          ) {
        final bool isNarrow =
            constraints.maxWidth < 600;

        // ------------------------------------------------------
        // MOBILE
        // ------------------------------------------------------

        if (isNarrow) {
          return Column(
            children: children
                .map(
                  (child) => Padding(
                padding:
                const EdgeInsets.only(
                  bottom: 20,
                ),
                child: child,
              ),
            )
                .toList(),
          );
        }

        // ------------------------------------------------------
        // DESKTOP
        // ------------------------------------------------------

        return Wrap(
          spacing: 20,
          runSpacing: 20,
          children: children
              .map(
                (child) => SizedBox(
              width:
              (constraints.maxWidth -
                  20) /
                  2,
              child: child,
            ),
          )
              .toList(),
        );
      },
    );
  }
}