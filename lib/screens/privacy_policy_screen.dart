// lib/screens/privacy_policy_screen.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

// ═══════════════════════════════════════════════════════════════
// THEME
// ═══════════════════════════════════════════════════════════════
class _PolicyColors {
  final bool isDark;
  const _PolicyColors(this.isDark);

  Color get bg => isDark ? const Color(0xFF0F0F10) : Colors.white;
  Color get cardBg =>
      isDark ? const Color(0xFF18181B) : const Color(0xFFF8F8F8);
  Color get cardBorder =>
      isDark ? const Color(0xFF3F3F46) : const Color(0xFFFFA500);
  Color get textPrimary => isDark ? Colors.white : Colors.black;
  Color get textMuted =>
      isDark ? const Color(0xFFB0B0B0) : const Color(0xFF71717A);
  Color get divider =>
      isDark ? const Color(0xFF27272A) : const Color(0xFFFFA500).withValues(alpha: 0.3);
  Color get highlight =>
      isDark ? const Color(0xFF27272A) : const Color(0xFFFFF3E0);

  static const Color orange = Color(0xFFFFA500);
  static const Color orangeDeep = Color(0xFFF54900);
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFF8A00), Color(0xFFFA6A00), Color(0xFFF54900)],
    stops: [0.0, 0.5, 1.0],
  );
}

const String _kLogoAsset = 'assets/images/logo.png';

double _degToRad(double deg) => deg * 3.1415926535 / 180;

// ═══════════════════════════════════════════════════════════════
// PRIVACY POLICY SCREEN
// ═══════════════════════════════════════════════════════════════
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const String _version = '1.0';
  static const String _effectiveDate = 'November 1, 2025';
  static const String _dpoEmail = 'dpo@racoma.com';
  static const String _supportEmail = 'support@racoma.com';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = _PolicyColors(isDark);

    return Scaffold(
      backgroundColor: tc.bg,
      body: SafeArea(
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            // Watermark
            Positioned(
              bottom: -130,
              left: -150,
              child: IgnorePointer(
                child: Transform.rotate(
                  angle: _degToRad(425),
                  child: Opacity(
                    opacity: isDark ? 0.15 : 0.80,
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
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            Column(
              children: [
                _buildHeader(context, tc),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildIntroCard(tc),
                        const SizedBox(height: 20),

                        _buildSection(
                          tc,
                          number: '1',
                          title: 'Information We Collect',
                          icon: Icons.folder_outlined,
                          bullets: const [
                            'Full name, email address, phone number, and employee ID',
                            'Position, department, and employment status',
                            'Biometric data (fingerprint verification result — the actual fingerprint image is NEVER stored)',
                            'Location data (GPS coordinates, distance from office, geofence zone)',
                            'Attendance records (clock-in/out time, date, device information)',
                            'Device information (model, OS, unique device binding token)',
                            'Camera photos (for facial recognition and profile display)',
                            'Security logs (login attempts, session activity, integrity checks)',
                          ],
                        ),
                        const SizedBox(height: 16),

                        _buildSection(
                          tc,
                          number: '2',
                          title: 'How We Use Your Information',
                          icon: Icons.settings_outlined,
                          bullets: const [
                            'Verify attendance (clock-in and clock-out)',
                            'Confirm that you are within the authorized work zone (geofencing)',
                            'Prevent fraud, fake GPS usage, and unauthorized access',
                            'Compute payroll, payslips, and attendance reports',
                            'Send notifications to admin (late arrivals, WFH, driver events)',
                            'Comply with legal and regulatory requirements',
                          ],
                        ),
                        const SizedBox(height: 16),

                        _buildSection(
                          tc,
                          number: '3',
                          title: 'How We Store Your Information',
                          icon: Icons.security_rounded,
                          bullets: const [
                            'Cloud storage: Google Firebase Firestore (encrypted at rest)',
                            'Local storage: encrypted shared preferences and secure storage',
                            'Biometric: the actual fingerprint is NEVER stored — only the verification result (true/false)',
                            'Device binding tokens are hashed (SHA-256) — they cannot be reversed',
                            'Session tokens automatically expire after 30 minutes of inactivity',
                          ],
                        ),
                        const SizedBox(height: 16),

                        _buildSection(
                          tc,
                          number: '4',
                          title: 'Data Sharing and Disclosure',
                          icon: Icons.share_outlined,
                          bullets: const [
                            'Your data is NEVER sold to third parties',
                            'Your company\'s admin/HR has access to attendance and reports',
                            'Firebase (Google) — acts solely as cloud infrastructure provider',
                            'Data may be disclosed only upon court order or valid legal request',
                            'No social media, advertising, or marketing partners',
                          ],
                        ),
                        const SizedBox(height: 16),

                        _buildSection(
                          tc,
                          number: '5',
                          title: 'Data Retention',
                          icon: Icons.schedule_rounded,
                          bullets: const [
                            'Attendance logs: 5 years (for BIR / DOLE compliance)',
                            'Security logs: 1 year',
                            'Session data: up to 30 minutes after logout',
                            'Profile photos: until resignation or deletion request',
                            'After the retention period, data is automatically purged',
                          ],
                        ),
                        const SizedBox(height: 16),

                        _buildSection(
                          tc,
                          number: '6',
                          title: 'Your Rights',
                          icon: Icons.verified_user_outlined,
                          bullets: const [
                            'Right to access — know what data we hold about you',
                            'Right to correction — update inaccurate information',
                            'Right to deletion — request removal (subject to legal retention)',
                            'Right to portability — obtain a copy of your data',
                            'Right to object — contest processing if you have valid grounds',
                            'To make a request, email our DPO using the contact below',
                          ],
                        ),
                        const SizedBox(height: 16),

                        _buildSection(
                          tc,
                          number: '7',
                          title: 'Data Privacy Act Compliance',
                          icon: Icons.gavel_rounded,
                          bullets: const [
                            'We comply with Republic Act No. 10173 (Data Privacy Act of 2012)',
                            'Our processing activities are registered with the National Privacy Commission (NPC)',
                            'Our Data Protection Officer (DPO) handles all privacy requests',
                            'All employees undergo privacy awareness training',
                          ],
                        ),
                        const SizedBox(height: 16),

                        _buildSection(
                          tc,
                          number: '8',
                          title: 'Security Measures',
                          icon: Icons.lock_outline_rounded,
                          bullets: const [
                            'End-to-end encryption of data in transit (HTTPS/TLS)',
                            'Server-side Firestore security rules for role-based access',
                            'Device integrity checks (jailbreak / root detection)',
                            'Session monitoring with auto-logout after 30 minutes of inactivity',
                            'Mock GPS / fake location apps are not accepted',
                          ],
                        ),
                        const SizedBox(height: 16),

                        _buildContactCard(tc),
                        const SizedBox(height: 24),

                        _buildFooter(tc),
                      ],
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

  // ═══════════════════════════════════════════════════════════════
  // HEADER
  // ═══════════════════════════════════════════════════════════════
  Widget _buildHeader(BuildContext context, _PolicyColors tc) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      decoration: const BoxDecoration(
        gradient: _PolicyColors.brandGradient,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Back button
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chevron_left_rounded,
                      color: Colors.white, size: 22),
                  SizedBox(width: 4),
                  Text(
                    'Back',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Row(
            children: [
              Icon(Icons.privacy_tip_rounded, color: Colors.white, size: 26),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Privacy Policy',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'R.A.C.O.M.A HRIS — Version $_version  •  Effective $_effectiveDate',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // INTRO CARD
  // ═══════════════════════════════════════════════════════════════
  Widget _buildIntroCard(_PolicyColors tc) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tc.highlight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _PolicyColors.orange.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _PolicyColors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.info_outline_rounded,
                  color: _PolicyColors.orange,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Your privacy matters to us',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _PolicyColors.orange,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'R.A.C.O.M.A HRIS is an attendance and monitoring system used by your employer. '
                'This privacy policy describes what data we collect, how we use it, and how we protect your information. '
                'By using this application, you agree to the terms outlined herein.',
            style: TextStyle(
              fontSize: 13,
              height: 1.55,
              color: tc.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // SECTION BUILDER
  // ═══════════════════════════════════════════════════════════════
  Widget _buildSection(
      _PolicyColors tc, {
        required String number,
        required String title,
        required IconData icon,
        required List<String> bullets,
      }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tc.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tc.cardBorder.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  gradient: _PolicyColors.brandGradient,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '$number. $title',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: tc.textPrimary,
                      height: 1.3,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...bullets.map((b) => Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6, right: 10),
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: const BoxDecoration(
                      color: _PolicyColors.orange,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    b,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: tc.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // CONTACT CARD
  // ═══════════════════════════════════════════════════════════════
  Widget _buildContactCard(_PolicyColors tc) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: _PolicyColors.brandGradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.contact_support_rounded,
                  color: Colors.white, size: 22),
              SizedBox(width: 10),
              Text(
                'Contact Our DPO',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'For questions about your data or to submit a privacy request, '
                'please contact our Data Protection Officer:',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 12.5,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          _contactButton(
            icon: Icons.email_rounded,
            label: _dpoEmail,
            onTap: () => _launchEmail(_dpoEmail),
          ),
          const SizedBox(height: 8),
          _contactButton(
            icon: Icons.support_agent_rounded,
            label: _supportEmail,
            onTap: () => _launchEmail(_supportEmail),
          ),
        ],
      ),
    );
  }

  Widget _contactButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Icon(Icons.open_in_new_rounded,
                color: Colors.white70, size: 14),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // FOOTER
  // ═══════════════════════════════════════════════════════════════
  Widget _buildFooter(_PolicyColors tc) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tc.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tc.cardBorder.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.verified_rounded,
            color: _PolicyColors.orange.withValues(alpha: 0.7),
            size: 28,
          ),
          const SizedBox(height: 10),
          Text(
            'Compliant with Republic Act No. 10173',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: tc.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Data Privacy Act of 2012\nNational Privacy Commission (NPC)',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.5,
              color: tc.textMuted,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            height: 1,
            color: tc.divider,
          ),
          const SizedBox(height: 12),
          Text(
            'Last updated: $_effectiveDate\nVersion $_version',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10.5,
              fontStyle: FontStyle.italic,
              color: tc.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // EMAIL LAUNCHER
  // ═══════════════════════════════════════════════════════════════
  Future<void> _launchEmail(String email) async {
    final uri = Uri(
      scheme: 'mailto',
      path: email,
      query: 'subject=Privacy Policy Inquiry — R.A.C.O.M.A HRIS',
    );
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        debugPrint('⚠️ Could not launch email to $email');
      }
    } catch (e) {
      debugPrint('⚠️ launchUrl failed: $e');
    }
  }
}