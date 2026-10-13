// lib/services/local_storage_service.dart
//
// Saves every attendance event as a JSON file on device storage.
//
// Folder structure created automatically:
//
//   HRIS_Biometrics/
//   ├── attendance/
//   │   ├── 2024-01-15/
//   │   │   ├── EMP-2024-001_clock_in_09-00-00.json
//   │   │   └── EMP-2024-001_clock_out_18-00-00.json
//   │   └── 2024-01-16/
//   │       └── EMP-2024-001_clock_in_08-55-00.json
//   ├── pin/
//   │   └── 2024-01-15/
//   │       └── EMP-2024-001_pin_auth_09-00-00.json
//   └── fingerprint/
//       └── 2024-01-15/
//           └── EMP-2024-001_fingerprint_auth_09-00-00.json

import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import '../models/attendance.dart';
import '../models/employee.dart';

class LocalStorageService {
  static LocalStorageService? _instance;
  LocalStorageService._();
  static LocalStorageService get instance =>
      _instance ??= LocalStorageService._();

  // Root folder name on device
  static const String _rootFolder = 'HRIS_Biometrics';

  // ── Get root directory ────────────────────────────────────────────────────

  Future<Directory> get _rootDir async {
    final base = await getApplicationDocumentsDirectory();
    final root = Directory('${base.path}/$_rootFolder');
    if (!await root.exists()) await root.create(recursive: true);
    return root;
  }

  Future<Directory> _getFolder(String subfolder, String date) async {
    final root = await _rootDir;
    final dir = Directory('${root.path}/$subfolder/$date');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  // ── Save clock-in record ──────────────────────────────────────────────────

  Future<File> saveClockIn({
    required Employee employee,
    required Attendance attendance,
  }) async {
    final date = attendance.date;
    final time = attendance.timeIn ?? DateFormat('HH-mm-ss').format(DateTime.now());
    final dir = await _getFolder('attendance', date);

    final fileName =
        '${employee.employeeId}_clock_in_${time.replaceAll(':', '-')}.json';
    final file = File('${dir.path}/$fileName');

    final data = {
      'event': 'clock_in',
      'employee_id': employee.employeeId,
      'employee_name': employee.fullName,
      'department': employee.department,
      'position': employee.position,
      'date': date,
      'time_in': attendance.timeIn,
      'status': attendance.status.name,
      'auth_method': attendance.method.name,
      'attendance_id': attendance.id,
      'saved_at': DateTime.now().toIso8601String(),
      'is_late': attendance.status == AttendanceStatus.late,
    };

    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));

    // Also save to method-specific folder
    await _saveMethodRecord(employee, attendance, 'clock_in', date, time);

    return file;
  }

  // ── Save clock-out record ─────────────────────────────────────────────────

  Future<File> saveClockOut({
    required Employee employee,
    required Attendance attendance,
    required String timeOut,
  }) async {
    final date = attendance.date;
    final dir = await _getFolder('attendance', date);

    final fileName =
        '${employee.employeeId}_clock_out_${timeOut.replaceAll(':', '-')}.json';
    final file = File('${dir.path}/$fileName');

    String? workDuration;
    if (attendance.timeIn != null) {
      try {
        final start = DateTime.parse('${attendance.date} ${attendance.timeIn}');
        final end = DateTime.parse('${attendance.date} $timeOut');
        final diff = end.difference(start);
        workDuration =
        '${diff.inHours}h ${diff.inMinutes % 60}m ${diff.inSeconds % 60}s';
      } catch (_) {}
    }

    final data = {
      'event': 'clock_out',
      'employee_id': employee.employeeId,
      'employee_name': employee.fullName,
      'department': employee.department,
      'position': employee.position,
      'date': date,
      'time_in': attendance.timeIn,
      'time_out': timeOut,
      'work_duration': workDuration,
      'status': attendance.status.name,
      'auth_method': attendance.method.name,
      'attendance_id': attendance.id,
      'saved_at': DateTime.now().toIso8601String(),
    };

    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));

    // Also save to method-specific folder
    await _saveMethodRecord(employee, attendance, 'clock_out', date, timeOut);

    return file;
  }

  // ── Save auth method record (pin/ or fingerprint/ subfolder) ─────────────

  Future<void> _saveMethodRecord(
      Employee employee,
      Attendance attendance,
      String event,
      String date,
      String time,
      ) async {
    final method = attendance.method;

    // Only create separate folders for PIN and Fingerprint
    if (method != AttendanceMethod.pin &&
        method != AttendanceMethod.fingerprint &&
        method != AttendanceMethod.face) {
      return;
    }

    final folderName = method == AttendanceMethod.pin
        ? 'pin'
        : method == AttendanceMethod.fingerprint
        ? 'fingerprint'
        : 'face_id';

    final dir = await _getFolder(folderName, date);
    final fileName =
        '${employee.employeeId}_${folderName}_${event}_${time.replaceAll(':', '-')}.json';
    final file = File('${dir.path}/$fileName');

    final data = {
      'event': event,
      'auth_method': method.name,
      'employee_id': employee.employeeId,
      'employee_name': employee.fullName,
      'date': date,
      'time': time,
      'attendance_id': attendance.id,
      'saved_at': DateTime.now().toIso8601String(),
    };

    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
  }

  // ── Save daily summary ────────────────────────────────────────────────────

  Future<File> saveDailySummary({
    required Employee employee,
    required Attendance attendance,
  }) async {
    final date = attendance.date;
    final dir = await _getFolder('attendance', date);
    final fileName = '${employee.employeeId}_summary.json';
    final file = File('${dir.path}/$fileName');

    String? workDuration;
    if (attendance.timeIn != null && attendance.timeOut != null) {
      try {
        final start =
        DateTime.parse('${attendance.date} ${attendance.timeIn}');
        final end = DateTime.parse('${attendance.date} ${attendance.timeOut}');
        final diff = end.difference(start);
        workDuration =
        '${diff.inHours}h ${diff.inMinutes % 60}m';
      } catch (_) {}
    }

    final data = {
      'date': date,
      'employee_id': employee.employeeId,
      'employee_name': employee.fullName,
      'department': employee.department,
      'time_in': attendance.timeIn ?? '--',
      'time_out': attendance.timeOut ?? '--',
      'work_duration': workDuration ?? '--',
      'status': attendance.status.name,
      'auth_method': attendance.method.name,
      'updated_at': DateTime.now().toIso8601String(),
    };

    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    return file;
  }

  // ── Read helpers ──────────────────────────────────────────────────────────

  /// Returns all attendance files for a given date
  Future<List<Map<String, dynamic>>> getRecordsForDate(String date) async {
    final results = <Map<String, dynamic>>[];
    final dir = await _getFolder('attendance', date);
    if (!await dir.exists()) return results;

    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'));

    for (final file in files) {
      try {
        final content = await file.readAsString();
        results.add(jsonDecode(content));
      } catch (_) {}
    }

    return results;
  }

  /// Returns all dates that have attendance records
  Future<List<String>> getAvailableDates() async {
    final root = await _rootDir;
    final attendanceDir = Directory('${root.path}/attendance');
    if (!await attendanceDir.exists()) return [];

    return attendanceDir
        .listSync()
        .whereType<Directory>()
        .map((d) => d.path.split('/').last)
        .toList()
      ..sort((a, b) => b.compareTo(a)); // newest first
  }

  /// Returns the full path of the root folder (for display in UI)
  Future<String> getRootPath() async {
    final root = await _rootDir;
    return root.path;
  }

  /// Returns total size of all saved files
  Future<String> getTotalSize() async {
    final root = await _rootDir;
    if (!await root.exists()) return '0 KB';

    int totalBytes = 0;
    await for (final entity in root.list(recursive: true)) {
      if (entity is File) {
        totalBytes += await entity.length();
      }
    }

    if (totalBytes < 1024) return '$totalBytes B';
    if (totalBytes < 1024 * 1024) {
      return '${(totalBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}