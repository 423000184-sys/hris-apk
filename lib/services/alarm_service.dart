import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';

class AlarmService {
  AlarmService._();
  static final AlarmService instance = AlarmService._();

  bool _isRinging = false;
  bool get isRinging => _isRinging;

  /// Starts the alarm sound and vibration
  Future<void> startAlarm() async {
    if (_isRinging) return;
    _isRinging = true;
    
    // In version 4.0.0+, play and stop are instance methods.
    FlutterRingtonePlayer().play(
      android: AndroidSounds.alarm,
      ios: IosSounds.alarm,
      looping: true,
      volume: 1.0,
      asAlarm: true,
    );

    _ringLoop();
  }

  /// Stops the alarm
  void stopAlarm() {
    _isRinging = false;
    FlutterRingtonePlayer().stop();
  }

  void _ringLoop() async {
    while (_isRinging) {
      // Periodic vibration alongside the sound
      HapticFeedback.vibrate();
      await Future.delayed(const Duration(milliseconds: 500));
      HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 1000));
    }
  }
}
