import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
<<<<<<< HEAD

// ═══════════════════════════════════════════════════════════════════
// Light-mode palette (pinanatili ang light colors)
// ═══════════════════════════════════════════════════════════════════
class _LightColors {
  static const background   = Color(0xFFF8F8F8);
  static const card         = Color(0xFFFFFFFF);
  static const surface      = Color(0xFFF2F2F3);
  static const cardBorder   = Color(0xFFE4E4E7);
  static const textPrimary  = Color(0xFF18181B);
  static const textSecondary= Color(0xFF52525B);
  static const textMuted    = Color(0xFF9CA3AF);

  static const orange       = Color(0xFFFF8A00);
  static const orangeDeep   = Color(0xFFFF6B00);

  static const green   = Color(0xFF16A34A);
  static const warning = Color(0xFFF59E0B);
  static const error   = Color(0xFFDC2626);
  static const info    = Color(0xFF2563EB);
  static const white   = Colors.white;

  static const gradientOrange = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [orange, orangeDeep],
  );

  static const gradientOrangeHot = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [orange, orangeDeep],
  );
}

// ═══════════════════════════════════════════════════════════════════
// Leave types
// ═══════════════════════════════════════════════════════════════════
=======
import '../theme/app_theme.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Leave types
// ══════════════════════════════════════════════════════════════════════════════
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
class _LeaveType {
  final String code;
  final String label;
  final IconData icon;
  const _LeaveType(this.code, this.label, this.icon);
}

const _leaveTypes = [
  _LeaveType('SL', 'Sick',      Icons.medical_services_rounded),
  _LeaveType('VL', 'Vacation',  Icons.beach_access_rounded),
  _LeaveType('EL', 'Emergency', Icons.warning_amber_rounded),
  _LeaveType('BL', 'Bereave',   Icons.sentiment_very_dissatisfied_rounded),
  _LeaveType('ML', 'Maternity', Icons.child_friendly_rounded),
];

<<<<<<< HEAD
// ═══════════════════════════════════════════════════════════════════
// ApplyLeaveScreen
// ═══════════════════════════════════════════════════════════════════
=======
// ══════════════════════════════════════════════════════════════════════════════
// ApplyLeaveScreen
// ══════════════════════════════════════════════════════════════════════════════
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
class ApplyLeaveScreen extends StatefulWidget {
  final String employeeId;
  final String employeeName;
  const ApplyLeaveScreen({
    super.key,
    required this.employeeId,
    required this.employeeName,
  });

  @override
  State<ApplyLeaveScreen> createState() => _ApplyLeaveScreenState();
}

class _ApplyLeaveScreenState extends State<ApplyLeaveScreen>
    with TickerProviderStateMixin {
<<<<<<< HEAD
  int     _currentStep = 0;
  String? _selectedLeaveType;
  bool    _isSubmitting = false;
  bool    _isCertified = false;
=======

  // State variables
  int     _currentStep = 0;
  String? _selectedLeaveType;
  bool    _isSubmitting = false;
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1

  DateTime? _startDate;
  DateTime? _endDate;
  final _reasonCtrl = TextEditingController();

<<<<<<< HEAD
=======
  // Animation
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
  late AnimationController _fadeCtrl;
  late Animation<double>   _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

<<<<<<< HEAD
  // ── Helpers ──────────────────────────────────────────────────────
=======
  // ── Helpers ────────────────────────────────────────────────────────────────
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
  int get _leaveDays {
    if (_startDate == null || _endDate == null) return 0;
    return _endDate!.difference(_startDate!).inDays + 1;
  }

<<<<<<< HEAD
  double get _leaveHours => _leaveDays * 8.0;

=======
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
  String _fmt(DateTime? d) {
    if (d == null) return 'dd/mm/yyyy';
    const months = ['','Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[d.month]} ${d.day}, ${d.year}';
  }

<<<<<<< HEAD
  String get _leaveLabel {
    if (_selectedLeaveType == null) return '—';
    return _leaveTypes.firstWhere((l) => l.code == _selectedLeaveType).label;
  }

  String get _leaveDisplay => '$_leaveLabel ($_selectedLeaveType)';

  String get _durationDisplay => '$_leaveDays Days';

  String get _datesDisplay {
    if (_startDate == null || _endDate == null) return '—';
    return '${_fmt(_startDate)} - ${_fmt(_endDate)}';
  }

  String get _reasonDisplay =>
      _reasonCtrl.text.trim().isEmpty ? '—' : _reasonCtrl.text.trim();

=======
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
  Future<void> _pickDate(bool isStart) async {
    final now  = DateTime.now();
    final pick = await showDatePicker(
      context: context,
      initialDate: isStart ? (_startDate ?? now) : (_endDate ?? _startDate ?? now),
      firstDate: now,
      lastDate: DateTime(now.year + 1),
      builder: (ctx, child) => Theme(
<<<<<<< HEAD
        data: ThemeData.light().copyWith(
          colorScheme: const ColorScheme.light(
            primary: _LightColors.orange,
            surface: _LightColors.card,
          ),
          dialogBackgroundColor: _LightColors.card,
=======
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.orange,
            surface: AppColors.surface,
          ),
          dialogBackgroundColor: AppColors.card,
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
        ),
        child: child!,
      ),
    );
    if (pick == null || !mounted) return;
    setState(() {
      if (isStart) {
        _startDate = pick;
        if (_endDate != null && _endDate!.isBefore(pick)) _endDate = null;
      } else {
        _endDate = pick;
      }
    });
  }

  void _goNext() {
<<<<<<< HEAD
    if (_currentStep == 0 && _selectedLeaveType == null) {
      _showToast('Please select a leave type', _LightColors.warning);
      return;
    }
    if (_currentStep == 1) {
      if (_startDate == null || _endDate == null) {
        _showToast('Please select dates', _LightColors.warning);
        return;
      }
      if (_reasonCtrl.text.trim().isEmpty) {
        _showToast('Please enter a reason', _LightColors.warning);
        return;
      }
    }
    if (_currentStep == 2 && !_isCertified) {
      _showToast('Please certify that all information is correct', _LightColors.warning);
      return;
    }
=======
    // Validation for Step 1
    if (_currentStep == 0 && _selectedLeaveType == null) {
      _showToast('Please select a leave type', AppColors.warning);
      return;
    }
    // Validation for Step 2
    if (_currentStep == 1) {
      if (_startDate == null || _endDate == null) {
        _showToast('Please select dates', AppColors.warning);
        return;
      }
      if (_reasonCtrl.text.trim().isEmpty) {
        _showToast('Please enter a reason', AppColors.warning);
        return;
      }
    }

>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
    if (_currentStep < 2) {
      _fadeCtrl.forward(from: 0);
      setState(() => _currentStep++);
    }
  }

  void _goBack() {
    if (_currentStep > 0) {
      _fadeCtrl.forward(from: 0);
      setState(() => _currentStep--);
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _submitApplication() async {
<<<<<<< HEAD
    if (!_isCertified) {
      _showToast('Please certify that all information is correct', _LightColors.warning);
      return;
    }

=======
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
    setState(() => _isSubmitting = true);
    try {
      await FirebaseFirestore.instance.collection('leave_applications').add({
        'employeeId'  : widget.employeeId,
        'employeeName': widget.employeeName,
        'leaveType'   : _selectedLeaveType,
        'startDate'   : _startDate?.toIso8601String(),
        'endDate'     : _endDate?.toIso8601String(),
        'days'        : _leaveDays,
<<<<<<< HEAD
        'hours'       : _leaveHours,
        'reason'      : _reasonCtrl.text.trim(),
        'status'      : 'pending',
        'certified'   : _isCertified,
=======
        'reason'      : _reasonCtrl.text.trim(),
        'status'      : 'pending',
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
        'createdAt'   : FieldValue.serverTimestamp(),
      });
      if (!mounted) return;

<<<<<<< HEAD
=======
      // Show success dialog
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
      showDialog(
        barrierDismissible: false,
        context: context,
        builder: (ctx) => AlertDialog(
<<<<<<< HEAD
          backgroundColor: _LightColors.card,
=======
          backgroundColor: AppColors.card,
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
<<<<<<< HEAD
                color: _LightColors.orange.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded,
                  color: _LightColors.orange, size: 40),
            ),
            const SizedBox(height: 16),
            const Text('Successfully added',
                style: TextStyle(color: _LightColors.textPrimary,
                    fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text('Just wait for the HR Approval...',
                style: TextStyle(color: _LightColors.textSecondary, fontSize: 13)),
=======
                color: AppColors.orange.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded,
                  color: AppColors.orange, size: 40),
            ),
            const SizedBox(height: 16),
            const Text('Successfully added',
                style: TextStyle(color: AppColors.textPrimary,
                    fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text('Just wait for the HR Approval...',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
<<<<<<< HEAD
                  backgroundColor: _LightColors.orange,
=======
                  backgroundColor: AppColors.orange,
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  Navigator.of(ctx).pop();
<<<<<<< HEAD
                  Navigator.of(context).pop();
=======
                  Navigator.of(context).pop(); // Exit screen
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
                },
                child: const Text('OK', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
      );

    } catch (e) {
      if (mounted) {
<<<<<<< HEAD
        _showToast('Failed to submit. Try again.', _LightColors.error);
=======
        _showToast('Failed to submit. Try again.', AppColors.error);
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _saveAsDraft() async {
<<<<<<< HEAD
    _showToast('Draft saved locally', _LightColors.info);
=======
    // Mock draft save
    _showToast('Draft saved locally', AppColors.info);
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
  }

  void _showToast(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(
<<<<<<< HEAD
              color: _LightColors.white,
=======
              color: AppColors.white,
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
              fontWeight: FontWeight.w600)),
      backgroundColor: color.withOpacity(0.9),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 2),
    ));
  }

<<<<<<< HEAD
  // ── Build ──────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _LightColors.background,
=======
  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryDeep,
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
      body: SafeArea(
        child: Column(children: [
          _buildHeader(),
          Expanded(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                child: Column(children: [
                  const SizedBox(height: 20),
                  _buildHeroCard(),
                  const SizedBox(height: 20),
                  _buildStepper(),
                  const SizedBox(height: 24),
                  _buildStepContent(),
                  const SizedBox(height: 24),
                  _buildActions(),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }

<<<<<<< HEAD
  // ── Header ────────────────────────────────────────────────────────
=======
  // ── Header ─────────────────────────────────────────────────────────────────
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Row(children: [
        GestureDetector(
          onTap: _goBack,
          child: Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
<<<<<<< HEAD
              color: _LightColors.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _LightColors.cardBorder),
            ),
            child: const Icon(Icons.chevron_left_rounded,
                color: _LightColors.textSecondary, size: 22),
=======
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: const Icon(Icons.chevron_left_rounded,
                color: AppColors.textSecondary, size: 22),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
          ),
        ),
        const SizedBox(width: 14),
        const Text('Apply for Leave',
            style: TextStyle(
<<<<<<< HEAD
              color: _LightColors.textPrimary,
=======
              color: AppColors.textPrimary,
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            )),
      ]),
    );
  }

<<<<<<< HEAD
  // ── Hero Card ─────────────────────────────────────────────────────
=======
  // ── Hero Card ──────────────────────────────────────────────────────────────
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
  Widget _buildHeroCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
<<<<<<< HEAD
        gradient: _LightColors.gradientOrange,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _LightColors.orange.withOpacity(0.25),
=======
        gradient: AppColors.gradientOrange,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.orange.withOpacity(0.35),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
<<<<<<< HEAD
            color: Colors.black.withOpacity(0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.25)),
=======
            color: Colors.black.withOpacity(0.2),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
          ),
          child: const Icon(Icons.event_note_rounded,
              color: Colors.white, size: 24),
        ),
        const SizedBox(width: 14),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('SELF SERVICE',
              style: TextStyle(
<<<<<<< HEAD
                color: Colors.white.withOpacity(0.85),
=======
                color: Colors.white.withOpacity(0.7),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              )),
          const SizedBox(height: 2),
          const Text('Apply for Leave',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              )),
        ]),
      ]),
    );
  }

<<<<<<< HEAD
  // ── Stepper ──────────────────────────────────────────────────────
=======
  // ── Stepper ────────────────────────────────────────────────────────────────
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
  Widget _buildStepper() {
    const steps = ['Type', 'Details', 'Submit'];
    return Row(
      children: List.generate(steps.length * 2 - 1, (i) {
        if (i.isOdd) {
          final stepIndex = i ~/ 2;
          final passed = _currentStep > stepIndex;
          return Expanded(
            child: Container(
              height: 2,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
<<<<<<< HEAD
                color: passed ? _LightColors.orange : _LightColors.cardBorder,
=======
                color: passed ? AppColors.orange : AppColors.cardBorder,
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          );
        }
        final stepIndex = i ~/ 2;
        final active = _currentStep == stepIndex;
        final done   = _currentStep > stepIndex;
        return Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 32, height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done
<<<<<<< HEAD
                  ? _LightColors.orange
                  : active
                  ? Colors.transparent
                  : _LightColors.surface,
              border: Border.all(
                color: done || active ? _LightColors.orange : _LightColors.cardBorder,
=======
                  ? AppColors.orange
                  : active
                  ? Colors.transparent
                  : AppColors.surface,
              border: Border.all(
                color: done || active ? AppColors.orange : AppColors.cardBorder,
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
                width: active ? 2 : 1.5,
              ),
              boxShadow: active || done
                  ? [BoxShadow(
<<<<<<< HEAD
                color: _LightColors.orange.withOpacity(0.3),
=======
                color: AppColors.orange.withOpacity(0.4),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
                blurRadius: 10,
              )]
                  : [],
            ),
            child: Center(
              child: done
                  ? const Icon(Icons.check_rounded,
                  color: Colors.white, size: 16)
                  : Text('${stepIndex + 1}', style: TextStyle(
<<<<<<< HEAD
                color: active ? _LightColors.orange : _LightColors.textMuted,
=======
                color: active ? AppColors.orange : AppColors.textMuted,
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
                fontSize: 13,
                fontWeight: FontWeight.w800,
              )),
            ),
          ),
          const SizedBox(height: 6),
          Text(steps[stepIndex], style: TextStyle(
            color: active
<<<<<<< HEAD
                ? _LightColors.textPrimary
                : done
                ? _LightColors.orange
                : _LightColors.textMuted,
=======
                ? AppColors.textPrimary
                : done
                ? AppColors.orange
                : AppColors.textMuted,
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
            fontSize: 11,
            fontWeight: active ? FontWeight.w700 : FontWeight.normal,
          )),
        ]);
      }),
    );
  }

<<<<<<< HEAD
  // ── Step Content ─────────────────────────────────────────────────
  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0: return _buildStep1();
      case 1: return _buildStep2(); // ✅ Step 2 = Routing Summary + Duration + Justification (orange gradient)
=======
  // ── Step Content ───────────────────────────────────────────────────────────
  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0: return _buildStep1();
      case 1: return _buildStep2();
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
      case 2: return _buildStep3();
      default: return const SizedBox();
    }
  }

<<<<<<< HEAD
  // ── STEP 1: Select Leave Type ────────────────────────────────────
=======
  // STEP 1: Select Leave Type
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
  Widget _buildStep1() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('SELECT LEAVE TYPE',
          style: TextStyle(
<<<<<<< HEAD
            color: _LightColors.textMuted,
=======
            color: AppColors.textMuted,
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
          )),
      const SizedBox(height: 14),
      GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.15,
        children: _leaveTypes.map((lt) {
          final sel = _selectedLeaveType == lt.code;
          return GestureDetector(
            onTap: () => setState(() => _selectedLeaveType = lt.code),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
<<<<<<< HEAD
                gradient: sel ? _LightColors.gradientOrange : null,
                color: sel ? null : _LightColors.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: sel ? _LightColors.orange : _LightColors.cardBorder,
=======
                gradient: sel ? AppColors.gradientOrange : null,
                color: sel ? null : AppColors.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: sel
                      ? AppColors.orange
                      : AppColors.cardBorder,
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
                  width: sel ? 1.5 : 1,
                ),
                boxShadow: sel
                    ? [BoxShadow(
<<<<<<< HEAD
                  color: _LightColors.orange.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                )]
                    : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
=======
                  color: AppColors.orange.withOpacity(0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                )]
                    : [],
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(lt.icon,
<<<<<<< HEAD
                      color: sel ? Colors.white : _LightColors.textMuted,
                      size: 22),
                  const SizedBox(height: 6),
                  Text(lt.code, style: TextStyle(
                    color: sel ? Colors.white : _LightColors.textPrimary,
=======
                      color: sel
                          ? Colors.white
                          : AppColors.textMuted,
                      size: 22),
                  const SizedBox(height: 6),
                  Text(lt.code, style: TextStyle(
                    color: sel
                        ? Colors.white
                        : AppColors.textPrimary,
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  )),
                  const SizedBox(height: 2),
                  Text(lt.label, style: TextStyle(
<<<<<<< HEAD
                    color: sel ? Colors.white.withOpacity(0.85) : _LightColors.textSecondary,
=======
                    color: sel
                        ? Colors.white.withOpacity(0.8)
                        : AppColors.textSecondary,
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  )),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    ]);
  }

<<<<<<< HEAD
  // ── STEP 2: Routing Summary + Duration Details + Justification ──
  // ✅ Lahat ng cards dito ay orange gradient (tulad ng HTML)
  Widget _buildStep2() {
    return Column(
      children: [
        // ── Routing Summary (Orange Gradient) ──
        _buildOrangeCard(
          icon: Icons.timeline_rounded,
          title: 'ROUTING SUMMARY',
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  image: const DecorationImage(
                    image: NetworkImage('https://i.pravatar.cc/150?u=a042581f4e29026704d'),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('Approved By',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                    SizedBox(height: 2),
                    Text('Ra Coma (Dept. Head)',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w400)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Duration Details (Orange Gradient) ──
        _buildOrangeCard(
          icon: Icons.calendar_today_rounded,
          title: 'Duration Details',
          child: Column(
            children: [
              // Start Date
              _buildOrangeDatePicker('Start Date', _startDate, () => _pickDate(true)),
              const SizedBox(height: 12),

              // End Date
              _buildOrangeDatePicker('End Date', _endDate, () => _pickDate(false)),
              const SizedBox(height: 16),

              // Total Days & Total Hours (row)
              Row(
                children: [
                  Expanded(child: _buildOrangeInfoField('Total Days', '${_leaveDays.toStringAsFixed(1)}')),
                  const SizedBox(width: 12),
                  Expanded(child: _buildOrangeInfoField('Total Hours', '${_leaveHours.toStringAsFixed(1)}')),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Justification (Orange Gradient) ──
        _buildOrangeCard(
          icon: Icons.edit_note_rounded,
          title: 'Justification',
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withOpacity(0.2)),
            ),
            child: TextField(
              controller: _reasonCtrl,
              maxLines: 4,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'Enter reason for leave...',
                hintStyle: TextStyle(color: Colors.white54, fontSize: 14),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Orange Card Widget (para sa Step 2) ──
  Widget _buildOrangeCard({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFF8A00), Color(0xFFFF6B00), Color(0xFF281D15)],
          stops: [0.0, 0.33, 1.0],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Color(0xFFFFA500), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  // ── Orange Date Picker ──
  Widget _buildOrangeDatePicker(String label, DateTime? value, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(_fmt(value),
                      style: TextStyle(
                        color: value != null ? Colors.white : Colors.white54,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      )),
                ),
                const Icon(Icons.calendar_today_rounded,
                    color: Colors.white54, size: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Orange Info Field ──
  Widget _buildOrangeInfoField(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.3),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
          ),
          child: Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }

  // ── STEP 3: Review & Submit ──────────────────────────────────────
  Widget _buildStep3() {
    return Column(
      children: [
        // ── Leave Information ──
        _buildWhiteCard(
          title: 'Leave Information',
          editButton: true,
          onEdit: () => setState(() => _currentStep = 0),
          child: Column(children: [
            _infoRow('Type of Leave', _leaveDisplay),
            const SizedBox(height: 12),
            _infoRow('Duration', _durationDisplay),
            const SizedBox(height: 12),
            _infoRow('Dates', _datesDisplay),
            const SizedBox(height: 12),
            _infoRow('Reason', _reasonDisplay, isMultiLine: true),
          ]),
        ),
        const SizedBox(height: 16),

        // ── Reliever Information ──
        _buildWhiteCard(
          title: 'Reliever Information',
          editButton: true,
          onEdit: () => setState(() => _currentStep = 1),
          child: Row(children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: _LightColors.surface,
              backgroundImage: const NetworkImage('https://i.pravatar.cc/150?u=a042581f4e29026704d'),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('Juliana Bantang',
                      style: TextStyle(
                          color: _LightColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                  Text('Logistics Department',
                      style: TextStyle(
                          color: _LightColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: _LightColors.textMuted),
          ]),
        ),
        const SizedBox(height: 16),

        // ── Approval Workflow ──
        _buildWhiteCard(
          title: 'Approval Workflow',
          editButton: false,
          child: Column(children: [
            _workflowStep(
              stage: 'Stage 1',
              role: 'Immediate Supervisor',
              status: 'David Henderson (Pending)',
              isComplete: false,
            ),
            const SizedBox(height: 16),
            _workflowStep(
              stage: 'Final Stage',
              role: 'Department Head',
              status: 'Automatic routing upon Stage 1 approval',
              isComplete: false,
              isLast: true,
            ),
          ]),
        ),
        const SizedBox(height: 16),

        // ── Certification ──
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () => setState(() => _isCertified = !_isCertified),
                child: Container(
                  width: 24,
                  height: 24,
                  margin: const EdgeInsets.only(top: 2),
                  decoration: BoxDecoration(
                    color: _isCertified ? _LightColors.orange : _LightColors.card,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: _isCertified ? _LightColors.orange : _LightColors.cardBorder,
                      width: 1.5,
                    ),
                  ),
                  child: _isCertified
                      ? const Icon(Icons.check, color: Colors.white, size: 16)
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'I certify that all information provided above is true and that my reliever has been fully briefed on my pending tasks.',
                  style: TextStyle(
                    color: _LightColors.textSecondary,
                    fontSize: 12,
                    height: 1.6,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── White Card (para sa Step 3) ──
  Widget _buildWhiteCard({
    required String title,
    required Widget child,
    bool editButton = false,
    VoidCallback? onEdit,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _LightColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _LightColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: _LightColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
              if (editButton && onEdit != null)
                GestureDetector(
                  onTap: onEdit,
                  child: const Text('Edit',
                      style: TextStyle(
                          color: _LightColors.orange,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, {bool isMultiLine = false}) {
    return Row(
      crossAxisAlignment: isMultiLine ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 100,
          child: Text(label,
              style: const TextStyle(
                  color: _LightColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(value,
              style: const TextStyle(
                color: _LightColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              maxLines: isMultiLine ? 3 : 1,
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  Widget _workflowStep({
    required String stage,
    required String role,
    required String status,
    required bool isComplete,
    bool isLast = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isComplete ? _LightColors.orange : _LightColors.surface,
                border: Border.all(
                  color: isComplete ? _LightColors.orange : _LightColors.cardBorder,
                  width: 2,
                ),
              ),
              child: isComplete
                  ? const Icon(Icons.check, color: Colors.white, size: 16)
                  : Center(
                child: Text('${_workflowStepIndex(stage)}',
                    style: const TextStyle(
                        color: _LightColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
            ),
            if (!isLast)
              SizedBox(
                height: 32,
                child: VerticalDivider(
                  color: _LightColors.cardBorder,
                  width: 2,
                  thickness: 2,
                  indent: 4,
                  endIndent: 4,
                ),
              ),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(stage,
                  style: const TextStyle(
                      color: _LightColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(role,
                  style: const TextStyle(
                      color: _LightColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
              Text(status,
                  style: const TextStyle(
                      color: _LightColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w400)),
            ],
          ),
        ),
      ],
    );
  }

  int _workflowStepIndex(String stage) {
    switch (stage) {
      case 'Stage 1': return 1;
      case 'Final Stage': return 2;
      default: return 0;
    }
  }

  // ── Actions ──────────────────────────────────────────────────────
=======
  // STEP 2: Details (Dates, Reason, Routing Summary)
  Widget _buildStep2() {
    final leaveLabel = _selectedLeaveType != null
        ? _leaveTypes.firstWhere((l) => l.code == _selectedLeaveType).label
        : '';

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Routing Summary Card (As seen in image)
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.timeline_rounded, color: AppColors.orange, size: 18),
            const SizedBox(width: 8),
            const Text('ROUTING SUMMARY',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            const Icon(Icons.check_circle_rounded, color: AppColors.green, size: 16),
            const SizedBox(width: 6),
            const Expanded(
              child: Text('Approved By Ra Coma (Dept. Head)',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ]),
        ]),
      ),
      const SizedBox(height: 20),

      // Duration Details
      const Text('DURATION DETAILS',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
          )),
      const SizedBox(height: 12),

      // Leave Type Label
      if(leaveLabel.isNotEmpty) ...[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.orange.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text('$leaveLabel ($_selectedLeaveType)', style: const TextStyle(color: AppColors.orange, fontSize: 12, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 12),
      ],

      // Date Pickers
      Row(children: [
        Expanded(child: _datePicker('Start Date', _startDate, () => _pickDate(true))),
        const SizedBox(width: 12),
        Expanded(child: _datePicker('End Date', _endDate, () => _pickDate(false))),
      ]),
      const SizedBox(height: 12),

      // Justification (Reason)
      const Text('JUSTIFICATION',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
          )),
      const SizedBox(height: 12),
      Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: TextField(
          controller: _reasonCtrl,
          maxLines: 4,
          style: const TextStyle(
              color: AppColors.textPrimary, fontSize: 14),
          decoration: const InputDecoration(
            hintText: 'Enter reason for leave...',
            hintStyle: TextStyle(
                color: AppColors.textMuted, fontSize: 13),
            border: InputBorder.none,
            contentPadding: EdgeInsets.all(16),
          ),
        ),
      ),
    ]);
  }

  // STEP 3: Review & Submit (Leaves & Reliever Info)
  Widget _buildStep3() {
    final leaveLabel = _selectedLeaveType != null
        ? _leaveTypes.firstWhere((l) => l.code == _selectedLeaveType).label
        : '—';

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('LEAVE INFORMATION',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
          )),
      const SizedBox(height: 14),

      // Summary Card
      Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Column(children: [
          _reviewRow(Icons.label_rounded, 'Type', '$leaveLabel ($_selectedLeaveType)'),
          _divider(),
          _reviewRow(Icons.calendar_today_rounded, 'Duration', '$_leaveDays Days'),
          _divider(),
          _reviewRow(Icons.date_range_rounded, 'Dates', '${_fmt(_startDate)} - ${_fmt(_endDate)}'),
          _divider(),
          _reviewRow(Icons.format_quote_rounded, 'Reason',
              _reasonCtrl.text.trim().isEmpty ? '—' : _reasonCtrl.text.trim()),
        ]),
      ),

      const SizedBox(height: 20),

      // Reliever Information (As seen in image)
      const Text('RELIEVER INFORMATION',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
          )),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Row(children: [
          CircleAvatar(
            backgroundColor: AppColors.surface,
            backgroundImage: const NetworkImage('https://i.pravatar.cc/150?u=a042581f4e29026704d'), // Placeholder
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('Reliever Name', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              SizedBox(height: 2),
              Text('Juliana Bantang', style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
              Text('Logistics Dept.', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
            ],
          )),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
        ]),
      ),
    ]);
  }

  // ── Widgets ────────────────────────────────────────────────────────────────
  Widget _datePicker(String label, DateTime? value, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(
                color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: value != null ? AppColors.orange.withOpacity(0.6) : AppColors.cardBorder,
              width: 1,
            ),
          ),
          child: Text(_fmt(value), style: TextStyle(
            color: value != null ? AppColors.textPrimary : AppColors.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          )),
        ),
      ]),
    );
  }

  Widget _reviewRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        Icon(icon, color: AppColors.orange, size: 16),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2),
              ]),
        ),
      ]),
    );
  }

  Widget _divider() => Container(
    height: 1,
    margin: const EdgeInsets.symmetric(horizontal: 16),
    color: AppColors.cardBorder,
  );

  // ── Actions ────────────────────────────────────────────────────────────────
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
  Widget _buildActions() {
    final isLastStep = _currentStep == 2;

    return Column(children: [
<<<<<<< HEAD
      // Primary Action
=======
      // Primary Action (Continue or Submit)
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
      GestureDetector(
        onTap: isLastStep
            ? (_isSubmitting ? null : _submitApplication)
            : _goNext,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          height: 54,
          decoration: BoxDecoration(
<<<<<<< HEAD
            gradient: _LightColors.gradientOrangeHot,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: _LightColors.orange.withOpacity(0.3),
=======
            gradient: AppColors.gradientOrangeHot,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppColors.orange.withOpacity(0.35),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Center(
            child: _isSubmitting
                ? const SizedBox(
              width: 22, height: 22,
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2.5),
            )
                : Row(mainAxisSize: MainAxisSize.min, children: [
              Text(
                isLastStep ? 'Submit Application' : 'Continue',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                isLastStep
                    ? Icons.send_rounded
                    : Icons.arrow_forward_rounded,
                color: Colors.white, size: 18,
              ),
            ]),
          ),
        ),
      ),
      const SizedBox(height: 12),

<<<<<<< HEAD
      // Secondary Action
=======
      // Secondary Action (Back or Save Draft)
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
      if (!isLastStep) ...[
        GestureDetector(
          onTap: _goBack,
          child: Container(
            width: double.infinity,
            height: 50,
            decoration: BoxDecoration(
<<<<<<< HEAD
              color: _LightColors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _LightColors.cardBorder),
=======
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.cardBorder),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
            ),
            child: const Center(
              child: Text('Back',
                  style: TextStyle(
<<<<<<< HEAD
                    color: _LightColors.textSecondary,
=======
                    color: AppColors.textSecondary,
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  )),
            ),
          ),
        ),
      ] else ...[
<<<<<<< HEAD
=======
        // Save as Draft only on last step
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
        GestureDetector(
          onTap: _saveAsDraft,
          child: Container(
            width: double.infinity,
            height: 50,
            decoration: BoxDecoration(
<<<<<<< HEAD
              color: _LightColors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _LightColors.cardBorder),
            ),
            child: const Center(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.save_alt_rounded, color: _LightColors.textSecondary, size: 17),
                SizedBox(width: 8),
                Text('Save as Draft',
                    style: TextStyle(
                      color: _LightColors.textSecondary,
=======
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: const Center(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.save_alt_rounded, color: AppColors.textSecondary, size: 17),
                SizedBox(width: 8),
                Text('Save as Draft',
                    style: TextStyle(
                      color: AppColors.textSecondary,
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    )),
              ]),
            ),
          ),
        ),
      ],
    ]);
  }
}