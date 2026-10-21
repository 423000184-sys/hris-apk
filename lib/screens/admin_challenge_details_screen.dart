import 'package:flutter/material.dart';
import 'admin_theme.dart';

class AdminChallengeDetailsScreen extends StatelessWidget {
  final String employeeId;
  final String employeeName;
  final String? challengeId;
  final String? notificationType;

  const AdminChallengeDetailsScreen({
    super.key,
    required this.employeeId,
    required this.employeeName,
    this.challengeId,
    this.notificationType,
  });

  @override
  Widget build(BuildContext context) {
    final tc = AdminTheme.getColors(context);
    return Scaffold(
      backgroundColor: tc.background,
      appBar: AppBar(
        backgroundColor: tc.topBarBg,
        foregroundColor: tc.text,
        elevation: 0,
        title: Text('Challenge Details',
            style: TextStyle(color: tc.text, fontWeight: FontWeight.w700)),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.gpp_maybe_rounded, size: 64, color: tc.orange),
              const SizedBox(height: 16),
              Text('Challenge Details',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: tc.text)),
              const SizedBox(height: 12),
              Text(
                '$employeeName\nEmployee ID: $employeeId\n'
                    'Challenge ID: ${challengeId ?? "—"}\n'
                    'Type: ${notificationType ?? "—"}',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13, color: tc.textMuted, height: 1.5),
              ),
              const SizedBox(height: 24),
              Text('TODO: Implement full challenge details screen.',
                  style: TextStyle(
                      fontSize: 11,
                      color: tc.muted,
                      fontStyle: FontStyle.italic)),
            ],
          ),
        ),
      ),
    );
  }
}