// lib/screens/admin_presence_monitor_screen.dart
// v1.3: 🎭 Demo Mode Support
//       🐛 FIX: RangeError sa initials kapag empty o puro spaces ang name.
//       🐛 FIX: Hindi na mag-render ng "Unnamed" ghost records (walang name & ID).
import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'admin_theme.dart';
import '../widgets/bootstrap_grid.dart';
import '../services/demo_mode_service.dart';

void _secureLog(String m) {
  debugPrint('[PresenceMonitor] $m');
}

enum PresenceStatus { present, idle, offline, unknown }

extension PresenceStatusX on PresenceStatus {
  String get label {
    switch (this) {
      case PresenceStatus.present:
        return 'Present';
      case PresenceStatus.idle:
        return 'Idle';
      case PresenceStatus.offline:
        return 'Offline';
      case PresenceStatus.unknown:
        return 'Unknown';
    }
  }

  Color get color {
    switch (this) {
      case PresenceStatus.present:
        return const Color(0xFF22C55E);
      case PresenceStatus.idle:
        return const Color(0xFFF59E0B);
      case PresenceStatus.offline:
        return const Color(0xFFEF4444);
      case PresenceStatus.unknown:
        return const Color(0xFF9CA3AF);
    }
  }

  IconData get icon {
    switch (this) {
      case PresenceStatus.present:
        return Icons.check_circle_rounded;
      case PresenceStatus.idle:
        return Icons.warning_amber_rounded;
      case PresenceStatus.offline:
        return Icons.cloud_off_rounded;
      case PresenceStatus.unknown:
        return Icons.help_outline_rounded;
    }
  }
}

class PresenceRow {
  final String employeeId;
  final String docId;
  final String name;
  final String role;
  final String department;
  final String photoUrl;
  final bool wfhAccess;
  final bool isDriver;
  final DateTime? lastUpdated;
  final String zone;
  final bool inRange;
  final double? distanceMeters;
  final double? accuracyMeters;
  final bool isOnline;
  final DateTime? outsideSince;
  final int checkCount;

  PresenceRow({
    required this.employeeId,
    required this.docId,
    required this.name,
    required this.role,
    required this.department,
    required this.photoUrl,
    required this.wfhAccess,
    required this.isDriver,
    required this.lastUpdated,
    required this.zone,
    required this.inRange,
    required this.distanceMeters,
    required this.accuracyMeters,
    required this.isOnline,
    required this.outsideSince,
    required this.checkCount,
  });

  PresenceStatus get status {
    if (lastUpdated == null) return PresenceStatus.unknown;
    final diff = DateTime.now().difference(lastUpdated!);
    if (diff.inMinutes >= 15) return PresenceStatus.offline;
    if (diff.inMinutes >= 5) return PresenceStatus.idle;
    return PresenceStatus.present;
  }

  String get lastSeenText {
    if (lastUpdated == null) return 'Walang record';
    final diff = DateTime.now().difference(lastUpdated!);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ${diff.inMinutes % 60}m ago';
    return '${diff.inDays}d ago';
  }

  String get zoneLabel {
    if (wfhAccess && zone == 'outside') return 'WFH (remote)';
    if (isDriver && zone == 'outside') return 'Field duty';
    if (zone == 'inside') return 'Inside office';
    if (zone == 'outside') return 'Outside office';
    return 'Unknown';
  }

  // 🐛 FIX: Safe handling for empty names
  String get initials {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';

    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';

    if (parts.length == 1) {
      return parts[0].substring(0, 1).toUpperCase();
    }

    final first = parts[0].isNotEmpty ? parts[0].substring(0, 1) : '';
    final second = parts[1].isNotEmpty ? parts[1].substring(0, 1) : '';
    return '$first$second'.toUpperCase();
  }
}

class AdminPresenceMonitorScreen extends StatefulWidget {
  const AdminPresenceMonitorScreen({super.key});

  @override
  State<AdminPresenceMonitorScreen> createState() =>
      _AdminPresenceMonitorScreenState();
}

class _AdminPresenceMonitorScreenState extends State<AdminPresenceMonitorScreen> {
  AdminColors get tc => AdminTheme.getColors(context);

  bool get _isDemo {
    try {
      return DemoModeService.instance.isEnabled;
    } catch (_) {
      return false;
    }
  }

  List<PresenceRow> _rows = [];
  bool _loading = true;
  String? _error;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _presenceSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _employeesSub;

  Map<String, Map<String, dynamic>> _employeesById = {};
  Map<String, Map<String, dynamic>> _presenceById = {};

  final _searchCtrl = TextEditingController();
  String _search = '';
  String _statusFilter = 'All';
  String _sort = 'Status';

  Timer? _tickTimer;

  List<PresenceRow> _getMockRows() {
    final now = DateTime.now();
    return [
      PresenceRow(
        employeeId: 'DEMO-001',
        docId: 'demo_emp_1',
        name: 'John Doe',
        role: 'Manager',
        department: 'Operation',
        photoUrl: '',
        wfhAccess: false,
        isDriver: false,
        lastUpdated: now.subtract(const Duration(seconds: 30)),
        zone: 'inside',
        inRange: true,
        distanceMeters: 45.0,
        accuracyMeters: 8.0,
        isOnline: true,
        outsideSince: null,
        checkCount: 12,
      ),
      PresenceRow(
        employeeId: 'DEMO-002',
        docId: 'demo_emp_2',
        name: 'Jane Smith',
        role: 'Accountant',
        department: 'Accounting',
        photoUrl: '',
        wfhAccess: true,
        isDriver: false,
        lastUpdated: now.subtract(const Duration(minutes: 8)),
        zone: 'outside',
        inRange: false,
        distanceMeters: 12400.0,
        accuracyMeters: 25.0,
        isOnline: true,
        outsideSince: now.subtract(const Duration(minutes: 8)),
        checkCount: 5,
      ),
      PresenceRow(
        employeeId: 'DEMO-003',
        docId: 'demo_emp_3',
        name: 'Mike Johnson',
        role: 'Driver',
        department: 'HR/Admin',
        photoUrl: '',
        wfhAccess: false,
        isDriver: true,
        lastUpdated: now.subtract(const Duration(minutes: 2)),
        zone: 'outside',
        inRange: false,
        distanceMeters: 890.0,
        accuracyMeters: 15.0,
        isOnline: true,
        outsideSince: now.subtract(const Duration(minutes: 15)),
        checkCount: 22,
      ),
      PresenceRow(
        employeeId: 'DEMO-004',
        docId: 'demo_emp_4',
        name: 'Sarah Lee',
        role: 'Broker',
        department: 'Operation',
        photoUrl: '',
        wfhAccess: false,
        isDriver: false,
        lastUpdated: now.subtract(const Duration(minutes: 45)),
        zone: 'unknown',
        inRange: false,
        distanceMeters: null,
        accuracyMeters: null,
        isOnline: false,
        outsideSince: null,
        checkCount: 0,
      ),
    ];
  }

  @override
  void initState() {
    super.initState();
    if (_isDemo) {
      _rows = _getMockRows();
      _loading = false;
    } else {
      _startStreams();
    }
    _tickTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _presenceSub?.cancel();
    _employeesSub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _startStreams() {
    if (_isDemo) {
      setState(() {
        _rows = _getMockRows();
        _loading = false;
        _error = null;
      });
      return;
    }

    _loading = true;
    _error = null;

    try {
      _employeesSub?.cancel();
      _employeesSub = FirebaseFirestore.instance
          .collection('employees')
          .snapshots()
          .listen(
            (snap) {
          final map = <String, Map<String, dynamic>>{};
          for (final d in snap.docs) {
            final data = d.data();
            final empId = (data['employeeId'] ?? '').toString();
            final entry = <String, dynamic>{...data, 'id': d.id};
            map[d.id] = entry;
            if (empId.isNotEmpty) map[empId] = entry;
          }
          _employeesById = map;
          _rebuildRows();
        },
        onError: (e) {
          debugPrint('❌ employees stream error: $e');
          if (mounted) {
            setState(() {
              _error = 'Failed to load employees: $e';
              _loading = false;
            });
          }
        },
      );
    } catch (e) {
      debugPrint('❌ employees stream setup: $e');
    }

    try {
      _presenceSub?.cancel();
      _presenceSub = FirebaseFirestore.instance
          .collection('employee_presence')
          .snapshots()
          .listen(
            (snap) {
          final map = <String, Map<String, dynamic>>{};
          for (final d in snap.docs) {
            map[d.id] = d.data();
          }
          _presenceById = map;
          _rebuildRows();
        },
        onError: (e) {
          debugPrint('❌ presence stream error: $e');
          if (mounted) {
            setState(() {
              _error = 'Failed to load presence: $e';
              _loading = false;
            });
          }
        },
      );
    } catch (e) {
      debugPrint('❌ presence stream setup: $e');
    }
  }

  void _rebuildRows() {
    if (_isDemo) return;
    if (!mounted) return;

    final list = <PresenceRow>[];
    final seenDocIds = <String>{};

    for (final entry in _employeesById.values) {
      final docId = (entry['id'] ?? '').toString();
      if (docId.isEmpty) continue;
      if (seenDocIds.contains(docId)) continue;
      seenDocIds.add(docId);

      if (entry['terminated'] == true) continue;

      final empId = (entry['employeeId'] ?? '').toString();

      // 🐛 Extract raw name
      final rawName = (entry['name'] ??
          '${entry['firstName'] ?? ''} ${entry['lastName'] ?? ''}')
          .toString()
          .trim();

      // 🐛 SKIP GHOST RECORDS: Kung walang name at walang employeeId, i-skip na.
      if (rawName.isEmpty && empId.isEmpty) {
        continue;
      }

      // 🐛 FALLBACK NAME: Kung walang name pero may ID, ID ang ipakita.
      final displayName = rawName.isNotEmpty
          ? rawName
          : 'Employee (${empId.isNotEmpty ? empId : docId.substring(0, 6)})';

      final presence = _presenceById[docId] ??
          (empId.isNotEmpty ? _presenceById[empId] : null);

      final role = (entry['role'] ?? entry['position'] ?? '').toString();
      final dept = (entry['department'] ?? '').toString();
      final roleLower = role.toLowerCase();
      final deptLower = dept.toLowerCase();
      final isDriver = roleLower.contains('driver') ||
          roleLower.contains('rider') ||
          deptLower.contains('driver') ||
          deptLower.contains('rider');

      final rawWfh = entry['wfhAccess'];
      final wfh = rawWfh is bool
          ? rawWfh
          : (rawWfh?.toString().toLowerCase() == 'true');

      DateTime? lastUpdated;
      final rawUpdated = presence?['lastUpdated'];
      if (rawUpdated is Timestamp) {
        lastUpdated = rawUpdated.toDate();
      } else {
        final rawLocal = presence?['lastUpdatedLocal'];
        if (rawLocal is String) {
          lastUpdated = DateTime.tryParse(rawLocal);
        }
      }

      DateTime? outsideSince;
      final rawOutside = presence?['outsideSince'];
      if (rawOutside is Timestamp) outsideSince = rawOutside.toDate();

      final zone = (presence?['zone'] ?? 'unknown').toString();
      final inRange = presence?['inRange'] == true;
      final distance =
      (presence?['distanceMeters'] as num?)?.toDouble();
      final accuracy =
      (presence?['accuracyMeters'] as num?)?.toDouble();
      final online = presence?['isOnline'] == true;
      final checkCount = (presence?['checkCount'] as num?)?.toInt() ?? 0;

      list.add(PresenceRow(
        employeeId: empId.isNotEmpty ? empId : docId,
        docId: docId,
        name: displayName, // 👈 Ginamit ang fallback name
        role: role,
        department: dept,
        photoUrl: (entry['photoUrl'] ?? '').toString(),
        wfhAccess: wfh,
        isDriver: isDriver,
        lastUpdated: lastUpdated,
        zone: zone,
        inRange: inRange,
        distanceMeters: distance,
        accuracyMeters: accuracy,
        isOnline: online,
        outsideSince: outsideSince,
        checkCount: checkCount,
      ));
    }

    setState(() {
      _rows = list;
      _loading = false;
    });
  }

  List<PresenceRow> get _filtered {
    var out = _rows.where((r) {
      if (_statusFilter == 'Present' &&
          r.status != PresenceStatus.present) {
        return false;
      }
      if (_statusFilter == 'Idle' && r.status != PresenceStatus.idle) {
        return false;
      }
      if (_statusFilter == 'Offline' &&
          r.status != PresenceStatus.offline) {
        return false;
      }

      final q = _search.trim().toLowerCase();
      if (q.isEmpty) return true;
      return r.name.toLowerCase().contains(q) ||
          r.role.toLowerCase().contains(q) ||
          r.department.toLowerCase().contains(q) ||
          r.employeeId.toLowerCase().contains(q);
    }).toList();

    out.sort((a, b) {
      if (_sort == 'Status') {
        final order = {
          PresenceStatus.offline: 0,
          PresenceStatus.idle: 1,
          PresenceStatus.unknown: 2,
          PresenceStatus.present: 3,
        };
        final cmp =
        (order[a.status] ?? 9).compareTo(order[b.status] ?? 9);
        if (cmp != 0) return cmp;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      } else if (_sort == 'Name') {
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      } else if (_sort == 'Recent') {
        final ta = a.lastUpdated?.millisecondsSinceEpoch ?? 0;
        final tb = b.lastUpdated?.millisecondsSinceEpoch ?? 0;
        return tb.compareTo(ta);
      }
      return 0;
    });

    return out;
  }

  int get _countPresent =>
      _rows.where((r) => r.status == PresenceStatus.present).length;
  int get _countIdle =>
      _rows.where((r) => r.status == PresenceStatus.idle).length;
  int get _countOffline =>
      _rows.where((r) => r.status == PresenceStatus.offline).length;
  int get _countUnknown =>
      _rows.where((r) => r.status == PresenceStatus.unknown).length;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: tc.background,
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_isDemo) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                    child: _buildDemoBanner(),
                  ),
                ],
                _buildHeader(),
                _buildStatsBar(),
                _buildFilterBar(),
                const SizedBox(height: 8),
                Expanded(child: _buildBody()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDemoBanner() {
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Demo Mode Active',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: tc.orange,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Showing sample presence data. Real-time updates are disabled.',
                  style: TextStyle(
                    fontSize: 11,
                    color: tc.textMuted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: tc.orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.radar_rounded, color: tc.orange, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Live Presence Monitor',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: tc.text,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(width: 10),
                    _liveDot(),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Real-time location & heartbeat ng lahat ng employees',
                  style: TextStyle(color: tc.muted, fontSize: 13),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _isDemo ? null : _startStreams,
            tooltip: _isDemo ? 'Refresh disabled in Demo' : 'Refresh',
            icon: Icon(Icons.refresh_rounded,
                color: _isDemo ? tc.muted : tc.text),
          ),
        ],
      ),
    );
  }

  Widget _liveDot() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF22C55E).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF22C55E).withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PulsingDot(color: const Color(0xFF22C55E)),
          const SizedBox(width: 5),
          const Text(
            'LIVE',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: Color(0xFF166534),
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
      child: LayoutBuilder(builder: (_, c) {
        final narrow = c.maxWidth < 560;
        final tiles = <Widget>[
          _statTile(
            label: 'Present',
            count: _countPresent,
            color: const Color(0xFF22C55E),
            icon: Icons.check_circle_rounded,
          ),
          _statTile(
            label: 'Idle',
            count: _countIdle,
            color: const Color(0xFFF59E0B),
            icon: Icons.warning_amber_rounded,
          ),
          _statTile(
            label: 'Offline',
            count: _countOffline,
            color: const Color(0xFFEF4444),
            icon: Icons.cloud_off_rounded,
          ),
          if (_countUnknown > 0)
            _statTile(
              label: 'Unknown',
              count: _countUnknown,
              color: const Color(0xFF9CA3AF),
              icon: Icons.help_outline_rounded,
            ),
        ];

        if (narrow) {
          return Column(
            children: [
              Row(children: [
                Expanded(child: tiles[0]),
                const SizedBox(width: 8),
                Expanded(child: tiles[1]),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: tiles[2]),
                const SizedBox(width: 8),
                Expanded(
                  child: tiles.length > 3 ? tiles[3] : const SizedBox.shrink(),
                ),
              ]),
            ],
          );
        }
        return Row(
          children: tiles
              .map((t) => Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: t,
            ),
          ))
              .toList(),
        );
      }),
    );
  }

  Widget _statTile({
    required String label,
    required int count,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tc.border),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: tc.text,
                    height: 1.1,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: tc.muted,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
      child: LayoutBuilder(builder: (_, c) {
        final narrow = c.maxWidth < 700;
        final search = Container(
          height: 42,
          decoration: BoxDecoration(
            color: tc.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: tc.border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Icon(Icons.search_rounded, size: 18, color: tc.muted),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _search = v),
                  style: TextStyle(color: tc.text, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Search name, role, department, ID...',
                    hintStyle: TextStyle(color: tc.muted, fontSize: 13),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              if (_search.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    _searchCtrl.clear();
                    setState(() => _search = '');
                  },
                  child: Icon(Icons.close_rounded,
                      size: 16, color: tc.muted),
                ),
            ],
          ),
        );

        final statusDD = _pillDropdown(
          value: _statusFilter,
          items: const ['All', 'Present', 'Idle', 'Offline'],
          prefix: 'Status: ',
          onChanged: (v) =>
              setState(() => _statusFilter = v ?? 'All'),
        );
        final sortDD = _pillDropdown(
          value: _sort,
          items: const ['Status', 'Name', 'Recent'],
          prefix: 'Sort: ',
          onChanged: (v) => setState(() => _sort = v ?? 'Status'),
        );

        if (narrow) {
          return Column(
            children: [
              search,
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: statusDD),
                const SizedBox(width: 8),
                Expanded(child: sortDD),
              ]),
            ],
          );
        }
        return Row(children: [
          Expanded(flex: 3, child: search),
          const SizedBox(width: 10),
          Expanded(child: statusDD),
          const SizedBox(width: 10),
          Expanded(child: sortDD),
        ]);
      }),
    );
  }

  Widget _pillDropdown({
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    String prefix = '',
  }) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: tc.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tc.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: tc.card,
          icon: Icon(Icons.keyboard_arrow_down_rounded,
              color: tc.muted, size: 18),
          style: TextStyle(
              color: tc.text, fontSize: 13, fontWeight: FontWeight.w600),
          items: items
              .map((d) => DropdownMenuItem<String>(
            value: d,
            child: Text('$prefix$d',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: tc.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded,
                  size: 48, color: tc.red),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: tc.muted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _isDemo ? null : _startStreams,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isDemo ? tc.border : tc.orange,
                  foregroundColor: _isDemo ? tc.muted : Colors.white,
                ),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final filtered = _filtered;

    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.radar_rounded, size: 48, color: tc.muted),
              const SizedBox(height: 12),
              Text(
                _rows.isEmpty
                    ? 'Walang presence data pa.\nEmployees need to login first.'
                    : 'Walang match sa filter.',
                textAlign: TextAlign.center,
                style: TextStyle(color: tc.muted, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return ScrollConfiguration(
      behavior: const MaterialScrollBehavior().copyWith(
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.stylus,
        },
      ),
      child: RefreshIndicator(
        onRefresh: () async {
          if (_isDemo) {
            setState(() {
              _rows = _getMockRows();
            });
            await Future.delayed(const Duration(milliseconds: 400));
            return;
          }
          _startStreams();
          await Future.delayed(const Duration(milliseconds: 600));
        },
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          itemCount: filtered.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (ctx, i) => _presenceCard(filtered[i]),
        ),
      ),
    );
  }

  Widget _presenceCard(PresenceRow r) {
    final status = r.status;
    final statusColor = status.color;

    return InkWell(
      onTap: () => _showDetailsDialog(r),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: tc.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: statusColor.withValues(alpha: 0.35),
            width: 1.2,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: tc.orange.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: tc.border, width: 1.5),
                  ),
                  child: _avatarContent(r),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: tc.card, width: 2.5),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          r.name.isEmpty ? 'Unnamed' : r.name,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: tc.text,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      _statusPill(status),
                      if (r.wfhAccess) ...[
                        const SizedBox(width: 6),
                        _miniTag(
                          'WFH',
                          const Color(0xFF22C55E),
                          const Color(0xFF166534),
                        ),
                      ] else if (r.isDriver) ...[
                        const SizedBox(width: 6),
                        _miniTag(
                          'DRIVER',
                          const Color(0xFF3B82F6),
                          const Color(0xFF1E40AF),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${r.role.isEmpty ? "—" : r.role} • ${r.department.isEmpty ? "—" : r.department}',
                    style: TextStyle(
                      fontSize: 12,
                      color: tc.muted,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _chip(
                        Icons.schedule_rounded,
                        r.lastSeenText,
                        statusColor,
                      ),
                      _chip(
                        r.zone == 'inside'
                            ? Icons.location_on_rounded
                            : Icons.location_off_rounded,
                        r.zoneLabel,
                        r.zone == 'inside'
                            ? const Color(0xFF22C55E)
                            : (r.wfhAccess || r.isDriver
                            ? const Color(0xFF3B82F6)
                            : const Color(0xFFEF4444)),
                      ),
                      if (r.distanceMeters != null)
                        _chip(
                          Icons.straighten_rounded,
                          '${r.distanceMeters!.toStringAsFixed(0)}m',
                          tc.muted,
                        ),
                      if (r.outsideSince != null)
                        _chip(
                          Icons.timer_outlined,
                          'Out ${_durSince(r.outsideSince!)}',
                          const Color(0xFFEF4444),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Icon(
                Icons.chevron_right_rounded,
                color: tc.muted,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatarContent(PresenceRow r) {
    final url = r.photoUrl;
    if (url.isEmpty || url == '—') return _avatarFallback(r.initials);

    if (url.startsWith('data:image')) {
      try {
        final b64 = url.split(',').last;
        return Image.memory(
          base64Decode(b64),
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _avatarFallback(r.initials),
        );
      } catch (_) {
        return _avatarFallback(r.initials);
      }
    }
    if (url.startsWith('http')) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _avatarFallback(r.initials),
      );
    }
    return _avatarFallback(r.initials);
  }

  Widget _avatarFallback(String initials) => Center(
    child: Text(
      initials,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: Color(0xFF904D00),
      ),
    ),
  );

  Widget _statusPill(PresenceStatus s) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: s.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: s.color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(s.icon, size: 11, color: s.color),
          const SizedBox(width: 4),
          Text(
            s.label.toUpperCase(),
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              color: s.color,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniTag(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: bg.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: fg,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tc.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: tc.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: tc.text,
            ),
          ),
        ],
      ),
    );
  }

  String _durSince(DateTime since) {
    final diff = DateTime.now().difference(since);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h ${diff.inMinutes % 60}m';
    return '${diff.inDays}d';
  }

  void _showDetailsDialog(PresenceRow r) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: tc.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        title: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: r.status.color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                r.name,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: tc.text,
                ),
              ),
            ),
            _statusPill(r.status),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow('Employee ID', r.employeeId),
              _detailRow('Role', r.role.isEmpty ? '—' : r.role),
              _detailRow('Department', r.department.isEmpty ? '—' : r.department),
              const Divider(height: 20),
              _detailRow('Status', r.status.label),
              _detailRow('Last seen', r.lastSeenText),
              _detailRow('Zone', r.zoneLabel),
              _detailRow('Inside range', r.inRange ? 'Yes' : 'No'),
              if (r.distanceMeters != null)
                _detailRow(
                  'Distance',
                  '${r.distanceMeters!.toStringAsFixed(1)} m',
                ),
              if (r.accuracyMeters != null)
                _detailRow(
                  'Accuracy',
                  '±${r.accuracyMeters!.toStringAsFixed(1)} m',
                ),
              if (r.outsideSince != null)
                _detailRow(
                  'Outside since',
                  '${_fmtDateTime(r.outsideSince!)} (${_durSince(r.outsideSince!)})',
                ),
              const Divider(height: 20),
              _detailRow('Is online', r.isOnline ? 'Yes' : 'No'),
              _detailRow('Heartbeat checks', '${r.checkCount}'),
              _detailRow('WFH access', r.wfhAccess ? 'Enabled' : 'Disabled'),
              _detailRow('Driver role', r.isDriver ? 'Yes' : 'No'),
              if (r.lastUpdated != null)
                _detailRow('Last updated', _fmtDateTime(r.lastUpdated!)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Close', style: TextStyle(color: tc.muted)),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: tc.muted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: tc.text,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _fmtDateTime(DateTime dt) {
    final l = dt.toLocal();
    final h = l.hour == 0 ? 12 : (l.hour > 12 ? l.hour - 12 : l.hour);
    final ampm = l.hour >= 12 ? 'PM' : 'AM';
    return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')} '
        '${h.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')} '
        '${l.second.toString().padLeft(2, '0')} $ampm';
  }
}

class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: widget.color.withValues(alpha: _anim.value),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}