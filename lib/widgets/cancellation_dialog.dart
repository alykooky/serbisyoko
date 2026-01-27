// lib/widgets/cancellation_dialog.dart
import 'package:flutter/material.dart';
import '../services/booking_cancellation_service.dart';

class CancellationDialog extends StatefulWidget {
  final bool isClient;
  final String? currentStatus;
  final String? bookingId;

  const CancellationDialog({
    super.key,
    required this.isClient,
    this.currentStatus,
    this.bookingId,
  });

  @override
  State<CancellationDialog> createState() => _CancellationDialogState();
}

class _CancellationDialogState extends State<CancellationDialog> {
  String? _selectedReason;
  String _additionalNotes = '';
  final _notesController = TextEditingController();
  bool _loading = false;
  bool _canCancelFreely = false;

  @override
  void initState() {
    super.initState();
    _canCancelFreely = widget.isClient &&
        BookingCancellationService.canClientCancelFreely(widget.currentStatus);
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _confirmCancellation() async {
    // If free cancellation, just need confirmation
    if (_canCancelFreely && !BookingCancellationService.requiresReason(widget.currentStatus, widget.isClient)) {
      Navigator.pop(context, {
        'confirmed': true,
        'reason': null,
        'notes': null,
      });
      return;
    }

    // Require reason
    if (_selectedReason == null || _selectedReason!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a reason for cancellation'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // If "Other" is selected, require notes
    if (_selectedReason == 'Other' && _notesController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please provide additional details for "Other" reason'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    Navigator.pop(context, {
      'confirmed': true,
      'reason': _selectedReason,
      'notes': _notesController.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final reasons = widget.isClient
        ? BookingCancellationService.clientCancellationReasons
        : BookingCancellationService.workerCancellationReasons;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.cancel, color: Colors.red),
          const SizedBox(width: 8),
          Text(
            widget.isClient ? 'Cancel Booking' : 'Cancel Booking',
            style: const TextStyle(color: Colors.red),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_canCancelFreely) ...[
              const Text(
                'You can cancel this booking without penalty since the worker hasn\'t accepted yet.',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
            ] else ...[
              Text(
                widget.isClient
                    ? 'This booking has been accepted. Please provide a reason for cancellation:'
                    : 'Please select a reason for cancelling this booking:',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              
              // Reason selection
              ...reasons.map((reason) => RadioListTile<String>(
                    title: Text(reason),
                    value: reason,
                    groupValue: _selectedReason,
                    onChanged: (value) {
                      setState(() => _selectedReason = value);
                    },
                    contentPadding: EdgeInsets.zero,
                  )),
              
              // Additional notes (especially for "Other")
              if (_selectedReason == 'Other' || !widget.isClient) ...[
                const SizedBox(height: 8),
                const Text(
                  'Additional details (optional):',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: _notesController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'Please provide more information...',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    setState(() => _additionalNotes = value);
                  },
                ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context, {'confirmed': false}),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _loading ? null : _confirmCancellation,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          child: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Confirm Cancellation'),
        ),
      ],
    );
  }
}


