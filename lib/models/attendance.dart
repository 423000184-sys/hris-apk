// lib/models/attendance.dart
class Attendance {
  final String id;
  final String employeeId;
  final String date;
  final String? timeIn;
  final String? timeOut;
  final AttendanceStatus status;
  final AttendanceMethod method;
  final double? latitude;
  final double? longitude;
  final String? deviceId;
  final String? notes;
  final DateTime createdAt;

  Attendance({
    required this.id,
    required this.employeeId,
    required this.date,
    this.timeIn,
    this.timeOut,
    this.status = AttendanceStatus.present,
    required this.method,
    this.latitude,
    this.longitude,
    this.deviceId,
    this.notes,
    required this.createdAt,
  });

  bool get isComplete => timeIn != null && timeOut != null;
  bool get isClockedIn => timeIn != null && timeOut == null;

  Duration? get workDuration {
    if (timeIn == null || timeOut == null) return null;
    final start = DateTime.parse('$date $timeIn');
    final end = DateTime.parse('$date $timeOut');
    return end.difference(start);
  }

  String get formattedWorkHours {
    final duration = workDuration;
    if (duration == null) return '--';
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    return '${hours}h ${minutes}m';
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'employee_id': employeeId,
        'date': date,
        'time_in': timeIn,
        'time_out': timeOut,
        'status': status.name,
        'method': method.name,
        'latitude': latitude,
        'longitude': longitude,
        'device_id': deviceId,
        'notes': notes,
        'created_at': createdAt.toIso8601String(),
      };

  factory Attendance.fromMap(Map<String, dynamic> map) => Attendance(
        id: map['id'],
        employeeId: map['employee_id'],
        date: map['date'],
        timeIn: map['time_in'],
        timeOut: map['time_out'],
        status: AttendanceStatus.values.firstWhere(
            (s) => s.name == (map['status'] ?? 'present'),
            orElse: () => AttendanceStatus.present),
        method: AttendanceMethod.values.firstWhere(
            (m) => m.name == (map['method'] ?? 'pin'),
            orElse: () => AttendanceMethod.pin),
        latitude: map['latitude'],
        longitude: map['longitude'],
        deviceId: map['device_id'],
        notes: map['notes'],
        createdAt: DateTime.parse(map['created_at']),
      );
}

enum AttendanceStatus {
  present,
  late,
  absent,
  halfDay,
  onLeave,
  holiday,
}

enum AttendanceMethod {
  face,
  fingerprint,
  pin,
  qrCode,
  nfc,
  manual,
}

extension AttendanceStatusExt on AttendanceStatus {
  String get label {
    switch (this) {
      case AttendanceStatus.present:
        return 'Present';
      case AttendanceStatus.late:
        return 'Late';
      case AttendanceStatus.absent:
        return 'Absent';
      case AttendanceStatus.halfDay:
        return 'Half Day';
      case AttendanceStatus.onLeave:
        return 'On Leave';
      case AttendanceStatus.holiday:
        return 'Holiday';
    }
  }
}

extension AttendanceMethodExt on AttendanceMethod {
  String get label {
    switch (this) {
      case AttendanceMethod.face:
        return 'Face ID';
      case AttendanceMethod.fingerprint:
        return 'Fingerprint';
      case AttendanceMethod.pin:
        return 'PIN';
      case AttendanceMethod.qrCode:
        return 'QR Code';
      case AttendanceMethod.nfc:
        return 'NFC Tag';
      case AttendanceMethod.manual:
        return 'Manual';
    }
  }

  String get icon {
    switch (this) {
      case AttendanceMethod.face:
        return '👤';
      case AttendanceMethod.fingerprint:
        return '🔐';
      case AttendanceMethod.pin:
        return '🔢';
      case AttendanceMethod.qrCode:
        return '📱';
      case AttendanceMethod.nfc:
        return '📡';
      case AttendanceMethod.manual:
        return '✏️';
    }
  }
}
