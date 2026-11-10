// lib/screens/admin_force_transfer_screen.dart
import 'package:flutter/material.dart';

import '../services/device_transfer_service.dart';

class AdminForceTransferScreen extends StatefulWidget {
  final String employeeId;
  final String employeeName;

  const AdminForceTransferScreen({
    super.key,
    required this.employeeId,
    required this.employeeName,
  });

  @override
  State<AdminForceTransferScreen> createState() =>
      _AdminForceTransferScreenState();
}

class _AdminForceTransferScreenState extends State<AdminForceTransferScreen> {
  final _reasonController = TextEditingController();
  bool _loading = false;

  Future<void> _transfer() async {
    if (_reasonController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please provide a reason')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Force Device Transfer'),
        content: Text(
          'This will:\n\n'
              '1. Send a wipe command to the OLD device of ${widget.employeeName}\n'
              '2. Erase all local data on the old device\n'
              '3. Allow login from a new device\n\n'
              'Reason: ${_reasonController.text}\n\n'
              'Are you sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Yes, Transfer'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _loading = true);

    final result = await DeviceTransferService().revokeOldDevice(
      employeeId: widget.employeeId,
      employeeName: widget.employeeName,
      reason: _reasonController.text.trim(),
    );

    if (!mounted) return;
    setState(() => _loading = false);

    if (result.success) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('✅ Transfer Initiated'),
          content: Text(result.message),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ ${result.message}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Transfer: ${widget.employeeName}')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Employee ID: ${widget.employeeId}',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
              'Ang lumang device ay mawi-wipe sa susunod na koneksyon. '
                  'Maaaring mag-login ang empleyado sa bagong device pagkatapos.',
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _reasonController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Reason for Transfer *',
                hintText: 'e.g., Device lost, device broken, upgrade',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _transfer,
                icon: _loading
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Icon(Icons.phonelink_erase),
                label: Text(_loading ? 'Transferring...' : 'Force Transfer'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 40),
            const Divider(),
            const SizedBox(height: 16),
            Text('Audit History',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder(
                stream: DeviceTransferService()
                    .getAuditHistory(widget.employeeId),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = snapshot.data!.docs;
                  if (docs.isEmpty) {
                    return const Center(
                      child: Text('No audit history yet'),
                    );
                  }
                  return ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (ctx, i) {
                      final d = docs[i].data() as Map<String, dynamic>;
                      return ListTile(
                        leading: Icon(
                          d['action'] == 'REVOKE'
                              ? Icons.lock_reset
                              : Icons.link,
                          color: d['action'] == 'REVOKE'
                              ? Colors.red
                              : Colors.green,
                        ),
                        title: Text('${d['action']} — ${d['reason'] ?? ''}'),
                        subtitle: Text(
                          'By: ${d['performedByName'] ?? 'Admin'}\n'
                              'Old device: ${d['oldDeviceId'] ?? 'N/A'}',
                        ),
                        isThreeLine: true,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }
}