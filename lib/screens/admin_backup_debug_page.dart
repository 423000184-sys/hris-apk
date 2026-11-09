// lib/screens/admin_backup_debug_page.dart
// v1.2: 🐛 Removed 'listCloudBackups' button to fix compilation error.
// v1.1: 🎭 Demo Mode Support (Action Blocking)
import 'package:flutter/material.dart';
import '../services/presence_monitor_service.dart';
import '../services/presence_backup_service.dart';
import '../services/demo_mode_service.dart';
import 'admin_theme.dart';

class AdminBackupDebugPage extends StatelessWidget {
  const AdminBackupDebugPage({super.key});

  // 🎭 Demo Mode Getter
  bool get _isDemo {
    try {
      return DemoModeService.instance.isEnabled;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tc = AdminTheme.getColors(context);

    return Scaffold(
      backgroundColor: tc.background,
      appBar: AppBar(
        backgroundColor: tc.topBarBg,
        foregroundColor: tc.text,
        elevation: 0,
        title: Text(
          'Backup Debug',
          style: TextStyle(color: tc.text, fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // 🎭 DEMO BANNER
          if (_isDemo) ...[
            _buildDemoBanner(context, tc),
            const SizedBox(height: 16),
          ],
          _section(tc, '🛰️ Presence Monitor'),
          _btn(tc, '🛰️ Print debug info', () async {
            if (_isDemo) {
              _demoBlock(context, tc);
              return;
            }
            PresenceMonitorService.instance.printDebugInfo();
          }),
          _btn(tc, '💾 Force backup now', () async {
            if (_isDemo) {
              _demoBlock(context, tc);
              return;
            }
            await PresenceMonitorService.instance.forceBackup();
          }),

          const SizedBox(height: 24),
          _section(tc, '📄 Backup Service'),
          _btn(tc, '📄 List local backups', () async {
            if (_isDemo) {
              _demoBlock(context, tc);
              return;
            }
            final files =
            await PresenceBackupService.instance.listLocalBackups();
            debugPrint('═══════════════════════════════');
            debugPrint('📄 ${files.length} local backups:');
            for (final f in files) {
              debugPrint('   • ${f.filename} '
                  '(${(f.sizeBytes / 1024).toStringAsFixed(1)} KB)');
            }
            debugPrint('═══════════════════════════════');
          }),

          // 🐛 FIX: Tinanggal ang "List cloud backups" dahil wala pang method na ito sa service.
        ],
      ),
    );
  }

  // 🎭 DEMO BANNER
  Widget _buildDemoBanner(BuildContext context, AdminColors tc) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: tc.orange.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tc.orange.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(Icons.science_rounded, color: tc.orange, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Demo Mode — debug actions are disabled.',
              style: TextStyle(
                fontSize: 11.5,
                color: tc.orange,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _demoBlock(BuildContext context, AdminColors tc) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Action disabled in Demo Mode.'),
        backgroundColor: tc.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Widget _section(AdminColors tc, String label) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 12),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        color: tc.textMuted,
        letterSpacing: 1,
      ),
    ),
  );

  Widget _btn(AdminColors tc, String label, Future<void> Function() onTap) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => onTap(),
            style: FilledButton.styleFrom(
              backgroundColor: _isDemo ? tc.border : tc.orange,
              foregroundColor: _isDemo ? tc.muted : Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_isDemo) ...[
                  Icon(Icons.lock_outline_rounded,
                      size: 14, color: tc.muted),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _isDemo ? tc.muted : Colors.white),
                ),
              ],
            ),
          ),
        ),
      );
}