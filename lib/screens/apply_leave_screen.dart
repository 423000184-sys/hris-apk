// lib/screens/apply_leave_screen.dart
// ✅ v1.1: DEMO MODE now shows the SAME skeleton loading screen as normal mode.
//         - Skeleton appears briefly (900ms), then fades into demo UI.
//         - All 3 screens (LeaveForm, History, ApplicationForm) updated.
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/admin_notification_service.dart';
import '../services/security_service.dart';
import '../services/security_hardening_service.dart';
import '../services/demo_mode_service.dart';
import '../data/local/dao/connectivity_service.dart';
import '../widgets/skeleton_screens.dart';
import 'itinerary_screen.dart';
import 'login_screen.dart';

// ═══════════════════════════════════════════════════════════════
// WATERMARK
// ═══════════════════════════════════════════════════════════════
const String _kLogoAsset = 'assets/images/logo.png';
double _degToRad(double deg) => deg * 3.1415926535 / 180;

/// 🆕 Shared demo skeleton display duration for all leave screens
const Duration _kDemoSkeletonDuration = Duration(milliseconds: 900);

Widget _buildHandWatermark({required double opacity}) {
  return Positioned(
    bottom: -130, left: -150,
    child: IgnorePointer(
      child: Transform.rotate(
        angle: _degToRad(425),
        child: Opacity(
          opacity: opacity,
          child: ColorFiltered(
            colorFilter: const ColorFilter.mode(
                Color.fromRGBO(255, 138, 0, 0.10), BlendMode.srcIn),
            child: Image.asset(_kLogoAsset, width: 500, height: 500,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox.shrink()),
          ),
        ),
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════
// LEAVE FETCH
// ═══════════════════════════════════════════════════════════════
Future<List<Map<String, dynamic>>> _fetchEmployeeLeaves(String empKey) async {
  // 🎭 DEMO MODE — return fake data, walang Firestore read
  if (DemoModeService.instance.isEnabled) {
    return DemoModeService.instance.demoLeaveHistory
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
  final key = empKey.trim();
  if (key.isEmpty) return [];
  final firestore = FirebaseFirestore.instance;
  final uniqueDocs = <String, Map<String, dynamic>>{};
  const identifierFields = ['employeeId', 'employee_id', 'employeeDocId',
    'employeeCode', 'employeeAuthUid', 'employeeEmail'];
  for (final field in identifierFields) {
    try {
      final snap = await firestore.collection('leave_applications')
          .where(field, isEqualTo: key).get()
          .timeout(const Duration(seconds: 10));
      for (var doc in snap.docs) {
        uniqueDocs.putIfAbsent(doc.id,
                () => <String, dynamic>{...doc.data(), 'id': doc.id});
      }
    } catch (e) { debugPrint('⚠️ [LeaveFetch] "$field" failed: $e'); }
  }
  return uniqueDocs.values.toList();
}

// ═══════════════════════════════════════════════════════════════
// GENDER FETCH
// ═══════════════════════════════════════════════════════════════
Future<String> _fetchEmployeeGender(String empKey) async {
  // 🎭 DEMO MODE — fixed gender
  if (DemoModeService.instance.isEnabled) return 'male';
  final key = empKey.trim();
  if (key.isEmpty) return 'unknown';
  final firestore = FirebaseFirestore.instance;
  String extractGender(Map<String, dynamic>? data) {
    if (data == null) return '';
    final raw = data['gender'] ?? data['sex'] ?? data['Gender'] ??
        data['Sex'] ?? data['GENDER'] ?? data['genderType'] ??
        data['employee_gender'] ?? '';
    return raw.toString().toLowerCase().trim();
  }
  try {
    final doc = await firestore.collection('employees').doc(key)
        .get().timeout(const Duration(seconds: 8));
    if (doc.exists) {
      final g = extractGender(doc.data());
      if (g.isNotEmpty) return g;
    }
  } catch (_) {}
  const empFields = ['employeeId', 'employee_id', 'email', 'authUid', 'uid'];
  for (final f in empFields) {
    try {
      final snap = await firestore.collection('employees')
          .where(f, isEqualTo: key).limit(1).get()
          .timeout(const Duration(seconds: 8));
      if (snap.docs.isNotEmpty) {
        final g = extractGender(snap.docs.first.data());
        if (g.isNotEmpty) return g;
      }
    } catch (_) {}
  }
  try {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser != null) {
      final snap = await firestore.collection('employees')
          .where('authUid', isEqualTo: authUser.uid).limit(1).get()
          .timeout(const Duration(seconds: 8));
      if (snap.docs.isNotEmpty) {
        final g = extractGender(snap.docs.first.data());
        if (g.isNotEmpty) return g;
      }
    }
  } catch (_) {}
  return 'unknown';
}

String _normalizeGender(String raw) {
  final g = raw.toLowerCase().trim();
  if (g.isEmpty) return 'unknown';
  const maleValues = {'male', 'm', 'man', 'lalaki', 'lalake', 'lala', 'boy', 'kuya'};
  const femaleValues = {'female', 'f', 'woman', 'babae', 'babayi', 'ate', 'girl'};
  if (maleValues.contains(g)) return 'male';
  if (femaleValues.contains(g)) return 'female';
  if (g.startsWith('mal') || g == 'm') return 'male';
  if (g.startsWith('fem') || g == 'f') return 'female';
  return 'unknown';
}

// ═══════════════════════════════════════════════════════════════
// SECURITY HELPERS
// ═══════════════════════════════════════════════════════════════
String _sanitizeInput(String input, {int maxLength = 500}) {
  if (input.isEmpty) return '';
  final sanitized = input
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '').trim();
  if (sanitized.length <= maxLength) return sanitized;
  return sanitized.substring(0, maxLength);
}

String _generateLeaveTxnId() {
  final ts = DateTime.now().millisecondsSinceEpoch;
  final rand = math.Random.secure();
  final randHex = rand.nextInt(0x7FFFFFFF).toRadixString(16).padLeft(8, '0');
  return 'LV-$ts-$randHex';
}

String _generateSessionNonce() {
  final rand = math.Random.secure();
  final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

Future<void> _logSecurityEvent({
  required String type,
  required String severity,
  required String details,
  String? employeeId,
  String? sessionNonce,
}) async {
  // 🎭 DEMO MODE — skip Firestore write
  if (DemoModeService.instance.isEnabled) {
    debugPrint('🎭 [DemoMode] Security event (skipped): $type — $details');
    return;
  }
  try {
    await FirebaseFirestore.instance.collection('security_events').add({
      'type': type, 'severity': severity, 'details': details,
      'employeeId': employeeId, 'sessionNonce': sessionNonce,
      'platform': kIsWeb ? 'web' : 'mobile',
      'stage': 'leave_application',
      'timestamp': FieldValue.serverTimestamp(),
    }).timeout(const Duration(seconds: 3));
  } catch (e) { debugPrint('⚠️ [LeaveSecurity] log error: $e'); }
}

enum _NetworkState { online, offline, checking }

class _ThemeColors {
  final bool isDark;
  const _ThemeColors(this.isDark);
  Color get bg => isDark ? const Color(0xFF0F0F10) : const Color(0xFFFFFFFF);
  Color get cardBg => isDark ? const Color(0xFF18181B) : const Color(0xFFFFFFFF);
  Color get cardFill => isDark ? const Color(0xFF1F1F23) : const Color.fromRGBO(131, 131, 131, 0.07);
  Color get textBlack => isDark ? Colors.white : const Color(0xFF000000);
  Color get textGray => isDark ? const Color(0xFFB0B0B0) : const Color(0xFF71717A);
  Color get textMuted => isDark ? const Color(0xFF888888) : const Color(0xFF9CA3AF);
  Color get border => isDark ? const Color(0xFF27272A) : const Color(0xFFE5E7EB);
  Color get darkBorder => isDark ? const Color(0xFF3F3F46) : const Color(0xFF27272A);
  Color get navBg => isDark ? const Color(0xFF18181B) : Colors.white;
  Color get navUnselected => isDark ? const Color(0xFF888888) : const Color(0xFF71717A);
  Color get softCard => isDark ? const Color(0xFF1F1F23) : const Color(0xFFF8F8F8);
  Color get softBorder => isDark ? const Color(0xFF3F3F46) : const Color(0xFFFFA500);
  double get watermarkOpacity => isDark ? 0.15 : 0.80;
}

class _T {
  static const Color orange = Color(0xFFFF8A00);
  static const Color orangeBorder = Color(0xFFFFA500);
  static const Color orangeLight = Color(0xFFFA6A00);
  static const Color orangeHot = Color(0xFFF54900);
  static const Color neonGreen = Color(0xFFC4FF0A);
  static const Color green = Color(0xFF16A34A);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFDC2626);
  static const Color info = Color(0xFF2563EB);
  static const Color white = Color(0xFFFFFFFF);
  static const LinearGradient brandGradient = LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [orange, orangeLight, orangeHot], stops: [0.0, 0.5, 1.0]);
  static const double r12 = 12;
  static const double r14 = 14;
  static const double r16 = 16;
  static const double r20 = 20;
}

const int kAnnualLeaveTotal = 18;
const int kSickLeaveTotal = 18;
const int kTotalLeaveCredits = kAnnualLeaveTotal + kSickLeaveTotal;
bool _isAnnual(String code) => code.toUpperCase() == 'VL';
bool _isSick(String code) => code.toUpperCase() == 'SL';

class _LeaveType {
  final String code;
  final String label;
  final IconData icon;
  const _LeaveType(this.code, this.label, this.icon);
}

const _baseLeaveTypes = [
  _LeaveType('SL', 'Sick', Icons.medical_services_rounded),
  _LeaveType('VL', 'Vacation', Icons.beach_access_rounded),
];
const _maternityType = _LeaveType('ML', 'Maternity', Icons.child_friendly_rounded);
const _paternityType = _LeaveType('PL', 'Paternity', Icons.child_friendly_rounded);

List<_LeaveType> _leaveTypesForGender(String gender) {
  final g = _normalizeGender(gender);
  switch (g) {
    case 'male': return [..._baseLeaveTypes, _paternityType];
    case 'female': return [..._baseLeaveTypes, _maternityType];
    default: return List<_LeaveType>.from(_baseLeaveTypes);
  }
}

int _safeInt(dynamic v, [int fallback = 0]) {
  if (v == null) return fallback;
  if (v is int) return v;
  if (v is double) return v.toInt();
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? fallback;
}

class _LeaveStats {
  int usedAnnual = 0;
  int usedSick = 0;
  int usedOther = 0;
  int pendingCount = 0;
  int get totalCredits => kTotalLeaveCredits;
  int get usedTotal => usedAnnual + usedSick + usedOther;
  int get remaining => (totalCredits - usedTotal).clamp(0, totalCredits);
}

_LeaveStats _computeStats(List<Map<String, dynamic>> history) {
  final s = _LeaveStats();
  for (final h in history) {
    final status = (h['status'] ?? 'pending').toString().toLowerCase();
    final code = (h['leaveType'] ?? 'SL').toString();
    final days = _safeInt(h['days'], 1);
    if (status == 'approved') {
      if (_isSick(code)) { s.usedSick += days; }
      else if (_isAnnual(code)) { s.usedAnnual += days; }
      else { s.usedOther += days; }
    } else if (status == 'pending') { s.pendingCount++; }
  }
  return s;
}

String _leaveTypeLabel(String code) {
  const map = {'SL': 'Sick Leave', 'VL': 'Vacation Leave',
    'EL': 'Emergency Leave', 'BL': 'Bereavement Leave',
    'ML': 'Maternity Leave', 'PL': 'Paternity Leave'};
  return map[code] ?? code;
}

String _formatDate(dynamic dateStr) {
  if (dateStr == null) return 'N/A';
  try {
    if (dateStr is Timestamp) return DateFormat('MMM d, yyyy').format(dateStr.toDate());
    if (dateStr is String) return DateFormat('MMM d, yyyy').format(DateTime.parse(dateStr));
    return 'N/A';
  } catch (_) { return dateStr.toString(); }
}

String _formatDateTime(dynamic dateStr) {
  if (dateStr == null) return 'N/A';
  try {
    if (dateStr is Timestamp) return DateFormat('MMM d, yyyy • hh:mm a').format(dateStr.toDate());
    if (dateStr is String) return DateFormat('MMM d, yyyy • hh:mm a').format(DateTime.parse(dateStr));
    return 'N/A';
  } catch (_) { return dateStr.toString(); }
}

// ═══════════════════════════════════════════════════════════════
// BIG ITINERARY BUTTON
// ═══════════════════════════════════════════════════════════════
Widget _buildBigItineraryButton({required VoidCallback onTap}) {
  return GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: _T.brandGradient,
        borderRadius: BorderRadius.circular(_T.r16),
        border: Border.all(color: _T.orangeBorder, width: 1.2),
        boxShadow: [BoxShadow(color: _T.orange.withValues(alpha: 0.35),
            blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Row(
        children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 1.2),
            ),
            child: const Icon(Icons.assignment_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('VIEW ITINERARY', style: TextStyle(color: Colors.white,
                    fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                SizedBox(height: 3),
                Text('Check your schedule and assignments',
                    style: TextStyle(color: Colors.white70, fontSize: 11,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1),
            ),
            child: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
          ),
        ],
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════
// NETWORK ERROR OVERLAY
// ═══════════════════════════════════════════════════════════════
Widget _buildNetworkErrorOverlay({required String message, required VoidCallback onRetry}) {
  return Container(
    color: Colors.black.withValues(alpha: 0.72),
    child: Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 380),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: _T.brandGradient,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white, width: 1.15),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 20, offset: const Offset(0, 12))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.2),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 1.5),
                ),
                child: const Icon(Icons.wifi_off_rounded, color: Colors.white, size: 40),
              ),
              const SizedBox(height: 20),
              const Text('No Connection', textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 20,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Text(message, textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.92),
                      fontSize: 13, height: 1.5)),
              const SizedBox(height: 24),
              SizedBox(
                width: 180,
                child: ElevatedButton.icon(
                  onPressed: onRetry,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white, foregroundColor: _T.orange,
                    padding: const EdgeInsets.symmetric(vertical: 14), elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Try Again',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════
// SHARED: LEAVE DETAILS BOTTOM SHEET
// ═══════════════════════════════════════════════════════════════
void _showLeaveDetailsSheet(BuildContext context, Map<String, dynamic> item,
    {String? employeeName}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final tc = _ThemeColors(isDark);
  final status = (item['status'] ?? 'pending').toString();
  final statusLower = status.toLowerCase();
  final isApproved = statusLower == 'approved';
  final isPending = statusLower == 'pending';
  final badgeBg = isApproved ? _T.neonGreen.withValues(alpha: 0.15)
      : (isPending ? _T.orange.withValues(alpha: 0.15) : _T.error.withValues(alpha: 0.15));
  final badgeBorder = isApproved ? _T.neonGreen.withValues(alpha: 0.3)
      : (isPending ? _T.orange.withValues(alpha: 0.3) : _T.error.withValues(alpha: 0.3));
  final badgeText = isApproved ? _T.neonGreen : (isPending ? _T.orange : _T.error);

  showModalBottomSheet(
    context: context, isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (ctx) => Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
      decoration: BoxDecoration(
        color: tc.bg,
        borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24), topRight: Radius.circular(24)),
        border: Border.all(color: _T.orangeBorder.withValues(alpha: 0.4), width: 1.2),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Container(width: 44, height: 5,
                  decoration: BoxDecoration(
                      color: tc.darkBorder.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(3))),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
              child: Row(
                children: [
                  Container(width: 40, height: 40,
                      decoration: BoxDecoration(
                          gradient: _T.brandGradient,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _T.orangeBorder, width: 1.1)),
                      child: const Icon(Icons.description_rounded,
                          color: Colors.white, size: 20)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Leave Details',
                            style: TextStyle(color: tc.textBlack, fontSize: 17,
                                fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                        Text('Application summary',
                            style: TextStyle(color: tc.textMuted, fontSize: 11)),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(ctx).pop(),
                    behavior: HitTestBehavior.opaque,
                    child: Container(width: 32, height: 32,
                        decoration: BoxDecoration(
                            color: tc.cardFill,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: tc.darkBorder.withValues(alpha: 0.3))),
                        child: Icon(Icons.close_rounded, color: tc.textGray, size: 18)),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: tc.darkBorder.withValues(alpha: 0.15)),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                            color: badgeBg,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: badgeBorder, width: 1.2)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                                isApproved ? Icons.check_circle_rounded
                                    : (isPending ? Icons.access_time_rounded
                                    : Icons.cancel_rounded),
                                color: badgeText, size: 18),
                            const SizedBox(width: 8),
                            Text(isApproved ? 'Approved'
                                : (isPending ? 'Pending' : 'Rejected'),
                                style: TextStyle(color: badgeText, fontSize: 13,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                          gradient: _T.brandGradient,
                          borderRadius: BorderRadius.circular(_T.r16),
                          border: Border.all(color: _T.orangeBorder, width: 1.15),
                          boxShadow: [BoxShadow(color: _T.orange.withValues(alpha: 0.25),
                              blurRadius: 18, offset: const Offset(0, 8))]),
                      child: Row(
                        children: [
                          Container(width: 44, height: 44,
                              decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(_T.r14),
                                  border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.25))),
                              child: const Icon(Icons.event_available_rounded,
                                  color: Colors.white, size: 22)),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_leaveTypeLabel(
                                    (item['leaveType'] ?? 'SL').toString()),
                                    style: const TextStyle(color: Colors.white,
                                        fontSize: 16, fontWeight: FontWeight.w800)),
                                const SizedBox(height: 2),
                                Text('${item['days'] ?? 1} day(s) filed',
                                    style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.85),
                                        fontSize: 12, fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    _detailsLabel(tc, 'APPLICATION INFO'),
                    const SizedBox(height: 10),
                    _detailsRow(tc, icon: Icons.tag_rounded, label: 'Reference ID',
                        value: (item['id'] ?? 'N/A').toString(), isMono: true),
                    _detailsRow(tc, icon: Icons.event_note_rounded, label: 'Leave Type',
                        value: _leaveTypeLabel((item['leaveType'] ?? 'SL').toString())),
                    _detailsRow(tc, icon: Icons.calendar_today_rounded, label: 'Start Date',
                        value: _formatDate(item['startDate'])),
                    _detailsRow(tc, icon: Icons.event_rounded, label: 'End Date',
                        value: _formatDate(item['endDate'])),
                    _detailsRow(tc, icon: Icons.hourglass_bottom_rounded, label: 'Duration',
                        value: '${item['days'] ?? 1} day(s)'),
                    _detailsRow(tc, icon: Icons.timelapse_rounded, label: 'Filed On',
                        value: _formatDateTime(item['createdAt'])),
                    const SizedBox(height: 18),
                    _detailsLabel(tc, 'JUSTIFICATION / REASON'),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                          color: tc.cardFill,
                          borderRadius: BorderRadius.circular(_T.r12),
                          border: Border.all(color: tc.darkBorder.withValues(alpha: 0.15))),
                      child: Text(
                        (item['reason'] ?? '').toString().trim().isEmpty
                            ? 'No reason provided.'
                            : (item['reason'] ?? '').toString(),
                        style: TextStyle(color: tc.textBlack, fontSize: 13, height: 1.5,
                            fontStyle: (item['reason'] ?? '').toString().trim().isEmpty
                                ? FontStyle.italic : FontStyle.normal),
                      ),
                    ),
                    if (employeeName != null && employeeName.trim().isNotEmpty) ...[
                      const SizedBox(height: 18),
                      _detailsLabel(tc, 'FILED BY'),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                            color: tc.cardFill,
                            borderRadius: BorderRadius.circular(_T.r12),
                            border: Border.all(color: tc.darkBorder.withValues(alpha: 0.15))),
                        child: Row(
                          children: [
                            Container(width: 38, height: 38,
                                decoration: BoxDecoration(
                                    gradient: _T.brandGradient, shape: BoxShape.circle),
                                child: Center(
                                  child: Text(
                                      employeeName.trim().substring(0, 1).toUpperCase(),
                                      style: const TextStyle(color: Colors.white,
                                          fontSize: 16, fontWeight: FontWeight.w800)),
                                )),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(employeeName, style: TextStyle(
                                  color: tc.textBlack, fontSize: 14,
                                  fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    GestureDetector(
                      onTap: () => Navigator.of(ctx).pop(),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        width: double.infinity, height: 50,
                        decoration: BoxDecoration(
                            gradient: _T.brandGradient,
                            borderRadius: BorderRadius.circular(_T.r16),
                            border: Border.all(color: _T.orangeBorder, width: 1.15),
                            boxShadow: [BoxShadow(
                                color: _T.orange.withValues(alpha: 0.3),
                                blurRadius: 16, offset: const Offset(0, 6))]),
                        child: const Center(
                          child: Text('Close', style: TextStyle(color: Colors.white,
                              fontSize: 14, fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _detailsLabel(_ThemeColors tc, String text) => Text(text,
    style: TextStyle(color: tc.textMuted, fontSize: 10,
        fontWeight: FontWeight.w800, letterSpacing: 1.4));

Widget _detailsRow(_ThemeColors tc, {required IconData icon,
  required String label, required String value, bool isMono = false}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
          color: tc.cardFill,
          borderRadius: BorderRadius.circular(_T.r12),
          border: Border.all(color: tc.darkBorder.withValues(alpha: 0.12))),
      child: Row(
        children: [
          Icon(icon, color: _T.orange, size: 18),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: TextStyle(color: tc.textGray,
              fontSize: 12, fontWeight: FontWeight.w600))),
          const SizedBox(width: 8),
          Flexible(child: Text(value, style: TextStyle(color: tc.textBlack,
              fontSize: 13, fontWeight: FontWeight.w700,
              fontFamily: isMono ? 'monospace' : null),
              overflow: TextOverflow.ellipsis, textAlign: TextAlign.right)),
        ],
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════
// SCREEN 1: LEAVE APPLICATION FORM
// ═══════════════════════════════════════════════════════════════
class LeaveApplicationFormScreen extends StatefulWidget {
  final String employeeId;
  final String employeeName;
  final VoidCallback? onBack;
  const LeaveApplicationFormScreen({super.key,
    required this.employeeId, required this.employeeName, this.onBack});
  @override
  State<LeaveApplicationFormScreen> createState() => _LeaveApplicationFormScreenState();
}

class _LeaveApplicationFormScreenState extends State<LeaveApplicationFormScreen>
    with WidgetsBindingObserver {
  _LeaveStats _stats = _LeaveStats();
  List<Map<String, dynamic>> _leaveHistory = [];
  bool _loading = true;
  String? _error;
  _NetworkState _networkState = _NetworkState.online;
  String _networkErrorMessage = 'No internet connection.';
  bool _showOfflineOverlay = false;
  Timer? _overlayDelayTimer;
  bool _isInitialLoading = true;
  StreamSubscription<bool>? _networkSub;
  static const Duration _sessionCacheTTL = Duration(seconds: 5);
  static const Duration _inactivityLimit = Duration(minutes: 30);
  late final String _sessionNonce;
  Timer? _heartbeatTimer;
  Timer? _inactivityTimer;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sessionSub;
  bool _loggedOut = false;
  bool _sessionValidated = false;
  DateTime? _lastUserActivityAt;
  bool? _cachedSessionValid;
  DateTime? _cachedSessionTime;
  String? _verifiedEmployeeId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sessionNonce = _generateSessionNonce();
    _lastUserActivityAt = DateTime.now();

    // ═══════════════════════════════════════════════════════════
    // 🎭 DEMO MODE — skip network listener, security monitoring
    //             pero IPAKITA ANG SKELETON sa simula
    // ═══════════════════════════════════════════════════════════
    if (DemoModeService.instance.isEnabled) {
      debugPrint('═══════════════════════════════════════════');
      debugPrint('🎭 [DemoMode] Leave Application Form — DEMO PATH');
      debugPrint('   • Skeleton shown for ${_kDemoSkeletonDuration.inMilliseconds}ms');
      debugPrint('═══════════════════════════════════════════');

      _networkState = _NetworkState.online;
      _sessionValidated = true;
      _verifiedEmployeeId = widget.employeeId;

      // 🆕 Keep skeleton visible at start
      _isInitialLoading = true;

      _fetchLeaveData();

      // 🆕 Hide skeleton after short delay
      Future.delayed(_kDemoSkeletonDuration, () {
        if (!mounted) return;
        setState(() => _isInitialLoading = false);
        debugPrint('🎭 [DemoMode] Skeleton hidden — demo UI revealed');
      });

      return;
    }

    try {
      _networkSub = ConnectivityService.instance.onStatusChange.listen((online) {
        if (!mounted || _loggedOut) return;
        if (!online) {
          _overlayDelayTimer?.cancel();
          setState(() {
            _networkState = _NetworkState.offline;
            _networkErrorMessage = 'No internet connection.\nPlease check your network.';
            _showOfflineOverlay = false;
          });
          _overlayDelayTimer = Timer(const Duration(milliseconds: 1200), () {
            if (mounted && _networkState == _NetworkState.offline) {
              setState(() => _showOfflineOverlay = true);
            }
          });
        } else if (_networkState == _NetworkState.offline) {
          _overlayDelayTimer?.cancel();
          _showOfflineOverlay = false;
          _retryNetworkCheck();
        }
      });
    } catch (e) { debugPrint('⚠️ connectivity failed: $e'); }
    _startSecurityMonitoring();
    _checkNetworkOnEntry().then((_) {
      if (mounted) {
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) setState(() => _isInitialLoading = false);
        });
      }
    });
    _validateSession(forceRefresh: true).then((valid) {
      if (!mounted || _loggedOut) return;
      if (!valid) { _forceLogout('Initial session invalid'); return; }
      _fetchLeaveData();
    });
  }

  Future<bool> _validateSession({bool forceRefresh = false}) async {
    // 🎭 DEMO MODE — always valid
    if (DemoModeService.instance.isEnabled) return true;
    if (_loggedOut) return false;
    if (!forceRefresh && _cachedSessionValid != null && _cachedSessionTime != null &&
        DateTime.now().difference(_cachedSessionTime!) < _sessionCacheTTL) {
      return _cachedSessionValid!;
    }
    try {
      final valid = await SecurityService.instance.isSessionValid()
          .timeout(const Duration(seconds: 5));
      if (!valid) {
        await _logSecurityEvent(type: 'leave_session_invalid',
            severity: 'high', details: 'Session expired',
            employeeId: widget.employeeId, sessionNonce: _sessionNonce);
        _cachedSessionValid = false;
        _cachedSessionTime = DateTime.now();
        return false;
      }
      final sessionEmpId = await SecurityService.instance.getCurrentEmployeeId();
      final matches = sessionEmpId == null || sessionEmpId.isEmpty ||
          sessionEmpId == widget.employeeId;
      if (!matches) {
        await _logSecurityEvent(type: 'leave_cross_access',
            severity: 'critical',
            details: 'Session ($sessionEmpId) != viewing (${widget.employeeId})',
            employeeId: widget.employeeId, sessionNonce: _sessionNonce);
        _cachedSessionValid = false;
        _cachedSessionTime = DateTime.now();
        return false;
      }
      _verifiedEmployeeId = sessionEmpId ?? widget.employeeId;
      _cachedSessionValid = true;
      _cachedSessionTime = DateTime.now();
      return true;
    } catch (e) {
      _cachedSessionValid = false;
      _cachedSessionTime = DateTime.now();
      return false;
    }
  }

  Future<void> _forceLogout(String reason) async {
    // 🎭 DEMO MODE — ignore logout
    if (DemoModeService.instance.isEnabled) {
      debugPrint('🎭 [DemoMode] Force logout ignored: $reason');
      return;
    }
    if (_loggedOut || !mounted) return;
    _loggedOut = true;
    _heartbeatTimer?.cancel();
    _inactivityTimer?.cancel();
    _sessionSub?.cancel();
    _networkSub?.cancel();
    _overlayDelayTimer?.cancel();
    try { await Clipboard.setData(const ClipboardData(text: '')); } catch (_) {}
    try { await SecurityHardeningService.instance.clearSession(); } catch (_) {}
    try { await SecurityService.instance.clearSession(); } catch (_) {}
    await _logSecurityEvent(type: 'leave_forced_logout', severity: 'high',
        details: 'Force logout: $reason',
        employeeId: widget.employeeId, sessionNonce: _sessionNonce);
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen(),
            settings: const RouteSettings(name: '/login')), (route) => false);
  }

  void _startSecurityMonitoring() {
    // 🎭 DEMO MODE — skip
    if (DemoModeService.instance.isEnabled) return;
    if (widget.employeeId.isNotEmpty) {
      _sessionSub?.cancel();
      _sessionSub = FirebaseFirestore.instance.collection('sessions')
          .doc(widget.employeeId).snapshots().listen((snap) {
        if (!mounted || _loggedOut) return;
        final data = snap.data();
        if (data == null) return;
        if (data['revoked'] == true) { _forceLogout('Session revoked by admin'); return; }
        final expiresAt = data['expiresAt'] as Timestamp?;
        if (expiresAt != null && expiresAt.toDate().isBefore(DateTime.now())) {
          _forceLogout('Session expired');
        }
      }, onError: (e) => debugPrint('Session listener error: $e'));
    }
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 2), (_) async {
      if (!mounted || _loggedOut) return;
      try {
        await SecurityService.instance.markSessionActive();
        final valid = await _validateSession(forceRefresh: true);
        if (!valid && mounted && !_loggedOut) await _forceLogout('Session invalidated');
      } catch (e) { debugPrint('⚠️ Heartbeat failed: $e'); }
    });
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      if (!mounted || _loggedOut) return;
      if (_lastUserActivityAt == null) return;
      final idle = DateTime.now().difference(_lastUserActivityAt!);
      if (idle > _inactivityLimit) await _forceLogout('Inactivity (${idle.inMinutes}m)');
    });
    _validateSession(forceRefresh: true).then((valid) {
      if (mounted) setState(() => _sessionValidated = valid);
    });
  }

  void _recordActivity() { _lastUserActivityAt = DateTime.now(); }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _networkSub?.cancel();
    _sessionSub?.cancel();
    _overlayDelayTimer?.cancel();
    _heartbeatTimer?.cancel();
    _inactivityTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _recordActivity();
      if (DemoModeService.instance.isEnabled) return;
      _validateSession(forceRefresh: true).then((valid) {
        if (!valid && mounted && !_loggedOut) _forceLogout('Session invalid on resume');
      });
    }
  }

  Future<void> _checkNetworkOnEntry() async {
    // 🎭 DEMO MODE — always online
    if (DemoModeService.instance.isEnabled) {
      if (mounted) setState(() => _networkState = _NetworkState.online);
      return;
    }
    if (!mounted) return;
    setState(() => _networkState = _NetworkState.checking);
    bool hasNet = true;
    try { hasNet = ConnectivityService.instance.isOnline; } catch (_) { hasNet = true; }
    if (!mounted) return;
    if (!hasNet) {
      setState(() {
        _networkState = _NetworkState.offline;
        _networkErrorMessage = 'No internet connection.\nPlease check your network and try again.';
      });
      return;
    }
    setState(() => _networkState = _NetworkState.online);
  }

  Future<void> _retryNetworkCheck() async {
    if (!mounted || _loggedOut) return;
    _recordActivity();
    setState(() { _networkState = _NetworkState.checking; _showOfflineOverlay = false; });
    await _checkNetworkOnEntry();
    if (_networkState == _NetworkState.online && mounted && !_loggedOut) {
      try { await _fetchLeaveData(); }
      catch (e) { debugPrint('⚠️ Retry refresh failed: $e'); }
    }
  }

  void refreshData() { _recordActivity(); _fetchLeaveData(); }

  Future<void> _fetchLeaveData() async {
    if (!mounted || _loggedOut) return;

    // 🎭 DEMO MODE — load fake data
    if (DemoModeService.instance.isEnabled) {
      setState(() { _loading = true; _error = null; });
      await Future.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      final history = DemoModeService.instance.demoLeaveHistory
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      history.sort((a, b) {
        final aTime = a['createdAt'];
        final bTime = b['createdAt'];
        if (aTime is DateTime && bTime is DateTime) return bTime.compareTo(aTime);
        return 0;
      });
      final stats = _computeStats(history);
      setState(() { _leaveHistory = history; _stats = stats; _loading = false; });
      return;
    }

    final valid = await _validateSession();
    if (!valid) {
      if (mounted && !_loggedOut) _forceLogout('Session invalid');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final rawDocs = await _fetchEmployeeLeaves(widget.employeeId);
      final List<Map<String, dynamic>> history = [];
      for (var data in rawDocs) {
        history.add({
          'id': data['id'], 'leaveType': data['leaveType'] ?? 'SL',
          'startDate': data['startDate'], 'endDate': data['endDate'],
          'days': _safeInt(data['days'], 1), 'status': data['status'] ?? 'pending',
          'reason': data['reason'] ?? '', 'createdAt': data['createdAt'],
        });
      }
      history.sort((a, b) {
        final aTime = a['createdAt'] as Timestamp?;
        final bTime = b['createdAt'] as Timestamp?;
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });
      final stats = _computeStats(history);
      if (!mounted || _loggedOut) return;
      setState(() { _leaveHistory = history; _stats = stats; _loading = false; });
    } catch (e) {
      debugPrint('Error fetching leave history: $e');
      if (!mounted) return;
      setState(() { _loading = false;
      _error = 'Failed to load leave data. Please try again.'; });
    }
  }

  void _openItinerary() {
    _recordActivity();
    if (_loggedOut) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (context) => ItineraryScreen(
        employeeId: widget.employeeId, employeeName: widget.employeeName,
        onGoHome: () { refreshData();
        if (Navigator.canPop(context)) Navigator.pop(context); },
      ),
    )).then((_) => refreshData());
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = _ThemeColors(isDark);
    final isOffline = _networkState == _NetworkState.offline;
    final isChecking = _networkState == _NetworkState.checking;
    if (isOffline || isChecking || _isInitialLoading) {
      return Scaffold(
        backgroundColor: tc.bg,
        body: SafeArea(child: Stack(children: [
          const ListSkeleton(itemCount: 5),
          if (isOffline) Positioned.fill(
            child: AnimatedOpacity(
              opacity: _showOfflineOverlay ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeInOut,
              child: IgnorePointer(ignoring: !_showOfflineOverlay,
                  child: _buildNetworkErrorOverlay(
                      message: _networkErrorMessage, onRetry: _retryNetworkCheck)),
            ),
          ),
        ])),
      );
    }
    return Scaffold(
      backgroundColor: tc.bg,
      body: SafeArea(bottom: false, child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          _buildHandWatermark(opacity: tc.watermarkOpacity),
          Column(children: [Expanded(child: _buildMainContent(tc))]),
        ],
      )),
    );
  }

  Widget _buildMainContent(_ThemeColors tc) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
          decoration: BoxDecoration(
            gradient: _T.brandGradient,
            borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
            border: Border(bottom: BorderSide(color: tc.darkBorder, width: 1.11)),
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: () {
                  _recordActivity();
                  if (widget.onBack != null) { widget.onBack!(); }
                  else if (Navigator.canPop(context)) { Navigator.pop(context); }
                },
                child: const Icon(Icons.arrow_back_ios_rounded,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Text('Leave Application Form',
                    style: TextStyle(color: Colors.white, fontSize: 20,
                        fontWeight: FontWeight.w500)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 24),
            child: _buildBigItineraryButton(onTap: _openItinerary)),
        const SizedBox(height: 20),
        if (_loading)
          const Padding(padding: EdgeInsets.symmetric(horizontal: 24),
              child: Center(child: CircularProgressIndicator()))
        else if (_error != null)
          Padding(padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Center(child: Column(children: [
                Text(_error!, style: const TextStyle(color: _T.error)),
                const SizedBox(height: 8),
                ElevatedButton(onPressed: _fetchLeaveData, child: const Text('Retry')),
              ])))
        else
          Padding(padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(children: [
                _statCard(tc, label: 'Total', value: '${_stats.totalCredits}',
                    valueColor: tc.textBlack, labelColor: tc.textGray),
                const SizedBox(width: 12),
                _statCard(tc, label: 'Used', value: '${_stats.usedTotal}',
                    valueColor: _T.neonGreen, labelColor: tc.textGray),
                const SizedBox(width: 12),
                _statCard(tc, label: 'Remaining', value: '${_stats.remaining}',
                    valueColor: _T.orange, labelColor: _T.orange, isHighlighted: true),
              ])),
        const SizedBox(height: 20),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(children: [
              Expanded(child: Align(alignment: Alignment.centerLeft,
                  child: Text('Leave History', style: TextStyle(color: tc.textBlack,
                      fontSize: 14, fontWeight: FontWeight.w500)))),
              if (!_loading && _leaveHistory.isNotEmpty)
                Text('Tap card for details', style: TextStyle(color: tc.textMuted,
                    fontSize: 10, fontStyle: FontStyle.italic)),
            ])),
        const SizedBox(height: 10),
        Expanded(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: _loading ? const Center(child: CircularProgressIndicator())
              : _leaveHistory.isEmpty ? Center(child: Text('No leave history yet.',
              style: TextStyle(color: tc.textGray)))
              : ListView.builder(itemCount: _leaveHistory.length,
              itemBuilder: (ctx, index) => _historyCard(tc, _leaveHistory[index])),
        )),
      ],
    );
  }

  Widget _historyCard(_ThemeColors tc, Map<String, dynamic> item) {
    final leaveType = _leaveTypeLabel(item['leaveType']);
    final start = _formatDate(item['startDate']);
    final end = _formatDate(item['endDate']);
    final days = item['days'];
    final status = (item['status'] ?? 'pending').toString();
    final statusLower = status.toLowerCase();
    final isApproved = statusLower == 'approved';
    final isPending = statusLower == 'pending';
    final badgeBg = isApproved ? _T.neonGreen.withValues(alpha: 0.1)
        : (isPending ? _T.orange.withValues(alpha: 0.1) : _T.error.withValues(alpha: 0.1));
    final badgeBorder = isApproved ? _T.neonGreen.withValues(alpha: 0.2)
        : (isPending ? _T.orange.withValues(alpha: 0.2) : _T.error.withValues(alpha: 0.2));
    final badgeText = isApproved ? _T.neonGreen : (isPending ? _T.orange : _T.error);
    return GestureDetector(
      onTap: () { _recordActivity();
      _showLeaveDetailsSheet(context, item, employeeName: widget.employeeName); },
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: tc.softCard, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: tc.softBorder, width: 1.11),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Expanded(child: Row(children: [
                const Icon(Icons.description_rounded, color: _T.orange, size: 14),
                const SizedBox(width: 6),
                Flexible(child: Text(leaveType, style: TextStyle(
                    color: tc.textBlack, fontSize: 14, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis)),
              ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: badgeBg, borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: badgeBorder, width: 1.11)),
                child: Text(isApproved ? 'Approved'
                    : (isPending ? 'Pending' : 'Rejected'),
                    style: TextStyle(color: badgeText, fontSize: 10,
                        fontWeight: FontWeight.w500)),
              ),
            ]),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('$start - $end', style: TextStyle(color: tc.textGray, fontSize: 12)),
              Text('$days Days', style: TextStyle(color: tc.textBlack,
                  fontSize: 12, fontWeight: FontWeight.w500)),
            ]),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              Text('View details', style: TextStyle(color: _T.orange,
                  fontSize: 10, fontWeight: FontWeight.w600)),
              const SizedBox(width: 2),
              const Icon(Icons.chevron_right_rounded, color: _T.orange, size: 14),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _statCard(_ThemeColors tc, {required String label, required String value,
    required Color valueColor, required Color labelColor, bool isHighlighted = false}) {
    return Expanded(child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: isHighlighted ? _T.orange.withValues(alpha: 0.2) : tc.softCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isHighlighted ? _T.orange.withValues(alpha: 0.2) : tc.softBorder,
            width: 1.11),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 3, offset: const Offset(0, 2))],
      ),
      child: Column(children: [
        Text(value, style: TextStyle(color: valueColor, fontSize: 20,
            fontWeight: FontWeight.w500)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(color: labelColor, fontSize: 10,
            fontWeight: FontWeight.w500)),
      ]),
    ));
  }
}

// ═══════════════════════════════════════════════════════════════
// SCREEN 2: LEAVE HISTORY
// ═══════════════════════════════════════════════════════════════
class LeaveHistoryScreen extends StatefulWidget {
  final String employeeId;
  final String employeeName;
  final VoidCallback? onGoHome;
  const LeaveHistoryScreen({super.key, required this.employeeId,
    required this.employeeName, this.onGoHome});
  @override
  State<LeaveHistoryScreen> createState() => _LeaveHistoryScreenState();
}

class _LeaveHistoryScreenState extends State<LeaveHistoryScreen>
    with WidgetsBindingObserver {
  _LeaveStats _stats = _LeaveStats();
  List<Map<String, dynamic>> _leaveHistory = [];
  bool _loading = true;
  String? _error;
  _NetworkState _networkState = _NetworkState.online;
  String _networkErrorMessage = 'No internet connection.';
  bool _showOfflineOverlay = false;
  Timer? _overlayDelayTimer;
  bool _isInitialLoading = true;
  StreamSubscription<bool>? _networkSub;
  static const Duration _sessionCacheTTL = Duration(seconds: 5);
  static const Duration _inactivityLimit = Duration(minutes: 30);
  late final String _sessionNonce;
  Timer? _heartbeatTimer;
  Timer? _inactivityTimer;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sessionSub;
  bool _loggedOut = false;
  bool _sessionValidated = false;
  DateTime? _lastUserActivityAt;
  bool? _cachedSessionValid;
  DateTime? _cachedSessionTime;
  String? _verifiedEmployeeId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sessionNonce = _generateSessionNonce();
    _lastUserActivityAt = DateTime.now();

    // ═══════════════════════════════════════════════════════════
    // 🎭 DEMO MODE — ipakita ang skeleton sa simula
    // ═══════════════════════════════════════════════════════════
    if (DemoModeService.instance.isEnabled) {
      debugPrint('═══════════════════════════════════════════');
      debugPrint('🎭 [DemoMode] Leave History — DEMO PATH');
      debugPrint('   • Skeleton shown for ${_kDemoSkeletonDuration.inMilliseconds}ms');
      debugPrint('═══════════════════════════════════════════');

      _networkState = _NetworkState.online;
      _sessionValidated = true;
      _verifiedEmployeeId = widget.employeeId;

      // 🆕 Keep skeleton visible at start
      _isInitialLoading = true;

      _fetchLeaveData();

      // 🆕 Hide skeleton after short delay
      Future.delayed(_kDemoSkeletonDuration, () {
        if (!mounted) return;
        setState(() => _isInitialLoading = false);
        debugPrint('🎭 [DemoMode] Skeleton hidden — demo UI revealed');
      });

      return;
    }

    try {
      _networkSub = ConnectivityService.instance.onStatusChange.listen((online) {
        if (!mounted || _loggedOut) return;
        if (!online) {
          _overlayDelayTimer?.cancel();
          setState(() {
            _networkState = _NetworkState.offline;
            _networkErrorMessage = 'No internet connection.\nPlease check your network.';
            _showOfflineOverlay = false;
          });
          _overlayDelayTimer = Timer(const Duration(milliseconds: 1200), () {
            if (mounted && _networkState == _NetworkState.offline) {
              setState(() => _showOfflineOverlay = true);
            }
          });
        } else if (_networkState == _NetworkState.offline) {
          _overlayDelayTimer?.cancel();
          _showOfflineOverlay = false;
          _retryNetworkCheck();
        }
      });
    } catch (e) { debugPrint('⚠️ connectivity failed: $e'); }
    _startSecurityMonitoring();
    _checkNetworkOnEntry().then((_) {
      if (mounted) {
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) setState(() => _isInitialLoading = false);
        });
      }
    });
    _validateSession(forceRefresh: true).then((valid) {
      if (!mounted || _loggedOut) return;
      if (!valid) { _forceLogout('Initial session invalid'); return; }
      _fetchLeaveData();
    });
  }

  Future<bool> _validateSession({bool forceRefresh = false}) async {
    if (DemoModeService.instance.isEnabled) return true; // 🎭 DEMO
    if (_loggedOut) return false;
    if (!forceRefresh && _cachedSessionValid != null && _cachedSessionTime != null &&
        DateTime.now().difference(_cachedSessionTime!) < _sessionCacheTTL) {
      return _cachedSessionValid!;
    }
    try {
      final valid = await SecurityService.instance.isSessionValid()
          .timeout(const Duration(seconds: 5));
      if (!valid) {
        _cachedSessionValid = false; _cachedSessionTime = DateTime.now(); return false;
      }
      final sessionEmpId = await SecurityService.instance.getCurrentEmployeeId();
      final matches = sessionEmpId == null || sessionEmpId.isEmpty ||
          sessionEmpId == widget.employeeId;
      if (!matches) {
        await _logSecurityEvent(type: 'leave_history_cross_access',
            severity: 'critical',
            details: 'Session ($sessionEmpId) != viewing (${widget.employeeId})',
            employeeId: widget.employeeId, sessionNonce: _sessionNonce);
        _cachedSessionValid = false; _cachedSessionTime = DateTime.now(); return false;
      }
      _verifiedEmployeeId = sessionEmpId ?? widget.employeeId;
      _cachedSessionValid = true; _cachedSessionTime = DateTime.now(); return true;
    } catch (e) {
      _cachedSessionValid = false; _cachedSessionTime = DateTime.now(); return false;
    }
  }

  Future<void> _forceLogout(String reason) async {
    if (DemoModeService.instance.isEnabled) {
      debugPrint('🎭 [DemoMode] Force logout ignored: $reason');
      return;
    }
    if (_loggedOut || !mounted) return;
    _loggedOut = true;
    _heartbeatTimer?.cancel(); _inactivityTimer?.cancel(); _sessionSub?.cancel();
    _networkSub?.cancel(); _overlayDelayTimer?.cancel();
    try { await Clipboard.setData(const ClipboardData(text: '')); } catch (_) {}
    try { await SecurityHardeningService.instance.clearSession(); } catch (_) {}
    try { await SecurityService.instance.clearSession(); } catch (_) {}
    await _logSecurityEvent(type: 'leave_history_forced_logout', severity: 'high',
        details: 'Force logout: $reason', employeeId: widget.employeeId,
        sessionNonce: _sessionNonce);
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen(),
            settings: const RouteSettings(name: '/login')), (route) => false);
  }

  void _startSecurityMonitoring() {
    if (DemoModeService.instance.isEnabled) return; // 🎭 DEMO
    if (widget.employeeId.isNotEmpty) {
      _sessionSub?.cancel();
      _sessionSub = FirebaseFirestore.instance.collection('sessions')
          .doc(widget.employeeId).snapshots().listen((snap) {
        if (!mounted || _loggedOut) return;
        final data = snap.data();
        if (data == null) return;
        if (data['revoked'] == true) { _forceLogout('Session revoked by admin'); return; }
        final expiresAt = data['expiresAt'] as Timestamp?;
        if (expiresAt != null && expiresAt.toDate().isBefore(DateTime.now())) {
          _forceLogout('Session expired');
        }
      }, onError: (e) => debugPrint('Session listener error: $e'));
    }
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 2), (_) async {
      if (!mounted || _loggedOut) return;
      try {
        await SecurityService.instance.markSessionActive();
        final valid = await _validateSession(forceRefresh: true);
        if (!valid && mounted && !_loggedOut) await _forceLogout('Session invalidated');
      } catch (_) {}
    });
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      if (!mounted || _loggedOut) return;
      if (_lastUserActivityAt == null) return;
      final idle = DateTime.now().difference(_lastUserActivityAt!);
      if (idle > _inactivityLimit) await _forceLogout('Inactivity (${idle.inMinutes}m)');
    });
    _validateSession(forceRefresh: true).then((valid) {
      if (mounted) setState(() => _sessionValidated = valid);
    });
  }

  void _recordActivity() { _lastUserActivityAt = DateTime.now(); }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _recordActivity();
      if (DemoModeService.instance.isEnabled) return;
      _validateSession(forceRefresh: true).then((valid) {
        if (!valid && mounted && !_loggedOut) _forceLogout('Session invalid on resume');
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _networkSub?.cancel(); _sessionSub?.cancel();
    _overlayDelayTimer?.cancel(); _heartbeatTimer?.cancel();
    _inactivityTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkNetworkOnEntry() async {
    if (DemoModeService.instance.isEnabled) {
      if (mounted) setState(() => _networkState = _NetworkState.online);
      return;
    }
    if (!mounted) return;
    setState(() => _networkState = _NetworkState.checking);
    bool hasNet = true;
    try { hasNet = ConnectivityService.instance.isOnline; } catch (_) { hasNet = true; }
    if (!mounted) return;
    if (!hasNet) {
      setState(() {
        _networkState = _NetworkState.offline;
        _networkErrorMessage = 'No internet connection.\nPlease check your network and try again.';
      });
      return;
    }
    setState(() => _networkState = _NetworkState.online);
  }

  Future<void> _retryNetworkCheck() async {
    if (!mounted || _loggedOut) return;
    _recordActivity();
    setState(() { _networkState = _NetworkState.checking; _showOfflineOverlay = false; });
    await _checkNetworkOnEntry();
    if (_networkState == _NetworkState.online && mounted && !_loggedOut) {
      try { await _fetchLeaveData(); }
      catch (e) { debugPrint('⚠️ Retry refresh failed: $e'); }
    }
  }

  Future<void> _fetchLeaveData() async {
    if (!mounted || _loggedOut) return;

    if (DemoModeService.instance.isEnabled) {
      setState(() { _loading = true; _error = null; });
      await Future.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      final history = DemoModeService.instance.demoLeaveHistory
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      history.sort((a, b) {
        final aTime = a['createdAt'];
        final bTime = b['createdAt'];
        if (aTime is DateTime && bTime is DateTime) return bTime.compareTo(aTime);
        return 0;
      });
      final stats = _computeStats(history);
      setState(() { _leaveHistory = history; _stats = stats; _loading = false; });
      return;
    }

    final valid = await _validateSession();
    if (!valid) {
      if (mounted && !_loggedOut) _forceLogout('Session invalid');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final rawDocs = await _fetchEmployeeLeaves(widget.employeeId);
      final List<Map<String, dynamic>> history = [];
      for (var data in rawDocs) {
        history.add({
          'id': data['id'], 'leaveType': data['leaveType'] ?? 'SL',
          'startDate': data['startDate'], 'endDate': data['endDate'],
          'days': _safeInt(data['days'], 1), 'status': data['status'] ?? 'pending',
          'reason': data['reason'] ?? '', 'createdAt': data['createdAt'],
        });
      }
      history.sort((a, b) {
        final aTime = a['createdAt'] as Timestamp?;
        final bTime = b['createdAt'] as Timestamp?;
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });
      final stats = _computeStats(history);
      if (!mounted || _loggedOut) return;
      setState(() { _leaveHistory = history; _stats = stats; _loading = false; });
    } catch (e) {
      debugPrint('Error fetching leave history: $e');
      if (!mounted) return;
      setState(() { _loading = false;
      _error = 'Failed to load leave data. Please try again.'; });
    }
  }

  void _openItinerary() {
    _recordActivity();
    if (_loggedOut) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (context) => ItineraryScreen(
        employeeId: widget.employeeId, employeeName: widget.employeeName,
        onGoHome: () { _fetchLeaveData();
        if (Navigator.canPop(context)) Navigator.pop(context); },
      ),
    )).then((_) => _fetchLeaveData());
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = _ThemeColors(isDark);
    final isOffline = _networkState == _NetworkState.offline;
    final isChecking = _networkState == _NetworkState.checking;
    if (isOffline || isChecking || _isInitialLoading) {
      return Scaffold(
        backgroundColor: tc.bg,
        body: SafeArea(child: Stack(children: [
          const ListSkeleton(itemCount: 5),
          if (isOffline) Positioned.fill(
            child: AnimatedOpacity(
              opacity: _showOfflineOverlay ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeInOut,
              child: IgnorePointer(ignoring: !_showOfflineOverlay,
                  child: _buildNetworkErrorOverlay(
                      message: _networkErrorMessage, onRetry: _retryNetworkCheck)),
            ),
          ),
        ])),
      );
    }
    return Scaffold(
      backgroundColor: tc.bg,
      body: SafeArea(child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          _buildHandWatermark(opacity: tc.watermarkOpacity),
          Column(children: [
            Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
              decoration: BoxDecoration(
                gradient: _T.brandGradient,
                borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
                border: Border(bottom: BorderSide(color: tc.darkBorder, width: 1.11)),
              ),
              child: Row(children: [
                GestureDetector(
                  onTap: () {
                    _recordActivity();
                    if (widget.onGoHome != null) { widget.onGoHome!(); }
                    else if (Navigator.canPop(context)) { Navigator.pop(context); }
                  },
                  child: const Icon(Icons.arrow_back_ios_rounded,
                      color: Colors.white, size: 20),
                ),
                const SizedBox(width: 16),
                const Expanded(child: Text('Leave Form',
                    style: TextStyle(color: Colors.white, fontSize: 20,
                        fontWeight: FontWeight.w500))),
              ]),
            ),
            const SizedBox(height: 20),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _buildBigItineraryButton(onTap: _openItinerary)),
            const SizedBox(height: 20),
            Expanded(child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(children: [
                if (_loading) const Center(child: CircularProgressIndicator())
                else if (_error != null) Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Column(children: [
                      Text(_error!, style: const TextStyle(color: _T.error)),
                      const SizedBox(height: 8),
                      ElevatedButton(onPressed: _fetchLeaveData, child: const Text('Retry')),
                    ]))
                else Row(children: [
                    _statCard(tc, label: 'Total', value: '${_stats.totalCredits}',
                        valueColor: tc.textBlack, labelColor: tc.textGray),
                    const SizedBox(width: 12),
                    _statCard(tc, label: 'Used', value: '${_stats.usedTotal}',
                        valueColor: _T.neonGreen, labelColor: tc.textGray),
                    const SizedBox(width: 12),
                    _statCard(tc, label: 'Remaining', value: '${_stats.remaining}',
                        valueColor: _T.orange, labelColor: _T.orange, isHighlighted: true),
                  ]),
                const SizedBox(height: 20),
                Align(alignment: Alignment.centerLeft,
                    child: Text('Leave History', style: TextStyle(
                        color: tc.textBlack, fontSize: 14, fontWeight: FontWeight.w500))),
                const SizedBox(height: 10),
                if (_loading) const Center(child: CircularProgressIndicator())
                else if (_leaveHistory.isEmpty) Center(child: Text(
                    'No leave history yet.', style: TextStyle(color: tc.textGray)))
                else Column(children: _leaveHistory.map((item) {
                    final leaveType = _leaveTypeLabel(item['leaveType']);
                    final start = _formatDate(item['startDate']);
                    final end = _formatDate(item['endDate']);
                    final days = item['days'];
                    final status = (item['status'] ?? 'pending').toString();
                    final statusLower = status.toLowerCase();
                    final isApproved = statusLower == 'approved';
                    final isPending = statusLower == 'pending';
                    final badgeBg = isApproved ? _T.neonGreen.withValues(alpha: 0.1)
                        : (isPending ? _T.orange.withValues(alpha: 0.1)
                        : _T.error.withValues(alpha: 0.1));
                    final badgeBorder = isApproved ? _T.neonGreen.withValues(alpha: 0.2)
                        : (isPending ? _T.orange.withValues(alpha: 0.2)
                        : _T.error.withValues(alpha: 0.2));
                    final badgeText = isApproved ? _T.neonGreen
                        : (isPending ? _T.orange : _T.error);
                    return GestureDetector(
                      onTap: () { _recordActivity();
                      _showLeaveDetailsSheet(context, item,
                          employeeName: widget.employeeName); },
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: tc.softCard, borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: tc.softBorder, width: 1.11),
                          boxShadow: [BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 4, offset: const Offset(0, 2))],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(child: Row(children: [
                                    const Icon(Icons.description_rounded,
                                        color: _T.orange, size: 14),
                                    const SizedBox(width: 6),
                                    Flexible(child: Text(leaveType,
                                        style: TextStyle(color: tc.textBlack,
                                            fontSize: 14, fontWeight: FontWeight.w500),
                                        overflow: TextOverflow.ellipsis)),
                                  ])),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                        color: badgeBg,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: badgeBorder, width: 1.11)),
                                    child: Text(isApproved ? 'Approved'
                                        : (isPending ? 'Pending' : 'Rejected'),
                                        style: TextStyle(color: badgeText,
                                            fontSize: 10, fontWeight: FontWeight.w500)),
                                  ),
                                ]),
                            const SizedBox(height: 8),
                            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('$start - $end', style: TextStyle(
                                      color: tc.textGray, fontSize: 12)),
                                  Text('$days Days', style: TextStyle(
                                      color: tc.textBlack, fontSize: 12,
                                      fontWeight: FontWeight.w500)),
                                ]),
                            const SizedBox(height: 6),
                            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                              Text('View details', style: TextStyle(
                                  color: _T.orange, fontSize: 10,
                                  fontWeight: FontWeight.w600)),
                              const SizedBox(width: 2),
                              const Icon(Icons.chevron_right_rounded,
                                  color: _T.orange, size: 14),
                            ]),
                          ],
                        ),
                      ),
                    );
                  }).toList()),
                const SizedBox(height: 20),
              ]),
            )),
          ]),
        ],
      )),
    );
  }

  Widget _statCard(_ThemeColors tc, {required String label, required String value,
    required Color valueColor, required Color labelColor, bool isHighlighted = false}) {
    return Expanded(child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: isHighlighted ? _T.orange.withValues(alpha: 0.2) : tc.softCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isHighlighted ? _T.orange.withValues(alpha: 0.2) : tc.softBorder,
            width: 1.11),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 3, offset: const Offset(0, 2))],
      ),
      child: Column(children: [
        Text(value, style: TextStyle(color: valueColor, fontSize: 20,
            fontWeight: FontWeight.w500)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(color: labelColor, fontSize: 10,
            fontWeight: FontWeight.w500)),
      ]),
    ));
  }
}

// ═══════════════════════════════════════════════════════════════
// SCREEN 3: LEAVE FORM (multi-step)
// ═══════════════════════════════════════════════════════════════
class LeaveFormScreen extends StatefulWidget {
  final String employeeId;
  final String employeeName;
  final VoidCallback? onGoHome;
  const LeaveFormScreen({super.key, required this.employeeId,
    required this.employeeName, this.onGoHome});
  @override
  State<LeaveFormScreen> createState() => _LeaveFormScreenState();
}

class _LeaveFormScreenState extends State<LeaveFormScreen>
    with WidgetsBindingObserver {
  int _currentStep = 0;
  String? _selectedLeaveType;
  bool _isSubmitting = false;
  bool _isCertified = false;
  DateTime? _startDate;
  DateTime? _endDate;
  final _reasonCtrl = TextEditingController();
  List<Map<String, dynamic>> _leaveHistory = [];
  bool _loadingHistory = true;
  String _employeeGender = 'unknown';
  bool _loadingGender = true;
  List<_LeaveType> _availableLeaveTypes = _baseLeaveTypes;
  _NetworkState _networkState = _NetworkState.online;
  String _networkErrorMessage = 'No internet connection.';
  bool _showOfflineOverlay = false;
  Timer? _overlayDelayTimer;
  bool _isInitialLoading = true;
  StreamSubscription<bool>? _networkSub;
  static const String _kSubmitCountPrefsKey = 'leave_submit_count_window';
  static const Duration _submitCooldown = Duration(seconds: 5);
  static const Duration _sessionCacheTTL = Duration(seconds: 5);
  static const Duration _inactivityLimit = Duration(minutes: 30);
  static const int _maxSubmitsPerHour = 10;
  static const int _maxLeaveDays = 60;
  late final String _sessionNonce;
  DateTime? _lastSubmitAt;
  DateTime? _lastUserActivityAt;
  int _totalSubmits = 0;
  Timer? _inactivityTimer;
  Timer? _heartbeatTimer;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sessionSub;
  bool _loggedOut = false;
  bool _sessionValidated = false;
  bool? _cachedSessionValid;
  DateTime? _cachedSessionTime;
  String? _verifiedEmployeeId;
  String? _pendingTxnId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sessionNonce = _generateSessionNonce();
    _lastUserActivityAt = DateTime.now();
    _reasonCtrl.addListener(_onReasonChanged);

    // ═══════════════════════════════════════════════════════════
    // 🎭 DEMO MODE — ipakita ang skeleton sa simula
    // ═══════════════════════════════════════════════════════════
    if (DemoModeService.instance.isEnabled) {
      debugPrint('═══════════════════════════════════════════');
      debugPrint('🎭 [DemoMode] Leave Form — DEMO PATH');
      debugPrint('   • Skeleton shown for ${_kDemoSkeletonDuration.inMilliseconds}ms');
      debugPrint('═══════════════════════════════════════════');

      _networkState = _NetworkState.online;
      _sessionValidated = true;
      _verifiedEmployeeId = widget.employeeId;

      // 🆕 Keep skeleton visible at start
      _isInitialLoading = true;

      _loadHistoryPreview();
      _loadEmployeeGender();

      // 🆕 Hide skeleton after short delay
      Future.delayed(_kDemoSkeletonDuration, () {
        if (!mounted) return;
        setState(() => _isInitialLoading = false);
        debugPrint('🎭 [DemoMode] Skeleton hidden — demo UI revealed');
      });

      return;
    }

    try {
      _networkSub = ConnectivityService.instance.onStatusChange.listen((online) {
        if (!mounted || _loggedOut) return;
        if (!online) {
          _overlayDelayTimer?.cancel();
          setState(() {
            _networkState = _NetworkState.offline;
            _networkErrorMessage = 'No internet connection.\nPlease check your network.';
            _showOfflineOverlay = false;
          });
          _overlayDelayTimer = Timer(const Duration(milliseconds: 1200), () {
            if (mounted && _networkState == _NetworkState.offline) {
              setState(() => _showOfflineOverlay = true);
            }
          });
        } else if (_networkState == _NetworkState.offline) {
          _overlayDelayTimer?.cancel();
          _showOfflineOverlay = false;
          _retryNetworkCheck();
        }
      });
    } catch (e) { debugPrint('⚠️ connectivity failed: $e'); }
    _startSecurityMonitoring();
    _checkNetworkOnEntry().then((_) {
      if (mounted) {
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) setState(() => _isInitialLoading = false);
        });
      }
    });
    _validateSession(forceRefresh: true).then((valid) {
      if (!mounted || _loggedOut) return;
      if (!valid) { _forceLogout('Initial session invalid'); return; }
      _loadHistoryPreview();
      _loadEmployeeGender();
    });
  }

  Future<bool> _validateSession({bool forceRefresh = false}) async {
    if (DemoModeService.instance.isEnabled) return true; // 🎭 DEMO
    if (_loggedOut) return false;
    if (!forceRefresh && _cachedSessionValid != null && _cachedSessionTime != null &&
        DateTime.now().difference(_cachedSessionTime!) < _sessionCacheTTL) {
      return _cachedSessionValid!;
    }
    try {
      final valid = await SecurityService.instance.isSessionValid()
          .timeout(const Duration(seconds: 5));
      if (!valid) {
        await _logSecurityEvent(type: 'leave_form_session_invalid',
            severity: 'high', details: 'Session expired');
        _cachedSessionValid = false; _cachedSessionTime = DateTime.now(); return false;
      }
      final sessionEmpId = await SecurityService.instance.getCurrentEmployeeId();
      final matches = sessionEmpId == null || sessionEmpId.isEmpty ||
          sessionEmpId == widget.employeeId;
      if (!matches) {
        await _logSecurityEvent(type: 'leave_form_cross_access',
            severity: 'critical',
            details: 'Session ($sessionEmpId) != form (${widget.employeeId})');
        _cachedSessionValid = false; _cachedSessionTime = DateTime.now(); return false;
      }
      _verifiedEmployeeId = sessionEmpId ?? widget.employeeId;
      _cachedSessionValid = true; _cachedSessionTime = DateTime.now(); return true;
    } catch (e) {
      _cachedSessionValid = false; _cachedSessionTime = DateTime.now(); return false;
    }
  }

  Future<void> _forceLogout(String reason) async {
    if (DemoModeService.instance.isEnabled) {
      debugPrint('🎭 [DemoMode] Force logout ignored: $reason');
      return;
    }
    if (_loggedOut || !mounted) return;
    _loggedOut = true;
    _inactivityTimer?.cancel(); _heartbeatTimer?.cancel();
    _sessionSub?.cancel(); _networkSub?.cancel(); _overlayDelayTimer?.cancel();
    try { await Clipboard.setData(const ClipboardData(text: '')); } catch (_) {}
    try { await SecurityHardeningService.instance.clearSession(); } catch (_) {}
    try { await SecurityService.instance.clearSession(); } catch (_) {}
    await _logSecurityEvent(type: 'leave_form_forced_logout', severity: 'high',
        details: 'Force logout: $reason');
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen(),
            settings: const RouteSettings(name: '/login')), (route) => false);
  }

  Future<void> _logSecurityEvent({required String type,
    required String severity, required String details}) async {
    if (DemoModeService.instance.isEnabled) {
      debugPrint('🎭 [DemoMode] Security event (skipped): $type — $details');
      return;
    }
    try {
      if (_networkState != _NetworkState.online) return;
      await FirebaseFirestore.instance.collection('security_events').add({
        'type': type, 'severity': severity, 'details': details,
        'employeeId': _verifiedEmployeeId ?? widget.employeeId,
        'sessionNonce': _sessionNonce,
        'platform': kIsWeb ? 'web' : 'mobile',
        'stage': 'leave_form',
        'timestamp': FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 3));
    } catch (e) { debugPrint('⚠️ [LeaveSecurity] log error: $e'); }
  }

  void _startSecurityMonitoring() {
    if (DemoModeService.instance.isEnabled) return; // 🎭 DEMO
    if (widget.employeeId.isNotEmpty) {
      _sessionSub?.cancel();
      _sessionSub = FirebaseFirestore.instance.collection('sessions')
          .doc(widget.employeeId).snapshots().listen((snap) {
        if (!mounted || _loggedOut) return;
        final data = snap.data();
        if (data == null) return;
        if (data['revoked'] == true) { _forceLogout('Session revoked by admin'); return; }
        final expiresAt = data['expiresAt'] as Timestamp?;
        if (expiresAt != null && expiresAt.toDate().isBefore(DateTime.now())) {
          _forceLogout('Session expired');
        }
      }, onError: (e) => debugPrint('Session listener error: $e'));
    }
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 2), (_) async {
      if (!mounted || _loggedOut) return;
      try {
        await SecurityService.instance.markSessionActive();
        final valid = await _validateSession(forceRefresh: true);
        if (!valid && mounted && !_loggedOut) await _forceLogout('Session invalidated');
      } catch (e) { debugPrint('⚠️ Heartbeat failed: $e'); }
    });
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      if (!mounted || _loggedOut) return;
      if (_lastUserActivityAt == null) return;
      final idle = DateTime.now().difference(_lastUserActivityAt!);
      if (idle > _inactivityLimit) await _forceLogout('Inactivity (${idle.inMinutes}m)');
    });
    _validateSession(forceRefresh: true).then((valid) {
      if (mounted) setState(() => _sessionValidated = valid);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _lastUserActivityAt = DateTime.now();
      if (DemoModeService.instance.isEnabled) return;
      _validateSession(forceRefresh: true).then((valid) {
        if (!valid && mounted && !_loggedOut) _forceLogout('Session invalid on resume');
      });
    }
  }

  bool _checkSubmitCooldown() {
    if (DemoModeService.instance.isEnabled) return true; // 🎭 DEMO — no cooldown
    final now = DateTime.now();
    if (_lastSubmitAt != null) {
      final elapsed = now.difference(_lastSubmitAt!).inMilliseconds;
      if (elapsed < _submitCooldown.inMilliseconds) {
        _showToast('Maghintay ng ilang segundo bago subukan muli.', _T.warning);
        return false;
      }
    }
    _lastSubmitAt = now;
    return true;
  }

  Future<bool> _checkHourlySubmitLimit() async {
    if (DemoModeService.instance.isEnabled) return true; // 🎭 DEMO
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kSubmitCountPrefsKey);
      int count = 0;
      DateTime? windowStart;
      if (raw != null) {
        final parts = raw.split('|');
        if (parts.length == 2) {
          windowStart = DateTime.tryParse(parts[0]);
          count = int.tryParse(parts[1]) ?? 0;
        }
      }
      final now = DateTime.now();
      if (windowStart == null || now.difference(windowStart).inHours >= 1) {
        windowStart = now; count = 0;
      }
      if (count >= _maxSubmitsPerHour) {
        await _logSecurityEvent(type: 'leave_form_excessive_submits',
            severity: 'medium', details: 'Count this hour: $count');
        return false;
      }
      await prefs.setString(_kSubmitCountPrefsKey,
          '${windowStart.toIso8601String()}|${count + 1}');
      return true;
    } catch (e) { debugPrint('⚠️ Submit limit check error: $e'); return true; }
  }

  void _onReasonChanged() {
    if (mounted) setState(() {});
    _lastUserActivityAt = DateTime.now();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _networkSub?.cancel(); _sessionSub?.cancel();
    _overlayDelayTimer?.cancel(); _inactivityTimer?.cancel();
    _heartbeatTimer?.cancel();
    _reasonCtrl.removeListener(_onReasonChanged);
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkNetworkOnEntry() async {
    if (DemoModeService.instance.isEnabled) {
      if (mounted) setState(() => _networkState = _NetworkState.online);
      return;
    }
    if (!mounted) return;
    setState(() => _networkState = _NetworkState.checking);
    bool hasNet = true;
    try { hasNet = ConnectivityService.instance.isOnline; } catch (_) { hasNet = true; }
    if (!mounted) return;
    if (!hasNet) {
      setState(() {
        _networkState = _NetworkState.offline;
        _networkErrorMessage = 'No internet connection.\nPlease check your network and try again.';
      });
      return;
    }
    setState(() => _networkState = _NetworkState.online);
  }

  Future<void> _retryNetworkCheck() async {
    if (!mounted || _loggedOut) return;
    setState(() { _networkState = _NetworkState.checking; _showOfflineOverlay = false; });
    await _checkNetworkOnEntry();
    if (_networkState == _NetworkState.online && mounted && !_loggedOut) {
      try { await _loadHistoryPreview(); await _loadEmployeeGender(); }
      catch (e) { debugPrint('⚠️ Retry refresh failed: $e'); }
    }
  }

  Future<void> _loadEmployeeGender() async {
    if (_loggedOut) return;
    try {
      final rawGender = await _fetchEmployeeGender(widget.employeeId);
      final normalized = _normalizeGender(rawGender);
      if (!mounted || _loggedOut) return;
      setState(() {
        _employeeGender = normalized;
        _availableLeaveTypes = _leaveTypesForGender(normalized);
        _loadingGender = false;
        if (_selectedLeaveType != null &&
            !_availableLeaveTypes.any((lt) => lt.code == _selectedLeaveType)) {
          _selectedLeaveType = null;
        }
      });
    } catch (e) {
      debugPrint('Gender load failed: $e');
      if (mounted && !_loggedOut) {
        setState(() {
          _employeeGender = 'unknown';
          _availableLeaveTypes = _leaveTypesForGender('unknown');
          _loadingGender = false;
        });
      }
    }
  }

  Future<void> _loadHistoryPreview() async {
    if (_loggedOut) return;

    // 🎭 DEMO MODE
    if (DemoModeService.instance.isEnabled) {
      await Future.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      final history = DemoModeService.instance.demoLeaveHistory
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      history.sort((a, b) {
        final aTime = a['createdAt'];
        final bTime = b['createdAt'];
        if (aTime is DateTime && bTime is DateTime) return bTime.compareTo(aTime);
        return 0;
      });
      setState(() { _leaveHistory = history; _loadingHistory = false; });
      return;
    }

    final valid = await _validateSession();
    if (!valid) {
      if (mounted && !_loggedOut) _forceLogout('Session invalid on history load');
      return;
    }
    try {
      final rawDocs = await _fetchEmployeeLeaves(widget.employeeId);
      final List<Map<String, dynamic>> history = [];
      for (var data in rawDocs) {
        history.add({
          'id': data['id'], 'leaveType': data['leaveType'] ?? 'SL',
          'startDate': data['startDate'], 'endDate': data['endDate'],
          'days': _safeInt(data['days'], 1), 'status': data['status'] ?? 'pending',
          'reason': data['reason'] ?? '', 'createdAt': data['createdAt'],
        });
      }
      history.sort((a, b) {
        final aTime = a['createdAt'] as Timestamp?;
        final bTime = b['createdAt'] as Timestamp?;
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });
      if (!mounted || _loggedOut) return;
      setState(() { _leaveHistory = history; _loadingHistory = false; });
    } catch (e) {
      debugPrint('History preview fetch failed: $e');
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  void _openLeaveApplicationFormHistory() {
    _lastUserActivityAt = DateTime.now();
    if (_loggedOut) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (context) => LeaveApplicationFormScreen(
        employeeId: widget.employeeId, employeeName: widget.employeeName,
        onBack: () { if (Navigator.canPop(context)) Navigator.pop(context); },
      ),
    )).then((_) => _loadHistoryPreview());
  }

  void _openLeaveApplicationForm() {
    _lastUserActivityAt = DateTime.now();
    if (_loggedOut) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (context) => LeaveApplicationFormScreen(
        employeeId: widget.employeeId, employeeName: widget.employeeName,
        onBack: () { if (Navigator.canPop(context)) Navigator.pop(context); },
      ),
    )).then((_) => _loadHistoryPreview());
  }

  void _openItinerary() {
    _lastUserActivityAt = DateTime.now();
    if (_loggedOut) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (context) => ItineraryScreen(
        employeeId: widget.employeeId, employeeName: widget.employeeName,
        onGoHome: () { if (Navigator.canPop(context)) Navigator.pop(context); },
      ),
    ));
  }

  int get _leaveDays {
    if (_startDate == null || _endDate == null) return 0;
    final raw = _endDate!.difference(_startDate!).inDays + 1;
    if (raw <= 0) return 0;
    return raw > _maxLeaveDays ? _maxLeaveDays : raw;
  }

  bool get _isDateRangeValid {
    if (_startDate == null || _endDate == null) return false;
    final raw = _endDate!.difference(_startDate!).inDays + 1;
    return raw > 0 && raw <= _maxLeaveDays;
  }

  String _fmt(DateTime? d) {
    if (d == null) return 'dd/mm/yyyy';
    const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[d.month]} ${d.day}, ${d.year}';
  }

  String get _leaveLabel {
    if (_selectedLeaveType == null) return '—';
    final match = _availableLeaveTypes.where((l) => l.code == _selectedLeaveType).toList();
    return match.isEmpty ? '—' : match.first.label;
  }

  String get _leaveDisplay => '$_leaveLabel ($_selectedLeaveType)';
  String get _durationDisplay => '$_leaveDays Days';
  String get _datesDisplay {
    if (_startDate == null || _endDate == null) return '—';
    return '${_fmt(_startDate)} - ${_fmt(_endDate)}';
  }

  String get _reasonDisplay => _reasonCtrl.text.trim().isEmpty ? '—' : _reasonCtrl.text.trim();

  bool get _canProceed {
    switch (_currentStep) {
      case 0: return _selectedLeaveType != null;
      case 1: return _isDateRangeValid && _reasonCtrl.text.trim().isNotEmpty;
      case 2: return _isCertified;
      default: return false;
    }
  }

  String get _disabledHint {
    switch (_currentStep) {
      case 0: return 'Please select a leave type to continue';
      case 1: return 'Please select valid dates (max $_maxLeaveDays days) and enter a reason';
      case 2: return 'Please certify above to enable submit';
      default: return '';
    }
  }

  Future<void> _pickDate(bool isStart) async {
    _lastUserActivityAt = DateTime.now();
    final now = DateTime.now();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ColorScheme pickerScheme = isDark
        ? const ColorScheme.dark(primary: _T.orange, onPrimary: Colors.white,
        surface: Color(0xFF1F1F23), onSurface: Colors.white,
        onSurfaceVariant: Color(0xFFB0B0B0), secondary: _T.orangeLight,
        onSecondary: Colors.white, tertiary: _T.orange)
        : const ColorScheme.light(primary: _T.orange, onPrimary: Colors.white,
        surface: Colors.white, onSurface: Color(0xFF1F2937),
        onSurfaceVariant: Color(0xFF6B7280), secondary: _T.orangeLight,
        onSecondary: Colors.white, tertiary: _T.orange);
    final pick = await showDatePicker(
      context: context,
      initialDate: isStart ? (_startDate ?? now) : (_endDate ?? _startDate ?? now),
      firstDate: now, lastDate: DateTime(now.year + 1),
      builder: (ctx, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: pickerScheme,
          dialogBackgroundColor: pickerScheme.surface,
          dialogTheme: DialogThemeData(backgroundColor: pickerScheme.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
          datePickerTheme: DatePickerThemeData(
            backgroundColor: pickerScheme.surface,
            surfaceTintColor: Colors.transparent,
            headerBackgroundColor: _T.orange,
            headerForegroundColor: Colors.white,
            dayForegroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) return Colors.white;
              if (states.contains(WidgetState.disabled)) {
                return pickerScheme.onSurface.withValues(alpha: 0.35);
              }
              return pickerScheme.onSurface;
            }),
            dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) return _T.orange;
              return Colors.transparent;
            }),
            todayForegroundColor: WidgetStateProperty.all(_T.orange),
            todayBorder: const BorderSide(color: _T.orange, width: 1.5),
            yearForegroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) return Colors.white;
              return pickerScheme.onSurface;
            }),
            yearBackgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) return _T.orange;
              return Colors.transparent;
            }),
            rangeSelectionBackgroundColor: _T.orange.withValues(alpha: 0.2),
            weekdayStyle: TextStyle(
                color: pickerScheme.onSurface.withValues(alpha: 0.7),
                fontWeight: FontWeight.w600),
          ),
        ),
        child: child!,
      ),
    );
    if (pick == null || !mounted) return;
    setState(() {
      if (isStart) {
        _startDate = pick;
        if (_endDate != null && _endDate!.isBefore(pick)) _endDate = null;
      } else { _endDate = pick; }
    });
  }

  Future<bool> _hasEnoughBalance() async {
    // 🎭 DEMO MODE — always enough
    if (DemoModeService.instance.isEnabled) return true;
    if (_selectedLeaveType == null || _leaveDays <= 0) return true;
    try {
      final rawDocs = await _fetchEmployeeLeaves(widget.employeeId);
      int usedAnnual = 0, usedSick = 0;
      for (final data in rawDocs) {
        final status = (data['status'] ?? 'pending').toString().toLowerCase();
        if (status != 'approved') continue;
        final code = (data['leaveType'] ?? '').toString();
        final days = _safeInt(data['days'], 1);
        if (_isAnnual(code)) { usedAnnual += days; }
        else if (_isSick(code)) { usedSick += days; }
      }
      final annualRemaining = kAnnualLeaveTotal - usedAnnual;
      final sickRemaining = kSickLeaveTotal - usedSick;
      if (_isAnnual(_selectedLeaveType!) && _leaveDays > annualRemaining) {
        _showToast('Insufficient Annual Leave. Remaining: $annualRemaining', _T.error);
        return false;
      }
      if (_isSick(_selectedLeaveType!) && _leaveDays > sickRemaining) {
        _showToast('Insufficient Sick Leave. Remaining: $sickRemaining', _T.error);
        return false;
      }
      return true;
    } catch (e) {
      await _logSecurityEvent(type: 'leave_balance_check_error',
          severity: 'high', details: 'Balance check threw: $e');
      _showToast('Hindi ma-verify ang leave balance. Try again.', _T.error);
      return false;
    }
  }

  void _goNext() {
    _lastUserActivityAt = DateTime.now();
    if (_currentStep == 0 && _selectedLeaveType == null) {
      _showToast('Please select a leave type', _T.warning); return;
    }
    if (_currentStep == 1) {
      if (_startDate == null || _endDate == null) {
        _showToast('Please select dates', _T.warning); return;
      }
      if (!_isDateRangeValid) {
        _showToast('Maximum $_maxLeaveDays days lang ang pwedeng i-file.', _T.warning);
        return;
      }
      if (_reasonCtrl.text.trim().isEmpty) {
        _showToast('Please enter a reason', _T.warning); return;
      }
    }
    if (_currentStep == 2 && !_isCertified) {
      _showToast('Please certify that all information is correct', _T.warning); return;
    }
    if (_currentStep < 2) setState(() => _currentStep++);
  }

  void _goBack() {
    _lastUserActivityAt = DateTime.now();
    if (_currentStep > 0) { setState(() => _currentStep--); }
    else {
      if (widget.onGoHome != null) { widget.onGoHome!(); }
      else if (Navigator.canPop(context)) { Navigator.pop(context); }
    }
  }

  Future<void> _submitApplication() async {
    if (!_isCertified) {
      _showToast('Please certify that all information is correct', _T.warning);
      return;
    }
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    _lastUserActivityAt = DateTime.now();

    // ═══════════════════════════════════════════════════════════
    // 🎭 DEMO MODE — skip lahat ng security + Firestore write
    // ═══════════════════════════════════════════════════════════
    if (DemoModeService.instance.isEnabled ||
        DemoModeService.instance.shouldSkipDbWrite) {
      await Future.delayed(const Duration(milliseconds: 700));
      _pendingTxnId = _generateLeaveTxnId();
      _totalSubmits++;
      debugPrint('🎭 [DemoMode] Leave submitted (NO DB WRITE): $_pendingTxnId');
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      _showSuccessDialog();
      return;
    }

    try {
      if (!_checkSubmitCooldown()) { setState(() => _isSubmitting = false); return; }
      if (!await _checkHourlySubmitLimit()) {
        _showToast('Max submissions reached. Try again later.', _T.error);
        setState(() => _isSubmitting = false); return;
      }
      final valid = await _validateSession(forceRefresh: true);
      if (!valid) {
        _showToast('🚨 Session expired. Please log in again.', _T.error);
        _forceLogout('Session invalid on submit'); return;
      }
      if (_networkState != _NetworkState.online) {
        _showToast('⚠️ Walang internet. Paki-check ang connection.', _T.error);
        setState(() => _isSubmitting = false); return;
      }
      if (!_isDateRangeValid) {
        _showToast('Invalid date range.', _T.warning);
        setState(() => _isSubmitting = false); return;
      }
      final sanitizedReason = _sanitizeInput(_reasonCtrl.text, maxLength: 500);
      if (sanitizedReason.isEmpty) {
        _showToast('Please enter a valid reason', _T.warning);
        setState(() => _isSubmitting = false); return;
      }
      _pendingTxnId = _generateLeaveTxnId();
      final ok = await _hasEnoughBalance();
      if (!ok) { setState(() => _isSubmitting = false); return; }
      await FirebaseFirestore.instance.collection('leave_applications').add({
        'employeeId': widget.employeeId, 'employee_id': widget.employeeId,
        'employeeDocId': widget.employeeId,
        'employeeAuthUid': _verifiedEmployeeId ?? widget.employeeId,
        'employeeName': widget.employeeName, 'employee_name': widget.employeeName,
        'employeeGender': _employeeGender, 'leaveType': _selectedLeaveType,
        'startDate': _startDate?.toIso8601String(),
        'endDate': _endDate?.toIso8601String(),
        'days': _leaveDays, 'reason': sanitizedReason,
        'status': 'pending', 'certified': _isCertified,
        'createdBy': 'employee', 'source': 'employee',
        'transaction_id': _pendingTxnId, 'session_nonce': _sessionNonce,
        'device_hash': sha256.convert(utf8.encode(widget.employeeId + _sessionNonce))
            .toString().substring(0, 16),
        'client_timestamp': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 30));
      _totalSubmits++;
      await _logSecurityEvent(type: 'leave_form_submitted', severity: 'info',
          details: 'TXN=$_pendingTxnId | type=$_selectedLeaveType | days=$_leaveDays');
      try {
        AdminNotificationService.instance.notifyLeaveRequest(
            employeeId: widget.employeeId, employeeName: widget.employeeName,
            leaveType: _selectedLeaveType ?? '—',
            dateRange: '${_fmt(_startDate)} — ${_fmt(_endDate)}');
      } catch (e) { debugPrint('⚠️ Admin leave notification failed: $e'); }
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      _loadHistoryPreview();
      _showSuccessDialog();
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        _showToast('Failed to submit: ${e.toString()}', _T.error);
        await _logSecurityEvent(type: 'leave_form_submit_error',
            severity: 'medium', details: 'Error: ${e.toString()}');
      }
    }
  }

  void _showSuccessDialog() {
    showDialog(
      barrierDismissible: false, context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.transparent, elevation: 0,
        contentPadding: EdgeInsets.zero,
        content: Container(
          width: double.infinity, padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            gradient: _T.brandGradient,
            borderRadius: BorderRadius.circular(_T.r20),
            border: Border.all(color: const Color(0xFF27272A), width: 1.15),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 40, spreadRadius: -8, offset: const Offset(0, 20))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 112, height: 112,
                  decoration: BoxDecoration(
                      color: _T.white, shape: BoxShape.circle,
                      border: Border.all(color: _T.neonGreen, width: 3)),
                  child: const Icon(Icons.check_circle_rounded,
                      color: _T.neonGreen, size: 72)),
              const SizedBox(height: 24),
              const Text('Successfully added', style: TextStyle(
                  color: _T.white, fontSize: 30, fontWeight: FontWeight.w500,
                  height: 1.2), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              const Text('Just wait for the HR Approval...', style: TextStyle(
                  color: Color(0xFFDFDFDF), fontSize: 14, height: 1.5),
                  textAlign: TextAlign.center),
              if (_pendingTxnId != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.receipt_long_rounded,
                          color: Colors.white, size: 12),
                      const SizedBox(width: 6),
                      Text('Ref: ${_pendingTxnId!.substring(0, 20)}',
                          style: const TextStyle(color: Colors.white,
                              fontSize: 10, fontWeight: FontWeight.w700,
                              letterSpacing: 0.3)),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 32),
              SizedBox(width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: _T.white, foregroundColor: _T.orange,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(_T.r12)),
                      elevation: 0,
                      side: BorderSide(color: _T.orange.withValues(alpha: 0.3))),
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    if (mounted) {
                      setState(() {
                        _currentStep = 0; _selectedLeaveType = null;
                        _startDate = null; _endDate = null;
                        _reasonCtrl.clear(); _isCertified = false;
                        _isSubmitting = false; _pendingTxnId = null;
                      });
                    }
                    widget.onGoHome?.call();
                  },
                  child: const Text('OK', style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _saveAsDraft() { _showToast('Draft saved locally', _T.info); }

  void _showToast(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: _T.white,
          fontWeight: FontWeight.w600)),
      backgroundColor: color.withValues(alpha: 0.9),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_T.r12)),
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 3),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = _ThemeColors(isDark);
    final isOffline = _networkState == _NetworkState.offline;
    final isChecking = _networkState == _NetworkState.checking;
    if (isOffline || isChecking || _isInitialLoading) {
      return Scaffold(
        backgroundColor: tc.bg,
        body: SafeArea(child: Stack(children: [
          const ListSkeleton(itemCount: 5),
          if (isOffline) Positioned.fill(
            child: AnimatedOpacity(
              opacity: _showOfflineOverlay ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeInOut,
              child: IgnorePointer(ignoring: !_showOfflineOverlay,
                  child: _buildNetworkErrorOverlay(
                      message: _networkErrorMessage, onRetry: _retryNetworkCheck)),
            ),
          ),
        ])),
      );
    }
    return Scaffold(
      backgroundColor: tc.bg,
      body: SafeArea(child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          _buildHandWatermark(opacity: tc.watermarkOpacity),
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(children: [
              const SizedBox(height: 12),
              _buildHeader(tc),
              const SizedBox(height: 12),
              _buildBigItineraryButton(onTap: _openItinerary),
              const SizedBox(height: 16),
              _buildHeroCard(),
              const SizedBox(height: 20),
              _buildStepper(tc),
              const SizedBox(height: 24),
              _buildStepContent(tc),
              const SizedBox(height: 24),
              _buildActions(tc),
              const SizedBox(height: 28),
              _buildRecentHistorySection(tc),
            ]),
          ),
        ],
      )),
    );
  }

  Widget _buildRecentHistorySection(_ThemeColors tc) {
    final recent = _leaveHistory.take(3).toList();
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: tc.cardBg,
        borderRadius: BorderRadius.circular(_T.r16),
        border: Border.all(color: tc.darkBorder.withValues(alpha: 0.15), width: 1.15),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(width: 32, height: 32,
                decoration: BoxDecoration(
                    color: _T.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.history_rounded, color: _T.orange, size: 18)),
            const SizedBox(width: 10),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Recent Leave History', style: TextStyle(
                    color: tc.textBlack, fontSize: 15, fontWeight: FontWeight.w700)),
                Text(_leaveHistory.isEmpty ? 'Wala pang naitalang leave'
                    : '${_leaveHistory.length} record(s) — tap for details',
                    style: TextStyle(color: tc.textMuted, fontSize: 11)),
              ],
            )),
          ]),
          const SizedBox(height: 14),
          if (_loadingHistory) const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: SizedBox(width: 22, height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4))),
          )
          else if (recent.isEmpty) Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Column(children: [
              Icon(Icons.inbox_rounded, color: tc.textMuted, size: 32),
              const SizedBox(height: 8),
              Text('No leave history yet', style: TextStyle(
                  color: tc.textGray, fontSize: 13)),
            ]),
          )
          else ...recent.map((item) => _recentHistoryRow(tc, item)),
          if (!_loadingHistory && _leaveHistory.length > 3)
            Padding(padding: const EdgeInsets.only(top: 6, left: 18),
                child: Text('+ ${_leaveHistory.length - 3} more record(s)...',
                    style: TextStyle(color: tc.textMuted, fontSize: 11,
                        fontStyle: FontStyle.italic))),
          const SizedBox(height: 14),
          Divider(height: 1, color: tc.darkBorder.withValues(alpha: 0.12)),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: _openLeaveApplicationFormHistory,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                  color: tc.cardFill,
                  borderRadius: BorderRadius.circular(_T.r12),
                  border: Border.all(color: _T.orange.withValues(alpha: 0.45), width: 1.2)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.list_alt_rounded, color: tc.textBlack, size: 18),
                  const SizedBox(width: 8),
                  Text('View Full History', style: TextStyle(
                      color: tc.textBlack, fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward_rounded, color: tc.textBlack, size: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _recentHistoryRow(_ThemeColors tc, Map<String, dynamic> item) {
    final label = _leaveTypeLabel(item['leaveType']);
    final status = (item['status'] ?? 'pending').toString().toLowerCase();
    final Color statusColor;
    if (status == 'approved') { statusColor = _T.neonGreen; }
    else if (status == 'pending') { statusColor = _T.orange; }
    else { statusColor = _T.error; }
    return GestureDetector(
      onTap: () { _lastUserActivityAt = DateTime.now();
      _showLeaveDetailsSheet(context, item, employeeName: widget.employeeName); },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(
              color: statusColor, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: TextStyle(color: tc.textBlack,
              fontSize: 13, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8)),
            child: Text(status == 'approved' ? 'Approved'
                : (status == 'pending' ? 'Pending' : 'Rejected'),
                style: TextStyle(color: statusColor, fontSize: 9,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
          Text('${item['days']}d', style: TextStyle(color: tc.textGray,
              fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded, color: tc.textMuted, size: 16),
        ]),
      ),
    );
  }

  Widget _buildHeader(_ThemeColors tc) {
    return Row(children: [
      GestureDetector(
        onTap: _goBack, behavior: HitTestBehavior.opaque,
        child: Padding(padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: Icon(Icons.chevron_left_rounded, color: tc.textGray, size: 28)),
      ),
      const SizedBox(width: 8),
      Expanded(child: Text('Leave Form', style: TextStyle(color: tc.textBlack,
          fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3))),
    ]);
  }

  Widget _buildHeroCard() {
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: _T.brandGradient,
        borderRadius: BorderRadius.circular(_T.r16),
        border: Border.all(color: _T.orangeBorder, width: 1.15),
        boxShadow: [BoxShadow(color: _T.orange.withValues(alpha: 0.25),
            blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Row(children: [
        Container(width: 44, height: 44,
            decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(_T.r14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.25))),
            child: const Icon(Icons.event_note_rounded, color: Colors.white, size: 22)),
        const SizedBox(width: 14),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SELF SERVICE', style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.4)),
            const SizedBox(height: 2),
            const Text('Apply for Leave', style: TextStyle(
                color: Colors.white, fontSize: 18,
                fontWeight: FontWeight.w800, letterSpacing: -0.3)),
          ],
        )),
        if (!_loadingGender && _employeeGender != 'unknown')
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 1)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(_employeeGender == 'female' ? Icons.female_rounded
                  : Icons.male_rounded, color: Colors.white, size: 14),
              const SizedBox(width: 4),
              Text(_employeeGender == 'female' ? 'Female' : 'Male',
                  style: const TextStyle(color: Colors.white,
                      fontSize: 11, fontWeight: FontWeight.w700)),
            ]),
          ),
      ]),
    );
  }

  Widget _buildStepper(_ThemeColors tc) {
    const steps = ['Type', 'Details', 'Submit'];
    return Row(children: List.generate(steps.length * 2 - 1, (i) {
      if (i.isOdd) {
        final stepIndex = i ~/ 2;
        final passed = _currentStep > stepIndex;
        return Expanded(child: Container(
            height: 2, margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
                color: passed ? _T.orange : tc.darkBorder.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(1))));
      }
      final stepIndex = i ~/ 2;
      final active = _currentStep == stepIndex;
      final done = _currentStep > stepIndex;
      return Column(mainAxisSize: MainAxisSize.min, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 32, height: 32,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? _T.orange : active ? Colors.transparent : tc.cardFill,
              border: Border.all(
                  color: done || active ? _T.orange
                      : tc.darkBorder.withValues(alpha: 0.2),
                  width: active ? 2 : 1.5),
              boxShadow: active || done
                  ? [BoxShadow(color: _T.orange.withValues(alpha: 0.3), blurRadius: 10)]
                  : []),
          child: Center(child: done
              ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
              : Text('${stepIndex + 1}', style: TextStyle(
              color: active ? _T.orange : tc.textMuted,
              fontSize: 13, fontWeight: FontWeight.w800))),
        ),
        const SizedBox(height: 6),
        Text(steps[stepIndex], style: TextStyle(
            color: active ? tc.textBlack : done ? _T.orange : tc.textMuted,
            fontSize: 11, fontWeight: active ? FontWeight.w700 : FontWeight.normal)),
      ]);
    }));
  }

  Widget _buildStepContent(_ThemeColors tc) {
    switch (_currentStep) {
      case 0: return _buildStep1(tc);
      case 1: return _buildStep2(tc);
      case 2: return _buildStep3(tc);
      default: return const SizedBox();
    }
  }

  Widget _buildStep1(_ThemeColors tc) {
    if (_loadingGender) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: const Center(child: Column(children: [
          CircularProgressIndicator(color: _T.orange),
          SizedBox(height: 14),
          Text('Loading leave options...',
              style: TextStyle(color: _T.orange, fontSize: 12)),
        ])),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text('SELECT LEAVE TYPE', style: TextStyle(color: tc.textMuted,
              fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.4)),
          const SizedBox(width: 8),
          if (_employeeGender != 'unknown')
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                  color: _T.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10)),
              child: Text(_employeeGender == 'female'
                  ? '👩 Maternity' : '👨 Paternity',
                  style: const TextStyle(color: _T.orange, fontSize: 9,
                      fontWeight: FontWeight.w700)),
            ),
        ]),
        const SizedBox(height: 14),
        if (_employeeGender == 'unknown')
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: _T.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(_T.r12),
                border: Border.all(color: _T.warning.withValues(alpha: 0.4), width: 1)),
            child: Row(children: [
              const Icon(Icons.info_outline_rounded, color: _T.warning, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(
                  'Gender not set. Maternity & Paternity leaves are hidden. '
                      'Please contact HR to update your profile.',
                  style: TextStyle(color: tc.textBlack, fontSize: 11, height: 1.4))),
            ]),
          ),
        GridView.count(
          crossAxisCount: 3, shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.15,
          children: _availableLeaveTypes.map((lt) {
            final sel = _selectedLeaveType == lt.code;
            return GestureDetector(
              onTap: () { _lastUserActivityAt = DateTime.now();
              setState(() => _selectedLeaveType = lt.code); },
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  gradient: sel ? _T.brandGradient : null,
                  color: sel ? null : tc.cardBg,
                  borderRadius: BorderRadius.circular(_T.r14),
                  border: Border.all(
                      color: sel ? _T.orange : tc.darkBorder.withValues(alpha: 0.15),
                      width: sel ? 1.5 : 1),
                  boxShadow: sel
                      ? [BoxShadow(color: _T.orange.withValues(alpha: 0.3),
                      blurRadius: 12, offset: const Offset(0, 4))]
                      : [BoxShadow(color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 6, offset: const Offset(0, 2))],
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(lt.icon, color: sel ? Colors.white : tc.textMuted, size: 22),
                  const SizedBox(height: 6),
                  Text(lt.code, style: TextStyle(
                      color: sel ? Colors.white : tc.textBlack,
                      fontSize: 16, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 2),
                  Text(lt.label, style: TextStyle(
                      color: sel ? Colors.white.withValues(alpha: 0.85) : tc.textGray,
                      fontSize: 11, fontWeight: FontWeight.w500)),
                ]),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildStep2(_ThemeColors tc) {
    return Column(children: [
      _buildWhiteCard(tc: tc, icon: Icons.calendar_today_rounded,
          title: 'Duration Details',
          child: Column(children: [
            _buildDatePicker(tc, 'Start Date', _startDate, () => _pickDate(true)),
            const SizedBox(height: 12),
            _buildDatePicker(tc, 'End Date', _endDate, () => _pickDate(false)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: _buildInfoField(tc, 'Total Days',
                  '${_leaveDays.toStringAsFixed(0)}')),
              const SizedBox(width: 12),
              Expanded(child: _buildInfoField(tc, 'Total Hours',
                  '${(_leaveDays * 8).toStringAsFixed(1)}')),
            ]),
          ])),
      const SizedBox(height: 16),
      _buildWhiteCard(tc: tc, icon: Icons.edit_note_rounded, title: 'Justification',
          child: Container(
            width: double.infinity, padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: tc.cardFill, borderRadius: BorderRadius.circular(8),
                border: Border.all(color: tc.darkBorder.withValues(alpha: 0.15))),
            child: TextField(
              controller: _reasonCtrl, maxLines: 4, maxLength: 500,
              style: TextStyle(color: tc.textBlack, fontSize: 14),
              decoration: InputDecoration(
                  hintText: 'Enter reason for leave...',
                  hintStyle: TextStyle(color: tc.textMuted, fontSize: 14),
                  border: InputBorder.none, contentPadding: EdgeInsets.zero,
                  counterStyle: TextStyle(color: tc.textMuted, fontSize: 10)),
            ),
          )),
    ]);
  }

  Widget _buildStep3(_ThemeColors tc) {
    return Column(children: [
      _buildWhiteCard(tc: tc, title: 'Leave Information', editButton: true,
          onEdit: () => setState(() => _currentStep = 0),
          child: Column(children: [
            _infoRow(tc, 'Type of Leave', _leaveDisplay),
            const SizedBox(height: 12),
            _infoRow(tc, 'Duration', _durationDisplay),
            const SizedBox(height: 12),
            _infoRow(tc, 'Dates', _datesDisplay),
            const SizedBox(height: 12),
            _infoRow(tc, 'Reason', _reasonDisplay, isMultiLine: true),
          ])),
      const SizedBox(height: 16),
      _buildWhiteCard(tc: tc, title: 'Approver Information', editButton: true,
          onEdit: () => setState(() => _currentStep = 1),
          child: Row(children: [
            Container(width: 56, height: 56,
                decoration: BoxDecoration(
                    shape: BoxShape.circle, color: tc.cardFill,
                    border: Border.all(color: tc.darkBorder.withValues(alpha: 0.2), width: 2)),
                child: Center(child: Text('HR', style: TextStyle(
                    color: tc.textGray, fontSize: 16, fontWeight: FontWeight.w800)))),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('HR', style: TextStyle(color: tc.textBlack,
                  fontSize: 16, fontWeight: FontWeight.w700)),
              Text('Human Resources', style: TextStyle(color: tc.textGray,
                  fontSize: 12, fontWeight: FontWeight.w600)),
            ])),
            Icon(Icons.chevron_right_rounded, color: tc.textMuted),
          ])),
      const SizedBox(height: 16),
      _buildWhiteCard(tc: tc, title: 'Approval Workflow', editButton: false,
          child: Column(children: [
            _workflowStep(tc: tc, stage: 'Stage 1', role: 'Immediate Supervisor',
                status: 'David Henderson (Pending)', isComplete: false),
            const SizedBox(height: 16),
            _workflowStep(tc: tc, stage: 'Final Stage', role: 'Department Head',
                status: 'Automatic routing upon Stage 1 approval',
                isComplete: false, isLast: true),
          ])),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          GestureDetector(
            onTap: () { _lastUserActivityAt = DateTime.now();
            setState(() => _isCertified = !_isCertified); },
            behavior: HitTestBehavior.opaque,
            child: Container(
                width: 24, height: 24, margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(
                    color: _isCertified ? _T.orange : tc.bg,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                        color: _isCertified ? _T.orange : tc.darkBorder.withValues(alpha: 0.3),
                        width: 1.5)),
                child: _isCertified ? const Icon(Icons.check,
                    color: Colors.white, size: 16) : null),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(
              'I certify that all information provided above is true and that my reliever has been fully briefed on my pending tasks.',
              style: TextStyle(color: tc.textGray, fontSize: 12, height: 1.6))),
        ]),
      ),
    ]);
  }

  Widget _buildWhiteCard({required _ThemeColors tc, required String title,
    required Widget child, IconData? icon, bool editButton = false,
    VoidCallback? onEdit}) {
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tc.cardBg, borderRadius: BorderRadius.circular(_T.r16),
        border: Border.all(color: tc.darkBorder.withValues(alpha: 0.15), width: 1.15),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            if (icon != null) ...[
              Icon(icon, color: _T.orange, size: 20),
              const SizedBox(width: 10),
            ],
            Text(title, style: TextStyle(color: tc.textBlack,
                fontSize: 16, fontWeight: FontWeight.w700)),
          ]),
          if (editButton && onEdit != null)
            GestureDetector(
                onTap: onEdit, behavior: HitTestBehavior.opaque,
                child: const Text('Edit', style: TextStyle(color: _T.orange,
                    fontSize: 12, fontWeight: FontWeight.w600))),
        ]),
        const SizedBox(height: 16),
        child,
      ]),
    );
  }

  Widget _buildDatePicker(_ThemeColors tc, String label, DateTime? value, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap, behavior: HitTestBehavior.opaque,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(color: tc.textMuted,
            fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
              color: tc.cardFill, borderRadius: BorderRadius.circular(_T.r12),
              border: Border.all(color: tc.darkBorder.withValues(alpha: 0.15))),
          child: Row(children: [
            Expanded(child: Text(_fmt(value), style: TextStyle(
                color: value != null ? tc.textBlack : tc.textMuted,
                fontSize: 14, fontWeight: FontWeight.w500))),
            Icon(Icons.calendar_today_rounded, color: tc.textMuted, size: 18),
          ]),
        ),
      ]),
    );
  }

  Widget _buildInfoField(_ThemeColors tc, String label, String value) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(color: tc.textMuted,
          fontSize: 12, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
            color: tc.cardFill, borderRadius: BorderRadius.circular(8),
            border: Border.all(color: tc.darkBorder.withValues(alpha: 0.15))),
        child: Text(value, style: TextStyle(color: tc.textBlack,
            fontSize: 14, fontWeight: FontWeight.w500)),
      ),
    ]);
  }

  Widget _infoRow(_ThemeColors tc, String label, String value, {bool isMultiLine = false}) {
    return Row(
      crossAxisAlignment: isMultiLine ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        SizedBox(width: 100, child: Text(label, style: TextStyle(
            color: tc.textMuted, fontSize: 12, fontWeight: FontWeight.w600))),
        const SizedBox(width: 8),
        Expanded(child: Text(value, style: TextStyle(color: tc.textBlack,
            fontSize: 14, fontWeight: FontWeight.w600),
            maxLines: isMultiLine ? 3 : 1, overflow: TextOverflow.ellipsis)),
      ],
    );
  }

  Widget _workflowStep({required _ThemeColors tc, required String stage,
    required String role, required String status, required bool isComplete,
    bool isLast = false}) {
    final int stepNumber = stage == 'Stage 1' ? 1 : 2;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Column(children: [
        Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isComplete ? _T.orange : tc.cardFill,
                border: Border.all(
                    color: isComplete ? _T.orange : tc.darkBorder.withValues(alpha: 0.15),
                    width: 2)),
            child: isComplete
                ? const Icon(Icons.check, color: Colors.white, size: 16)
                : Center(child: Text('$stepNumber', style: TextStyle(
                color: tc.textGray, fontSize: 12, fontWeight: FontWeight.w700)))),
        if (!isLast) SizedBox(height: 32,
            child: VerticalDivider(color: tc.darkBorder.withValues(alpha: 0.15),
                width: 2, thickness: 2, indent: 4, endIndent: 4)),
      ]),
      const SizedBox(width: 16),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(stage, style: TextStyle(color: tc.textMuted,
            fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(role, style: TextStyle(color: tc.textBlack,
            fontSize: 14, fontWeight: FontWeight.w700)),
        Text(status, style: TextStyle(color: tc.textGray,
            fontSize: 12, fontWeight: FontWeight.w400)),
      ])),
    ]);
  }

  Widget _buildActions(_ThemeColors tc) {
    final isLastStep = _currentStep == 2;
    final canProceed = _canProceed;
    final isDisabled = !canProceed;
    final Color btnTextColor = isDisabled ? tc.textMuted : Colors.white;
    final Color btnBorderColor = isDisabled
        ? tc.darkBorder.withValues(alpha: 0.25) : _T.orangeBorder;
    return Column(children: [
      GestureDetector(
        onTap: isDisabled
            ? () => _showToast(_disabledHint, _T.warning)
            : (isLastStep ? (_isSubmitting ? null : _submitApplication) : _goNext),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: double.infinity, height: 54,
          decoration: BoxDecoration(
              gradient: isDisabled ? null : _T.brandGradient,
              color: isDisabled ? tc.cardFill : null,
              borderRadius: BorderRadius.circular(_T.r16),
              border: Border.all(color: btnBorderColor, width: 1.15),
              boxShadow: isDisabled ? [] : [
                BoxShadow(color: _T.orange.withValues(alpha: 0.3),
                    blurRadius: 16, offset: const Offset(0, 6)),
              ]),
          child: Center(child: _isSubmitting
              ? const SizedBox(width: 22, height: 22,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
              : Row(mainAxisSize: MainAxisSize.min, children: [
            Text(isLastStep ? 'Submit Application' : 'Continue',
                style: TextStyle(color: btnTextColor, fontSize: 15,
                    fontWeight: FontWeight.w800)),
            const SizedBox(width: 8),
            Icon(isLastStep ? Icons.send_rounded : Icons.arrow_forward_rounded,
                color: btnTextColor, size: 18),
          ])),
        ),
      ),
      if (isDisabled) ...[
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.info_outline_rounded, color: _T.warning, size: 14),
          const SizedBox(width: 6),
          Flexible(child: Text(_disabledHint, textAlign: TextAlign.center,
              style: TextStyle(color: _T.warning, fontSize: 11,
                  fontWeight: FontWeight.w600))),
        ]),
      ],
      const SizedBox(height: 12),
      if (!isLastStep) ...[
        GestureDetector(
          onTap: _goBack, behavior: HitTestBehavior.opaque,
          child: Container(
              width: double.infinity, height: 50,
              decoration: BoxDecoration(
                  color: tc.bg, borderRadius: BorderRadius.circular(_T.r16),
                  border: Border.all(color: tc.darkBorder.withValues(alpha: 0.15),
                      width: 1.15)),
              child: Center(child: Text('Back', style: TextStyle(
                  color: tc.textGray, fontSize: 14, fontWeight: FontWeight.w700)))),
        ),
      ] else ...[
        GestureDetector(
          onTap: _isSubmitting ? null : _saveAsDraft,
          behavior: HitTestBehavior.opaque,
          child: Container(
              width: double.infinity, height: 50,
              decoration: BoxDecoration(
                  color: tc.bg, borderRadius: BorderRadius.circular(_T.r16),
                  border: Border.all(color: tc.darkBorder.withValues(alpha: 0.15),
                      width: 1.15)),
              child: Center(child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.save_alt_rounded, color: tc.textGray, size: 17),
                const SizedBox(width: 8),
                Text('Save as Draft', style: TextStyle(color: tc.textGray,
                    fontSize: 14, fontWeight: FontWeight.w700)),
              ]))),
        ),
      ],
    ]);
  }
}