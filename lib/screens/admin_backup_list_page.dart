// lib/screens/admin_backup_list_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../services/presence_backup_service.dart';
import 'admin_theme.dart';

class AdminBackupListPage extends StatefulWidget {
  final String employeeId;
  final String employeeName;

  const AdminBackupListPage({
    super.key,
    required this.employeeId,
    required this.employeeName,
  });

  @override
  State<AdminBackupListPage> createState() => _AdminBackupListPageState();
}

class _AdminBackupListPageState extends State<AdminBackupListPage> {
  List<BackupFileInfo> _backups = [];
  bool _loading = true;
  int _totalSizeBytes = 0;
  String _backupDir = '';

  @override
  void initState() {
    super.initState();
    _loadBackups();
  }

  Future<void> _loadBackups() async {
    setState(() => _loading = true);
    final files = await PresenceBackupService.instance.listLocalBackups();
    final size = await PresenceBackupService.instance.getTotalSizeBytes();
    final dir = await PresenceBackupService.instance.getBackupDirectory();

    if (mounted) {
      setState(() {
        _backups = files;
        _totalSizeBytes = size;
        _backupDir = dir;
        _loading = false;
      });
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
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Local Backups',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: tc.text,
              ),
            ),
            Text(
              widget.employeeName,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: tc.textMuted,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: Icon(Icons.refresh_rounded, color: tc.textMuted, size: 20),
            onPressed: _loadBackups,
          ),
          if (_backups.isNotEmpty)
            IconButton(
              tooltip: 'Delete all',
              icon: Icon(Icons.delete_sweep_rounded,
                  color: tc.red, size: 20),
              onPressed: () => _confirmDeleteAll(tc),
            ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: tc.border),
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: tc.orange))
          : Column(
        children: [
          _buildSummaryCard(tc),
          Expanded(
            child: _backups.isEmpty
                ? _emptyState(tc)
                : RefreshIndicator(
              color: tc.orange,
              onRefresh: _loadBackups,
              child: ListView.separated(
                padding:
                const EdgeInsets.symmetric(vertical: 8),
                itemCount: _backups.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color: tc.border,
                  indent: 16,
                ),
                itemBuilder: (_, i) =>
                    _tile(tc, _backups[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(AdminColors tc) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tc.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.folder_rounded, color: tc.orange, size: 18),
              const SizedBox(width: 8),
              Text(
                '${_backups.length} backup files',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: tc.text,
                ),
              ),
              const Spacer(),
              Text(
                _formatSize(_totalSizeBytes),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: tc.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '📁 $_backupDir',
            style: TextStyle(
              fontSize: 10,
              color: tc.muted,
              fontFamily: 'monospace',
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            '💡 Local device storage only — hindi naka-sync sa cloud',
            style: TextStyle(
              fontSize: 10,
              color: tc.muted,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(AdminColors tc, BackupFileInfo file) {
    return InkWell(
      onTap: () => _viewFile(tc, file),
      onLongPress: () => _showQuickActions(tc, file),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: tc.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.description_rounded,
                color: tc.orange,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.filename,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: tc.text,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.schedule_rounded,
                          size: 11, color: tc.muted),
                      const SizedBox(width: 4),
                      Text(
                        _fmtTime(file.savedAt),
                        style: TextStyle(
                          fontSize: 11,
                          color: tc.textMuted,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Icon(Icons.data_usage_rounded,
                          size: 11, color: tc.muted),
                      const SizedBox(width: 4),
                      Text(
                        _formatSize(file.sizeBytes),
                        style: TextStyle(
                          fontSize: 11,
                          color: tc.textMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: tc.muted,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  void _viewFile(AdminColors tc, BackupFileInfo file) async {
    final content = await PresenceBackupService.instance
        .readBackup(file.path);

    if (!mounted) return;

    if (content == null || content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Cannot read file'),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: tc.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollCtrl) => Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: tc.border,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Icon(Icons.description_rounded,
                      color: tc.orange, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      file.filename,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: tc.text,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Divider(height: 1, color: tc.border),
            // Content
            Expanded(
              child: Container(
                width: double.infinity,
                color: tc.isDark
                    ? const Color(0xFF1A1A1A)
                    : const Color(0xFFF5F5F5),
                child: SingleChildScrollView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(
                    content,
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: tc.text,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ),
            // Footer buttons
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _confirmDelete(tc, file);
                        },
                        icon: Icon(Icons.delete_outline_rounded,
                            size: 16, color: tc.red),
                        label: Text(
                          'Delete',
                          style: TextStyle(
                            color: tc.red,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: tc.border),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context),
                        style: FilledButton.styleFrom(
                          backgroundColor: tc.orange,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text(
                          'Close',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showQuickActions(AdminColors tc, BackupFileInfo file) {
    showModalBottomSheet(
      context: context,
      backgroundColor: tc.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(Icons.visibility_rounded, color: tc.orange),
              title: Text('View content',
                  style: TextStyle(color: tc.text)),
              onTap: () {
                Navigator.pop(context);
                _viewFile(tc, file);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: tc.red),
              title: Text('Delete', style: TextStyle(color: tc.text)),
              onTap: () {
                Navigator.pop(context);
                _confirmDelete(tc, file);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(AdminColors tc, BackupFileInfo file) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: tc.card,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text('Delete this file?',
            style: TextStyle(
                color: tc.text, fontWeight: FontWeight.w800)),
        content: Text(
          file.filename,
          style: TextStyle(
            color: tc.textMuted,
            fontSize: 12,
            fontFamily: 'monospace',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel',
                style: TextStyle(
                    color: tc.textMuted, fontWeight: FontWeight.w700)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: tc.red),
            child: const Text('Delete',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (ok == true) {
      await PresenceBackupService.instance.deleteBackup(file.path);
      _loadBackups();
    }
  }

  Future<void> _confirmDeleteAll(AdminColors tc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: tc.card,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text('Delete ALL backups?',
            style: TextStyle(
                color: tc.text, fontWeight: FontWeight.w800)),
        content: Text(
          'Burahin lahat ng ${_backups.length} files? Hindi na maibabalik.',
          style: TextStyle(color: tc.textMuted, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel',
                style: TextStyle(
                    color: tc.textMuted, fontWeight: FontWeight.w700)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: tc.red),
            child: const Text('Delete all',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (ok == true) {
      await PresenceBackupService.instance.deleteAllBackups();
      _loadBackups();
    }
  }

  Widget _emptyState(AdminColors tc) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: tc.orangeLight,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.folder_off_rounded,
                size: 32,
                color: tc.orange,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Walang local backups',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: tc.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              kIsWeb
                  ? 'Hindi supported sa web.\nGamitin sa mobile device.'
                  : 'Babalik ito every 1 hour.\nO i-tap yung "Force Backup Now".',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: tc.textMuted,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════
  String _fmtTime(DateTime d) {
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inMinutes < 1) return 'Ngayon lang';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d, hh:mm a').format(d);
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}