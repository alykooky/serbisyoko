import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

import 'my_bookings.dart';
import 'Dashboard.dart';
import 'referral_service.dart';

class BookingConfirmationScreen extends StatefulWidget {
  final String? bookingId; // Primary way - fetch dynamically
  // Backward compatibility - optional parameters if bookingId not provided
  final String? workerName;
  final String? workerId;
  final DateTime? selectedDate;
  final TimeOfDay? selectedTime;
  final int? hourlyRate;

  const BookingConfirmationScreen({
    super.key,
    this.bookingId,
    // Backward compatibility
    this.workerName,
    this.workerId,
    this.selectedDate,
    this.selectedTime,
    this.hourlyRate,
  });

  @override
  State<BookingConfirmationScreen> createState() => _BookingConfirmationScreenState();
}

class _BookingConfirmationScreenState extends State<BookingConfirmationScreen> {
  final _sb = Supabase.instance.client;
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _booking;
  Map<String, dynamic>? _worker;
  Map<String, dynamic>? _client;

  @override
  void initState() {
    super.initState();
    if (widget.bookingId != null) {
      _loadBookingData();
    } else {
      // Use provided parameters (backward compatibility)
      setState(() => _loading = false);
    }
  }

  Future<void> _loadBookingData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Fetch booking
      final bookingRow = await _sb
          .from('bookings')
          .select()
          .eq('id', widget.bookingId!)
          .maybeSingle();

      if (bookingRow == null) {
        setState(() {
          _error = 'Booking not found';
          _loading = false;
        });
        return;
      }

      _booking = Map<String, dynamic>.from(bookingRow);

      // Fetch worker info
      final workerId = _booking!['worker_id']?.toString();
      if (workerId != null) {
        try {
          // Try to get worker name from users table
          final workerUser = await _sb
              .from('users')
              .select('id, name, email, phone')
              .eq('id', workerId)
              .maybeSingle();

          if (workerUser != null) {
            _worker = Map<String, dynamic>.from(workerUser);
          }

          // Get worker profile for hourly rate
          final workerProfile = await _sb
              .from('worker_profiles')
              .select('user_id, hourly_rate, is_verified')
              .eq('user_id', workerId)
              .maybeSingle();

          if (workerProfile != null) {
            _worker = {
              ...?(_worker ?? {}),
              ...Map<String, dynamic>.from(workerProfile),
            };
          }
        } catch (e) {
          debugPrint('Error fetching worker info: $e');
        }
      }

      // Fetch client info (for reference)
      final clientId = _booking!['client_id']?.toString();
      if (clientId != null) {
        try {
          final clientUser = await _sb
              .from('users')
              .select('id, name, email, phone')
              .eq('id', clientId)
              .maybeSingle();

          if (clientUser != null) {
            _client = Map<String, dynamic>.from(clientUser);
          }
        } catch (e) {
          debugPrint('Error fetching client info: $e');
        }
      }

      setState(() => _loading = false);
    } catch (e) {
      debugPrint('Error loading booking: $e');
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String get _workerName {
    if (_worker != null) {
      return _worker!['name']?.toString() ?? 
             '${_worker!['first_name'] ?? ''} ${_worker!['last_name'] ?? ''}'.trim() ??
             'Worker';
    }
    return widget.workerName ?? 'Worker';
  }

  int get _hourlyRate {
    if (_booking != null) {
      // Calculate from estimated_price if available
      final estimatedPrice = (_booking!['estimated_price'] as num?)?.toInt();
      if (estimatedPrice != null && estimatedPrice > 0) {
        // Assume 2 hours default
        return estimatedPrice ~/ 2;
      }
    }
    if (_worker != null) {
      return (_worker!['hourly_rate'] as num?)?.toInt() ?? 0;
    }
    return widget.hourlyRate ?? 0;
  }

  DateTime get _scheduledDateTime {
    if (_booking != null && _booking!['scheduled_time'] != null) {
      try {
        return DateTime.parse(_booking!['scheduled_time'].toString());
      } catch (e) {
        debugPrint('Error parsing scheduled_time: $e');
      }
    }
    return widget.selectedDate ?? DateTime.now();
  }

  String get _serviceType {
    return _booking?['service_type']?.toString() ?? 'Service';
  }

  String get _location {
    return _booking?['location']?.toString() ?? 
           _booking?['client_address']?.toString() ?? 
           'Location not specified';
  }

  int get _totalAmount {
    if (_booking != null) {
      final price = (_booking!['estimated_price'] as num?)?.toInt() ??
                    (_booking!['price'] as num?)?.toInt();
      if (price != null && price > 0) {
        return price;
      }
    }
    return _hourlyRate * 2; // Default 2 hours
  }

  String _getDayName(int weekday) {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];
    return days[weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFED9121);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: accent,
          title: const Text(
            'Booking Confirmation',
            style: TextStyle(color: Colors.white),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: accent,
          title: const Text(
            'Booking Confirmation',
            style: TextStyle(color: Colors.white),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 48),
                const SizedBox(height: 16),
                Text(
                  'Error: $_error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: widget.bookingId != null ? _loadBookingData : null,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final scheduledDate = _scheduledDateTime;
    final scheduledTime = TimeOfDay.fromDateTime(scheduledDate);
    final endTime = TimeOfDay(
      hour: (scheduledTime.hour + 2) % 24,
      minute: scheduledTime.minute,
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: accent,
        title: const Text(
          'Booking Confirmation',
          style: TextStyle(color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ✅ Success Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 60),
                  const SizedBox(height: 12),
                  const Text(
                    'Booking Confirmed!',
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.green),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your booking with $_workerName has been confirmed',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, color: Colors.black87),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ✅ Booking Details
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.info_outline, color: accent, size: 20),
                        const SizedBox(width: 8),
                        const Text('Booking Details',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildDetailRow(
                        icon: Icons.person,
                        label: 'Service Provider',
                        value: _workerName),
                    const SizedBox(height: 12),
                    _buildDetailRow(
                      icon: Icons.build,
                      label: 'Service Type',
                      value: _serviceType,
                    ),
                    const SizedBox(height: 12),
                    _buildDetailRow(
                      icon: Icons.location_on,
                      label: 'Location',
                      value: _location,
                    ),
                    const SizedBox(height: 12),
                    _buildDetailRow(
                      icon: Icons.calendar_today,
                      label: 'Date',
                      value:
                          '${_getDayName(scheduledDate.weekday)}, ${scheduledDate.day}/${scheduledDate.month}/${scheduledDate.year}',
                    ),
                    const SizedBox(height: 12),
                    _buildDetailRow(
                      icon: Icons.access_time,
                      label: 'Time Slot',
                      value:
                          '${scheduledTime.format(context)} - ${endTime.format(context)}',
                    ),
                    if (_hourlyRate > 0) ...[
                      const SizedBox(height: 12),
                      _buildDetailRow(
                          icon: Icons.attach_money,
                          label: 'Hourly Rate',
                          value: '₱$_hourlyRate / hour'),
                    ],
                    const SizedBox(height: 12),
                    _buildDetailRow(
                      icon: Icons.calculate,
                      label: 'Total Amount',
                      value: '₱$_totalAmount',
                      isTotal: true,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ✅ Next Steps
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.next_plan, color: accent, size: 20),
                        const SizedBox(width: 8),
                        const Text("What's Next?",
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildNextStep(
                      number: '1',
                      title: 'Worker Notification',
                      description:
                          '$_workerName will be notified of your booking request.',
                    ),
                    const SizedBox(height: 12),
                    _buildNextStep(
                      number: '2',
                      title: 'Confirmation Call',
                      description:
                          'The worker will call you to confirm the details.',
                    ),
                    const SizedBox(height: 12),
                    _buildNextStep(
                      number: '3',
                      title: 'Service Day',
                      description:
                          'The worker will arrive at the scheduled time.',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ✅ Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const MyBookingsScreen()),
                      );
                    },
                    icon: const Icon(Icons.list),
                    label: const Text('View Bookings'),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: accent),
                      foregroundColor: accent,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      if (widget.bookingId != null) {
                        try {
                          await ReferralService(_sb)
                              .awardIfFirstBookingCompleted();
                        } catch (e) {
                          debugPrint('Referral check skipped: $e');
                        }
                      }

                      if (!context.mounted) return;
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              const DashboardPage(title: 'Dashboard'),
                        ),
                        (route) => false,
                      );
                    },
                    icon: const Icon(Icons.home),
                    label: const Text('Back to Home'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ===== Helper Widgets =====

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
    bool isTotal = false,
  }) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFFED9121), size: 16),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label,
              style: const TextStyle(fontSize: 14, color: Colors.grey)),
        ),
        Flexible(
          child: Text(
            value,
            style: TextStyle(
              fontSize: isTotal ? 16 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
              color: isTotal ? const Color(0xFFED9121) : Colors.black87,
            ),
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildNextStep({
    required String number,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(
            color: Color(0xFFED9121),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87)),
              const SizedBox(height: 2),
              Text(description,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
      ],
    );
  }
}
