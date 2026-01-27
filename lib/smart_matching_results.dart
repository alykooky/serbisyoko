import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/advanced_matching_service.dart';
import 'services/notification_service.dart';
import 'booking_confirmation.dart';
import 'provider_profile.dart';

class SmartMatchingResultsScreen extends StatefulWidget {
  final String serviceType;
  final double clientLat;
  final double clientLng;
  final String location;
  final String? description; // Service description/problem details
  final double budgetMin;
  final double budgetMax;
  final DateTime preferredStartTime;
  final DateTime preferredEndTime;
  final List<Map<String, dynamic>> results; // placeholder

  const SmartMatchingResultsScreen({
    super.key,
    required this.serviceType,
    required this.clientLat,
    required this.clientLng,
    required this.location,
    this.description, // Optional description
    required this.budgetMin,
    required this.budgetMax,
    required this.preferredStartTime,
    required this.preferredEndTime,
    required this.results,
  });

  @override
  State<SmartMatchingResultsScreen> createState() =>
      _SmartMatchingResultsScreenState();
}

class _SmartMatchingResultsScreenState
    extends State<SmartMatchingResultsScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _matches = [];

  @override
  void initState() {
    super.initState();
    _loadSQLResults();
  }

  Future<void> _loadSQLResults() async {
    setState(() => _loading = true);

    try {
      final data = await AdvancedMatchingService.findBestMatches(
        serviceType: widget.serviceType,
        clientLatitude: widget.clientLat,
        clientLongitude: widget.clientLng,
        preferredStartTime: widget.preferredStartTime,
        preferredEndTime: widget.preferredEndTime,
        budgetMin: widget.budgetMin,
        budgetMax: widget.budgetMax,
        limit: 10,
        searchRadiusKm: 15,
      );

      setState(() {
        _matches = data;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Error loading matches: $e');
      setState(() {
        _matches = [];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFED9121);

    return Scaffold(
      appBar: AppBar(
        title: Text("Matches for ${widget.serviceType}"),
        backgroundColor: accent,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.orange))
          : _matches.isEmpty
              ? const Center(
                  child: Text(
                    "No workers matched your request.",
                    style: TextStyle(fontSize: 18),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _matches.length,
                  itemBuilder: (context, i) {
                    final r = _matches[i];

                    final name = r['name']?.toString().trim();
                    if (name == null || name.isEmpty || name == 'Unnamed Worker') {
                      // Skip workers without names
                      return const SizedBox.shrink();
                    }

                    final distance =
                        (r['distance_km'] as num?)?.toDouble() ?? 0.0;
                    final hourlyRate =
                        (r['estimatedFee'] as num?)?.toDouble() ?? 
                        (r['hourlyRate'] as num?)?.toDouble() ?? 0.0;

                    final skills = (r['matchedSkills'] as List?)?.cast<String>() ?? 
                                   (r['skills'] as List?)?.cast<String>() ?? [];

                    final workerId = (r['workerId'] ?? r['id'])?.toString() ?? '';
                    
                    // Worker details
                    final email = r['email']?.toString() ?? '';
                    final phone = r['phone']?.toString() ?? '';
                    final address = r['address']?.toString() ?? '';
                    final bio = r['bio']?.toString() ?? '';
                    final averageRating = (r['averageRating'] as num?)?.toDouble() ?? 0.0;
                    final totalJobs = (r['totalJobs'] as num?)?.toInt() ?? 0;
                    final completedJobs = (r['completedJobs'] as num?)?.toInt() ?? 0;
                    final isVerified = r['isVerified'] == true;
                    final profileImage = r['profileImage']?.toString();

                    return Card(
                      elevation: 3,
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header with name and verification badge
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      if (profileImage != null && profileImage.isNotEmpty)
                                        CircleAvatar(
                                          radius: 20,
                                          backgroundImage: NetworkImage(profileImage),
                                        )
                                      else
                                        const CircleAvatar(
                                          radius: 20,
                                          child: Icon(Icons.person),
                                        ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    name,
                                                    style: const TextStyle(
                                                      fontSize: 17,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                if (isVerified)
                                                  const Icon(
                                                    Icons.verified,
                                                    color: Colors.green,
                                                    size: 18,
                                                  ),
                                              ],
                                            ),
                                            if (averageRating > 0)
                                              Row(
                                                children: [
                                                  const Icon(Icons.star, size: 14, color: Colors.amber),
                                                  Text(
                                                    ' ${averageRating.toStringAsFixed(1)}',
                                                    style: const TextStyle(fontSize: 12),
                                                  ),
                                                  if (completedJobs > 0)
                                                    Text(
                                                      ' • $completedJobs jobs',
                                                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                                                    ),
                                                ],
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 10),

                            // Distance and hourly rate
                            Row(
                              children: [
                                const Icon(Icons.location_on, size: 18, color: Colors.grey),
                                Text(" ${distance.toStringAsFixed(2)} km away"),
                                const SizedBox(width: 12),
                                const Icon(Icons.money, size: 18, color: Colors.grey),
                                Text(" ₱${hourlyRate.toStringAsFixed(0)} / hr"),
                              ],
                            ),

                            if (phone.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Icon(Icons.phone, size: 16, color: Colors.grey),
                                  Text(" $phone", style: const TextStyle(fontSize: 13)),
                                ],
                              ),
                            ],

                            if (address.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.home, size: 16, color: Colors.grey),
                                  Expanded(
                                    child: Text(
                                      " $address",
                                      style: const TextStyle(fontSize: 13),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],

                            if (bio.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                bio,
                                style: const TextStyle(fontSize: 13, color: Colors.black87),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],

                            const SizedBox(height: 12),

                            // Skills chips
                            if (skills.isNotEmpty)
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: skills
                                    .map((s) => Chip(
                                          label: Text(s),
                                          backgroundColor: Colors.orange.shade100,
                                          padding: const EdgeInsets.symmetric(horizontal: 8),
                                        ))
                                    .toList(),
                              ),

                            const SizedBox(height: 14),

                            // Action buttons
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () {
                                      // Navigate to worker profile
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => ProviderProfileScreen(
                                            workerId: workerId,
                                          ),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.person),
                                    label: const Text("View Profile"),
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(color: accent),
                                      foregroundColor: accent,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: accent,
                                      foregroundColor: Colors.white,
                                    ),
                                    onPressed: () => _bookWorker(
                                          workerId: workerId,
                                          workerName: name,
                                          hourlyRate: hourlyRate.toInt(),
                                        ),
                                    child: const Text("Book Now"),
                                  ),
                                ),
                              ],
                            )
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  Future<void> _bookWorker({
    required String workerId,
    required String workerName,
    required int hourlyRate,
  }) async {
    const accent = Color(0xFFED9121);
    
    // Use the preferred schedule that was already selected, or allow user to change it
    DateTime scheduledDateTime = widget.preferredStartTime;
    DateTime selectedDate;
    TimeOfDay selectedTime;

    // Show confirmation dialog with the preferred schedule
    final shouldChange = await showDialog<bool>(
      context: context,
      builder: (context) {
        final formattedDate = '${scheduledDateTime.month}/${scheduledDateTime.day}/${scheduledDateTime.year}';
        final formattedTime = TimeOfDay.fromDateTime(scheduledDateTime).format(context);
        return AlertDialog(
          title: const Text('Confirm Booking Schedule'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Date: $formattedDate'),
              const SizedBox(height: 8),
              Text('Time: $formattedTime'),
              const SizedBox(height: 16),
              const Text('Use this schedule or change it?'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, true), // Change schedule
              child: const Text('Change'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, false), // Use current schedule
              style: ElevatedButton.styleFrom(backgroundColor: accent),
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );

    if (shouldChange == null) return; // User cancelled

    // If user wants to change, show date/time pickers
    if (shouldChange == true) {
      // Pick date
      final pickedDate = await showDatePicker(
        context: context,
        initialDate: scheduledDateTime,
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 365)),
      );
      if (pickedDate == null) return;
      selectedDate = pickedDate;

      // Pick time
      final pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(scheduledDateTime),
      );
      if (pickedTime == null) return;
      selectedTime = pickedTime;

      scheduledDateTime = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        selectedTime.hour,
        selectedTime.minute,
      );
    } else {
      // Use preferred schedule
      selectedDate = scheduledDateTime;
      selectedTime = TimeOfDay.fromDateTime(scheduledDateTime);
    }

    // Create booking
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please sign in to book a worker.')),
        );
        return;
      }

      // Validate location before creating booking
      if (widget.clientLat == 0 || widget.clientLng == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error: Invalid location. Please set your service location.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final bookingResult = await Supabase.instance.client
          .from('bookings')
          .insert({
        'client_id': user.id,
        'worker_id': workerId,
        'service_type': widget.serviceType,
        'scheduled_time': scheduledDateTime.toIso8601String(),
        // Always save the exact location address provided by the client
        'location': widget.location.isNotEmpty ? widget.location : null,
        'client_address': widget.location.isNotEmpty ? widget.location : null,
        'client_lat': widget.clientLat, // Save client latitude
        'client_lng': widget.clientLng, // Save client longitude
        'problem_details': (widget.description?.trim().isEmpty ?? true)
            ? null
            : widget.description?.trim(), // Save description as problem details
        'estimated_price': hourlyRate * 2, // 2 hours default
        'booking_fee': 0,
        'mode_of_payment': 'Cash',
        'status': 'pending',
      }).select().single();
      
      debugPrint('✅ Booking created with coordinates: ${widget.clientLat}, ${widget.clientLng}');
      debugPrint('✅ Address saved: ${widget.location}');

      // Send notification to worker
      try {
        await NotificationService.createNotification(
          userId: workerId,
          type: 'booking_created',
          title: 'New Booking Request',
          message: 'You have a new booking request for "${widget.serviceType}". Please check your bookings.',
          relatedId: bookingResult['id'].toString(),
          relatedType: 'booking',
        );
      } catch (e) {
        debugPrint('Error sending notification to worker: $e');
        // Don't fail the booking creation if notification fails
      }

      // Send notification to client (confirmation)
      try {
        await NotificationService.createNotification(
          userId: user.id,
          type: 'booking_created',
          title: 'Booking Confirmed',
          message: 'Your booking for "${widget.serviceType}" has been created. Waiting for worker confirmation.',
          relatedId: bookingResult['id'].toString(),
          relatedType: 'booking',
        );
      } catch (e) {
        debugPrint('Error sending notification to client: $e');
        // Don't fail the booking creation if notification fails
      }

      if (!mounted) return;

      // Navigate to booking confirmation using booking ID
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => BookingConfirmationScreen(
            bookingId: bookingResult['id'].toString(),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error creating booking: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year}';
  }
}
