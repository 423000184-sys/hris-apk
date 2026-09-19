// lib/screens/notification_backup_list_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../services/notification_backup_service.dart';
import 'admin_theme.dart';

class NotificationBackupListPage extends StatefulWidget {
  const NotificationBackupListPage({super.key});

  @override
  State<NotificationBackupListPage> createState() =>
      _NotificationBackupListPageState();
}

class _NotificationBackupListPageState
    extends State<NotificationBackupListPage> {
  List<NotificationBackupInfo> _backups = [];
  bool _loading = true;
  int _totalSize = 0;
  String _dir = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final files = await NotificationBackupService.instance.listBackups();
    final size = await NotificationBackupService.instance.getTotalSize();
    final dir = await NotificationBackupService.instance.getBackupDirectory();
    if (mounted) {
      setState(() {
        _backups = files;
        _totalSize = size;
        _dir = dir;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // ✅ Use AnimatedBuilder para live update kapag nag-toggle ng theme
    return AnimatedBuilder(
      animation: ThemeProvider.instance,
      builder: (context, _) {
        // ✅ Use ThemeProvider directly — hindi nag-follow sa system theme
        final tc = ThemeProvider.instance.colors;

        return Scaffold(
          backgroundColor: tc.background,
          appBar: AppBar(
            backgroundColor: tc.topBarBg,
            foregroundColor: tc.text,
            elevation: 0,
            scrolledUnderElevation: 0,
            surfaceTintColor: Colors.transparent,
            title: Text(
              'Notification Backups',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: tc.text,
              ),
            ),
            actions: [
              IconButton(
                tooltip: 'Refresh',
                icon: Icon(Icons.refresh_rounded,
                    color: tc.textMuted, size: 20),
                onPressed: _load,
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
              _summaryCard(tc),
              Expanded(
                child: _backups.isEmpty
                    ? _emptyState(tc)
                    : RefreshIndicator(
                  color: tc.orange,
                  onRefresh: _load,
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
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // SUMMARY CARD
  // ═══════════════════════════════════════════════════════════════
  Widget _summaryCard(AdminColors tc) {
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
              Icon(Icons.backup_rounded, color: tc.orange, size: 18),
              const SizedBox(width: 8),
              Text(
                '${_backups.length} backup file${_backups.length == 1 ? "" : "s"}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: tc.text,
                ),
              ),
              const Spacer(),
              Text(
                _fmtSize(_totalSize),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: tc.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                kIsWeb ? Icons.language_rounded : Icons.folder_rounded,
                size: 12,
                color: tc.muted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _dir,
                  style: TextStyle(
                    fontSize: 10,
                    color: tc.muted,
                    fontFamily: 'monospace',
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            kIsWeb
                ? '💡 Naka-save sa browser localStorage'
                : '💡 Single file log — append kada may bagong notification',
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

  // ═══════════════════════════════════════════════════════════════
  // TILE
  // ═══════════════════════════════════════════════════════════════
  Widget _tile(AdminColors tc, NotificationBackupInfo file) {
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
                      fontSize: 12,
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
                            fontSize: 11, color: tc.textMuted),
                      ),
                      const SizedBox(width: 10),
                      Icon(Icons.data_usage_rounded,
                          size: 11, color: tc.muted),
                      const SizedBox(width: 4),
                      Text(
                        _fmtSize(file.sizeBytes),
                        style: TextStyle(
                            fontSize: 11, color: tc.textMuted),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: tc.muted, size: 20),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // VIEW FILE
  // ═══════════════════════════════════════════════════════════════
  void _viewFile(AdminColors tc, NotificationBackupInfo file) async {
    final content =
    await NotificationBackupService.instance.readBackup(file.path);

    if (!mounted) return;
    if (content == null || content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Walang content'),
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
        initialChildSize: 0.85,
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
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: tc.orange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.description_rounded,
                      color: tc.orange,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          file.filename,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: tc.text,
                            fontFamily: 'monospace',
                          ),
                        ),
                        Text(
                          '${_fmtTime(file.savedAt)} · ${_fmtSize(file.sizeBytes)}',
                          style: TextStyle(
                            fontSize: 10,
                            color: tc.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Divider(height: 1, color: tc.border),

            // Content
            Expanded(
              child: Container(
                width: double.infinity,
                color: tc.isDark
                    ? const Color(0xFF0F0F10)
                    : const Color(0xFFF5F5F5),
                child: SingleChildScrollView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(
                    content,
                    style: TextStyle(
                      fontSize: 11,
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

  // ═══════════════════════════════════════════════════════════════
  // QUICK ACTIONS
  // ═══════════════════════════════════════════════════════════════
  void _showQuickActions(AdminColors tc, NotificationBackupInfo file) {
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
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // CONFIRM DIALOGS
  // ═══════════════════════════════════════════════════════════════
  Future<void> _confirmDelete(
      AdminColors tc, NotificationBackupInfo file) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: tc.card,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text('Delete this file?',
            style: TextStyle(
                color: tc.text, fontWeight: FontWeight.w800)),
        content: Text(file.filename,
            style: TextStyle(
                color: tc.textMuted,
                fontSize: 12,
                fontFamily: 'monospace')),
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
      await NotificationBackupService.instance.deleteBackup(file.path);
      _load();
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
      await NotificationBackupService.instance.deleteAll();
      _load();
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // EMPTY STATE
  // ═══════════════════════════════════════════════════════════════
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
                color: tc.orange.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.inbox_rounded,
                  size: 32, color: tc.orange),
            ),
            const SizedBox(height: 16),
            Text('Walang backups pa',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: tc.text)),
            const SizedBox(height: 6),
            Text(
              'Auto-save kada may bagong notification.\nMag-clock in ang employee para mag-test.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13, color: tc.textMuted, height: 1.5),
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

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}