// lib/security/idle_timeout.dart
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Mixin for admin pages — auto sign-out after inactivity.
mixin IdleTimeoutMixin<T extends StatefulWidget> on State<T> {
  Timer? _idleTimer;
  static const Duration _timeout = Duration(minutes: 10);

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_timeout, () async {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _resetIdleTimer();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    super.dispose();
  }

  Widget buildWithIdleDetection() {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _resetIdleTimer(),
      onPointerMove: (_) => _resetIdleTimer(),
      child: buildContent(),
    );
  }

  /// Subclass must implement this.
  Widget buildContent();
}