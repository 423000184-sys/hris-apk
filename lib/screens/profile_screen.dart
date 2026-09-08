// lib/screens/profile_screen.dart
<<<<<<< HEAD
//
// CONVERTED FROM HTML DESIGN:
//   - Orange gradient header, "Profile & Settings" title (no back button —
//     this is a bottom-tab screen, not a pushed route)
//   - Profile card: avatar overlaps the top edge of the card, status dot,
//     name, position (orange text), Employee ID pill badge
//   - "PERSONAL DETAILS" card: Email / Phone / Location rows, each with a
//     gradient icon square, a muted label, and an orange value
//   - "APP SETTINGS" card: Dark Mode + Push Notifications toggle switches
//     (custom-drawn to match the mockup's pill/gradient track), Language row
//   - "ACCOUNT SECURITY" card: biometric enrollment rows, Change Password,
//     Attendance History
//   - "DATA & BACKUP" card: Cloud Backup row
//   - "SECURITY & LEGAL" card: Privacy Policy row
//   - "DANGER ZONE" card: Delete My Account row
//   - Sign Out: light card with a red border, matching the mockup's pill
//
// NOTE: the mockup shows Phone and Location fields that aren't on the
// current `Employee` model yet. They're read defensively via `_dynGet` so
// this compiles today and will pick the real values up automatically once
// those fields exist on the model — until then they show "—".
//
// This screen intentionally uses the mockup's own light palette (white /
// #F8F8F8 cards, #FFA500 borders & value text) rather than the app-wide
// dark `AppColors` palette, the same way the mobile attendance cards do.

=======
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../theme/app_theme.dart';
import '../theme/theme_notifier.dart';
import '../services/database_service.dart';
import '../services/security_service.dart';
import '../services/auth_service.dart';
import '../models/employee.dart';
import 'landing_screen.dart';
import 'attendance_history_screen.dart';

<<<<<<< HEAD
class _Mock {
  static const Color orange = Color(0xFFFFA500);
  static const Color lime = Color(0xFFC4FF0A);
  static const Color red = Color(0xFFFB2C36);
  static const Color textMuted = Color(0xFF71717A);
  static const Color cardBg = Color(0xFFF8F8F8);
  static const Color switchTrackOff = Color(0xFF3F3F46);
}

=======
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
class ProfileScreen extends StatefulWidget {
  final Employee? initialEmployee;
  const ProfileScreen({super.key, this.initialEmployee});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Employee? _employee;
  bool _loading = true;
  bool _isSyncing = false;
  bool _isDeleting = false;
<<<<<<< HEAD
  bool _pushEnabled = true;
=======
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
  final _localAuth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final empId = await SecurityService.instance.getCurrentEmployeeId();
    Employee? employee;
    if (empId != null) {
      employee = await DatabaseService.instance.getEmployeeById(empId);
    }
    employee ??= widget.initialEmployee;
    if (mounted) {
      setState(() {
        _employee = employee;
        _loading = false;
      });
    }
  }

  Future<void> _logout() async {
    await AuthService.instance.signOut(employee: _employee);
    await SecurityService.instance.clearSession();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LandingScreen()),
          (_) => false,
    );
  }

  Future<void> _confirmDeleteAccount() async {
    if (_employee == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
<<<<<<< HEAD
        backgroundColor: Colors.white,
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: _Mock.red),
          SizedBox(width: 10),
          Text('Delete Account',
              style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700)),
=======
        backgroundColor: AppColors.card,
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: AppColors.error),
          SizedBox(width: 10),
          Text('Delete Account',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w900)),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
        ]),
        content: const Text(
          'Are you sure you want to permanently delete your account? '
              'This will remove all your data from the local database, '
              'cloud storage, and admin records. This cannot be undone.',
<<<<<<< HEAD
          style: TextStyle(color: _Mock.textMuted, fontSize: 13, height: 1.6),
=======
          style: TextStyle(
              color: AppColors.textSecondary, fontSize: 13, height: 1.6),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
<<<<<<< HEAD
            child: const Text('Cancel', style: TextStyle(color: _Mock.textMuted)),
=======
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textMuted)),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
<<<<<<< HEAD
                backgroundColor: _Mock.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            child: const Text('Delete Permanently',
                style: TextStyle(fontWeight: FontWeight.w700)),
=======
                backgroundColor: AppColors.error,
                foregroundColor: AppColors.textPrimary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4))),
            child: const Text('Delete Permanently',
                style: TextStyle(fontWeight: FontWeight.w800)),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isDeleting = true);
      try {
        await AuthService.instance.deleteAccount(_employee!);
        await SecurityService.instance.clearSession();
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const LandingScreen()),
                (_) => false,
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error deleting account: $e'),
<<<<<<< HEAD
            backgroundColor: _Mock.red,
=======
            backgroundColor: AppColors.error,
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
          ));
        }
      } finally {
        if (mounted) setState(() => _isDeleting = false);
      }
    }
  }

  Future<void> _syncToFirebase() async {
    if (_employee == null || _isSyncing) return;
    setState(() => _isSyncing = true);

    try {
      User? user = AuthService.instance.currentUser;

      if (user == null) {
        final pin = await _promptForPin();
        if (pin == null || pin.length < 4) {
          throw 'Valid 4-digit PIN required to link cloud account';
        }
        final email = _employee!.email;
        final password = pin.padRight(6, '0');
        try {
          await AuthService.instance
              .login(email: email, password: password);
        } catch (e) {
          await AuthService.instance.registerEmployee(
            email: email,
            password: password,
            employee: _employee!,
          );
        }
        user = AuthService.instance.currentUser;
      }

      if (user == null) throw 'Could not authenticate with Firebase';

      final data = _employee!.toMap();
      data['uid'] = user.uid;
      data['last_manual_sync'] = FieldValue.serverTimestamp();

      await FirebaseFirestore.instance
          .collection('employees')
          .doc(user.uid)
          .set(data, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✓ Profile successfully backed up to Cloud!'),
          backgroundColor: AppColors.success,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Sync failed: $e'),
<<<<<<< HEAD
          backgroundColor: _Mock.red,
=======
          backgroundColor: AppColors.error,
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
        ));
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<String?> _promptForPin() async {
    String pinInput = '';
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
<<<<<<< HEAD
        backgroundColor: Colors.white,
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Link Cloud Account',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700)),
=======
        backgroundColor: AppColors.card,
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: const Text('Link Cloud Account',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w900)),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter your 4-digit PIN to secure your cloud backup.',
<<<<<<< HEAD
              style: TextStyle(color: _Mock.textMuted, fontSize: 13, height: 1.5),
=======
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.5),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
            ),
            const SizedBox(height: 16),
            TextField(
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 28,
                  letterSpacing: 10,
<<<<<<< HEAD
                  color: Colors.black,
                  fontWeight: FontWeight.w700),
=======
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w900),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
              onChanged: (v) => pinInput = v,
              decoration: const InputDecoration(
                hintText: '––––',
                counterText: '',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
<<<<<<< HEAD
            child: const Text('Cancel', style: TextStyle(color: _Mock.textMuted)),
=======
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textMuted)),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, pinInput),
            style: ElevatedButton.styleFrom(
<<<<<<< HEAD
                backgroundColor: _Mock.orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            child: const Text('CONFIRM',
                style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1)),
=======
                backgroundColor: AppColors.orange,
                foregroundColor: AppColors.textPrimary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4))),
            child: const Text('CONFIRM',
                style: TextStyle(
                    fontWeight: FontWeight.w800, letterSpacing: 1)),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
          ),
        ],
      ),
    );
  }

  Future<void> _enroll(String type) async {
    if (_employee == null) return;
    bool canCheck = await _localAuth.canCheckBiometrics ||
        await _localAuth.isDeviceSupported();
    if (!canCheck) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Biometrics not available.'),
<<<<<<< HEAD
        backgroundColor: _Mock.red,
=======
        backgroundColor: AppColors.error,
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
      ));
      return;
    }
    try {
      bool authenticated = await _localAuth.authenticate(
        localizedReason: 'Scan to enroll $type',
        options: const AuthenticationOptions(
            biometricOnly: true, stickyAuth: true),
      );
      if (authenticated) {
        await _updateBiometricFlag(type, enrolled: true);
        final updated =
        await DatabaseService.instance.getEmployeeById(_employee!.id);
        if (mounted) {
          setState(() => _employee = updated);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('$type enrolled successfully'),
            backgroundColor: AppColors.success,
          ));
        }
      }
    } catch (e) {
      debugPrint('Enrollment error: $e');
    }
  }

  Future<void> _unenroll(String type) async {
    if (_employee == null) return;
    await _updateBiometricFlag(type, enrolled: false);
    final updated =
    await DatabaseService.instance.getEmployeeById(_employee!.id);
    if (mounted) {
      setState(() => _employee = updated);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$type removed'),
        backgroundColor: AppColors.warning,
      ));
    }
  }

  Future<void> _updateBiometricFlag(String type,
      {required bool enrolled}) async {
    final emp = _employee;
    if (emp == null) return;
    final Employee updatedEmployee;
    if (type == 'Face ID') {
      updatedEmployee =
          emp.copyWith(faceEmbedding: enrolled ? emp.faceEmbedding : null);
    } else if (type == 'Fingerprint') {
      updatedEmployee = emp.copyWith(
          fingerprintHash: enrolled ? emp.fingerprintHash : null);
    } else {
      return;
    }
    await DatabaseService.instance.updateEmployee(updatedEmployee);
  }

<<<<<<< HEAD
  void _comingSoon(String label) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$label — coming soon'),
      backgroundColor: _Mock.textMuted,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(12),
    ));
  }

  // Reads a field off `Employee` that may not exist on the model yet
  // (e.g. phone / location from the mockup) without crashing the build —
  // falls back to `fallback` if the getter throws or returns null.
  String _dynGet(dynamic obj, dynamic Function(dynamic) getter,
      {String fallback = '—'}) {
    if (obj == null) return fallback;
    try {
      final v = getter(obj);
      if (v == null || v.toString().isEmpty) return fallback;
      return v.toString();
    } catch (_) {
      return fallback;
    }
  }

  // ── build ───────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_loading || _isDeleting) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(color: _Mock.orange),
            if (_isDeleting) ...[
              const SizedBox(height: 20),
              const Text('Deleting account data...',
                  style: TextStyle(color: _Mock.textMuted)),
=======
  // ── build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (_loading || _isDeleting) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(color: AppColors.orange),
            if (_isDeleting) ...[
              const SizedBox(height: 20),
              const Text('Deleting account data...',
                  style: TextStyle(color: AppColors.textSecondary)),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
            ],
          ]),
        ),
      );
    }

    return Scaffold(
<<<<<<< HEAD
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 44, 20, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildProfileCard(),
                    const SizedBox(height: 24),

                    _sectionLabel('Personal Details'),
                    const SizedBox(height: 10),
                    _sectionCard([
                      _detailRow(
                        icon: Icons.email_rounded,
                        label: 'Email Address',
                        value: _employee?.email ?? '—',
                      ),
                      _detailRow(
                        icon: Icons.phone_rounded,
                        label: 'Phone Number',
                        value: _dynGet(_employee, (e) => e.phone),
                      ),
                      _detailRow(
                        icon: Icons.location_on_rounded,
                        label: 'Location',
                        value: _dynGet(_employee, (e) => e.location),
                        isLast: true,
                      ),
                    ]),
                    const SizedBox(height: 24),

                    _sectionLabel('App Settings'),
                    const SizedBox(height: 10),
                    Builder(builder: (ctx) {
                      final themeNotifier = ctx.watch<ThemeNotifier>();
                      return _sectionCard([
                        _toggleRow(
                          icon: Icons.dark_mode_outlined,
                          label: 'Dark Mode',
                          subtitle: 'Toggle dark theme',
                          value: themeNotifier.isDark,
                          onChanged: (_) => themeNotifier.toggle(),
                        ),
                        _toggleRow(
                          icon: Icons.notifications_rounded,
                          label: 'Push Notifications',
                          subtitle: 'Updates and alerts',
                          value: _pushEnabled,
                          onChanged: (v) => setState(() => _pushEnabled = v),
                        ),
                        _chevronRow(
                          icon: Icons.language_rounded,
                          label: 'Language',
                          subtitle: 'English (US)',
                          onTap: () => _comingSoon('Language selection'),
                          isLast: true,
                        ),
                      ]);
                    }),
                    const SizedBox(height: 24),

                    _sectionLabel('Account Security'),
                    const SizedBox(height: 10),
                    _sectionCard([
                      _biometricRow(
                        icon: Icons.face_rounded,
                        label: 'Face ID Setup',
                        enrolled: _employee?.hasFaceEnrolled ?? false,
                        onEnroll: () => _enroll('Face ID'),
                        onUnenroll: () => _unenroll('Face ID'),
                      ),
                      _biometricRow(
                        icon: Icons.fingerprint_rounded,
                        label: 'Fingerprint Setup',
                        enrolled: _employee?.hasFingerprintEnrolled ?? false,
                        onEnroll: () => _enroll('Fingerprint'),
                        onUnenroll: () => _unenroll('Fingerprint'),
                      ),
                      _chevronRow(
                        icon: Icons.lock_reset_rounded,
                        label: 'Change Password',
                        onTap: () => _comingSoon('Change password'),
                      ),
                      _chevronRow(
                        icon: Icons.history_rounded,
                        label: 'Attendance History',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AttendanceHistoryScreen(
                                initialEmployee: _employee),
                          ),
                        ),
                        isLast: true,
                      ),
                    ]),
                    const SizedBox(height: 24),

                    _sectionLabel('Data & Backup'),
                    const SizedBox(height: 10),
                    _sectionCard([
                      _chevronRow(
                        icon: Icons.cloud_sync_rounded,
                        label: 'Cloud Backup',
                        subtitle: 'Sync your profile to Firebase',
                        trailing: _isSyncing
                            ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: _Mock.orange))
                            : null,
                        onTap: _isSyncing ? null : _syncToFirebase,
                        isLast: true,
                      ),
                    ]),
                    const SizedBox(height: 24),

                    _sectionLabel('Security & Legal'),
                    const SizedBox(height: 10),
                    _sectionCard([
                      _chevronRow(
                        icon: Icons.privacy_tip_rounded,
                        label: 'Privacy Policy',
                        onTap: () => _comingSoon('Privacy policy'),
                        isLast: true,
                      ),
                    ]),
                    const SizedBox(height: 24),

                    _sectionLabel('Danger Zone', color: _Mock.red),
                    const SizedBox(height: 10),
                    _sectionCard([
                      _chevronRow(
                        icon: Icons.delete_forever_rounded,
                        label: 'Delete My Account',
                        labelColor: _Mock.red,
                        onTap: _confirmDeleteAccount,
                        isLast: true,
                      ),
                    ], borderColor: _Mock.red.withOpacity(0.4)),

                    const SizedBox(height: 32),
                    _buildSignOut(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── HEADER (orange gradient, matches mockup) ────────────────────────────
  // Fixed size constant so the left spacer and the right icon button are
  // always identical — this is what keeps the title mathematically centered.
  //
  // NOTE: this used to be a Stack + Positioned(right: 0). That approach
  // sizes the icon relative to whatever width the Stack happens to resolve
  // to, and on some layouts (e.g. this screen embedded in a shell with its
  // own horizontal insets) that width didn't match the header's real
  // on-screen width — the icon rendered past the header's right edge /
  // rounded corner. A Row with a matching-size spacer can't drift like
  // that: both sides are always exactly _kHeaderActionSize wide, clipped
  // to the header's own padding, so it can't overflow regardless of the
  // parent's width.
  static const double _kHeaderActionSize = 40;

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: const BoxDecoration(
        gradient: AppColors.gradientOrange,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(25),
          bottomRight: Radius.circular(25),
        ),
      ),
      child: SizedBox(
        height: _kHeaderActionSize,
        child: Row(
          children: [
            const SizedBox(width: _kHeaderActionSize), // balances the icon
            const Expanded(
              child: Text(
                'Profile & Settings',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            _headerQuickActionsButton(),
          ],
        ),
      ),
    );
  }

  // Trailing grid icon button (quick actions) — matches the translucent
  // white rounded square shown in the screenshot on the right of the header.
  Widget _headerQuickActionsButton() {
    return GestureDetector(
      onTap: () => _comingSoon('Quick actions'),
      child: Container(
        width: _kHeaderActionSize,
        height: _kHeaderActionSize,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.18),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(
          Icons.grid_view_rounded,
          color: Colors.white,
          size: 20,
        ),
      ),
    );
  }

  // ── PROFILE CARD (avatar overlaps the top edge, per mockup) ─────────────
  // Avatar size lives in one place (_kAvatarSize) so the card's top margin
  // and padding — which exist purely to leave room for the avatar to
  // overlap — are always computed from it instead of being separate magic
  // numbers that can drift out of sync and make the avatar look
  // mis-sized/cramped relative to the card.
  static const double _kAvatarSize = 88;

  Widget _buildProfileCard() {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        Container(
          margin: EdgeInsets.only(top: _kAvatarSize / 2),
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(16, _kAvatarSize / 2 + 12, 16, 20),
          decoration: BoxDecoration(
            color: _Mock.cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _Mock.orange),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 10,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            children: [
              Text(
                _employee?.fullName ?? 'Unknown',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _employee?.position ?? 'Position',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: _Mock.orange,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: _Mock.cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _Mock.orange),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.badge_outlined, size: 14, color: _Mock.orange),
                    const SizedBox(width: 6),
                    Text(
                      _employee?.employeeId ?? _employee?.id ?? '—',
                      style: const TextStyle(fontSize: 12, color: _Mock.orange),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Avatar overlapping the card's top edge
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: _kAvatarSize,
              height: _kAvatarSize,
              decoration: BoxDecoration(
                gradient: AppColors.gradientOrange,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _Mock.orange, width: 3.3),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 6,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              // Photo (once the Employee model has one — read defensively
              // the same way phone/location are, via `_dynGet`) clipped to
              // fill the full box; falls back to initials until then, so
              // this never renders a blank/undersized box either way.
              child: _avatarPhotoUrl() != null
                  ? ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: Image.network(
                  _avatarPhotoUrl()!,
                  width: _kAvatarSize,
                  height: _kAvatarSize,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _avatarInitials(),
                ),
              )
                  : _avatarInitials(),
            ),
            // Online status dot
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: _Mock.lime,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF18181B), width: 1),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Reads a photo URL off `Employee` if/when that field exists on the
  // model — returns null until then, which keeps the initials fallback
  // active instead of crashing the build.
  String? _avatarPhotoUrl() {
    final v = _dynGet(_employee, (e) => e.photoUrl, fallback: '');
    return v.isEmpty ? null : v;
  }

  Widget _avatarInitials() {
    return Center(
      child: Text(
        _employee?.initials ?? '??',
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w900,
          color: Colors.white,
        ),
=======
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildProfileCard(theme, cs),
              const SizedBox(height: 32),

              _sectionLabel('PREFERENCES'),
              const SizedBox(height: 10),
              Builder(
                builder: (ctx) {
                  final themeNotifier = ctx.watch<ThemeNotifier>();
                  return _buildSettings(theme, cs, themeNotifier);
                },
              ),
              const SizedBox(height: 28),

              _sectionLabel('ACCOUNT SECURITY'),
              const SizedBox(height: 10),
              _buildBiometricStatus(theme, cs),
              const SizedBox(height: 28),

              _sectionLabel('DATA & BACKUP'),
              const SizedBox(height: 10),
              _buildSyncSection(theme, cs),
              const SizedBox(height: 28),

              _sectionLabel('DANGER ZONE', color: AppColors.error),
              const SizedBox(height: 10),
              _buildDangerZone(theme, cs),

              const SizedBox(height: 40),
              _buildLogout(),
              const SizedBox(height: 20),
            ],
          ),
        ),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
      ),
    );
  }

<<<<<<< HEAD
  // ── SECTION HELPERS ──────────────────────────────────────────────────────
  Widget _sectionLabel(String text, {Color color = Colors.black}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
          color: color,
        ),
      ),
    );
  }

  Widget _sectionCard(List<Widget> rows, {Color? borderColor}) {
    return Container(
      decoration: BoxDecoration(
        color: _Mock.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor ?? _Mock.orange),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: rows),
    );
  }

  Widget _iconBox(IconData icon) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        gradient: AppColors.gradientOrange,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: Colors.white, size: 20),
    );
  }

  BoxDecoration _rowDivider(bool isLast) => BoxDecoration(
    border: isLast
        ? null
        : Border(bottom: BorderSide(color: _Mock.orange.withOpacity(0.3))),
  );

  Widget _detailRow({
    required IconData icon,
    required String label,
    required String value,
    bool isLast = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _rowDivider(isLast),
      child: Row(
        children: [
          _iconBox(icon),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(fontSize: 12, color: _Mock.textMuted)),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: _Mock.orange,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggleRow({
    required IconData icon,
    required String label,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool isLast = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _rowDivider(isLast),
      child: Row(
        children: [
          _iconBox(icon),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: _Mock.orange)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(fontSize: 12, color: _Mock.textMuted)),
              ],
            ),
          ),
          _ToggleSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _chevronRow({
    required IconData icon,
    required String label,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    Color? labelColor,
    bool isLast = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: _rowDivider(isLast),
        child: Row(
          children: [
            _iconBox(icon),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: labelColor ?? _Mock.orange)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: const TextStyle(fontSize: 12, color: _Mock.textMuted)),
                  ],
                ],
              ),
            ),
            trailing ??
                const Icon(Icons.chevron_right_rounded,
                    color: _Mock.textMuted, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _biometricRow({
    required IconData icon,
    required String label,
    required bool enrolled,
    required VoidCallback onEnroll,
    required VoidCallback onUnenroll,
    bool isLast = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _rowDivider(isLast),
      child: Row(
        children: [
          _iconBox(icon),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: _Mock.orange)),
                const SizedBox(height: 2),
                Text(
                  enrolled ? 'Enabled' : 'Not configured',
                  style: TextStyle(
                    fontSize: 12,
                    color: enrolled ? AppColors.success : _Mock.textMuted,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: enrolled ? onUnenroll : onEnroll,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: enrolled
                    ? _Mock.red.withOpacity(0.08)
                    : _Mock.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: enrolled
                      ? _Mock.red.withOpacity(0.4)
                      : _Mock.orange.withOpacity(0.4),
                ),
              ),
              child: Text(
                enrolled ? 'DISABLE' : 'SET UP',
                style: TextStyle(
                  color: enrolled ? _Mock.red : _Mock.orange,
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                  letterSpacing: 0.5,
=======
  Widget _sectionLabel(String text, {Color color = AppColors.textMuted}) {
    return Text(text,
        style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
            color: color));
  }

  // ── Profile card ─────────────────────────────────────────────────────────────
  Widget _buildProfileCard(ThemeData theme, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: AppColors.orange.withOpacity(0.25), width: 1),
        boxShadow: [
          BoxShadow(
              color: AppColors.orange.withOpacity(0.08),
              blurRadius: 24,
              spreadRadius: 2),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              gradient: AppColors.gradientOrange,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                    color: AppColors.orange.withOpacity(0.4),
                    blurRadius: 20),
              ],
            ),
            child: Center(
              child: Text(
                _employee?.initials ?? '??',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
                ),
              ),
            ),
          ),
<<<<<<< HEAD
=======
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _employee?.fullName ?? 'Unknown',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _employee?.position ?? 'Position',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  _employee?.email ?? '',
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          // Status dot
          Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.1),
              borderRadius: BorderRadius.circular(3),
              border:
              Border.all(color: AppColors.success.withOpacity(0.3)),
            ),
            child: const Text('ACTIVE',
                style: TextStyle(
                    fontSize: 9,
                    color: AppColors.success,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1)),
          ),
        ],
      ),
    );
  }

  // ── Settings ─────────────────────────────────────────────────────────────────
  Widget _buildSettings(
      ThemeData theme, ColorScheme cs, ThemeNotifier themeNotifier) {
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: _SettingTile(
        icon: Icons.dark_mode_outlined,
        label: 'App Theme',
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              themeNotifier.isDark ? 'Dark' : 'Light',
              style: const TextStyle(
                  color: AppColors.textMuted, fontSize: 12),
            ),
            const SizedBox(width: 8),
            Switch(
              value: themeNotifier.isDark,
              onChanged: (_) => themeNotifier.toggle(),
              activeColor: AppColors.orange,
            ),
          ],
        ),
      ),
    );
  }

  // ── Sync section ─────────────────────────────────────────────────────────────
  Widget _buildSyncSection(ThemeData theme, ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: ListTile(
        leading: const Icon(Icons.cloud_sync_rounded,
            color: AppColors.orange),
        title: const Text('Cloud Backup',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700)),
        subtitle: const Text('Sync your profile to Firebase',
            style: TextStyle(
                fontSize: 11, color: AppColors.textSecondary)),
        trailing: _isSyncing
            ? const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.orange))
            : const Icon(Icons.chevron_right,
            color: AppColors.textMuted, size: 18),
        onTap: _isSyncing ? null : _syncToFirebase,
      ),
    );
  }

  // ── Biometric status ─────────────────────────────────────────────────────────
  Widget _buildBiometricStatus(ThemeData theme, ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        children: [
          _BiometricRow(
            icon: Icons.face,
            label: 'Face ID Setup',
            enrolled: _employee?.hasFaceEnrolled ?? false,
            onEnroll: () => _enroll('Face ID'),
            onUnenroll: () => _unenroll('Face ID'),
          ),
          Divider(
              color: AppColors.cardBorder, height: 1, indent: 56),
          _BiometricRow(
            icon: Icons.fingerprint,
            label: 'Fingerprint Setup',
            enrolled: _employee?.hasFingerprintEnrolled ?? false,
            onEnroll: () => _enroll('Fingerprint'),
            onUnenroll: () => _unenroll('Fingerprint'),
          ),
          Divider(
              color: AppColors.cardBorder, height: 1, indent: 56),
          _SettingTile(
            icon: Icons.history,
            label: 'Attendance History',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AttendanceHistoryScreen(
                    initialEmployee: _employee),
              ),
            ),
          ),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
        ],
      ),
    );
  }

<<<<<<< HEAD
  // ── SIGN OUT (light card, red border, per mockup) ────────────────────────
  Widget _buildSignOut() {
    return InkWell(
      onTap: _logout,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _Mock.cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _Mock.red),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.logout_rounded, color: _Mock.red, size: 18),
            SizedBox(width: 8),
            Text(
              'Sign Out',
              style: TextStyle(
                color: _Mock.red,
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ],
=======
  // ── Danger zone ───────────────────────────────────────────────────────────────
  Widget _buildDangerZone(ThemeData theme, ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error.withOpacity(0.3)),
      ),
      child: _SettingTile(
        icon: Icons.delete_forever_rounded,
        label: 'Delete My Account',
        labelColor: AppColors.error,
        iconColor: AppColors.error,
        onTap: _confirmDeleteAccount,
      ),
    );
  }

  // ── Logout ───────────────────────────────────────────────────────────────────
  Widget _buildLogout() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _logout,
        icon: const Icon(Icons.logout_rounded,
            color: AppColors.error, size: 18),
        label: const Text('LOG OUT',
            style: TextStyle(
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
                color: AppColors.error,
                fontSize: 13)),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4)),
          side: BorderSide(
              color: AppColors.error.withOpacity(0.3), width: 1),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
        ),
      ),
    );
  }
}

<<<<<<< HEAD
// ══════════════════════════════════════════════════════════════════════════
// Custom pill/gradient toggle switch matching the mockup's SVG track exactly
// (off = solid dark track, on = orange gradient track, white knob).
// ══════════════════════════════════════════════════════════════════════════
class _ToggleSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _ToggleSwitch({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 48,
        height: 24,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: value ? AppColors.gradientOrange : null,
          color: value ? null : _Mock.switchTrackOff,
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 180),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
=======
// ══════════════════════════════════════════════════════════════════════════════
// Reusable widgets
// ══════════════════════════════════════════════════════════════════════════════

class _BiometricRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enrolled;
  final VoidCallback onEnroll;
  final VoidCallback onUnenroll;

  const _BiometricRow({
    required this.icon,
    required this.label,
    required this.enrolled,
    required this.onEnroll,
    required this.onUnenroll,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        icon,
        color: enrolled ? AppColors.success : AppColors.textMuted,
        size: 22,
      ),
      title: Text(
        label,
        style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 14),
      ),
      subtitle: Text(
        enrolled ? 'Enabled' : 'Not configured',
        style: TextStyle(
          color: enrolled ? AppColors.success : AppColors.textMuted,
          fontSize: 11,
        ),
      ),
      trailing: GestureDetector(
        onTap: enrolled ? onUnenroll : onEnroll,
        child: Container(
          padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: enrolled
                ? AppColors.error.withOpacity(0.08)
                : AppColors.orange.withOpacity(0.1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: enrolled
                  ? AppColors.error.withOpacity(0.3)
                  : AppColors.orange.withOpacity(0.3),
            ),
          ),
          child: Text(
            enrolled ? 'DISABLE' : 'SET UP',
            style: TextStyle(
              color: enrolled ? AppColors.error : AppColors.orange,
              fontWeight: FontWeight.w800,
              fontSize: 10,
              letterSpacing: 1,
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
            ),
          ),
        ),
      ),
    );
  }
<<<<<<< HEAD
=======
}

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? labelColor;
  final Color? iconColor;

  const _SettingTile({
    required this.icon,
    required this.label,
    this.trailing,
    this.onTap,
    this.labelColor,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon,
          color: iconColor ?? AppColors.textSecondary, size: 20),
      title: Text(label,
          style: TextStyle(
              color: labelColor ?? AppColors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 14)),
      trailing: trailing ??
          const Icon(Icons.chevron_right,
              color: AppColors.textMuted, size: 18),
      onTap: onTap,
    );
  }
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
}