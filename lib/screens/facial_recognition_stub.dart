// lib/screens/facial_recognition_stub.dart
import 'package:flutter/material.dart';
import '../models/employee.dart' as model;

class FacialRecognitionScreen extends StatelessWidget {
  final model.Employee employee;
  final dynamic challenge;

  const FacialRecognitionScreen({
    super.key,
    required this.employee,
    this.challenge,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Not Supported')),
      body: const Center(
        child: Text(
          'Facial recognition and camera are not supported on the Web platform.',
          style: TextStyle(fontSize: 16),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}