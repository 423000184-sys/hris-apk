// lib/screens/clock_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
<<<<<<< HEAD
=======
import 'package:local_auth/local_auth.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:image_picker/image_picker.dart';
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
import '../theme/app_theme.dart';
import '../services/database_service.dart';
import '../services/security_service.dart';
import '../services/geofence_service.dart';
import '../models/attendance.dart';
import '../models/employee.dart';

<<<<<<< HEAD
class _MockColors {
  static const Color darkBorder = Color(0xFF27272A);
  static const Color orangeBorder = Color(0xFFFFA500);
  static const Color lime = Color(0xFFC4FF0A);
  static const Color red = Color(0xFFFF0000);
  static const Color translucentGray = Color.fromRGBO(131, 131, 131, 0.28);
}

class ClockScreen extends StatefulWidget {
  final Employee? initialEmployee;
  final VoidCallback? onBack;
  final VoidCallback? onContinue;

  const ClockScreen({
    super.key,
    this.initialEmployee,
    this.onBack,
    this.onContinue,
  });
=======
class ClockScreen extends StatefulWidget {
  final Employee? initialEmployee;
  const ClockScreen({super.key, this.initialEmployee});
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1

  @override
  State<ClockScreen> createState() => _ClockScreenState();
}

class _ClockScreenState extends State<ClockScreen> with TickerProviderStateMixin {
<<<<<<< HEAD
  late AnimationController _successCtrl;
  late AnimationController _glowCtrl;
  late AnimationController _fadeCtrl;
  late Animation<double> _successAnim;
  late Animation<double> _glowAnim;
  late Animation<double> _fadeAnim;

  Employee? _employee;
=======

  late AnimationController _pulseCtrl;
  late AnimationController _successCtrl;
  late AnimationController _glowCtrl;
  late AnimationController _fadeCtrl;
  late Animation<double>   _pulseAnim;
  late Animation<double>   _successAnim;
  late Animation<double>   _glowAnim;
  late Animation<double>   _fadeAnim;

  Employee?   _employee;
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
  Attendance? _lastRecord;

  String? _webTimeIn;
  String? _webTimeOut;
  String? _webDate;
<<<<<<< HEAD
  bool _webClockedIn = false;

  // ── FIX: local (mobile) override state so the UI updates instantly
  // right after a clock in/out, instead of waiting on a DB re-fetch ──
  String? _mobileTimeInOverride;
  String? _mobileTimeOutOverride;
  bool? _mobileClockedInOverride;

  bool _loading = true;
  bool _processing = false;
  bool _showSuccess = false;
  String _successMsg = '';
  String _successSubMsg = '';

  GeofenceResult? _geofenceResult;
  bool _gpsLoading = true;

  late Timer _timer;
  DateTime _now = DateTime.now();

  final _uuid = const Uuid();

  StreamSubscription? _firestoreSub;

  bool get _isClockedIn =>
      kIsWeb ? _webClockedIn : (_mobileClockedInOverride ?? _lastRecord?.isClockedIn ?? false);
  String? get _displayTimeIn =>
      kIsWeb ? _webTimeIn : (_mobileTimeInOverride ?? _lastRecord?.timeIn);
  String? get _displayTimeOut =>
      kIsWeb ? _webTimeOut : (_mobileTimeOutOverride ?? _lastRecord?.timeOut);
  bool get _isInsideZone => _geofenceResult?.isInside ?? false;
=======
  bool    _webClockedIn = false;

  bool   _loading        = true;
  bool   _processing     = false;
  bool   _showSuccess    = false;
  String _successMsg     = '';
  String _successSubMsg  = '';
  int    _selectedMethod = 0;

  GeofenceResult? _geofenceResult;
  bool            _gpsLoading = true;

  late Timer   _timer;
  DateTime     _now = DateTime.now();

  final _uuid            = const Uuid();
  final _localAuth       = LocalAuthentication();
  final _imagePicker     = ImagePicker();
  final _pinController   = TextEditingController();
  final _scrollCtrl      = ScrollController();

  StreamSubscription? _firestoreSub;

  late final List<_ClockMethod> _methods;

  bool    get _isClockedIn      => kIsWeb ? _webClockedIn  : (_lastRecord?.isClockedIn ?? false);
  String? get _displayTimeIn    => kIsWeb ? _webTimeIn     : _lastRecord?.timeIn;
  String? get _displayTimeOut   => kIsWeb ? _webTimeOut    : _lastRecord?.timeOut;
  bool    get _isInsideZone     => _geofenceResult?.isInside ?? false;
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1

  @override
  void initState() {
    super.initState();
<<<<<<< HEAD
=======

    _methods = [
      if (!kIsWeb)
        _ClockMethod(Icons.contactless_rounded,       'NFC Tag',     AppColors.info,    AttendanceMethod.nfc),
      _ClockMethod(Icons.face_retouching_natural,     'Face ID',     AppColors.orange,  AttendanceMethod.face),
      if (!kIsWeb)
        _ClockMethod(Icons.fingerprint_rounded,       'Fingerprint', AppColors.success, AttendanceMethod.fingerprint),
      _ClockMethod(Icons.pin_rounded,                 'PIN',         AppColors.amber,   AttendanceMethod.pin),
    ];

>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

<<<<<<< HEAD
=======
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.96, end: 1.04)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
    _successCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _successAnim = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _successCtrl, curve: Curves.elasticOut));

    _glowCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.2, end: 0.8)
        .animate(CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut));

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });

    _loadData();
    _checkGeofence();
    if (!kIsWeb) _startNfcSession();
  }

  @override
  void dispose() {
    _timer.cancel();
    _fadeCtrl.dispose();
<<<<<<< HEAD
    _successCtrl.dispose();
    _glowCtrl.dispose();
=======
    _pulseCtrl.dispose();
    _successCtrl.dispose();
    _glowCtrl.dispose();
    _pinController.dispose();
    _scrollCtrl.dispose();
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
    _firestoreSub?.cancel();
    if (!kIsWeb) NfcManager.instance.stopSession();
    super.dispose();
  }

  Future<void> _loadData() async {
    final empId = await SecurityService.instance.getCurrentEmployeeId();
<<<<<<< HEAD
    Employee? emp;
=======
    Employee?   emp;
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
    Attendance? att;

    if (empId != null && !kIsWeb) {
      emp = await DatabaseService.instance.getEmployeeById(empId);
      att = await DatabaseService.instance.getTodayAttendance(empId);
    }
    emp ??= widget.initialEmployee;

    if (kIsWeb && emp != null) {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      try {
        final snap = await FirebaseFirestore.instance
            .collection('attendance_logs')
            .where('employee_id', isEqualTo: emp.employeeId)
            .where('date', isEqualTo: today)
            .orderBy('timestamp', descending: false)
            .get();
        String? lastIn, lastOut;
        for (final doc in snap.docs) {
          final d = doc.data();
<<<<<<< HEAD
          if (d['type'] == 'IN') lastIn = d['time']?.toString();
          if (d['type'] == 'OUT') lastOut = d['time']?.toString();
        }
        if (mounted) setState(() {
          _webTimeIn = lastIn;
          _webTimeOut = lastOut;
          _webDate = today;
=======
          if (d['type'] == 'IN')  lastIn  = d['time']?.toString();
          if (d['type'] == 'OUT') lastOut = d['time']?.toString();
        }
        if (mounted) setState(() {
          _webTimeIn    = lastIn;
          _webTimeOut   = lastOut;
          _webDate      = today;
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
          _webClockedIn = lastIn != null && lastOut == null;
        });

        _firestoreSub?.cancel();
        _firestoreSub = FirebaseFirestore.instance
            .collection('attendance_logs')
            .where('employee_id', isEqualTo: emp.employeeId)
            .where('date', isEqualTo: today)
            .orderBy('timestamp', descending: false)
            .snapshots()
            .listen((s) {
          if (!mounted) return;
          String? li, lo;
          for (final doc in s.docs) {
            final d = doc.data();
<<<<<<< HEAD
            if (d['type'] == 'IN') li = d['time']?.toString();
            if (d['type'] == 'OUT') lo = d['time']?.toString();
          }
          setState(() {
            _webTimeIn = li;
            _webTimeOut = lo;
            _webDate = today;
=======
            if (d['type'] == 'IN')  li = d['time']?.toString();
            if (d['type'] == 'OUT') lo = d['time']?.toString();
          }
          setState(() {
            _webTimeIn    = li;
            _webTimeOut   = lo;
            _webDate      = today;
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
            _webClockedIn = li != null && lo == null;
          });
        });
      } catch (e) {
        debugPrint('Firestore web load: $e');
      }
    }

    if (mounted) setState(() {
<<<<<<< HEAD
      _employee = emp;
      _lastRecord = att;
      _loading = false;
=======
      _employee   = emp;
      _lastRecord = att;
      _loading    = false;
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
    });
  }

  Future<void> _checkGeofence() async {
<<<<<<< HEAD
    if (mounted) setState(() => _gpsLoading = true);
=======
    setState(() => _gpsLoading = true);
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
    try {
      final res = await GeofenceService.instance.checkGeofence();
      if (mounted) setState(() => _geofenceResult = res);
    } catch (_) {} finally {
      if (mounted) setState(() => _gpsLoading = false);
    }
  }

<<<<<<< HEAD
  void _handleClockTileTap() async {
    if (_processing) return;

    await _checkGeofence();
    if (!mounted) return;

    if (!_isInsideZone) {
      _showGeofenceDialog();
      return;
    }

    setState(() => _processing = true);
    final ok = await _recordAttendance(AttendanceMethod.pin);
    if (!mounted) return;
    setState(() => _processing = false);

    if (ok) {
      await Future.delayed(const Duration(milliseconds: 1600));
      if (!mounted) return;
      _handleContinue();
=======
  Future<bool> _authenticateWithFace() async {
    if (kIsWeb) { _showSnack('Face capture is only available on Mobile.', AppColors.info); return false; }
    try {
      final XFile? photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 85,
        maxWidth: 640,
        maxHeight: 640,
      );
      if (photo == null) { _showSnack('Face capture cancelled.', AppColors.warning); return false; }
      debugPrint('Face photo: ${photo.path}');
      return true;
    } on PlatformException catch (e) {
      if (e.code == 'camera_access_denied') {
        _showSnack('Camera permission denied. Please allow in Settings.', AppColors.error);
      } else {
        _showSnack('Camera error: ${e.message}', AppColors.error);
      }
      return false;
    } catch (e) {
      _showSnack('Unexpected error: $e', AppColors.error);
      return false;
    }
  }

  Future<bool> _authenticateWithFingerprint() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isAvail  = await _localAuth.isDeviceSupported();
      if (!canCheck || !isAvail) {
        _showSnack('Biometric authentication not available on this device.', AppColors.error);
        return false;
      }
      final biometrics = await _localAuth.getAvailableBiometrics();
      if (biometrics.isEmpty) {
        _showSnack('No fingerprint enrolled. Set up in device settings.', AppColors.error);
        return false;
      }
      return await _localAuth.authenticate(
        localizedReason: 'Scan your fingerprint to record attendance',
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true, useErrorDialogs: true),
      );
    } on PlatformException catch (e) {
      if (e.code == auth_error.notEnrolled) {
        _showSnack('No fingerprint enrolled.', AppColors.error);
      } else if (e.code == auth_error.lockedOut || e.code == auth_error.permanentlyLockedOut) {
        _showSnack('Fingerprint locked. Too many failed attempts.', AppColors.error);
      } else {
        _showSnack('Fingerprint error: ${e.message}', AppColors.error);
      }
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CLOCK TAP HANDLER
  // ═══════════════════════════════════════════════════════════════════════════
  void _handleClockTap() async {
    if (_processing) return;

    setState(() => _gpsLoading = true);
    try {
      final res = await GeofenceService.instance.checkGeofence();
      if (mounted) setState(() { _geofenceResult = res; _gpsLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _gpsLoading = false);
    }

    if (!_isInsideZone) { _showGeofenceDialog(); return; }

    final type = _methods[_selectedMethod].type;

    if (kIsWeb && (type == AttendanceMethod.face || type == AttendanceMethod.fingerprint || type == AttendanceMethod.nfc)) {
      _showSnack('${_methods[_selectedMethod].label} is only available on Mobile', AppColors.info);
      return;
    }

    if (type == AttendanceMethod.pin) {
      if (_pinController.text.length == 4) {
        _handlePinSubmit(_pinController.text);
      } else {
        _showSnack('Please enter your 4-digit PIN first', AppColors.warning);
      }
      return;
    }

    if (type == AttendanceMethod.face) {
      setState(() => _processing = true);
      final ok = await _authenticateWithFace();
      if (!ok) { if (mounted) setState(() => _processing = false); return; }
      await _recordAttendance(AttendanceMethod.face);
      return;
    }

    if (type == AttendanceMethod.fingerprint) {
      setState(() => _processing = true);
      final ok = await _authenticateWithFingerprint();
      if (!ok) { if (mounted) setState(() => _processing = false); return; }
      await _recordAttendance(AttendanceMethod.fingerprint);
      return;
    }

    if (type == AttendanceMethod.nfc) {
      if (_isClockedIn) {
        setState(() => _processing = true);
        await _recordAttendance(AttendanceMethod.nfc);
      } else {
        _showSnack('Tap your NFC keyfob to the back of the device', AppColors.info);
      }
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
    }
  }

  Future<void> _startNfcSession() async {
    if (kIsWeb) return;
    try {
      final isAvailable = await NfcManager.instance.isAvailable();
      if (!isAvailable) return;
      NfcManager.instance.startSession(onDiscovered: (NfcTag tag) async {
        if (_processing || _showSuccess) return;
<<<<<<< HEAD

        await _checkGeofence();
        if (!mounted) return;
        if (!_isInsideZone) {
          _showGeofenceDialog();
          return;
        }

        final tagId = _extractTagId(tag);
        if (tagId == null) return;
        setState(() => _processing = true);
=======
        if (_methods[_selectedMethod].type != AttendanceMethod.nfc) return;
        if (!_isInsideZone) { _showGeofenceDialog(); return; }
        final tagId = _extractTagId(tag);
        if (tagId == null) return;
        if (mounted) setState(() => _processing = true);
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
        try {
          final emp = await DatabaseService.instance.getEmployeeByNfcTag(tagId);
          if (emp != null) {
            final rec = await DatabaseService.instance.getTodayAttendance(emp.id);
<<<<<<< HEAD
            final ok = await _recordAttendance(AttendanceMethod.nfc,
                nfcTagId: tagId, targetEmployee: emp, targetRecord: rec);
            if (ok && mounted) {
              await Future.delayed(const Duration(milliseconds: 1600));
              if (mounted) {
                _handleContinue();
              }
            }
=======
            await _recordAttendance(AttendanceMethod.nfc, nfcTagId: tagId, targetEmployee: emp, targetRecord: rec);
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
          } else {
            _showSnack('Unregistered NFC Tag: $tagId', AppColors.error);
            if (mounted) setState(() => _processing = false);
          }
        } catch (e) {
          debugPrint('NFC error: $e');
          if (mounted) setState(() => _processing = false);
        }
      });
    } catch (e) {
      debugPrint('NFC session: $e');
    }
  }

  String? _extractTagId(NfcTag tag) {
    try {
      final m = tag.data;
      List<int>? id;
<<<<<<< HEAD
      if (m.containsKey('nfca')) id = m['nfca']['identifier']?.cast<int>();
      else if (m.containsKey('mifare-classic')) id = m['mifare-classic']['identifier']?.cast<int>();
      if (id == null) return null;
      return id.map((e) => e.toRadixString(16).padLeft(2, '0')).join(':').toUpperCase();
    } catch (_) {
      return null;
    }
  }

  // ── ITONG PARTE ANG BINAGO PARA MAKITA NG DASHBOARD, CLOCK SCREEN,
  //     AT ATTENDANCE HISTORY ──
  //
  // Mobile path ngayon ay:
  //   1. Isusulat muna LOCALLY gamit ang DatabaseService (logAttendance /
  //      updateTimeOut) — ito ang pinapakinggan ng Attendance History
  //      screen (_attendanceSub / onAttendanceChanged) at ng _lastRecord
  //      dito sa Clock Screen (via _loadData()).
  //   2. Pagkatapos, i-mirror din papunta sa Firestore attendance_logs —
  //      ito ang binabasa ng Dashboard screen.
  //   3. May instant "override" state din para hindi na kailangan
  //      hintayin ang re-fetch bago mag-update ang UI.
  Future<bool> _recordAttendance(
      AttendanceMethod method, {
        String? nfcTagId,
        Employee? targetEmployee,
        Attendance? targetRecord,
      }) async {
    final now = DateTime.now();
    final today = DateFormat('yyyy-MM-dd').format(now);
    final timeStr = DateFormat('HH:mm:ss').format(now);
    final emp = targetEmployee ?? _employee ?? widget.initialEmployee;
    if (emp == null) return false;
=======
      if (m.containsKey('nfca'))               id = m['nfca']['identifier']?.cast<int>();
      else if (m.containsKey('mifare-classic')) id = m['mifare-classic']['identifier']?.cast<int>();
      if (id == null) return null;
      return id.map((e) => e.toRadixString(16).padLeft(2, '0')).join(':').toUpperCase();
    } catch (_) { return null; }
  }

  Future<void> _handlePinSubmit(String pin) async {
    if (_processing) return;

    setState(() => _gpsLoading = true);
    try {
      final res = await GeofenceService.instance.checkGeofence();
      if (mounted) setState(() { _geofenceResult = res; _gpsLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _gpsLoading = false);
    }

    if (!_isInsideZone) { _showGeofenceDialog(); return; }
    setState(() => _processing = true);

    bool isValid = false;
    try {
      final snap = await FirebaseFirestore.instance.collection('employees').where('status', isEqualTo: 'active').get();
      final emp  = _employee ?? widget.initialEmployee;
      for (final doc in snap.docs) {
        final data  = doc.data();
        if ((data['tempPin']?.toString() ?? '') != pin) continue;
        final fId   = (data['employeeId'] ?? data['employee_id'] ?? '').toString();
        final sId   = (emp?.employeeId.isNotEmpty == true ? emp!.employeeId : emp?.id ?? '').toString();
        final fMail = (data['email'] ?? '').toString().toLowerCase();
        final sMail = (emp?.email ?? '').toString().toLowerCase();
        if (fId == sId || fId.toLowerCase() == sId.toLowerCase() || (sMail.isNotEmpty && fMail == sMail)) {
          isValid = true;
          break;
        }
      }
      if (!isValid) {
        final pinMatches = snap.docs.where((d) => (d.data()['tempPin']?.toString() ?? '') == pin).toList();
        if (pinMatches.length == 1) isValid = true;
      }
    } catch (e) {
      debugPrint('Firestore PIN: $e');
    }

    if (!isValid) {
      try {
        final empId = await SecurityService.instance.getCurrentEmployeeId();
        if (empId != null) isValid = await SecurityService.instance.verifyPin(empId, pin);
      } catch (e) { debugPrint('Local PIN: $e'); }
    }

    if (isValid) {
      _pinController.clear();
      await _recordAttendance(AttendanceMethod.pin);
    } else {
      _showSnack('Invalid PIN. Please try again.', AppColors.error);
      _pinController.clear();
      setState(() => _processing = false);
    }
  }

  Future<void> _recordAttendance(
      AttendanceMethod method, {
        String?     nfcTagId,
        Employee?   targetEmployee,
        Attendance? targetRecord,
      }) async {
    final now     = DateTime.now();
    final today   = DateFormat('yyyy-MM-dd').format(now);
    final timeStr = DateFormat('HH:mm:ss').format(now);
    final emp     = targetEmployee ?? _employee ?? widget.initialEmployee;
    if (emp == null) return;
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1

    final isClockedIn = kIsWeb
        ? _webClockedIn
        : (targetRecord?.isClockedIn ?? _lastRecord?.isClockedIn ?? false);
    final record = targetRecord ?? _lastRecord;

    try {
      if (kIsWeb) {
        final type = isClockedIn ? 'OUT' : 'IN';
        await FirebaseFirestore.instance.collection('attendance_logs').add({
<<<<<<< HEAD
          'employee_id': emp.employeeId,
          'employee_name': emp.fullName,
          'date': today,
          'time': timeStr,
          'type': type,
          'method': method.name,
          'platform': 'Web',
          'timestamp': FieldValue.serverTimestamp(),
        });
        if (mounted) setState(() {
          if (type == 'IN') {
            _webTimeIn = timeStr;
            _webTimeOut = null;
            _webDate = today;
            _webClockedIn = true;
          } else {
            _webTimeOut = timeStr;
            _webClockedIn = false;
          }
=======
          'employee_id'  : emp.employeeId,
          'employee_name': emp.fullName,
          'date'         : today,
          'time'         : timeStr,
          'type'         : type,
          'method'       : method.name,
          'platform'     : 'Web',
          'timestamp'    : FieldValue.serverTimestamp(),
        });
        if (mounted) setState(() {
          if (type == 'IN') { _webTimeIn = timeStr; _webTimeOut = null; _webDate = today; _webClockedIn = true; }
          else               { _webTimeOut = timeStr; _webClockedIn = false; }
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
        });
        _showSuccessOverlay(
          '${type == "IN" ? "Clock In" : "Clock Out"} Success',
          '${emp.fullName}\n${DateFormat("hh:mm a").format(now)}\n(Logged to Cloud)',
        );
      } else {
<<<<<<< HEAD
        // MOBILE PATH
        if (isClockedIn && record != null) {
          // ── CLOCK OUT ──
          // 1. Local DB — ito ang gagawing basehan ng Attendance History
          //    at ng Clock Screen (_lastRecord).
          await DatabaseService.instance.updateTimeOut(record.id, timeStr);

          // 2. Mirror sa Firestore — para makita rin sa Dashboard.
          await FirebaseFirestore.instance.collection('attendance_logs').add({
            'employee_id': emp.employeeId,
            'employee_name': emp.fullName,
            'date': today,
            'time': timeStr,
            'type': 'OUT',
            'method': method.name,
            'platform': 'Mobile',
            'timestamp': FieldValue.serverTimestamp(),
          });

          // 3. Instant UI update.
          if (mounted) {
            setState(() {
              _mobileTimeOutOverride = timeStr;
              _mobileClockedInOverride = false;
            });
          }

          _showSuccessOverlay('Clock Out Success', '${emp.fullName}\n${DateFormat("hh:mm a").format(now)}');
        } else {
          // ── CLOCK IN ──
          final isLate = now.hour > 9 || (now.hour == 9 && now.minute > 0);

          // 1. Local DB.
          final newRecord = Attendance(
            id: _uuid.v4(),
            employeeId: emp.id,
            date: today,
            timeIn: timeStr,
            timeOut: null,
            status: isLate ? AttendanceStatus.late : AttendanceStatus.present,
            method: method,
            latitude: null,
            longitude: null,
            deviceId: nfcTagId,
            createdAt: now,
          );
          await DatabaseService.instance.logAttendance(newRecord);

          // 2. Mirror sa Firestore.
          await FirebaseFirestore.instance.collection('attendance_logs').add({
            'employee_id': emp.employeeId,
            'employee_name': emp.fullName,
            'date': today,
            'time': timeStr,
            'type': 'IN',
            'method': method.name,
            'platform': 'Mobile',
            'timestamp': FieldValue.serverTimestamp(),
          });

          // 3. Instant UI update.
          if (mounted) {
            setState(() {
              _mobileTimeInOverride = timeStr;
              _mobileTimeOutOverride = null;
              _mobileClockedInOverride = true;
            });
          }

=======
        if (isClockedIn && record != null) {
          await DatabaseService.instance.updateTimeOut(record.id, timeStr);
          _showSuccessOverlay('Clock Out Success', '${emp.fullName}\n${DateFormat("hh:mm a").format(now)}');
        } else {
          final isLate    = now.hour > 9 || (now.hour == 9 && now.minute > 0);
          final attendance = Attendance(
            id        : _uuid.v4(),
            employeeId: emp.id,
            date      : today,
            timeIn    : timeStr,
            status    : isLate ? AttendanceStatus.late : AttendanceStatus.present,
            method    : method,
            createdAt : now,
            notes     : nfcTagId != null ? 'NFC: $nfcTagId' : null,
          );
          await DatabaseService.instance.logAttendance(attendance);
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
          _showSuccessOverlay(
            'Clock In Success',
            '${emp.fullName}\n${DateFormat("hh:mm a").format(now)}${isLate ? "\n⚠ Late Arrival" : ""}',
          );
        }
        await _loadData();
      }
<<<<<<< HEAD
      return true;
    } catch (e) {
      _showSnack('Record failed: $e', AppColors.error);
      return false;
    }
  }

  void _handleContinue() {
    if (!mounted) return;
    widget.onContinue?.call();
  }

=======
    } catch (e) {
      _showSnack('Record failed: $e', AppColors.error);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
  @override
  Widget build(BuildContext context) {
    if (_loading) return _buildSplash();
    return Scaffold(
<<<<<<< HEAD
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
=======
      backgroundColor: AppColors.primaryDeep,
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
      body: Stack(children: [
        FadeTransition(
          opacity: _fadeAnim,
          child: SafeArea(
            child: SingleChildScrollView(
<<<<<<< HEAD
=======
              controller: _scrollCtrl,
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _buildHeader(),
                const SizedBox(height: 20),
                _buildStatusBanner(),
                const SizedBox(height: 16),
                _buildLocationCard(),
                const SizedBox(height: 16),
                _buildTimeRow(),
                const SizedBox(height: 28),
<<<<<<< HEAD
                _buildClockTile(),
=======
                _buildClockButton(),
                const SizedBox(height: 28),
                _buildMethodSelector(),
                const SizedBox(height: 16),
                _buildMethodContent(),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
              ]),
            ),
          ),
        ),
        if (_showSuccess) _buildSuccessOverlay(),
      ]),
    );
  }

  Widget _buildHeader() {
    final name = _employee?.firstName ?? _employee?.fullName.split(' ').first ?? 'Employee';
<<<<<<< HEAD
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      height: 72,
      child: Row(children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppColors.gradientOrange,
            border: Border.all(color: _MockColors.darkBorder, width: 1.15),
=======
    return Container(
      height: 72,
      child: Row(children: [
        Container(
          width: 46, height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.orange,
            border: Border.all(color: AppColors.orange.withOpacity(0.4), width: 2),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
          ),
          child: Center(
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : 'U',
<<<<<<< HEAD
              style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w900, fontSize: 18),
=======
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
            ),
          ),
        ),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
<<<<<<< HEAD
          Text(
            'HI, ${name.toUpperCase()}',
            style: TextStyle(
              color: isDark ? AppColors.textSecondary : AppColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.0,
            ),
          ),
          Text(
            'Employee Dashboard',
            style: TextStyle(
              color: isDark ? AppColors.textPrimary : Colors.black,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ]),
        const Spacer(),
        GestureDetector(
          onTap: () {
            widget.onBack?.call();
          },
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: AppColors.gradientOrange,
              shape: BoxShape.circle,
              border: Border.all(color: _MockColors.orangeBorder, width: 1.15),
            ),
            child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
=======
          Text('HI, ${name.toUpperCase()}',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1.0)),
          const Text('Employee Dashboard',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
        ]),
        const Spacer(),
        GestureDetector(
          onTap: _checkGeofence,
          child: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary, size: 20),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
          ),
        ),
      ]),
    );
  }

  Widget _buildStatusBanner() {
    final inRange = _isInsideZone;
    final loading = _gpsLoading;
<<<<<<< HEAD
    final statusText = loading ? 'Detecting...' : (inRange ? 'In Range.' : 'Out of Range.');
    final statusColor = loading ? AppColors.textSecondary : AppColors.orange;
    final subText = inRange || loading
        ? 'Our system verified your location. You are\nready to go.'
        : 'You are outside the authorized zone.\nMove closer to clock in.';

    return Container(
      width: double.infinity,
      height: 175,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3A3A3A), Color(0xFF1A1A1A), Color(0xFF0D0D0D)],
        ),
        border: Border.all(color: _MockColors.orangeBorder, width: 1.15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.white15,
                      Colors.transparent,
                      Colors.black.withOpacity(0.4),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                RichText(
                  text: TextSpan(
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w500,
                      color: AppColors.white,
                      height: 1.25,
                    ),
=======
    final statusText  = loading ? 'Detecting...' : (inRange ? 'In Range.' : 'Out of Range.');
    final statusColor = loading ? AppColors.textSecondary : (inRange ? AppColors.orange : AppColors.error);
    final subText     = inRange || loading
        ? 'Our system verified your location. You are\nready to go.'
        : 'You are outside the authorized zone.\nMove closer to clock in.';

    return AnimatedBuilder(
      animation: _glowAnim,
      builder: (_, __) => Container(
        width: double.infinity,
        height: 175,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1E1E1E), Color(0xFF2A2A2A), Color(0xFF1A1A1A)],
          ),
          border: Border.all(color: AppColors.cardBorder, width: 1),
          boxShadow: [
            BoxShadow(
              color: loading ? Colors.black45 : statusColor.withOpacity(0.15 * _glowAnim.value),
              blurRadius: 40, spreadRadius: 4,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(children: [
            Positioned(
              right: -40, top: -40,
              child: Container(
                width: 180, height: 180,
                decoration: BoxDecoration(shape: BoxShape.circle, color: statusColor.withOpacity(0.06)),
              ),
            ),
            Positioned(
              right: 20, bottom: -60,
              child: Container(
                width: 140, height: 140,
                decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.cardBorder.withOpacity(0.04)),
              ),
            ),
            CustomPaint(size: const Size(double.infinity, 175), painter: _SilkPainter()),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                RichText(
                  text: TextSpan(
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.textPrimary, height: 1.25, letterSpacing: -0.3),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
                    children: [
                      const TextSpan(text: 'You are currently\n'),
                      TextSpan(
                        text: statusText,
<<<<<<< HEAD
                        style: TextStyle(color: statusColor),
=======
                        style: TextStyle(
                          color: statusColor,
                          shadows: !loading ? [Shadow(color: statusColor.withOpacity(0.5), blurRadius: 20)] : [],
                        ),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
<<<<<<< HEAD
                Text(
                  subText,
                  style: const TextStyle(
                    color: AppColors.white70,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
=======
                Text(subText, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.5)),
              ]),
            ),
          ]),
        ),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
      ),
    );
  }

  Widget _buildLocationCard() {
<<<<<<< HEAD
    final inRange = _isInsideZone;
    final loading = _gpsLoading;
    final zoneText = loading ? 'Checking your zone…' : (inRange ? 'Inside Authorized Zone' : 'Outside Authorized Zone');
    final dist = _geofenceResult?.distanceMeters;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final accentColor = loading ? AppColors.orange : (inRange ? _MockColors.lime : _MockColors.red);
    final cardBorderColor = loading ? _MockColors.orangeBorder : (inRange ? _MockColors.orangeBorder : _MockColors.red);
    final cardBg = loading || inRange ? null : _MockColors.translucentGray;
    final cardGradient = loading || inRange ? AppColors.gradientOrange : null;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(
          'Location Status',
          style: TextStyle(color: isDark ? AppColors.textPrimary : Colors.black, fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const Spacer(),
        const Icon(Icons.navigation_rounded, color: Colors.black, size: 13),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: _checkGeofence,
          child: const Text(
            'Live GPS',
            style: TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.w500),
          ),
=======
    final inRange     = _isInsideZone;
    final loading     = _gpsLoading;
    final statusLabel = loading ? 'Locating...' : (inRange ? 'Inside Authorized Zone' : 'Outside Authorized Zone');
    final dotColor    = loading ? AppColors.textMuted : (inRange ? AppColors.success : AppColors.error);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('Location Status', style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
        const Spacer(),
        const Icon(Icons.navigation_rounded, color: AppColors.orange, size: 13),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: _checkGeofence,
          child: const Text('Live GPS', style: TextStyle(color: AppColors.orange, fontSize: 11, fontWeight: FontWeight.w600)),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
        ),
      ]),
      const SizedBox(height: 10),
      Container(
<<<<<<< HEAD
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: cardBg,
          gradient: cardGradient,
          border: Border.all(color: cardBorderColor, width: 1.15),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: loading
                ? const Padding(
              padding: EdgeInsets.all(8),
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.orange),
            )
                : Icon(Icons.location_on_rounded, color: accentColor, size: 18),
=======
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Row(children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(color: AppColors.orange.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.location_on_rounded, color: AppColors.orange, size: 20),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
<<<<<<< HEAD
              Text(
                zoneText,
                style: TextStyle(
                  color: accentColor,
                  fontSize: 12,
                  fontWeight: (!loading && !inRange) ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'HQ Main Office',
                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 4),
              Text(
                GeofenceService.officeAddress,
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500, height: 1.3),
              ),
              if (dist != null) ...[
                const SizedBox(height: 4),
                Text(
                  '${dist.toStringAsFixed(0)} m from office',
                  style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w600),
                ),
              ],
            ]),
          ),
=======
              const Text('HQ Main Office', style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              const Text('1245 Paz Street, 1007 Manila,\nMetro Manila - Philippines',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 11, height: 1.4)),
              const SizedBox(height: 4),
              Text(statusLabel, style: TextStyle(color: dotColor, fontSize: 11, fontWeight: FontWeight.w600)),
            ]),
          ),
          const SizedBox(width: 8),
          loading
              ? const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textMuted))
              : Container(
            width: 10, height: 10,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: dotColor.withOpacity(0.6), blurRadius: 8, spreadRadius: 2)],
            ),
          ),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
        ]),
      ),
    ]);
  }

  Widget _buildTimeRow() {
    final clocked = _isClockedIn;
<<<<<<< HEAD
    final timeIn = _fmt12(_displayTimeIn);
    final timeOut = _fmt12(_displayTimeOut);

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        gradient: AppColors.gradientOrange,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.orange, width: 1.15),
      ),
      child: Row(children: [
        Expanded(child: _toggleSegment('Clock In', timeIn, active: !clocked)),
        const SizedBox(width: 4),
        Expanded(child: _toggleSegment('Clock Out', timeOut, active: clocked)),
      ]),
    );
  }

  Widget _toggleSegment(String title, String time, {required bool active}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: active ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: active ? Border.all(color: _MockColors.orangeBorder, width: 1) : null,
        boxShadow: active ? [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 6, offset: const Offset(0, 2))] : null,
      ),
      child: Column(children: [
        Text(
          title,
          style: TextStyle(color: active ? Colors.black : Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 2),
        Text(
          time,
          style: TextStyle(color: active ? const Color(0xFFA1A1AA) : Colors.white, fontSize: 11),
=======
    final timeIn  = _fmt12(_displayTimeIn);
    final timeOut = _fmt12(_displayTimeOut);

    return Container(
      height: 68,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.orange.withOpacity(0.5), width: 1.5),
      ),
      child: Row(children: [
        Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: clocked ? AppColors.cardBorder : AppColors.orange.withOpacity(0.6),
                width: 1,
              ),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('Clock In', style: TextStyle(color: clocked ? AppColors.textSecondary : AppColors.orange, fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(clocked ? timeIn : '--:--',
                  style: TextStyle(color: clocked ? AppColors.textMuted : AppColors.orange.withOpacity(0.6), fontSize: 11, fontWeight: FontWeight.w500)),
            ]),
          ),
        ),
        Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              gradient: clocked
                  ? const LinearGradient(colors: [AppColors.orange, AppColors.orangeHot], begin: Alignment.topLeft, end: Alignment.bottomRight)
                  : null,
              color: clocked ? null : AppColors.card,
              borderRadius: BorderRadius.circular(12),
              boxShadow: clocked ? [BoxShadow(color: AppColors.orange.withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 4))] : null,
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('Clock Out', style: TextStyle(color: clocked ? Colors.white : AppColors.textMuted, fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(clocked ? timeOut : '--:--',
                  style: TextStyle(color: clocked ? Colors.white.withOpacity(0.75) : AppColors.textMuted.withOpacity(0.4), fontSize: 11, fontWeight: FontWeight.w500)),
            ]),
          ),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
        ),
      ]),
    );
  }

<<<<<<< HEAD
  Widget _buildClockTile() {
    final clocked = _isClockedIn;
    final canAct = _isInsideZone;
    final label = clocked ? 'Clock Out' : 'Clock In';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final tileBorder = canAct ? _MockColors.orangeBorder : _MockColors.red;
    final tileBg = canAct ? Colors.white.withOpacity(0.2) : _MockColors.translucentGray;

    return Column(children: [
      Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          style: TextStyle(color: isDark ? AppColors.textPrimary : Colors.black, fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ),
      const SizedBox(height: 12),
      Center(
        child: GestureDetector(
          onTap: _processing ? null : _handleClockTileTap,
          child: Container(
            width: 105,
            height: 112,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
            decoration: BoxDecoration(
              border: Border.all(color: tileBorder, width: 1.15),
              borderRadius: BorderRadius.circular(20),
              color: tileBg,
            ),
            child: _processing
                ? const Center(child: CircularProgressIndicator(color: AppColors.orange, strokeWidth: 2))
                : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: canAct ? AppColors.gradientOrange : null,
                    color: canAct ? null : AppColors.error,
                    shape: BoxShape.circle,
                    border: Border.all(color: canAct ? _MockColors.orangeBorder : _MockColors.red, width: 1.15),
                  ),
                  child: Icon(
                    canAct
                        ? (clocked ? Icons.timer_off_rounded : Icons.access_time_rounded)
                        : Icons.location_off_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  label,
                  style: TextStyle(
                    color: canAct ? Colors.black : Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
=======
  Widget _buildClockButton() {
    final clocked   = _isClockedIn;
    final blocked   = !_isInsideZone && !_gpsLoading;
    final canAct    = _isInsideZone;
    final ringColor = blocked ? AppColors.error : (clocked ? AppColors.orangeHot : AppColors.orange);
    final label     = blocked ? 'Clock Out' : (clocked ? 'Clock Out' : 'Clock In');
    final timeNow   = DateFormat('hh:mm a').format(_now);
    final dateNow   = DateFormat('EEEE, MMMM d yyyy').format(_now);

    return Column(children: [
      Center(
        child: AnimatedBuilder(
          animation: _pulseAnim,
          builder: (_, __) => Transform.scale(
            scale: canAct ? _pulseAnim.value : 1.0,
            child: GestureDetector(
              onTap: _processing ? null : _handleClockTap,
              child: Stack(alignment: Alignment.center, children: [
                AnimatedBuilder(
                  animation: _glowAnim,
                  builder: (_, __) => Container(
                    width: 160, height: 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: ringColor.withOpacity(0.15 * _glowAnim.value), width: 1),
                    ),
                  ),
                ),
                Container(
                  width: 140, height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: canAct
                        ? LinearGradient(
                      colors: clocked
                          ? [AppColors.orangeHot, AppColors.orangeGlow]
                          : [AppColors.orange, AppColors.orangeHot],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                        : null,
                    color: canAct ? null : AppColors.surfaceLight,
                    border: Border.all(
                      color: canAct ? ringColor.withOpacity(0.5) : AppColors.cardBorder,
                      width: 3,
                    ),
                    boxShadow: canAct
                        ? [BoxShadow(color: ringColor.withOpacity(0.4), blurRadius: 32, spreadRadius: 4)]
                        : null,
                  ),
                  child: _processing
                      ? const Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                      : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(
                      blocked ? Icons.location_off_rounded : (clocked ? Icons.timer_off_rounded : Icons.timer_rounded),
                      color: canAct ? Colors.white : AppColors.textMuted,
                      size: 36,
                    ),
                    const SizedBox(height: 6),
                    Text(label,
                        style: TextStyle(
                          color: canAct ? Colors.white : AppColors.textMuted,
                          fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.3,
                        )),
                  ]),
                ),
              ]),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
            ),
          ),
        ),
      ),
      const SizedBox(height: 14),
<<<<<<< HEAD
      Center(
        child: Text(
          DateFormat('hh:mm a').format(_now),
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.5),
        ),
      ),
      const SizedBox(height: 2),
      Center(
        child: Text(
          DateFormat('EEEE, MMMM d yyyy').format(_now),
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
        ),
=======
      Center(child: Text(timeNow, style: const TextStyle(color: AppColors.textSecondary, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.5))),
      const SizedBox(height: 2),
      Center(child: Text(dateNow, style: const TextStyle(color: AppColors.textMuted, fontSize: 11))),
    ]);
  }

  Widget _buildMethodSelector() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Authentication Method', style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
      const SizedBox(height: 12),
      Row(
        children: _methods.asMap().entries.map((e) {
          final active = _selectedMethod == e.key;
          final m      = e.value;
          final isLast = e.key == _methods.length - 1;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: isLast ? 0 : 10),
              child: GestureDetector(
                onTap: () {
                  setState(() => _selectedMethod = e.key);
                  if (m.type == AttendanceMethod.pin) {
                    Future.delayed(const Duration(milliseconds: 200), () {
                      if (_scrollCtrl.hasClients) _scrollCtrl.animateTo(
                        _scrollCtrl.position.maxScrollExtent,
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeOut,
                      );
                    });
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 72,
                  decoration: BoxDecoration(
                    color: active ? m.color.withOpacity(0.12) : AppColors.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: active ? m.color.withOpacity(0.55) : AppColors.cardBorder,
                      width: active ? 1.5 : 1,
                    ),
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(
                      width: 30, height: 30,
                      decoration: BoxDecoration(
                        color: active ? m.color.withOpacity(0.15) : AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(m.icon, color: active ? m.color : AppColors.textMuted, size: 15),
                    ),
                    const SizedBox(height: 5),
                    Text(m.label,
                        style: TextStyle(
                          color: active ? m.color : AppColors.textMuted,
                          fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.3,
                        )),
                  ]),
                ),
              ),
            ),
          );
        }).toList(),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
      ),
    ]);
  }

<<<<<<< HEAD
  Widget _buildSuccessOverlay() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
=======
  Widget _buildMethodContent() {
    final m = _methods[_selectedMethod];
    if (m.type == AttendanceMethod.pin)         return _buildPinInput();
    if (m.type == AttendanceMethod.face)        return _buildBiometricCard(m, isFace: true);
    if (m.type == AttendanceMethod.fingerprint) return _buildBiometricCard(m, isFace: false);
    return _buildNfcCard(m);
  }

  Widget _buildNfcCard(_ClockMethod m) {
    final clocked = _isClockedIn;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: m.color.withOpacity(0.2)),
      ),
      child: Column(children: [
        Container(
          width: 60, height: 60,
          decoration: BoxDecoration(color: m.color.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(m.icon, color: m.color, size: 28),
        ),
        const SizedBox(height: 16),
        Text(
          clocked ? 'TAP BUTTON ABOVE TO CLOCK OUT' : 'TAP YOUR KEYFOB TO THE BACK OF THE DEVICE',
          textAlign: TextAlign.center,
          style: TextStyle(color: m.color, fontWeight: FontWeight.w700, fontSize: 11, letterSpacing: 1.2, height: 1.7),
        ),
        const SizedBox(height: 8),
        Text(
          clocked ? 'No NFC required for clock out' : 'Ready and listening…',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
        if (clocked) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: m.color,
                foregroundColor: Colors.white,
                disabledBackgroundColor: m.color.withOpacity(0.4),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              onPressed: _processing ? null : _handleClockTap,
              icon: _processing
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.timer_off_rounded, size: 18),
              label: Text(
                _processing ? 'Recording…' : 'Clock Out Now',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _buildBiometricCard(_ClockMethod m, {required bool isFace}) {
    final clocked  = _isClockedIn;
    final action   = clocked ? 'Clock Out' : 'Clock In';
    final hint     = isFace
        ? 'Your front camera will open — look straight ahead and take a photo'
        : 'Place your finger on the fingerprint sensor when prompted';
    final btnLabel = isFace ? 'Open Camera to $action' : 'Scan Fingerprint to $action';
    final btnIcon  = isFace ? Icons.camera_alt_rounded : m.icon;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: m.color.withOpacity(0.25)),
      ),
      child: Column(children: [
        Container(
          width: 72, height: 72,
          decoration: BoxDecoration(
            color: m.color.withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(color: m.color.withOpacity(0.3)),
          ),
          child: Icon(m.icon, color: m.color, size: 34),
        ),
        const SizedBox(height: 16),
        Text(m.label, style: TextStyle(color: m.color, fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(hint, textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.5)),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: m.color,
              foregroundColor: Colors.white,
              disabledBackgroundColor: m.color.withOpacity(0.4),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            onPressed: _processing ? null : _handleClockTap,
            icon: _processing
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Icon(btnIcon, size: 18),
            label: Text(
              _processing ? (isFace ? 'Opening Camera…' : 'Authenticating…') : btnLabel,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
          ),
        ),
        if (kIsWeb) ...[
          const SizedBox(height: 10),
          const Text('Available on mobile devices only',
              style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
        ],
      ]),
    );
  }

  Widget _buildPinInput() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.amber.withOpacity(0.25)),
      ),
      child: Column(children: [
        Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: AppColors.amber.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.pin_rounded, color: AppColors.amber, size: 18),
          ),
          const SizedBox(width: 12),
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('PIN Authentication', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 14)),
            Text('Enter your 4-digit PIN', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ]),
        ]),
        const SizedBox(height: 20),
        TextField(
          controller    : _pinController,
          obscureText   : true,
          textAlign     : TextAlign.center,
          keyboardType  : TextInputType.number,
          maxLength     : 4,
          style: const TextStyle(fontSize: 26, letterSpacing: 16, color: AppColors.amber, fontWeight: FontWeight.w800),
          decoration: InputDecoration(
            counterText: '',
            hintText   : '• • • •',
            hintStyle  : const TextStyle(color: AppColors.textMuted, letterSpacing: 14, fontSize: 20),
            filled     : true,
            fillColor  : AppColors.surfaceLight,
            contentPadding: const EdgeInsets.symmetric(vertical: 16),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide  : const BorderSide(color: AppColors.cardBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide  : const BorderSide(color: AppColors.amber, width: 1.5),
            ),
          ),
          onChanged: (val) { if (val.length == 4) _handlePinSubmit(val); },
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.amber,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.amber.withOpacity(0.4),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            onPressed: _processing ? null : () {
              if (_pinController.text.length == 4) _handlePinSubmit(_pinController.text);
              else _showSnack('Please enter your 4-digit PIN first', AppColors.warning);
            },
            icon: _processing
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.lock_open_rounded, size: 16),
            label: Text(_processing ? 'Verifying…' : 'Submit PIN',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          ),
        ),
      ]),
    );
  }

  Widget _buildSuccessOverlay() {
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.8),
        child: Center(
          child: ScaleTransition(
            scale: _successAnim,
            child: Container(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
              constraints: const BoxConstraints(maxWidth: 380),
              decoration: BoxDecoration(
<<<<<<< HEAD
                color: isDark ? AppColors.card : Theme.of(context).cardColor,
=======
                color: AppColors.card,
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.success.withOpacity(0.4)),
                boxShadow: [BoxShadow(color: AppColors.success.withOpacity(0.12), blurRadius: 40, spreadRadius: 4)],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
<<<<<<< HEAD
                  width: 72,
                  height: 72,
=======
                  width: 72, height: 72,
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
                  decoration: BoxDecoration(color: AppColors.success.withOpacity(0.12), shape: BoxShape.circle),
                  child: const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 44),
                ),
                const SizedBox(height: 16),
<<<<<<< HEAD
                Text(
                  _successMsg,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: isDark ? AppColors.textPrimary : Colors.black,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _successSubMsg,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary, height: 1.7, fontSize: 14),
                ),
=======
                Text(_successMsg,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: 0.3)),
                const SizedBox(height: 10),
                Text(_successSubMsg,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textSecondary, height: 1.7, fontSize: 14)),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
              ]),
            ),
          ),
        ),
      ),
    );
  }

  void _showGeofenceDialog() {
    final dist = _geofenceResult?.distanceMeters?.toStringAsFixed(0) ?? '?';
<<<<<<< HEAD
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppColors.card : Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Container(
            width: 36,
            height: 36,
=======
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Container(
            width: 36, height: 36,
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
            decoration: BoxDecoration(color: AppColors.error.withOpacity(0.15), shape: BoxShape.circle),
            child: const Icon(Icons.location_off_rounded, color: AppColors.error, size: 20),
          ),
          const SizedBox(width: 12),
<<<<<<< HEAD
          Expanded(
            child: Text(
              'Outside Work Zone',
              style: TextStyle(color: isDark ? AppColors.textPrimary : Colors.black, fontWeight: FontWeight.w800, fontSize: 15),
            ),
=======
          const Expanded(
            child: Text('Outside Work Zone',
                style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 15)),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
          ),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.error.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.error.withOpacity(0.3)),
            ),
            child: Column(children: [
              const Icon(Icons.gps_off_rounded, color: AppColors.error, size: 32),
              const SizedBox(height: 10),
<<<<<<< HEAD
              Text(
                'You are ${dist}m away from the office.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 8),
              const Text(
                'Move inside the authorized zone to clock in or out.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.error, fontSize: 12, fontWeight: FontWeight.w700, height: 1.4),
              ),
=======
              Text('You are ${dist}m away from the office.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5)),
              const SizedBox(height: 8),
              const Text('Move inside the authorized zone to clock in or out.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.error, fontSize: 12, fontWeight: FontWeight.w700, height: 1.4)),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
            ]),
          ),
        ]),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.info.withOpacity(0.15),
                foregroundColor: AppColors.info,
                elevation: 0,
<<<<<<< HEAD
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: AppColors.info.withOpacity(0.3)),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () {
                Navigator.of(ctx).pop();
                _checkGeofence();
              },
=======
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: AppColors.info.withOpacity(0.3))),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () { Navigator.of(ctx).pop(); _checkGeofence(); },
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Retry Location Check', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
<<<<<<< HEAD
              child: const Text('Dismiss', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
=======
              child: const Text('Dismiss', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSplash() {
    return Scaffold(
<<<<<<< HEAD
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: AppColors.gradientOrange,
            ),
            child: const Icon(Icons.fingerprint, color: AppColors.textPrimary, size: 34),
=======
      backgroundColor: AppColors.primaryDeep,
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(colors: [AppColors.orange, AppColors.orangeHot], begin: Alignment.topLeft, end: Alignment.bottomRight),
            ),
            child: const Icon(Icons.fingerprint, color: Colors.white, size: 34),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
          ),
          const SizedBox(height: 16),
          const Text('Loading attendance terminal…', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 24),
          SizedBox(
            width: 160,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: const LinearProgressIndicator(
                backgroundColor: AppColors.cardBorder,
                valueColor: AlwaysStoppedAnimation(AppColors.orange),
                minHeight: 4,
              ),
            ),
          ),
        ]),
      ),
    );
  }

  String _fmt12(String? t) {
    if (t == null) return '--:--';
<<<<<<< HEAD
    try {
      return DateFormat('hh:mm a').format(DateFormat('HH:mm:ss').parse(t));
    } catch (_) {
      return t;
    }
  }

  void _showSuccessOverlay(String title, String message) {
    setState(() {
      _showSuccess = true;
      _successMsg = title;
      _successSubMsg = message;
    });
=======
    try { return DateFormat('hh:mm a').format(DateFormat('HH:mm:ss').parse(t)); }
    catch (_) { return t; }
  }

  void _showSuccessOverlay(String title, String message) {
    setState(() { _showSuccess = true; _successMsg = title; _successSubMsg = message; });
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
    _successCtrl.forward(from: 0);
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showSuccess = false);
    });
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
<<<<<<< HEAD
      content: Text(msg, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
=======
      content: Text(msg, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }
<<<<<<< HEAD
=======
}

class _SilkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.025)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (int i = -5; i < 20; i++) {
      final path = Path();
      final startX = i * 22.0;
      path.moveTo(startX, 0);
      path.cubicTo(startX + 30, size.height * 0.3, startX - 10, size.height * 0.7, startX + 20, size.height);
      canvas.drawPath(path, paint);
    }
  }
  @override
  bool shouldRepaint(_SilkPainter _) => false;
}

class _ClockMethod {
  final IconData         icon;
  final String           label;
  final Color            color;
  final AttendanceMethod type;
  const _ClockMethod(this.icon, this.label, this.color, this.type);
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
}