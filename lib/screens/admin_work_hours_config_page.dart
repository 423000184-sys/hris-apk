// lib/screens/admin_work_hours_config_page.dart
import 'package:flutter/material.dart';
import '../services/work_hours_service.dart';
import 'admin_theme.dart';

class AdminWorkHoursConfigPage extends StatefulWidget {
  const AdminWorkHoursConfigPage({super.key});

  @override
  State<AdminWorkHoursConfigPage> createState() =>
      _AdminWorkHoursConfigPageState();
}

class _AdminWorkHoursConfigPageState
    extends State<AdminWorkHoursConfigPage> {
  bool _loading = true;
  bool _saving = false;

  // Form state
  int _lunchBreakMinutes = 60;
  int _applyAfterMinutes = 360;
  int _standardWorkMinutes = 480;
  bool _allowOvertime = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final config = await WorkHoursService.instance.loadConfig(force: true);
    if (mounted) {
      setState(() {
        _lunchBreakMinutes = config.lunchBreakMinutes;
        _applyAfterMinutes = config.applyAfterMinutes;
        _standardWorkMinutes = config.standardWorkMinutes;
        _allowOvertime = config.allowOvertime;
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final config = WorkHoursConfig(
        lunchBreakMinutes: _lunchBreakMinutes,
        applyAfterMinutes: _applyAfterMinutes,
        standardWorkMinutes: _standardWorkMinutes,
        allowOvertime: _allowOvertime,
      );

      await WorkHoursService.instance.updateConfig(config);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Work hours config updated!'),
          backgroundColor: Color(0xFF16A34A),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Failed: $e'),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ThemeProvider.instance,
      builder: (context, _) {
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
              'Work Hours Config',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: tc.text,
              ),
            ),
            actions: [
              if (_saving)
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: tc.orange,
                        strokeWidth: 2,
                      ),
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: TextButton(
                    onPressed: _save,
                    child: Text(
                      'Save',
                      style: TextStyle(
                        color: tc.orange,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(height: 1, color: tc.border),
            ),
          ),
          body: _loading
              ? Center(child: CircularProgressIndicator(color: tc.orange))
              : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Preview card
                _buildPreviewCard(tc),
                const SizedBox(height: 20),

                // Section: Lunch Break
                _sectionHeader(tc, '🍱 Lunch Break'),
                _buildLunchBreakCard(tc),

                const SizedBox(height: 20),

                // Section: Threshold
                _sectionHeader(tc, '⏱️ When to apply lunch break'),
                _buildThresholdCard(tc),

                const SizedBox(height: 20),

                // Section: Standard work hours
                _sectionHeader(tc, '📅 Standard work hours'),
                _buildStandardCard(tc),

                const SizedBox(height: 20),

                // Section: Overtime
                _sectionHeader(tc, '💰 Overtime'),
                _buildOvertimeCard(tc),

                const SizedBox(height: 24),
                _buildSaveButton(tc),
                const SizedBox(height: 40),
              ],
            ),
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // PREVIEW CARD — live preview ng effect sa 9am-6pm shift
  // ═══════════════════════════════════════════════════════════════
  Widget _buildPreviewCard(AdminColors tc) {
    // Example shift: 8:00 AM to 5:00 PM
    final rawMinutes = 9 * 60; // 9 hours
    final lunchApplied = rawMinutes >= _applyAfterMinutes;
    final lunchDeduct = lunchApplied ? _lunchBreakMinutes : 0;
    var netMinutes = rawMinutes - lunchDeduct;
    int overtime = 0;

    if (netMinutes > _standardWorkMinutes) {
      overtime = netMinutes - _standardWorkMinutes;
      if (!_allowOvertime) netMinutes = _standardWorkMinutes;
    }

    String fmt(int m) {
      final h = m ~/ 60;
      final mm = m % 60;
      if (mm == 0) return '${h}h';
      return '${h}h ${mm}m';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tc.orange.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calculate_rounded, color: tc.orange, size: 18),
              const SizedBox(width: 8),
              Text(
                'Preview — 8:00 AM to 5:00 PM shift',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: tc.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: tc.border, height: 1),
          const SizedBox(height: 12),
          _previewRow(tc, 'Clock in', '8:00 AM', tc.text),
          _previewRow(tc, 'Clock out', '5:00 PM', tc.text),
          _previewRow(tc, 'Raw total', fmt(rawMinutes), tc.text),
          _previewRow(
            tc,
            'Lunch break',
            lunchApplied ? '-${fmt(_lunchBreakMinutes)}' : '— (not applied)',
            lunchApplied ? const Color(0xFFEF4444) : tc.muted,
          ),
          if (overtime > 0) ...[
            _previewRow(
              tc,
              'Overtime',
              '${fmt(overtime)} ${_allowOvertime ? "(paid)" : "(capped)"}',
              const Color(0xFF16A34A),
            ),
          ],
          Divider(color: tc.border, height: 20),
          _previewRow(
            tc,
            '💰 Net hours (paid)',
            fmt(netMinutes),
            tc.orange,
            isBold: true,
          ),
        ],
      ),
    );
  }

  Widget _previewRow(
      AdminColors tc,
      String label,
      String value,
      Color valueColor, {
        bool isBold = false,
      }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: tc.textMuted,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isBold ? 14 : 12.5,
              color: valueColor,
              fontWeight: isBold ? FontWeight.w800 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // SECTION HEADER
  // ═══════════════════════════════════════════════════════════════
  Widget _sectionHeader(AdminColors tc, String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: tc.textMuted,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // LUNCH BREAK CARD
  // ═══════════════════════════════════════════════════════════════
  Widget _buildLunchBreakCard(AdminColors tc) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tc.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How many minutes to deduct for lunch?',
            style: TextStyle(fontSize: 13, color: tc.text),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip(tc, 30, '30 min'),
              _chip(tc, 45, '45 min'),
              _chip(tc, 60, '60 min (1 hr)'),
              _chip(tc, 90, '90 min'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _lunchBreakMinutes.toDouble(),
                  min: 0,
                  max: 120,
                  divisions: 24,
                  activeColor: tc.orange,
                  label: '$_lunchBreakMinutes min',
                  onChanged: (v) {
                    setState(() => _lunchBreakMinutes = v.round());
                  },
                ),
              ),
              SizedBox(
                width: 70,
                child: Text(
                  '$_lunchBreakMinutes min',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: tc.orange,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(AdminColors tc, int value, String label) {
    final selected = _lunchBreakMinutes == value;
    return GestureDetector(
      onTap: () => setState(() => _lunchBreakMinutes = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? tc.orange.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? tc.orange : tc.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
            color: selected ? tc.orange : tc.text,
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // THRESHOLD CARD
  // ═══════════════════════════════════════════════════════════════
  Widget _buildThresholdCard(AdminColors tc) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tc.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Apply lunch deduction lang kung ang shift ay lumagpas sa:',
            style: TextStyle(fontSize: 13, color: tc.text),
          ),
          const SizedBox(height: 4),
          Text(
            'Kung mas maikli pa sa threshold, walang lunch break deduction (halimbawa: half-day shift)',
            style: TextStyle(fontSize: 11, color: tc.textMuted),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _thresholdChip(tc, 240, '4 hours'),
              _thresholdChip(tc, 300, '5 hours'),
              _thresholdChip(tc, 360, '6 hours'),
              _thresholdChip(tc, 420, '7 hours'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _thresholdChip(AdminColors tc, int value, String label) {
    final selected = _applyAfterMinutes == value;
    return GestureDetector(
      onTap: () => setState(() => _applyAfterMinutes = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? tc.orange.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? tc.orange : tc.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
            color: selected ? tc.orange : tc.text,
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // STANDARD CARD
  // ═══════════════════════════════════════════════════════════════
  Widget _buildStandardCard(AdminColors tc) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tc.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Standard work hours per day',
                  style: TextStyle(fontSize: 13, color: tc.text),
                ),
                Text(
                  'Ito yung base para sa overtime computation',
                  style: TextStyle(fontSize: 11, color: tc.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          DropdownButton<int>(
            value: _standardWorkMinutes,
            dropdownColor: tc.card,
            underline: const SizedBox.shrink(),
            style: TextStyle(
              color: tc.text,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
            items: const [
              DropdownMenuItem(value: 240, child: Text('4 hours')),
              DropdownMenuItem(value: 300, child: Text('5 hours')),
              DropdownMenuItem(value: 360, child: Text('6 hours')),
              DropdownMenuItem(value: 420, child: Text('7 hours')),
              DropdownMenuItem(value: 480, child: Text('8 hours')),
              DropdownMenuItem(value: 540, child: Text('9 hours')),
            ],
            onChanged: (v) {
              if (v != null) {
                setState(() => _standardWorkMinutes = v);
              }
            },
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // OVERTIME CARD
  // ═══════════════════════════════════════════════════════════════
  Widget _buildOvertimeCard(AdminColors tc) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tc.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Allow overtime',
                  style: TextStyle(fontSize: 13, color: tc.text),
                ),
                Text(
                  _allowOvertime
                      ? 'Sobra sa 8 hours ay binabayaran (may OT pay)'
                      : 'Sobra sa 8 hours ay hindi binabayaran (capped)',
                  style: TextStyle(
                    fontSize: 11,
                    color: _allowOvertime
                        ? const Color(0xFF16A34A)
                        : tc.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _allowOvertime,
            activeColor: tc.orange,
            onChanged: (v) => setState(() => _allowOvertime = v),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // SAVE BUTTON
  // ═══════════════════════════════════════════════════════════════
  Widget _buildSaveButton(AdminColors tc) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _saving ? null : _save,
        icon: _saving
            ? const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            color: Colors.white,
            strokeWidth: 2,
          ),
        )
            : const Icon(Icons.save_rounded, size: 18),
        label: Text(
          _saving ? 'Saving...' : 'Save Configuration',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: tc.orange,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}