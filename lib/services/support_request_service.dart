// lib/services/support_request_service.dart
// ═══════════════════════════════════════════════════════════════════
// SUPPORT REQUEST SERVICE  v1.1
// Purpose:
//   Employees use this to notify admin/HR when something goes wrong
//   (e.g., PDF download fails, password not working, etc.).
//   This writes a notification to the admin_notifications collection
//   so it appears on the admin's notification page immediately.
// Updates:
//   - All user-facing text now in English.
// ═══════════════════════════════════════════════════════════════════
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;

import '../models/employee.dart';

class SupportRequestService {
  SupportRequestService._();
  static final instance = SupportRequestService._();

  static const String _collection = 'admin_notifications';

  /// Send a support request to admin. Returns true on success.
  Future<bool> sendRequest({
    required Employee employee,
    required String category,
    required String description,
  }) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final categoryLabel = categoryLabelOf(category);

      final trimmedDesc = description.trim();
      final message = trimmedDesc.isEmpty
          ? '${employee.fullName} needs help with $categoryLabel.'
          : trimmedDesc;

      final doc = <String, dynamic>{
        'title': 'Support: $categoryLabel',
        'message': message,
        'type': 'support_request',
        'priority': 'high',
        'read': false,
        'employeeId': employee.employeeId,
        'employeeName': employee.fullName,
        'employeeDocId': employee.id,
        'authUid': uid,
        'timestamp': FieldValue.serverTimestamp(),
        'metadata': <String, dynamic>{
          'category': category,
          'categoryLabel': categoryLabel,
          'platform': kIsWeb ? 'web' : 'mobile',
          'descriptionLength': trimmedDesc.length,
        },
      };

      await FirebaseFirestore.instance
          .collection(_collection)
          .add(doc)
          .timeout(const Duration(seconds: 10));

      debugPrint('✅ [Support] Sent: $categoryLabel from ${employee.fullName}');
      return true;
    } catch (e) {
      debugPrint('❌ [Support] Failed: $e');
      return false;
    }
  }

  static String categoryLabelOf(String category) {
    switch (category) {
      case 'pdf_download':
        return 'PDF Download Issue';
      case 'pdf_password':
        return 'PDF Password Not Working';
      case 'salary_question':
        return 'Salary / Payslip Question';
      case 'app_issue':
        return 'App Not Working';
      case 'other':
      default:
        return 'General Help';
    }
  }

  static const List<SupportCategory> categories = <SupportCategory>[
    SupportCategory(
      value: 'pdf_download',
      label: 'PDF failed to download',
      hint: 'The download button failed or did not work',
    ),
    SupportCategory(
      value: 'pdf_password',
      label: 'PDF password not working',
      hint: 'The password was not accepted by the PDF',
    ),
    SupportCategory(
      value: 'salary_question',
      label: 'Salary / payslip question',
      hint: 'You have a question about your salary or payslip',
    ),
    SupportCategory(
      value: 'app_issue',
      label: 'App not working',
      hint: 'The app hangs, crashes, or does not work',
    ),
    SupportCategory(
      value: 'other',
      label: 'Other concern',
      hint: 'Any other concern',
    ),
  ];
}

class SupportCategory {
  final String value;
  final String label;
  final String hint;
  const SupportCategory({
    required this.value,
    required this.label,
    required this.hint,
  });
}