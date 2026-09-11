// lib/screens/profile_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/app_theme.dart';
import '../theme/theme_notifier.dart';
import '../services/database_service.dart';
import '../services/security_service.dart';
import '../services/auth_service.dart';
import '../models/employee.dart';
import 'landing_screen.dart';

// Brand colors (same in both themes)
class _Mock {
  static const Color orange = Color(0xFFFFA500);
  static const Color lime = Color(0xFFC4FF0A);
  static const Color red = Color(0xFFFB2C36);
  static const Color switchTrackOff = Color(0xFF3F3F46);
}

// ═══════════════════════════════════════════════════════════════════════════
// _ThemeColors — theme-aware colors for profile screen
// ═══════════════════════════════════════════════════════════════════════════
class _ThemeColors {
  final bool isDark;
  const _ThemeColors(this.isDark);

  Color get bg => isDark ? const Color(0xFF0F0F10) : Colors.white;

  Color get cardBg => isDark ? const Color(0xFF18181B) : const Color(0xFFF8F8F8);
  Color get cardBorder =>
      isDark ? const Color(0xFF3F3F46) : _Mock.orange;

  Color get textPrimary => isDark ? Colors.white : Colors.black;
  Color get textMuted =>
      isDark ? const Color(0xFFB0B0B0) : const Color(0xFF71717A);

  // Row divider
  Color get rowDivider =>
      isDark ? const Color(0xFF27272A) : _Mock.orange.withValues(alpha: 0.3);

  // Section label color (same for both = black/white)
  Color get sectionLabel => isDark ? Colors.white : Colors.black;
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
  bool _pushEnabled = true;

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

  void _comingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature feature coming soon!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = _ThemeColors(isDark);

    if (_loading) {
      return Scaffold(
        backgroundColor: tc.bg,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: tc.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
                child: Column(
                  children: [
                    _buildProfileCard(tc),
                    const SizedBox(height: 32),

                    _sectionLabel(tc, 'Personal Details'),
                    const SizedBox(height: 10),
                    _sectionCard(tc, [
                      _detailRow(
                        tc: tc,
                        icon: Icons.email_rounded,
                        label: 'Email Address',
                        value: _employee?.email ?? '—',
                      ),
                      _detailRow(
                        tc: tc,
                        icon: Icons.phone_android_rounded,
                        label: 'Phone Number',
                        value: _employee?.phone ?? '—',
                      ),
                      _detailRow(
                        tc: tc,
                        icon: Icons.location_on_rounded,
                        label: 'Location',
                        value: _employee?.department ?? '—',
                        isLast: true,
                      ),
                    ]),
                    const SizedBox(height: 24),

                    _sectionLabel(tc, 'App Settings'),
                    const SizedBox(height: 10),
                    _sectionCard(tc, [
                      _toggleRow(
                        tc: tc,
                        icon: Icons.dark_mode_rounded,
                        label: 'Dark Mode',
                        subtitle: 'Toggle dark theme',
                        value: context.watch<ThemeNotifier>().isDark,
                        onChanged: (v) =>
                            context.read<ThemeNotifier>().toggle(),
                      ),
                      _toggleRow(
                        tc: tc,
                        icon: Icons.notifications_active_rounded,
                        label: 'Push Notifications',
                        subtitle: 'Updates and alerts',
                        value: _pushEnabled,
                        onChanged: (v) =>
                            setState(() => _pushEnabled = v),
                      ),
                      _chevronRow(
                        tc: tc,
                        icon: Icons.translate_rounded,
                        label: 'Language',
                        subtitle: 'English (US)',
                        onTap: () => _comingSoon('Language selection'),
                        isLast: true,
                      ),
                    ]),
                    const SizedBox(height: 24),

                    _sectionLabel(tc, 'Security'),
                    const SizedBox(height: 10),
                    _sectionCard(tc, [
                      _chevronRow(
                        tc: tc,
                        icon: Icons.lock_reset_rounded,
                        label: 'Change Password',
                        onTap: () => _comingSoon('Change password'),
                      ),
                      _chevronRow(
                        tc: tc,
                        icon: Icons.privacy_tip_rounded,
                        label: 'Privacy Policy',
                        onTap: () => _comingSoon('Privacy policy'),
                        isLast: true,
                      ),
                    ]),

                    const SizedBox(height: 32),
                    _buildSignOut(tc),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header (same brand gradient in both themes) ──────────────────────
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
      child: const SizedBox(
        height: 40,
        child: Center(
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
      ),
    );
  }

  // ── Profile Card ────────────────────────────────────────────────────
  static const double _kAvatarSize = 88;

  Widget _buildProfileCard(_ThemeColors tc) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        Container(
          margin: EdgeInsets.only(top: _kAvatarSize / 2),
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(16, _kAvatarSize / 2 + 12, 16, 20),
          decoration: BoxDecoration(
            color: tc.cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: tc.cardBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
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
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                  color: tc.textPrimary,
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
                padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: tc.cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: tc.cardBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.badge_outlined,
                        size: 14, color: _Mock.orange),
                    const SizedBox(width: 6),
                    Text(
                      _employee?.employeeId ?? _employee?.id ?? '—',
                      style:
                      const TextStyle(fontSize: 12, color: _Mock.orange),
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
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 6,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: _avatarPhotoPath() != null
                  ? ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: Image.network(
                  _avatarPhotoPath()!,
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
                  border: Border.all(
                      color: const Color(0xFF18181B), width: 1),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String? _avatarPhotoPath() {
    if (_employee?.photoPath != null && _employee!.photoPath!.isNotEmpty) {
      return _employee!.photoPath;
    }
    return null;
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

  // ── UI Helpers ──────────────────────────────────────────────────────
  Widget _sectionLabel(_ThemeColors tc, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
            color: tc.sectionLabel,
          ),
        ),
      ),
    );
  }

  Widget _sectionCard(_ThemeColors tc, List<Widget> rows,
      {Color? borderColor}) {
    return Container(
      decoration: BoxDecoration(
        color: tc.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor ?? tc.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
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

  BoxDecoration _rowDivider(_ThemeColors tc, bool isLast) => BoxDecoration(
    border: isLast
        ? null
        : Border(
      bottom: BorderSide(color: tc.rowDivider),
    ),
  );

  Widget _detailRow({
    required _ThemeColors tc,
    required IconData icon,
    required String label,
    required String value,
    bool isLast = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _rowDivider(tc, isLast),
      child: Row(
        children: [
          _iconBox(icon),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(fontSize: 12, color: tc.textMuted)),
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
    required _ThemeColors tc,
    required IconData icon,
    required String label,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool isLast = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _rowDivider(tc, isLast),
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
                    style: TextStyle(fontSize: 12, color: tc.textMuted)),
              ],
            ),
          ),
          _ToggleSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _chevronRow({
    required _ThemeColors tc,
    required IconData icon,
    required String label,
    String? subtitle,
    VoidCallback? onTap,
    bool isLast = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: _rowDivider(tc, isLast),
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
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style:
                        TextStyle(fontSize: 12, color: tc.textMuted)),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: tc.textMuted, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSignOut(_ThemeColors tc) {
    return InkWell(
      onTap: _logout,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tc.cardBg,
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