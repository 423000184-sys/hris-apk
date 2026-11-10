// lib/screens/admin_device_management_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/onesignal_sender.dart';
import 'admin_theme.dart';

class AdminDeviceManagementScreen extends StatefulWidget {
  const AdminDeviceManagementScreen({super.key});

  @override
  State<AdminDeviceManagementScreen> createState() =>
      _AdminDeviceManagementScreenState();
}

class _AdminDeviceManagementScreenState
    extends State<AdminDeviceManagementScreen> {
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  bool _processing = false;
  String? _processingEmployeeId;

  AdminColors get _c => ThemeProvider.instance.colors;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _revokeDevice({
    required String employeeId,
    required String employeeName,
    required String? currentDeviceId,
  }) async {
    final reasonCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _c.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.phonelink_erase, color: _c.red, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Revoke Device',
                style: TextStyle(
                  color: _c.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'I-revoke ang device ni $employeeName?\n\n'
                    'Ang lumang device ay mawi-wipe sa susunod na online niya. '
                    'Makaka-login siya sa bagong device pagkatapos.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: _c.textMuted,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: reasonCtrl,
                style: TextStyle(color: _c.text),
                decoration: InputDecoration(
                  labelText: 'Reason (optional)',
                  labelStyle: TextStyle(color: _c.muted),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  isDense: true,
                ),
                maxLines: 2,
              ),
              if (currentDeviceId != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _c.surface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _c.border),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.memory, size: 14, color: _c.muted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Current: ${currentDeviceId.substring(0, 8)}...',
                          style: TextStyle(
                            fontSize: 11,
                            color: _c.muted,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: _c.textMuted)),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.phonelink_erase, size: 16),
            label: const Text('Revoke'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _c.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _processing = true;
      _processingEmployeeId = employeeId;
    });

    try {
      final reason = reasonCtrl.text.trim().isEmpty
          ? 'Admin-initiated transfer'
          : reasonCtrl.text.trim();

      final sent = await OneSignalSender.instance.revokeEmployeeDevice(
        employeeId: employeeId,
        reason: reason,
      );

      await FirebaseFirestore.instance
          .collection('employees')
          .doc(employeeId)
          .update({
        'activeDeviceId': FieldValue.delete(),
        'deviceBoundAt': FieldValue.delete(),
        'lastRevokedAt': FieldValue.serverTimestamp(),
      });

      await FirebaseFirestore.instance.collection('device_audit').add({
        'employeeId': employeeId,
        'employeeName': employeeName,
        'action': 'REVOKE',
        'oldDeviceId': currentDeviceId,
        'reason': reason,
        'pushSent': sent,
        'timestamp': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            sent
                ? '✅ Revoke signal sent. Old device will be wiped.'
                : '⚠️ Binding cleared but push failed. Will wipe on next app open.',
          ),
          backgroundColor: sent ? Colors.green : Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error: $e'),
          backgroundColor: _c.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      reasonCtrl.dispose();
      if (mounted) {
        setState(() {
          _processing = false;
          _processingEmployeeId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ThemeProvider.instance,
      builder: (context, _) {
        final c = ThemeProvider.instance.colors;
        return Container(
          color: c.background,
          child: Column(
            children: [
              _buildHeader(c),
              _buildSearchBar(c),
              Expanded(child: _buildEmployeeList(c)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(AdminColors c) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [c.orange, c.orange.withValues(alpha: 0.7)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.phonelink_setup_rounded,
                color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Device Management',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: c.text,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Manage employee device bindings & revoke access',
                  style: TextStyle(fontSize: 12, color: c.textMuted),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Audit History',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const _AuditHistoryScreen(),
                ),
              );
            },
            icon: Icon(Icons.history, color: c.orange),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(AdminColors c) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: TextField(
        controller: _searchCtrl,
        style: TextStyle(color: c.text, fontSize: 14),
        cursorColor: c.orange,
        decoration: InputDecoration(
          hintText: 'Search by name or employee ID...',
          hintStyle: TextStyle(color: c.muted, fontSize: 13),
          prefixIcon: Icon(Icons.search, color: c.muted, size: 20),
          filled: true,
          fillColor: c.surface,
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: c.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: c.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: c.orange, width: 1.5),
          ),
        ),
        onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
      ),
    );
  }

  Widget _buildEmployeeList(AdminColors c) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('employees').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(color: c.orange));
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error: ${snapshot.error}',
              style: TextStyle(color: c.red),
            ),
          );
        }

        final allDocs = snapshot.data?.docs ?? [];
        final Map<String, QueryDocumentSnapshot> uniqueEmployees = {};

        // ═══════════════════════════════════════════════════════════════
        // 🚨 FILTERING LOGIC: DEMO & DUPLICATES LANG ANG TINATANGGAL
        // ═══════════════════════════════════════════════════════════════
        for (final doc in allDocs) {
          final data = doc.data() as Map<String, dynamic>;

          final docId = doc.id.toLowerCase();
          final empIdStr = (data['employeeId'] ?? '').toString().toLowerCase();
          final nameStr = (data['name'] ?? '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}').toString().toLowerCase();
          final emailStr = (data['email'] ?? '').toString().toLowerCase();

          // 1. Filter Demo Accounts
          if (docId.contains('demo') ||
              empIdStr.contains('demo') ||
              nameStr.contains('demo') ||
              emailStr.contains('demo') ||
              data['isDemo'] == true) {
            continue;
          }

          // 2. Duplicate Check (Para isa lang si April)
          final key = empIdStr.isNotEmpty ? empIdStr : docId;

          if (uniqueEmployees.containsKey(key)) {
            final existingDoc = uniqueEmployees[key]!;
            final existingData = existingDoc.data() as Map<String, dynamic>;

            final existingDevice = existingData['activeDeviceId'] as String?;
            final currentDevice = data['activeDeviceId'] as String?;

            final existingHasDevice = existingDevice != null && existingDevice.isNotEmpty;
            final currentHasDevice = currentDevice != null && currentDevice.isNotEmpty;

            // Kung yung bagong nahanap ay may device, palitan natin yung luma
            if (currentHasDevice && !existingHasDevice) {
              uniqueEmployees[key] = doc;
            }
          } else {
            uniqueEmployees[key] = doc;
          }
        }

        // Gawing listahan ulit
        var activeDocs = uniqueEmployees.values.toList();

        // 3. Search Bar Filter
        final filtered = activeDocs.where((doc) {
          if (_searchQuery.isEmpty) return true;
          final data = doc.data() as Map<String, dynamic>;
          final name = (data['name'] ??
              '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}')
              .toString()
              .toLowerCase();
          final empId =
          (data['employeeId'] ?? doc.id).toString().toLowerCase();
          return name.contains(_searchQuery) || empId.contains(_searchQuery);
        }).toList();

        // 4. Sort Alphabetically
        filtered.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          final aName = (aData['name'] ?? '').toString().toLowerCase();
          final bName = (bData['name'] ?? '').toString().toLowerCase();
          return aName.compareTo(bName);
        });

        if (filtered.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.search_off, size: 56, color: c.muted),
                const SizedBox(height: 12),
                Text(
                  'No employees found',
                  style: TextStyle(color: c.textMuted, fontSize: 14),
                ),
              ],
            ),
          );
        }

        final totalBound = filtered.where((d) {
          final data = d.data() as Map<String, dynamic>;
          final id = data['activeDeviceId'] as String?;
          return id != null && id.isNotEmpty;
        }).length;

        return Column(
          children: [
            // Stats bar
            Container(
              margin: const EdgeInsets.fromLTRB(24, 8, 24, 12),
              padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.border),
              ),
              child: Row(
                children: [
                  _statChip(
                    c: c,
                    icon: Icons.people_alt_rounded,
                    label: 'Total',
                    value: '${filtered.length}',
                    color: c.orange,
                  ),
                  const SizedBox(width: 16),
                  _statChip(
                    c: c,
                    icon: Icons.phonelink_lock,
                    label: 'Bound',
                    value: '$totalBound',
                    color: Colors.green,
                  ),
                  const SizedBox(width: 16),
                  _statChip(
                    c: c,
                    icon: Icons.phonelink_erase,
                    label: 'Unbound',
                    value: '${filtered.length - totalBound}',
                    color: Colors.grey,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                itemCount: filtered.length,
                itemBuilder: (context, i) {
                  return _buildEmployeeCard(c, filtered[i]);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _statChip({
    required AdminColors c,
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: c.textMuted),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmployeeCard(AdminColors c, QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final employeeId = doc.id;
    final employeeName = (data['name'] ??
        '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}')
        .toString()
        .trim();
    final activeDeviceId = data['activeDeviceId'] as String?;
    final isBound = activeDeviceId != null && activeDeviceId.isNotEmpty;
    final isProcessing =
        _processing && _processingEmployeeId == employeeId;
    final boundAt = data['deviceBoundAt'] as Timestamp?;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isBound ? Colors.green.withValues(alpha: 0.3) : c.border,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: isBound && !isProcessing
              ? () => _revokeDevice(
            employeeId: employeeId,
            employeeName:
            employeeName.isEmpty ? 'Unknown' : employeeName,
            currentDeviceId: activeDeviceId,
          )
              : null,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: isBound
                      ? Colors.green.withValues(alpha: 0.15)
                      : c.muted.withValues(alpha: 0.15),
                  child: Icon(
                    isBound ? Icons.phonelink_lock : Icons.phonelink_erase,
                    color: isBound ? Colors.green : c.muted,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        employeeName.isEmpty ? 'Unknown Employee' : employeeName,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: c.text,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(Icons.badge_outlined, size: 11, color: c.muted),
                          const SizedBox(width: 4),
                          Text(
                            'ID: ${data['employeeId'] ?? employeeId}',
                            style:
                            TextStyle(fontSize: 11, color: c.textMuted),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isBound ? Colors.green : c.muted,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              isBound
                                  ? 'Bound: ${activeDeviceId.substring(0, 8)}...'
                                  : 'No device bound',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color:
                                isBound ? Colors.green.shade700 : c.muted,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isBound && boundAt != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              _formatDate(boundAt.toDate()),
                              style: TextStyle(
                                fontSize: 10,
                                color: c.muted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (isProcessing)
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: c.orange),
                  )
                else if (isBound)
                  IconButton(
                    tooltip: 'Revoke Device',
                    icon: Icon(Icons.phonelink_erase, color: c.red, size: 20),
                    onPressed: () => _revokeDevice(
                      employeeId: employeeId,
                      employeeName:
                      employeeName.isEmpty ? 'Unknown' : employeeName,
                      currentDeviceId: activeDeviceId,
                    ),
                  )
                else
                  Icon(Icons.check_circle_outline, color: c.muted, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day}/${dt.year}';
  }
}

// ═══════════════════════════════════════════════════════════════
// AUDIT HISTORY SCREEN
// ═══════════════════════════════════════════════════════════════
class _AuditHistoryScreen extends StatelessWidget {
  const _AuditHistoryScreen();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ThemeProvider.instance,
      builder: (context, _) {
        final c = ThemeProvider.instance.colors;
        return Scaffold(
          backgroundColor: c.background,
          appBar: AppBar(
            backgroundColor: c.card,
            foregroundColor: c.text,
            elevation: 0,
            title: const Text('Device Audit History'),
          ),
          body: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('device_audit')
                .orderBy('timestamp', descending: true)
                .limit(100)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(
                    child: CircularProgressIndicator(color: c.orange));
              }
              final docs = snapshot.data?.docs ?? [];
              if (docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history, size: 56, color: c.muted),
                      const SizedBox(height: 12),
                      Text(
                        'No audit history yet',
                        style: TextStyle(color: c.textMuted, fontSize: 14),
                      ),
                    ],
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final d = docs[i].data() as Map<String, dynamic>;
                  final ts = d['timestamp'] as Timestamp?;
                  final isRevoke = d['action'] == 'REVOKE';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: c.card,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isRevoke
                            ? c.red.withValues(alpha: 0.3)
                            : Colors.green.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: (isRevoke ? c.red : Colors.green)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            isRevoke ? Icons.lock_reset : Icons.link,
                            color: isRevoke ? c.red : Colors.green,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${d['action']} — ${d['employeeName'] ?? 'Unknown'}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: c.text,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                d['reason'] ?? 'No reason',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: c.textMuted,
                                ),
                              ),
                              if (d['oldDeviceId'] != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Old device: ${d['oldDeviceId']}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontFamily: 'monospace',
                                    color: c.muted,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 4),
                              Text(
                                ts != null ? _formatTs(ts.toDate()) : '',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: c.muted,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  String _formatTs(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}