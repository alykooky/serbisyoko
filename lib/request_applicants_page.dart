import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'services/job_application_service.dart';
import 'booking_confirmation.dart';
import 'services/notification_service.dart';

class RequestApplicantsPage extends StatefulWidget {
  final String requestId;
  final String serviceType;

  const RequestApplicantsPage({
    super.key,
    required this.requestId,
    required this.serviceType,
  });

  @override
  State<RequestApplicantsPage> createState() => _RequestApplicantsPageState();
}

class _RequestApplicantsPageState extends State<RequestApplicantsPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _apps = [];
  Map<String, dynamic>? _serviceRequest;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // Load service request details
      final request = await Supabase.instance.client
          .from('service_requests')
          .select('*')
          .eq('id', widget.requestId)
          .maybeSingle();
      
      if (request != null) {
        setState(() => _serviceRequest = Map<String, dynamic>.from(request));
      }

      // Load applicants
      final rows = await JobApplicationService.fetchApplicantsForRequest(
          widget.requestId);
      setState(() => _apps = rows);
    } catch (e) {
      debugPrint("Error loading applicants: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setStatus(String appId, String status, String workerId) async {
    if (status == 'accepted') {
      // Show confirmation dialog first
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Accept Applicant?'),
          content: const Text(
            'Are you sure you want to accept this worker? A booking will be created and other applicants will be rejected.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFED9121),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );

      if (confirmed == true && mounted) {
        await _acceptApplicant(appId, workerId);
      }
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Reject Applicant?'),
          content: const Text('Are you sure you want to reject this worker?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Reject'),
            ),
          ],
        ),
      );

      if (confirmed == true && mounted) {
        await Supabase.instance.client
            .from('job_applications')
            .update({'status': status}).eq('id', appId);
        await _load();
      }
    }
  }

  Future<void> _acceptApplicant(String appId, String workerId) async {
    if (_serviceRequest == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: Service request not found.')),
      );
      return;
    }

    try {
      final clientId = Supabase.instance.client.auth.currentUser?.id;
      if (clientId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please sign in.')),
        );
        return;
      }

      // Get the application to get rate_offer
      final application = _apps.firstWhere((app) => app['id'].toString() == appId);
      final rateOffer = (application['rate_offer'] as num?)?.toDouble() ?? 0.0;
      final workerName = application['display_name'] ?? 'Worker';

      // Parse preferred date from service request
      final preferredDateStr = _serviceRequest!['preferred_date']?.toString();
      DateTime scheduledDateTime;
      if (preferredDateStr != null && preferredDateStr.isNotEmpty) {
        scheduledDateTime = DateTime.tryParse(preferredDateStr) ?? DateTime.now().add(const Duration(days: 1));
      } else {
        scheduledDateTime = DateTime.now().add(const Duration(days: 1));
      }

      // Get coordinates and address from service request
      final clientLat = (_serviceRequest!['latitude'] ?? _serviceRequest!['client_latitude']) as num?;
      final clientLng = (_serviceRequest!['longitude'] ?? _serviceRequest!['client_longitude']) as num?;
      // Get the actual address provided by client, don't use placeholder
      final clientAddress = (_serviceRequest!['location']?.toString().trim().isNotEmpty == true)
                              ? _serviceRequest!['location']?.toString().trim()
                              : (_serviceRequest!['client_address']?.toString().trim().isNotEmpty == true)
                                  ? _serviceRequest!['client_address']?.toString().trim()
                                  : null;

      // Create booking
      final bookingResult = await Supabase.instance.client
          .from('bookings')
          .insert({
        'client_id': clientId,
        'worker_id': workerId,
        'service_type': widget.serviceType,
        'scheduled_time': scheduledDateTime.toIso8601String(),
        'location': clientAddress, // Save actual address or null
        'client_address': clientAddress, // Save actual address or null
        'client_lat': clientLat?.toDouble(),
        'client_lng': clientLng?.toDouble(),
        'problem_details': _serviceRequest!['description']?.toString(),
        'estimated_price': (rateOffer * 2).toInt(), // 2 hours default
        'booking_fee': 0,
        'mode_of_payment': 'Cash',
        'status': 'pending',
      }).select().single();

      // Update application status to accepted
      await Supabase.instance.client
          .from('job_applications')
          .update({'status': 'accepted'}).eq('id', appId);

      // Close the service request
      await Supabase.instance.client
          .from('service_requests')
          .update({'status': 'closed'}).eq('id', widget.requestId);

      // Reject other pending applications
      await Supabase.instance.client
          .from('job_applications')
          .update({'status': 'rejected'})
          .eq('request_id', widget.requestId)
          .eq('status', 'pending');

      // Send notifications
      try {
        // Get current user (client) ID
        final currentUser = Supabase.instance.client.auth.currentUser;
        final clientId = currentUser?.id;

        // Notify worker that their application was accepted
        await NotificationService.createNotification(
          userId: workerId,
          type: 'application_accepted',
          title: 'Application Accepted!',
          message: 'Your application for "${widget.serviceType}" has been accepted. A booking has been created.',
          relatedId: bookingResult['id'].toString(),
          relatedType: 'booking',
        );

        // Notify client (confirmation that booking was created)
        if (clientId != null) {
          await NotificationService.createNotification(
            userId: clientId,
            type: 'booking_created',
            title: 'Booking Created',
            message: 'Your booking for "${widget.serviceType}" has been created successfully. Waiting for worker confirmation.',
            relatedId: bookingResult['id'].toString(),
            relatedType: 'booking',
          );
        }

        // Notify other rejected workers
        final rejectedApps = await Supabase.instance.client
            .from('job_applications')
            .select('worker_id')
            .eq('request_id', widget.requestId)
            .eq('status', 'rejected');

        for (final app in rejectedApps) {
          final rejectedWorkerId = app['worker_id']?.toString();
          if (rejectedWorkerId != null && rejectedWorkerId != workerId) {
            await NotificationService.createNotification(
              userId: rejectedWorkerId,
              type: 'application_rejected',
              title: 'Application Update',
              message: 'Another worker was selected for "${widget.serviceType}".',
              relatedId: widget.requestId,
              relatedType: 'request',
            );
          }
        }
      } catch (e) {
        debugPrint('Error sending notifications: $e');
        // Don't fail the entire operation if notifications fail
      }

      if (!mounted) return;

      // Navigate to booking confirmation screen using booking ID
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => BookingConfirmationScreen(
            bookingId: bookingResult['id'].toString(),
          ),
        ),
      );
    } catch (e) {
      debugPrint("Error accepting applicant: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFED9121);

    return Scaffold(
      appBar: AppBar(
        title: Text('Applicants for ${widget.serviceType}'),
        backgroundColor: accent,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _apps.isEmpty
              ? const Center(
                  child: Text('No workers have applied yet.'),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _apps.length,
                  itemBuilder: (ctx, i) {
                    final app = _apps[i];
                    final worker = app['worker_profiles'] ?? {};

                    final appId = app['id'].toString();
                    final status = app['status']?.toString() ?? 'pending';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              worker['display_name'] ?? 'Worker',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                                'Rate offer: ₱${(app['rate_offer'] ?? 0).toString()} / hr'),
                            Text('Rating: ${worker['average_rating'] ?? 0}'),
                            Text('Jobs done: ${worker['completed_jobs'] ?? 0}'),
                            if (app['note'] != null &&
                                app['note'].toString().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text('Message: ${app['note']}'),
                              ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Status: $status',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: status == 'accepted'
                                        ? Colors.green
                                        : status == 'rejected'
                                            ? Colors.red
                                            : Colors.grey,
                                  ),
                                ),
                                if (status == 'pending')
                                  Row(
                                    children: [
                                      TextButton(
                                        onPressed: () =>
                                            _setStatus(appId, 'rejected', app['worker_id'].toString()),
                                        child: const Text('Reject'),
                                      ),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: accent,
                                          foregroundColor: Colors.white,
                                        ),
                                        onPressed: () => _setStatus(
                                          appId,
                                          'accepted',
                                          app['worker_id'].toString(),
                                        ),
                                        child: const Text('Accept'),
                                      ),
                                    ],
                                  )
                                else
                                  Text(
                                    status == 'accepted'
                                        ? '✓ Accepted'
                                        : '✗ Rejected',
                                    style: TextStyle(
                                      color: status == 'accepted'
                                          ? Colors.green
                                          : Colors.red,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
