// lib/widgets/work_hours_summary_card.dart
import 'package:flutter/material.dart';

/// 🍱 Work Hours Summary Card
/// Reusable widget para sa net hours display na may lunch break
/// deduction indicator.
class WorkHoursSummaryCard extends StatelessWidget {
  final int rawMinutes;
  final int lunchMinutes;
  final int netMinutes;
  final int overtimeMinutes;
  final String title;
  final String? subtitle;
  final bool compact;
  final bool showDailyBreakdown;
  final List<DailyHoursDisplay>? dailyBreakdown;

  const WorkHoursSummaryCard({
    super.key,
    required this.rawMinutes,
    required this.lunchMinutes,
    required this.netMinutes,
    required this.overtimeMinutes,
    this.title = 'Work Hours',
    this.subtitle,
    this.compact = false,
    this.showDailyBreakdown = false,
    this.dailyBreakdown,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasLunch = lunchMinutes > 0;
    final hasOT = overtimeMinutes > 0;

    final bgColor = isDark
        ? const Color(0xFF18181B)
        : Colors.white.withValues(alpha: 0.5);
    const borderColor = Color(0xFFFFA500);
    final textColor = isDark ? Colors.white : Colors.black;
    final mutedColor =
    isDark ? const Color(0xFFA1A1AA) : const Color(0xFF71717A);

    return Container(
      padding: EdgeInsets.all(compact ? 14 : 18),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF8A00).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.schedule_rounded,
                  color: Color(0xFFFF8A00),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: compact ? 12 : 13,
                        fontWeight: FontWeight.w700,
                        color: textColor,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: TextStyle(fontSize: 10, color: mutedColor),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF8A00).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _fmt(netMinutes),
                  style: const TextStyle(
                    color: Color(0xFFFF8A00),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Rows
          _row(
            icon: Icons.timer_outlined,
            label: 'Total time',
            value: _fmt(rawMinutes),
            color: textColor,
            mutedColor: mutedColor,
          ),

          if (hasLunch) ...[
            const SizedBox(height: 6),
            _row(
              icon: Icons.restaurant_rounded,
              label: 'Lunch break',
              value: '-${_fmt(lunchMinutes)}',
              color: const Color(0xFFEF4444),
              mutedColor: mutedColor,
            ),
          ],

          if (hasOT) ...[
            const SizedBox(height: 6),
            _row(
              icon: Icons.flash_on_rounded,
              label: 'Overtime',
              value: '+${_fmt(overtimeMinutes)}',
              color: const Color(0xFF16A34A),
              mutedColor: mutedColor,
            ),
          ],

          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Container(
              height: 1,
              color: borderColor.withValues(alpha: 0.2),
            ),
          ),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF16A34A),
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Net hours worked',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                    ),
                  ),
                ],
              ),
              Text(
                _fmt(netMinutes),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF16A34A),
                ),
              ),
            ],
          ),

          // Optional daily breakdown
          if (showDailyBreakdown &&
              dailyBreakdown != null &&
              dailyBreakdown!.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(height: 1, color: borderColor.withValues(alpha: 0.2)),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.list_alt_rounded, size: 13, color: mutedColor),
                const SizedBox(width: 6),
                Text(
                  'Daily Breakdown',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: mutedColor,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                Text(
                  '${dailyBreakdown!.length} day(s)',
                  style: TextStyle(fontSize: 10, color: mutedColor),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...dailyBreakdown!.take(10).map((d) => _dailyRow(
              d,
              textColor,
              mutedColor,
            )),
          ],
        ],
      ),
    );
  }

  Widget _row({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required Color mutedColor,
  }) {
    return Row(
      children: [
        Icon(icon, size: 13, color: mutedColor),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              color: mutedColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12.5,
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _dailyRow(
      DailyHoursDisplay d,
      Color textColor,
      Color mutedColor,
      ) {
    final hIn = _fmtTime(d.clockIn);
    final hOut = _fmtTime(d.clockOut);
    final hasLunch = d.lunchMinutes > 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(
              d.date.length >= 10 ? d.date.substring(5) : d.date,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ),
          Expanded(
            child: Text(
              '$hIn – $hOut',
              style: TextStyle(fontSize: 10.5, color: mutedColor),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _fmt(d.netMinutes),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
              ),
              if (hasLunch)
                Text(
                  '-${_fmt(d.lunchMinutes)} lunch',
                  style: TextStyle(fontSize: 9, color: mutedColor),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _fmtTime(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    final p = d.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $p';
  }

  static String _fmt(int m) {
    if (m <= 0) return '0m';
    final h = m ~/ 60;
    final mm = m % 60;
    if (h == 0) return '${mm}m';
    if (mm == 0) return '${h}h';
    return '${h}h ${mm}m';
  }
}

// Model for daily breakdown display
class DailyHoursDisplay {
  final String date;
  final DateTime clockIn;
  final DateTime clockOut;
  final int rawMinutes;
  final int lunchMinutes;
  final int netMinutes;
  final int overtimeMinutes;

  const DailyHoursDisplay({
    required this.date,
    required this.clockIn,
    required this.clockOut,
    required this.rawMinutes,
    required this.lunchMinutes,
    required this.netMinutes,
    required this.overtimeMinutes,
  });
}