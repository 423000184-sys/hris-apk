// lib/services/attendance_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'geofence_service.dart';
import 'admin_notification_service.dart';
import 'device_info_service.dart';

/// Latest attendance state read from Firestore, so every device shows the same thing.
class ClockStatus {
  final bool isClockedIn;
  final String? deviceModel;
  final String? date;

  const ClockStatus({required this.isClockedIn, this.deviceModel, this.date});
}

class AttendanceService {
  AttendanceService._();
  static final instance = AttendanceService._();

  final _col = FirebaseFirestore.instance.collection('attendance_logs');

  /// Reads the latest record for this employee.
  /// Needs a composite index: employeeId (asc) + timestamp (desc).
  /// Call this when the attendance screen loads.
  Future<ClockStatus> getClockStatus(String employeeId) async {
    final snap = await _col
        .where('employeeId', isEqualTo: employeeId)
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return const ClockStatus(isClockedIn: false);

    final data = snap.docs.first.data();
    return ClockStatus(
      isClockedIn: data['type'] == 'clock_in',
      deviceModel: data['device_model'] as String?,
      date: data['date'] as String?,
    );
  }

  /// Returns an error message if this device is not the active session device,
  /// or null if OK. Fails open on offline/errors so employees are never blocked.
  Future<String?> _checkActiveDevice(String deviceId) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return null;

      final snap = await FirebaseFirestore.instance
          .collection('active_sessions')
          .doc(uid)
          .get();

      final activeId = snap.data()?['device_id'] as String?;
      if (snap.exists && activeId != null && activeId != deviceId) {
        final model = snap.data()?['device_model'] ?? 'ibang device';
        return 'Ang active device mo ay $model. Doon ka mag-clock in/out.';
      }
    } catch (e) {
      debugPrint('[Attendance] Device check skipped: $e');
    }
    return null;
  }

  Future<AttendanceResult> clockIn({
    required String employeeId,
    required String employeeName,
    bool isWFH = false,
    bool isDriver = false,
    double? faceMatchPercent,
  }) async {
    final deviceId = await DeviceInfoService.instance.getUniqueDeviceId();
    final deviceModel = await DeviceInfoService.instance.getDeviceModel();
    final now = DateTime.now();
    final dateStr = DateFormat('yyyy-MM-dd').format(now);

    final deviceError = await _checkActiveDevice(deviceId);
    if (deviceError != null) {
      return AttendanceResult(success: false, zone: 'blocked', message: deviceError);
    }

    // Block duplicate clock-in for today. A clock-in left open from a
    // previous day does not block today's clock-in.
    try {
      final status = await getClockStatus(employeeId);
      if (status.isClockedIn && status.date == dateStr) {
        return AttendanceResult(
          success: false,
          zone: 'blocked',
          message:
          'Naka-clock in ka na${status.deviceModel != null ? ' sa ${status.deviceModel}' : ''}.',
        );
      }
    } catch (e) {
      debugPrint('[Attendance] Status check skipped: $e');
    }

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

    if (zone == 'outside') {
      await AdminNotificationService.instance.notifyGeofenceAlert(
        employeeId: employeeId,
        employeeName: employeeName,
        timeStr: DateFormat('hh:mm a').format(now),
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

    await _col.add({
      'employeeId': employeeId,
      'employee_id': employeeId,
      'employeeName': employeeName,
      'type': 'clock_in',
      'zone': zone,
      'date': dateStr,
      'timestamp': FieldValue.serverTimestamp(),
      'distanceMeters': geo.distanceMeters,
      'faceMatchPercent': faceMatchPercent,
      'wfh': isWFH,
      'driver': isDriver,
      'device_id': deviceId,
      'device_model': deviceModel,
    });

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
        zoneType: zone,
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

  Future<AttendanceResult> clockOut({
    required String employeeId,
    required String employeeName,
    bool isWFH = false,
    bool isDriver = false,
    double? faceMatchPercent,
  }) async {
    final deviceId = await DeviceInfoService.instance.getUniqueDeviceId();
    final deviceModel = await DeviceInfoService.instance.getDeviceModel();
    final now = DateTime.now();
    final dateStr = DateFormat('yyyy-MM-dd').format(now);

    final deviceError = await _checkActiveDevice(deviceId);
    if (deviceError != null) {
      return AttendanceResult(success: false, zone: 'blocked', message: deviceError);
    }

    // Block clock-out when there is nothing to clock out from.
    try {
      final status = await getClockStatus(employeeId);
      if (!status.isClockedIn) {
        return const AttendanceResult(
          success: false,
          zone: 'blocked',
          message: 'Wala kang aktibong clock in.',
        );
      }
    } catch (e) {
      debugPrint('[Attendance] Status check skipped: $e');
    }

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

    await _col.add({
      'employeeId': employeeId,
      'employee_id': employeeId,
      'employeeName': employeeName,
      'type': 'clock_out',
      'zone': zone,
      'date': dateStr,
      'timestamp': FieldValue.serverTimestamp(),
      'distanceMeters': geo.distanceMeters,
      'wfh': isWFH,
      'driver': isDriver,
      'device_id': deviceId,
      'device_model': deviceModel,
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