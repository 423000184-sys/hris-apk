// lib/models/employee_notification.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class EmployeeNotification {
  final String id;
  final String type;
  final String title;
  final String message;
  final String employeeId;
  final String senderName;
  final bool read;
  final String priority;
  final DateTime? timestamp;
  final Map<String, dynamic> metadata;

  const EmployeeNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.employeeId,
    this.senderName = 'Admin',
    this.read = false,
    this.priority = 'normal',
    this.timestamp,
    this.metadata = const {},
  });

  factory EmployeeNotification.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};

    DateTime? ts;
    final raw = d['timestamp'];
    if (raw is Timestamp) {
      ts = raw.toDate();
    } else if (raw is String) {
      ts = DateTime.tryParse(raw);
    }

    if (ts == null) {
      final clientTs = d['clientTimestamp'];
      if (clientTs is String) {
        ts = DateTime.tryParse(clientTs);
      }
    }

    return EmployeeNotification(
      id: doc.id,
      type: (d['type'] ?? 'general').toString(),
      title: (d['title'] ?? '').toString(),
      message: (d['message'] ?? '').toString(),
      employeeId: (d['employeeId'] ?? '').toString(),
      senderName: (d['senderName'] ?? 'Admin').toString(),
      read: d['read'] == true,
      priority: (d['priority'] ?? 'normal').toString(),
      timestamp: ts,
      metadata: (d['metadata'] as Map?)?.cast<String, dynamic>() ?? {},
    );
  }
}