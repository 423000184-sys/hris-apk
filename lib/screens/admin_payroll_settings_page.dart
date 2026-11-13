// lib/screens/admin_payroll_settings_page.dart
// HR-editable payroll rates (SSS, PhilHealth, Pag-IBIG, OT/ND multipliers,
// BIR withholding brackets). Stored in Firestore: settings/payroll.
//
// 🔐 Saving requires the HR Assistant override password (shared with
//    admin_payroll_management_page.dart via settings/payroll_override).
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import '../services/payroll_calculator.dart';
import 'admin_theme.dart';

class _Field {
  final String key;
  final String label;
  final String unit; // '%' or '₱'
  final String help;
  const _Field(this.key, this.label, this.unit, [this.help = '']);
  bool get isPercent => unit == '%';
}

class _Group {
  final String title;
  final String note;
  final List<_Field> fields;
  const _Group(this.title, this.note, this.fields);
}

const List<_Group> _groups = <_Group>[
  _Group('SSS', 'Employee share = rate x MSC bracket (MSC = salary rounded to the step, clamped to min/max).', <_Field>[
    _Field('sssEmployeeRate', 'Employee rate', '%'),
    _Field('sssMinMsc', 'Minimum MSC', '₱'),
    _Field('sssMaxMsc', 'Maximum MSC', '₱'),
    _Field('sssMscStep', 'MSC step', '₱'),
  ]),
  _Group('PhilHealth', 'Total premium rate; the employee pays half. Salary is clamped to floor/ceiling.', <_Field>[
    _Field('philhealthTotalRate', 'Total premium rate', '%'),
    _Field('philhealthFloor', 'Salary floor', '₱'),
    _Field('philhealthCeiling', 'Salary ceiling', '₱'),
  ]),
  _Group('Pag-IBIG', 'Employee share = rate x salary, capped at the maximum.', <_Field>[
    _Field('pagibigEmployeeRate', 'Employee rate', '%'),
    _Field('pagibigMax', 'Maximum contribution', '₱'),
    _Field('pagibigLowSalaryThreshold', 'Low-salary threshold', '₱'),
    _Field('pagibigLowRate', 'Low-salary rate', '%'),
  ]),
  _Group('Overtime & Night Differential', 'Multipliers are % of the hourly rate. Night differential is the extra % added for 10PM-6AM hours.', <_Field>[
    _Field('ordinaryOtMultiplier', 'Ordinary OT', '%', 'Default 125'),
    _Field('restDayRegularMultiplier', 'Rest day (first 8h)', '%', 'Default 130'),
    _Field('restDayOtMultiplier', 'Rest day OT', '%', 'Default 169'),
    _Field('nightDiffMultiplier', 'Night differential', '%', 'Default 10'),
  ]),
];

/// Removes trailing zeros: 5000.0000 -> 5000, 1.2500 -> 1.25.
String _fmt(double v) {
  final s = v.toStringAsFixed(4);
  return s.replaceFirst(RegExp(r'\.?0+$'), '');
}

class _BracketRow {
  final TextEditingController over;
  final TextEditingController base;
  final TextEditingController rate;

  _BracketRow(TaxBracket b)
      : over = TextEditingController(text: _fmt(b.over)),
        base = TextEditingController(text: _fmt(b.base)),
        rate = TextEditingController(text: _fmt(b.rate * 100));

  _BracketRow.empty()
      : over = TextEditingController(),
        base = TextEditingController(),
        rate = TextEditingController();

  void dispose() {
    over.dispose();
    base.dispose();
    rate.dispose();
  }
}

class PayrollSettingsPage extends StatefulWidget {
  final VoidCallback? onBack;
  const PayrollSettingsPage({super.key, this.onBack});

  @override
  State<PayrollSettingsPage> createState() => _PayrollSettingsPageState();
}

class _PayrollSettingsPageState extends State<PayrollSettingsPage> {
  AdminColors get tc => AdminTheme.getColors(context);

  // ── HR Assistant password (shared with admin_payroll_management_page) ──
  static const String _kHrOverrideCollection = 'settings';
  static const String _kHrOverrideDoc = 'payroll_override';
  static const String _kHrOverrideField = 'hrAssistantPasswordHash';

  final Map<String, TextEditingController> _ctrls = <String, TextEditingController>{
    for (final g in _groups)
      for (final f in g.fields) f.key: TextEditingController(),
  };
  final List<_BracketRow> _rows = <_BracketRow>[];

  bool _loading = true;
  bool _saving = false;
  List<String> _errors = const <String>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final s = await PayrollCalculator.fetchSettings();
    if (!mounted) return;
    setState(() {
      _apply(s);
      _loading = false;
    });
  }

  /// Fills the form from [s]. Old bracket controllers are disposed after the
  /// frame so mounted TextFields never touch a disposed controller.
  void _apply(PayrollSettings s) {
    final map = s.toMap();
    for (final g in _groups) {
      for (final f in g.fields) {
        final v = (map[f.key] as num).toDouble();
        _ctrls[f.key]!.text = _fmt(f.isPercent ? v * 100 : v);
      }
    }
    final old = List<_BracketRow>.from(_rows);
    _rows
      ..clear()
      ..addAll(s.taxBrackets.map((b) => _BracketRow(b)));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final r in old) {
        r.dispose();
      }
    });
    _errors = const <String>[];
  }

  /// Parses the form. Returns null (and sets [_errors]) if anything is invalid.
  PayrollSettings? _collect() {
    final errs = <String>[];
    final vals = <String, double>{};

    for (final g in _groups) {
      for (final f in g.fields) {
        final v = double.tryParse(_ctrls[f.key]!.text.trim());
        if (v == null) {
          errs.add('${g.title} - ${f.label}: enter a valid number');
        } else {
          vals[f.key] = f.isPercent ? v / 100 : v;
        }
      }
    }

    final brackets = <TaxBracket>[];
    for (var i = 0; i < _rows.length; i++) {
      final o = double.tryParse(_rows[i].over.text.trim());
      final b = double.tryParse(_rows[i].base.text.trim());
      final r = double.tryParse(_rows[i].rate.text.trim());
      if (o == null || b == null || r == null) {
        errs.add('Tax bracket ${i + 1}: enter valid numbers');
      } else {
        brackets.add(TaxBracket(o, b, r / 100));
      }
    }

    if (errs.isNotEmpty) {
      setState(() => _errors = errs);
      return null;
    }

    brackets.sort((a, b) => a.over.compareTo(b.over));
    final s = PayrollSettings(
      sssEmployeeRate: vals['sssEmployeeRate']!,
      sssMinMsc: vals['sssMinMsc']!,
      sssMaxMsc: vals['sssMaxMsc']!,
      sssMscStep: vals['sssMscStep']!,
      philhealthTotalRate: vals['philhealthTotalRate']!,
      philhealthFloor: vals['philhealthFloor']!,
      philhealthCeiling: vals['philhealthCeiling']!,
      pagibigEmployeeRate: vals['pagibigEmployeeRate']!,
      pagibigMax: vals['pagibigMax']!,
      pagibigLowSalaryThreshold: vals['pagibigLowSalaryThreshold']!,
      pagibigLowRate: vals['pagibigLowRate']!,
      ordinaryOtMultiplier: vals['ordinaryOtMultiplier']!,
      restDayRegularMultiplier: vals['restDayRegularMultiplier']!,
      restDayOtMultiplier: vals['restDayOtMultiplier']!,
      nightDiffMultiplier: vals['nightDiffMultiplier']!,
      taxBrackets: brackets,
    );

    final problems = s.validate();
    if (problems.isNotEmpty) {
      setState(() => _errors = problems);
      return null;
    }
    setState(() => _errors = const <String>[]);
    return s;
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? tc.red : tc.orange),
    );
  }

  // ───────────────────── HR Assistant password helpers ─────────────────────

  String _sha256Hex(String input) =>
      sha256.convert(utf8.encode(input)).toString();

  Future<String?> _getStoredHrPasswordHash() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection(_kHrOverrideCollection)
          .doc(_kHrOverrideDoc)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 8));
      final raw = doc.data()?[_kHrOverrideField];
      if (raw is String && raw.isNotEmpty) return raw;
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ [HrOverride] fetch hash failed: $e');
      return null;
    }
  }

  Future<void> _setHrPassword(String plainPassword) async {
    final hash = _sha256Hex(plainPassword);
    await FirebaseFirestore.instance
        .collection(_kHrOverrideCollection)
        .doc(_kHrOverrideDoc)
        .set({
      _kHrOverrideField: hash,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': FirebaseAuth.instance.currentUser?.uid,
    }, SetOptions(merge: true));
  }

  Future<bool> _verifyHrPassword(String plainPassword) async {
    if (plainPassword.isEmpty) return false;
    final storedHash = await _getStoredHrPasswordHash();
    if (storedHash == null || storedHash.isEmpty) return false;
    return _sha256Hex(plainPassword) == storedHash;
  }

  Future<bool?> _showOverridePasswordDialog({required bool isSetup}) async {
    if (!mounted) return false;
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _OverridePasswordDialog(
        isSetup: isSetup,
        onSetup: _setHrPassword,
        onVerify: _verifyHrPassword,
      ),
    );
  }

  // ─────────────────────────────── Save flow ────────────────────────────────

  Future<void> _save() async {
    if (_saving) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _toast('Session expired. Please sign in again.', error: true);
      return;
    }
    final s = _collect();
    if (s == null) return;

    // 🔐 Require HR Assistant password before we touch Firestore.
    bool isSetup = false;
    try {
      final storedHash = await _getStoredHrPasswordHash();
      isSetup = storedHash == null || storedHash.isEmpty;
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ [PayrollSettings] hash lookup failed: $e');
      _toast('Could not verify HR Assistant password. Please try again.',
          error: true);
      return;
    }

    if (!mounted) return;
    final approved = await _showOverridePasswordDialog(isSetup: isSetup);
    if (approved != true) {
      // User cancelled or verification failed — do not save.
      return;
    }

    setState(() => _saving = true);
    try {
      await PayrollCalculator.saveSettings(s, actorUid: user.uid)
          .timeout(const Duration(seconds: 12));
      try {
        await FirebaseFirestore.instance.collection('security_events').add({
          'type': 'admin_action',
          'action': 'payroll_settings_update',
          'targetId': 'settings/payroll',
          'targetType': 'payroll_settings',
          'actorUid': user.uid,
          'metadata': {
            ...s.toMap(),
            'hr_assistant_authorized': true,
            'password_was_first_setup': isSetup,
          },
          'timestamp': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        if (kDebugMode) debugPrint('payroll settings audit failed: $e');
      }
      _toast('Payroll settings saved. New rates apply on the next computation.');
    } catch (e) {
      if (kDebugMode) debugPrint('payroll settings save failed: $e');
      _toast(kDebugMode ? '$e' : 'Could not save settings. Please try again.',
          error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _resetDefaults() {
    setState(() => _apply(PayrollSettings.fallback));
  }

  InputDecoration _deco(String label, {String? prefix, String? suffix, String? helper}) {
    OutlineInputBorder b(Color c) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: c),
    );
    return InputDecoration(
      labelText: label,
      helperText: helper,
      prefixText: prefix,
      suffixText: suffix,
      isDense: true,
      filled: true,
      fillColor: tc.surface,
      labelStyle: TextStyle(color: tc.muted, fontSize: 12),
      border: b(tc.border),
      enabledBorder: b(tc.border),
      focusedBorder: b(tc.orange),
    );
  }

  Widget _numField(TextEditingController c, String label,
      {String? prefix, String? suffix, String? helper, double width = 230}) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: TextStyle(color: tc.text, fontSize: 14),
        decoration: _deco(label, prefix: prefix, suffix: suffix, helper: helper),
      ),
    );
  }

  Widget _card({required String title, String? note, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tc.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, color: tc.text)),
          if (note != null) ...[
            const SizedBox(height: 4),
            Text(note, style: TextStyle(fontSize: 12, color: tc.muted)),
          ],
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _groupCard(_Group g) {
    return _card(
      title: g.title,
      note: g.note,
      child: Wrap(
        spacing: 12,
        runSpacing: 16,
        children: [
          for (final f in g.fields)
            _numField(
              _ctrls[f.key]!,
              f.label,
              prefix: f.unit == '₱' ? '₱ ' : null,
              suffix: f.isPercent ? '%' : null,
              helper: f.help.isEmpty ? null : f.help,
            ),
        ],
      ),
    );
  }

  Widget _bracketsCard() {
    return _card(
      title: 'BIR Withholding Tax (monthly)',
      note: 'Tax = base + (taxable income - "over") x rate, using the highest bracket whose "over" is below the taxable income.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < _rows.length; i++)
            Padding(
              key: ObjectKey(_rows[i]),
              padding: const EdgeInsets.only(bottom: 12),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _numField(_rows[i].over, 'Over', prefix: '₱ ', width: 180),
                  _numField(_rows[i].base, 'Base tax', prefix: '₱ ', width: 180),
                  _numField(_rows[i].rate, 'Rate on excess', suffix: '%', width: 150),
                  IconButton(
                    tooltip: 'Remove bracket',
                    icon: Icon(Icons.delete_outline_rounded, color: tc.red),
                    onPressed: _rows.length <= 1
                        ? null
                        : () {
                      final removed = _rows.removeAt(i);
                      setState(() {});
                      WidgetsBinding.instance
                          .addPostFrameCallback((_) => removed.dispose());
                    },
                  ),
                ],
              ),
            ),
          TextButton.icon(
            onPressed: () => setState(() => _rows.add(_BracketRow.empty())),
            icon: Icon(Icons.add_rounded, size: 18, color: tc.orange),
            label: Text('Add bracket', style: TextStyle(color: tc.orange)),
          ),
        ],
      ),
    );
  }

  Widget _errorBox() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tc.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tc.red.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in _errors)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text('• $e', style: TextStyle(color: tc.red, fontSize: 12)),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: tc.background,
        body: Center(child: CircularProgressIndicator(color: tc.orange)),
      );
    }

    return Scaffold(
      backgroundColor: tc.background,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.onBack != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: widget.onBack,
                      icon: Icon(Icons.arrow_back_rounded, size: 18, color: tc.orange),
                      label: Text('Back', style: TextStyle(color: tc.orange)),
                    ),
                  ),
                Text('Payroll Rates',
                    style: TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w800, color: tc.text)),
                const SizedBox(height: 4),
                Text(
                  'Changes apply to the next payroll computation. Payslips already downloaded are not recalculated.',
                  style: TextStyle(fontSize: 13, color: tc.muted),
                ),
                const SizedBox(height: 20),
                for (final g in _groups) ...[
                  _groupCard(g),
                  const SizedBox(height: 16),
                ],
                _bracketsCard(),
                const SizedBox(height: 16),
                if (_errors.isNotEmpty) ...[
                  _errorBox(),
                  const SizedBox(height: 16),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: _saving ? null : _resetDefaults,
                      child: const Text('Reset to defaults'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save_rounded, size: 16),
                      label: Text(_saving ? 'Saving...' : 'Save rates'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: tc.orange,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// HR Assistant Override Password Dialog
// (Copied from admin_payroll_management_page.dart so both screens share the
//  same settings/payroll_override.hrAssistantPasswordHash.)
// ═══════════════════════════════════════════════════════════════════════════

class _OverridePasswordDialog extends StatefulWidget {
  final bool isSetup;
  final Future<void> Function(String password) onSetup;
  final Future<bool> Function(String password) onVerify;

  const _OverridePasswordDialog({
    required this.isSetup,
    required this.onSetup,
    required this.onVerify,
  });

  @override
  State<_OverridePasswordDialog> createState() =>
      _OverridePasswordDialogState();
}

class _OverridePasswordDialogState extends State<_OverridePasswordDialog> {
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _verifying = false;
  String? _error;
  bool _obscure = true;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_verifying) return;
    setState(() {
      _error = null;
    });

    final pwd = _passwordCtrl.text;
    if (pwd.isEmpty) {
      setState(() => _error = 'Password is required.');
      return;
    }
    if (pwd.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }

    if (widget.isSetup) {
      if (pwd != _confirmCtrl.text) {
        setState(() => _error = 'Passwords do not match.');
        return;
      }
    }

    setState(() => _verifying = true);
    try {
      if (widget.isSetup) {
        await widget.onSetup(pwd);
        if (!mounted) return;
        Navigator.pop(context, true);
      } else {
        final ok = await widget.onVerify(pwd);
        if (!mounted) return;
        if (ok) {
          Navigator.pop(context, true);
        } else {
          setState(() {
            _verifying = false;
            _error = 'Incorrect HR Assistant password.';
            _passwordCtrl.clear();
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _error = 'Something went wrong. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tc = AdminTheme.getColors(context);
    final title = widget.isSetup
        ? 'Set HR Assistant Password'
        : 'HR Assistant Override Required';
    final subtitle = widget.isSetup
        ? 'First-time setup. This password will authorize future payroll rate changes. Share it only with HR Assistants.'
        : 'An HR Assistant must authorize this payroll rate change before it can be saved.';

    return AlertDialog(
      backgroundColor: tc.card,
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: tc.orange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              widget.isSetup
                  ? Icons.lock_person_rounded
                  : Icons.shield_rounded,
              color: tc.orange,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(title,
                style: TextStyle(
                    color: tc.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w800)),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(subtitle,
                style: TextStyle(
                    color: tc.muted, fontSize: 12, height: 1.5)),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordCtrl,
              obscureText: _obscure,
              enabled: !_verifying,
              autofocus: true,
              onSubmitted: (_) => _submit(),
              style: TextStyle(color: tc.text, fontSize: 14),
              cursorColor: tc.orange,
              decoration: InputDecoration(
                hintText: widget.isSetup
                    ? 'New HR Assistant password'
                    : 'Enter HR Assistant password',
                hintStyle: TextStyle(color: tc.muted, fontSize: 13),
                prefixIcon:
                Icon(Icons.key_rounded, color: tc.muted, size: 18),
                suffixIcon: IconButton(
                  icon: Icon(
                      _obscure
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded,
                      size: 18,
                      color: tc.muted),
                  onPressed: () =>
                      setState(() => _obscure = !_obscure),
                ),
                filled: true,
                fillColor: tc.surface,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 12),
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
                  borderSide: BorderSide(color: tc.orange, width: 1.5),
                ),
              ),
            ),
            if (widget.isSetup) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _confirmCtrl,
                obscureText: _obscure,
                enabled: !_verifying,
                onSubmitted: (_) => _submit(),
                style: TextStyle(color: tc.text, fontSize: 14),
                cursorColor: tc.orange,
                decoration: InputDecoration(
                  hintText: 'Confirm password',
                  hintStyle: TextStyle(color: tc.muted, fontSize: 13),
                  prefixIcon: Icon(Icons.check_circle_outline_rounded,
                      color: tc.muted, size: 18),
                  filled: true,
                  fillColor: tc.surface,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
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
                    borderSide: BorderSide(color: tc.orange, width: 1.5),
                  ),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: tc.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: tc.red.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline_rounded,
                        color: tc.red, size: 14),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(_error!,
                          style: TextStyle(
                              color: tc.red,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600)),
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
          onPressed: _verifying ? null : () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: tc.muted)),
        ),
        ElevatedButton.icon(
          onPressed: _verifying ? null : _submit,
          icon: _verifying
              ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.check_circle_rounded, size: 16),
          label: Text(
              _verifying
                  ? 'Verifying...'
                  : (widget.isSetup ? 'Set & Authorize' : 'Authorize'),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(
            backgroundColor: tc.orange,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
            padding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
        ),
      ],
    );
  }
}