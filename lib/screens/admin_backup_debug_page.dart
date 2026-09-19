// lib/screens/admin_backup_debug_page.dart
import 'package:flutter/material.dart';
import '../services/presence_monitor_service.dart';
import '../services/presence_backup_service.dart';
import 'admin_theme.dart';

class AdminBackupDebugPage extends StatelessWidget {
  const AdminBackupDebugPage({super.key});

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
          _section(tc, '🛰️ Presence Monitor'),
          _btn(tc, '🛰️ Print debug info', () async {
            PresenceMonitorService.instance.printDebugInfo();
          }),
          _btn(tc, '💾 Force backup now', () async {
            await PresenceMonitorService.instance.forceBackup();
          }),

          const SizedBox(height: 24),
          _section(tc, '📄 Backup Service'),
          _btn(tc, '📄 List local backups', () async {
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
          _btn(tc, '☁️ List cloud backups (emp-01-2026)', () async {
            final files = await PresenceBackupService.instance
                .listCloudBackups('emp-01-2026');
            debugPrint('═══════════════════════════════');
            debugPrint('☁️ ${files.length} cloud backups:');
            for (final f in files) {
              debugPrint('   • ${f.filename}');
              debugPrint('     ${f.url}');
            }
            debugPrint('═══════════════════════════════');
          }),
        ],
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
              backgroundColor: tc.orange,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      );
}