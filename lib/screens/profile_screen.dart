// lib/screens/profile_screen.dart
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

class _Mock {
  static const Color orange = Color(0xFFFFA500);
  static const Color lime = Color(0xFFC4FF0A);
  static const Color red = Color(0xFFFB2C36);
  static const Color textMuted = Color(0xFF71717A);
  static const Color cardBg = Color(0xFFF8F8F8);
  static const Color switchTrackOff = Color(0xFF3F3F46);
}

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
  bool _pushEnabled = true;
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
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: _Mock.red),
          SizedBox(width: 10),
          Text('Delete Account',
              style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700)),
        ]),
        content: const Text(
          'Are you sure you want to permanently delete your account? '
              'This will remove all your data from the local database, '
              'cloud storage, and admin records. This cannot be undone.',
          style: TextStyle(color: _Mock.textMuted, fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: _Mock.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: _Mock.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            child: const Text('Delete Permanently',
                style: TextStyle(fontWeight: FontWeight.w700)),
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
            backgroundColor: _Mock.red,
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
          await AuthService.instance.login(email: email, password: password);
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
          backgroundColor: _Mock.red,
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
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Link Cloud Account',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter your 4-digit PIN to secure your cloud backup.',
              style: TextStyle(color: _Mock.textMuted, fontSize: 13, height: 1.5),
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
                  color: Colors.black,
                  fontWeight: FontWeight.w700),
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
            child: const Text('Cancel', style: TextStyle(color: _Mock.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, pinInput),
            style: ElevatedButton.styleFrom(
                backgroundColor: _Mock.orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            child: const Text('CONFIRM',
                style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1)),
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
        backgroundColor: _Mock.red,
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

  void _comingSoon(String label) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$label — coming soon'),
      backgroundColor: _Mock.textMuted,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(12),
    ));
  }

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
            ],
          ]),
        ),
      );
    }

    return Scaffold(
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
            const SizedBox(width: _kHeaderActionSize),
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
      ),
    );
  }

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
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

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
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
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
        ),
      ),
    );
  }
}

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
            ),
          ),
        ),
      ),
    );
  }
}