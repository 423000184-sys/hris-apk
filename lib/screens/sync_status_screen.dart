// lib/screens/sync_status_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/offline_attendance_service.dart';

class SyncStatusScreen extends StatefulWidget {
  const SyncStatusScreen({super.key});

  @override
  State<SyncStatusScreen> createState() => _SyncStatusScreenState();
}

class _SyncStatusScreenState extends State<SyncStatusScreen> {
  List<Map<String, dynamic>> _records = [];
  bool _loading = true;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final records = await OfflineAttendanceService.instance.getAll();
    if (!mounted) return;
    setState(() {
      _records = records;
      _loading = false;
    });
  }

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    final count = await OfflineAttendanceService.instance.syncPending();
    if (!mounted) return;
    setState(() => _syncing = false);
    await _load();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Synced $count records'),
        backgroundColor: const Color(0xFF16A34A),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pending = _records.where((r) => r['synced'] == 0).length;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0F),
        foregroundColor: Colors.white,
        title: const Text('Sync Status'),
        actions: [
          if (pending > 0)
            TextButton.icon(
              onPressed: _syncing ? null : _syncNow,
              icon: _syncing
                  ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Color(0xFFFF8A00)),
              )
                  : const Icon(Icons.sync_rounded,
                  color: Color(0xFFFF8A00)),
              label: const Text('Sync Now',
                  style: TextStyle(color: Color(0xFFFF8A00))),
            ),
        ],
      ),
      body: _loading
          ? const Center(
          child: CircularProgressIndicator(color: Color(0xFFFF8A00)))
          : _records.isEmpty
          ? const Center(
        child: Text(
          'Walang records',
          style: TextStyle(color: Colors.white54),
        ),
      )
          : Column(
        children: [
          if (pending > 0)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: const Color(0xFFFF8A00).withValues(alpha: 0.15),
              child: Row(
                children: [
                  const Icon(Icons.cloud_off_rounded,
                      color: Color(0xFFFF8A00)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '$pending record(s) waiting to sync',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _records.length,
              itemBuilder: (_, i) =>
                  _buildRecordTile(_records[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordTile(Map<String, dynamic> r) {
    final isSynced = r['synced'] == 1;
    final type = r['type'] as String;
    final ts = DateTime.tryParse(r['timestamp'] as String? ?? '');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (type == 'IN'
                  ? const Color(0xFF16A34A)
                  : const Color(0xFFDC2626))
                  .withValues(alpha: 0.15),
            ),
            child: Icon(
              type == 'IN'
                  ? Icons.login_rounded
                  : Icons.logout_rounded,
              color: type == 'IN'
                  ? const Color(0xFF16A34A)
                  : const Color(0xFFDC2626),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Clock $type',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                if (ts != null)
                  Text(
                    DateFormat('MMM d, hh:mm a').format(ts),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: (isSynced
                  ? const Color(0xFF16A34A)
                  : const Color(0xFFFF8A00))
                  .withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isSynced
                      ? Icons.cloud_done_rounded
                      : Icons.cloud_off_rounded,
                  color: isSynced
                      ? const Color(0xFF16A34A)
                      : const Color(0xFFFF8A00),
                  size: 12,
                ),
                const SizedBox(width: 4),
                Text(
                  isSynced ? 'Synced' : 'Pending',
                  style: TextStyle(
                    color: isSynced
                        ? const Color(0xFF16A34A)
                        : const Color(0xFFFF8A00),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}