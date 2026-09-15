// lib/models/admin_notification.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminNotification {
  final String id;
  final String type;
  final String title;
  final String message;
  final String? employeeId;
  final String? employeeName;
  final DateTime? timestamp;
  final bool read;
  final String priority;
  final Map<String, dynamic> metadata;

  const AdminNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    this.employeeId,
    this.employeeName,
    this.timestamp,
    this.read = false,
    this.priority = 'normal',
    this.metadata = const {},
  });

  factory AdminNotification.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    DateTime? ts;
    final raw = d['timestamp'];
    if (raw is Timestamp) ts = raw.toDate();
    return AdminNotification(
      id: doc.id,
      type: (d['type'] ?? 'unknown').toString(),
      title: (d['title'] ?? '').toString(),
      message: (d['message'] ?? '').toString(),
      employeeId: d['employeeId']?.toString(),
      employeeName: d['employeeName']?.toString(),
      timestamp: ts,
      read: d['read'] == true,
      priority: (d['priority'] ?? 'normal').toString(),
      metadata: (d['metadata'] as Map?)?.cast<String, dynamic>() ?? {},
    );
  }
}