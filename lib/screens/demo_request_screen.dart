// lib/screens/demo_request_screen.dart
// v2.1: 🌓 Follows app theme (light/dark) — no hardcoded dark background.
//       🎭 Email-gated demo request flow (unchanged).
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/demo_mode_service.dart';
import '../services/demo_request_service.dart';
import 'login_screen.dart';

const _orange = Color(0xFFFF6900);

enum _View {
  loading,
  form,
  submitting,
  sendingToAdmin,
  pending,
  codeEntry,
  rejected,
  expired,
  emailFailed,
  error,
}

// ═══════════════════════════════════════════════════════════════════════════
// THEME COLORS — mirrors landing screen approach
// ═══════════════════════════════════════════════════════════════════════════
class _DemoTheme {
  final bool isDark;
  const _DemoTheme(this.isDark);

  Color get scaffoldBg =>
      isDark ? const Color(0xFF1A0F05) : const Color(0xFFFFF2EA);
  Color get appBarBg =>
      isDark ? const Color(0xFF0C0C0E) : Colors.white;
  Color get appBarText =>
      isDark ? Colors.white : const Color(0xFF000000);

  Color get cardBg => isDark ? const Color(0xFF1A1A21) : Colors.white;
  Color get fieldBg => isDark ? const Color(0xFF1A1A21) : Colors.white;
  Color get surfaceBg =>
      isDark ? const Color(0xFF27272A) : const Color(0xFFF4F4F5);

  Color get titleText =>
      isDark ? Colors.white : const Color(0xFF000000);
  Color get bodyText =>
      isDark ? const Color(0xFFE4E4E7) : const Color(0xFF27272A);
  Color get mutedText =>
      isDark ? const Color(0xFF9F9FA9) : const Color(0xFF71717A);
  Color get hintText =>
      isDark ? const Color(0xFF52525B) : const Color(0xFFA1A1AA);

  Color get border => isDark
      ? Colors.white.withValues(alpha: 0.08)
      : const Color(0xFFE4E4E7);

  Color get fieldBorder => isDark
      ? Colors.white.withValues(alpha: 0.10)
      : const Color(0xFFD4D4D8);

  Color get divider =>
      isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF4F4F5);
}

class DemoRequestScreen extends StatefulWidget {
  const DemoRequestScreen({super.key});
  @override
  State<DemoRequestScreen> createState() => _DemoRequestScreenState();
}

class _DemoRequestScreenState extends State<DemoRequestScreen> {
  _View _view = _View.loading;
  String _errorMsg = '';

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _companyCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  String? _requestId;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _watchSub;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final existing = await DemoRequestService.instance.getMyRequest();
      if (!mounted) return;
      if (existing == null) {
        setState(() => _view = _View.form);
        return;
      }
      _requestId = existing.id;
      final status = (existing.data()?['status'] ?? '').toString();

      switch (status) {
        case 'sending':
          setState(() => _view = _View.sendingToAdmin);
          _watchStatus();
          break;
        case 'pending':
          setState(() => _view = _View.pending);
          _watchStatus();
          break;
        case 'email_failed':
          setState(() => _view = _View.emailFailed);
          break;
        case 'approved':
          final exp = existing.data()?['expiresAt'];
          if (exp is Timestamp &&
              exp.toDate().isBefore(DateTime.now())) {
            setState(() => _view = _View.expired);
            return;
          }
          setState(() => _view = _View.codeEntry);
          _watchStatus();
          break;
        case 'rejected':
          setState(() => _view = _View.rejected);
          break;
        case 'expired':
        case 'exhausted':
          setState(() => _view = _View.expired);
          break;
        default:
          setState(() => _view = _View.form);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _view = _View.error;
        _errorMsg = e.toString();
      });
    }
  }

  void _watchStatus() {
    if (_requestId == null) return;
    _watchSub?.cancel();
    _watchSub =
        DemoRequestService.instance.watchRequest(_requestId!).listen((snap) {
          if (!mounted || !snap.exists) return;
          final status = (snap.data()?['status'] ?? '').toString();

          if (status == 'pending' && _view == _View.sendingToAdmin) {
            setState(() => _view = _View.pending);
            return;
          }
          if (status == 'email_failed' && _view == _View.sendingToAdmin) {
            setState(() => _view = _View.emailFailed);
            return;
          }
          if (status == 'approved' && _view == _View.pending) {
            setState(() => _view = _View.codeEntry);
            return;
          }
          if (status == 'rejected') {
            setState(() => _view = _View.rejected);
          } else if (status == 'expired' || status == 'exhausted') {
            setState(() => _view = _View.expired);
          }
        });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _view = _View.submitting;
      _busy = true;
    });
    try {
      final id = await DemoRequestService.instance.submitRequest(
        name: _nameCtrl.text,
        email: _emailCtrl.text,
        company: _companyCtrl.text,
        phone: _phoneCtrl.text,
        reason: _reasonCtrl.text,
      );
      _requestId = id;
      if (!mounted) return;
      setState(() {
        _view = _View.sendingToAdmin;
        _busy = false;
      });
      _watchStatus();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _view = _View.form;
        _busy = false;
      });
      _snack('Failed to submit: $e');
    }
  }

  Future<void> _retryEmail() async {
    if (_requestId == null) return;
    setState(() => _busy = true);
    try {
      await DemoRequestService.instance.retryEmailNotification(_requestId!);
      if (!mounted) return;
      setState(() {
        _view = _View.sendingToAdmin;
        _busy = false;
      });
      _watchStatus();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('Retry failed: $e');
    }
  }

  Future<void> _redeem() async {
    if (_requestId == null) return;
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.length < 4) {
      _snack('Enter the 6-character access code.');
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await DemoRequestService.instance.redeemCode(
        requestId: _requestId!,
        code: code,
      );
      if (!result.success) {
        if (!mounted) return;
        setState(() => _busy = false);
        _snack(result.message);
        return;
      }

      await DemoModeService.instance.startDemoSession();
      if (!mounted) return;
      await Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const LoginScreen(),
          settings: const RouteSettings(name: '/login-demo'),
        ),
            (_) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('Redeem failed: $e');
    }
  }

  Future<void> _resetRequest() async {
    await DemoRequestService.instance.clearMyRequest();
    if (!mounted) return;
    setState(() {
      _view = _View.form;
      _requestId = null;
      _codeCtrl.clear();
    });
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10)),
      ));
  }

  @override
  void dispose() {
    _watchSub?.cancel();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _companyCtrl.dispose();
    _phoneCtrl.dispose();
    _reasonCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final t = _DemoTheme(isDark);

    return Scaffold(
      backgroundColor: t.scaffoldBg,
      appBar: AppBar(
        backgroundColor: t.appBarBg,
        foregroundColor: t.appBarText,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: t.divider),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: t.appBarText),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Demo Access',
          style: TextStyle(
            color: t.appBarText,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: _buildBody(t),
        ),
      ),
    );
  }

  Widget _buildBody(_DemoTheme t) {
    switch (_view) {
      case _View.loading:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 80),
          child: Center(
              child: CircularProgressIndicator(color: _orange)),
        );
      case _View.form:
        return _buildForm(t);
      case _View.submitting:
        return _buildCentered(
          t,
          icon: Icons.cloud_upload_rounded,
          title: 'Submitting…',
          message: 'Saving your request.',
        );
      case _View.sendingToAdmin:
        return _buildCentered(
          t,
          icon: Icons.outgoing_mail,
          title: 'Notifying Admin…',
          message:
          'Sending your request to the admin\'s inbox. This may take a few seconds.',
          accentColor: Colors.blue,
          showLoader: true,
        );
      case _View.pending:
        return _buildPending(t);
      case _View.codeEntry:
        return _buildCodeEntry(t);
      case _View.rejected:
        return _buildRejected(t);
      case _View.expired:
        return _buildExpired(t);
      case _View.emailFailed:
        return _buildEmailFailed(t);
      case _View.error:
        return _buildCentered(
          t,
          icon: Icons.error_outline_rounded,
          title: 'Something went wrong',
          message: _errorMsg,
          actionLabel: 'Retry',
          onAction: () {
            setState(() => _view = _View.loading);
            _bootstrap();
          },
        );
    }
  }

  Widget _buildForm(_DemoTheme t) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: _orange,
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.science_rounded,
                color: Colors.black, size: 28),
          ),
          const SizedBox(height: 16),
          Text(
            'Request Demo Access',
            style: TextStyle(
              color: t.titleText,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Fill up this form. The admin will review and email your access code.',
            style: TextStyle(color: t.mutedText, fontSize: 13),
          ),
          const SizedBox(height: 24),
          _field(t, _nameCtrl, 'Full Name', Icons.person_rounded,
              required: true),
          const SizedBox(height: 12),
          _field(t, _emailCtrl, 'Email Address', Icons.email_rounded,
              required: true, isEmail: true),
          const SizedBox(height: 12),
          _field(t, _companyCtrl, 'Company (optional)',
              Icons.business_rounded),
          const SizedBox(height: 12),
          _field(t, _phoneCtrl, 'Phone (optional)', Icons.phone_rounded,
              keyboardType: TextInputType.phone),
          const SizedBox(height: 12),
          _field(t, _reasonCtrl, 'Reason for demo (optional)',
              Icons.description_rounded, maxLines: 3),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _busy ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: _orange,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: const Text('Submit Request',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(
      _DemoTheme t,
      TextEditingController ctrl,
      String label,
      IconData icon, {
        bool required = false,
        bool isEmail = false,
        int maxLines = 1,
        TextInputType? keyboardType,
      }) {
    return TextFormField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: TextStyle(color: t.bodyText),
      cursorColor: _orange,
      validator: required
          ? (v) {
        if (v == null || v.trim().isEmpty) return 'Required';
        if (isEmail &&
            !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                .hasMatch(v.trim())) {
          return 'Invalid email';
        }
        return null;
      }
          : null,
      decoration: InputDecoration(
        labelText: label + (required ? ' *' : ''),
        labelStyle: TextStyle(color: t.mutedText, fontSize: 13),
        floatingLabelStyle: const TextStyle(color: _orange, fontSize: 13),
        prefixIcon: Icon(icon, color: t.mutedText, size: 20),
        filled: true,
        fillColor: t.fieldBg,
        hintStyle: TextStyle(color: t.hintText),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: t.fieldBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: t.fieldBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _orange, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 1.5),
        ),
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      ),
    );
  }

  Widget _buildPending(_DemoTheme t) {
    return Column(
      children: [
        _buildCentered(
          t,
          icon: Icons.hourglass_top_rounded,
          title: 'Waiting for Approval',
          message:
          'Your request has been delivered to the admin. You will receive an email once approved with your access code.',
          accentColor: Colors.amber,
          showLoader: true,
        ),
        const SizedBox(height: 20),
        TextButton(
          onPressed: _resetRequest,
          child: Text('Cancel request',
              style: TextStyle(color: t.mutedText)),
        ),
      ],
    );
  }

  Widget _buildEmailFailed(_DemoTheme t) {
    return Column(
      children: [
        _buildCentered(
          t,
          icon: Icons.wifi_off_rounded,
          title: 'Could Not Reach Admin',
          message:
          'We couldn\'t deliver your request to the admin\'s email. Please check your connection and try again.',
          accentColor: Colors.red,
          actionLabel: _busy ? 'Retrying…' : 'Retry Now',
          onAction: _busy ? null : _retryEmail,
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _resetRequest,
          child: Text('Cancel and start over',
              style: TextStyle(color: t.mutedText)),
        ),
      ],
    );
  }

  Widget _buildCodeEntry(_DemoTheme t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: Colors.green.shade700,
            borderRadius: BorderRadius.circular(16),
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.check_circle_rounded,
              color: Colors.white, size: 30),
        ),
        const SizedBox(height: 16),
        Text(
          'Access Approved!',
          style: TextStyle(
              color: t.titleText,
              fontSize: 22,
              fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          'Enter the access code we sent to your email.',
          style: TextStyle(color: t.mutedText, fontSize: 13),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _codeCtrl,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: t.bodyText,
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: 6,
          ),
          cursorColor: _orange,
          textCapitalization: TextCapitalization.characters,
          maxLength: 6,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
            UpperCaseTextFormatter(),
          ],
          decoration: InputDecoration(
            counterText: '',
            hintText: 'ABC123',
            hintStyle: TextStyle(
              color: t.hintText,
              letterSpacing: 6,
              fontWeight: FontWeight.w700,
            ),
            filled: true,
            fillColor: t.fieldBg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: t.fieldBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: t.fieldBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _orange, width: 2),
            ),
            contentPadding:
            const EdgeInsets.symmetric(vertical: 22, horizontal: 14),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _busy ? null : _redeem,
            style: ElevatedButton.styleFrom(
              backgroundColor: _orange,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            child: _busy
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  color: Colors.black, strokeWidth: 2),
            )
                : const Text('Unlock Demo',
                style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ),
      ],
    );
  }

  Widget _buildRejected(_DemoTheme t) {
    return _buildCentered(
      t,
      icon: Icons.cancel_rounded,
      title: 'Request Rejected',
      message:
      'Your demo access request was not approved. You can submit a new request.',
      accentColor: Colors.red,
      actionLabel: 'Submit New Request',
      onAction: _resetRequest,
    );
  }

  Widget _buildExpired(_DemoTheme t) {
    return _buildCentered(
      t,
      icon: Icons.timer_off_rounded,
      title: 'Access Expired',
      message:
      'Your demo access has expired or has been used. Submit a new request.',
      accentColor: Colors.orange,
      actionLabel: 'Request Again',
      onAction: _resetRequest,
    );
  }

  Widget _buildCentered(
      _DemoTheme t, {
        required IconData icon,
        required String title,
        required String message,
        Color accentColor = _orange,
        bool showLoader = false,
        String? actionLabel,
        VoidCallback? onAction,
      }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: accentColor, size: 36),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: t.titleText,
                fontSize: 20,
                fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: t.mutedText, fontSize: 13, height: 1.5),
          ),
          if (showLoader) ...[
            const SizedBox(height: 24),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  color: _orange, strokeWidth: 2.5),
            ),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: onAction,
              style: ElevatedButton.styleFrom(
                backgroundColor: _orange,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: Text(actionLabel,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ],
      ),
    );
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}