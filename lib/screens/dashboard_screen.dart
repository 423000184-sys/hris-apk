// lib/screens/dashboard_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/employee.dart';
import '../services/database_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// _ThemeColors — theme-aware colors
// ═══════════════════════════════════════════════════════════════════════════
class _ThemeColors {
  final bool isDark;
  const _ThemeColors(this.isDark);

  // Background
  Color get bg => isDark ? const Color(0xFF0F0F10) : const Color(0xFFFFFFFF);

  // Text
  Color get textBlack => isDark ? Colors.white : const Color(0xFF000000);
  Color get textDark => isDark ? Colors.white : const Color(0xFF1A1A1A);
  Color get textGray => isDark ? const Color(0xFFB0B0B0) : const Color(0xFF71717A);
  Color get textMuted => isDark ? const Color(0xFF888888) : const Color(0xFFA1A1AA);

  // Card fill (light gray surface for cards)
  Color get cardFill => isDark
      ? const Color(0xFF1F1F23)
      : const Color.fromRGBO(131, 131, 131, 0.07);

  // Border
  Color get darkBorder => isDark ? const Color(0xFF3F3F46) : const Color(0xFF27272A);

  // Toggle active tab background
  Color get toggleActiveBg => isDark ? const Color(0xFF27272A) : Colors.white;
}

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens — brand colors (same in both themes)
// ─────────────────────────────────────────────────────────────────────────────
class _T {
  static const List<Color> gradient = [
    Color(0xFFFF8A00),
    Color(0xFFFA6A00),
    Color(0xFFF54900),
  ];
  static const Color orange = Color(0xFFFF8A00);
  static const Color orangeBorder = Color(0xFFFFA500);
  static const Color lime = Color(0xFFC4FF0A);

  static const double r18 = 18;
  static const double r20 = 20;
  static const double r24 = 24;

  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: gradient,
    stops: [0.0, 0.5, 1.0],
  );
}

class DashboardScreen extends StatefulWidget {
  final Function(int)? onTabSwitch;
  final VoidCallback? onClockAction;
  final Employee? initialEmployee;

  const DashboardScreen({
    super.key,
    this.onTabSwitch,
    this.onClockAction,
    this.initialEmployee,
  });

  @override
  State<DashboardScreen> createState() => DashboardScreenState();
}

class DashboardScreenState extends State<DashboardScreen> {
  Employee? _employee;
  bool _isClockedIn = false;
  String _clockInTime = '--:--';
  String _clockOutTime = '--:--';
  bool _isLoadingAttendance = true;
  Timer? _durationTimer;
  String _elapsedDuration = '00:00:00';
  DateTime? _rawClockInDateTime;

  final DateTime _payslipMonth =
  DateTime(DateTime.now().year, DateTime.now().month - 1);
  double? _payslipAmount;
  bool _payslipLoading = true;
  bool _payslipError = false;

  bool get _isPayslipVisible {
    final now = DateTime.now();
    final firstDayAfterPayslipMonth =
    DateTime(_payslipMonth.year, _payslipMonth.month + 1, 1);
    return !now.isBefore(firstDayAfterPayslipMonth);
  }

  @override
  void initState() {
    super.initState();
    _employee = widget.initialEmployee;
    _loadTodayAttendance();
    _loadPayslipAmount();
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    super.dispose();
  }

  void _startElapsedTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_rawClockInDateTime != null && _isClockedIn) {
        final now = DateTime.now();
        final difference = now.difference(_rawClockInDateTime!);
        final hours = difference.inHours.toString().padLeft(2, '0');
        final minutes = (difference.inMinutes % 60).toString().padLeft(2, '0');
        final seconds = (difference.inSeconds % 60).toString().padLeft(2, '0');
        if (mounted) {
          setState(() {
            _elapsedDuration = '$hours:$minutes:$seconds';
          });
        }
      }
    });
  }

  Future<void> loadTodayAttendance() async => _loadTodayAttendance();
  Future<void> loadPayslipAmount() async => _loadPayslipAmount();

  Future<void> _loadTodayAttendance() async {
    setState(() => _isLoadingAttendance = true);
    try {
      final employeeId = _employee?.employeeId ??
          widget.initialEmployee?.employeeId ??
          _employee?.id ??
          widget.initialEmployee?.id;
      if (employeeId == null) {
        throw Exception('Walang nahanap na employee ID.');
      }

      final todayStr = DateTime.now().toIso8601String().substring(0, 10);
      final snapshot = await FirebaseFirestore.instance
          .collection('attendance_logs')
          .where('employee_id', isEqualTo: employeeId)
          .where('date', isEqualTo: todayStr)
          .get();

      String? latestInTime;
      String? latestOutTime;
      bool clockedInState = false;
      DateTime? parsedInDateTime;

      if (snapshot.docs.isNotEmpty) {
        var docs = snapshot.docs;
        docs.sort((a, b) {
          var aTime = a.data()['timestamp'] ?? a.data()['time'] ?? '';
          var bTime = b.data()['timestamp'] ?? b.data()['time'] ?? '';
          return aTime.toString().compareTo(bTime.toString());
        });

        for (var doc in docs) {
          final data = doc.data();
          final type = data['type']?.toString().toUpperCase();
          final timeVal = data['time']?.toString() ?? '--:--';

          if (type == 'IN' || type == 'CLOCK_IN') {
            latestInTime = _formatTimeTo12Hour(timeVal);
            clockedInState = true;
            try {
              final parts = timeVal.split(':');
              if (parts.length >= 2) {
                final now = DateTime.now();
                parsedInDateTime = DateTime(
                  now.year,
                  now.month,
                  now.day,
                  int.parse(parts[0]),
                  int.parse(parts[1]),
                  parts.length > 2
                      ? int.parse(parts[2].substring(0, 2))
                      : 0,
                );
              }
            } catch (_) {}
          } else if (type == 'OUT' || type == 'CLOCK_OUT') {
            latestOutTime = _formatTimeTo12Hour(timeVal);
            clockedInState = false;
            parsedInDateTime = null;
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _isClockedIn = clockedInState;
        _clockInTime = latestInTime ?? '--:--';
        _clockOutTime = latestOutTime ?? '--:--';
        _rawClockInDateTime = parsedInDateTime;
        _isLoadingAttendance = false;
      });

      if (_isClockedIn) {
        _startElapsedTimer();
      } else {
        _durationTimer?.cancel();
      }
    } catch (e) {
      debugPrint('Error loading today attendance: $e');
      if (mounted) setState(() => _isLoadingAttendance = false);
    }
  }

  String _formatTimeTo12Hour(String t) {
    try {
      if (t.contains('AM') || t.contains('PM')) return t;
      final parts = t.split(':');
      if (parts.length < 2) return t;
      int h = int.parse(parts[0]);
      final m = parts[1];
      final period = h >= 12 ? 'PM' : 'AM';
      if (h == 0) h = 12;
      if (h > 12) h -= 12;
      return '${h.toString().padLeft(2, '0')}:$m $period';
    } catch (_) {
      return t;
    }
  }

  Future<void> _loadPayslipAmount() async {
    setState(() {
      _payslipLoading = true;
      _payslipError = false;
    });
    try {
      final employeeId =
          _employee?.employeeId ?? widget.initialEmployee?.employeeId;
      if (employeeId == null) {
        throw Exception('Walang naka-load na employee.');
      }
      final double? amount =
      await _fetchPayslipFromBackend(employeeId, _payslipMonth);
      if (!mounted) return;
      setState(() {
        _payslipAmount = amount;
        _payslipLoading = false;
      });
    } catch (e) {
      debugPrint('Payslip fetch error: $e');
      if (!mounted) return;
      setState(() {
        _payslipAmount = null;
        _payslipError = true;
        _payslipLoading = false;
      });
    }
  }

  Future<double?> _fetchPayslipFromBackend(
      String employeeId, DateTime month) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return null;
  }

  String _formatPeso(double amount) {
    final wholeStr = amount.toStringAsFixed(0);
    final buf = StringBuffer();
    for (int i = 0; i < wholeStr.length; i++) {
      final posFromEnd = wholeStr.length - i;
      buf.write(wholeStr[i]);
      if (posFromEnd > 1 && posFromEnd % 3 == 1) buf.write(',');
    }
    return '\u20b1${buf.toString()}';
  }

  static const List<String> _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  String get _payslipMonthLabel =>
      '${_monthNames[_payslipMonth.month - 1]} ${_payslipMonth.year}';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = _ThemeColors(isDark);

    return Scaffold(
      backgroundColor: tc.bg,
      body: SafeArea(
        child: RefreshIndicator(
          color: _T.orange,
          onRefresh: _loadTodayAttendance,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 160),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(tc),
                      const SizedBox(height: 20),
                      _buildStatusBanner(),
                      const SizedBox(height: 24),
                      _buildToggle(tc),
                      const SizedBox(height: 24),
                      _buildSectionTitle(
                        'Location Status',
                        tc: tc,
                        trailing: _buildGpsTag(tc),
                      ),
                      const SizedBox(height: 12),
                      _buildLocationCard(tc),
                      const SizedBox(height: 24),
                      _buildSectionTitle('Shortcuts', tc: tc),
                      const SizedBox(height: 12),
                      _buildShortcutsGrid(tc),
                      if (_isPayslipVisible) ...[
                        const SizedBox(height: 24),
                        _buildSectionTitle(
                          'Recent Payslip',
                          tc: tc,
                          viewAll: true,
                          onViewAllTap: () => widget.onTabSwitch?.call(4),
                        ),
                        const SizedBox(height: 12),
                        _buildPayslipCard(tc),
                      ],
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 20,
                right: 20,
                bottom: 20,
                child: _buildFloatingAction(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── HEADER ──────────────────────────────────────────────────────────
  Widget _buildHeader(_ThemeColors tc) {
    final name =
        _employee?.firstName ?? widget.initialEmployee?.firstName ?? 'Employee';
    final lastName =
        _employee?.lastName ?? widget.initialEmployee?.lastName ?? '';

    return Row(
      children: [
        Container(
          width: 45,
          height: 45,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: tc.darkBorder, width: 1.15),
          ),
          child: ClipOval(
            child: Container(
              color: _T.orange,
              alignment: Alignment.center,
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : 'U',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'HI, ${name.toUpperCase()} ${lastName.toUpperCase()}',
              style: TextStyle(
                fontSize: 10,
                color: tc.textGray,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Employee Dashboard',
              style: TextStyle(
                fontSize: 14,
                color: tc.textBlack,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ─── STATUS BANNER (always dark - hero card) ──────────────────────
  Widget _buildStatusBanner() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_T.r24),
        border: Border.all(color: _T.orangeBorder, width: 1.15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 40,
            spreadRadius: -8,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_T.r24 - 1.5),
        child: Stack(
          children: [
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF3A3A3A),
                      Color(0xFF1A1A1A),
                      Color(0xFF0D0D0D)
                    ],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: CustomPaint(painter: _SilkPainter()),
            ),
            Padding(
              padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                        height: 1.2,
                      ),
                      children: [
                        const TextSpan(text: 'You are currently\n'),
                        TextSpan(
                          text:
                          _isClockedIn ? 'clocked in.' : 'clocked out.',
                          style: const TextStyle(color: _T.orange),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isClockedIn
                        ? 'Our system verified your location. You are ready to go.'
                        : 'Clock in from the authorized zone to start your shift.',
                    style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFFA1A1AA),
                        height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── TOGGLE ─────────────────────────────────────────────────────────
  Widget _buildToggle(_ThemeColors tc) {
    final clocked = _isClockedIn;
    final timeIn = _clockInTime;
    final timeOut = _clockOutTime;

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_T.r18),
        gradient: _T.brandGradient,
        border: Border.all(color: _T.orange, width: 1.15),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: clocked ? null : widget.onClockAction,
              behavior: HitTestBehavior.opaque,
              child: _toggleTab(
                tc: tc,
                label: 'Clock In',
                time: _isLoadingAttendance ? 'Loading...' : timeIn,
                active: true,
                inactiveTimeColor: Colors.white,
                inactiveLabelColor: Colors.white,
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: clocked ? widget.onClockAction : null,
              behavior: HitTestBehavior.opaque,
              child: _toggleTab(
                tc: tc,
                label: 'Clock Out',
                time: _isLoadingAttendance ? 'Loading...' : timeOut,
                active: false,
                inactiveTimeColor: Colors.white,
                inactiveLabelColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggleTab({
    required _ThemeColors tc,
    required String label,
    required String time,
    required bool active,
    required Color inactiveLabelColor,
    required Color inactiveTimeColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: active ? tc.toggleActiveBg : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: active ? Border.all(color: _T.orangeBorder, width: 1) : null,
        boxShadow: active
            ? [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ]
            : null,
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: active ? tc.textBlack : inactiveLabelColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            time,
            style: TextStyle(
              fontSize: 11,
              color: active ? tc.textMuted : inactiveTimeColor,
            ),
          ),
        ],
      ),
    );
  }

  // ─── SECTION TITLE ──────────────────────────────────────────────────
  Widget _buildSectionTitle(
      String title, {
        required _ThemeColors tc,
        Widget? trailing,
        bool viewAll = false,
        VoidCallback? onViewAllTap,
      }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: tc.textBlack,
          ),
        ),
        if (trailing != null) trailing,
        if (viewAll)
          GestureDetector(
            onTap: onViewAllTap,
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              child: Text(
                'View All',
                style: TextStyle(
                  fontSize: 12,
                  color: _T.orange,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildGpsTag(_ThemeColors tc) {
    return Row(
      children: [
        Icon(Icons.near_me_rounded, size: 12, color: tc.textBlack),
        const SizedBox(width: 4),
        Text(
          'Live GPS',
          style: TextStyle(
            fontSize: 12,
            color: tc.textBlack,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }

  // ─── LOCATION CARD ──────────────────────────────────────────────────
  Widget _buildLocationCard(_ThemeColors tc) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tc.cardFill,
        borderRadius: BorderRadius.circular(_T.r20),
        border: Border.all(color: _T.orangeBorder, width: 1.15),
      ),
      child: Row(
        children: [
          Stack(
            children: [
              Container(
                width: 45,
                height: 45,
                decoration: const BoxDecoration(
                  gradient: _T.brandGradient,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.location_on_rounded,
                    color: Colors.white, size: 22),
              ),
              Positioned(
                top: 2,
                right: 2,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _T.lime,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 15),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'HQ Main Office',
                style: TextStyle(
                  fontSize: 14,
                  color: tc.textBlack,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Inside Authorized Zone',
                style: TextStyle(
                  fontSize: 12,
                  color: _T.lime,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── SHORTCUTS GRID ─────────────────────────────────────────────────
  Widget _buildShortcutsGrid(_ThemeColors tc) {
    final items = [
      (Icons.history_rounded, 'Logs', _T.orange,
          () => widget.onTabSwitch?.call(1)),
      (Icons.calendar_month_rounded, 'Leaves', _T.orangeBorder,
          () => widget.onTabSwitch?.call(2)),
      (Icons.person_rounded, 'Profile', _T.orange,
          () => widget.onTabSwitch?.call(3)),
    ];

    return Row(
      children: items.map((item) {
        final isLast = item == items.last;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: isLast ? 0 : 12),
            child: GestureDetector(
              onTap: item.$4,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding:
                const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
                decoration: BoxDecoration(
                  color: tc.cardFill,
                  borderRadius: BorderRadius.circular(_T.r20),
                  border: Border.all(color: _T.orangeBorder, width: 1.15),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: _T.brandGradient,
                        shape: BoxShape.circle,
                        border: Border.all(color: _T.orange, width: 1.15),
                      ),
                      child: Icon(item.$1, color: Colors.white, size: 20),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      item.$2,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: item.$3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ─── PAYSLIP CARD ───────────────────────────────────────────────────
  Widget _buildPayslipCard(_ThemeColors tc) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tc.cardFill,
        borderRadius: BorderRadius.circular(_T.r20),
        border: Border.all(color: _T.orange, width: 1.15),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: _T.brandGradient,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: _T.orange.withValues(alpha: 0.2), width: 1.15),
            ),
            child: const Icon(Icons.receipt_long_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _payslipMonthLabel,
                  style: TextStyle(
                    fontSize: 14,
                    color: tc.textBlack,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                _buildPayslipAmountText(tc),
              ],
            ),
          ),
          if (_payslipAmount != null && !_payslipLoading && !_payslipError)
            Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(
                  color: _T.orange, shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded,
                  color: Colors.white, size: 14),
            )
          else if (_payslipError)
            GestureDetector(
              onTap: _loadPayslipAmount,
              behavior: HitTestBehavior.opaque,
              child: const Icon(Icons.refresh_rounded,
                  color: _T.orange, size: 20),
            ),
        ],
      ),
    );
  }

  Widget _buildPayslipAmountText(_ThemeColors tc) {
    if (_payslipLoading) {
      return const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2, color: _T.orange),
      );
    }
    if (_payslipError) {
      return const Text(
        'Hindi makuha ang sahod ngayon',
        style: TextStyle(fontSize: 12, color: Colors.redAccent),
      );
    }
    if (_payslipAmount == null) {
      return Text(
        'Wala pang available na payslip',
        style: TextStyle(fontSize: 12, color: tc.textGray),
      );
    }
    return Text(
      'Amount: ${_formatPeso(_payslipAmount!)}',
      style: TextStyle(fontSize: 12, color: tc.textGray),
    );
  }

  // ─── FLOATING ACTION BAR ────────────────────────────────────────────
  Widget _buildFloatingAction() {
    if (!_isClockedIn) return const SizedBox.shrink();

    return RepaintBoundary(
      child: GestureDetector(
        onTap: () {
          debugPrint('🟢 Floating Clock Out button tapped!');
          widget.onClockAction?.call();
        },
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_T.r18),
            gradient: _T.brandGradient,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF8A00).withValues(alpha: 0.15),
                blurRadius: 40,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Clock Out (Tap to proceed)',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.timer_rounded,
                          size: 13, color: Colors.white70),
                      const SizedBox(width: 4),
                      Text(
                        'Duty Time: $_elapsedDuration',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_forward_rounded,
                    color: Colors.white, size: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom painter para sa silk texture
// ─────────────────────────────────────────────────────────────────────────────
class _SilkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.035)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    for (int i = -5; i < 20; i++) {
      final path = Path();
      final startX = i * 22.0;
      path.moveTo(startX, 0);
      path.cubicTo(
        startX + 30, size.height * 0.3,
        startX - 10, size.height * 0.7,
        startX + 20, size.height,
      );
      canvas.drawPath(path, paint);
    }

    final glowPaint = Paint()
      ..color = const Color(0xFFFF8A00).withValues(alpha: 0.06)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40);
    canvas.drawCircle(
        Offset(size.width * 0.85, size.height * 1.1), 90, glowPaint);
  }

  @override
  bool shouldRepaint(_SilkPainter old) => false;
}