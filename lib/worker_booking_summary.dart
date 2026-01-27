import 'package:flutter/material.dart';

class WorkerBookingSummaryScreen extends StatelessWidget {
  final Map<String, dynamic> booking;
  const WorkerBookingSummaryScreen({super.key, required this.booking});

  @override
  Widget build(BuildContext context) {
    final accent = const Color(0xFFED9121);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Booking Summary', style: TextStyle(color: Colors.white)),
        backgroundColor: accent,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _info('Service Type', booking['service_type']),
                _info('Scheduled Time', booking['scheduled_time']),
                _info('Client Name', booking['client_name']),
                _info('Worker Name', booking['worker_name']),
                _info('Location', booking['location']),
                _info('Estimated Price', 'PHP ${booking['estimated_price']}'),
                _info('Mode of Payment', booking['mode_of_payment'] ?? 'Cash'),
                _info('Status', booking['status']),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              height: 160,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: const Text('Location of Client (map placeholder)'),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total:', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('₱ ${(booking['estimated_price'] ?? 0) + (booking['booking_fee'] ?? 0)}', style: TextStyle(color: accent, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, 'accept'),
                    style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white),
                    child: const Text('Accept'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, 'decline'),
                    child: const Text('Decline'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _info(String label, String? value) {
    return SizedBox(
      width: 160,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.black12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 4),
            Text(value ?? '-', style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}



