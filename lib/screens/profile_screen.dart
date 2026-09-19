// lib/screens/profile_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, Platform;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

import '../theme/app_theme.dart';
import '../theme/theme_notifier.dart';
import '../services/database_service.dart';
import '../services/security_service.dart';
import '../services/auth_service.dart';
import '../services/notification_preference_service.dart';
import '../services/language_service.dart';
import '../services/admin_notification_service.dart';   // ✅ BAGONG IMPORT
import '../models/employee.dart';
import 'landing_screen.dart';

// Brand colors (same in both themes)
class _Mock {
  static const Color orange = Color(0xFFFFA500);
  static const Color lime = Color(0xFFC4FF0A);
  static const Color red = Color(0xFFFB2C36);
  static const Color switchTrackOff = Color(0xFF3F3F46);
}

class _ThemeColors {
  final bool isDark;
  const _ThemeColors(this.isDark);

  Color get bg => isDark ? const Color(0xFF0F0F10) : Colors.white;
  Color get cardBg => isDark ? const Color(0xFF18181B) : const Color(0xFFF8F8F8);
  Color get cardBorder => isDark ? const Color(0xFF3F3F46) : _Mock.orange;
  Color get textPrimary => isDark ? Colors.white : Colors.black;
  Color get textMuted =>
      isDark ? const Color(0xFFB0B0B0) : const Color(0xFF71717A);
  Color get rowDivider =>
      isDark ? const Color(0xFF27272A) : _Mock.orange.withValues(alpha: 0.3);
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
  bool _pushLoading = true;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _employeeSub;

  // ✅ BAGO — password change request state
  bool _sendingPasswordRequest = false;
  DateTime? _lastPasswordRequest;
  static const _passwordCooldown = Duration(minutes: 10);

  LanguageService get lang => LanguageService.instance;

  @override
  void initState() {
    super.initState();
    _load();
    _loadPushPreference();
  }

  @override
  void dispose() {
    _employeeSub?.cancel();
    super.dispose();
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
      debugPrint('👤 [Profile] Initial load: ${employee?.fullName} '
          '(id=${employee?.id})');
    }

    _startEmployeeListener();
  }

  void _startEmployeeListener() {
    final docId = _employee?.id;
    if (docId == null || docId.isEmpty) {
      debugPrint('⚠️ [Profile] Walang employee doc ID — skip listener');
      return;
    }

    debugPrint('🎧 [Profile] Starting live listener for doc: $docId');

    _employeeSub?.cancel();
    _employeeSub = FirebaseFirestore.instance
        .collection('employees')
        .doc(docId)
        .snapshots()
        .listen(
          (snap) {
        if (!mounted) return;
        final data = snap.data();
        if (data == null) {
          debugPrint('⚠️ [Profile] Doc deleted o empty');
          return;
        }

        Employee? updated;
        try {
          updated = Employee.fromFirestore(data, snap.id);
        } catch (e) {
          debugPrint('❌ [Profile] Parse error: $e');
          return;
        }

        final oldPhoto = _employee?.photoUrl ?? _employee?.photoPath;
        final newPhoto = updated.photoUrl ?? updated.photoPath;
        final photoChanged = oldPhoto != newPhoto;

        final oldName = _employee?.fullName;
        final newName = updated.fullName;
        final nameChanged = oldName != newName;

        setState(() => _employee = updated);

        debugPrint('🔄 [Profile] Live update: name="${updated.fullName}"'
            '${photoChanged ? " • 📸 PHOTO CHANGED!" : ""}'
            '${nameChanged ? " • NAME CHANGED!" : ""}');

        DatabaseService.instance.insertEmployee(updated).catchError((e) {
          debugPrint('⚠️ [Profile] Local save error: $e');
        });
      },
      onError: (e) {
        debugPrint('❌ [Profile] Listener error: $e');
      },
    );
  }

  Future<void> _loadPushPreference() async {
    final enabled =
    await NotificationPreferenceService.instance.isPushEnabled();
    if (mounted) {
      setState(() {
        _pushEnabled = enabled;
        _pushLoading = false;
      });
      debugPrint('🔔 [Profile] Push pref loaded: $enabled');
    }
  }

  Future<void> _onPushToggle(bool value) async {
    setState(() => _pushEnabled = value);

    await NotificationPreferenceService.instance.setPushEnabled(value);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              value
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_off_rounded,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                value
                    ? lang.t('notif_on_msg')
                    : lang.t('notif_off_msg'),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        backgroundColor:
        value ? const Color(0xFF16A34A) : const Color(0xFF52525B),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 🔐 PASSWORD CHANGE REQUEST  (BAGO)
  // ═══════════════════════════════════════════════════════════════
  Future<void> _requestPasswordChange() async {
    // Cooldown check
    final now = DateTime.now();
    if (_lastPasswordRequest != null &&
        now.difference(_lastPasswordRequest!) < _passwordCooldown) {
      final remain = _passwordCooldown - now.difference(_lastPasswordRequest!);
      _showSnack(
        '⏳ Nagpadala ka na kamakailan. Subukan ulit sa ${remain.inMinutes}m.',
        isError: true,
      );
      return;
    }

    final employee = _employee;
    if (employee == null) {
      _showSnack('⚠️ Hindi makuha ang employee info.', isError: true);
      return;
    }

    // Confirm dialog
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final dtc = _ThemeColors(isDark);
        return AlertDialog(
          backgroundColor: dtc.cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: dtc.cardBorder, width: 1),
          ),
          title: Row(
            children: [
              const Icon(Icons.lock_reset_rounded,
                  color: _Mock.orange, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  lang.t('change_password'),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: dtc.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            'Ipapaalam ito sa admin. Ikaw mismo ang magse-set ng bagong '
                'password matapos ma-approve.\n\nEmployee: ${employee.fullName}\n'
                'Email: ${employee.email}',
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: dtc.textMuted,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                lang.isTagalog ? 'Kanselahin' : 'Cancel',
                style: TextStyle(
                  color: dtc.textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _Mock.orange),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                lang.isTagalog ? 'Ipadala' : 'Send Request',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        );
      },
    );

    if (ok != true) return;

    setState(() => _sendingPasswordRequest = true);

    try {
      await AdminNotificationService.instance.notifyPasswordChangeRequest(
        employeeId: employee.id,
        employeeName: employee.fullName,
        email: employee.email,
        reason: 'Employee-initiated password reset',
      );

      _lastPasswordRequest = DateTime.now();

      if (!mounted) return;
      _showSnack(
        lang.isTagalog
            ? '✅ Naipadala na sa admin ang iyong request.'
            : '✅ Request sent to admin.',
      );
    } catch (e) {
      debugPrint('❌ [PasswordChange] $e');
      if (!mounted) return;
      _showSnack(
        lang.isTagalog
            ? '⚠️ Hindi naipadala. Subukan ulit.'
            : '⚠️ Failed to send. Try again.',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _sendingPasswordRequest = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        content: Row(
          children: [
            Icon(
              isError
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_rounded,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(msg, style: const TextStyle(fontSize: 13)),
            ),
          ],
        ),
        backgroundColor:
        isError ? const Color(0xFFEF4444) : const Color(0xFF16A34A),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 🆕 LANGUAGE SELECTION
  // ═══════════════════════════════════════════════════════════════
  Future<void> _showLanguageDialog() async {
    final current = lang.language;

    final picked = await showDialog<AppLanguage>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final dialogTc = _ThemeColors(isDark);

        return AlertDialog(
          backgroundColor: dialogTc.cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: dialogTc.cardBorder, width: 1),
          ),
          title: Row(
            children: [
              const Icon(Icons.translate_rounded,
                  color: _Mock.orange, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  lang.t('select_language'),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: dialogTc.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _languageOption(
                tc: dialogTc,
                value: AppLanguage.english,
                label: '🇬🇧  English',
                subtitle: 'Use English language',
                selected: current == AppLanguage.english,
                onTap: () =>
                    Navigator.pop(ctx, AppLanguage.english),
              ),
              const SizedBox(height: 8),
              _languageOption(
                tc: dialogTc,
                value: AppLanguage.tagalog,
                label: '🇵🇭  Tagalog',
                subtitle: 'Gamitin ang wikang Tagalog',
                selected: current == AppLanguage.tagalog,
                onTap: () =>
                    Navigator.pop(ctx, AppLanguage.tagalog),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                current == AppLanguage.tagalog ? 'Kanselahin' : 'Cancel',
                style: TextStyle(
                  color: dialogTc.textMuted,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (picked == null || picked == current) return;

    await lang.setLanguage(picked);

    if (!mounted) return;

    final msg = picked == AppLanguage.tagalog
        ? 'Nakaset na ang wika sa Tagalog'
        : 'App language set to English';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded,
                color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(msg, style: const TextStyle(fontSize: 13)),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF16A34A),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _languageOption({
    required _ThemeColors tc,
    required AppLanguage value,
    required String label,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding:
        const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? _Mock.orange.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? _Mock.orange.withValues(alpha: 0.5)
                : tc.cardBorder.withValues(alpha: 0.4),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: selected ? _Mock.orange : tc.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: tc.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle_rounded,
                  color: _Mock.orange, size: 22)
            else
              Icon(Icons.radio_button_unchecked_rounded,
                  color: tc.textMuted, size: 22),
          ],
        ),
      ),
    );
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
      SnackBar(content: Text('$feature ${lang.t('feature_coming_soon')}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ✅ Watch LanguageService — auto-rebuild kapag nag-change ng wika
    final langService = context.watch<LanguageService>();
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
            _buildHeader(langService),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
                child: Column(
                  children: [
                    _buildProfileCard(tc),
                    const SizedBox(height: 32),

                    _sectionLabel(tc, langService.t('personal_details')),
                    const SizedBox(height: 10),
                    _sectionCard(tc, [
                      _detailRow(
                        tc: tc,
                        icon: Icons.email_rounded,
                        label: langService.t('email_address'),
                        value: _employee?.email ?? '—',
                      ),
                      _detailRow(
                        tc: tc,
                        icon: Icons.phone_android_rounded,
                        label: langService.t('phone_number'),
                        value: _employee?.phone ?? '—',
                      ),
                      _detailRow(
                        tc: tc,
                        icon: Icons.location_on_rounded,
                        label: langService.t('department'),
                        value: _employee?.department ?? '—',
                      ),
                      _detailRow(
                        tc: tc,
                        icon: Icons.work_outline_rounded,
                        label: langService.t('position'),
                        value: _employee?.position ?? '—',
                        isLast: true,
                      ),
                    ]),
                    const SizedBox(height: 24),

                    _sectionLabel(tc, langService.t('app_settings')),
                    const SizedBox(height: 10),
                    _sectionCard(tc, [
                      _toggleRow(
                        tc: tc,
                        icon: Icons.dark_mode_rounded,
                        label: langService.t('dark_mode'),
                        subtitle: langService.t('dark_mode_subtitle'),
                        value: context.watch<ThemeNotifier>().isDark,
                        onChanged: (v) =>
                            context.read<ThemeNotifier>().toggle(),
                      ),

                      _toggleRow(
                        tc: tc,
                        icon: _pushEnabled
                            ? Icons.notifications_active_rounded
                            : Icons.notifications_off_rounded,
                        label: langService.t('push_notifications'),
                        subtitle: _pushLoading
                            ? langService.t('push_loading')
                            : (_pushEnabled
                            ? langService.t('push_on')
                            : langService.t('push_off')),
                        value: _pushEnabled,
                        onChanged: _pushLoading ? (_) {} : _onPushToggle,
                      ),

                      // 🆕 LANGUAGE ROW — working selector
                      _chevronRow(
                        tc: tc,
                        icon: Icons.translate_rounded,
                        label: langService.t('language'),
                        subtitle: langService.isTagalog
                            ? 'Tagalog 🇵🇭'
                            : 'English 🇬🇧',
                        onTap: _showLanguageDialog,
                        isLast: true,
                      ),
                    ]),
                    const SizedBox(height: 24),

                    _sectionLabel(tc, langService.t('security')),
                    const SizedBox(height: 10),
                    _sectionCard(tc, [
                      // ✅ UPDATED — password change request na
                      _chevronRow(
                        tc: tc,
                        icon: Icons.lock_reset_rounded,
                        label: langService.t('change_password'),
                        subtitle: _sendingPasswordRequest
                            ? (langService.isTagalog
                            ? 'Ipinapadala…'
                            : 'Sending…')
                            : (langService.isTagalog
                            ? 'I-request sa admin'
                            : 'Request from admin'),
                        onTap: _sendingPasswordRequest
                            ? null
                            : _requestPasswordChange,
                      ),
                      _chevronRow(
                        tc: tc,
                        icon: Icons.privacy_tip_rounded,
                        label: langService.t('privacy_policy'),
                        onTap: () =>
                            _comingSoon(langService.t('privacy_policy')),
                        isLast: true,
                      ),
                    ]),

                    const SizedBox(height: 32),
                    _buildSignOut(tc, langService),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(LanguageService langService) {
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
        height: 40,
        child: Center(
          child: Text(
            langService.t('profile_title'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

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
                _employee?.fullName ?? lang.t('unknown'),
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
              clipBehavior: Clip.antiAlias,
              child: _buildAvatarContent(),
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
                  border:
                  Border.all(color: const Color(0xFF18181B), width: 1),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAvatarContent() {
    final url = _employee?.photoUrl ?? _employee?.photoPath;

    if (url == null || url.isEmpty || url == '—') {
      return _avatarInitials();
    }

    if (url.startsWith('data:image')) {
      try {
        final b64 = url.split(',').last;
        return Image.memory(
          base64Decode(b64),
          fit: BoxFit.cover,
          width: _kAvatarSize,
          height: _kAvatarSize,
          errorBuilder: (_, __, ___) {
            debugPrint('⚠️ [Profile] Base64 decode failed');
            return _avatarInitials();
          },
        );
      } catch (e) {
        debugPrint('❌ [Profile] Base64 error: $e');
        return _avatarInitials();
      }
    }

    if (url.startsWith('http://') || url.startsWith('https://')) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        width: _kAvatarSize,
        height: _kAvatarSize,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            color: _Mock.orange,
            alignment: Alignment.center,
            child: const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            ),
          );
        },
        errorBuilder: (_, __, ___) {
          debugPrint('⚠️ [Profile] Network image failed');
          return _avatarInitials();
        },
      );
    }

    if (Platform.isAndroid || Platform.isIOS) {
      try {
        final file = File(url);
        if (file.existsSync()) {
          return Image.file(
            file,
            fit: BoxFit.cover,
            width: _kAvatarSize,
            height: _kAvatarSize,
            errorBuilder: (_, __, ___) => _avatarInitials(),
          );
        }
      } catch (_) {}
    }

    return _avatarInitials();
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
                        style: TextStyle(fontSize: 12, color: tc.textMuted)),
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

  Widget _buildSignOut(_ThemeColors tc, LanguageService langService) {
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
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.logout_rounded, color: _Mock.red, size: 18),
            const SizedBox(width: 8),
            Text(
              langService.t('sign_out'),
              style: const TextStyle(
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