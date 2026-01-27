import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

import 'booking_detail_screen.dart';
import 'services/notification_service.dart';
import 'services/booking_cancellation_service.dart';
import 'widgets/cancellation_dialog.dart';

class WorkerBookingsHistoryScreen extends StatefulWidget {
  final int? initialTabIndex; // 0=All, 1=Pending, 2=Upcoming, 3=Past
  
  const WorkerBookingsHistoryScreen({super.key, this.initialTabIndex});

  @override
  State<WorkerBookingsHistoryScreen> createState() => _WorkerBookingsHistoryScreenState();
}

class _WorkerBookingsHistoryScreenState extends State<WorkerBookingsHistoryScreen> with SingleTickerProviderStateMixin {
  final _sb = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _allBookings = [];
  List<Map<String, dynamic>> _filteredBookings = [];
  late TabController _tabController;
  String _selectedFilter = 'all'; // 'all', 'upcoming', 'past', 'pending'

  @override
  void initState() {
    super.initState();
    final initialIndex = widget.initialTabIndex ?? 0;
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: initialIndex.clamp(0, 3),
    );
    _tabController.addListener(_onTabChanged);
    
    // Set initial filter based on tab index
    switch (_tabController.index) {
      case 0:
        _selectedFilter = 'all';
        break;
      case 1:
        _selectedFilter = 'pending';
        break;
      case 2:
        _selectedFilter = 'upcoming';
        break;
      case 3:
        _selectedFilter = 'past';
        break;
    }
    
    _loadBookings();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    setState(() {
      switch (_tabController.index) {
        case 0:
          _selectedFilter = 'all';
          break;
        case 1:
          _selectedFilter = 'pending';
          break;
        case 2:
          _selectedFilter = 'upcoming';
          break;
        case 3:
          _selectedFilter = 'past';
          break;
      }
      _applyFilter();
    });
  }

  Future<void> _loadBookings() async {
    setState(() => _loading = true);
    try {
      final user = _sb.auth.currentUser;
      if (user == null) throw "Not logged in";

      // Fetch bookings with client info
      final bookingsData = await _sb
          .from('bookings')
          .select()
          .eq('worker_id', user.id)
          .order('scheduled_time', ascending: false);

      final bookings = (bookingsData as List).map((b) => Map<String, dynamic>.from(b)).toList();

      // Fetch client information for each booking
      final clientIds = bookings
          .map((b) => b['client_id']?.toString())
          .where((id) => id != null && id.isNotEmpty)
          .toSet()
          .toList();

      Map<String, Map<String, dynamic>> clientMap = {};
      if (clientIds.isNotEmpty) {
        try {
          final clients = await _sb
              .from('users')
              .select('id, name, email, phone')
              .inFilter('id', clientIds);

          for (final client in clients) {
            clientMap[client['id'].toString()] = Map<String, dynamic>.from(client);
          }
        } catch (e) {
          debugPrint('Error fetching client info: $e');
        }
      }

      // Fetch ratings for bookings
      final bookingIds = bookings.map((b) => b['id'].toString()).toList();
      Map<String, Map<String, dynamic>> ratingMap = {};
      
      if (bookingIds.isNotEmpty) {
        try {
          final ratings = await _sb
              .from('ratings')
              .select('booking_id, score, comment, created_at')
              .inFilter('booking_id', bookingIds);

          for (final rating in ratings) {
            ratingMap[rating['booking_id'].toString()] = Map<String, dynamic>.from(rating);
          }
        } catch (e) {
          debugPrint('Error fetching ratings: $e');
        }
      }

      // Merge client and rating info into bookings
      for (final booking in bookings) {
        final clientId = booking['client_id']?.toString();
        final bookingId = booking['id'].toString();
        
        if (clientId != null && clientMap.containsKey(clientId)) {
          booking['client'] = clientMap[clientId];
        }
        
        if (ratingMap.containsKey(bookingId)) {
          booking['rating'] = ratingMap[bookingId];
        }
      }

      setState(() {
        _allBookings = bookings;
      });
      _applyFilter();
    } catch (e) {
      debugPrint("Error loading bookings: $e");
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Error loading bookings: $e")));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyFilter() {
    final now = DateTime.now();
    
    setState(() {
      _filteredBookings = _allBookings.where((booking) {
        final scheduledTimeStr = booking['scheduled_time']?.toString();
        if (scheduledTimeStr == null) return _selectedFilter == 'all';
        
        final scheduledTime = DateTime.tryParse(scheduledTimeStr);
        if (scheduledTime == null) return _selectedFilter == 'all';
        
        final status = (booking['status']?.toString() ?? '').toLowerCase();
        final isPast = scheduledTime.isBefore(now);
        final isPending = status == 'pending';
        final isAccepted = status == 'accepted';
        final isUpcoming = scheduledTime.isAfter(now) && !isPast && (isAccepted || status == 'inprogress');
        final isCompleted = status == 'completed';
        final isCancelled = status == 'cancelled';

        switch (_selectedFilter) {
          case 'pending':
            return isPending && !isCancelled;
          case 'upcoming':
            return isUpcoming && !isCancelled && !isCompleted;
          case 'past':
            return (isPast || isCompleted) && !isCancelled;
          case 'all':
          default:
            return true;
        }
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFED9121);

    return Scaffold(
      appBar: AppBar(
        title: const Text("My Bookings"),
        backgroundColor: accent,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadBookings,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Pending'),
            Tab(text: 'Upcoming'),
            Tab(text: 'Past'),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadBookings,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: accent))
            : _filteredBookings.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _filteredBookings.length,
                    itemBuilder: (context, index) {
                      return _buildBookingCard(_filteredBookings[index]);
                    },
                  ),
      ),
    );
  }

  Widget _buildEmptyState() {
    String message = 'No bookings found.';
    IconData icon = Icons.calendar_today_outlined;
    
    switch (_selectedFilter) {
      case 'pending':
        message = 'No pending bookings.';
        icon = Icons.pending_actions;
        break;
      case 'upcoming':
        message = 'No upcoming bookings.';
        icon = Icons.schedule_outlined;
        break;
      case 'past':
        message = 'No past bookings yet.';
        icon = Icons.history;
        break;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              message,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBookingCard(Map<String, dynamic> booking) {
    const accent = Color(0xFFED9121);
    
    final scheduledTimeStr = booking['scheduled_time']?.toString();
    final scheduledTime = scheduledTimeStr != null 
        ? DateTime.tryParse(scheduledTimeStr) 
        : null;
    
    final status = (booking['status']?.toString() ?? 'Pending').toLowerCase();
    final client = booking['client'] as Map<String, dynamic>?;
    final clientName = client?['name']?.toString() ?? 'Client';
    final rating = booking['rating'] as Map<String, dynamic>?;
    final serviceType = booking['service_type']?.toString() ?? 'Service';
    final location = booking['location']?.toString() ?? 'Location not specified';
    final estimatedPrice = (booking['estimated_price'] as num?)?.toInt() ?? 0;

    // Status color
    Color statusColor;
    IconData statusIcon;
    switch (status) {
      case 'completed':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'cancelled':
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        break;
      case 'inprogress':
        statusColor = Colors.blue;
        statusIcon = Icons.work;
        break;
      case 'accepted':
        statusColor = Colors.orange;
        statusIcon = Icons.check;
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.pending;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BookingDetailScreen(bookingId: booking['id'].toString()),
            ),
          ).then((_) => _loadBookings());
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          serviceType,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.person, size: 16, color: Colors.grey[600]),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                clientName,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[700],
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: statusColor.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon, size: 16, color: statusColor),
                        const SizedBox(width: 4),
                        Text(
                          status.toUpperCase(),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
              // Date and time
              if (scheduledTime != null) ...[
                Row(
                  children: [
                    Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 8),
                    Text(
                      DateFormat('EEEE, MMMM dd, yyyy').format(scheduledTime),
                      style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 8),
                    Text(
                      DateFormat('h:mm a').format(scheduledTime),
                      style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
              ],
              
              // Location
              Row(
                children: [
                  Icon(Icons.location_on, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      location,
                      style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              
              // Rating received
              if (rating != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Text('Rating: ', style: TextStyle(fontSize: 12)),
                      ...List.generate(5, (i) {
                        return Icon(
                          i < (rating['score'] as int? ?? 0)
                              ? Icons.star
                              : Icons.star_border,
                          size: 16,
                          color: Colors.amber,
                        );
                      }),
                      if (rating['comment'] != null && rating['comment'].toString().isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            rating['comment'].toString(),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[700],
                              fontStyle: FontStyle.italic,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              
              // Price
              if (estimatedPrice > 0) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.attach_money, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 8),
                    Text(
                      '₱${estimatedPrice.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ],
              
              const SizedBox(height: 12),
              
              // Action buttons for providers
              if (status == 'pending') ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _suggestDifferentTime(booking),
                      icon: const Icon(Icons.schedule),
                      label: const Text('Suggest Time'),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: accent),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () => _declineBooking(booking['id'].toString()),
                      icon: const Icon(Icons.cancel, color: Colors.red),
                      label: const Text('Decline', style: TextStyle(color: Colors.red)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () => _acceptBooking(booking['id'].toString()),
                      icon: const Icon(Icons.check),
                      label: const Text('Accept'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _acceptBooking(String bookingId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Accept Booking?'),
        content: const Text('Are you sure you want to accept this booking?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFED9121)),
            child: const Text('Accept'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _sb
          .from('bookings')
          .update({'status': 'Accepted'}).eq('id', bookingId);

      // Send notification to client
      final booking = _allBookings.firstWhere((b) => b['id'].toString() == bookingId);
      final clientId = booking['client_id']?.toString();
      
      if (clientId != null) {
        await NotificationService.createNotification(
          userId: clientId,
          type: 'booking_status_changed',
          title: 'Booking Accepted',
          message: 'Your booking has been accepted by the worker.',
          relatedId: bookingId,
          relatedType: 'booking',
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Booking accepted."),
            backgroundColor: Colors.green,
          ),
        );
        _loadBookings();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  Future<void> _declineBooking(String bookingId) async {
    // Get current booking status
    final booking = _allBookings.firstWhere(
      (b) => b['id'].toString() == bookingId,
      orElse: () => {},
    );
    
    final currentStatus = booking['status']?.toString();
    
    // Show cancellation dialog (workers always need to provide reason)
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => CancellationDialog(
        isClient: false,
        currentStatus: currentStatus,
        bookingId: bookingId,
      ),
    );

    if (result == null || result['confirmed'] != true) return;

    // Check if worker has exceeded cancellation limit
    final user = _sb.auth.currentUser;
    if (user != null) {
      final hasExceeded = await BookingCancellationService.hasExceededCancellationLimit(
        user.id,
        maxCancellations: 5, // Configurable
        days: 30,
      );
      
      if (hasExceeded) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'You have exceeded the cancellation limit. Please contact support or reduce your cancellation rate.',
              ),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 5),
            ),
          );
        }
        return;
      }
    }

    // Perform cancellation
    try {
      final cancellationResult = await BookingCancellationService.cancelByWorker(
        bookingId: bookingId,
        reason: result['reason']?.toString() ?? 'No reason provided',
        additionalNotes: result['notes']?.toString(),
      );

      if (cancellationResult['success'] == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Booking cancelled successfully."),
            backgroundColor: Colors.orange,
          ),
        );
        _loadBookings();
      } else {
        throw Exception(cancellationResult['error'] ?? 'Cancellation failed');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error cancelling booking: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _suggestDifferentTime(Map<String, dynamic> booking) async {
    final scheduledTimeStr = booking['scheduled_time']?.toString();
    final currentScheduledTime = scheduledTimeStr != null
        ? DateTime.tryParse(scheduledTimeStr)
        : DateTime.now().add(const Duration(days: 1));

    DateTime? selectedDate;
    TimeOfDay? selectedTime;

    // Show date picker
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: currentScheduledTime ?? DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (pickedDate == null) return;
    selectedDate = pickedDate;

    // Show time picker
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(currentScheduledTime ?? DateTime.now()),
    );

    if (pickedTime == null) return;
    selectedTime = pickedTime;

    // Combine date and time
    final newScheduledTime = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      selectedTime.hour,
      selectedTime.minute,
    );

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Suggest Different Time'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Proposed new time:'),
            const SizedBox(height: 8),
            Text('Date: ${DateFormat('EEEE, MMMM dd, yyyy').format(newScheduledTime)}'),
            Text('Time: ${DateFormat('h:mm a').format(newScheduledTime)}'),
            const SizedBox(height: 8),
            const Text(
              'The client will be notified and can accept or reject this suggestion.',
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFED9121)),
            child: const Text('Send Suggestion'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final workerId = _sb.auth.currentUser?.id;
      final bookingId = booking['id'].toString();
      final clientId = booking['client_id']?.toString();
      
      // Store suggested time in booking
      await _sb
          .from('bookings')
          .update({
            'suggested_time': newScheduledTime.toIso8601String(),
            'suggested_by': workerId,
          })
          .eq('id', bookingId);

      // Send notification to client
      if (clientId != null) {
        await NotificationService.createNotification(
          userId: clientId,
          type: 'time_suggestion',
          title: 'Time Suggestion',
          message: 'Worker suggests a different time: ${DateFormat('EEEE, MMMM dd at h:mm a').format(newScheduledTime)}',
          relatedId: bookingId,
          relatedType: 'booking',
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Time suggestion sent to client."),
            backgroundColor: Colors.green,
          ),
        );
        _loadBookings();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }
}

