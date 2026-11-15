// lib/services/attendance_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'geofence_service.dart';
import 'field_proof_service.dart'; // <-- NEW IMPORT
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

    try {
      final status = await getClockStatus(employeeId);
      if (status.isClockedIn && status.date == dateStr) {
        return AttendanceResult(
          success: false,
          zone: 'blocked',
          message: 'Naka-clock in ka na${status.deviceModel != null ? ' sa ${status.deviceModel}' : ''}.',
        );
      }
    } catch (e) {
      debugPrint('[Attendance] Status check skipped: $e');
    }

    // ── NEW: Use checkGeofenceForEmployee to get field proof logic ──
    final geo = await GeofenceService.instance.checkGeofenceForEmployee(
      employeeId: employeeId, // assuming this is the doc ID for employees collection
    );

    // ── NEW: Handle Field Worker needing selfie proof ──
    if (geo.needsProof) {
      try {
        final proofId = await FieldProofService.instance.captureAndSubmit(
          employeeId: employeeId,
          employeeDocId: employeeId, // Adjust if your Auth UID is different from employeeId
          attendanceType: 'IN',
          nearestSiteName: geo.matchedLocationName,
        );
        return AttendanceResult(
          success: false,
          needsProof: true,
          proofId: proofId,
          zone: 'pending_proof',
          message: 'Selfie proof submitted.\nWaiting for HR approval.',
          distanceMeters: geo.distanceMeters,
        );
      } on FieldProofException catch (e) {
        return AttendanceResult(
          success: false,
          needsProof: true,
          zone: 'blocked',
          message: e.message,
          distanceMeters: geo.distanceMeters,
        );
      }
    }

    // ── Validate Zone ──
    String zone;
    if (isWFH) {
      zone = 'wfh';
    } else if (isDriver) {
      zone = 'driver';
    } else if (geo.isAllowed) { // geo.isAllowed covers exact inside, tolerance, and exempted
      zone = 'inside';
    } else {
      zone = 'outside';
    }

    if (zone == 'outside' || (!geo.isAllowed && !isWFH && !isDriver)) {
      await AdminNotificationService.instance.notifyGeofenceAlert(
        employeeId: employeeId,
        employeeName: employeeName,
        timeStr: DateFormat('hh:mm a').format(now),
        distanceMeters: geo.distanceMeters ?? 0,
        action: 'clock_in',
      );
      return AttendanceResult(
        success: false,
        zone: 'outside',
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

    // ── NEW: Use checkGeofenceForEmployee ──
    final geo = await GeofenceService.instance.checkGeofenceForEmployee(
      employeeId: employeeId,
    );

    // ── NEW: Handle Field Worker needing selfie proof for Clock Out ──
    if (geo.needsProof) {
      try {
        final proofId = await FieldProofService.instance.captureAndSubmit(
          employeeId: employeeId,
          employeeDocId: employeeId,
          attendanceType: 'OUT',
          nearestSiteName: geo.matchedLocationName,
        );
        return AttendanceResult(
          success: false,
          needsProof: true,
          proofId: proofId,
          zone: 'pending_proof',
          message: 'Selfie proof submitted.\nWaiting for HR approval.',
          distanceMeters: geo.distanceMeters,
        );
      } on FieldProofException catch (e) {
        return AttendanceResult(
          success: false,
          needsProof: true,
          zone: 'blocked',
          message: e.message,
          distanceMeters: geo.distanceMeters,
        );
      }
    }

    String zone;
    if (isWFH) {
      zone = 'wfh';
    } else if (isDriver) {
      zone = 'driver';
    } else if (geo.isAllowed) {
      zone = 'inside';
    } else {
      zone = 'outside';
    }

    // Your original logic allows clocking OUT even if outside
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
        inRange: geo.isAllowed, // <-- updated to use isAllowed
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

// ══════════════════════════════════════════════════════════════════
// UPDATED RESULT MODEL
// ══════════════════════════════════════════════════════════════════
class AttendanceResult {
  final bool success;
  final String zone;
  final String message;
  final double? distanceMeters;

  // NEW FIELDS
  final bool needsProof;
  final String? proofId;

  const AttendanceResult({
    required this.success,
    required this.zone,
    required this.message,
    this.distanceMeters,
    this.needsProof = false,
    this.proofId,
  });
}