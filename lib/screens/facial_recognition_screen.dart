// lib/screens/facial_recognition_screen.dart
// v3.3: 🏷️ Removed all biometric matching/enrollment logic.
//       Renamed to "Face Liveness Check" everywhere.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/employee.dart';
import '../services/face_matcher.dart'; // Kept for cleanup only
import '../services/clock_status_service.dart';
import '../services/geofence_service.dart';
import '../services/admin_notification_service.dart';
import '../services/network_guard.dart';
import '../services/offline_attendance_service.dart';
import '../services/device_info_service.dart';
import '../services/face_liveness.dart';
import '../services/security_hardening_service.dart';
import '../services/presence_challenge_service.dart';
import '../services/demo_mode_service.dart';
import '../services/overtime_reminder_service.dart';
import '../services/trusted_time_service.dart';
import '../services/face_support_service.dart';
import '../data/local/dao/connectivity_service.dart';
import '../widgets/skeleton_screens.dart';
import 'main_screen.dart';
import 'clock_in_success_screen.dart';

void _secureLog(String message) {
  if (kDebugMode) debugPrint(message);
}

class _ThemeColors {
  final bool isDark;
  const _ThemeColors(this.isDark);

  Color get bg => isDark ? const Color(0xFF0A0A0A) : const Color(0xFFF7F7F7);
  Color get bgTop => isDark ? const Color(0xFF0A0A0A) : const Color(0xFFFFFFFF);
  Color get outerCardBg =>
      isDark ? const Color(0xFF18181B) : const Color(0xFFECEBE8);
  Color get stepLabelColor =>
      isDark ? const Color(0xFFB0B0B0) : const Color(0xFF8A8A85);
  Color get cancelBg =>
      isDark ? const Color(0xFFFFFFFF) : const Color(0xFFFFFFFF);
  Color get cancelPressed =>
      isDark ? const Color(0xFFFFF4EE) : const Color(0xFFFFF4EE);
  Color get cancelText => const Color(0xFFF05000);
}

enum _NetState { online, offline, checking }

class FacialRecognitionScreen extends StatefulWidget {
  final Employee employee;
  final DateTime? arrivalTime;
  final PresenceChallenge? challenge;

  const FacialRecognitionScreen({
    super.key,
    required this.employee,
    this.arrivalTime,
    this.challenge,
  });

  @override
  State<FacialRecognitionScreen> createState() =>
      _FacialRecognitionScreenState();
}

class _FacialRecognitionScreenState extends State<FacialRecognitionScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  bool get _isChallenge => widget.challenge != null;
  bool get _isDemo => DemoModeService.instance.isEnabled;

  _FaceState _faceState = _FaceState.idle;
  String? _errorMessage;
  _FaceWarning _faceWarning = _FaceWarning.none;

  CameraController? _camCtrl;
  bool _camReady = false;
  bool _camTried = false;
  bool _cancelPressed = false;
  bool _isProcessing = false;
  bool _isScanning = false;
  String? _camError;

  bool _isCheckingGeofence = false;

  bool _geofenceVerifiedOffline = false;
  int _pendingCount = 0;
  StreamSubscription<int>? _pendingSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _adminActionSub;

  String _deviceModel = 'Unknown Device';

  static const double _minFaceAreaRatio = 0.06;
  static const double _maxFaceAreaRatio = 0.65;
  static const double _maxHeadYawDeg = 22.0;
  static const double _maxHeadRollDeg = 22.0;
  static const double _maxHeadPitchDeg = 20.0;

  static const double _verifyMaxYaw = 30.0;
  static const double _verifyMaxRoll = 30.0;
  static const double _verifyMaxPitch = 25.0;
  static const double _verifyMinFaceArea = 0.02;
  static const double _verifyMaxFaceArea = 0.80;
  static const double _verifyMinSharpness = 8.0;

  late final FaceDetector _faceDetector;

  _LivenessStep _livenessStep = _LivenessStep.waitingForFace;
  bool _blinkDone = false;
  bool _smileDone = false;

  bool _facePresent = false;
  bool _eyesWereClosed = false;
  int _closedFrames = 0;
  int _openFramesAfterClose = 0;

  static const int _minClosedFrames = 2;
  static const int _minOpenFrames = 2;
  static const double _blinkClosedThreshold = 0.40;
  static const double _blinkOpenThreshold = 0.55;
  static const double _smileThreshold = 0.40;
  static const int _maxClosedFramesBeforeStuck = 45;

  DateTime? _livenessStartTime;
  static const int _livenessTimeoutMs = 25000;

  static const double _cameraBoxSize = 300.0;

  final FaceLivenessService _webLiveness = FaceLivenessService();

  static const double _webEyeClosedThreshold = 0.30;
  static const double _webEyeOpenThreshold = 0.35;
  static const double _webSmileThreshold = 0.40;
  static const int _webDetectIntervalMs = 150;

  bool _preAuthValid = false;
  bool _deviceCompromised = false;
  bool _obscureContent = false;
  String? _deviceBinding;
  late final String _sessionNonce;

  bool _cancelRecorded = false;
  bool _sendingAdminReport = false;

  static const String _kLastReportKey = 'last_face_report_time';
  static const String _kLastFaceResetKey = 'fp_last_face_reset_ms';
  static const Duration _reportCooldown = Duration(minutes: 3);

  DateTime? _firstAttemptTime;

  _NetState _networkState = _NetState.online;
  Timer? _overlayDelayTimer;
  bool _isInitialLoading = true;
  StreamSubscription<bool>? _connectivitySub;

  static const String _kPreAuthEmpKey = 'fp_preauth_employee_id';
  static const String _kPreAuthTimeKey = 'fp_preauth_time';

  int _rotationCompensation = 0;

  late AnimationController _pulseCtrl;
  late AnimationController _ringCtrl;
  late AnimationController _fadeCtrl;
  late AnimationController _shakeCtrl;
  late AnimationController _successCtrl;
  late AnimationController _scanLineCtrl;
  late AnimationController _warningCtrl;
  late AnimationController _flashCtrl;

  late Animation<double> _pulseAnim;
  late Animation<double> _ringAnim;
  late Animation<double> _fadeAnim;
  late Animation<double> _shakeAnim;
  late Animation<double> _successAnim;
  late Animation<double> _scanLineAnim;
  late Animation<double> _warningAnim;
  late Animation<double> _flashAnim;

  static const _white = Color(0xFFFFFFFF);
  static const _orange = Color(0xFFF05000);
  static const _success = Color(0xFFCCFF00);
  static const _error = Color(0xFFFF3D00);
  static const _faceGreen = Color(0xFF00E676);
  static const _warning = Color(0xFFFFCC00);
  static const _verifiedGreen = Color(0xFF51FF00);

  static const _demoAccent = Color(0xFFFF8A00);
  static const _demoAccentMid = Color(0xFFFA6A00);
  static const _demoAccentDark = Color(0xFFF54900);

  bool get _isOffline => _networkState == _NetState.offline;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sessionNonce = _generateSessionNonce();

    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableClassification: true,
        enableLandmarks: true,
        enableContours: false,
        minFaceSize: 0.08,
      ),
    );

    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2));
    _ringCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 3));
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _shakeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _successCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _scanLineCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
    _warningCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _flashCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));

    _pulseAnim = Tween<double>(begin: 0.93, end: 1.07).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _ringAnim = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _ringCtrl, curve: Curves.linear));
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut));
    _shakeAnim = Tween<double>(begin: 0, end: 12).animate(CurvedAnimation(parent: _shakeCtrl, curve: Curves.elasticIn));
    _successAnim = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _successCtrl, curve: Curves.elasticOut));
    _scanLineAnim = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _scanLineCtrl, curve: Curves.easeInOut));
    _warningAnim = Tween<double>(begin: 0.7, end: 1.0).animate(CurvedAnimation(parent: _warningCtrl, curve: Curves.easeInOut));
    _flashAnim = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _flashCtrl, curve: Curves.easeOut));

    _pulseCtrl.repeat(reverse: true);
    _ringCtrl.repeat();
    _fadeCtrl.forward();

    if (_isDemo) {
      _secureLog('🎭 [DemoMode] FacialRecognitionScreen — internet required');
      _preAuthValid = true;
      _networkState = _NetState.online;

      try {
        _connectivitySub = ConnectivityService.instance.onStatusChange.listen((online) {
          if (!mounted) return;
          setState(() {
            _networkState = online ? _NetState.online : _NetState.offline;
          });
        });
      } catch (e) {
        _secureLog('⚠️ connectivity listen error: $e');
      }

      try {
        final online = ConnectivityService.instance.isOnline;
        _networkState = online ? _NetState.online : _NetState.offline;
      } catch (_) {}

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await Future.delayed(const Duration(milliseconds: 400));
        if (mounted) setState(() => _isInitialLoading = false);
      });
      return;
    }

    _loadDeviceModel();
    _bootstrapSecurity();
    _subscribePendingCount();
    _setupAdminActionListener();

    try {
      _connectivitySub = ConnectivityService.instance.onStatusChange.listen((online) {
        if (!mounted) return;
        if (!online) {
          setState(() => _networkState = _NetState.offline);
        } else if (_networkState == _NetState.offline) {
          _retryNetworkCheck();
        }
      });
    } catch (e) {
      _secureLog('⚠️ connectivity listen error: $e');
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkNetworkAndProceed();
      if (mounted) {
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) setState(() => _isInitialLoading = false);
        });
      }
      _updateRotationCompensation();
    });
  }

  void _setupAdminActionListener() {
    if (_isDemo) return;
    final id = widget.employee.id;
    if (id.isEmpty) return;

    _adminActionSub = FirebaseFirestore.instance
        .collection('employees')
        .doc(id)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final data = snap.data();
      if (data != null) _processAdminActions(data);
    });
  }

  Future<void> _processAdminActions(Map<String, dynamic> data) async {
    if (_isDemo) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastReset = prefs.getInt(_kLastFaceResetKey) ?? 0;
      final resetAt = (data['faceAdminResetAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;

      if (resetAt > lastReset) {
        await prefs.setInt(_kLastFaceResetKey, resetAt);

        try {
          const prefixes = <String>[
            'face_template_', 'face_enrolled_', 'face_photo_url_',
            'face_samples_', 'face_embedding_', 'face_version_', 'face_count_'
          ];
          final id = widget.employee.id;
          final stale = prefs.getKeys().where((k) => k.contains(id) && prefixes.any(k.startsWith)).toList();
          for (final k in stale) { await prefs.remove(k); }
        } catch (_) {}

        if (mounted) {
          setState(() {
            _faceState = _FaceState.idle;
            _errorMessage = null;
            _faceWarning = _FaceWarning.none;
          });
          _showInfoSnack('🔄 Admin reset your liveness status. Please try again.');
        }
      }
    } catch (e) {
      _secureLog('⚠️ Admin action process failed: $e');
    }
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  void _resetFirstAttempt() {
    _firstAttemptTime = null;
  }

  DateTime get _effectiveAttendanceTime {
    final now = DateTime.now();
    if (_firstAttemptTime != null && _isSameDay(_firstAttemptTime!, now)) {
      return _firstAttemptTime!;
    }
    return now;
  }

  void _showOfflineSnack([String? custom]) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.cloud_off_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  custom ?? 'Internet connection is required for Demo Mode.',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          backgroundColor: _error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 3),
        ),
      );
  }

  static const List<({String key, String label})> _reportCategories = [
    (key: 'liveness_failed',     label: 'Liveness failed'),
    (key: 'camera_error',        label: 'Camera problem'),
    (key: 'geofence_issue',      label: 'Location issue'),
    (key: 'security_issue',      label: 'Security error'),
    (key: 'other',               label: 'Other'),
  ];

  void _showInfoSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
          backgroundColor: const Color(0xFF27272A),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 3),
        ),
      );
  }

  String _defaultReportCategory() {
    final err = (_errorMessage ?? '').toLowerCase();
    if (err.contains('camera')) return 'camera_error';
    if (err.contains('liveness')) return 'liveness_failed';
    if (err.contains('compromised') || err.contains('security')) return 'security_issue';
    if (err.contains('geofence') || err.contains('location')) return 'geofence_issue';
    return 'other';
  }

  String _labelForReportCategory(String c) {
    return _reportCategories.firstWhere((e) => e.key == c, orElse: () => (key: c, label: c)).label;
  }

  String _buildReportMessage({required String category, required String notes}) {
    final buf = StringBuffer();
    buf.writeln('Employee reported an issue: ${_labelForReportCategory(category)}.');
    if (_errorMessage != null && _errorMessage!.isNotEmpty) {
      buf.writeln('Error shown: ${_errorMessage!.replaceAll('\n', ' ')}');
    }
    buf.writeln('Stage: ${_faceState.name} • Mode: Liveness');
    buf.writeln('Device: $_deviceModel • Network: ${_networkState.name}');
    if (notes.isNotEmpty) buf.writeln('\nNotes from employee: $notes');
    return buf.toString().trim();
  }

  Future<bool> _checkReportCooldown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastMs = prefs.getInt(_kLastReportKey) ?? 0;
      if (lastMs > 0) {
        final last = DateTime.fromMillisecondsSinceEpoch(lastMs);
        final diff = DateTime.now().difference(last);
        if (diff < _reportCooldown) {
          final remaining = _reportCooldown - diff;
          final mins = remaining.inMinutes;
          final secs = remaining.inSeconds % 60;
          final timeStr = mins > 0 ? '${mins}m ${secs}s' : '${secs}s';
          _showInfoSnack('⚠️ Please wait $timeStr before sending again.');
          return false;
        }
      }
      return true;
    } catch (_) {
      return true;
    }
  }

  Future<void> _markReportSent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kLastReportKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  Future<bool> _sendAdminReport({required String category, required String notes}) async {
    if (_isDemo) return false;
    if (_sendingAdminReport) return false;
    final canSend = await _checkReportCooldown();
    if (!canSend) return false;

    setState(() => _sendingAdminReport = true);

    try {
      final result = await FaceSupportService.instance.reportIssue(
        employeeId: _employeeIdForAttendance,
        employeeName: widget.employee.fullName,
        employeeEmail: widget.employee.email,
        employeeDocId: widget.employee.id,
        subCategory: category,
        issueMessage: _buildReportMessage(category: category, notes: notes),
        additionalNotes: notes.isEmpty ? null : notes,
        faceMatchPercent: null,
        deviceModel: _deviceModel,
        zoneType: _computeZoneType(),
        authMode: 'liveness',
        stage: _faceState.name,
        errorDetail: _errorMessage,
      );

      if (!mounted) return result.ok;

      if (result.ok && result.queuedOffline) {
        _showInfoSnack('📥 Saved. Your report will reach Admin once you\'re back online.');
      } else if (result.ok) {
        _showInfoSnack('📨 Report sent. Admin will contact you shortly.');
        await _markReportSent();
      } else {
        _showInfoSnack('⚠️ Could not send report. Please try again.');
      }
      return result.ok;
    } catch (e) {
      _secureLog('⚠️ _sendAdminReport failed: $e');
      if (mounted) _showInfoSnack('⚠️ Could not send report. Please try again.');
      return false;
    } finally {
      if (mounted) setState(() => _sendingAdminReport = false);
    }
  }

  Future<void> _openContactAdminSheet() async {
    if (_isDemo) {
      _showInfoSnack('Contact Admin is disabled in Demo Mode.');
      return;
    }
    if (_sendingAdminReport) return;

    final notesCtrl = TextEditingController();
    String category = _defaultReportCategory();
    bool sending = false;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = isDark ? const Color(0xFF1C1C1F) : Colors.white;
    final textCol = isDark ? Colors.white : const Color(0xFF111111);
    final mutedCol = isDark ? const Color(0xFFA1A1AA) : const Color(0xFF6B7280);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Future<void> doSend() async {
            if (sending) return;
            setSheet(() => sending = true);
            final ok = await _sendAdminReport(category: category, notes: notesCtrl.text.trim());
            if (!ctx.mounted) return;
            setSheet(() => sending = false);
            if (ok) Navigator.pop(ctx);
          }

          Widget chip(({String key, String label}) c) {
            final active = category == c.key;
            return GestureDetector(
              onTap: sending ? null : () => setSheet(() => category = c.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: active ? _orange : (isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF4F4F5)),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: active ? _orange : mutedCol.withValues(alpha: 0.25), width: 1),
                ),
                child: Text(
                  c.label,
                  style: TextStyle(
                    color: active ? Colors.white : textCol,
                    fontSize: 11.5,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
            );
          }

          Widget ctxRow(String k, String v) => Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 62, child: Text(k, style: TextStyle(fontSize: 10, color: mutedCol, fontWeight: FontWeight.w700))),
                Expanded(child: Text(v, style: TextStyle(fontSize: 10.5, color: textCol, fontWeight: FontWeight.w600))),
              ],
            ),
          );

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              decoration: BoxDecoration(color: sheetBg, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: mutedCol.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(4)))),
                    const SizedBox(height: 14),
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: _orange.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.support_agent_rounded, color: _orange, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Contact Admin', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: textCol)),
                            Text('Tell us what went wrong with your liveness check.', style: TextStyle(fontSize: 11.5, color: mutedCol)),
                          ],
                        ),
                      ),
                    ]),
                    const SizedBox(height: 16),
                    Text('What went wrong?', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: mutedCol, letterSpacing: 0.5)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [for (final c in _reportCategories) chip(c)]),
                    const SizedBox(height: 16),
                    TextField(
                      controller: notesCtrl,
                      maxLines: 4,
                      maxLength: 500,
                      enabled: !sending,
                      style: TextStyle(color: textCol, fontSize: 13, height: 1.4),
                      decoration: InputDecoration(
                        hintText: 'Add details (optional)...',
                        hintStyle: TextStyle(color: mutedCol, fontSize: 13),
                        filled: true,
                        fillColor: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF4F4F5),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: mutedCol.withValues(alpha: 0.3))),
                        focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10)), borderSide: BorderSide(color: _orange, width: 1.5)),
                        counterStyle: TextStyle(color: mutedCol, fontSize: 10),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withValues(alpha: 0.03) : const Color(0xFFF9F9FB),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: mutedCol.withValues(alpha: 0.15)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('INCLUDED AUTOMATICALLY', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: mutedCol, letterSpacing: 0.6)),
                          const SizedBox(height: 6),
                          ctxRow('Stage', _faceState.name),
                          ctxRow('Mode', 'Liveness'),
                          if (_errorMessage != null && _errorMessage!.isNotEmpty) ctxRow('Error', _errorMessage!.replaceAll('\n', ' ')),
                          ctxRow('Device', _deviceModel),
                          ctxRow('Network', _networkState.name),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: sending ? null : () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: mutedCol.withValues(alpha: 0.4)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: Text('Cancel', style: TextStyle(color: textCol, fontWeight: FontWeight.w700)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          onPressed: sending ? null : doSend,
                          icon: sending
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.send_rounded, size: 16),
                          label: Text(sending ? 'Sending...' : 'Send to Admin', style: const TextStyle(fontWeight: FontWeight.w700)),
                          style: FilledButton.styleFrom(
                            backgroundColor: _orange,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  bool _isOnlineSafely() {
    try {
      return ConnectivityService.instance.isOnline;
    } catch (_) {
      return true;
    }
  }

  void _subscribePendingCount() {
    if (_isDemo) return;
    try {
      _pendingSub = OfflineAttendanceService.instance.pendingStream.listen((c) {
        if (mounted) setState(() => _pendingCount = c);
      });
      OfflineAttendanceService.instance.getPendingCount().then((c) {
        if (mounted) setState(() => _pendingCount = c);
      });
    } catch (e) {
      _secureLog('⚠️ pending stream error: $e');
    }
  }

  Future<void> _emitPendingCount() async {
    if (_isDemo) return;
    try {
      final c = await OfflineAttendanceService.instance.getPendingCount();
      if (mounted) setState(() => _pendingCount = c);
    } catch (_) {}
  }

  void _updateRotationCompensation() {
    if (_isDemo) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        final orientation = MediaQuery.of(context).orientation;
        final size = MediaQuery.of(context).size;
        if (orientation == Orientation.portrait) {
          _rotationCompensation = 0;
        } else {
          _rotationCompensation = size.width > size.height ? 90 : 270;
        }
      } catch (_) {}
    });
  }

  Future<bool> _hasNetwork() async {
    try {
      return ConnectivityService.instance.isOnline;
    } catch (_) {
      return true;
    }
  }

  Future<void> _checkNetworkAndProceed() async {
    if (_isDemo) {
      setState(() => _networkState = _NetState.online);
      return;
    }

    if (!mounted) return;
    setState(() => _networkState = _NetState.checking);

    final hasNet = await _hasNetwork();
    if (!mounted) return;

    if (!hasNet) {
      setState(() => _networkState = _NetState.offline);
      return;
    }

    setState(() => _networkState = _NetState.online);
  }

  Future<void> _retryNetworkCheck() async {
    if (_isDemo) return;
    if (!mounted) return;
    _overlayDelayTimer?.cancel();
    setState(() {
      _networkState = _NetState.checking;
      _errorMessage = null;
    });
    await _checkNetworkAndProceed();
  }

  String _generateSessionNonce() {
    final rand = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<T> _executeWithLoadBalancer<T>(Future<T> Function() operation) async {
    int retries = 0;
    const maxRetries = 3;
    final jitter = math.Random().nextInt(800) + 100;
    await Future.delayed(Duration(milliseconds: jitter));

    while (true) {
      try {
        return await operation();
      } catch (e) {
        if (retries >= maxRetries) rethrow;
        retries++;
        final backoff = (math.pow(2, retries) * 1000).toInt() + math.Random().nextInt(500);
        _secureLog('⚖️ [LoadBalancer] Write throttled. Retrying in ${backoff}ms... (Attempt $retries/$maxRetries)');
        await Future.delayed(Duration(milliseconds: backoff));
      }
    }
  }

  Future<void> _bootstrapSecurity() async {
    if (_isDemo) {
      _preAuthValid = true;
      return;
    }

    try {
      await SecurityHardeningService.instance.enableSecureScreen();
    } catch (e) {
      _secureLog('⚠️ [Security] FLAG_SECURE failed: $e');
    }

    try {
      final ok = await SecurityHardeningService.instance.checkDeviceIntegrity();
      if (!ok) {
        _secureLog('🚨 [Integrity] Compromised');
        await _logSecurityEvent(
          type: 'face_compromised_device',
          severity: 'critical',
          details: SecurityHardeningService.instance.integrityIssues.join(','),
        );
      }
      if (mounted) setState(() => _deviceCompromised = !ok);
    } catch (e) {}

    await _verifyPreAuthAndSession();

    try {
      _deviceBinding = await SecurityHardeningService.instance.getDeviceBindingToken();
    } catch (_) {}
  }

  Future<void> _verifyPreAuthAndSession() async {
    if (_isDemo) {
      _preAuthValid = true;
      return;
    }

    try {
      String? secEmpId;
      try {
        secEmpId = await SecurityHardeningService.instance.getCurrentEmployeeId().timeout(const Duration(seconds: 5));
      } catch (e) {
        _secureLog('⚠️ [PreAuth] Session check failed: $e');
      }

      String? preAuthEmpId;
      try {
        final prefs = await SharedPreferences.getInstance();
        preAuthEmpId = prefs.getString(_kPreAuthEmpKey);
      } catch (e) {
        _secureLog('⚠️ [PreAuth] Prefs read failed: $e');
      }

      final targetId = widget.employee.id;
      final sessionMatches = secEmpId != null && secEmpId.isNotEmpty && secEmpId == targetId;
      final prefsMatches = preAuthEmpId != null && preAuthEmpId.isNotEmpty && preAuthEmpId == targetId;
      final bothEmpty = (secEmpId == null || secEmpId.isEmpty) && (preAuthEmpId == null || preAuthEmpId.isEmpty);

      if (!sessionMatches && !prefsMatches && !bothEmpty) {
        if (mounted) {
          setState(() {
            _preAuthValid = false;
            _errorMessage = '🚨 Security check failed. Please log in again.';
            _faceState = _FaceState.error;
          });
          _shakeCtrl.forward(from: 0);
        }
        return;
      }

      _preAuthValid = true;
      _secureLog('✅ [Security] Pre-auth OK');
    } catch (e) {
      _secureLog('🚨 [Security] Pre-auth FATAL: $e');
      _preAuthValid = true;
    }
  }

  Future<void> _logSecurityEvent({
    required String type,
    required String severity,
    required String details,
  }) async {
    if (_isDemo) return;

    if (!NetworkGuard.instance.isOnline) {
      try {
        await OfflineAttendanceService.instance.enqueue(
          collection: 'security_events',
          data: {
            'type': type, 'severity': severity, 'details': details,
            'employeeId': widget.employee.id, 'employeeName': widget.employee.fullName,
            'sessionNonce': _sessionNonce, 'deviceBinding': _deviceBinding,
            'deviceCompromised': _deviceCompromised,
            'stage': _isChallenge ? 'presence_challenge' : 'liveness_check',
            if (_isChallenge) 'challengeId': widget.challenge!.id,
            'platform': kIsWeb ? 'web' : 'mobile', 'timestamp': DateTime.now(),
          },
        );
      } catch (_) {}
      return;
    }

    try {
      final hashDevice = _deviceBinding != null ? sha256.convert(utf8.encode(_deviceBinding!)).toString() : null;
      await FirebaseFirestore.instance.collection('security_events').add({
        'type': type, 'severity': severity, 'details': details,
        'employeeId': widget.employee.id, 'employeeName': widget.employee.fullName,
        'sessionNonce': _sessionNonce, 'deviceHash': hashDevice,
        'deviceBinding': _deviceBinding, 'deviceCompromised': _deviceCompromised,
        'stage': _isChallenge ? 'presence_challenge' : 'liveness_check',
        if (_isChallenge) 'challengeId': widget.challenge!.id,
        'platform': kIsWeb ? 'web' : 'mobile', 'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  Future<void> _loadDeviceModel() async {
    if (_isDemo) {
      if (mounted) setState(() => _deviceModel = 'Demo Device');
      return;
    }
    try {
      final model = await DeviceInfoService.instance.getDeviceModel();
      if (mounted) setState(() => _deviceModel = model);
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final obscure = state == AppLifecycleState.inactive || state == AppLifecycleState.paused || state == AppLifecycleState.hidden;
    if (obscure != _obscureContent && mounted) setState(() => _obscureContent = obscure);

    if (obscure) {
      if (_isScanning) _stopAllCameraOperations();
    } else if (state == AppLifecycleState.resumed) {
      _updateRotationCompensation();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _isScanning = false;
    _connectivitySub?.cancel();
    _pendingSub?.cancel();
    _adminActionSub?.cancel();
    _overlayDelayTimer?.cancel();
    _pulseCtrl.dispose(); _ringCtrl.dispose(); _fadeCtrl.dispose(); _shakeCtrl.dispose();
    _successCtrl.dispose(); _scanLineCtrl.dispose(); _warningCtrl.dispose(); _flashCtrl.dispose();

    final ctrl = _camCtrl;
    if (ctrl != null) {
      try { if (ctrl.value.isStreamingImages) ctrl.stopImageStream().catchError((_) {}); } catch (_) {}
      try { ctrl.dispose(); } catch (_) {}
    }
    _camCtrl = null;
    _faceDetector.close();
    SecurityHardeningService.instance.disableSecureScreen();
    super.dispose();
  }

  Future<void> _recordChallengeFailure(String reason) async {
    if (_isDemo || !_isChallenge || widget.challenge == null || _cancelRecorded) return;
    _cancelRecorded = true;
    try {
      await PresenceChallengeService.instance.recordFailedAttempt(widget.challenge!, faceScore: 0.0, reason: reason);
      unawaited(_logSecurityEvent(
        type: 'presence_challenge_cancelled', severity: 'medium',
        details: 'User cancelled challenge ${widget.challenge!.id} — reason=$reason',
      ));
    } catch (_) {}
  }

  Future<bool> _ensureCameraPermission() async {
    if (kIsWeb) return true;
    try {
      final status = await Permission.camera.status;
      if (status.isGranted) return true;
      final result = await Permission.camera.request();
      if (result.isGranted) return true;
      _onFailure(result.isPermanentlyDenied ? 'Camera access denied.\nEnable in Settings.' : 'Camera permission required.');
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _initCamera() async {
    if (_camTried && _camReady) return;
    _camTried = true;
    _camError = null;
    try {
      final granted = await _ensureCameraPermission();
      if (!granted) {
        _camError = 'Camera permission not granted.';
        return;
      }
      List<CameraDescription> cameras = await availableCameras();
      if (cameras.isEmpty && kIsWeb) {
        await Future.delayed(const Duration(seconds: 1));
        cameras = await availableCameras();
      }
      if (cameras.isEmpty) {
        _camError = 'No camera detected.';
        if (mounted) setState(() {});
        return;
      }
      final front = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cameras.first);
      final ctrl = CameraController(
        front, ResolutionPreset.high, enableAudio: false,
        imageFormatGroup: kIsWeb ? ImageFormatGroup.jpeg : ImageFormatGroup.nv21,
      );
      await ctrl.initialize();

      try { await ctrl.setFocusMode(FocusMode.auto); } catch (_) {}
      try { await ctrl.setExposureMode(ExposureMode.auto); } catch (_) {}

      if (!mounted) {
        ctrl.dispose();
        return;
      }
      setState(() {
        _camCtrl = ctrl;
        _camReady = true;
      });
    } catch (e) {
      _camError = 'Camera error';
      if (mounted) setState(() {});
    }
  }

  Future<void> _waitForFocusAndCapture() async {
    try { await _camCtrl!.setFocusPoint(const Offset(0.5, 0.5)); } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 250));
  }

  Future<void> _startScan() async {
    if (!mounted || _isScanning) return;

    _firstAttemptTime ??= DateTime.now();

    if (_isDemo) {
      final online = _isOnlineSafely();
      if (!online) {
        _showOfflineSnack('Internet connection is required for Demo Mode.');
        return;
      }

      _isScanning = true; _blinkDone = false; _smileDone = false; _eyesWereClosed = false;
      _closedFrames = 0; _openFramesAfterClose = 0; _facePresent = false;
      _livenessStep = _LivenessStep.waitingForFace; _livenessStartTime = DateTime.now();

      setState(() {
        _faceState = _FaceState.scanning;
        _errorMessage = null;
        _faceWarning = _FaceWarning.none;
      });

      bool cameraOk = false;
      if (!kIsWeb) {
        if (!_camReady) await _initCamera();
        cameraOk = _camReady;
      }

      if (!cameraOk) {
        await Future.delayed(const Duration(milliseconds: 1500));
        if (!mounted) return;

        if (!_isOnlineSafely()) {
          _isScanning = false;
          setState(() { _faceState = _FaceState.idle; _errorMessage = null; });
          _showOfflineSnack('No internet connection. Internet is required to continue.');
          return;
        }
        await _demoAutoSucceed();
        return;
      }

      _scanLineCtrl.repeat(reverse: true);
      try {
        await _camCtrl!.startImageStream(_onCameraImage);
      } catch (e) {
        _isScanning = false; _scanLineCtrl.stop();
        if (!_isOnlineSafely()) {
          setState(() { _faceState = _FaceState.idle; _errorMessage = null; });
          _showOfflineSnack('No internet connection. Internet is required to continue.');
          return;
        }
        await _demoAutoSucceed();
      }
      return;
    }

    if (!_preAuthValid) {
      _onFailure('Security check failed. Please log in again.');
      return;
    }

    if (!kIsWeb && _deviceCompromised) {
      _onFailure('This device is flagged as compromised. Access blocked.');
      return;
    }

    _isScanning = true; _blinkDone = false; _smileDone = false; _eyesWereClosed = false;
    _closedFrames = 0; _openFramesAfterClose = 0; _facePresent = false;
    _livenessStep = _LivenessStep.waitingForFace; _livenessStartTime = DateTime.now();

    setState(() {
      _faceState = _FaceState.scanning;
      _errorMessage = null;
      _faceWarning = _FaceWarning.none;
    });

    if (!_camReady) await _initCamera();
    if (!mounted) return;

    if (!_camReady || kIsWeb) {
      _scanLineCtrl.repeat(reverse: true);
      await _runMockScan();
      return;
    }

    _scanLineCtrl.repeat(reverse: true);
    await _camCtrl!.startImageStream(_onCameraImage);
  }

  Future<void> _demoAutoSucceed() async {
    if (!mounted) return;
    if (_isDemo && !_isOnlineSafely()) {
      _isScanning = false; _scanLineCtrl.stop();
      setState(() { _faceState = _FaceState.idle; _errorMessage = null; });
      _showOfflineSnack('No internet connection. Internet is required to continue.');
      return;
    }

    _isScanning = false; _scanLineCtrl.stop();
    _blinkDone = true; _smileDone = true; _facePresent = true;

    setState(() {
      _faceState = _FaceState.success;
      _errorMessage = null;
    });

    _successCtrl.forward(from: 0); _pulseCtrl.stop(); _ringCtrl.stop();

    await Future.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;

    if (_isDemo && !_isOnlineSafely()) {
      setState(() { _faceState = _FaceState.idle; _errorMessage = null; });
      _successCtrl.reset(); _pulseCtrl.repeat(reverse: true); _ringCtrl.repeat();
      _showOfflineSnack('No internet connection. Internet is required to continue.');
      return;
    }

    if (_isChallenge) {
      Navigator.of(context).pop(true);
      return;
    }
    _proceedToNext();
  }

  Future<void> _runMockScan() async {
    if (_isDemo) return;
    while (mounted && _isScanning) {
      await Future.delayed(const Duration(milliseconds: _webDetectIntervalMs));
      if (!mounted || !_isScanning) return;

      final videoEl = _webLiveness.getVideoElement();
      if (videoEl == null) continue;

      final result = await _webLiveness.detect(videoEl);
      if (result == null) continue;

      if (!result.facePresent) {
        if (mounted && _facePresent) setState(() => _facePresent = false);
        continue;
      }

      if (mounted && !_facePresent) setState(() => _facePresent = true);

      if (!_blinkDone) {
        final ear = result.eyeOpenScore;
        if (ear < _webEyeClosedThreshold) {
          _eyesWereClosed = true;
        } else if (ear > _webEyeOpenThreshold && _eyesWereClosed) {
          if (mounted) setState(() => _blinkDone = true);
          _eyesWereClosed = false;
          _livenessStep = _LivenessStep.smile;
        }
        continue;
      }

      if (!_smileDone) {
        if (result.smileScore > _webSmileThreshold) {
          if (mounted) setState(() => _smileDone = true);
        }
        continue;
      }

      _isScanning = false; _scanLineCtrl.stop(); _onLivenessFailed();
      return;
    }
  }

  InputImage? _buildInputImage(CameraImage image) {
    if (_camCtrl == null) return null;

    final camera = _camCtrl!.description;
    final sensorOrientation = camera.sensorOrientation;
    final isFrontCamera = camera.lensDirection == CameraLensDirection.front;

    InputImageRotation rotation;
    if (kIsWeb) {
      rotation = InputImageRotation.rotation0deg;
    } else if (Platform.isIOS) {
      rotation = InputImageRotation.rotation90deg;
    } else {
      if (isFrontCamera) {
        rotation = InputImageRotation.rotation270deg;
      } else {
        final comp = (sensorOrientation + _rotationCompensation) % 360;
        switch (comp) {
          case 90: rotation = InputImageRotation.rotation90deg; break;
          case 180: rotation = InputImageRotation.rotation180deg; break;
          case 270: rotation = InputImageRotation.rotation270deg; break;
          case 0:
          default: rotation = InputImageRotation.rotation0deg;
        }
      }
    }

    try {
      final width = image.width;
      final height = image.height;
      if (width <= 0 || height <= 0) return null;

      if (image.planes.length == 1) {
        final plane = image.planes[0];
        if (plane.bytes.isEmpty) return null;
        final fmt = (kIsWeb || Platform.isIOS) ? InputImageFormat.bgra8888 : InputImageFormat.nv21;
        return InputImage.fromBytes(
          bytes: plane.bytes,
          metadata: InputImageMetadata(
            size: Size(width.toDouble(), height.toDouble()),
            rotation: rotation, format: fmt, bytesPerRow: plane.bytesPerRow,
          ),
        );
      }

      if (image.planes.length >= 3) {
        final yPlane = image.planes[0];
        final uPlane = image.planes[1];
        final vPlane = image.planes[2];

        if (yPlane.bytes.length < width * height) return null;
        if (uPlane.bytes.isEmpty || vPlane.bytes.isEmpty) return null;

        final int yRowStride = yPlane.bytesPerRow;
        final int uvRowStride = uPlane.bytesPerRow;
        final int uvPixelStride = uPlane.bytesPerPixel ?? 1;
        if (uvPixelStride == 0) return null;

        final nv21 = Uint8List(width * height * 3 ~/ 2);
        int pos = 0;

        if (yRowStride == width) {
          nv21.setRange(0, width * height, yPlane.bytes);
          pos = width * height;
        } else {
          for (int r = 0; r < height; r++) {
            final int start = r * yRowStride;
            if (start + width > yPlane.bytes.length) break;
            nv21.setRange(pos, pos + width, yPlane.bytes, start);
            pos += width;
          }
        }

        final int uvHeight = height ~/ 2;
        final int uvWidth = width ~/ 2;
        for (int r = 0; r < uvHeight; r++) {
          for (int c = 0; c < uvWidth; c++) {
            final int uvIdx = r * uvRowStride + c * uvPixelStride;
            if (uvIdx >= uPlane.bytes.length || uvIdx >= vPlane.bytes.length) break;
            if (pos + 1 >= nv21.length) break;
            nv21[pos++] = vPlane.bytes[uvIdx];
            nv21[pos++] = uPlane.bytes[uvIdx];
          }
        }

        return InputImage.fromBytes(
          bytes: nv21,
          metadata: InputImageMetadata(
            size: Size(width.toDouble(), height.toDouble()),
            rotation: rotation, format: InputImageFormat.nv21, bytesPerRow: width,
          ),
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _onCameraImage(CameraImage image) async {
    if (!_isScanning || _isProcessing || !mounted) return;
    _isProcessing = true;
    try {
      final inputImage = _buildInputImage(image);
      if (inputImage == null) {
        _isProcessing = false; return;
      }

      final faces = await _faceDetector.processImage(inputImage);
      if (!mounted || !_isScanning) {
        _isProcessing = false; return;
      }

      _facePresent = faces.isNotEmpty;
      if (mounted) setState(() {});

      if (faces.isEmpty) {
        _resetWarning(); _isProcessing = false; return;
      }

      final face = faces.first;
      await _handleVerifyFrame(image, face);
    } catch (_) {}
    _isProcessing = false;
  }

  Future<void> _handleVerifyFrame(CameraImage image, Face face) async {
    final quality = _assessVerifyQuality(face, image);
    if (quality != _FaceWarning.none) {
      _eyesWereClosed = false; _closedFrames = 0; _openFramesAfterClose = 0;
      if (mounted) setState(() => _faceWarning = quality);
      _warningCtrl.repeat(reverse: true); _isProcessing = false; return;
    }

    _warningCtrl.stop(); _warningCtrl.reset();

    final leftOpen = face.leftEyeOpenProbability ?? 1.0;
    final rightOpen = face.rightEyeOpenProbability ?? 1.0;
    final avgOpen = (leftOpen + rightOpen) / 2;
    final smile = face.smilingProbability ?? 0.0;

    if (_livenessStep == _LivenessStep.waitingForFace) {
      _livenessStep = _LivenessStep.blink;
      if (mounted) setState(() => _faceWarning = _FaceWarning.none);
    }

    if (_livenessStep == _LivenessStep.blink && !_blinkDone) {
      if (avgOpen < _blinkClosedThreshold) {
        _closedFrames++; _openFramesAfterClose = 0; _eyesWereClosed = true;
        if (_closedFrames > _maxClosedFramesBeforeStuck) {
          _eyesWereClosed = false; _closedFrames = 0;
          if (mounted) setState(() => _faceWarning = _FaceWarning.eyesClosed);
          _warningCtrl.repeat(reverse: true); _isProcessing = false; return;
        }
      } else if (avgOpen > _blinkOpenThreshold) {
        if (_eyesWereClosed && _closedFrames >= _minClosedFrames) {
          _openFramesAfterClose++;
          if (_openFramesAfterClose >= _minOpenFrames) {
            _blinkDone = true; _eyesWereClosed = false; _closedFrames = 0; _openFramesAfterClose = 0;
            _livenessStep = _LivenessStep.smile;
          }
        }
      } else {
        if (_eyesWereClosed && _closedFrames < _minClosedFrames) {
          _eyesWereClosed = false; _closedFrames = 0;
        }
      }
    } else if (_livenessStep == _LivenessStep.smile && !_smileDone) {
      if (smile > _smileThreshold) {
        _smileDone = true;
        await _camCtrl!.stopImageStream();
        _isScanning = false; _scanLineCtrl.stop();

        // Liveness passed
        await _onSuccess();
        _isProcessing = false; return;
      }
    }

    if (_livenessStartTime != null && !_smileDone) {
      if (DateTime.now().difference(_livenessStartTime!).inMilliseconds > _livenessTimeoutMs) {
        await _camCtrl!.stopImageStream();
        _isScanning = false; _scanLineCtrl.stop();
        if (mounted) _onFailure('Liveness check timed out. Try again.');
        _isProcessing = false; return;
      }
    }

    if (mounted) setState(() => _faceWarning = _FaceWarning.none);
  }

  _FaceWarning _assessVerifyQuality(Face face, CameraImage image) {
    final yaw = face.headEulerAngleY ?? 0.0;
    final roll = face.headEulerAngleZ ?? 0.0;
    final pitch = face.headEulerAngleX ?? 0.0;

    if (yaw.abs() > _verifyMaxYaw || roll.abs() > _verifyMaxRoll || pitch.abs() > _verifyMaxPitch) return _FaceWarning.headAngle;

    final faceArea = (face.boundingBox.width * face.boundingBox.height).toDouble();
    final imageArea = (image.width * image.height).toDouble();
    final areaRatio = faceArea / imageArea;

    if (areaRatio < _verifyMinFaceArea) return _FaceWarning.tooFar;
    if (areaRatio > _verifyMaxFaceArea) return _FaceWarning.tooClose;

    final lmCount = [
      face.landmarks[FaceLandmarkType.noseBase] != null,
      face.landmarks[FaceLandmarkType.leftEye] != null,
      face.landmarks[FaceLandmarkType.rightEye] != null,
    ].where((x) => x).length;
    if (lmCount < 2) return _FaceWarning.occluded;

    if (!kIsWeb && image.planes.isNotEmpty) {
      if (_estimateSharpness(image) < _verifyMinSharpness) return _FaceWarning.blurry;
      final brightness = _estimateBrightness(image);
      if (brightness < 25) return _FaceWarning.tooDark;
      if (brightness > 240) return _FaceWarning.tooBright;
    }
    return _FaceWarning.none;
  }

  double _estimateSharpness(CameraImage image) {
    try {
      final bytes = image.planes.first.bytes;
      final w = image.width;
      final h = image.height;
      if (bytes.length < w * 2 + 2 || w < 5 || h < 5) return 0;

      int sum = 0; double sumSq = 0; int n = 0; const step = 4;
      for (int y = 2; y < h - 2; y += step) {
        for (int x = 2; x < w - 2; x += step) {
          final i = y * w + x;
          if (i - w < 0 || i + w >= bytes.length) continue;
          final lap = (4 * bytes[i] - bytes[i - 1] - bytes[i + 1] - bytes[i - w] - bytes[i + w]).toDouble();
          sum += lap.toInt(); sumSq += lap * lap; n++;
        }
      }
      if (n == 0) return 0;
      final mean = sum / n;
      return (sumSq / n) - (mean * mean);
    } catch (_) { return 0; }
  }

  double _estimateBrightness(CameraImage image) {
    try {
      final bytes = image.planes.first.bytes;
      if (bytes.isEmpty) return 128;
      final step = (bytes.length / 500).ceil().clamp(1, 100);
      int sum = 0; int count = 0;
      for (int i = 0; i < bytes.length; i += step) { sum += bytes[i]; count++; }
      return count == 0 ? 128 : sum / count;
    } catch (_) { return 128; }
  }

  void _resetWarning() {
    _eyesWereClosed = false; _closedFrames = 0; _openFramesAfterClose = 0;
    _warningCtrl.stop(); _warningCtrl.reset();
    if (mounted) setState(() => _faceWarning = _FaceWarning.none);
  }

  void _onLivenessFailed() {
    if (_isDemo || !mounted) return;
    _isScanning = false; _scanLineCtrl.stop();

    if (_isChallenge) {
      unawaited(PresenceChallengeService.instance.recordFailedAttempt(
        widget.challenge!, faceScore: 0.0, reason: 'liveness_failed',
      ));
      unawaited(_logSecurityEvent(
        type: 'presence_challenge_failed', severity: 'high',
        details: 'Challenge ${widget.challenge!.id} FAILED — liveness failed',
      ));
      _cancelRecorded = true;
    }

    const reason = 'Liveness check failed.\nPlease try again in a well-lit area and follow the prompts.';

    setState(() {
      _faceState = _FaceState.error;
      _errorMessage = reason;
    });
    _shakeCtrl.forward(from: 0);

    if (_isChallenge) {
      Future.delayed(const Duration(seconds: 3), () { if (mounted) Navigator.of(context).pop(false); });
      return;
    }

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _faceState == _FaceState.error) {
        setState(() {
          _faceState = _FaceState.idle; _errorMessage = null;
          _faceWarning = _FaceWarning.none;
        });
      }
    });
  }

  Future<bool> _checkRoleAndGeofence() async {
    if (_isDemo) {
      if (mounted) setState(() => _isCheckingGeofence = false);
      return true;
    }

    if (mounted) setState(() => _isCheckingGeofence = true);
    GeofenceService.instance.invalidateCache();

    try {
      GeofenceResult? geoResult;
      try {
        geoResult = await GeofenceService.instance.checkGeofenceForEmployee(employeeId: widget.employee.id).timeout(const Duration(seconds: 20));
      } catch (_) {}

      final isAllowed = geoResult?.isAllowed ?? false;
      final isExempted = geoResult?.isExempted ?? false;

      if (isAllowed || isExempted) {
        _geofenceVerifiedOffline = false;
        if (mounted) setState(() => _isCheckingGeofence = false);
        return true;
      }

      if (_isOffline && geoResult == null) {
        _geofenceVerifiedOffline = true;
        if (mounted) setState(() => _isCheckingGeofence = false);
        return true;
      }

      if (geoResult == null) {
        if (mounted) {
          setState(() {
            _faceState = _FaceState.error;
            _errorMessage = 'Unable to verify location.\nPlease try again.';
            _isCheckingGeofence = false;
          });
          _shakeCtrl.forward(from: 0);
        }
        return false;
      }

      final dist = geoResult.distanceMeters;
      final radius = geoResult.radiusUsed;
      final nearest = geoResult.matchedLocationName ?? 'Unknown';

      if (mounted) {
        setState(() {
          _faceState = _FaceState.error;
          _errorMessage = '📍 Outside work zone\nNearest: $nearest\nDistance: ${dist?.toStringAsFixed(0) ?? "?"}m (allowed: ${radius?.toStringAsFixed(0) ?? "?"}m)';
          _isCheckingGeofence = false;
        });
        _shakeCtrl.forward(from: 0);
      }
      return false;
    } catch (_) {
      if (mounted) setState(() => _isCheckingGeofence = false);
      if (_isOffline) { _geofenceVerifiedOffline = true; return true; }
      return false;
    }
  }

  String get _employeeIdForAttendance {
    if (_isDemo) return DemoModeService.demoEmployee.employeeId;
    final empId = widget.employee.employeeId;
    if (empId.isNotEmpty) return empId;
    return widget.employee.id;
  }

  String _computeZoneType() {
    if (_isDemo) return 'inside';
    final role = widget.employee.position.toLowerCase();
    final dept = widget.employee.department.toLowerCase();
    if (role.contains('driver') || role.contains('rider') || dept.contains('driver') || dept.contains('rider')) return 'driver';
    if (widget.employee.wfhAccess) return 'wfh';
    return 'inside';
  }

  Future<bool> _hasClockedInToday(String employeeId) async {
    try {
      final now = DateTime.now();
      final todayStr = now.toIso8601String().substring(0, 10);
      final prefs = await SharedPreferences.getInstance();
      final lastClockIn = prefs.getString('last_clock_in_date_$employeeId');

      if (lastClockIn == todayStr) return true;
      if (!NetworkGuard.instance.isOnline) return false;

      final q = await FirebaseFirestore.instance.collection('attendance_logs')
          .where('employee_id', isEqualTo: employeeId)
          .where('date', isEqualTo: todayStr)
          .where('type', isEqualTo: 'IN')
          .limit(1)
          .get().timeout(const Duration(seconds: 5));

      if (q.docs.isNotEmpty) {
        await prefs.setString('last_clock_in_date_$employeeId', todayStr);
        return true;
      }
      return false;
    } catch (_) { return false; }
  }

  Future<void> _onAttendanceTypeDetermined({required bool isClockIn, required String employeeId, required String employeeName}) async {
    if (_isDemo) return;
    try {
      if (isClockIn) {
        try { await OvertimeReminderService.instance.scheduleForEmployee(employeeId: employeeId, maxOvertimeHours: 6); } catch (_) {}
        try {
          await TrustedTimeService.instance.syncWithServer(force: true);
          if (TrustedTimeService.instance.isTampered) {
            await TrustedTimeService.instance.logTamperEvent(employeeId: employeeId, employeeName: employeeName, context: 'clock_in_liveness');
          }
        } catch (_) {}
      } else {
        try { await OvertimeReminderService.instance.cancelAll(); } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> _writeAttendanceLog() async {
    if (_isDemo) return;
    try {
      final employeeId = _employeeIdForAttendance;
      if (employeeId.isEmpty) return;

      final alreadyClockedIn = await ClockStatusService.instance.isCurrentlyClockedIn(employeeId);
      final attendanceType = alreadyClockedIn ? 'OUT' : 'IN';
      final isClockIn = attendanceType == 'IN';

      final now = DateTime.now();
      final effectiveTime = _effectiveAttendanceTime;
      final todayStr = effectiveTime.toIso8601String().substring(0, 10);
      final timeStr = '${effectiveTime.hour.toString().padLeft(2, '0')}:${effectiveTime.minute.toString().padLeft(2, '0')}:${effectiveTime.second.toString().padLeft(2, '0')}';
      final delayMinutes = now.difference(effectiveTime).inMinutes;

      if (attendanceType == 'IN') {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('last_clock_in_date_$employeeId', todayStr);
        } catch (_) {}
      }

      final employeeName = widget.employee.fullName;
      final employeeEmail = widget.employee.email;
      final deviceName = _deviceModel;
      final zoneType = _computeZoneType();

      final baseRemarks = _geofenceVerifiedOffline ? 'liveness:passed|pending_geofence_verification' : 'liveness:passed';
      final remarks = delayMinutes >= 1 ? '$baseRemarks|first_attempt_delay:${delayMinutes}m' : baseRemarks;

      await _onAttendanceTypeDetermined(isClockIn: isClockIn, employeeId: employeeId, employeeName: employeeName);

      AttendanceResult? offlineResult;
      try {
        offlineResult = await OfflineAttendanceService.instance.logAttendance(
          employeeId: employeeId, employeeName: employeeName, employeeEmail: employeeEmail,
          type: attendanceType, timestamp: effectiveTime, device: deviceName, remarks: remarks, zoneType: zoneType,
        );
      } catch (e) {
        await _logSecurityEvent(type: 'attendance_local_save_failed', severity: 'critical', details: 'Failed to save attendance locally: $e');
      }

      final needsDirectWrite = offlineResult != null && !offlineResult.queued && NetworkGuard.instance.isOnline;
      if (!needsDirectWrite) { await _emitPendingCount(); return; }

      final attendancePayload = <String, dynamic>{
        'employee_id': employeeId, 'employee_name': employeeName, 'employee_email': employeeEmail,
        'type': attendanceType, 'date': todayStr, 'time': timeStr, 'timestamp': FieldValue.serverTimestamp(),
        'first_attempt_at': Timestamp.fromDate(effectiveTime), 'success_at': Timestamp.fromDate(now),
        'attempt_delay_minutes': delayMinutes, 'device': deviceName, 'device_binding': _deviceBinding,
        'zone_type': zoneType, 'liveness_passed': true,
        'session_nonce': _sessionNonce, 'device_compromised': _deviceCompromised,
        'remarks': remarks, if (_geofenceVerifiedOffline) 'pending_geofence_verification': true,
      };

      try {
        await _executeWithLoadBalancer(() => FirebaseFirestore.instance.collection('attendance_logs').add(attendancePayload));
      } catch (_) {}

      final activityPayload = <String, dynamic>{
        'type': isClockIn ? 'clock_in' : 'clock_out', 'action': isClockIn ? 'Clocked In (Liveness)' : 'Clocked Out (Liveness)',
        'employeeId': widget.employee.id, 'employee_id': employeeId, 'employee_name': employeeName,
        'email': employeeEmail, 'liveness_passed': true,
        'zone_type': zoneType, 'time': timeStr, 'date': todayStr,
        'first_attempt_at': Timestamp.fromDate(effectiveTime), 'success_at': Timestamp.fromDate(now),
        'attempt_delay_minutes': delayMinutes, 'device': deviceName, 'device_binding': _deviceBinding,
        'device_compromised': _deviceCompromised, 'platform': kIsWeb ? 'web' : 'mobile',
        'session_nonce': _sessionNonce, 'timestamp': FieldValue.serverTimestamp(),
        if (_geofenceVerifiedOffline) 'pending_geofence_verification': true,
      };

      try {
        await _executeWithLoadBalancer(() => FirebaseFirestore.instance.collection('activity_logs').add(activityPayload));
      } catch (_) {
        try { await OfflineAttendanceService.instance.enqueue(collection: 'activity_logs', data: activityPayload); } catch (_) {}
      }

      if (isClockIn) {
        try {
          unawaited(PresenceChallengeService.instance.scheduleForToday(employeeId: employeeId, clockInAt: effectiveTime, employeeName: employeeName));
        } catch (_) {}
      }

      try {
        if (isClockIn) {
          AdminNotificationService.instance.notifyClockIn(employeeId: employeeId, employeeName: employeeName, timeStr: timeStr, faceMatchPercent: null, wfh: widget.employee.wfhAccess, inRange: true, zoneType: zoneType);
        } else {
          AdminNotificationService.instance.notifyClockOut(employeeId: employeeId, employeeName: employeeName, timeStr: timeStr, faceMatchPercent: null, wfh: widget.employee.wfhAccess, inRange: true, zoneType: zoneType);
        }
      } catch (_) {}
    } catch (_) {}
  }

  Future<void> _onSuccess() async {
    if (!mounted) return;
    setState(() { _faceState = _FaceState.success; _errorMessage = null; });
    _pulseCtrl.stop(); _ringCtrl.stop(); _successCtrl.forward();

    if (_isChallenge) { await _finishChallenge(); return; }

    final canProceed = await _checkRoleAndGeofence();
    if (!canProceed) return;

    final employeeId = _employeeIdForAttendance;
    final alreadyClockedIn = await ClockStatusService.instance.isCurrentlyClockedIn(employeeId);

    if (!alreadyClockedIn) {
      final hasClockedInToday = await _hasClockedInToday(employeeId);
      if (hasClockedInToday) {
        if (mounted) {
          setState(() { _faceState = _FaceState.error; _errorMessage = 'You have already clocked in today.\nOnly one clock-in is allowed per day.'; });
          _shakeCtrl.forward(from: 0); _successCtrl.reset(); _pulseCtrl.repeat(reverse: true); _ringCtrl.repeat();
        }
        return;
      }
    }

    await _writeAttendanceLog();
    await Future.delayed(const Duration(milliseconds: 2000));
    if (!mounted) return;

    if (_isDemo && !_isOnlineSafely()) {
      _showOfflineSnack('No internet connection. Internet is required to continue.');
      setState(() { _faceState = _FaceState.idle; _errorMessage = null; });
      _successCtrl.reset(); _pulseCtrl.repeat(reverse: true); _ringCtrl.repeat();
      return;
    }
    _proceedToNext();
  }

  Future<void> _finishChallenge() async {
    if (_isDemo) {
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      if (!_isOnlineSafely()) { _showOfflineSnack('No internet connection. Internet is required to continue.'); return; }
      Navigator.of(context).pop(true);
      return;
    }

    if (!mounted) return;
    final ch = widget.challenge!;
    _cancelRecorded = true;

    final canProceed = await _checkRoleAndGeofence();
    if (!canProceed) {
      unawaited(PresenceChallengeService.instance.recordFailedAttempt(ch, faceScore: 0.0, reason: 'geofence_failed_at_verify'));
      await _logSecurityEvent(type: 'challenge_failed_geofence', severity: 'high', details: 'Challenge ${ch.id} FAILED — outside work zone at verification');
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      Navigator.of(context).pop(false);
      return;
    }

    final zone = _computeZoneType();
    if (!NetworkGuard.instance.isOnline) {
      try {
        await OfflineAttendanceService.instance.enqueue(
          collection: 'presence_challenges', docId: ch.id,
          data: {
            'id': ch.id, 'employeeId': widget.employee.id, 'status': 'passed',
            'liveness_passed': true, 'zone': zone, 'deviceBinding': _deviceBinding,
            'verifiedAt': DateTime.now(), 'verificationMode': 'offline',
          },
        );
      } catch (_) {}
    } else {
      try {
        await PresenceChallengeService.instance.submitPassed(ch, faceScore: 0.0, zone: zone, deviceBinding: _deviceBinding);
      } catch (_) {}
    }

    await _logSecurityEvent(type: 'challenge_passed', severity: 'info', details: 'Random face check passed (liveness)');
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  void _proceedToNext() {
    if (!mounted) return;
    final navigator = Navigator.of(context);
    navigator.pushReplacement(
      MaterialPageRoute(
        builder: (_) => ClockInSuccessScreen(
          employee: widget.employee,
          arrivalTime: _effectiveAttendanceTime,
          faceMatchPercent: 100.0,
          verificationMethod: 'liveness_check',
          onContinue: () {
            navigator.pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => MainScreen(employee: widget.employee)),
                  (route) => false,
            );
          },
        ),
      ),
    );
  }

  void _onFailure(String msg) {
    if (!mounted) return;
    _isScanning = false; _scanLineCtrl.stop();
    setState(() { _faceState = _FaceState.error; _errorMessage = msg; });
    _shakeCtrl.forward(from: 0);

    unawaited(_logSecurityEvent(type: 'liveness_auth_failed', severity: 'medium', details: msg));

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _faceState == _FaceState.error) {
        setState(() { _faceState = _FaceState.idle; _errorMessage = null; });
      }
    });
  }

  Future<void> _stopAllCameraOperations() async {
    _isScanning = false; _isProcessing = false;
    try {
      if (_camCtrl?.value.isStreamingImages == true) await _camCtrl!.stopImageStream();
    } catch (_) {}
    _scanLineCtrl.stop(); _warningCtrl.stop(); _pulseCtrl.stop(); _ringCtrl.stop();
  }

  Future<void> _goBack() async {
    await _stopAllCameraOperations();
    if (_isChallenge && !_cancelRecorded && !_isDemo) await _recordChallengeFailure('user_tapped_back');
    _resetFirstAttempt();
    if (!mounted) return;

    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(false);
    } else {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => MainScreen(employee: widget.employee)));
    }
  }

  Future<void> _onCancelTapped() async {
    await _stopAllCameraOperations();
    if (_isChallenge && !_cancelRecorded && !_isDemo) await _recordChallengeFailure('user_tapped_cancel');
    _resetFirstAttempt();
    if (!mounted) return;

    setState(() => _cancelPressed = true);
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    setState(() => _cancelPressed = false);
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;

    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(false);
    } else {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => MainScreen(employee: widget.employee)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = _ThemeColors(isDark);

    if (_isInitialLoading) {
      return Scaffold(backgroundColor: tc.bgTop, body: SafeArea(child: Stack(children: [const DashboardSkeleton(), if (_obscureContent) _buildPrivacyShield()])));
    }

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A0A0A) : const Color(0xFF121212),
      body: SafeArea(
        top: false, bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final screenWidth = constraints.maxWidth;
            final contentWidth = screenWidth < 420 ? screenWidth : 375.0;
            return Center(
              child: SizedBox(
                width: contentWidth, height: constraints.maxHeight,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(screenWidth <= 420 ? 0 : 40),
                  child: FadeTransition(
                    opacity: _fadeAnim,
                    child: Stack(
                      children: [
                        Positioned.fill(child: Container(color: tc.bg)),
                        _buildHeader(),
                        Positioned(top: 205, left: 16, right: 16, child: _buildOuterCard(tc)),
                        if (_pendingCount > 0 && !_isDemo) _buildPendingBadge(),
                        if (_obscureContent) _buildPrivacyShield(),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPendingBadge() {
    return Positioned(
      top: 12, right: 12,
      child: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: Colors.orange.shade700, borderRadius: BorderRadius.circular(20)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.6, valueColor: AlwaysStoppedAnimation(Colors.white))),
              const SizedBox(width: 6),
              Text('$_pendingCount pending', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPrivacyShield() {
    return Positioned.fill(
      child: AbsorbPointer(
        absorbing: true,
        child: Container(
          color: const Color(0xFF0C0C0E), alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 64, height: 64, decoration: BoxDecoration(color: _orange, borderRadius: BorderRadius.circular(20)), alignment: Alignment.center, child: const Icon(Icons.lock_outline_rounded, color: Colors.black, size: 32)),
              const SizedBox(height: 16),
              const Text('R.A.C.O.M.A.', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18, letterSpacing: 1.2)),
              const SizedBox(height: 6),
              Text('Session hidden for your privacy', style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity, height: 287.13,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: _isDemo ? [_demoAccent, _demoAccentMid, _demoAccentDark] : const [Color(0xFFFF8A00), Color(0xFFFF6B00), Color(0xFFF54900)],
          stops: const [0.0001, 0.3318, 1.0],
        ),
        borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 24, top: 48,
            child: GestureDetector(
              onTap: _goBack, behavior: HitTestBehavior.opaque,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chevron_left_rounded, color: Colors.white, size: 22),
                  SizedBox(width: 2),
                  Text('Back', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ),
          Positioned(
            left: 24, top: 95.99,
            child: Text(
              _isDemo ? 'Demo Check' : (_isChallenge ? 'Random Check' : 'Liveness & Clock In'),
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: Colors.white, height: 0.9),
            ),
          ),
          Positioned(
            left: 24, top: 136.99,
            child: Text(
              _isDemo ? 'Real camera + liveness — always pass' : (_isChallenge ? 'Presence verification required' : 'Liveness verification'),
              style: const TextStyle(fontSize: 14, color: Colors.white, height: 0.9),
            ),
          ),
          if (_isDemo)
            Positioned(
              right: 24, top: 48,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(12)),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.science_rounded, color: Colors.white, size: 12),
                        SizedBox(width: 5),
                        Text('DEMO', style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                      ],
                    ),
                  ),
                  if (_isOffline) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: _error.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(12)),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cloud_off_rounded, color: Colors.white, size: 11),
                          SizedBox(width: 4),
                          Text('OFFLINE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            )
          else if (_isOffline)
            Positioned(
              right: 24, top: 48,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(12)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_rounded, color: Colors.white, size: 12),
                    const SizedBox(width: 5),
                    Text(
                      _pendingCount > 0 ? 'Offline · $_pendingCount pending' : 'Offline mode',
                      style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOuterCard(_ThemeColors tc) {
    return Container(
      decoration: BoxDecoration(
        color: tc.outerCardBg,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      padding: const EdgeInsets.fromLTRB(0, 18, 0, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _isDemo ? 'Demo Mode' : (_isChallenge ? 'Presence Check' : 'Step 3: Face Liveness'),
            textAlign: TextAlign.center,
            style: TextStyle(color: _isDemo ? _demoAccent : tc.stepLabelColor, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5),
          ),
          const SizedBox(height: 12),
          _buildModalCard(tc),
        ],
      ),
    );
  }

  Widget _buildModalCard(_ThemeColors tc) {
    final isScanning = _faceState == _FaceState.scanning;
    final isSuccess = _faceState == _FaceState.success;
    final isBusy = isScanning;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: _isDemo ? [_demoAccent, _demoAccentDark] : const [Color(0xFFFF8C2B), Color(0xFFF05000)],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [BoxShadow(color: (_isDemo ? _demoAccent : const Color(0xFFF05000)).withValues(alpha: 0.35), blurRadius: 30, offset: const Offset(0, 12))],
      ),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: _cameraBoxSize, height: _cameraBoxSize,
            child: Center(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: (!isBusy && !isSuccess && !_isCheckingGeofence) ? _startScan : null,
                child: isSuccess ? _buildVerifiedBadgeWithScore() : isScanning ? _buildCameraPreview() : _buildFaceIconBox(),
              ),
            ),
          ),
          if (isScanning) ...[
            const SizedBox(height: 16),
            _buildScanProgressBar(),
          ],
          const SizedBox(height: 20),
          if (isSuccess) ...[
            _buildLivenessVerifiedBadge(),
            const SizedBox(height: 14),
          ],
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              _stateTitle.replaceAll('\n', ' '),
              key: ValueKey('title_${_faceState}-$_isDemo'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: _white, fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              _errorMessage ?? _stateSubtitle.replaceAll('\n', ' '),
              key: ValueKey('subtitle_${_errorMessage ?? _faceState}_${_networkState.name}_$_pendingCount-$_isDemo'),
              textAlign: TextAlign.center,
              style: TextStyle(color: _white.withValues(alpha: 0.9), fontSize: 12, height: 1.4),
            ),
          ),
          if (_isCheckingGeofence) ...[
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
              const SizedBox(width: 8),
              Text('Verifying location...', style: TextStyle(color: _white.withValues(alpha: 0.9), fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
          ],
          if (_camError != null && _faceState == _FaceState.idle && !_isDemo) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(6)),
              child: Text('⚠️ $_camError', textAlign: TextAlign.center, style: const TextStyle(color: _warning, fontSize: 10)),
            ),
          ],
          if (_isOffline && _pendingCount > 0 && !_isDemo) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_upload_outlined, color: Colors.white, size: 13),
                  const SizedBox(width: 6),
                  Text('$_pendingCount queued for sync', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          _buildCancelButton(tc),
          if (!_isDemo) ...[
            const SizedBox(height: 8),
            _buildContactAdminLink(),
          ],
        ],
      ),
    );
  }

  Widget _buildContactAdminLink() {
    final isError = _faceState == _FaceState.error;
    return GestureDetector(
      onTap: _sendingAdminReport ? null : _openContactAdminSheet,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isError ? _white.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: isError ? Border.all(color: _white.withValues(alpha: 0.4), width: 1) : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.support_agent_rounded, color: isError ? _white : _white.withValues(alpha: 0.72), size: 15),
            const SizedBox(width: 6),
            Text(
              isError ? 'Liveness issue? Contact Admin' : 'Having trouble? Contact Admin',
              style: TextStyle(color: isError ? _white : _white.withValues(alpha: 0.72), fontSize: 12, fontWeight: isError ? FontWeight.w700 : FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLivenessVerifiedBadge() {
    final color = _isDemo ? _demoAccent : _verifiedGreen;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.7), width: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'LIVENESS VERIFIED',
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1.2),
          ),
          const SizedBox(height: 2),
          const Text(
            'Face is live',
            style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildFaceIconBox() {
    return SizedBox(
      width: 75, height: 75,
      child: AnimatedBuilder(
        animation: Listenable.merge([_pulseAnim, _successAnim, _shakeAnim]),
        builder: (_, __) {
          final isError = _faceState == _FaceState.error;
          return Transform.scale(
            scale: _pulseAnim.value,
            child: Container(
              width: 75, height: 75,
              decoration: BoxDecoration(color: _white, borderRadius: BorderRadius.circular(18)),
              child: Center(
                child: CustomPaint(
                  size: const Size(36, 36),
                  painter: _FaceScanIconPainter(color: isError ? _error : (_isDemo ? _demoAccent : _orange)),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildVerifiedBadgeWithScore() {
    return AnimatedBuilder(
      animation: _successAnim,
      builder: (_, __) => Transform.scale(
        scale: _successAnim.value,
        child: SizedBox(
          width: 140, height: 140,
          child: CustomPaint(painter: _VerifiedBadgePainter(color: _isDemo ? _demoAccent : _verifiedGreen)),
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    final faceDetected = _facePresent;
    final hasWarning = _faceWarning != _FaceWarning.none;
    final borderColor = hasWarning ? _warning : (faceDetected ? _faceGreen : _orange);
    final bool hasRealCamera = _camCtrl != null && _camCtrl!.value.isInitialized && _camCtrl!.value.previewSize != null;

    return AnimatedBuilder(
      animation: Listenable.merge([_ringAnim, _scanLineAnim, _warningAnim, _flashAnim]),
      builder: (_, __) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: _cameraBoxSize, height: _cameraBoxSize,
            child: Stack(
              alignment: Alignment.center, fit: StackFit.expand,
              children: [
                if (hasRealCamera)
                  FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: _camCtrl!.value.previewSize!.height,
                      height: _camCtrl!.value.previewSize!.width,
                      child: CameraPreview(_camCtrl!),
                    ),
                  )
                else if (kIsWeb)
                  Container(color: Colors.black)
                else
                  Container(color: Colors.black, child: const Center(child: CircularProgressIndicator(color: Colors.orange, strokeWidth: 2))),
                Positioned.fill(
                  child: Align(
                    alignment: Alignment(0, (_scanLineAnim.value * 2) - 1),
                    child: Container(
                      height: 2,
                      decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.transparent, borderColor, Colors.transparent])),
                    ),
                  ),
                ),
                Positioned.fill(child: CustomPaint(painter: _FaceBracketPainter(color: borderColor))),
                Positioned(
                  top: 6, right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(20)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 5, height: 5, decoration: BoxDecoration(color: borderColor, shape: BoxShape.circle)),
                        const SizedBox(width: 4),
                        Text(_statusBadgeText, style: const TextStyle(color: _white, fontSize: 7.5, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
                      ],
                    ),
                  ),
                ),
                if (hasWarning)
                  Positioned(
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.72), borderRadius: BorderRadius.circular(20)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: _warning, size: 11),
                          const SizedBox(width: 4),
                          Text(_warningHintText, style: const TextStyle(color: _warning, fontSize: 8, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  )
                else if (faceDetected)
                  Positioned(
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(20)),
                      child: Text(
                        _livenessHint,
                        style: const TextStyle(color: _faceGreen, fontSize: 8, fontWeight: FontWeight.w700),
                      ),
                    ),
                  )
                else
                  Positioned(
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(20)),
                      child: Text('Center your face', style: TextStyle(color: _white.withValues(alpha: 0.75), fontSize: 8, fontWeight: FontWeight.w600)),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCancelButton(_ThemeColors tc) {
    return GestureDetector(
      onTap: _onCancelTapped,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(color: _cancelPressed ? tc.cancelPressed : tc.cancelBg, borderRadius: BorderRadius.circular(12)),
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(color: _isDemo ? _demoAccent : tc.cancelText, fontSize: 14, fontWeight: FontWeight.w600),
            child: Text(
              _isDemo ? 'Exit Demo' : (_isChallenge ? 'Cancel Verification' : 'Cancel Authentication'),
            ),
          ),
        ),
      ),
    );
  }

  double get _scanProgress {
    if (_faceState == _FaceState.success) return 1.0;
    if (!_facePresent) return 0.1;
    if (_faceWarning != _FaceWarning.none) return 0.25;
    if (_blinkDone && _smileDone) return 0.95;
    if (_blinkDone) return 0.7;
    return 0.5;
  }

  Color get _scanProgressColor {
    if (_smileDone && _blinkDone) return _success;
    if (_faceWarning != _FaceWarning.none) return _warning;
    if (_facePresent) return _faceGreen;
    return _white.withValues(alpha: 0.5);
  }

  String get _scanProgressLabel {
    if (_smileDone && _blinkDone) return 'Verifying...';
    if (_faceWarning != _FaceWarning.none) return 'Fix issue';
    if (_blinkDone && !_smileDone) return 'Step 2: Smile 😊';
    if (_facePresent) return 'Step 1: Blink your eyes 👁️';
    return 'Looking for face';
  }

  Widget _buildScanProgressBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Container(
            height: 8, width: double.infinity,
            color: Colors.black.withValues(alpha: 0.22),
            child: LayoutBuilder(builder: (context, constraints) {
              return Align(
                alignment: Alignment.centerLeft,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: constraints.maxWidth * _scanProgress, height: 8,
                  decoration: BoxDecoration(color: _scanProgressColor, borderRadius: BorderRadius.circular(20)),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 6),
        Text(_scanProgressLabel, style: TextStyle(color: _white.withValues(alpha: 0.85), fontSize: 11, fontWeight: FontWeight.w600)),
      ],
    );
  }

  String get _statusBadgeText {
    if (_faceState == _FaceState.success) {
      return 'VERIFIED ✓';
    }
    if (_smileDone && _blinkDone) return 'VERIFYING';
    if (_facePresent) return 'FACE FOUND';
    return 'SCANNING';
  }

  String get _warningHintText {
    switch (_faceWarning) {
      case _FaceWarning.faceMask: return 'Remove face mask';
      case _FaceWarning.occluded: return 'Remove obstruction from face';
      case _FaceWarning.headAngle: return 'Look straight at the camera';
      case _FaceWarning.eyesClosed: return 'Open your eyes';
      case _FaceWarning.blurry: return 'Blurry — stop and hold steady';
      case _FaceWarning.tooDark: return 'Too dark — move to a brighter area';
      case _FaceWarning.tooBright: return 'Too bright — avoid direct light';
      case _FaceWarning.tooFar: return 'Move closer to the camera';
      case _FaceWarning.tooClose: return 'Move slightly away from the camera';
      case _FaceWarning.none: return '';
    }
  }

  String get _livenessHint {
    if (_blinkDone && !_smileDone) return 'Now smile 😊';
    if (_blinkDone && _smileDone) return 'Verifying...';
    return 'Blink your eyes 👁️';
  }

  String get _stateTitle {
    if (_isCheckingGeofence) return 'Verifying\nLocation...';

    switch (_faceState) {
      case _FaceState.idle: return _isChallenge ? 'Presence\nCheck' : 'Liveness\nCheck';
      case _FaceState.scanning:
        if (_smileDone && _blinkDone) return 'Verifying\nLiveness...';
        if (_facePresent) return _faceWarning != _FaceWarning.none ? 'Quality\nCheck Failed' : 'Liveness\nCheck';
        return 'Scanning\nFace...';
      case _FaceState.success: return 'Verified!';
      case _FaceState.error: return 'Try Again';
      case _FaceState.enrolling: return 'Liveness\nCheck'; // Unused but required by enum
    }
  }

  String get _stateSubtitle {
    if (_isCheckingGeofence) return 'Checking your role and location...';

    if (_isDemo && _isOffline) {
      switch (_faceState) {
        case _FaceState.idle: return '📴 No internet connection. Internet is required to use Demo account.';
        case _FaceState.scanning: return 'Checking internet connection...';
        case _FaceState.success: return 'Demo verification complete. Proceeding to Clock-In...';
        case _FaceState.error: return 'No internet. Please connect to the network.';
        case _FaceState.enrolling: return 'No internet. Please connect to the network.';
      }
    }

    switch (_faceState) {
      case _FaceState.idle:
        if (_isOffline) return '📴 Offline mode — tap to scan.\nAttendance will be saved locally\nand synced automatically when online.';
        return _isChallenge ? 'Tap to start random verification' : 'Tap the camera icon to start\nliveness check';
      case _FaceState.scanning:
        if (_smileDone && _blinkDone) return 'Checking liveness...';
        if (_facePresent) {
          if (_faceWarning != _FaceWarning.none) return _warningHintText;
          if (!_blinkDone) return 'Step 1 of 2: Blink your eyes 👁️';
          if (!_smileDone) return 'Step 2 of 2: Smile for the camera 😊';
        }
        return 'Center your face in the frame';
      case _FaceState.success: return 'Liveness confirmed.${_isChallenge ? " Returning..." : " Proceeding..."}';
      case _FaceState.error: return 'Liveness check failed.\nTap to try again.';
      case _FaceState.enrolling: return 'Tap the camera icon to start\nliveness check';
    }
  }
}

// ═══════════════════════════════════════════════════════════════
// ENUMS
// ═══════════════════════════════════════════════════════════════
enum _FaceState { idle, scanning, success, error, enrolling }
enum _FaceWarning { none, blurry, faceMask, occluded, headAngle, eyesClosed, tooFar, tooClose, tooDark, tooBright }
enum _LivenessStep { waitingForFace, blink, smile }

// ═══════════════════════════════════════════════════════════════
// PAINTERS
// ═══════════════════════════════════════════════════════════════
class _FaceScanIconPainter extends CustomPainter {
  final Color color;
  const _FaceScanIconPainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    Offset p(double x, double y) => Offset(x * s, y * s);
    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(Path()..moveTo(p(3, 7).dx, p(3, 7).dy)..lineTo(p(3, 5).dx, p(3, 5).dy)..arcToPoint(p(5, 3), radius: Radius.circular(2 * s), clockwise: true)..lineTo(p(7, 3).dx, p(7, 3).dy), strokePaint);
    canvas.drawPath(Path()..moveTo(p(17, 3).dx, p(17, 3).dy)..lineTo(p(19, 3).dx, p(19, 3).dy)..arcToPoint(p(21, 5), radius: Radius.circular(2 * s), clockwise: true)..lineTo(p(21, 7).dx, p(21, 7).dy), strokePaint);
    canvas.drawPath(Path()..moveTo(p(21, 17).dx, p(21, 17).dy)..lineTo(p(21, 19).dx, p(21, 19).dy)..arcToPoint(p(19, 21), radius: Radius.circular(2 * s), clockwise: true)..lineTo(p(17, 21).dx, p(17, 21).dy), strokePaint);
    canvas.drawPath(Path()..moveTo(p(7, 21).dx, p(7, 21).dy)..lineTo(p(5, 21).dx, p(5, 21).dy)..arcToPoint(p(3, 19), radius: Radius.circular(2 * s), clockwise: true)..lineTo(p(3, 17).dx, p(3, 17).dy), strokePaint);
    final dotPaint = Paint()..color = color..style = PaintingStyle.fill;
    canvas.drawCircle(p(9, 9), 1.1 * s, dotPaint);
    canvas.drawCircle(p(15, 9), 1.1 * s, dotPaint);
    canvas.drawPath(Path()..moveTo(p(9, 13).dx, p(9, 13).dy)..cubicTo(p(9.5, 13.8).dx, p(9.5, 13.8).dy, p(10.5, 14.5).dx, p(10.5, 14.5).dy, p(12, 14.5).dx, p(12, 14.5).dy)..cubicTo(p(13.5, 14.5).dx, p(13.5, 14.5).dy, p(14.5, 13.8).dx, p(14.5, 13.8).dy, p(15, 13).dx, p(15, 13).dy), strokePaint);
  }
  @override
  bool shouldRepaint(_FaceScanIconPainter old) => old.color != color;
}

class _FaceBracketPainter extends CustomPainter {
  final Color color;
  const _FaceBracketPainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final margin = size.width * 0.06;
    final r = size.width * 0.08;
    final len = size.width * 0.15;
    canvas.drawLine(Offset(margin + r, margin), Offset(margin + r + len, margin), paint);
    canvas.drawArc(Rect.fromLTWH(margin, margin, r * 2, r * 2), math.pi, math.pi / 2, false, paint);
    canvas.drawLine(Offset(margin, margin + r), Offset(margin, margin + r + len), paint);
    final xr = size.width - margin;
    canvas.drawLine(Offset(xr - r, margin), Offset(xr - r - len, margin), paint);
    canvas.drawArc(Rect.fromLTWH(xr - r * 2, margin, r * 2, r * 2), -math.pi / 2, math.pi / 2, false, paint);
    canvas.drawLine(Offset(xr, margin + r), Offset(xr, margin + r + len), paint);
    final yb = size.height - margin;
    canvas.drawLine(Offset(margin + r, yb), Offset(margin + r + len, yb), paint);
    canvas.drawArc(Rect.fromLTWH(margin, yb - r * 2, r * 2, r * 2), math.pi / 2, math.pi / 2, false, paint);
    canvas.drawLine(Offset(margin, yb - r), Offset(margin, yb - r - len), paint);
    canvas.drawLine(Offset(xr - r, yb), Offset(xr - r - len, yb), paint);
    canvas.drawArc(Rect.fromLTWH(xr - r * 2, yb - r * 2, r * 2, r * 2), 0, math.pi / 2, false, paint);
    canvas.drawLine(Offset(xr, yb - r), Offset(xr, yb - r - len), paint);
  }
  @override
  bool shouldRepaint(covariant _FaceBracketPainter old) => old.color != color;
}

class _VerifiedBadgePainter extends CustomPainter {
  final Color color;
  const _VerifiedBadgePainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 112;
    final frameRect = Rect.fromLTRB(1.5 * s, 1.5 * s, 110.496 * s, 110.496 * s);
    final rrect = RRect.fromRectAndRadius(frameRect, Radius.circular(14.5 * s));
    canvas.drawRRect(rrect, Paint()..color = Colors.white);
    canvas.drawRRect(rrect, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 3 * s);
    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4 * s
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(Offset(55.989 * s, 55.989 * s), 19.998 * s, strokePaint);
    canvas.drawPath(Path()..moveTo(49.9897 * s, 55.9889 * s)..lineTo(53.9894 * s, 59.9886 * s)..lineTo(61.9887 * s, 51.9893 * s), strokePaint);
  }
  @override
  bool shouldRepaint(covariant _VerifiedBadgePainter old) => old.color != color;
}