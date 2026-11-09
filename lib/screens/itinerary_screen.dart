// lib/screens/itinerary_screen.dart
// v1.1: 🎭 DEMO MODE now shows the SAME skeleton loading screen as normal mode.
//       Skeleton appears briefly (900ms), then fades into demo UI.
//       Demo mode skips: security monitoring, Firestore reads, network listener.
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../services/security_service.dart';
import '../services/demo_mode_service.dart';
import '../data/local/dao/connectivity_service.dart';
import '../widgets/skeleton_screens.dart';

// ══════════════════════════════════════════════════════════════
// ✅ HAND WATERMARK
// ══════════════════════════════════════════════════════════════
const String _kLogoAsset = 'assets/images/logo.png';

double _degToRad(double deg) => deg * 3.1415926535 / 180;

Widget _buildHandWatermark({required double opacity}) {
  return Positioned(
    bottom: -130,
    left: -150,
    child: IgnorePointer(
      child: Transform.rotate(
        angle: _degToRad(425),
        child: Opacity(
          opacity: opacity,
          child: ColorFiltered(
            colorFilter: const ColorFilter.mode(
              Color.fromRGBO(255, 138, 0, 0.10),
              BlendMode.srcIn,
            ),
            child: Image.asset(
              _kLogoAsset,
              width: 500,
              height: 500,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) {
                debugPrint('logo.png failed to load');
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    ),
  );
}

// ══════════════════════════════════════════════════════════════
// 🔒 SECURITY HELPERS
// ══════════════════════════════════════════════════════════════

/// 🔒 Generate unique session nonce
String _generateSessionNonce() {
  final rand = math.Random.secure();
  final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// 🔒 Log security events to Firestore (GLOBAL — top-level)
/// 🎭 DEMO MODE — skips Firestore write
Future<void> _logSecurityEventGlobal({
  required String type,
  required String severity,
  required String details,
  String? employeeId,
  String? sessionNonce,
}) async {
  if (DemoModeService.instance.isEnabled) {
    debugPrint('🎭 [DemoMode] Security event (skipped): $type — $details');
    return;
  }
  try {
    await FirebaseFirestore.instance.collection('security_events').add({
      'type': type,
      'severity': severity,
      'details': details,
      'employeeId': employeeId,
      'sessionNonce': sessionNonce,
      'platform': kIsWeb ? 'web' : 'mobile',
      'stage': 'itinerary',
      'timestamp': FieldValue.serverTimestamp(),
    });
  } catch (e) {
    debugPrint('⚠️ [ItinSecurity] log error: $e');
  }
}

// ══════════════════════════════════════════════════════════════
// THEME COLORS
// ══════════════════════════════════════════════════════════════
class _ThemeColors {
  final bool isDark;
  const _ThemeColors(this.isDark);

  Color get bg => isDark ? const Color(0xFF0F0F10) : const Color(0xFFFFFFFF);
  Color get textBlack => isDark ? Colors.white : const Color(0xFF000000);
  Color get textDark => isDark ? Colors.white : const Color(0xFF1A1A1A);
  Color get textGray =>
      isDark ? const Color(0xFFB0B0B0) : const Color(0xFF71717A);
  Color get textMuted =>
      isDark ? const Color(0xFF888888) : const Color(0xFFA1A1AA);
  Color get cardFill =>
      isDark ? const Color(0xFF1F1F23) : const Color(0xFFF8F8F8);
  Color get darkBorder =>
      isDark ? const Color(0xFF3F3F46) : const Color(0xFF27272A);

  double get watermarkOpacity => isDark ? 0.15 : 0.80;
}

// ══════════════════════════════════════════════════════════════
// COLORS
// ══════════════════════════════════════════════════════════════
class _ItinColors {
  static const Color orange = Color(0xFFFF8A00);
  static const Color orangeDeep = Color(0xFFFA6A00);
  static const Color orangeDark = Color(0xFFF54900);
  static const Color orangeBorder = Color(0xFFFFA500);
  static const Color lime = Color(0xFFC4FF0A);
  static const Color limeBg = Color(0x1AC4FF0A);
  static const Color limeBorder = Color(0x33C4FF0A);
  static const Color cardBg = Color(0xFFF8F8F8);
  static const Color error = Color(0xFFDC2626);
  static const Color errorBg = Color(0x1ADC2626);
  static const Color errorBorder = Color(0x33DC2626);
  static const Color muted = Color(0xFF71717A);

  static const LinearGradient headerGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [orange, orangeDeep, orangeDark],
    stops: [0.0, 0.5, 1.0],
  );
}

// ══════════════════════════════════════════════════════════════
// NETWORK STATE ENUM
// ══════════════════════════════════════════════════════════════
enum _NetworkState { online, offline, checking }

// ══════════════════════════════════════════════════════════════
// POLICY — Total credits
// ══════════════════════════════════════════════════════════════
const int _kTotalCredits = 36;

// 🆕 Demo skeleton display duration
const Duration _kDemoSkeletonDuration = Duration(milliseconds: 900);

// ══════════════════════════════════════════════════════════════
// HELPERS — date formatting
// ══════════════════════════════════════════════════════════════
DateTime? _toDateTimeShared(dynamic v) {
  if (v == null) return null;
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  return null;
}

String _fmtDateShared(dynamic v) {
  final dt = _toDateTimeShared(v);
  if (dt == null) return 'N/A';
  return DateFormat('MMM d, yyyy').format(dt);
}

String _fmtTimeShared(dynamic v) {
  final dt = _toDateTimeShared(v);
  if (dt == null) return 'N/A';
  return DateFormat('h:mm a').format(dt);
}

String _fmtDateTimeShared(dynamic v) {
  final dt = _toDateTimeShared(v);
  if (dt == null) return 'N/A';
  return DateFormat('MMM d, yyyy • h:mm a').format(dt);
}

// ══════════════════════════════════════════════════════════════
// SHARED: NETWORK ERROR OVERLAY
// ══════════════════════════════════════════════════════════════
Widget _buildNetworkErrorOverlay({
  required String message,
  required VoidCallback onRetry,
}) {
  return Container(
    color: Colors.black.withValues(alpha: 0.72),
    child: Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 380),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: _ItinColors.headerGradient,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white, width: 1.15),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 20,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.2),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                ),
                child: const Icon(
                  Icons.wifi_off_rounded,
                  color: Colors.white,
                  size: 40,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'No Connection',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.92),
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: 180,
                child: ElevatedButton.icon(
                  onPressed: onRetry,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: _ItinColors.orange,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text(
                    'Try Again',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Automatically retries when network returns.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

// ══════════════════════════════════════════════════════════════
// SHARED: ITINERARY DETAILS BOTTOM SHEET
// ══════════════════════════════════════════════════════════════
void _showItineraryDetailsSheet(
    BuildContext context,
    Map<String, dynamic> item, {
      String? employeeName,
    }) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final tc = _ThemeColors(isDark);

  final status = (item['status'] ?? 'pending_hr_approval')
      .toString()
      .toLowerCase();
  final isApproved = status == 'approved';
  final isRejected = status == 'rejected';
  final isPending = !isApproved && !isRejected;

  final badgeBg = isApproved
      ? _ItinColors.limeBg
      : (isPending
      ? _ItinColors.orange.withValues(alpha: 0.15)
      : _ItinColors.errorBg);
  final badgeBorder = isApproved
      ? _ItinColors.limeBorder
      : (isPending
      ? _ItinColors.orange.withValues(alpha: 0.3)
      : _ItinColors.errorBorder);
  final badgeText = isApproved
      ? _ItinColors.lime
      : (isPending ? _ItinColors.orange : _ItinColors.error);
  final badgeLabel =
  isApproved ? 'Approved' : (isPending ? 'Pending' : 'Rejected');

  final statusIcon = isApproved
      ? Icons.check_circle_rounded
      : (isPending ? Icons.access_time_rounded : Icons.cancel_rounded);

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (ctx) {
      return Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          color: tc.bg,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          border: Border.all(
            color: _ItinColors.orangeBorder.withValues(alpha: 0.4),
            width: 1.2,
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 4),
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: tc.darkBorder.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: _ItinColors.headerGradient,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: _ItinColors.orangeBorder, width: 1.1),
                      ),
                      child: const Icon(Icons.location_on_rounded,
                          color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Client Meeting Details',
                              style: TextStyle(
                                  color: tc.textBlack,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3)),
                          Text('Itinerary summary',
                              style: TextStyle(
                                  color: tc.textMuted, fontSize: 11)),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.of(ctx).pop(),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: tc.cardFill,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: tc.darkBorder.withValues(alpha: 0.3)),
                        ),
                        child: Icon(Icons.close_rounded,
                            color: tc.textGray, size: 18),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(
                height: 1,
                color: tc.darkBorder.withValues(alpha: 0.15),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: badgeBg,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: badgeBorder, width: 1.2),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(statusIcon,
                                  color: badgeText, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                badgeLabel,
                                style: TextStyle(
                                    color: badgeText,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: _ItinColors.headerGradient,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: _ItinColors.orangeBorder, width: 1.15),
                          boxShadow: [
                            BoxShadow(
                                color: _ItinColors.orange
                                    .withValues(alpha: 0.25),
                                blurRadius: 18,
                                offset: const Offset(0, 8)),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color:
                                Colors.black.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                    color: Colors.white
                                        .withValues(alpha: 0.25)),
                              ),
                              child: const Icon(
                                  Icons.location_city_rounded,
                                  color: Colors.white,
                                  size: 22),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    (item['location'] ?? 'Unknown Location')
                                        .toString(),
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Client Meeting',
                                    style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.85),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      _detailsLabelItin(tc, 'MEETING INFO'),
                      const SizedBox(height: 10),
                      _detailsRowItin(
                        tc,
                        icon: Icons.tag_rounded,
                        label: 'Reference ID',
                        value: (item['id'] ?? 'N/A').toString(),
                        isMono: true,
                      ),
                      _detailsRowItin(
                        tc,
                        icon: Icons.place_rounded,
                        label: 'Location',
                        value: (item['location'] ?? 'Unknown Location')
                            .toString(),
                      ),
                      _detailsRowItin(
                        tc,
                        icon: Icons.calendar_today_rounded,
                        label: 'Date',
                        value: _fmtDateShared(item['date']),
                      ),
                      _detailsRowItin(
                        tc,
                        icon: Icons.access_time_rounded,
                        label: 'Time',
                        value: _fmtTimeShared(item['date']),
                      ),
                      _detailsRowItin(
                        tc,
                        icon: Icons.timelapse_rounded,
                        label: 'Logged At',
                        value: _fmtDateTimeShared(item['date']),
                      ),
                      const SizedBox(height: 18),
                      _detailsLabelItin(tc, 'STATUS'),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: tc.cardFill,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: tc.darkBorder
                                  .withValues(alpha: 0.15)),
                        ),
                        child: Row(
                          children: [
                            Icon(statusIcon, color: badgeText, size: 22),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    badgeLabel,
                                    style: TextStyle(
                                        color: badgeText,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    isApproved
                                        ? 'Approved ng HR — counted sa used credits'
                                        : (isPending
                                        ? 'Naghihintay ng approval mula sa HR'
                                        : 'Na-reject ng HR'),
                                    style: TextStyle(
                                        color: tc.textMuted,
                                        fontSize: 11,
                                        height: 1.4),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (employeeName != null &&
                          employeeName.trim().isNotEmpty) ...[
                        const SizedBox(height: 18),
                        _detailsLabelItin(tc, 'LOGGED BY'),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: tc.cardFill,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: tc.darkBorder
                                    .withValues(alpha: 0.15)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: const BoxDecoration(
                                  gradient: _ItinColors.headerGradient,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    employeeName
                                        .trim()
                                        .substring(0, 1)
                                        .toUpperCase(),
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  employeeName,
                                  style: TextStyle(
                                      color: tc.textBlack,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700),
                                ),
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
                          width: double.infinity,
                          height: 50,
                          decoration: BoxDecoration(
                            gradient: _ItinColors.headerGradient,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: _ItinColors.orangeBorder,
                                width: 1.15),
                            boxShadow: [
                              BoxShadow(
                                  color: _ItinColors.orange
                                      .withValues(alpha: 0.3),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6)),
                            ],
                          ),
                          child: const Center(
                            child: Text('Close',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800)),
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
      );
    },
  );
}

Widget _detailsLabelItin(_ThemeColors tc, String text) {
  return Text(
    text,
    style: TextStyle(
      color: tc.textMuted,
      fontSize: 10,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.4,
    ),
  );
}

Widget _detailsRowItin(
    _ThemeColors tc, {
      required IconData icon,
      required String label,
      required String value,
      bool isMono = false,
    }) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: tc.cardFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tc.darkBorder.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Icon(icon, color: _ItinColors.orange, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    color: tc.textGray,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                  color: tc.textBlack,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  fontFamily: isMono ? 'monospace' : null),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    ),
  );
}

// ══════════════════════════════════════════════════════════════
// ITINERARY SCREEN
// ══════════════════════════════════════════════════════════════
class ItineraryScreen extends StatefulWidget {
  final String employeeId;
  final String employeeName;
  final VoidCallback? onGoHome;

  const ItineraryScreen({
    super.key,
    required this.employeeId,
    required this.employeeName,
    this.onGoHome,
  });

  @override
  State<ItineraryScreen> createState() => _ItineraryScreenState();
}

class _ItineraryScreenState extends State<ItineraryScreen>
    with WidgetsBindingObserver {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _history = [];
  int _usedTotal = 0;

  // 🌐 Network state
  _NetworkState _networkState = _NetworkState.online;
  String _networkErrorMessage = 'No internet connection.';
  bool _showOfflineOverlay = false;
  Timer? _overlayDelayTimer;
  bool _isInitialLoading = true;
  StreamSubscription<bool>? _networkSub;

  // ══════════════════════════════════════════════════════════
  // 🔒 SECURITY STATE
  // ══════════════════════════════════════════════════════════
  static const Duration _refreshCooldown = Duration(seconds: 3);
  static const Duration _sessionWatchdog = Duration(minutes: 30);
  static const int _maxRefreshesPerSession = 50;

  late final String _sessionNonce;
  DateTime? _lastRefreshAt;
  DateTime? _lastUserActivityAt;
  DateTime? _openedAt;
  int _totalRefreshes = 0;
  Timer? _heartbeatTimer;
  Timer? _sessionWatchdogTimer;
  bool _sessionValidated = false;
  String? _verifiedEmployeeId;

  // 🎭 DEMO MODE
  bool get _isDemo => DemoModeService.instance.isEnabled;

  int get _remaining =>
      (_kTotalCredits - _usedTotal).clamp(0, _kTotalCredits);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // 🔒 Initialize security
    _sessionNonce = _generateSessionNonce();
    _lastUserActivityAt = DateTime.now();
    _openedAt = DateTime.now();

    // ═══════════════════════════════════════════════════════════
    // 🎭 DEMO MODE — skip network listener, security monitoring
    //             pero IPAKITA ANG SKELETON sa simula
    // ═══════════════════════════════════════════════════════════
    if (_isDemo) {
      debugPrint('═══════════════════════════════════════════');
      debugPrint('🎭 [DemoMode] Itinerary — DEMO PATH');
      debugPrint('   • Skipping network listener');
      debugPrint('   • Skipping security monitoring');
      debugPrint('   • Skipping Firestore fetch');
      debugPrint('   • Skeleton shown for ${_kDemoSkeletonDuration.inMilliseconds}ms');
      debugPrint('═══════════════════════════════════════════');

      _networkState = _NetworkState.online;
      _sessionValidated = true;
      _verifiedEmployeeId = widget.employeeId;

      // 🆕 Keep skeleton visible at start
      _isInitialLoading = true;

      _fetchData();

      // 🆕 Hide skeleton after short delay
      Future.delayed(_kDemoSkeletonDuration, () {
        if (!mounted) return;
        setState(() => _isInitialLoading = false);
        debugPrint('🎭 [DemoMode] Skeleton hidden — demo UI revealed');
      });

      return;
    }

    // ═══════════════════════════════════════════════════════════
    // NORMAL MODE
    // ═══════════════════════════════════════════════════════════
    try {
      _networkSub =
          ConnectivityService.instance.onStatusChange.listen((online) {
            if (!mounted) return;
            debugPrint('🌐 [Itinerary] connectivity → online=$online');

            if (!online) {
              _overlayDelayTimer?.cancel();
              setState(() {
                _networkState = _NetworkState.offline;
                _networkErrorMessage =
                'No internet connection.\nPlease check your network.';
                _showOfflineOverlay = false;
              });

              _overlayDelayTimer =
                  Timer(const Duration(milliseconds: 1200), () {
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
    } catch (e) {
      debugPrint('⚠️ [Itinerary] connectivity failed: $e');
    }

    _startSecurityMonitoring();

    _checkNetworkOnEntry().then((_) {
      if (mounted) {
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) setState(() => _isInitialLoading = false);
        });
      }
    });

    _fetchData();
  }

  // ══════════════════════════════════════════════════════════
  // 🔒 SECURITY METHODS
  // ══════════════════════════════════════════════════════════

  Future<bool> _validateSession() async {
    // 🎭 DEMO — always valid
    if (_isDemo) return true;

    try {
      final valid = await SecurityService.instance.isSessionValid();
      if (!valid) {
        await _logSecurityEventGlobal(
          type: 'itinerary_session_invalid',
          severity: 'high',
          details: 'Session expired',
          employeeId: widget.employeeId,
          sessionNonce: _sessionNonce,
        );
        return false;
      }

      final sessionEmpId =
      await SecurityService.instance.getCurrentEmployeeId();
      if (sessionEmpId != null && sessionEmpId != widget.employeeId) {
        await _logSecurityEventGlobal(
          type: 'itinerary_cross_access',
          severity: 'critical',
          details:
          'Session ($sessionEmpId) != viewing (${widget.employeeId})',
          employeeId: widget.employeeId,
          sessionNonce: _sessionNonce,
        );
        return false;
      }

      _verifiedEmployeeId = sessionEmpId ?? widget.employeeId;
      return true;
    } catch (e) {
      debugPrint('⚠️ [Itinerary] Session validation error: $e');
      return true;
    }
  }

  // 🔒 Wrapper — uses top-level function with state's session info
  Future<void> _logSecurityEvent({
    required String type,
    required String severity,
    required String details,
  }) async {
    await _logSecurityEventGlobal(
      type: type,
      severity: severity,
      details: details,
      employeeId: _verifiedEmployeeId ?? widget.employeeId,
      sessionNonce: _sessionNonce,
    );
  }

  void _startSecurityMonitoring() {
    // 🎭 DEMO — skip
    if (_isDemo) return;

    // Heartbeat
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 2), (_) async {
      if (!mounted) return;
      await SecurityService.instance.markSessionActive();
    });

    // Watchdog
    _sessionWatchdogTimer?.cancel();
    _sessionWatchdogTimer =
        Timer.periodic(const Duration(minutes: 1), (_) async {
          if (!mounted) return;
          if (_lastUserActivityAt == null) return;

          final idle = DateTime.now().difference(_lastUserActivityAt!);
          if (idle > _sessionWatchdog) {
            await _logSecurityEvent(
              type: 'itinerary_inactivity',
              severity: 'info',
              details: 'Idle for ${idle.inMinutes} min',
            );
          }
        });

    // Initial validation
    _validateSession().then((valid) {
      if (mounted) {
        setState(() => _sessionValidated = valid);
        _logSecurityEvent(
          type: 'itinerary_opened',
          severity: 'info',
          details: 'Itinerary screen opened',
        );
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isDemo) return;

    if (state == AppLifecycleState.resumed) {
      _lastUserActivityAt = DateTime.now();
      _validateSession();
    }
  }

  // ══════════════════════════════════════════════════════════
  // 🔒 RATE LIMIT
  // ══════════════════════════════════════════════════════════
  bool _checkRefreshRateLimit() {
    // 🎭 DEMO — no rate limit
    if (_isDemo) return true;

    final now = DateTime.now();
    if (_lastRefreshAt != null) {
      final elapsed = now.difference(_lastRefreshAt!).inMilliseconds;
      if (elapsed < _refreshCooldown.inMilliseconds) {
        debugPrint('🚦 [Itinerary] Refresh rate-limited ($elapsed ms)');
        return false;
      }
    }
    _lastRefreshAt = now;
    _totalRefreshes++;

    if (_totalRefreshes > _maxRefreshesPerSession) {
      _logSecurityEvent(
        type: 'itinerary_excessive_refresh',
        severity: 'medium',
        details: 'Total refreshes: $_totalRefreshes',
      );
    }

    return true;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _networkSub?.cancel();
    _overlayDelayTimer?.cancel();
    _heartbeatTimer?.cancel();
    _sessionWatchdogTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkNetworkOnEntry() async {
    // 🎭 DEMO — always online
    if (_isDemo) {
      if (mounted) setState(() => _networkState = _NetworkState.online);
      return;
    }

    if (!mounted) return;
    setState(() => _networkState = _NetworkState.checking);

    bool hasNet = true;
    try {
      hasNet = ConnectivityService.instance.isOnline;
    } catch (_) {
      hasNet = true;
    }

    if (!mounted) return;

    if (!hasNet) {
      setState(() {
        _networkState = _NetworkState.offline;
        _networkErrorMessage =
        'No internet connection.\nPlease check your network and try again.';
      });
      return;
    }

    setState(() => _networkState = _NetworkState.online);
  }

  Future<void> _retryNetworkCheck() async {
    if (_isDemo) return;

    if (!mounted) return;
    _lastUserActivityAt = DateTime.now();

    setState(() {
      _networkState = _NetworkState.checking;
      _showOfflineOverlay = false;
    });

    await _checkNetworkOnEntry();

    if (_networkState == _NetworkState.online && mounted) {
      try {
        await _fetchData();
      } catch (e) {
        debugPrint('⚠️ Retry refresh failed: $e');
      }
    }
  }

  // ══════════════════════════════════════════════════════════
  // 🎭 DEMO DATA — fake itinerary history
  // ══════════════════════════════════════════════════════════
  List<Map<String, dynamic>> _buildDemoHistory() {
    final now = DateTime.now();
    return <Map<String, dynamic>>[
      {
        'id': 'DEMO_ITIN_001',
        'location': 'BGC Corporate Center, Taguig',
        'date': now.subtract(const Duration(hours: 3)),
        'status': 'approved',
      },
      {
        'id': 'DEMO_ITIN_002',
        'location': 'Makati Medical Center',
        'date': now.subtract(const Duration(days: 1)),
        'status': 'approved',
      },
      {
        'id': 'DEMO_ITIN_003',
        'location': 'SM Mall of Asia, Pasay',
        'date': now.subtract(const Duration(days: 2)),
        'status': 'pending_hr_approval',
      },
      {
        'id': 'DEMO_ITIN_004',
        'location': 'Ortigas Center, Pasig',
        'date': now.subtract(const Duration(days: 4)),
        'status': 'approved',
      },
      {
        'id': 'DEMO_ITIN_005',
        'location': 'Quezon City Hall',
        'date': now.subtract(const Duration(days: 6)),
        'status': 'rejected',
      },
    ];
  }

  // ══════════════════════════════════════════════════════════
  // 🔒 SECURED FETCH
  // ══════════════════════════════════════════════════════════
  Future<void> _fetchData() async {
    if (!mounted) return;

    // ═══════════════════════════════════════════════════════════
    // 🎭 DEMO MODE — load fake data, no Firestore
    // ═══════════════════════════════════════════════════════════
    if (_isDemo) {
      setState(() {
        _loading = true;
        _error = null;
      });

      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;

      final demoList = _buildDemoHistory();
      int used = 0;
      for (final item in demoList) {
        if (item['status'] == 'approved') used += 1;
      }

      if (!mounted) return;
      setState(() {
        _history = demoList;
        _usedTotal = used;
        _loading = false;
      });

      debugPrint('🎭 [DemoMode] Loaded ${demoList.length} demo itinerary items');
      return;
    }

    // 🔒 Rate limit check
    if (!_checkRefreshRateLimit()) return;

    // 🔒 Session validation
    final valid = await _validateSession();
    if (!valid) {
      if (mounted) {
        setState(() {
          _error = 'Session expired. Please log in again.';
          _loading = false;
        });
      }
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final snap = await FirebaseFirestore.instance
          .collection('attendance_logs')
          .where('type', isEqualTo: 'client_meeting')
          .get();

      final list = <Map<String, dynamic>>[];
      int used = 0;

      for (final doc in snap.docs) {
        final d = doc.data();

        final empId = (d['employee_id'] ?? d['employeeId'] ?? '').toString();
        if (empId.isEmpty) continue;

        // 🔒 Verify viewing own data only
        if (empId != widget.employeeId) {
          if (d['employee_id'] != null) {
            debugPrint('⚠️ [Itinerary] Skipping other employee: $empId');
          }
          continue;
        }

        final status =
        (d['status'] ?? 'pending_hr_approval').toString().toLowerCase();
        final location =
        (d['location_name'] ?? 'Unknown Location').toString();
        final ts = d['timestamp'] ?? d['createdAt'];

        list.add({
          'id': doc.id,
          'location': location,
          'date': ts,
          'status': status,
        });

        if (status == 'approved') used += 1;
      }

      list.sort((a, b) {
        final at = _toDateTimeShared(a['date']);
        final bt = _toDateTimeShared(b['date']);
        if (at == null && bt == null) return 0;
        if (at == null) return 1;
        if (bt == null) return -1;
        return bt.compareTo(at);
      });

      debugPrint('📋 [Itinerary] Found ${list.length} client meetings '
          '($used approved) for ${widget.employeeId}');

      if (!mounted) return;
      setState(() {
        _history = list;
        _usedTotal = used;
        _loading = false;
      });
    } catch (e) {
      debugPrint('ItineraryScreen fetch error: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load client meeting data. Please try again.';
      });

      await _logSecurityEvent(
        type: 'itinerary_fetch_error',
        severity: 'medium',
        details: 'Error: ${e.toString()}',
      );
    }
  }

  DateTime? _toDateTime(dynamic v) => _toDateTimeShared(v);

  String _fmt(dynamic v) => _fmtDateShared(v);

  String _fmtTime(dynamic v) => _fmtTimeShared(v);

  void _goBack() {
    _lastUserActivityAt = DateTime.now();
    if (widget.onGoHome != null) {
      widget.onGoHome!();
    } else if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = _ThemeColors(isDark);

    final isOffline = _networkState == _NetworkState.offline;
    final isChecking = _networkState == _NetworkState.checking;

    // ═══════════════════════════════════════════════════════════
    // 🆕 SKELETON LOADING STATE (works for demo + normal)
    // ═══════════════════════════════════════════════════════════
    if (isOffline || isChecking || _isInitialLoading) {
      return Scaffold(
        backgroundColor: tc.bg,
        body: SafeArea(
          child: Stack(
            children: [
              const ListSkeleton(itemCount: 5),
              if (isOffline)
                Positioned.fill(
                  child: AnimatedOpacity(
                    opacity: _showOfflineOverlay ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeInOut,
                    child: IgnorePointer(
                      ignoring: !_showOfflineOverlay,
                      child: _buildNetworkErrorOverlay(
                        message: _networkErrorMessage,
                        onRetry: _retryNetworkCheck,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: tc.bg,
      body: SafeArea(
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            _buildHandWatermark(opacity: tc.watermarkOpacity),

            Column(
              children: [
                _buildHeader(tc),
                const SizedBox(height: 20),
                Expanded(
                  child: RefreshIndicator(
                    color: _ItinColors.orange,
                    onRefresh: _fetchData,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildStatCards(tc),
                          const SizedBox(height: 28),
                          Padding(
                            padding:
                            const EdgeInsets.symmetric(horizontal: 24),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Client Meeting History',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: tc.textBlack,
                                    ),
                                  ),
                                ),
                                if (!_loading && _history.isNotEmpty)
                                  Text(
                                    'Tap card for details',
                                    style: TextStyle(
                                        color: tc.textMuted,
                                        fontSize: 10,
                                        fontStyle: FontStyle.italic),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildHistoryList(tc),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── HEADER ─────────────────────────────────────────────
  Widget _buildHeader(_ThemeColors tc) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      decoration: const BoxDecoration(
        gradient: _ItinColors.headerGradient,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _goBack,
            behavior: HitTestBehavior.opaque,
            child: const Icon(
              Icons.chevron_left_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              children: [
                const Text(
                  'Itinerary',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
                // 🎭 DEMO badge
                if (_isDemo) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.5),
                          width: 1),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.science_rounded,
                            color: Colors.white, size: 10),
                        SizedBox(width: 3),
                        Text('DEMO',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          GestureDetector(
            onTap: _fetchData,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: tc.isDark
                    ? const Color(0xFF1F1F23)
                    : _ItinColors.cardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: _ItinColors.orangeBorder, width: 1.11),
              ),
              child: const Icon(
                Icons.refresh_rounded,
                color: _ItinColors.orange,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── STAT CARDS ────────────────────────────────────────
  Widget _buildStatCards(_ThemeColors tc) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Expanded(
            child: _StatCard(
              value: '$_kTotalCredits',
              label: 'Total',
              valueColor: tc.textBlack,
              labelColor: tc.textMuted,
              bgColor: tc.cardFill,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _StatCard(
              value: '$_usedTotal',
              label: 'Used',
              valueColor: _ItinColors.lime,
              labelColor: tc.textMuted,
              bgColor: tc.cardFill,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _StatCard(
              value: '$_remaining',
              label: 'Remaining',
              valueColor: _ItinColors.orange,
              labelColor: _ItinColors.orange,
              bgColor: _ItinColors.orange.withValues(alpha: 0.2),
              borderColor: _ItinColors.orange.withValues(alpha: 0.2),
            ),
          ),
        ],
      ),
    );
  }

  // ─── HISTORY LIST ──────────────────────────────────────
  Widget _buildHistoryList(_ThemeColors tc) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: CircularProgressIndicator(color: _ItinColors.orange),
        ),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Center(
          child: Column(
            children: [
              Text(_error!,
                  style: const TextStyle(color: _ItinColors.error)),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _fetchData,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _ItinColors.orange,
                ),
                child: const Text('Retry',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    if (_history.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.event_busy_rounded,
                  size: 40, color: tc.textMuted),
              const SizedBox(height: 12),
              Text(
                'No client meeting records yet.',
                style: TextStyle(color: tc.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                'Go to Login → Client Meeting to check in.',
                textAlign: TextAlign.center,
                style: TextStyle(color: tc.textMuted, fontSize: 11),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: _history.map((item) => _historyCard(item, tc)).toList(),
      ),
    );
  }

  Widget _historyCard(Map<String, dynamic> item, _ThemeColors tc) {
    final status = (item['status'] ?? 'pending_hr_approval')
        .toString()
        .toLowerCase();

    final isApproved = status == 'approved';
    final isRejected = status == 'rejected';
    final isPending = !isApproved && !isRejected;

    final badgeBg = isApproved
        ? _ItinColors.limeBg
        : (isPending
        ? _ItinColors.orange.withValues(alpha: 0.1)
        : _ItinColors.errorBg);
    final badgeBorder = isApproved
        ? _ItinColors.limeBorder
        : (isPending
        ? _ItinColors.orange.withValues(alpha: 0.2)
        : _ItinColors.errorBorder);
    final badgeText = isApproved
        ? _ItinColors.lime
        : (isPending ? _ItinColors.orange : _ItinColors.error);

    final badgeLabel =
    isApproved ? 'Approved' : (isPending ? 'Pending' : 'Rejected');

    return GestureDetector(
      onTap: () {
        _lastUserActivityAt = DateTime.now();
        _showItineraryDetailsSheet(
          context,
          item,
          employeeName: widget.employeeName,
        );
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: tc.cardFill,
          borderRadius: BorderRadius.circular(16),
          border:
          Border.all(color: _ItinColors.orangeBorder, width: 1.11),
          boxShadow: [
            BoxShadow(
              color: Colors.black
                  .withValues(alpha: tc.isDark ? 0.25 : 0.06),
              blurRadius: 4,
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
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.location_on_rounded,
                          color: _ItinColors.orange, size: 14),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Client Meeting',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: tc.textBlack,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(12),
                    border:
                    Border.all(color: badgeBorder, width: 1.11),
                  ),
                  child: Text(
                    badgeLabel,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: badgeText,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.place_rounded,
                  size: 12,
                  color: _ItinColors.orange,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    item['location'].toString(),
                    style: TextStyle(
                      fontSize: 12,
                      color: tc.textMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${_fmt(item['date'])} · ${_fmtTime(item['date'])}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: tc.textBlack,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'View details',
                  style: TextStyle(
                      color: _ItinColors.orange,
                      fontSize: 10,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 2),
                const Icon(Icons.chevron_right_rounded,
                    color: _ItinColors.orange, size: 14),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// STAT CARD
// ══════════════════════════════════════════════════════════════
class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  final Color valueColor;
  final Color labelColor;
  final Color bgColor;
  final Color borderColor;

  const _StatCard({
    required this.value,
    required this.label,
    required this.valueColor,
    required this.labelColor,
    required this.bgColor,
    this.borderColor = _ItinColors.orangeBorder,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.11),
        boxShadow: [
          BoxShadow(
            color: Colors.black
                .withValues(alpha: isDark ? 0.25 : 0.05),
            blurRadius: 3,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w500,
              color: valueColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, color: labelColor),
          ),
        ],
      ),
    );
  }
}