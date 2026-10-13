// lib/services/attendance_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'geofence_service.dart';
import 'admin_notification_service.dart';

class AttendanceService {
  AttendanceService._();
  static final instance = AttendanceService._();

  final _col = FirebaseFirestore.instance.collection('attendance');

  /// ═══════════════════════════════════════════════════════════════
  /// CLOCK IN — geofence-aware + notifies admin
  /// ═══════════════════════════════════════════════════════════════
  Future<AttendanceResult> clockIn({
    required String employeeId,
    required String employeeName,
    bool isWFH = false,
    bool isDriver = false,
    double? faceMatchPercent,
  }) async {
    // 1) Geofence check
    final geo = await GeofenceService.instance.checkGeofence();

    // 2) Determine zone
    String zone;
    if (isWFH) {
      zone = 'wfh';
    } else if (isDriver) {
      zone = 'driver';
    } else if (geo.isInside) {
      zone = 'inside';
    } else {
      zone = 'outside';
    }

    // 3) Block clock-in kung outside at hindi WFH/driver
    if (zone == 'outside') {
      // 🔔 Notify admin agad (kahit blocked)
      await AdminNotificationService.instance.notifyGeofenceAlert(
        employeeId: employeeId,
        employeeName: employeeName,
        timeStr: DateFormat('hh:mm a').format(DateTime.now()),
        distanceMeters: geo.distanceMeters ?? 0,
        action: 'clock_in',
      );
      return AttendanceResult(
        success: false,
        zone: zone,
        message: geo.message,
        distanceMeters: geo.distanceMeters,
      );
    }

    // 4) Save attendance record
    final now = DateTime.now();
    await _col.add({
      'employeeId': employeeId,
      'employeeName': employeeName,
      'type': 'clock_in',
      'zone': zone,
      'timestamp': FieldValue.serverTimestamp(),
      'distanceMeters': geo.distanceMeters,
      'faceMatchPercent': faceMatchPercent,
      'wfh': isWFH,
      'driver': isDriver,
    });

    // 5) 🔔 Notify admin
    final timeStr = DateFormat('hh:mm a').format(now);
    if (isWFH) {
      await AdminNotificationService.instance.notifyWFHClockIn(
        employeeId: employeeId,
        employeeName: employeeName,
        timeStr: timeStr,
        faceMatchPercent: faceMatchPercent,
      );
    } else if (isDriver) {
      await AdminNotificationService.instance.notifyDriverClockIn(
        employeeId: employeeId,
        employeeName: employeeName,
        timeStr: timeStr,
        faceMatchPercent: faceMatchPercent,
      );
    } else {
      await AdminNotificationService.instance.notifyClockIn(
        employeeId: employeeId,
        employeeName: employeeName,
        timeStr: timeStr,
        wfh: false,
        inRange: true,
        zoneType: zone,                       // 👈 'inside'
        faceMatchPercent: faceMatchPercent,
        distanceMeters: geo.distanceMeters,
      );
    }

    return AttendanceResult(
      success: true,
      zone: zone,
      message: 'Clocked in ($zone)',
      distanceMeters: geo.distanceMeters,
    );
  }

  /// ═══════════════════════════════════════════════════════════════
  /// CLOCK OUT — geofence-aware + notifies admin
  /// ═══════════════════════════════════════════════════════════════
  Future<AttendanceResult> clockOut({
    required String employeeId,
    required String employeeName,
    bool isWFH = false,
    bool isDriver = false,
    double? faceMatchPercent,
  }) async {
    final geo = await GeofenceService.instance.checkGeofence();

    String zone;
    if (isWFH) {
      zone = 'wfh';
    } else if (isDriver) {
      zone = 'driver';
    } else if (geo.isInside) {
      zone = 'inside';
    } else {
      zone = 'outside';
    }

    // Clock out is more lenient — pwede outside (nakaalis na)
    final now = DateTime.now();
    await _col.add({
      'employeeId': employeeId,
      'employeeName': employeeName,
      'type': 'clock_out',
      'zone': zone,
      'timestamp': FieldValue.serverTimestamp(),
      'distanceMeters': geo.distanceMeters,
      'wfh': isWFH,
      'driver': isDriver,
    });

    final timeStr = DateFormat('hh:mm a').format(now);
    if (isWFH) {
      await AdminNotificationService.instance.notifyWFHClockOut(
        employeeId: employeeId,
        employeeName: employeeName,
        timeStr: timeStr,
      );
    } else if (isDriver) {
      await AdminNotificationService.instance.notifyDriverClockOut(
        employeeId: employeeId,
        employeeName: employeeName,
        timeStr: timeStr,
      );
    } else {
      await AdminNotificationService.instance.notifyClockOut(
        employeeId: employeeId,
        employeeName: employeeName,
        timeStr: timeStr,
        wfh: false,
        inRange: geo.isInside,
        zoneType: zone,
        distanceMeters: geo.distanceMeters,
      );
    }

    return AttendanceResult(
      success: true,
      zone: zone,
      message: 'Clocked out ($zone)',
      distanceMeters: geo.distanceMeters,
    );
  }
}

class AttendanceResult {
  final bool success;
  final String zone;
  final String message;
  final double? distanceMeters;

  const AttendanceResult({
    required this.success,
    required this.zone,
    required this.message,
    this.distanceMeters,
  });
}