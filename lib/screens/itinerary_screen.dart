// lib/screens/itinerary_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

// ══════════════════════════════════════════════════════════════
// THEME COLORS — mirrors DashboardScreen._ThemeColors
// ══════════════════════════════════════════════════════════════
class _ThemeColors {
  final bool isDark;
  const _ThemeColors(this.isDark);

  Color get bg => isDark ? const Color(0xFF0F0F10) : const Color(0xFFFFFFFF);
  Color get textBlack => isDark ? Colors.white : const Color(0xFF000000);
  Color get textDark => isDark ? Colors.white : const Color(0xFF1A1A1A);
  Color get textGray =>
      isDark ? const Color(0xFFB0B0B0) : const Color(0xFF71717A);
  Color get textMuted =>
      isDark ? const Color(0xFF888888) : const Color(0xFFA1A1AA);
  Color get cardFill => isDark
      ? const Color(0xFF1F1F23)
      : const Color(0xFFF8F8F8);
  Color get darkBorder =>
      isDark ? const Color(0xFF3F3F46) : const Color(0xFF27272A);
}

// ══════════════════════════════════════════════════════════════
// COLORS — brand colors (theme-independent)
// ══════════════════════════════════════════════════════════════
class _ItinColors {
  static const Color orange = Color(0xFFFF8A00);
  static const Color orangeDeep = Color(0xFFFA6A00);
  static const Color orangeDark = Color(0xFFF54900);
  static const Color orangeBorder = Color(0xFFFFA500);
  static const Color lime = Color(0xFFC4FF0A);
  static const Color limeBg = Color(0x1AC4FF0A);
  static const Color limeBorder = Color(0x33C4FF0A);
  static const Color cardBg = Color(0xFFF8F8F8); // kept for light fallback
  static const Color error = Color(0xFFDC2626);
  static const Color errorBg = Color(0x1ADC2626);
  static const Color errorBorder = Color(0x33DC2626);
  static const Color muted = Color(0xFF71717A);

  static const LinearGradient headerGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [orange, orangeDeep, orangeDark],
    stops: [0.0, 0.5, 1.0],
  );
}

// ══════════════════════════════════════════════════════════════
// POLICY — Total credits (36 by default)
// ══════════════════════════════════════════════════════════════
const int _kTotalCredits = 36;

// ══════════════════════════════════════════════════════════════
// ITINERARY SCREEN — shows CLIENT MEETING data
// ══════════════════════════════════════════════════════════════
class ItineraryScreen extends StatefulWidget {
  final String employeeId;
  final String employeeName;
  final VoidCallback? onGoHome;

  const ItineraryScreen({
    super.key,
    required this.employeeId,
    required this.employeeName,
    this.onGoHome,
  });

  @override
  State<ItineraryScreen> createState() => _ItineraryScreenState();
}

class _ItineraryScreenState extends State<ItineraryScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _history = [];
  int _usedTotal = 0;

  int get _remaining =>
      (_kTotalCredits - _usedTotal).clamp(0, _kTotalCredits);

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  // ══════════════════════════════════════════════════════════
  // FETCH — from attendance_logs (type = 'client_meeting')
  // ══════════════════════════════════════════════════════════
  Future<void> _fetchData() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final snap = await FirebaseFirestore.instance
          .collection('attendance_logs')
          .where('type', isEqualTo: 'client_meeting')
          .get();

      final list = <Map<String, dynamic>>[];
      int used = 0;

      for (final doc in snap.docs) {
        final d = doc.data();

        // ─── Filter by employee ID (either field name) ───
        final empId = (d['employee_id'] ?? d['employeeId'] ?? '').toString();
        if (empId.isEmpty) continue;
        if (empId != widget.employeeId) continue;

        final status =
        (d['status'] ?? 'pending_hr_approval').toString().toLowerCase();
        final location =
        (d['location_name'] ?? 'Unknown Location').toString();
        final ts = d['timestamp'] ?? d['createdAt'];

        list.add({
          'id': doc.id,
          'location': location,
          'date': ts,
          'status': status,
        });

        // ✅ Count only APPROVED as "used"
        if (status == 'approved') used += 1;
      }

      // Sort newest first
      list.sort((a, b) {
        final at = _toDateTime(a['date']);
        final bt = _toDateTime(b['date']);
        if (at == null && bt == null) return 0;
        if (at == null) return 1;
        if (bt == null) return -1;
        return bt.compareTo(at);
      });

      debugPrint('📋 [Itinerary] Found ${list.length} client meetings '
          '($used approved) for ${widget.employeeId}');

      if (!mounted) return;
      setState(() {
        _history = list;
        _usedTotal = used;
        _loading = false;
      });
    } catch (e) {
      debugPrint('ItineraryScreen fetch error: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load client meeting data.';
      });
    }
  }

  DateTime? _toDateTime(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  String _fmt(dynamic v) {
    final dt = _toDateTime(v);
    if (dt == null) return 'N/A';
    return DateFormat('MMM d, yyyy').format(dt);
  }

  String _fmtTime(dynamic v) {
    final dt = _toDateTime(v);
    if (dt == null) return '';
    return DateFormat('h:mm a').format(dt);
  }

  void _goBack() {
    if (widget.onGoHome != null) {
      widget.onGoHome!();
    } else if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = _ThemeColors(isDark);

    return Scaffold(
      backgroundColor: tc.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(tc),
            const SizedBox(height: 20),
            Expanded(
              child: RefreshIndicator(
                color: _ItinColors.orange,
                onRefresh: _fetchData,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildStatCards(tc),
                      const SizedBox(height: 28),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          'Client Meeting History',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: tc.textBlack,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildHistoryList(tc),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── HEADER ─────────────────────────────────────────────
  Widget _buildHeader(_ThemeColors tc) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      decoration: const BoxDecoration(
        gradient: _ItinColors.headerGradient,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _goBack,
            behavior: HitTestBehavior.opaque,
            child: const Icon(
              Icons.chevron_left_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Itinerary',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
          ),
          GestureDetector(
            onTap: _fetchData,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                // ⭐ Theme-aware refresh button bg
                color: tc.isDark ? const Color(0xFF1F1F23) : _ItinColors.cardBg,
                borderRadius: BorderRadius.circular(12),
                border:
                Border.all(color: _ItinColors.orangeBorder, width: 1.11),
              ),
              child: const Icon(
                Icons.refresh_rounded,
                color: _ItinColors.orange,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── STAT CARDS ────────────────────────────────────────
  Widget _buildStatCards(_ThemeColors tc) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Expanded(
            child: _StatCard(
              value: '$_kTotalCredits',
              label: 'Total',
              valueColor: tc.textBlack,
              labelColor: tc.textMuted,
              bgColor: tc.cardFill,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _StatCard(
              value: '$_usedTotal',
              label: 'Used',
              valueColor: _ItinColors.lime,
              labelColor: tc.textMuted,
              bgColor: tc.cardFill,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _StatCard(
              value: '$_remaining',
              label: 'Remaining',
              valueColor: _ItinColors.orange,
              labelColor: _ItinColors.orange,
              bgColor: _ItinColors.orange.withValues(alpha: 0.2),
              borderColor: _ItinColors.orange.withValues(alpha: 0.2),
            ),
          ),
        ],
      ),
    );
  }

  // ─── HISTORY LIST ──────────────────────────────────────
  Widget _buildHistoryList(_ThemeColors tc) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: CircularProgressIndicator(color: _ItinColors.orange),
        ),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Center(
          child: Column(
            children: [
              Text(_error!, style: const TextStyle(color: _ItinColors.error)),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _fetchData,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _ItinColors.orange,
                ),
                child:
                const Text('Retry', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    if (_history.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.event_busy_rounded,
                  size: 40, color: tc.textMuted),
              const SizedBox(height: 12),
              Text(
                'No client meeting records yet.',
                style: TextStyle(color: tc.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                'Pumunta sa Login → Client Meeting para mag-check in.',
                textAlign: TextAlign.center,
                style: TextStyle(color: tc.textMuted, fontSize: 11),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: _history.map((item) => _historyCard(item, tc)).toList(),
      ),
    );
  }

  Widget _historyCard(Map<String, dynamic> item, _ThemeColors tc) {
    final status = (item['status'] ?? 'pending_hr_approval')
        .toString()
        .toLowerCase();

    final isApproved = status == 'approved';
    final isRejected = status == 'rejected';
    final isPending = !isApproved && !isRejected;

    final badgeBg = isApproved
        ? _ItinColors.limeBg
        : (isPending
        ? _ItinColors.orange.withValues(alpha: 0.1)
        : _ItinColors.errorBg);
    final badgeBorder = isApproved
        ? _ItinColors.limeBorder
        : (isPending
        ? _ItinColors.orange.withValues(alpha: 0.2)
        : _ItinColors.errorBorder);
    final badgeText = isApproved
        ? _ItinColors.lime
        : (isPending ? _ItinColors.orange : _ItinColors.error);

    final badgeLabel =
    isApproved ? 'Approved' : (isPending ? 'Pending' : 'Rejected');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        // ⭐ Theme-aware card bg
        color: tc.cardFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _ItinColors.orangeBorder, width: 1.11),
        boxShadow: [
          BoxShadow(
            color: Colors.black
                .withValues(alpha: tc.isDark ? 0.25 : 0.06),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Title + Status badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Client Meeting',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: tc.textBlack,
                ),
              ),
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: badgeBorder, width: 1.11),
                ),
                child: Text(
                  badgeLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: badgeText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Row 2: Location + Date
          Row(
            children: [
              const Icon(
                Icons.location_on_rounded,
                size: 12,
                color: _ItinColors.orange,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  item['location'].toString(),
                  style: TextStyle(
                    fontSize: 12,
                    color: tc.textMuted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${_fmt(item['date'])} · ${_fmtTime(item['date'])}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: tc.textBlack,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// STAT CARD
// ══════════════════════════════════════════════════════════════
class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  final Color valueColor;
  final Color labelColor;
  final Color bgColor;
  final Color borderColor;

  const _StatCard({
    required this.value,
    required this.label,
    required this.valueColor,
    required this.labelColor,
    required this.bgColor,
    this.borderColor = _ItinColors.orangeBorder,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.11),
        boxShadow: [
          BoxShadow(
            color: Colors.black
                .withValues(alpha: isDark ? 0.25 : 0.05),
            blurRadius: 3,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w500,
              color: valueColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, color: labelColor),
          ),
        ],
      ),
    );
  }
}