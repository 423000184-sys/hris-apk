// lib/screens/admin_create_leave_request_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'admin_theme.dart';
import '../widgets/bootstrap_grid.dart';

class AdminCreateLeaveRequestPage extends StatefulWidget {
  final List<Map<String, dynamic>> employees;
  final VoidCallback? onBack;
  final VoidCallback? onSuccess;

  const AdminCreateLeaveRequestPage({
    super.key,
    this.employees = const [],
    this.onBack,
    this.onSuccess,
  });

  @override
  State<AdminCreateLeaveRequestPage> createState() =>
      _AdminCreateLeaveRequestPageState();
}

class _AdminCreateLeaveRequestPageState
    extends State<AdminCreateLeaveRequestPage> {
  // ══════════════════════════════════════════════════════════════
  // THEME ACCESSOR
  // ══════════════════════════════════════════════════════════════
  AdminColors get tc => AdminTheme.getColors(context);

  // ══════════════════════════════════════════════════════════════
  // TEXT CONTROLLERS
  // ══════════════════════════════════════════════════════════════
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _positionController = TextEditingController();
  final TextEditingController _departmentController = TextEditingController();
  final TextEditingController _relieverController = TextEditingController();
  final TextEditingController _fromDateController = TextEditingController();
  final TextEditingController _toDateController = TextEditingController();
  final TextEditingController _daysController =
  TextEditingController(text: "0");
  final TextEditingController _hoursController =
  TextEditingController(text: "0");
  final TextEditingController _returnDateController = TextEditingController();
  final TextEditingController _returnTimeController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();

  // ══════════════════════════════════════════════════════════════
  // DATE / TIME VALUES
  // ══════════════════════════════════════════════════════════════
  DateTime? _dateFrom;
  DateTime? _dateTo;
  DateTime? _returnDate;
  TimeOfDay? _returnTime;
  double _totalDays = 0;
  double _totalHours = 0;

  // ══════════════════════════════════════════════════════════════
  // LEAVE TYPES
  // ══════════════════════════════════════════════════════════════
  final List<Map<String, String>> _leaveTypes = const [
    {"code": "SL", "desc": "Sick Leave"},
    {"code": "VL", "desc": "Vacation Leave"},
    {"code": "EL", "desc": "Emergency"},
    {"code": "BL", "desc": "Bereavement"},
    {"code": "ML", "desc": "Maternity/Paternity"},
    {"code": "Others", "desc": "Specify below"},
  ];
  String _selectedLeaveType = "SL";

  // ══════════════════════════════════════════════════════════════
  // EMPLOYEE
  // ══════════════════════════════════════════════════════════════
  String? _selectedEmployeeId;
  bool _isSubmitting = false;

  // ══════════════════════════════════════════════════════════════
  // EMPLOYEE NAME HELPER
  // ══════════════════════════════════════════════════════════════
  String _empName(Map<String, dynamic> employee) {
    final dynamic name = employee['name'];
    if (name != null && name.toString().trim().isNotEmpty) {
      return name.toString().trim();
    }
    final String first = (employee['firstName'] ?? '').toString().trim();
    final String last = (employee['lastName'] ?? '').toString().trim();
    final String fullName = '$first $last'.trim();
    return fullName.isEmpty ? 'Unknown' : fullName;
  }

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

  // ══════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: tc.background,
      resizeToAvoidBottomInset: true,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          child: BsContainer(
            maxWidth: 1400,
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
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // BACK LINK
  // ══════════════════════════════════════════════════════════════
  Widget _buildBackLink() {
    return InkWell(
      onTap: widget.onBack ?? () => Navigator.of(context).maybePop(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.arrow_back, size: 14, color: tc.orange),
          const SizedBox(width: 6),
          Text(
            "Back to Activity & Leave",
            style: TextStyle(
              color: tc.orange,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // PAGE HEADING — responsive font
  // ══════════════════════════════════════════════════════════════
  Widget _buildPageHeading() {
    return LayoutBuilder(builder: (_, c) {
      final r = BsResponsive(c.maxWidth);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Create Leave Request",
            style: TextStyle(
              fontSize: r.responsive<double>(
                xs: 22, sm: 26, md: 28, lg: 32,
              ),
              fontWeight: FontWeight.w700,
              color: tc.text,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            "Application for Leave of Absence",
            style: TextStyle(
              fontSize: r.responsive<double>(xs: 13, md: 16),
              fontWeight: FontWeight.w500,
              color: tc.orange,
            ),
          ),
        ],
      );
    });
  }

  // ══════════════════════════════════════════════════════════════
  // FORM CARD — responsive padding
  // ══════════════════════════════════════════════════════════════
  Widget _buildFormCard() {
    return LayoutBuilder(builder: (_, c) {
      final r = BsResponsive(c.maxWidth);
      final padding = r.responsive<double>(
        xs: 16, sm: 20, md: 24, lg: 32,
      );

      return Container(
        padding: EdgeInsets.all(padding),
        decoration: BoxDecoration(
          color: tc.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: tc.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInstructionBox(),
            const SizedBox(height: 24),
            _sectionLabel("EMPLOYEE INFORMATION"),
            const SizedBox(height: 16),
            _buildEmployeeInformation(),
            const SizedBox(height: 32),
            _sectionLabel("LEAVE DETAILS"),
            const SizedBox(height: 16),
            _buildLeaveDetails(),
            const SizedBox(height: 20),
            _buildReturnToWork(),
            const SizedBox(height: 32),
            _sectionLabel("LEAVE APPLIED FOR"),
            const SizedBox(height: 16),
            _buildLeaveTypes(),
            const SizedBox(height: 20),
            _buildReasonField(),
            const SizedBox(height: 28),
            _buildApprovalWorkflow(),
            const SizedBox(height: 24),
            _buildActionButtons(),
          ],
        ),
      );
    });
  }

  // ══════════════════════════════════════════════════════════════
  // INSTRUCTION BOX
  // ══════════════════════════════════════════════════════════════
  Widget _buildInstructionBox() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      decoration: BoxDecoration(
        color: tc.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(color: tc.orange, width: 4),
        ),
      ),
      child: Text(
        "INSTRUCTION: This form should be filled out BEFORE an "
            "employee goes on leave. In case of emergency or illness, "
            "this form must be filled out IMMEDIATELY upon return for "
            "work. Sick leave applications will only be honored "
            "provided it is a duty certified by licensed Physician.",
        style: TextStyle(
          fontSize: 12,
          height: 1.5,
          color: tc.text,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: tc.border, width: 1),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: tc.orange,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // RESPONSIVE GRID HELPER (2 columns on md+, 1 column on xs/sm)
  // ══════════════════════════════════════════════════════════════
  Widget _responsiveGrid({required List<Widget> children}) {
    return LayoutBuilder(builder: (_, c) {
      final r = BsResponsive(c.maxWidth);
      // Stack on xs/sm, 2-col on md+
      final narrow = !r.up(BsSize.md);

      if (narrow) {
        return Column(
          children: children
              .map((child) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: child,
          ))
              .toList(),
        );
      }
      return Wrap(
        spacing: 20,
        runSpacing: 20,
        children: children
            .map((child) => SizedBox(
          width: (c.maxWidth - 20) / 2,
          child: child,
        ))
            .toList(),
      );
    });
  }

  // ══════════════════════════════════════════════════════════════
  // EMPLOYEE INFORMATION
  // ══════════════════════════════════════════════════════════════
  Widget _buildEmployeeInformation() {
    return _responsiveGrid(
      children: [
        _labeledField("Name of Employee", _buildNameField()),
        _labeledField("Designation / Position",
            _textField(_positionController, "Enter job title")),
        _labeledField("Section / Department",
            _textField(_departmentController, "Enter department")),
        _labeledField("Name of Reliever (Optional)",
            _textField(_relieverController, "Who will cover your duties?")),
      ],
    );
  }

  Widget _buildNameField() {
    return TextField(
      controller: _nameController,
      style: TextStyle(fontSize: 16, color: tc.text),
      decoration: _inputDecoration("Enter full name"),
      onChanged: _tryFindEmployee,
    );
  }

  void _tryFindEmployee(String value) {
    final String typedName = value.trim().toLowerCase();
    if (typedName.isEmpty) {
      setState(() => _selectedEmployeeId = null);
      return;
    }
    for (final employee in widget.employees) {
      final String employeeName = _empName(employee).trim().toLowerCase();
      if (employeeName == typedName) {
        setState(
                () => _selectedEmployeeId = (employee['id'] ?? '').toString());
        return;
      }
    }
    setState(() => _selectedEmployeeId = null);
  }

  // ══════════════════════════════════════════════════════════════
  // LEAVE DETAILS
  // ══════════════════════════════════════════════════════════════
  Widget _buildLeaveDetails() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tc.blue.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tc.border),
      ),
      child: _responsiveGrid(
        children: [
          _labeledField(
            "Inclusive Dates",
            LayoutBuilder(builder: (_, c) {
              // Stack From/To on very narrow
              final veryNarrow = c.maxWidth < 320;
              final fromField = _editableDateField(
                label: "From",
                controller: _fromDateController,
                onDateSelected: (date) {
                  setState(() {
                    _dateFrom = date;
                    _fromDateController.text = _fmtDate(date);
                  });
                  _calculateTotalDays();
                },
              );
              final toField = _editableDateField(
                label: "To",
                controller: _toDateController,
                onDateSelected: (date) {
                  setState(() {
                    _dateTo = date;
                    _toDateController.text = _fmtDate(date);
                  });
                  _calculateTotalDays();
                },
              );

              if (veryNarrow) {
                return Column(
                  children: [
                    fromField,
                    const SizedBox(height: 10),
                    toField,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: fromField),
                  const SizedBox(width: 10),
                  Expanded(child: toField),
                ],
              );
            }),
          ),
          _labeledField(
            "Total Time Out",
            Row(
              children: [
                Expanded(
                  child: _numberField(
                    "Days",
                    _daysController,
                    onChanged: (value) {
                      setState(
                              () => _totalDays = double.tryParse(value) ?? 0);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _numberField(
                    "Hours",
                    _hoursController,
                    onChanged: (value) {
                      setState(
                              () => _totalHours = double.tryParse(value) ?? 0);
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

  Widget _editableDateField({
    required String label,
    required TextEditingController controller,
    required void Function(DateTime) onDateSelected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: tc.muted)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType: TextInputType.datetime,
          style: TextStyle(fontSize: 16, color: tc.text),
          decoration: _inputDecoration(
            "mm/dd/yyyy",
            suffixIcon: IconButton(
              tooltip: "Select date",
              icon: Icon(Icons.calendar_today_outlined,
                  size: 18, color: tc.muted),
              onPressed: () => _pickDate(onDateSelected),
            ),
          ),
          onChanged: (value) {
            final date = _parseDate(value);
            if (date != null) {
              if (controller == _fromDateController) _dateFrom = date;
              if (controller == _toDateController) _dateTo = date;
              _calculateTotalDays();
            }
          },
        ),
      ],
    );
  }

  Future<void> _pickDate(void Function(DateTime) onPicked) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (ctx, child) => Theme(
        data: AdminTheme.themeData(isDark),
        child: child!,
      ),
    );
    if (picked != null) onPicked(picked);
  }

  DateTime? _parseDate(String value) {
    final input = value.trim();
    if (input.isEmpty) return null;
    final regex = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$');
    final match = regex.firstMatch(input);
    if (match == null) return null;
    final month = int.tryParse(match.group(1)!);
    final day = int.tryParse(match.group(2)!);
    final year = int.tryParse(match.group(3)!);
    if (month == null || day == null || year == null) return null;
    try {
      final date = DateTime(year, month, day);
      if (date.year != year || date.month != month || date.day != day)
        return null;
      return date;
    } catch (_) {
      return null;
    }
  }

  void _calculateTotalDays() {
    if (_dateFrom == null || _dateTo == null) return;
    if (_dateTo!.isBefore(_dateFrom!)) {
      setState(() {
        _totalDays = 0;
        _daysController.text = "0";
      });
      return;
    }
    final days = _dateTo!.difference(_dateFrom!).inDays + 1;
    setState(() {
      _totalDays = days.toDouble();
      _daysController.text = days.toString();
    });
  }

  // ══════════════════════════════════════════════════════════════
  // RETURN TO WORK
  // ══════════════════════════════════════════════════════════════
  Widget _buildReturnToWork() {
    return _responsiveGrid(
      children: [
        _labeledField("Return to Work Date", _buildReturnDateField()),
        _labeledField("Return to Work Time", _buildReturnTimeField()),
      ],
    );
  }

  Widget _buildReturnDateField() {
    return TextField(
      controller: _returnDateController,
      keyboardType: TextInputType.datetime,
      style: TextStyle(fontSize: 16, color: tc.text),
      decoration: _inputDecoration(
        "mm/dd/yyyy",
        suffixIcon: IconButton(
          tooltip: "Select date",
          icon: Icon(Icons.calendar_today_outlined,
              size: 18, color: tc.muted),
          onPressed: () => _pickDate((date) {
            setState(() {
              _returnDate = date;
              _returnDateController.text = _fmtDate(date);
            });
          }),
        ),
      ),
      onChanged: (value) => _returnDate = _parseDate(value),
    );
  }

  Widget _buildReturnTimeField() {
    return TextField(
      controller: _returnTimeController,
      keyboardType: TextInputType.datetime,
      style: TextStyle(fontSize: 16, color: tc.text),
      decoration: _inputDecoration(
        "--:--",
        suffixIcon: IconButton(
          tooltip: "Select time",
          icon: Icon(Icons.access_time_outlined,
              size: 18, color: tc.muted),
          onPressed: _pickTime,
        ),
      ),
      onChanged: (value) => _returnTime = _parseTime(value),
    );
  }

  Future<void> _pickTime() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (ctx, child) => Theme(
        data: AdminTheme.themeData(isDark),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _returnTime = picked;
        _returnTimeController.text = picked.format(context);
      });
    }
  }

  TimeOfDay? _parseTime(String value) {
    final input = value.trim().toLowerCase();
    if (input.isEmpty) return null;
    final regex =
    RegExp(r'^(\d{1,2}):(\d{2})(?:\s*(am|pm))?$', caseSensitive: false);
    final match = regex.firstMatch(input);
    if (match == null) return null;
    int hour = int.tryParse(match.group(1)!) ?? -1;
    final minute = int.tryParse(match.group(2)!) ?? -1;
    final period = match.group(3)?.toLowerCase();
    if (minute < 0 || minute > 59) return null;
    if (period != null) {
      if (hour < 1 || hour > 12) return null;
      if (period == "pm" && hour != 12) hour += 12;
      if (period == "am" && hour == 12) hour = 0;
    } else {
      if (hour < 0 || hour > 23) return null;
    }
    return TimeOfDay(hour: hour, minute: minute);
  }

  Widget _numberField(
      String label,
      TextEditingController controller, {
        required void Function(String) onChanged,
      }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: tc.muted)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType:
          const TextInputType.numberWithOptions(decimal: true),
          style: TextStyle(fontSize: 16, color: tc.text),
          decoration: _inputDecoration("0"),
          onChanged: onChanged,
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════
  // LEAVE TYPES
  // ══════════════════════════════════════════════════════════════
  Widget _buildLeaveTypes() {
    return LayoutBuilder(builder: (_, c) {
      final r = BsResponsive(c.maxWidth);
      // Chips get wider on smaller screens for better tap targets
      final chipWidth = r.responsive<double>(
        xs: (c.maxWidth - 24) / 2, // 2 cols on phone
        sm: 130,
        md: 130,
        lg: 130,
      );

      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: _leaveTypes.map((type) {
          final selected = _selectedLeaveType == type["code"];
          return InkWell(
            onTap: () =>
                setState(() => _selectedLeaveType = type["code"]!),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: chipWidth,
              padding:
              const EdgeInsets.symmetric(vertical: 11, horizontal: 10),
              decoration: BoxDecoration(
                color:
                selected ? tc.orange.withValues(alpha: 0.12) : tc.card,
                border: Border.all(
                    color: selected ? tc.orange : tc.border),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    type["code"]!,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: tc.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    type["desc"]!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12,
                        color: tc.muted,
                        fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      );
    });
  }

  Widget _buildReasonField() {
    return _labeledField(
      "Reason",
      TextField(
        controller: _reasonController,
        maxLines: 4,
        style: TextStyle(fontSize: 16, color: tc.text),
        decoration: _inputDecoration(
            "Please provide specific details regarding your leave request..."),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // APPROVAL WORKFLOW — responsive
  // ══════════════════════════════════════════════════════════════
  Widget _buildApprovalWorkflow() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tc.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tc.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Approval Workflow (Automatic Routing)",
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: tc.text,
            ),
          ),
          const SizedBox(height: 16),

          // Signature block — responsive
          LayoutBuilder(builder: (_, c) {
            final narrow = c.maxWidth < 400;
            final sigInfo = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Digital Signature",
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: tc.text),
                ),
                const SizedBox(height: 2),
                Text(
                  "Will be attached upon submission",
                  style: TextStyle(fontSize: 12, color: tc.muted),
                ),
              ],
            );
            final dateInfo = Column(
              crossAxisAlignment: narrow
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.end,
              children: [
                Text("Date",
                    style: TextStyle(fontSize: 12, color: tc.muted)),
                const SizedBox(height: 2),
                Text(
                  DateFormat('MMM d, yyyy').format(DateTime.now()),
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: tc.text),
                ),
              ],
            );

            return Container(
              padding: const EdgeInsets.only(top: 16, bottom: 12),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: tc.border, width: 1),
                ),
              ),
              child: narrow
                  ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  sigInfo,
                  const SizedBox(height: 12),
                  dateInfo,
                ],
              )
                  : Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(child: sigInfo),
                  const SizedBox(width: 16),
                  dateInfo,
                ],
              ),
            );
          }),

          // Approval items
          _buildApprovalItem("Section Head", "Pending Recommendation"),
          _buildApprovalItem("Department Head", "Pending Approval"),
        ],
      ),
    );
  }

  Widget _buildApprovalItem(String title, String status) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: tc.blue.withValues(alpha: 0.15),
            child: Icon(Icons.person_outline, size: 16, color: tc.blue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: tc.text),
                ),
                Text(
                  status,
                  style: TextStyle(fontSize: 12, color: tc.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // ACTION BUTTONS — stack on narrow
  // ══════════════════════════════════════════════════════════════
  Widget _buildActionButtons() {
    return LayoutBuilder(builder: (_, c) {
      final r = BsResponsive(c.maxWidth);
      final narrow = !r.up(BsSize.sm);

      final cancelBtn = OutlinedButton(
        onPressed:
        widget.onBack ?? () => Navigator.of(context).maybePop(),
        style: OutlinedButton.styleFrom(
          foregroundColor: tc.text,
          side: BorderSide(color: tc.border),
          padding:
          const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8)),
        ),
        child: const Text(
          "Cancel",
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      );

      final submitBtn = ElevatedButton(
        onPressed: _isSubmitting
            ? null
            : () {
          FocusScope.of(context).unfocus();
          _submitLeaveRequest();
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: tc.orange,
          foregroundColor: Colors.white,
          disabledBackgroundColor: tc.orange.withValues(alpha: 0.6),
          padding:
          const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8)),
          elevation: 0,
        ),
        child: _isSubmitting
            ? const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: Colors.white),
        )
            : const Text(
          "Submit Request",
          style:
          TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      );

      if (narrow) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            submitBtn,
            const SizedBox(height: 12),
            cancelBtn,
          ],
        );
      }
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          cancelBtn,
          const SizedBox(width: 16),
          submitBtn,
        ],
      );
    });
  }

  // ══════════════════════════════════════════════════════════════
  // SUBMIT LEAVE REQUEST
  // ══════════════════════════════════════════════════════════════
  Future<void> _submitLeaveRequest() async {
    final parsedFrom = _parseDate(_fromDateController.text);
    final parsedTo = _parseDate(_toDateController.text);
    final parsedReturnDate = _parseDate(_returnDateController.text);
    final parsedReturnTime = _parseTime(_returnTimeController.text);

    _dateFrom = parsedFrom;
    _dateTo = parsedTo;
    _returnDate = parsedReturnDate;
    _returnTime = parsedReturnTime;

    _tryFindEmployee(_nameController.text);

    if (_nameController.text.trim().isEmpty) {
      _showError("Please enter the employee name.");
      return;
    }
    if (_selectedEmployeeId == null || _selectedEmployeeId!.isEmpty) {
      _showError(
          "Employee name was not found. Please type the exact employee name.");
      return;
    }
    if (_dateFrom == null) {
      _showError("Please enter a valid From date.");
      return;
    }
    if (_dateTo == null) {
      _showError("Please enter a valid To date.");
      return;
    }
    if (_dateTo!.isBefore(_dateFrom!)) {
      _showError("The To date cannot be earlier than the From date.");
      return;
    }

    _totalDays = _dateTo!.difference(_dateFrom!).inDays + 1;
    _totalHours = double.tryParse(_hoursController.text.trim()) ?? 0;
    _daysController.text = _totalDays.toString();

    if (!mounted) return;
    setState(() => _isSubmitting = true);

    try {
      final leaveData = {
        'employeeId': _selectedEmployeeId,
        'employeeName': _nameController.text.trim(),
        'position': _positionController.text.trim(),
        'department': _departmentController.text.trim(),
        'reliever': _relieverController.text.trim(),
        'leaveType': _selectedLeaveType,
        'startDate': _dateFrom!.toIso8601String(),
        'endDate': _dateTo!.toIso8601String(),
        'days': _totalDays.toInt(),
        'hours': _totalHours,
        'returnDate': _returnDate?.toIso8601String(),
        'returnTime': _returnTime != null
            ? "${_returnTime!.hour.toString().padLeft(2, '0')}:${_returnTime!.minute.toString().padLeft(2, '0')}"
            : null,
        'reason': _reasonController.text.trim(),
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': 'admin',
      };

      await FirebaseFirestore.instance
          .collection('leave_applications')
          .add(leaveData);

      await FirebaseFirestore.instance
          .collection('employees')
          .doc(_selectedEmployeeId)
          .update({
        'leaveRequests': FieldValue.arrayUnion([
          {
            'id': DateTime.now().millisecondsSinceEpoch.toString(),
            'leaveType': _selectedLeaveType,
            'startDate': _dateFrom!.toIso8601String(),
            'endDate': _dateTo!.toIso8601String(),
            'days': _totalDays.toInt(),
            'reason': _reasonController.text.trim(),
            'status': 'pending',
            'createdAt': Timestamp.now(),
          }
        ]),
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Leave request submitted successfully!"),
          backgroundColor: tc.green,
        ),
      );

      widget.onSuccess?.call();
      Navigator.of(context).maybePop(true);
      widget.onBack?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed to submit: ${e.toString()}"),
          backgroundColor: tc.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: tc.red),
    );
  }

  Widget _textField(TextEditingController controller, String hint,
      {TextInputType? keyboardType}) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: TextStyle(fontSize: 16, color: tc.text),
      decoration: _inputDecoration(hint),
    );
  }

  Widget _labeledField(String label, Widget field) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: tc.text,
          ),
        ),
        const SizedBox(height: 6),
        field,
      ],
    );
  }

  InputDecoration _inputDecoration(String hint, {Widget? suffixIcon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: tc.muted, fontSize: 14),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: tc.card,
      contentPadding:
      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
        borderSide: BorderSide(color: tc.orange, width: 1.2),
      ),
    );
  }

  String _fmtDate(DateTime date) {
    return "${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}/${date.year}";
  }
}