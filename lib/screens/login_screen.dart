// lib/screens/login_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:nfc_manager/nfc_manager.dart';
import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/security_service.dart';
import '../services/database_service.dart';
import '../services/location_tracking_service.dart';
import '../models/employee.dart';
import 'fingerprint_screen.dart';
import 'landing_screen.dart';

enum _LoginStep { selectMethod, pinEntry, nfcWait, clientMeeting }

class _ThemeColors {
  final bool isDark;
  const _ThemeColors(this.isDark);

  Color get bgTop => isDark ? const Color(0xFF0A0A0A) : const Color(0xFFFFFFFF);
  Color get bgMid => isDark ? const Color(0xFF0F0D0B) : const Color(0xFFFFF0E5);
  Color get bgBottom =>
      isDark ? const Color(0xFF1A0F05) : const Color(0xFFFFE3D1);
  Color get cardBg =>
      isDark ? const Color(0xFF18181B) : const Color(0xFFFFFFFF);
  Color get cardBorder =>
      isDark ? const Color(0xFF3F3F46) : const Color(0xFFFFEDD5);
  Color get optionBorder =>
      isDark ? const Color(0xFF7C2D12) : const Color(0xFFFDBA74);
  Color get hoverBg =>
      isDark ? const Color(0xFF27272A) : const Color(0xFFFFF7ED);
  Color get textDark => isDark ? Colors.white : const Color(0xFF1F2937);
  Color get textMuted =>
      isDark ? const Color(0xFFB0B0B0) : const Color(0xFF6B7280);
  Color get infoBg => isDark ? const Color(0xFF1F1F23) : Colors.white;
  Color get infoBorder =>
      isDark ? const Color(0xFF3F3F46) : const Color(0xFFFFEDD5);
  Color get infoText =>
      isDark ? const Color(0xFFB0B0B0) : const Color(0xFF6B7280);
  Color get methodIconBg => isDark ? const Color(0xFF27272A) : Colors.white;
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  String _pinInput = '';
  bool _isLoading = false;
  bool _nfcAvailable = false;
  String? _errorMessage;
  _LoginStep _step = _LoginStep.selectMethod;

  bool _clientMeetingMode = false;

  late final DateTime _arrivalTime;

  CameraController? _cameraController;
  bool _isCapturing = false;
  bool _captureSuccess = false;
  DateTime _now = DateTime.now();
  Timer? _clockTimer;
  Timer? _successCloseTimer;
  bool _useFrontCamera = true;

  // 📍 Location State
  double? _currentLatitude;
  double? _currentLongitude;
  String _currentPlaceName = 'Getting location…';
  bool _loadingLocation = false;
  DateTime? _locationTimestamp;
  StreamSubscription<Position>? _positionSub;

  Employee? _activeEmployee;

  // ✅ SharedPreferences KEY
  static const String _kLastEmployeeIdKey = 'last_logged_in_employee_id';

  late AnimationController _shakeController;
  late Animation<double> _shakeAnim;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;
  late AnimationController _modalController;
  late Animation<double> _modalScaleAnim;
  late Animation<double> _modalOpacityAnim;
  late AnimationController _nfcPulseController;
  late Animation<double> _nfcPulseAnim;

  static const Color _headerStart = Color(0xFFFF8A00);
  static const Color _headerMid = Color(0xFFFF6B00);
  static const Color _headerEnd = Color(0xFFF54900);
  static const Color _headerBorder = Color(0xFF382A20);
  static const Color _orange = Color(0xFFF97316);
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _error = Color(0xFFDC2626);
  static const Color _errorBg = Color(0xFFFEE2E2);
  static const Color _modalGradTop = Color(0xFFFF8A00);
  static const Color _modalGradMid = Color(0xFFFA6A00);
  static const Color _modalGradEnd = Color(0xFFF54900);
  static const Color _scrim = Color.fromRGBO(9, 9, 21, 0.68);
  static const Color _cmPreviewBg = Color(0xFF20212A);
  static const Color _cmShutterOuter = Color(0xFFFFA500);
  static const Color _cmShutterInner = Color(0xFFFEE0AA);
  static const Color _cmShutterGlow = Color(0xFFFF8C00);

  static const double _kHeaderDesignFrameWidth = 386.13;
  static const double _kHeaderH = 287.13;
  static const double _kHeaderBorderBottom = 1.15;
  static const double _kHeaderRadius = 16.0;
  static const double _kBackLeft = 24.0;
  static const double _kBackTop = 48.0;
  static const double _kBackIconSize = 19.99;
  static const double _kTitleLeft = 24.0;
  static const double _kTitleTop = 95.99;
  static const double _kTitleFontSize = 30.0;
  static const double _kSubtitleLeft = 24.0;
  static const double _kSubtitleTop = 136.99;
  static const double _kSubtitleFontSize = 14.0;

  static const List<String> _notFoundCodes = [
    'user-not-found',
    'invalid-credential',
    'invalid-login-credentials',
    'INVALID_LOGIN_CREDENTIALS',
  ];

  String? get _employeeId {
    final emp = _activeEmployee;
    if (emp == null) return null;
    if (emp.employeeId.isNotEmpty) return emp.employeeId;
    if (emp.id.isNotEmpty) return emp.id;
    return null;
  }

  String get _employeeName => _activeEmployee?.fullName ?? 'Unknown';
  String get _employeeEmail => _activeEmployee?.email ?? '';

  @override
  void initState() {
    super.initState();

    _arrivalTime = DateTime.now();
    debugPrint('⏱️ [LoginScreen] Arrival time captured: $_arrivalTime');

    _shakeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fadeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _modalController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 260));
    _nfcPulseController =
        AnimationController(vsync: this, duration: const Duration(seconds: 2));

    _shakeAnim = Tween<double>(begin: 0, end: 10).animate(
        CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn));
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));
    _modalScaleAnim = Tween<double>(begin: 0.9, end: 1.0).animate(
        CurvedAnimation(parent: _modalController, curve: Curves.easeOutBack));
    _modalOpacityAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _modalController, curve: Curves.easeOut));
    _nfcPulseAnim = Tween<double>(begin: 0.9, end: 1.1).animate(
        CurvedAnimation(parent: _nfcPulseController, curve: Curves.easeInOut));

    _nfcPulseController.repeat(reverse: true);
    _fadeController.forward();

    _startClockTimer();
    _checkCapabilities();
    _preloadLastEmployee();
  }

  Future<void> _preloadLastEmployee() async {
    final lastId = await _getLastEmployeeId();
    if (lastId == null || lastId.isEmpty) return;
    final emp = await _loadEmployeeById(lastId);
    if (emp != null && mounted) {
      setState(() => _activeEmployee = emp);
      debugPrint('✅ [Preload] Restored active employee: ${emp.id}');
    }
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _fadeController.dispose();
    _modalController.dispose();
    _nfcPulseController.dispose();
    _clockTimer?.cancel();
    _successCloseTimer?.cancel();
    _positionSub?.cancel();
    _releaseCamera();
    if (!kIsWeb) {
      try {
        NfcManager.instance.stopSession();
      } catch (_) {}
    }
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════
  // 💾 SHARED PREFERENCES HELPERS
  // ═══════════════════════════════════════════════════════════════
  Future<void> _saveLastEmployeeId(String empId) async {
    if (empId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLastEmployeeIdKey, empId);
      debugPrint('✅ [Prefs] Saved last empId: $empId');
    } catch (e) {
      debugPrint('⚠️ [Prefs] Save failed: $e');
    }
  }

  Future<String?> _getLastEmployeeId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_kLastEmployeeIdKey);
    } catch (e) {
      debugPrint('⚠️ [Prefs] Read failed: $e');
      return null;
    }
  }

  Future<void> _checkCapabilities() async {
    if (kIsWeb) {
      if (mounted) setState(() => _nfcAvailable = false);
      return;
    }
    try {
      final available = await NfcManager.instance.isAvailable();
      if (mounted) setState(() => _nfcAvailable = available);
    } catch (e) {
      debugPrint('NFC check error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // 📍 LOCATION
  // ═══════════════════════════════════════════════════════════════
  Future<bool> _ensureLocationPermission() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('⚠️ Location services disabled');
        return false;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        debugPrint('⚠️ Location permission denied');
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('⚠️ Location permission error: $e');
      return false;
    }
  }

  void _startLocationTracking() {
    _positionSub?.cancel();
    if (mounted) {
      setState(() {
        _loadingLocation = true;
        _currentPlaceName = 'Getting location…';
      });
    }
    _getCurrentPositionOnce();
    try {
      _positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 10,
        ),
      ).listen((Position pos) {
        _updatePosition(pos);
      }, onError: (e) {
        debugPrint('⚠️ Position stream error: $e');
      });
    } catch (e) {
      debugPrint('⚠️ Position stream init failed: $e');
    }
  }

  Future<void> _getCurrentPositionOnce() async {
    try {
      final ok = await _ensureLocationPermission();
      if (!ok) {
        if (mounted) {
          setState(() {
            _loadingLocation = false;
            _currentPlaceName = 'Location unavailable';
          });
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 15),
      );
      await _updatePosition(pos);
    } catch (e) {
      debugPrint('⚠️ getCurrentPosition error: $e');
      if (mounted) {
        setState(() {
          _loadingLocation = false;
          if (_currentPlaceName == 'Getting location…') {
            _currentPlaceName = 'Location unavailable';
          }
        });
      }
    }
  }

  Future<void> _updatePosition(Position pos) async {
    if (!mounted) return;
    if (pos.latitude == 0 && pos.longitude == 0) return;
    setState(() {
      _currentLatitude = pos.latitude;
      _currentLongitude = pos.longitude;
      _locationTimestamp = DateTime.now();
      _loadingLocation = false;
    });
    debugPrint('📍 GPS: ${pos.latitude}, ${pos.longitude}');
    await _reverseGeocode(pos.latitude, pos.longitude);
  }

  Future<void> _reverseGeocode(double lat, double lng) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isEmpty || !mounted) return;
      final p = placemarks.first;
      final subLocality = (p.subLocality ?? '').trim();
      final locality = (p.locality ?? '').trim();
      final subAdmin = (p.subAdministrativeArea ?? '').trim();
      final admin = (p.administrativeArea ?? '').trim();
      final street = (p.street ?? '').trim();
      final name = (p.name ?? '').trim();
      String placeName = '';
      if (subLocality.isNotEmpty &&
          locality.isNotEmpty &&
          subLocality != locality) {
        placeName = '$subLocality, $locality';
      } else if (locality.isNotEmpty) {
        placeName = locality;
      } else if (subAdmin.isNotEmpty) {
        placeName = subAdmin;
      } else if (admin.isNotEmpty) {
        placeName = admin;
      } else if (subLocality.isNotEmpty) {
        placeName = subLocality;
      } else if (street.isNotEmpty) {
        placeName = street;
      } else if (name.isNotEmpty) {
        placeName = name;
      } else {
        placeName = 'Unknown location';
      }
      if (!mounted) return;
      setState(() => _currentPlaceName = placeName);
      debugPrint('📍 Place: $placeName');
    } catch (e) {
      debugPrint('⚠️ Reverse geocode failed: $e');
      if (!mounted) return;
      setState(() => _currentPlaceName = 'Location unavailable');
    }
  }

  String get _locationDisplay {
    if (_loadingLocation) return 'Getting location…';
    return _currentPlaceName;
  }

  void _stopLocationTracking() {
    _positionSub?.cancel();
    _positionSub = null;
    if (mounted) {
      setState(() {
        _loadingLocation = false;
        _currentLatitude = null;
        _currentLongitude = null;
        _locationTimestamp = null;
        _currentPlaceName = 'Getting location…';
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // NFC LOGIN
  // ═══════════════════════════════════════════════════════════════
  Future<void> _startNfcSession() async {
    if (kIsWeb) {
      _setError('NFC is not available on web browsers. Please use PIN instead.');
      return;
    }
    try {
      await NfcManager.instance.stopSession();
      NfcManager.instance.startSession(
        pollingOptions: {NfcPollingOption.iso14443, NfcPollingOption.iso15693},
        onDiscovered: (NfcTag tag) async {
          if (_isLoading) return;
          final serial = _extractTagId(tag);
          if (serial == null) {
            _setError('Could not read keyfob ID.');
            return;
          }
          if (mounted) {
            setState(() {
              _isLoading = true;
              _errorMessage = null;
            });
          }
          try {
            final employee = await _findEmployeeByNfc(serial);
            if (employee != null) {
              await NfcManager.instance.stopSession();
              await _openSession(employee);
            } else {
              await NfcManager.instance.stopSession();
              _setError('Keyfob not registered. Contact your Admin.');
            }
          } catch (e) {
            _setError('NFC login error: $e');
          }
        },
      );
    } catch (e) {
      debugPrint('NFC session error: $e');
    }
  }

  Future<Employee?> _findEmployeeByNfc(String serial) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('employees')
          .where('nfcTagId', isEqualTo: serial)
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;
      return _docToEmployee(snap.docs.first);
    } catch (e) {
      debugPrint('_findEmployeeByNfc error: $e');
      return null;
    }
  }

  String? _extractTagId(NfcTag tag) {
    try {
      final tagMap = tag.data as Map<String, dynamic>;
      List<int>? tryKey(String key) {
        final tech = tagMap[key] as Map<dynamic, dynamic>?;
        if (tech == null) return null;
        final raw = tech['identifier'];
        if (raw is List) return raw.cast<int>();
        return null;
      }
      final id = tryKey('nfca') ??
          tryKey('nfcb') ??
          tryKey('nfcf') ??
          tryKey('nfcv') ??
          tryKey('isodep') ??
          tryKey('mifare-classic') ??
          tryKey('mifare-ultralight');
      if (id == null || id.isEmpty) return null;
      return id
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(':')
          .toUpperCase();
    } catch (_) {
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // PIN LOGIN
  // ═══════════════════════════════════════════════════════════════
  Future<void> _loginWithPin() async {
    if (_pinInput.length < 4) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      Employee? employee;
      employee = await _findEmployeeByPin(_pinInput);

      if (employee == null && !kIsWeb) {
        final localEmployees = await DatabaseService.instance.getAllEmployees();
        for (final emp in localEmployees) {
          final valid =
          await SecurityService.instance.verifyPin(emp.id, _pinInput);
          if (valid) {
            employee = emp;
            break;
          }
        }
      }

      if (employee == null) throw 'Invalid PIN. Please try again.';

      await _saveLastEmployeeId(employee.id);

      if (_clientMeetingMode) {
        _activeEmployee = employee;
        try {
          await SecurityService.instance.createSession(employee.id);
        } catch (e) {
          debugPrint('⚠️ [ClientMeeting] createSession failed: $e');
        }
        if (!kIsWeb) {
          try {
            LocationTrackingService.instance.startTracking(employee.id);
          } catch (e) {
            debugPrint('⚠️ [ClientMeeting] startTracking failed: $e');
          }
        }
        try {
          await FirebaseFirestore.instance.collection('activity_logs').add({
            'type': 'client_meeting_login',
            'employeeId': employee.id,
            'employee_id': employee.id,
            'employee_name': employee.fullName,
            'email': employee.email,
            'role': employee.position,
            'timestamp': FieldValue.serverTimestamp(),
            'device': kIsWeb ? 'Web Browser' : 'Mobile App',
          });
        } catch (e) {
          debugPrint('⚠️ [ClientMeeting] login audit log failed: $e');
        }
        if (mounted) {
          setState(() {
            _isLoading = false;
            _pinInput = '';
            _errorMessage = null;
            _clientMeetingMode = false;
          });
        }
        debugPrint(
            '✅ [ClientMeeting] PIN verified — empId=${employee.id}, name=${employee.fullName}');
        _goToStep(_LoginStep.clientMeeting);
        return;
      }

      await _openSession(employee);
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().contains('Invalid PIN')
              ? 'Invalid PIN. Please try again.'
              : 'Login error: ${e.toString()}';
          _isLoading = false;
          _pinInput = '';
        });
        _shakeController.forward(from: 0);
      }
    }
  }

  Future<Employee?> _findEmployeeByPin(String pin) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('employees')
          .where('pin', isEqualTo: pin)
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;
      final employee = _docToEmployee(snap.docs.first);
      if (!kIsWeb) {
        try {
          await DatabaseService.instance.insertEmployee(employee);
        } catch (_) {}
      }
      return employee;
    } catch (e) {
      debugPrint('_findEmployeeByPin error: $e');
      return null;
    }
  }

  Future<Employee?> _loadEmployeeById(String empId) async {
    if (empId.isEmpty) return null;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('employees')
          .doc(empId)
          .get();
      if (!doc.exists) return null;
      return _docToEmployee(doc);
    } catch (e) {
      debugPrint('⚠️ _loadEmployeeById($empId) failed: $e');
      return null;
    }
  }

  Employee _docToEmployee(dynamic doc) {
    final Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    final String docId = doc.id as String;
    final firstName = data['firstName'] ?? '';
    final lastName = data['lastName'] ?? '';
    final fullName = data['name'] ?? '$firstName $lastName'.trim();

    return Employee.fromMap({
      'id': docId,
      'employee_id': data['employeeId'] ?? docId,
      'first_name': firstName,
      'last_name': lastName,
      'full_name': fullName,
      'email': data['email'] ?? '',
      'role': data['role'] ?? 'Employee',
      'department': data['role'] ?? data['department'] ?? '',
      'position': data['role'] ?? data['position'] ?? '',
      'phone': data['phone'],
      'photo_path': data['photoPath'],
      'photo_url': data['photoUrl'],
      'face_embedding': data['faceEmbedding'],
      'fingerprint_hash': data['fingerprintHash'],
      'pin_hash': null,
      'pin_salt': null,
      'nfc_tag_id': data['nfcTagId'],
      'is_active': data['status'] == 'active' ? 1 : 0,
      'created_at': (data['createdAt'] as Timestamp?)
          ?.toDate()
          .toIso8601String() ??
          DateTime.now().toIso8601String(),
      'updated_at': (data['updatedAt'] as Timestamp?)
          ?.toDate()
          .toIso8601String() ??
          DateTime.now().toIso8601String(),
    });
  }

  Future<void> _signIntoFirebaseAuth(Employee employee) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('employees')
          .doc(employee.id)
          .get();
      final data = snap.data();
      final email = (data?['email'] as String? ?? '').trim();
      final password = (data?['password'] as String? ?? '').trim();
      if (email.isEmpty || password.isEmpty) {
        debugPrint('Firebase Auth skipped — no email/password.');
        return;
      }
      try {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
            email: email, password: password);
      } catch (signInErr) {
        final code = signInErr is FirebaseAuthException ? signInErr.code : '';
        if (_notFoundCodes.contains(code)) {
          try {
            await FirebaseAuth.instance.createUserWithEmailAndPassword(
                email: email, password: password);
            final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
            if (uid.isNotEmpty) {
              await FirebaseFirestore.instance
                  .collection('employees')
                  .doc(employee.id)
                  .update({'authUid': uid});
            }
          } catch (createErr) {
            debugPrint('Firebase Auth create error: $createErr');
          }
        }
      }
    } catch (e) {
      debugPrint('Firebase Auth outer error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // ✅ OPEN SESSION — BINAGO: pushReplacement (dating pushAndRemoveUntil)
  //    Ito ang nag-a-allow ng back navigation pabalik sa LoginScreen
  // ═══════════════════════════════════════════════════════════════
  Future<void> _openSession(Employee employee) async {
    try {
      _activeEmployee = employee;
      await _saveLastEmployeeId(employee.id);
      await SecurityService.instance.createSession(employee.id);
      if (!kIsWeb) LocationTrackingService.instance.startTracking(employee.id);
      await _signIntoFirebaseAuth(employee);

      try {
        await FirebaseFirestore.instance.collection('activity_logs').add({
          'type': 'login',
          'employeeId': employee.id,
          'employee_id': employee.id,
          'employee_name': employee.fullName,
          'email': employee.email,
          'role': employee.position,
          'arrival_time': Timestamp.fromDate(_arrivalTime),
          'timestamp': FieldValue.serverTimestamp(),
          'device': kIsWeb ? 'Web Browser' : 'Mobile App',
        });
      } catch (logErr) {
        debugPrint('Activity log error: $logErr');
      }

      if (!mounted) return;
      // ✅ BINAGO: pushReplacement para may babalikan kapag Back
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => FingerprintScreen(
            employee: employee,
            arrivalTime: _arrivalTime,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Session error: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _onPinKey(String key) {
    if (_isLoading) return;
    setState(() => _errorMessage = null);
    if (key == 'del') {
      if (_pinInput.isNotEmpty) {
        setState(
                () => _pinInput = _pinInput.substring(0, _pinInput.length - 1));
      }
    } else if (_pinInput.length < 4) {
      setState(() => _pinInput += key);
      if (_pinInput.length == 4) {
        Future.delayed(const Duration(milliseconds: 250), _loginWithPin);
      }
    }
  }

  void _setError(String msg) {
    if (mounted) {
      setState(() {
        _errorMessage = msg;
        _isLoading = false;
        _pinInput = '';
      });
      _shakeController.forward(from: 0);
    }
  }

  void _goToStep(_LoginStep step) {
    if (step == _LoginStep.nfcWait && kIsWeb) {
      _setError('NFC is not available on web. Please use PIN instead.');
      return;
    }
    setState(() {
      _step = step;
      _errorMessage = null;
      _pinInput = '';
      _captureSuccess = false;
    });
    _modalController.forward(from: 0);
    if (step == _LoginStep.nfcWait) _startNfcSession();
    if (step == _LoginStep.clientMeeting) {
      _useFrontCamera = true;
      _startCameraSession();
      _startClockTimer();
      _startLocationTracking();
    }
  }

  void _goBack() {
    if (_step == _LoginStep.selectMethod) {
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => const LandingScreen()));
    } else {
      if (_step == _LoginStep.nfcWait && !kIsWeb) {
        try {
          NfcManager.instance.stopSession();
        } catch (_) {}
      }
      if (_step == _LoginStep.clientMeeting) {
        _clockTimer?.cancel();
        _successCloseTimer?.cancel();
        _releaseCamera();
        _stopLocationTracking();
        _useFrontCamera = true;
      }
      _modalController.reverse().then((_) {
        if (mounted) {
          setState(() {
            _step = _LoginStep.selectMethod;
            _errorMessage = null;
            _pinInput = '';
            _captureSuccess = false;
            _clientMeetingMode = false;
          });
        }
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // ✅ CLIENT MEETING
  //    May naka-login → CAMERA AGAD
  //    Walang naka-login → EMPLOYEE PICKER (piliin ang pangalan)
  // ═══════════════════════════════════════════════════════════════
  Future<void> _onClientMeetingLogin() async {
    if (mounted) setState(() => _isLoading = true);

    Employee? resolved;

    // 1. In-memory
    if (_activeEmployee != null) {
      resolved = _activeEmployee;
      debugPrint('✅ [ClientMeeting] Using in-memory employee: ${resolved!.id}');
    }

    // 2. SecurityService session
    if (resolved == null) {
      try {
        final secId = await SecurityService.instance.getCurrentEmployeeId();
        if (secId != null && secId.isNotEmpty) {
          resolved = await _loadEmployeeById(secId);
          if (resolved != null) {
            debugPrint(
                '✅ [ClientMeeting] Resolved from SecurityService: $secId');
          }
        }
      } catch (e) {
        debugPrint('⚠️ [ClientMeeting] SecurityService lookup failed: $e');
      }
    }

    // 3. FirebaseAuth → Firestore
    if (resolved == null) {
      final authUser = FirebaseAuth.instance.currentUser;
      if (authUser != null) {
        try {
          final snap = await FirebaseFirestore.instance
              .collection('employees')
              .where('authUid', isEqualTo: authUser.uid)
              .limit(1)
              .get();

          if (snap.docs.isNotEmpty) {
            resolved = _docToEmployee(snap.docs.first);
            debugPrint(
                '✅ [ClientMeeting] Resolved from authUid: ${resolved.id}');
          } else if (authUser.email != null) {
            final emailSnap = await FirebaseFirestore.instance
                .collection('employees')
                .where('email', isEqualTo: authUser.email!.toLowerCase())
                .limit(1)
                .get();
            if (emailSnap.docs.isNotEmpty) {
              resolved = _docToEmployee(emailSnap.docs.first);
              debugPrint(
                  '✅ [ClientMeeting] Resolved from email: ${resolved.id}');
            }
          }
        } catch (e) {
          debugPrint('⚠️ [ClientMeeting] FirebaseAuth lookup failed: $e');
        }
      }
    }

    // 4. SharedPreferences — huling naka-login
    if (resolved == null) {
      try {
        final lastId = await _getLastEmployeeId();
        if (lastId != null && lastId.isNotEmpty) {
          resolved = await _loadEmployeeById(lastId);
          if (resolved != null) {
            debugPrint(
                '✅ [ClientMeeting] Resolved from SharedPreferences: $lastId');
          }
        }
      } catch (e) {
        debugPrint('⚠️ [ClientMeeting] SharedPreferences lookup failed: $e');
      }
    }

    // ❌ WALANG EMPLOYEE → IPAKITA ANG EMPLOYEE PICKER
    if (resolved == null) {
      debugPrint('📋 [ClientMeeting] No employee — showing picker.');
      if (!mounted) return;
      setState(() => _isLoading = false);
      await _showEmployeePicker();
      return;
    }

    // ✅ MAY EMPLOYEE — setup session, camera agad
    await _startClientMeetingFor(resolved);
  }

  // ✅ Common helper — setup session at buksan camera para sa isang employee
  Future<void> _startClientMeetingFor(Employee employee) async {
    _activeEmployee = employee;
    try {
      await SecurityService.instance.createSession(employee.id);
    } catch (e) {
      debugPrint('⚠️ [ClientMeeting] createSession failed: $e');
    }
    if (!kIsWeb) {
      try {
        LocationTrackingService.instance.startTracking(employee.id);
      } catch (e) {
        debugPrint('⚠️ [ClientMeeting] startTracking failed: $e');
      }
    }
    try {
      await FirebaseFirestore.instance.collection('activity_logs').add({
        'type': 'client_meeting_login',
        'employeeId': employee.id,
        'employee_id': employee.id,
        'employee_name': employee.fullName,
        'email': employee.email,
        'role': employee.position,
        'timestamp': FieldValue.serverTimestamp(),
        'device': kIsWeb ? 'Web Browser' : 'Mobile App',
      });
    } catch (e) {
      debugPrint('⚠️ [ClientMeeting] audit log failed: $e');
    }

    debugPrint(
        '✅ [ClientMeeting] Employee resolved — ${employee.fullName} (${employee.id})');

    if (!mounted) return;
    setState(() => _isLoading = false);
    _goToStep(_LoginStep.clientMeeting);
  }

  // ✅ EMPLOYEE PICKER — listahan ng lahat ng active employees
  Future<void> _showEmployeePicker() async {
    List<Employee> employees = [];

    try {
      final snap = await FirebaseFirestore.instance
          .collection('employees')
          .where('status', isEqualTo: 'active')
          .get();
      employees = snap.docs.map((d) => _docToEmployee(d)).toList();
      employees.sort((a, b) =>
          a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));
    } catch (e) {
      debugPrint('⚠️ Failed to fetch employees: $e');
    }

    if (!mounted) return;

    // Walang laman ang employees → ipakita ang fallback dialog
    if (employees.isEmpty) {
      _showNoEmployeesDialog();
      return;
    }

    final selected = await showModalBottomSheet<Employee>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(ctx).size.height * 0.78,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF8A00), Color(0xFFF54900)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.person_search_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Select Employee',
                            style: TextStyle(
                              color: Color(0xFF1F2937),
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Piliin ang iyong pangalan para sa Client Meeting',
                            style: TextStyle(
                              color: Color(0xFF6B7280),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  itemCount: employees.length,
                  separatorBuilder: (_, __) =>
                  const Divider(height: 1, indent: 70),
                  itemBuilder: (_, i) {
                    final emp = employees[i];
                    final nameParts = emp.fullName.trim().split(' ');
                    final initials = nameParts.length >= 2
                        ? '${nameParts[0][0]}${nameParts[1][0]}'.toUpperCase()
                        : (nameParts.isNotEmpty && nameParts[0].isNotEmpty
                        ? nameParts[0][0].toUpperCase()
                        : '?');
                    final empIdDisplay =
                    emp.employeeId.isNotEmpty ? emp.employeeId : emp.id;
                    return ListTile(
                      onTap: () => Navigator.of(ctx).pop(emp),
                      leading: CircleAvatar(
                        radius: 22,
                        backgroundColor:
                        const Color(0xFFF97316).withValues(alpha: 0.15),
                        child: Text(
                          initials,
                          style: const TextStyle(
                            color: Color(0xFFF97316),
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      title: Text(
                        emp.fullName,
                        style: const TextStyle(
                          color: Color(0xFF1F2937),
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        'ID: $empIdDisplay'
                            '${emp.position.isNotEmpty ? " • ${emp.position}" : ""}',
                        style: const TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 12,
                        ),
                      ),
                      trailing: const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 14,
                        color: Color(0xFF9CA3AF),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );

    if (selected == null) {
      debugPrint('ℹ️ [ClientMeeting] Picker cancelled.');
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    // ✅ I-save sa SharedPreferences para susunod na pindot, diretso na
    await _saveLastEmployeeId(selected.id);

    // ✅ Simulan ang client meeting para sa piniling employee
    await _startClientMeetingFor(selected);
  }

  // ✅ Fallback dialog kung walang employees sa Firestore
  void _showNoEmployeesDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        backgroundColor: Colors.white,
        title: const Text(
          'No Employees Found',
          style: TextStyle(
            color: Color(0xFF1F2937),
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: const Text(
          'Walang aktibong employees sa database. Paki-contact ang Admin.',
          style: TextStyle(color: Color(0xFF4B5563), fontSize: 14),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF97316),
              foregroundColor: Colors.white,
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _releaseCamera() async {
    final controller = _cameraController;
    _cameraController = null;
    if (controller != null) {
      try {
        await controller.dispose();
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  Future<void> _startCameraSession() async {
    await _releaseCamera();
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _setError(kIsWeb
            ? 'No camera detected. Please allow camera access in your browser.'
            : 'No camera found on this device.');
        return;
      }
      final selected = cameras.firstWhere(
            (c) =>
        c.lensDirection ==
            (_useFrontCamera
                ? CameraLensDirection.front
                : CameraLensDirection.back),
        orElse: () => cameras.first,
      );
      _cameraController = CameraController(
        selected,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await _cameraController!.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Camera init error: $e');
      _setError(kIsWeb
          ? 'Could not start camera. Please allow camera access and try again.'
          : 'Could not start camera. Check camera permission.');
    }
  }

  Future<void> _switchCamera() async {
    if (_isCapturing) return;
    setState(() {
      _useFrontCamera = !_useFrontCamera;
    });
    await _startCameraSession();
  }

  void _startClockTimer() {
    _clockTimer?.cancel();
    _now = DateTime.now();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  // ═══════════════════════════════════════════════════════════════
  // 📸 CAPTURE PHOTO — may guard laban sa walang employee
  // ═══════════════════════════════════════════════════════════════
  Future<void> _capturePhoto() async {
    final controller = _cameraController;
    if (controller == null ||
        !controller.value.isInitialized ||
        _isCapturing) {
      return;
    }

    // ✅ GUARD — bawal mag-capture kung walang employee
    if (_activeEmployee == null || _employeeId == null) {
      if (mounted) {
        setState(() => _isCapturing = false);
        _setError(
            'Walang naka-login na employee. Mag-login muna gamit ang PIN o Key Fob.');
      }
      return;
    }

    setState(() {
      _isCapturing = true;
      _errorMessage = null;
    });

    try {
      final ok = await _ensureLocationPermission();
      if (ok) {
        try {
          final freshPos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.best,
            timeLimit: const Duration(seconds: 10),
          );
          await _updatePosition(freshPos);
        } catch (e) {
          debugPrint('⚠️ Fresh position failed: $e');
        }
      }

      final photo = await controller.takePicture();
      debugPrint('📸 Client meeting photo: ${photo.path}');
      debugPrint('📍 Location at capture: $_currentPlaceName');

      await _saveClientMeetingLog(photoPath: photo.path);

      _clockTimer?.cancel();
      _stopLocationTracking();
      await _releaseCamera();
      if (!mounted) return;
      setState(() {
        _isCapturing = false;
        _captureSuccess = true;
      });
      _successCloseTimer?.cancel();
      _successCloseTimer = Timer(const Duration(seconds: 2), () {
        if (mounted && _step == _LoginStep.clientMeeting && _captureSuccess) {
          _goBack();
        }
      });
    } catch (e) {
      debugPrint('Client meeting capture error: $e');
      if (mounted) setState(() => _isCapturing = false);
      _setError(e.toString().replaceAll('Exception: ', ''));
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // 💾 SAVE CLIENT MEETING — tunay na Employee ID + Name
  // ═══════════════════════════════════════════════════════════════
  Future<void> _saveClientMeetingLog({required String photoPath}) async {
    String empId = _employeeId ?? '';
    String empName = _employeeName;
    String empEmail = _employeeEmail;

    // Fallback 1: SecurityService session
    if (empId.isEmpty) {
      try {
        final secId = await SecurityService.instance.getCurrentEmployeeId();
        if (secId != null && secId.isNotEmpty) {
          empId = secId;
          final emp = await _loadEmployeeById(secId);
          if (emp != null) {
            empName = emp.fullName;
            empEmail = emp.email;
          }
          debugPrint('🔑 Resolved empId from SecurityService: $empId');
        }
      } catch (e) {
        debugPrint('⚠️ SecurityService lookup failed: $e');
      }
    }

    // Fallback 2: SharedPreferences — huling naka-login
    if (empId.isEmpty) {
      try {
        final lastId = await _getLastEmployeeId();
        if (lastId != null && lastId.isNotEmpty) {
          empId = lastId;
          final emp = await _loadEmployeeById(lastId);
          if (emp != null) {
            empName = emp.fullName;
            empEmail = emp.email;
          }
          debugPrint('🔑 Resolved empId from SharedPreferences: $empId');
        }
      } catch (e) {
        debugPrint('⚠️ SharedPreferences lookup failed: $e');
      }
    }

    // Fallback 3: FirebaseAuth currentUser → Firestore lookup
    if (empId.isEmpty) {
      final authUser = FirebaseAuth.instance.currentUser;
      if (authUser != null) {
        try {
          final snap = await FirebaseFirestore.instance
              .collection('employees')
              .where('authUid', isEqualTo: authUser.uid)
              .limit(1)
              .get();
          if (snap.docs.isNotEmpty) {
            final emp = _docToEmployee(snap.docs.first);
            empId = emp.employeeId.isNotEmpty ? emp.employeeId : emp.id;
            empName = emp.fullName;
            empEmail = emp.email;
            debugPrint('🔑 Resolved empId via authUid: $empId');
          } else if (authUser.email != null) {
            final emailSnap = await FirebaseFirestore.instance
                .collection('employees')
                .where('email', isEqualTo: authUser.email!.toLowerCase())
                .limit(1)
                .get();
            if (emailSnap.docs.isNotEmpty) {
              final emp = _docToEmployee(emailSnap.docs.first);
              empId = emp.employeeId.isNotEmpty ? emp.employeeId : emp.id;
              empName = emp.fullName;
              empEmail = emp.email;
              debugPrint('🔑 Resolved empId via email: $empId');
            }
          }
        } catch (e) {
          debugPrint('⚠️ FirebaseAuth → Firestore lookup failed: $e');
        }
      }
    }

    // ❌ STRICT — walang guest. Kung wala talaga, i-throw.
    if (empId.isEmpty) {
      debugPrint('❌ Client meeting save BLOCKED — no employee identity.');
      throw 'Walang naka-login na employee. Mag-login muna gamit ang PIN o Key Fob bago mag-Client Meeting.';
    }

    // Kunin ang name/email kung kulang pa
    if (empName == 'Unknown' || empEmail.isEmpty) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('employees')
            .doc(empId)
            .get();
        if (doc.exists) {
          final d = doc.data()!;
          final fn = (d['firstName'] ?? '').toString();
          final ln = (d['lastName'] ?? '').toString();
          empName = (d['name'] ?? '$fn $ln').toString().trim();
          empEmail = (d['email'] ?? '').toString();
        }
      } catch (e) {
        debugPrint('⚠️ Employee name lookup failed: $e');
      }
    }

    debugPrint('═══════════════════════════════════════════');
    debugPrint('📸 SAVING CLIENT MEETING');
    debugPrint('   empId    : "$empId"');
    debugPrint('   empName  : "$empName"');
    debugPrint('   empEmail : "$empEmail"');
    debugPrint('   location : "$_currentPlaceName"');
    debugPrint('   photo    : $photoPath');
    debugPrint('═══════════════════════════════════════════');

    final now = DateTime.now();
    final dateStr = '${now.year}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final timeStr = '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';

    final payload = <String, dynamic>{
      'employee_id': empId,
      'employeeId': empId,
      'employee_name': empName,
      'employee_email': empEmail,
      'type': 'client_meeting',
      'action': 'Client Meeting Clock In',
      'details': 'Client meeting — $_currentPlaceName',
      'description': 'Client meeting at $_currentPlaceName',
      'remarks': 'client_meeting',
      'date': dateStr,
      'time': timeStr,
      'photo_path': photoPath,
      'location_name': _currentPlaceName,
      'latitude': _currentLatitude,
      'longitude': _currentLongitude,
      'location_captured_at': _locationTimestamp != null
          ? Timestamp.fromDate(_locationTimestamp!)
          : null,
      'has_location': _currentLatitude != null && _currentLongitude != null,
      'device': kIsWeb ? 'Web Browser' : 'Mobile App',
      'platform': kIsWeb ? 'web' : 'mobile',
      'zone_type': 'client_meeting',
      'status': 'pending_hr_approval',
      'payrollStatus': 'Pending',
      'timestamp': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    };

    final fs = FirebaseFirestore.instance;

    await fs.collection('attendance_logs').add(payload);
    debugPrint('✅ Saved → attendance_logs');

    await fs.collection('activity_logs').add(payload);
    debugPrint('✅ Saved → activity_logs');

    await fs.collection('activity logs').add(payload);
    debugPrint('✅ Saved → activity logs');

    debugPrint('🎉 Client meeting saved successfully!');
  }

  String _formatTimestamp(DateTime dt) {
    final mm = dt.month.toString().padLeft(2, '0');
    final dd = dt.day.toString().padLeft(2, '0');
    final yyyy = dt.year.toString();
    int hour12 = dt.hour % 12;
    if (hour12 == 0) hour12 = 12;
    final hh = hour12.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$mm/$dd/$yyyy - $hh:$min $ampm';
  }

  String _formatClockTime(DateTime dt) {
    int h = dt.hour % 12;
    if (h == 0) h = 12;
    final hh = h.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hh:$mm:$ss $ampm';
  }

  String _formatClockDate(DateTime dt) {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${days[dt.weekday - 1]}, ${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  // ═══════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = _ThemeColors(isDark);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goBack();
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 1024;
          if (!isWide) {
            return Scaffold(
              backgroundColor: tc.bgMid,
              body: _buildContent(tc),
            );
          }
          return Scaffold(
            backgroundColor: const Color(0xFF0A0A0F),
            body: Stack(
              children: [
                _buildWebLayout(tc),
                if (_step != _LoginStep.selectMethod) _buildDesktopModal(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildWebLayout(_ThemeColors tc) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0A0A0F),
            Color(0xFF0D0B08),
            Color(0xFF1A0F05),
          ],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            _buildWebTopNav(),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildWebSidebar(),
                  Expanded(child: _buildWebMainContent(tc)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebTopNav() {
    return Container(
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFF8A00), Color(0xFFF54900)],
              ),
              borderRadius: BorderRadius.circular(11),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF8A00).withValues(alpha: 0.4),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(Icons.access_time_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          const Text(
            'R.A.C.O.M.A.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFFF8A00).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: const Color(0xFFFF8A00).withValues(alpha: 0.4)),
            ),
            child: const Text(
              'v1.0.3',
              style: TextStyle(
                color: Color(0xFFFF8A00),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _formatClockTime(_now),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _formatClockDate(_now),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWebSidebar() {
    return Container(
      width: 280,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'AUTHENTICATION FLOW',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 24),
          _buildStepItem(1, 'Initial Login', 'Key Fob or PIN', isActive: true),
          _buildStepConnector(),
          _buildStepItem(2, 'Confirm Identity', 'Secondary verification',
              isActive: false),
          _buildStepConnector(),
          _buildStepItem(3, 'Clock In', 'Attendance recorded', isActive: false),
        ],
      ),
    );
  }

  Widget _buildStepItem(int n, String title, String subtitle,
      {required bool isActive}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: isActive
                ? const LinearGradient(
              colors: [Color(0xFFFF8A00), Color(0xFFF54900)],
            )
                : null,
            color: isActive ? null : Colors.white.withValues(alpha: 0.05),
            shape: BoxShape.circle,
            border: isActive
                ? null
                : Border.all(color: Colors.white.withValues(alpha: 0.1)),
            boxShadow: isActive
                ? [
              BoxShadow(
                color: const Color(0xFFFF8A00).withValues(alpha: 0.4),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ]
                : null,
          ),
          child: Text(
            '$n',
            style: TextStyle(
              color:
              isActive ? Colors.white : Colors.white.withValues(alpha: 0.4),
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: isActive
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.55),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStepConnector() {
    return Container(
      margin: const EdgeInsets.only(left: 15, top: 6, bottom: 6),
      width: 2,
      height: 24,
      color: Colors.white.withValues(alpha: 0.08),
    );
  }

  Widget _buildWebMainContent(_ThemeColors tc) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Auth & Clock In',
            style: TextStyle(
              color: Colors.white,
              fontSize: 42,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.4,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Choose your verification method to begin your shift.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 40),
          SizedBox(
            height: 320,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _WebOptionCard(
                    icon: Icons.contactless_rounded,
                    title: 'Key Fob',
                    desc:
                    'Tap your fob on the NFC reader to authenticate instantly.',
                    enabled: !kIsWeb && _nfcAvailable,
                    onTap: () => _goToStep(_LoginStep.nfcWait),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: _WebOptionCard(
                    icon: Icons.key_rounded,
                    title: 'Use PIN',
                    desc:
                    'Enter your 4-digit security PIN to verify your identity.',
                    enabled: true,
                    onTap: () => _goToStep(_LoginStep.pinEntry),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Text(
                'Having trouble? ',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 13,
                ),
              ),
              GestureDetector(
                onTap: () {},
                child: const Text(
                  'Contact administrator',
                  style: TextStyle(
                    color: Color(0xFFFF8A00),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                    decorationColor: Color(0xFFFF8A00),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopModal() {
    Widget card;
    switch (_step) {
      case _LoginStep.pinEntry:
        card = _buildPinModalCard();
        break;
      case _LoginStep.nfcWait:
        card = _buildNfcModalCard();
        break;
      case _LoginStep.clientMeeting:
        card = _buildClientMeetingModalCard();
        break;
      case _LoginStep.selectMethod:
        return const SizedBox.shrink();
    }
    return Positioned.fill(
      child: FadeTransition(
        opacity: _modalOpacityAnim,
        child: Container(
          color: _scrim,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Center(
            child: SingleChildScrollView(
              child: ScaleTransition(scale: _modalScaleAnim, child: card),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(_ThemeColors tc) {
    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [tc.bgTop, tc.bgMid, tc.bgBottom],
              stops: const [0.0, 0.6, 1.0],
            ),
          ),
          child: FadeTransition(
            opacity: _fadeAnim,
            child: Column(children: [
              _buildOrangeHeader(),
              Expanded(child: _buildSelectMethodStep(tc)),
            ]),
          ),
        ),
        if (_step != _LoginStep.selectMethod) _buildModalOverlay(),
      ],
    );
  }

  Widget _buildModalOverlay() {
    Widget card;
    switch (_step) {
      case _LoginStep.pinEntry:
        card = _buildPinModalCard();
        break;
      case _LoginStep.nfcWait:
        card = _buildNfcModalCard();
        break;
      case _LoginStep.clientMeeting:
        card = _buildClientMeetingModalCard();
        break;
      case _LoginStep.selectMethod:
        card = const SizedBox.shrink();
        break;
    }
    return Positioned.fill(
      child: FadeTransition(
        opacity: _modalOpacityAnim,
        child: Container(
          color: _scrim,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Center(
            child: ScaleTransition(scale: _modalScaleAnim, child: card),
          ),
        ),
      ),
    );
  }

  Widget _buildOrangeHeader() {
    return SafeArea(
      bottom: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          double scale = constraints.maxWidth.isFinite
              ? constraints.maxWidth / _kHeaderDesignFrameWidth
              : 1.0;
          if (scale <= 0) scale = 1.0;
          if (scale > 1.0) scale = 1.0;

          final outerRadius = _kHeaderRadius * scale;
          final borderW = _kHeaderBorderBottom * scale;
          final innerRadius = (outerRadius - borderW).clamp(0.0, outerRadius);
          return Container(
            width: double.infinity,
            height: _kHeaderH * scale,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: _headerBorder,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(outerRadius),
                bottomRight: Radius.circular(outerRadius),
              ),
            ),
            padding: EdgeInsets.only(bottom: borderW),
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [_headerStart, _headerMid, _headerEnd],
                  stops: [0.0001, 0.3318, 1.0],
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(innerRadius),
                  bottomRight: Radius.circular(innerRadius),
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    left: _kBackLeft * scale,
                    top: _kBackTop * scale,
                    child: GestureDetector(
                      onTap: _goBack,
                      behavior: HitTestBehavior.opaque,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: _kBackIconSize * scale,
                            height: _kBackIconSize * scale,
                            child: CustomPaint(painter: _BackArrowPainter()),
                          ),
                          SizedBox(width: 2 * scale),
                          Text(
                            'Back',
                            style: TextStyle(
                              color: _white,
                              fontSize: 16 * scale,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: _kTitleLeft * scale,
                    top: _kTitleTop * scale,
                    child: Text(
                      'Auth & Clock In',
                      style: TextStyle(
                        color: _white,
                        fontSize: _kTitleFontSize * scale,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                        height: 1.0,
                      ),
                    ),
                  ),
                  Positioned(
                    left: _kSubtitleLeft * scale,
                    top: _kSubtitleTop * scale,
                    child: Text(
                      'Select your initial verification method',
                      style: TextStyle(
                        color: _white,
                        fontSize: _kSubtitleFontSize * scale,
                        fontWeight: FontWeight.w400,
                        height: 1.0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSelectMethodStep(_ThemeColors tc) {
    return LayoutBuilder(
      builder: (context, constraints) {
        double scale = constraints.maxWidth.isFinite
            ? constraints.maxWidth / _kHeaderDesignFrameWidth
            : 1.0;
        if (scale <= 0) scale = 1.0;
        if (scale > 1.0) scale = 1.0;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(children: [
            _buildOverlapCard(
              tc: tc,
              stepLabel: 'Step 1: Initial Login',
              overlap: 64 * scale,
              child: Column(children: [
                Row(children: [
                  Expanded(
                    child: _MethodButton(
                      icon: Icons.contactless_rounded,
                      label: 'Key Fob',
                      enabled: !kIsWeb && _nfcAvailable,
                      onTap: () => _goToStep(_LoginStep.nfcWait),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MethodButton(
                      icon: Icons.key_rounded,
                      label: 'Use PIN',
                      onTap: () => _goToStep(_LoginStep.pinEntry),
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                _buildClientMeetingButton(),
              ]),
            ),
            if (kIsWeb) ...[
              const SizedBox(height: 16),
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: tc.infoBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: tc.infoBorder, width: 1.5),
                ),
                child: Row(children: [
                  Icon(Icons.info_outline_rounded,
                      color: tc.infoText, size: 16),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'NFC / Key Fob is not supported by web browsers. '
                          'Please use PIN or Client Meeting login, or download the APK.',
                      style: TextStyle(
                          color: tc.infoText, fontSize: 12, height: 1.4),
                    ),
                  ),
                ]),
              ),
            ] else if (!_nfcAvailable) ...[
              const SizedBox(height: 16),
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: tc.infoBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: tc.infoBorder, width: 1.5),
                ),
                child: Row(children: [
                  Icon(Icons.info_outline_rounded,
                      color: tc.infoText, size: 16),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'NFC not available on this device. Use PIN to sign in.',
                      style: TextStyle(color: tc.infoText, fontSize: 12),
                    ),
                  ),
                ]),
              ),
            ],
          ]),
        );
      },
    );
  }

  Widget _buildClientMeetingButton() {
    return GestureDetector(
      onTap: _isLoading ? null : _onClientMeetingLogin,
      child: Container(
        width: double.infinity,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _orange, width: 1),
        ),
        child: _isLoading
            ? const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
              color: _orange, strokeWidth: 2),
        )
            : const Text(
          'Client Meeting LogIn',
          style: TextStyle(
              color: _orange, fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  Widget _buildOverlapCard({
    required _ThemeColors tc,
    required String stepLabel,
    required Widget child,
    double overlap = 30,
  }) {
    return Transform.translate(
      offset: Offset(0, -overlap),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: tc.cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: tc.cardBorder, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: _headerEnd.withValues(alpha: 0.08),
              blurRadius: 25,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Text(
                stepLabel,
                style: TextStyle(
                  color: tc.textDark,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            const SizedBox(height: 20),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildPinModalCard() {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 380),
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_modalGradTop, _modalGradMid, _modalGradEnd],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white, width: 1.15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 12.5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child:
            const Icon(Icons.key_rounded, color: _modalGradTop, size: 32),
          ),
          const SizedBox(height: 20),
          const Text('Enter PIN',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 10),
          Text(
            'Please enter your 4-digit PIN to begin',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.92), fontSize: 14),
          ),
          const SizedBox(height: 24),
          AnimatedBuilder(
            animation: _shakeAnim,
            builder: (_, child) => Transform.translate(
              offset: Offset(
                  _shakeAnim.value *
                      ((_shakeController.value * 10).round().isEven ? 1 : -1),
                  0),
              child: child,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (i) {
                final filled = i < _pinInput.length;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.35),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 28),
          Column(
            children: [
              _pinPadRow(['1', '2', '3']),
              const SizedBox(height: 12),
              _pinPadRow(['4', '5', '6']),
              const SizedBox(height: 12),
              _pinPadRow(['7', '8', '9']),
              const SizedBox(height: 12),
              _pinPadRow(['', '0', 'del']),
            ],
          ),
          const SizedBox(height: 16),
          _buildFeedback(onDark: true),
          const SizedBox(height: 8),
          _buildCancelButton(),
        ],
      ),
    );
  }

  Widget _pinPadRow(List<String> keys) {
    return Row(
      children: List.generate(keys.length, (colIdx) {
        final key = keys[colIdx];
        if (key.isEmpty) return const Expanded(child: SizedBox());
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              left: colIdx > 0 ? 10 : 0,
              right: colIdx < keys.length - 1 ? 10 : 0,
            ),
            child: _PinKeyWhite(label: key, onTap: () => _onPinKey(key)),
          ),
        );
      }),
    );
  }

  Widget _buildNfcModalCard() {
    if (kIsWeb) {
      return _buildUnsupportedWebCard(
        icon: Icons.contactless_rounded,
        title: 'NFC Not Supported',
        message: 'NFC / Key Fob login is not available on web browsers.\n\n'
            'Please use PIN or Client Meeting login instead.',
      );
    }
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 380),
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_modalGradTop, _modalGradMid, _modalGradEnd],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white, width: 1.15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 12.5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _nfcPulseAnim,
            builder: (_, __) => Transform.scale(
              scale: _isLoading ? 1.0 : _nfcPulseAnim.value,
              child: Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: _isLoading
                    ? const CircularProgressIndicator(
                    color: _modalGradTop, strokeWidth: 2.5)
                    : const Icon(Icons.contactless_rounded,
                    color: _modalGradTop, size: 48),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text('Tap Key Fob',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 10),
          Text(
            _isLoading
                ? 'Reading keyfob…'
                : 'Please tap your key fob on the reader...',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85), fontSize: 14),
          ),
          const SizedBox(height: 24),
          if (_errorMessage != null) ...[
            _buildFeedback(onDark: true),
            const SizedBox(height: 12),
          ],
          _buildCancelButton(),
        ],
      ),
    );
  }

  Widget _buildUnsupportedWebCard({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 380),
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_modalGradTop, _modalGradMid, _modalGradEnd],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white, width: 1.15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 12.5),
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
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: _modalGradTop, size: 40),
          ),
          const SizedBox(height: 20),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 13,
                  height: 1.5)),
          const SizedBox(height: 24),
          _buildCancelButton(),
        ],
      ),
    );
  }

  Widget _buildClientMeetingModalCard() {
    if (_captureSuccess) return _buildClientMeetingSuccessCard();
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 380),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_modalGradTop, _modalGradMid, _modalGradEnd],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white, width: 1.15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 12.5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Client Meeting Check-In',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Snap a photo to log your visit',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
          const SizedBox(height: 16),
          _buildCameraPreviewBox(),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildShutterButton(),
              const SizedBox(width: 20),
              _buildCameraSwitchButton(),
            ],
          ),
          const SizedBox(height: 16),
          if (_errorMessage != null) ...[
            _buildFeedback(onDark: true),
            const SizedBox(height: 8),
          ],
          _buildCancelButton(),
        ],
      ),
    );
  }

  Widget _buildCameraSwitchButton() {
    return GestureDetector(
      onTap: _switchCamera,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white, width: 1),
        ),
        child: Row(
          children: [
            const Icon(Icons.switch_camera, color: Colors.white, size: 18),
            const SizedBox(width: 4),
            Text(_useFrontCamera ? 'Front' : 'Back',
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraPreviewBox() {
    return AspectRatio(
      aspectRatio: 314 / 456,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFDBA74), width: 1.5),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14.5),
          child: Container(
            color: _cmPreviewBg,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_cameraController != null &&
                    _cameraController!.value.isInitialized)
                  _buildCoveredCameraPreview()
                else
                  const Center(
                    child: CircularProgressIndicator(
                        color: Colors.white54, strokeWidth: 2.5),
                  ),
                if (_isCapturing)
                  Container(color: Colors.black.withValues(alpha: 0.25)),
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 20,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.location_on_rounded,
                              color: Color(0xFFC4FF0A), size: 14),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              _locationDisplay,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black87,
                                      blurRadius: 6,
                                    ),
                                  ]),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _formatTimestamp(_now),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            shadows: [
                              Shadow(
                                color: Colors.black87,
                                blurRadius: 6,
                              ),
                            ]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCoveredCameraPreview() {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        child:
        CircularProgressIndicator(color: Colors.white54, strokeWidth: 2.5),
      );
    }
    final previewSize = controller.value.previewSize;
    if (previewSize == null) return CameraPreview(controller);
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: previewSize.height,
        height: previewSize.width,
        child: CameraPreview(controller),
      ),
    );
  }

  Widget _buildShutterButton() {
    return GestureDetector(
      onTap: _isCapturing ? null : _capturePhoto,
      child: AnimatedBuilder(
        animation: _nfcPulseAnim,
        builder: (_, __) => Transform.scale(
          scale: _isCapturing ? 1.0 : _nfcPulseAnim.value,
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _cmShutterOuter,
              boxShadow: [
                BoxShadow(
                    color: _cmShutterGlow.withValues(alpha: 0.8),
                    blurRadius: 15),
              ],
            ),
            alignment: Alignment.center,
            child: _isCapturing
                ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2.5),
            )
                : Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _cmShutterInner,
                boxShadow: [
                  BoxShadow(
                      color: _cmShutterGlow.withValues(alpha: 0.8),
                      blurRadius: 15),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildClientMeetingSuccessCard() {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 380),
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_modalGradTop, _modalGradMid, _modalGradEnd],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white, width: 1.15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 12.5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.check_circle_rounded,
                color: _modalGradTop, size: 32),
          ),
          const SizedBox(height: 20),
          const Text('Successfully Clock In',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 10),
          Text(
            'Just wait for the HR Approvement...',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.92), fontSize: 14),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildCancelButton() {
    return GestureDetector(
      onTap: _goBack,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFFA500), width: 1.15),
        ),
        child: const Text('Cancel',
            style: TextStyle(
                color: Color(0xFFFFA500),
                fontSize: 14,
                fontWeight: FontWeight.w500)),
      ),
    );
  }

  Widget _buildFeedback({bool onDark = false}) {
    if (_isLoading) {
      return SizedBox(
        height: 36,
        child: Center(
          child: CircularProgressIndicator(
              color: onDark ? Colors.white : _orange, strokeWidth: 2.5),
        ),
      );
    }
    if (_errorMessage != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: onDark ? Colors.white.withValues(alpha: 0.15) : _errorBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: onDark
                  ? Colors.white.withValues(alpha: 0.4)
                  : _error.withValues(alpha: 0.35)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline_rounded,
              color: onDark ? Colors.white : _error, size: 16),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              _errorMessage!,
              style: TextStyle(
                  color: onDark ? Colors.white : _error,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ]),
      );
    }
    return const SizedBox(height: 8);
  }
}

// ═══════════════════════════════════════════════════════════════
// WEB OPTION CARD
// ═══════════════════════════════════════════════════════════════
class _WebOptionCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String desc;
  final bool enabled;
  final VoidCallback onTap;

  const _WebOptionCard({
    required this.icon,
    required this.title,
    required this.desc,
    required this.enabled,
    required this.onTap,
  });

  @override
  State<_WebOptionCard> createState() => _WebOptionCardState();
}

class _WebOptionCardState extends State<_WebOptionCard> {
  final ValueNotifier<bool> _hovered = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _pressed = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _hovered.dispose();
    _pressed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;

    return MouseRegion(
      cursor: enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.forbidden,
      onEnter: (_) => _hovered.value = true,
      onExit: (_) => _hovered.value = false,
      child: GestureDetector(
        onTapDown: enabled ? (_) => _pressed.value = true : null,
        onTapUp: enabled
            ? (_) {
          _pressed.value = false;
          widget.onTap();
        }
            : null,
        onTapCancel: enabled ? () => _pressed.value = false : null,
        child: ValueListenableBuilder<bool>(
          valueListenable: _hovered,
          builder: (context, hovered, _) {
            return ValueListenableBuilder<bool>(
              valueListenable: _pressed,
              builder: (context, pressed, __) {
                final active = enabled && (hovered || pressed);
                final scale = pressed ? 0.98 : 1.0;

                return AnimatedScale(
                  duration: const Duration(milliseconds: 140),
                  scale: scale,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: active
                          ? const Color(0xFFFF8A00).withValues(alpha: 0.06)
                          : Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: active
                            ? const Color(0xFFFF8A00)
                            .withValues(alpha: 0.5)
                            : Colors.white.withValues(alpha: 0.08),
                        width: 1.5,
                      ),
                      boxShadow: active
                          ? [
                        BoxShadow(
                          color: const Color(0xFFFF8A00)
                              .withValues(alpha: 0.18),
                          blurRadius: 32,
                          offset: const Offset(0, 12),
                        ),
                      ]
                          : null,
                    ),
                    child: Opacity(
                      opacity: enabled ? 1.0 : 0.45,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFFFF8A00), Color(0xFFF54900)],
                              ),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFFF8A00)
                                      .withValues(alpha: 0.35),
                                  blurRadius: 20,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Icon(widget.icon,
                                color: Colors.white, size: 26),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            widget.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.4,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.desc,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 14,
                              height: 1.5,
                            ),
                          ),
                          const Spacer(),
                          Row(
                            children: [
                              Text(
                                'Select',
                                style: TextStyle(
                                  color: enabled
                                      ? const Color(0xFFFF8A00)
                                      : Colors.white.withValues(alpha: 0.3),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              const SizedBox(width: 6),
                              AnimatedPadding(
                                duration: const Duration(milliseconds: 180),
                                padding: EdgeInsets.only(
                                    left: hovered && enabled ? 4 : 0),
                                child: Icon(
                                  Icons.arrow_forward_rounded,
                                  color: enabled
                                      ? const Color(0xFFFF8A00)
                                      : Colors.white.withValues(alpha: 0.3),
                                  size: 16,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _BackArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.66602 * (size.width / 19.99)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final s = size.width / 19.99;
    Offset p(double x, double y) => Offset(x * s, (y - 5) * s);
    final path = Path()
      ..moveTo(p(12.4951, 14.9941).dx, p(12.4951, 14.9941).dy)
      ..lineTo(p(7.49707, 9.9961).dx, p(7.49707, 9.9961).dy)
      ..lineTo(p(12.4951, 4.99805).dx, p(12.4951, 4.99805).dy);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MethodButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;

  const _MethodButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  @override
  State<_MethodButton> createState() => _MethodButtonState();
}

class _MethodButtonState extends State<_MethodButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressCtrl;
  late Animation<double> _scaleAnim;

  static const Color _orange = Color(0xFFF97316);
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 120));
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.93)
        .animate(CurvedAnimation(parent: _pressCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = _ThemeColors(isDark);

    final button = GestureDetector(
      onTapDown: widget.enabled
          ? (_) {
        _pressCtrl.forward();
        setState(() => _pressed = true);
      }
          : null,
      onTapUp: widget.enabled
          ? (_) {
        _pressCtrl.reverse();
        setState(() => _pressed = false);
        widget.onTap();
      }
          : null,
      onTapCancel: widget.enabled
          ? () {
        _pressCtrl.reverse();
        setState(() => _pressed = false);
      }
          : null,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Opacity(
          opacity: widget.enabled ? 1.0 : 0.45,
          child: AspectRatio(
            aspectRatio: 0.95,
            child: Container(
              decoration: BoxDecoration(
                color: _pressed ? tc.hoverBg : tc.cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _pressed ? _orange : tc.optionBorder,
                  width: 1.5,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: tc.methodIconBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: widget.enabled
                            ? tc.optionBorder
                            : (isDark
                            ? const Color(0xFF3F3F46)
                            : const Color(0xFFE5E5E5)),
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      widget.icon,
                      color: widget.enabled
                          ? _orange
                          : (isDark
                          ? const Color(0xFF666666)
                          : const Color(0xFFBBBBBB)),
                      size: 26,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: widget.enabled
                          ? tc.textDark
                          : (isDark
                          ? const Color(0xFF888888)
                          : const Color(0xFFAAAAAA)),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (!widget.enabled) {
      return Tooltip(
        message: 'NFC / Key Fob is not supported on web browsers',
        child: button,
      );
    }
    return button;
  }
}

class _PinKeyWhite extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const _PinKeyWhite({required this.label, required this.onTap});
  @override
  State<_PinKeyWhite> createState() => _PinKeyWhiteState();
}

class _PinKeyWhiteState extends State<_PinKeyWhite>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressCtrl;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 100));
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.93)
        .animate(CurvedAnimation(parent: _pressCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDel = widget.label == 'del';
    return GestureDetector(
      onTapDown: (_) => _pressCtrl.forward(),
      onTapUp: (_) {
        _pressCtrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _pressCtrl.reverse(),
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF564334), width: 1.15),
          ),
          child: Center(
            child: isDel
                ? const Text('DEL',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF71717A)))
                : Text(widget.label,
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    color: Colors.black)),
          ),
        ),
      ),
    );
  }
}