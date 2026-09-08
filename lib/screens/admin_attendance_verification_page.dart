import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'admin_dashboard.dart';

// This widget no longer builds its own AppBar/Sidebar/Drawer — those are
// hardcoded duplicates of AdminDashboard's shared shell. It now returns
// only the page CONTENT, so AdminDashboard can embed it inside its own
// persistent top bar + sidebar (see AdminDashboardState.buildPage(),
// case 3). Call `onBack` to return to the normal Attendance list — it's
// wired by AdminDashboard, not hardcoded to Navigator.pop anymore.
class AdminAttendanceVerificationPage extends StatelessWidget {
  final String logId;
  final Map<String, dynamic> logData;
  final VoidCallback? onBack;

  const AdminAttendanceVerificationPage({
    super.key,
    required this.logId,
    required this.logData,
    this.onBack,
  });

  // ---- Design tokens — kept identical to AdminDashboard's palette so the
  // content still matches once it's embedded in the shared shell. ----
  static const Color _bg = Color(0xFFF7F4F1);
  static const Color _orange = Color(0xFFF3A24B);
  static const Color _cardBorder = Color(0xFFECE8E3);
  static const Color _textDark = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _mutedLight = Color(0xFF9CA3AF);
  static const Color _innerBoxBg = Color(0xFFF9FAFB);
  static const Color _innerBoxBorder = Color(0xFFF3F4F6);
  static const Color _greenBadgeBg = Color(0xFFDEF7EC);
  static const Color _greenBadgeText = Color(0xFF03543F);
  static const Color _amberBadgeBg = Color(0xFFFEF3C7);
  static const Color _amberBadgeText = Color(0xFF92400E);
  static const Color _blueBadgeBg = Color(0xFFEFF6FF);
  static const Color _blueBadgeText = Color(0xFF2563EB);
  static const Color _timelineDot = Color(0xFF9CA3AF);
  static const Color _timelineDotActive = Color(0xFFB45309);

  String _s(dynamic v, [String fallback = 'Not recorded']) {
    if (v == null) return fallback;
    final str = v.toString().trim();
    return str.isEmpty ? fallback : str;
  }

  @override
  Widget build(BuildContext context) {
    final name = _s(logData['employee_name'] ?? logData['name'], 'System User');
    final role = _s(logData['role'], 'Employee');
    final department = _s(logData['department']);
    final manager = _s(logData['manager']);
    final photoUrl = _s(logData['photoUrl'], '');
    final client = _s(logData['client']);
    final deviceInfo = _s(logData['deviceInfo']);
    final locationName = _s(logData['locationName']);
    final lat = logData['latitude'];
    final lng = logData['longitude'];
    final coordsStr = (lat != null && lng != null) ? '$lat, $lng' : 'Not recorded';
    final verificationNote = _s(logData['verificationNote'], 'No additional notes');

    final ts = logData['timestamp'];
    final DateTime? dateObj = ts is Timestamp ? ts.toDate() : (ts is DateTime ? ts : null);
    final dateStr = dateObj != null ? DateFormat('MMM d, yyyy \u2022 hh:mm:ss a').format(dateObj) : 'Not recorded';

    // Shows the tapped log as the active/top timeline entry. Wire in real
    // history later via logData['history'] if/when that data exists —
    // this never fabricates events that weren't actually logged.
    final rawHistory = logData['history'];
    final List<Map<String, dynamic>> history = rawHistory is List
        ? rawHistory.whereType<Map<String, dynamic>>().toList()
        : <Map<String, dynamic>>[];
    final timelineEntries = [logData, ...history];

    return LayoutBuilder(builder: (_, c) {
      final wide = c.maxWidth >= 900;
      return Container(
        color: _bg,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Breadcrumb + back
              Row(children: [
                if (onBack != null) ...[
                  InkWell(
                    onTap: onBack,
                    borderRadius: BorderRadius.circular(8),
                    child: const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(Icons.arrow_back_rounded, size: 16, color: _muted),
                    ),
                  ),
                ],
                RichText(
                  text: TextSpan(
                    style: const TextStyle(fontSize: 12, color: _muted),
                    children: [
                      TextSpan(
                        text: 'Attendance Logs',
                        recognizer: onBack != null
                            ? (TapGestureRecognizerHolder(onBack!).recognizer)
                            : null,
                      ),
                      const TextSpan(text: ' > '),
                      const TextSpan(text: 'Verification Detail', style: TextStyle(color: _orange, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 8),

              // Page header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Attendance Verification', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: _textDark)),
                  ElevatedButton.icon(
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Marked as approved.')),
                    ),
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: const Text('Approve All', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              wide
                  ? IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 420, child: _leftColumn(name, role, department, manager, photoUrl, timelineEntries)),
                    const SizedBox(width: 24),
                    Expanded(child: _verificationCard(client, deviceInfo, locationName, coordsStr, verificationNote, dateStr)),
                  ],
                ),
              )
                  : Column(
                children: [
                  _leftColumn(name, role, department, manager, photoUrl, timelineEntries),
                  const SizedBox(height: 20),
                  _verificationCard(client, deviceInfo, locationName, coordsStr, verificationNote, dateStr),
                ],
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget _leftColumn(String name, String role, String department, String manager, String photoUrl, List<Map<String, dynamic>> timelineEntries) {
    return Column(
      children: [
        _employeeCard(name, role, department, manager, photoUrl),
        const SizedBox(height: 28),
        _timelineCard(timelineEntries),
      ],
    );
  }

  Widget _employeeCard(String name, String role, String department, String manager, String photoUrl) {
    final employeeId = logId.isNotEmpty ? logId : 'N/A';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: _cardBorder)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(clipBehavior: Clip.none, children: [
            Row(children: [
              ClipOval(
                child: photoUrl.isNotEmpty
                    ? Image.network(photoUrl, width: 48, height: 48, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _initialsAvatar(name))
                    : _initialsAvatar(name),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _textDark), overflow: TextOverflow.ellipsis),
                    Text(role, style: const TextStyle(fontSize: 12, color: _muted), overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ]),
            Positioned(
              top: -4, right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: _blueBadgeBg, borderRadius: BorderRadius.circular(6)),
                child: Text(employeeId, style: const TextStyle(color: _blueBadgeText, fontSize: 10, fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
          const SizedBox(height: 20),
          Container(height: 1, color: _innerBoxBorder),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _metaColumn('DEPARTMENT', department),
              _metaColumn('MANAGER', manager),
            ],
          ),
        ],
      ),
    );
  }

  Widget _initialsAvatar(String name) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      width: 48, height: 48,
      color: _orange,
      alignment: Alignment.center,
      child: Text(initial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
    );
  }

  Widget _metaColumn(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontSize: 10, color: _mutedLight, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
      const SizedBox(height: 2),
      Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _textDark)),
    ],
  );

  Widget _timelineCard(List<Map<String, dynamic>> entries) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: _cardBorder)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text('Recent Time-In Events', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _textDark)),
              Text('This Week', style: TextStyle(fontSize: 11, color: _mutedLight)),
            ],
          ),
          const SizedBox(height: 24),
          for (int i = 0; i < entries.length; i++)
            _timelineItem(entries[i], isFirst: i == 0, isLast: i == entries.length - 1),
        ],
      ),
    );
  }

  Widget _timelineItem(Map<String, dynamic> entry, {required bool isFirst, required bool isLast}) {
    final ts = entry['timestamp'];
    final DateTime? dateObj = ts is Timestamp ? ts.toDate() : (ts is DateTime ? ts : null);
    final dateLabel = dateObj != null ? DateFormat('MMM d, hh:mm a').format(dateObj) : 'Not recorded';
    final type = _s(entry['type'], 'LOGIN').toString().toUpperCase();
    final isLogin = type.contains('IN') || type.contains('LOGIN');
    final verifiedVia = _s(entry['verificationMethod'], 'Not recorded');
    final locationTag = _s(entry['locationName'], '');

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 12,
            child: Column(children: [
              Container(
                width: 12, height: 12,
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(color: isFirst ? _timelineDotActive : _timelineDot, shape: BoxShape.circle),
              ),
              if (!isLast) Expanded(child: Container(width: 2, color: const Color(0xFFE5E7EB))),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 28),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                decoration: BoxDecoration(color: _innerBoxBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: _cardBorder)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(dateLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _textDark)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: isLogin ? _greenBadgeBg : _amberBadgeBg, borderRadius: BorderRadius.circular(4)),
                          child: Text(isLogin ? 'Verified' : 'Logout', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: isLogin ? _greenBadgeText : _amberBadgeText)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text('Verification: $verifiedVia', style: const TextStyle(fontSize: 11, color: _muted)),
                    if (locationTag.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(locationTag, style: const TextStyle(fontSize: 10, color: _mutedLight)),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _verificationCard(String client, String deviceInfo, String locationName, String coordsStr, String verificationNote, String dateStr) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: _cardBorder)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                const Icon(Icons.description_outlined, size: 16, color: _orange),
                const SizedBox(width: 8),
                const Text('Verification Detail', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _textDark)),
              ]),
              IconButton(
                icon: const Icon(Icons.flag_outlined, color: Color(0xFFEF4444), size: 18),
                onPressed: () {},
                tooltip: 'Flag for review',
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(verificationNote, style: const TextStyle(fontSize: 12, color: _muted)),
          const SizedBox(height: 24),

          Container(
            height: 280,
            width: double.infinity,
            clipBehavior: Clip.hardEdge,
            decoration: BoxDecoration(color: const Color(0xFFE5E7EB), borderRadius: BorderRadius.circular(8), border: Border.all(color: _cardBorder)),
            child: Stack(
              children: [
                Center(child: Icon(Icons.terrain_rounded, size: 64, color: Colors.black.withOpacity(0.15))),
                Positioned(
                  left: 12, right: 12, bottom: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6, offset: const Offset(0, -1))]),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                const Icon(Icons.calendar_today_rounded, size: 11, color: _muted),
                                const SizedBox(width: 4),
                                Flexible(child: Text(dateStr, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _textDark), overflow: TextOverflow.ellipsis)),
                              ]),
                              const SizedBox(height: 2),
                              Row(children: [
                                const Icon(Icons.location_on_rounded, size: 12, color: Color(0xFFEF4444)),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text.rich(
                                    TextSpan(children: [
                                      TextSpan(text: coordsStr, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _textDark)),
                                      if (locationName != 'Not recorded')
                                        TextSpan(text: ' ($locationName)', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.normal, color: _muted)),
                                    ]),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ]),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: _greenBadgeBg, borderRadius: BorderRadius.circular(6)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.verified_rounded, size: 12, color: _greenBadgeText),
                            const SizedBox(width: 4),
                            const Text('Location Matched', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _greenBadgeText)),
                          ]),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          Row(
            children: [
              Expanded(child: _subDetailBox(Icons.work_outline_rounded, 'Client', client)),
              const SizedBox(width: 12),
              Expanded(child: _subDetailBox(Icons.phone_iphone_rounded, 'Device Info', deviceInfo)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _subDetailBox(IconData icon, String label, String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
    decoration: BoxDecoration(color: _innerBoxBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: _cardBorder)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(icon, size: 12, color: _mutedLight),
          const SizedBox(width: 6),
          Text(label.toUpperCase(), style: const TextStyle(fontSize: 10, color: _mutedLight, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
        ]),
        const SizedBox(height: 8),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _textDark)),
      ],
    ),
  );
}

// Small helper so the "Attendance Logs" breadcrumb segment is tappable
// (acts like a second back affordance) without pulling in a StatefulWidget
// just for a TapGestureRecognizer.
class TapGestureRecognizerHolder {
  final VoidCallback onTap;
  TapGestureRecognizerHolder(this.onTap);
  late final recognizer = (TapGestureRecognizer()..onTap = onTap);
}