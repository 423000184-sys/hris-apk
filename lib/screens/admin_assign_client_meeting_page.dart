// lib/screens/admin_assign_client_meeting_page.dart
// v1.1: 🎭 Demo Mode Support (Mock Data & Action Blocking)
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/client_meeting_assignment.dart';
import '../services/client_meeting_assignment_service.dart';
import '../services/employee_notification_service.dart';
import '../services/demo_mode_service.dart'; // 🎭 Added
import 'admin_theme.dart';
import 'admin_add_client_location_page.dart';

class AdminAssignClientMeetingPage extends StatefulWidget {
  final List<Map<String, dynamic>> employees;
  final VoidCallback? onBack;
  final String? currentAdminId;
  final String? currentAdminName;
  final bool embedded;
  final void Function(int index)? onTabNavigate;

  const AdminAssignClientMeetingPage({
    super.key,
    required this.employees,
    this.onBack,
    this.currentAdminId,
    this.currentAdminName,
    this.embedded = false,
    this.onTabNavigate,
  });

  @override
  State<AdminAssignClientMeetingPage> createState() =>
      _AdminAssignClientMeetingPageState();
}

class _AdminAssignClientMeetingPageState
    extends State<AdminAssignClientMeetingPage> {
  AdminColors get tc => AdminTheme.getColors(context);

  // 🎭 Demo Mode Getter
  bool get _isDemo {
    try {
      return DemoModeService.instance.isEnabled;
    } catch (_) {
      return false;
    }
  }

  // 🎭 Demo Block Helper
  void _demoBlock() {
    _showSnack('Action disabled in Demo Mode.', isError: true);
  }

  List<ClientMeetingAssignment> _assignments = [];
  bool _loading = true;
  String? _listError;
  AssignmentStatus? _filterStatus;

  final _formKey = GlobalKey<FormState>();
  Map<String, dynamic>? _selectedEmployee;
  Map<String, dynamic>? _selectedClient;

  DateTime _selectedDate = DateTime.now();
  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 11, minute: 0);
  int _graceMinutes = 15;

  final _purposeCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  bool _submitting = false;

  List<Map<String, dynamic>> _clients = [];
  bool _loadingClients = true;

  @override
  void initState() {
    super.initState();
    _loadClients();
    _loadAssignments();
  }

  @override
  void dispose() {
    _purposeCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  // 🎭 MOCK CLIENTS
  List<Map<String, dynamic>> _getMockClients() {
    return [
      {
        'id': 'demo_client_1',
        'name': 'Acme Corporation',
        'address': '123 Ayala Ave, Makati City',
        'lat': 14.5547,
        'lng': 121.0244,
        'radiusMeters': 100,
        'isActive': true,
      },
      {
        'id': 'demo_client_2',
        'name': 'Global Tech Solutions',
        'address': '456 BGC, Taguig City',
        'lat': 14.5500,
        'lng': 121.0500,
        'radiusMeters': 150,
        'isActive': true,
      },
      {
        'id': 'demo_client_3',
        'name': 'Sunrise Ventures',
        'address': '789 Ortigas Center, Pasig',
        'lat': 14.5800,
        'lng': 121.0600,
        'radiusMeters': 120,
        'isActive': true,
      },
    ];
  }

  // 🎭 MOCK ASSIGNMENTS
  List<ClientMeetingAssignment> _getMockAssignments() {
    final now = DateTime.now();
    return [
      ClientMeetingAssignment(
        id: 'demo_assign_1',
        employeeId: 'DEMO-001',
        employeeName: 'John Doe',
        employeeEmail: 'john@demo.local',
        clientId: 'demo_client_1',
        clientName: 'Acme Corporation',
        clientAddress: '123 Ayala Ave, Makati City',
        clientLat: 14.5547,
        clientLng: 121.0244,
        clientRadius: 100,
        purpose: 'Quarterly business review',
        notes: 'Bring updated contract documents',
        scheduledStart: now.add(const Duration(hours: 2)),
        scheduledEnd: now.add(const Duration(hours: 4)),
        assignedBy: 'demo_admin',
        assignedByName: 'Demo Admin',
        status: AssignmentStatus.active,
        createdAt: now.subtract(const Duration(hours: 1)),
      ),
      ClientMeetingAssignment(
        id: 'demo_assign_2',
        employeeId: 'DEMO-002',
        employeeName: 'Jane Smith',
        employeeEmail: 'jane@demo.local',
        clientId: 'demo_client_2',
        clientName: 'Global Tech Solutions',
        clientAddress: '456 BGC, Taguig City',
        clientLat: 14.5500,
        clientLng: 121.0500,
        clientRadius: 150,
        purpose: 'Initial product demo',
        notes: null,
        scheduledStart: now.add(const Duration(days: 1, hours: 3)),
        scheduledEnd: now.add(const Duration(days: 1, hours: 5)),
        assignedBy: 'demo_admin',
        assignedByName: 'Demo Admin',
        status: AssignmentStatus.active,
        createdAt: now.subtract(const Duration(hours: 5)),
      ),
      ClientMeetingAssignment(
        id: 'demo_assign_3',
        employeeId: 'DEMO-003',
        employeeName: 'Mike Johnson',
        employeeEmail: 'mike@demo.local',
        clientId: 'demo_client_3',
        clientName: 'Sunrise Ventures',
        clientAddress: '789 Ortigas Center, Pasig',
        clientLat: 14.5800,
        clientLng: 121.0600,
        clientRadius: 120,
        purpose: 'Partnership discussion',
        notes: 'Client will provide lunch',
        scheduledStart: now.subtract(const Duration(days: 2, hours: 3)),
        scheduledEnd: now.subtract(const Duration(days: 2, hours: 1)),
        assignedBy: 'demo_admin',
        assignedByName: 'Demo Admin',
        status: AssignmentStatus.used,
        createdAt: now.subtract(const Duration(days: 3)),
      ),
    ];
  }

  // ═══════════════════════════════════════════════════════════════
  // DATA LOADING
  // ═══════════════════════════════════════════════════════════════

  Future<void> _loadClients() async {
    if (!mounted) return;

    // 🎭 Demo Mode — use mock clients
    if (_isDemo) {
      setState(() {
        _clients = _getMockClients();
        _loadingClients = false;
      });
      return;
    }

    setState(() => _loadingClients = true);

    try {
      final snap = await FirebaseFirestore.instance
          .collection('client_locations')
          .where('isActive', isEqualTo: true)
          .get()
          .timeout(const Duration(seconds: 10));

      final list = snap.docs
          .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
          .toList();

      list.sort((a, b) {
        final aName = (a['name'] ?? '').toString().toLowerCase();
        final bName = (b['name'] ?? '').toString().toLowerCase();
        return aName.compareTo(bName);
      });

      if (!mounted) return;
      setState(() {
        _clients = list;
        _loadingClients = false;
      });

      debugPrint('✅ [AssignMeeting] Loaded ${list.length} clients');
    } catch (e) {
      debugPrint('⚠️ loadClients error: $e');
      if (mounted) setState(() => _loadingClients = false);
    }
  }

  Future<void> _loadAssignments() async {
    if (!mounted) return;

    // 🎭 Demo Mode — use mock assignments
    if (_isDemo) {
      var list = _getMockAssignments();
      if (_filterStatus != null) {
        list = list.where((a) => a.status == _filterStatus).toList();
      }
      setState(() {
        _assignments = list;
        _loading = false;
        _listError = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _listError = null;
    });

    try {
      final list = await ClientMeetingAssignmentService.instance
          .getAdminAssignments(
        status: _filterStatus,
        limit: 100,
      );

      if (!mounted) return;
      setState(() {
        _assignments = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _listError = e.toString();
      });
    }
  }

  Future<void> _openAddClientPage() async {
    if (_isDemo) return _demoBlock();

    if (widget.onTabNavigate != null) {
      debugPrint('🧭 [AssignMeeting] → switching to Add Client tab (8)');
      widget.onTabNavigate!(8);
      return;
    }

    debugPrint('🧭 [AssignMeeting] → pushing Add Client route');
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminAddClientLocationPage(
          onSaved: () {
            debugPrint('✅ [AssignMeeting] New client saved');
          },
          onBack: () => Navigator.pop(context),
        ),
      ),
    );
    if (mounted) _loadClients();
  }

  // ═══════════════════════════════════════════════════════════════
  // ACTIONS
  // ═══════════════════════════════════════════════════════════════

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
    );
    if (picked == null) return;

    setState(() {
      if (isStart) {
        _startTime = picked;
        final startMin = picked.hour * 60 + picked.minute;
        final endMin = _endTime.hour * 60 + _endTime.minute;
        if (endMin <= startMin) {
          final newEnd = startMin + 120;
          _endTime = TimeOfDay(
            hour: (newEnd ~/ 60) % 24,
            minute: newEnd % 60,
          );
        }
      } else {
        _endTime = picked;
      }

      final sMin = _startTime.hour * 60 + _startTime.minute;
      final eMin = _endTime.hour * 60 + _endTime.minute;
      if (eMin <= sMin) {
        debugPrint('🌙 Overnight meeting: ends next day');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            final nextDay = _selectedDate.add(const Duration(days: 1));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '🌙 Overnight meeting — will end the next day ('
                      '${DateFormat('MMM d').format(_selectedDate)} → '
                      '${DateFormat('MMM d').format(nextDay)})',
                ),
                backgroundColor: tc.orange,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        });
      }
    });
  }

  DateTime _combineDate(DateTime date, TimeOfDay time) {
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _createAssignment() async {
    if (_isDemo) return _demoBlock();

    if (!_formKey.currentState!.validate()) return;

    if (_selectedEmployee == null) {
      _showSnack('Please select an employee', isError: true);
      return;
    }
    if (_selectedClient == null) {
      _showSnack('Please select a client location', isError: true);
      return;
    }

    final startDT = _combineDate(_selectedDate, _startTime);
    var endDT = _combineDate(_selectedDate, _endTime);

    final isOvernight = !endDT.isAfter(startDT);
    if (isOvernight) {
      endDT = endDT.add(const Duration(days: 1));
      debugPrint('🌙 [Assignment] Overnight meeting detected: '
          '$startDT → $endDT');
    }

    setState(() => _submitting = true);

    try {
      final emp = _selectedEmployee!;
      final client = _selectedClient!;

      final empId = (emp['id'] ?? '').toString();
      final empName = (emp['name'] ??
          '${emp['firstName'] ?? ''} ${emp['lastName'] ?? ''}')
          .toString()
          .trim();
      final empEmail = (emp['email'] ?? '').toString();

      final clientId = (client['id'] ?? '').toString();
      final clientName = (client['name'] ?? '').toString();
      final clientAddress = (client['address'] ?? '').toString();
      final clientLat = (client['lat'] as num?)?.toDouble() ?? 0;
      final clientLng = (client['lng'] as num?)?.toDouble() ?? 0;
      final clientRadius =
          (client['radiusMeters'] as num?)?.toDouble() ?? 100;

      final assignmentId =
      await ClientMeetingAssignmentService.instance.createAssignment(
        employeeId: empId,
        employeeName: empName,
        employeeEmail: empEmail,
        clientId: clientId,
        clientName: clientName,
        clientAddress: clientAddress,
        clientLat: clientLat,
        clientLng: clientLng,
        clientRadius: clientRadius,
        purpose: _purposeCtrl.text.trim(),
        notes: _notesCtrl.text.trim().isEmpty
            ? null
            : _notesCtrl.text.trim(),
        scheduledStart: startDT,
        scheduledEnd: endDT,
        assignedBy: widget.currentAdminId ?? 'admin',
        assignedByName: widget.currentAdminName ?? 'Admin',
        gracePeriod: Duration(minutes: _graceMinutes),
      );

      if (assignmentId == null) {
        throw 'Failed to create assignment';
      }

      try {
        final dateStr = DateFormat('MMM d, yyyy').format(startDT);
        final timeStr = '${_startTime.hour.toString().padLeft(2, '0')}:'
            '${_startTime.minute.toString().padLeft(2, '0')} - '
            '${_endTime.hour.toString().padLeft(2, '0')}:'
            '${_endTime.minute.toString().padLeft(2, '0')}'
            '${isOvernight ? " (next day)" : ""}';

        if (empId.isNotEmpty) {
          await EmployeeNotificationService.instance.send(
            type: 'reminder',
            title: '📋 New Client Meeting Assigned',
            message: 'You have a client meeting at $clientName.\n'
                '📅 $dateStr\n⏰ $timeStr\n'
                '📝 ${_purposeCtrl.text.trim()}',
            employeeId: empId,
            priority: 'high',
          );
        }
      } catch (e) {
        debugPrint('⚠️ notify failed: $e');
      }

      if (!mounted) return;
      _showSnack(
          '✅ Assignment created for $empName${isOvernight ? " (overnight)" : ""}');
      _resetForm();
      _loadAssignments();
    } catch (e) {
      if (!mounted) return;
      _showSnack('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _resetForm() {
    setState(() {
      _selectedEmployee = null;
      _selectedClient = null;
      _selectedDate = DateTime.now();
      _startTime = const TimeOfDay(hour: 9, minute: 0);
      _endTime = const TimeOfDay(hour: 11, minute: 0);
      _graceMinutes = 15;
      _purposeCtrl.clear();
      _notesCtrl.clear();
    });
  }

  Future<void> _cancelAssignment(ClientMeetingAssignment a) async {
    if (_isDemo) return _demoBlock();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: tc.card,
        title: Text('Cancel Assignment?',
            style: TextStyle(color: tc.text)),
        content: Text(
          'Cancel client meeting assignment for ${a.employeeName}?\n\n'
              'Client: ${a.clientName}\n'
              'Schedule: ${a.dateLabel} ${a.timeWindowLabel}\n\n'
              'Status will be set to CANCELLED (kept in history).',
          style: TextStyle(color: tc.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('No', style: TextStyle(color: tc.muted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: tc.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final ok = await ClientMeetingAssignmentService.instance
        .cancelAssignment(a.id);
    if (!mounted) return;

    if (ok) {
      _showSnack('Assignment cancelled');
      _loadAssignments();

      try {
        await EmployeeNotificationService.instance.send(
          type: 'reminder',
          title: '❌ Client Meeting Cancelled',
          message: 'Your client meeting at ${a.clientName} '
              '(${a.dateLabel} ${a.timeWindowLabel}) has been cancelled.',
          employeeId: a.employeeId,
          priority: 'high',
        );
      } catch (_) {}
    } else {
      _showSnack('Failed to cancel', isError: true);
    }
  }

  Future<void> _editAssignment(ClientMeetingAssignment a) async {
    if (_isDemo) return _demoBlock();

    debugPrint('✏️ [Edit] Opening edit dialog for assignment ${a.id}');

    final updated = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _EditAssignmentDialog(
        assignment: a,
        employees: widget.employees,
        clients: _clients,
        currentAdminName: widget.currentAdminName,
      ),
    );

    if (updated != true) return;

    if (!mounted) return;
    _showSnack('✅ Assignment updated for ${a.employeeName}');
    _loadAssignments();

    try {
      await EmployeeNotificationService.instance.send(
        type: 'reminder',
        title: '✏️ Client Meeting Updated',
        message: 'Your client meeting at ${a.clientName} has been updated '
            'by admin. Please check the new schedule.',
        employeeId: a.employeeId,
        priority: 'high',
      );
    } catch (e) {
      debugPrint('⚠️ [Edit] notify failed: $e');
    }
  }

  Future<void> _deleteAssignment(ClientMeetingAssignment a) async {
    if (_isDemo) return _demoBlock();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: tc.card,
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: tc.red, size: 22),
            const SizedBox(width: 8),
            Text(
              'Delete Assignment?',
              style: TextStyle(
                color: tc.text,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Permanently delete this assignment?',
              style: TextStyle(
                color: tc.text,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: tc.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: tc.red.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Employee: ${a.employeeName}',
                      style: TextStyle(color: tc.text, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text('Client: ${a.clientName}',
                      style: TextStyle(color: tc.text, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text('Schedule: ${a.dateLabel} ${a.timeWindowLabel}',
                      style: TextStyle(color: tc.text, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '⚠️ This action CANNOT be undone.\n'
                  'This will be permanently removed from the employee\'s records.',
              style: TextStyle(
                color: tc.red,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: tc.muted)),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.delete_forever_rounded, size: 16),
            label: const Text('Yes, Delete'),
            style: ElevatedButton.styleFrom(
              backgroundColor: tc.red,
              foregroundColor: Colors.white,
              padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      debugPrint('🗑️ [Delete] Deleting assignment ${a.id}...');

      await FirebaseFirestore.instance
          .collection('client_meeting_assignments')
          .doc(a.id)
          .delete()
          .timeout(const Duration(seconds: 10));

      debugPrint('✅ [Delete] Assignment ${a.id} deleted');

      if (!mounted) return;
      _showSnack('🗑️ Deleted assignment for ${a.employeeName}');
      _loadAssignments();

      try {
        await EmployeeNotificationService.instance.send(
          type: 'reminder',
          title: '❌ Client Meeting Removed',
          message: 'Your client meeting at ${a.clientName} '
              '(${a.dateLabel} ${a.timeWindowLabel}) has been removed by admin.',
          employeeId: a.employeeId,
          priority: 'high',
        );
      } catch (e) {
        debugPrint('⚠️ [Delete] notify failed: $e');
      }
    } catch (e) {
      debugPrint('❌ [Delete] error: $e');
      if (!mounted) return;
      _showSnack('Delete failed: $e', isError: true);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? tc.red : tc.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Container(
      color: tc.background,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 🎭 DEMO BANNER
                if (_isDemo) ...[
                  _buildDemoBanner(),
                  const SizedBox(height: 16),
                ],

                if (!widget.embedded) _buildTopBar(),
                if (widget.embedded) _buildEmbeddedHeader(),

                const SizedBox(height: 20),

                _buildForm(),
                const SizedBox(height: 32),
                _buildAssignmentsList(),
                const SizedBox(height: 60),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 🎭 DEMO BANNER
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
                  'Showing sample assignments. Create, edit, cancel, and delete are disabled.',
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

  Widget _buildEmbeddedHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.onBack != null)
          InkWell(
            onTap: widget.onBack,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8.0, top: 4, right: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_back_rounded, color: tc.orange, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    'Back to Activity & Leave',
                    style: TextStyle(
                      color: tc.orange,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        Text(
          'Assign Client Meeting',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: tc.text,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Pre-authorize employee client meetings with time windows.',
          style: TextStyle(fontSize: 13, color: tc.muted),
        ),
      ],
    );
  }

  Widget _buildTopBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.onBack != null)
          InkWell(
            onTap: () {
              if (widget.onBack != null) {
                widget.onBack!();
              } else {
                Navigator.maybePop(context);
              }
            },
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8.0, top: 4, right: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_back_rounded, color: tc.orange, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    'Back to Activity & Leave',
                    style: TextStyle(
                      color: tc.orange,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        Text(
          'Assign Client Meeting',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: tc.text,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Pre-authorize employee client meetings with time windows.',
          style: TextStyle(fontSize: 13, color: tc.muted),
        ),
      ],
    );
  }

  Widget _buildForm() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tc.border),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(builder: (context, c) {
              final isNarrow = c.maxWidth < 420;

              final title = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_circle_outline_rounded,
                      color: tc.orange, size: 20),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Create New Assignment',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: tc.text,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              );

              final actions = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton.icon(
                    onPressed: _isDemo ? _demoBlock : _openAddClientPage,
                    icon: Icon(Icons.add_location_alt_rounded,
                        size: 16, color: _isDemo ? tc.muted : tc.orange),
                    label: Text(
                      'Add Client',
                      style: TextStyle(
                          color: _isDemo ? tc.muted : tc.orange,
                          fontWeight: FontWeight.w700,
                          fontSize: 13),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  IconButton(
                    onPressed: _loadAssignments,
                    icon: Icon(Icons.refresh_rounded,
                        color: tc.muted, size: 20),
                    tooltip: 'Refresh',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                        minWidth: 32, minHeight: 32),
                  ),
                ],
              );

              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title,
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: actions,
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: title),
                  actions,
                ],
              );
            }),
            const SizedBox(height: 20),

            LayoutBuilder(builder: (context, c) {
              final wide = c.maxWidth >= 700;
              final empDropdown = _buildEmployeeDropdown();
              final clientDropdown = _buildClientDropdown();

              if (!wide) {
                return Column(
                  children: [
                    empDropdown,
                    const SizedBox(height: 16),
                    clientDropdown,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: empDropdown),
                  const SizedBox(width: 16),
                  Expanded(child: clientDropdown),
                ],
              );
            }),
            const SizedBox(height: 16),

            LayoutBuilder(builder: (context, c) {
              final wide = c.maxWidth >= 700;
              final children = <Widget>[
                _buildDateField(),
                _buildTimeField('Start Time', _startTime, true),
                _buildTimeField('End Time', _endTime, false),
              ];

              if (!wide) {
                return Column(
                  children: children
                      .map((w) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: w,
                  ))
                      .toList(),
                );
              }
              return Row(
                children: [
                  Expanded(child: children[0]),
                  const SizedBox(width: 12),
                  Expanded(child: children[1]),
                  const SizedBox(width: 12),
                  Expanded(child: children[2]),
                ],
              );
            }),
            const SizedBox(height: 16),

            _buildGraceSelector(),
            const SizedBox(height: 16),

            TextFormField(
              controller: _purposeCtrl,
              maxLength: 120,
              decoration: InputDecoration(
                labelText: 'Purpose *',
                hintText: 'e.g. Product demo with client',
                labelStyle: TextStyle(color: tc.muted),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: tc.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: tc.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: tc.orange, width: 2),
                ),
              ),
              style: TextStyle(color: tc.text),
              validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 8),

            TextFormField(
              controller: _notesCtrl,
              maxLines: 3,
              maxLength: 500,
              decoration: InputDecoration(
                labelText: 'Notes (optional)',
                hintText: 'Additional instructions...',
                labelStyle: TextStyle(color: tc.muted),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: tc.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: tc.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: tc.orange, width: 2),
                ),
              ),
              style: TextStyle(color: tc.text),
            ),
            const SizedBox(height: 8),

            Row(
              children: [
                TextButton.icon(
                  onPressed: _submitting ? null : _resetForm,
                  icon: Icon(Icons.refresh_rounded,
                      size: 16, color: tc.muted),
                  label:
                  Text('Reset', style: TextStyle(color: tc.muted)),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: (_submitting || _isDemo)
                      ? (_isDemo ? _demoBlock : null)
                      : _createAssignment,
                  icon: (_submitting)
                      ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                      : Icon(
                    _isDemo
                        ? Icons.lock_outline_rounded
                        : Icons.check_rounded,
                    size: 16,
                  ),
                  label: Text(
                    _submitting
                        ? 'Creating...'
                        : (_isDemo
                        ? 'Create Disabled (Demo)'
                        : 'Create Assignment'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isDemo ? tc.border : tc.orange,
                    foregroundColor: _isDemo ? tc.muted : Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
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

  Widget _buildEmployeeDropdown() {
    return DropdownButtonFormField<Map<String, dynamic>>(
      initialValue: _selectedEmployee,
      isExpanded: true,
      dropdownColor: tc.card,
      decoration: InputDecoration(
        labelText: 'Employee *',
        labelStyle: TextStyle(color: tc.muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: tc.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: tc.border),
        ),
      ),
      items: widget.employees
          .where((emp) => emp['terminated'] != true)
          .map((emp) {
        final name = (emp['name'] ??
            '${emp['firstName'] ?? ''} ${emp['lastName'] ?? ''}')
            .toString()
            .trim();
        return DropdownMenuItem<Map<String, dynamic>>(
          value: emp,
          child: Text(name.isEmpty ? 'Unknown' : name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: tc.text)),
        );
      }).toList(),
      onChanged: (v) => setState(() => _selectedEmployee = v),
    );
  }

  Widget _buildClientDropdown() {
    if (_loadingClients) {
      return Container(
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: tc.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (_clients.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: tc.orange.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: tc.orange.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                size: 18, color: tc.orangeText),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'No registered clients yet.',
                style: TextStyle(fontSize: 12, color: tc.orangeText),
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: _isDemo ? _demoBlock : _openAddClientPage,
              icon: Icon(Icons.add_rounded,
                  size: 14, color: tc.orangeText),
              label: Text(
                'Add Client',
                style: TextStyle(
                  color: tc.orangeText,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return DropdownButtonFormField<Map<String, dynamic>>(
      initialValue: _selectedClient,
      isExpanded: true,
      dropdownColor: tc.card,
      decoration: InputDecoration(
        labelText: 'Client Location *',
        labelStyle: TextStyle(color: tc.muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: tc.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: tc.border),
        ),
      ),
      items: _clients.map((c) {
        final name = (c['name'] ?? 'Unknown').toString();
        return DropdownMenuItem<Map<String, dynamic>>(
          value: c,
          child: Text(name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: tc.text)),
        );
      }).toList(),
      onChanged: (v) => setState(() => _selectedClient = v),
    );
  }

  Widget _buildDateField() {
    return InkWell(
      onTap: _pickDate,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          border: Border.all(color: tc.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_rounded,
                size: 16, color: tc.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Date',
                      style: TextStyle(fontSize: 11, color: tc.muted)),
                  Text(
                    DateFormat('MMM d, yyyy').format(_selectedDate),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: tc.text),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeField(String label, TimeOfDay time, bool isStart) {
    final t = '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';

    final sMin = _startTime.hour * 60 + _startTime.minute;
    final eMin = _endTime.hour * 60 + _endTime.minute;
    final overnight = eMin <= sMin && !isStart;

    return InkWell(
      onTap: () => _pickTime(isStart),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          border: Border.all(
              color: overnight ? tc.orange : tc.border,
              width: overnight ? 1.5 : 1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.access_time_rounded, size: 16, color: tc.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(label,
                          style:
                          TextStyle(fontSize: 11, color: tc.muted)),
                      if (overnight) ...[
                        const SizedBox(width: 4),
                        Text('(next day)',
                            style: TextStyle(
                                fontSize: 10,
                                color: tc.orange,
                                fontWeight: FontWeight.w600)),
                      ],
                    ],
                  ),
                  Text(t,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: tc.text)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGraceSelector() {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timer_outlined, size: 16, color: tc.muted),
            const SizedBox(width: 8),
            Text('Grace period:',
                style: TextStyle(fontSize: 13, color: tc.muted)),
          ],
        ),
        ...([0, 15, 30, 60].map((min) {
          final selected = _graceMinutes == min;
          return InkWell(
            onTap: () => setState(() => _graceMinutes = min),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: selected
                    ? tc.orange.withValues(alpha: 0.15)
                    : tc.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected
                      ? tc.orange.withValues(alpha: 0.5)
                      : tc.border,
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: Text(
                min == 0 ? 'Strict' : '±${min}m',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight:
                  selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? tc.orangeText : tc.text,
                ),
              ),
            ),
          );
        }).toList()),
      ],
    );
  }

  Widget _buildAssignmentsList() {
    return Container(
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tc.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(Icons.list_alt_rounded, color: tc.orange, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Existing Assignments',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: tc.text,
                    ),
                  ),
                ),
                _buildStatusFilter(),
              ],
            ),
          ),
          Divider(height: 1, color: tc.border),
          if (_loading)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Center(
                child: CircularProgressIndicator(color: tc.orange),
              ),
            )
          else if (_listError != null)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Error: $_listError',
                  style: TextStyle(color: tc.red, fontSize: 13)),
            )
          else if (_assignments.isEmpty)
              Padding(
                padding: const EdgeInsets.all(40),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.inbox_rounded, size: 40, color: tc.muted),
                      const SizedBox(height: 8),
                      Text('No assignments yet.',
                          style: TextStyle(color: tc.muted, fontSize: 13)),
                    ],
                  ),
                ),
              )
            else
              ..._assignments.map(_buildAssignmentTile),
        ],
      ),
    );
  }

  Widget _buildStatusFilter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: tc.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tc.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<AssignmentStatus?>(
          value: _filterStatus,
          dropdownColor: tc.card,
          icon: Icon(Icons.keyboard_arrow_down_rounded,
              size: 18, color: tc.muted),
          style: TextStyle(fontSize: 12, color: tc.text),
          items: [
            DropdownMenuItem<AssignmentStatus?>(
              value: null,
              child: Text('All Status', style: TextStyle(color: tc.text)),
            ),
            ...AssignmentStatus.values.map(
                  (s) => DropdownMenuItem<AssignmentStatus?>(
                value: s,
                child: Text(s.label, style: TextStyle(color: tc.text)),
              ),
            ),
          ],
          onChanged: (v) {
            setState(() => _filterStatus = v);
            _loadAssignments();
          },
        ),
      ),
    );
  }

  Widget _buildAssignmentTile(ClientMeetingAssignment a) {
    final statusColor = _statusColor(a.status);
    final canCancel = a.status == AssignmentStatus.active;
    final canEdit = a.status == AssignmentStatus.active;

    return LayoutBuilder(builder: (context, c) {
      final isNarrow = c.maxWidth < 600;

      final statusPill = Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: statusColor.withValues(alpha: 0.5)),
        ),
        child: Text(
          a.status.label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: statusColor,
          ),
        ),
      );

      final actions = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canEdit)
            IconButton(
              onPressed: _isDemo ? _demoBlock : () => _editAssignment(a),
              icon: Icon(Icons.edit_rounded,
                  size: 18, color: _isDemo ? tc.muted : tc.orange),
              tooltip: _isDemo ? 'Edit disabled in Demo' : 'Edit assignment',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                  minWidth: 36, minHeight: 36),
            ),
          if (canCancel)
            IconButton(
              onPressed: _isDemo ? _demoBlock : () => _cancelAssignment(a),
              icon: Icon(Icons.cancel_outlined,
                  size: 18, color: _isDemo ? tc.muted : tc.red),
              tooltip: _isDemo ? 'Cancel disabled in Demo' : 'Cancel',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                  minWidth: 36, minHeight: 36),
            ),
          IconButton(
            onPressed: _isDemo ? _demoBlock : () => _deleteAssignment(a),
            icon: Icon(Icons.delete_forever_rounded,
                size: 18, color: _isDemo ? tc.muted : tc.red),
            tooltip: _isDemo ? 'Delete disabled in Demo' : 'Delete permanently',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
                minWidth: 36, minHeight: 36),
          ),
        ],
      );

      final statusBar = Container(
        width: 6,
        height: isNarrow ? 80 : 40,
        decoration: BoxDecoration(
          color: statusColor,
          borderRadius: BorderRadius.circular(3),
        ),
      );

      if (isNarrow) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: tc.border)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              statusBar,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            a.employeeName,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: tc.text,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        statusPill,
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      a.purpose,
                      style: TextStyle(fontSize: 12, color: tc.muted),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.business_rounded,
                            size: 12, color: tc.orange),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            a.clientName,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: tc.text),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.calendar_today_rounded,
                            size: 12, color: tc.muted),
                        const SizedBox(width: 4),
                        Text(
                          a.dateLabel,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: tc.text),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.access_time_rounded,
                            size: 12, color: tc.muted),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            a.timeWindowLabel,
                            style:
                            TextStyle(fontSize: 11, color: tc.muted),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: actions,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }

      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: tc.border)),
        ),
        child: Row(
          children: [
            statusBar,
            const SizedBox(width: 12),

            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.employeeName,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: tc.text,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    a.purpose,
                    style: TextStyle(fontSize: 11, color: tc.muted),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            Expanded(
              flex: 3,
              child: Row(
                children: [
                  Icon(Icons.business_rounded,
                      size: 12, color: tc.orange),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      a.clientName,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: tc.text),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.dateLabel,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: tc.text),
                  ),
                  Text(
                    a.timeWindowLabel,
                    style: TextStyle(fontSize: 11, color: tc.muted),
                  ),
                ],
              ),
            ),

            statusPill,
            const SizedBox(width: 12),

            ...actions.children,
          ],
        ),
      );
    });
  }

  Color _statusColor(AssignmentStatus s) {
    switch (s) {
      case AssignmentStatus.active:
        return tc.green;
      case AssignmentStatus.used:
        return tc.orange;
      case AssignmentStatus.expired:
        return tc.muted;
      case AssignmentStatus.cancelled:
        return tc.red;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════
// EDIT ASSIGNMENT DIALOG
// ═══════════════════════════════════════════════════════════════════
class _EditAssignmentDialog extends StatefulWidget {
  final ClientMeetingAssignment assignment;
  final List<Map<String, dynamic>> employees;
  final List<Map<String, dynamic>> clients;
  final String? currentAdminName;

  const _EditAssignmentDialog({
    required this.assignment,
    required this.employees,
    required this.clients,
    this.currentAdminName,
  });

  @override
  State<_EditAssignmentDialog> createState() => _EditAssignmentDialogState();
}

class _EditAssignmentDialogState extends State<_EditAssignmentDialog> {
  AdminColors get tc => AdminTheme.getColors(context);

  final _formKey = GlobalKey<FormState>();

  Map<String, dynamic>? _selectedEmployee;
  Map<String, dynamic>? _selectedClient;

  late DateTime _selectedDate;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  late int _graceMinutes;

  late final TextEditingController _purposeCtrl;
  late final TextEditingController _notesCtrl;

  bool _saving = false;

  @override
  void initState() {
    super.initState();

    final a = widget.assignment;

    _selectedEmployee = _findEmployeeById(a.employeeId);
    _selectedClient = _findClientById(a.clientId);

    _selectedDate = a.scheduledStart;
    _startTime = TimeOfDay(
      hour: a.scheduledStart.hour,
      minute: a.scheduledStart.minute,
    );
    _endTime = TimeOfDay(
      hour: a.scheduledEnd.hour,
      minute: a.scheduledEnd.minute,
    );

    int grace = 15;
    try {
      final g = (a as dynamic).gracePeriod;
      if (g is Duration) grace = g.inMinutes;
    } catch (_) {}
    _graceMinutes = grace;

    _purposeCtrl = TextEditingController(text: a.purpose);
    _notesCtrl = TextEditingController(text: a.notes ?? '');
  }

  Map<String, dynamic>? _findEmployeeById(String id) {
    if (id.isEmpty) return null;
    for (final e in widget.employees) {
      if ((e['id'] ?? '').toString() == id) return e;
    }
    return null;
  }

  Map<String, dynamic>? _findClientById(String id) {
    if (id.isEmpty) return null;
    for (final c in widget.clients) {
      if ((c['id'] ?? '').toString() == id) return c;
    }
    return null;
  }

  @override
  void dispose() {
    _purposeCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startTime = picked;
        final startMin = picked.hour * 60 + picked.minute;
        final endMin = _endTime.hour * 60 + _endTime.minute;
        if (endMin <= startMin) {
          final newEnd = startMin + 120;
          _endTime = TimeOfDay(
            hour: (newEnd ~/ 60) % 24,
            minute: newEnd % 60,
          );
        }
      } else {
        _endTime = picked;
      }
    });
  }

  DateTime _combine(DateTime date, TimeOfDay time) {
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedEmployee == null) {
      _showSnack('Please select an employee', isError: true);
      return;
    }
    if (_selectedClient == null) {
      _showSnack('Please select a client location', isError: true);
      return;
    }

    final startDT = _combine(_selectedDate, _startTime);
    var endDT = _combine(_selectedDate, _endTime);

    final isOvernight = !endDT.isAfter(startDT);
    if (isOvernight) {
      endDT = endDT.add(const Duration(days: 1));
      debugPrint('🌙 [Edit] Overnight: $startDT → $endDT');
    }

    setState(() => _saving = true);

    try {
      final emp = _selectedEmployee!;
      final client = _selectedClient!;

      final empId = (emp['id'] ?? '').toString();
      final empName = (emp['name'] ??
          '${emp['firstName'] ?? ''} ${emp['lastName'] ?? ''}')
          .toString()
          .trim();
      final empEmail = (emp['email'] ?? '').toString();

      final clientId = (client['id'] ?? '').toString();
      final clientName = (client['name'] ?? '').toString();
      final clientAddress = (client['address'] ?? '').toString();
      final clientLat = (client['lat'] as num?)?.toDouble() ?? 0;
      final clientLng = (client['lng'] as num?)?.toDouble() ?? 0;
      final clientRadius =
          (client['radiusMeters'] as num?)?.toDouble() ?? 100;

      final update = <String, dynamic>{
        'employee_id': empId,
        'employee_name': empName,
        'employee_email': empEmail,
        'client_id': clientId,
        'client_name': clientName,
        'client_address': clientAddress,
        'client_lat': clientLat,
        'client_lng': clientLng,
        'client_radius': clientRadius,
        'purpose': _purposeCtrl.text.trim(),
        'notes': _notesCtrl.text.trim().isEmpty
            ? null
            : _notesCtrl.text.trim(),
        'scheduled_start': Timestamp.fromDate(startDT),
        'scheduled_end': Timestamp.fromDate(endDT),
        'grace_period_minutes': _graceMinutes,
        'updated_at': FieldValue.serverTimestamp(),
      };

      debugPrint('💾 [Edit] Updating assignment ${widget.assignment.id}');
      debugPrint('💾 [Edit] Payload: $update');

      await FirebaseFirestore.instance
          .collection('client_meeting_assignments')
          .doc(widget.assignment.id)
          .update(update)
          .timeout(const Duration(seconds: 15));

      debugPrint('✅ [Edit] Update SUCCESS');

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e, stack) {
      debugPrint('❌ [Edit] FAILED: $e');
      debugPrint('❌ [Edit] Stack: $stack');
      if (!mounted) return;
      _showSnack('Update failed: $e', isError: true);
      setState(() => _saving = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? tc.red : tc.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 700;

    return Dialog(
      backgroundColor: tc.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      insetPadding: const EdgeInsets.symmetric(
          horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 620,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: tc.orange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.edit_rounded,
                        color: tc.orange, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Edit Assignment',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: tc.text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Update details for ${widget.assignment.employeeName}',
                          style: TextStyle(
                              fontSize: 11, color: tc.muted),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(false),
                    icon: Icon(Icons.close_rounded,
                        color: tc.muted, size: 20),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: tc.border),

            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildEmployeeDropdown(),
                      const SizedBox(height: 16),
                      _buildClientDropdown(),
                      const SizedBox(height: 16),

                      if (isWide)
                        Row(
                          children: [
                            Expanded(child: _buildDateField()),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildTimeField(
                                  'Start Time', _startTime, true),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildTimeField(
                                  'End Time', _endTime, false),
                            ),
                          ],
                        )
                      else ...[
                        _buildDateField(),
                        const SizedBox(height: 12),
                        _buildTimeField('Start Time', _startTime, true),
                        const SizedBox(height: 12),
                        _buildTimeField('End Time', _endTime, false),
                      ],
                      const SizedBox(height: 16),

                      _buildGraceSelector(),
                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _purposeCtrl,
                        maxLength: 120,
                        decoration: _inputDeco('Purpose *',
                            hint: 'e.g. Product demo with client'),
                        style: TextStyle(color: tc.text),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Required'
                            : null,
                      ),
                      const SizedBox(height: 8),

                      TextFormField(
                        controller: _notesCtrl,
                        maxLines: 3,
                        maxLength: 500,
                        decoration: _inputDeco('Notes (optional)',
                            hint: 'Additional instructions...'),
                        style: TextStyle(color: tc.text),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            Divider(height: 1, color: tc.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(false),
                    icon: Icon(Icons.close_rounded,
                        size: 16, color: tc.muted),
                    label: Text('Cancel',
                        style: TextStyle(color: tc.muted)),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                        : const Icon(Icons.save_rounded, size: 16),
                    label: Text(
                      _saving ? 'Saving...' : 'Save Changes',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: tc.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmployeeDropdown() {
    return DropdownButtonFormField<Map<String, dynamic>>(
      initialValue: _selectedEmployee,
      isExpanded: true,
      dropdownColor: tc.card,
      decoration: InputDecoration(
        labelText: 'Employee *',
        labelStyle: TextStyle(color: tc.muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: tc.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: tc.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: tc.orange, width: 2),
        ),
      ),
      items: widget.employees
          .where((emp) => emp['terminated'] != true)
          .map((emp) {
        final name = (emp['name'] ??
            '${emp['firstName'] ?? ''} ${emp['lastName'] ?? ''}')
            .toString()
            .trim();
        return DropdownMenuItem<Map<String, dynamic>>(
          value: emp,
          child: Text(name.isEmpty ? 'Unknown' : name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: tc.text)),
        );
      }).toList(),
      onChanged: (v) => setState(() => _selectedEmployee = v),
    );
  }

  Widget _buildClientDropdown() {
    if (widget.clients.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: tc.orange.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: tc.orange.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                size: 18, color: tc.orangeText),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'No registered clients available.',
                style: TextStyle(fontSize: 12, color: tc.orangeText),
              ),
            ),
          ],
        ),
      );
    }

    return DropdownButtonFormField<Map<String, dynamic>>(
      initialValue: _selectedClient,
      isExpanded: true,
      dropdownColor: tc.card,
      decoration: InputDecoration(
        labelText: 'Client Location *',
        labelStyle: TextStyle(color: tc.muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: tc.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: tc.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: tc.orange, width: 2),
        ),
      ),
      items: widget.clients.map((c) {
        final name = (c['name'] ?? 'Unknown').toString();
        return DropdownMenuItem<Map<String, dynamic>>(
          value: c,
          child: Text(name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: tc.text)),
        );
      }).toList(),
      onChanged: (v) => setState(() => _selectedClient = v),
    );
  }

  Widget _buildDateField() {
    return InkWell(
      onTap: _pickDate,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          border: Border.all(color: tc.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_rounded,
                size: 16, color: tc.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Date',
                      style: TextStyle(fontSize: 11, color: tc.muted)),
                  Text(
                    DateFormat('MMM d, yyyy').format(_selectedDate),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: tc.text),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeField(String label, TimeOfDay time, bool isStart) {
    final t = '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';

    final sMin = _startTime.hour * 60 + _startTime.minute;
    final eMin = _endTime.hour * 60 + _endTime.minute;
    final overnight = eMin <= sMin && !isStart;

    return InkWell(
      onTap: () => _pickTime(isStart),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          border: Border.all(
              color: overnight ? tc.orange : tc.border,
              width: overnight ? 1.5 : 1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.access_time_rounded, size: 16, color: tc.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(label,
                          style:
                          TextStyle(fontSize: 11, color: tc.muted)),
                      if (overnight) ...[
                        const SizedBox(width: 4),
                        Text('(next day)',
                            style: TextStyle(
                                fontSize: 10,
                                color: tc.orange,
                                fontWeight: FontWeight.w600)),
                      ],
                    ],
                  ),
                  Text(t,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: tc.text)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGraceSelector() {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timer_outlined, size: 16, color: tc.muted),
            const SizedBox(width: 8),
            Text('Grace period:',
                style: TextStyle(fontSize: 13, color: tc.muted)),
          ],
        ),
        ...([0, 15, 30, 60].map((min) {
          final selected = _graceMinutes == min;
          return InkWell(
            onTap: _saving
                ? null
                : () => setState(() => _graceMinutes = min),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: selected
                    ? tc.orange.withValues(alpha: 0.15)
                    : tc.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected
                      ? tc.orange.withValues(alpha: 0.5)
                      : tc.border,
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: Text(
                min == 0 ? 'Strict' : '±${min}m',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight:
                  selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? tc.orangeText : tc.text,
                ),
              ),
            ),
          );
        }).toList()),
      ],
    );
  }

  InputDecoration _inputDeco(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: TextStyle(color: tc.muted),
      hintStyle: TextStyle(color: tc.muted.withValues(alpha: 0.6)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: tc.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: tc.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: tc.orange, width: 2),
      ),
    );
  }
}