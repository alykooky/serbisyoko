import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

import 'booking_detail_screen.dart';
import 'booking_confirmation.dart';
import 'provider_profile.dart';
import 'services/booking_cancellation_service.dart';
import 'widgets/cancellation_dialog.dart';

class MyBookingsScreen extends StatefulWidget {
  const MyBookingsScreen({super.key});

  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen> with SingleTickerProviderStateMixin {
  final supa = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _allBookings = [];
  List<Map<String, dynamic>> _filteredBookings = [];
  late TabController _tabController;
  String _selectedFilter = 'all'; // 'all', 'upcoming', 'past', 'ongoing'

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);
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
          _selectedFilter = 'upcoming';
          break;
        case 2:
          _selectedFilter = 'ongoing';
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
      final user = supa.auth.currentUser;
      if (user == null) throw "Not logged in";

      // Fetch bookings with worker info
      // Order by created_at descending to show most recent bookings first
      final bookingsData = await supa
          .from('bookings')
          .select()
          .eq('client_id', user.id)
          .order('created_at', ascending: false);

      final bookings = (bookingsData as List).map((b) => Map<String, dynamic>.from(b)).toList();

      // Fetch worker information for each booking
      final workerIds = bookings
          .map((b) => b['worker_id']?.toString())
          .where((id) => id != null && id.isNotEmpty)
          .toSet()
          .toList();

      Map<String, Map<String, dynamic>> workerMap = {};
      if (workerIds.isNotEmpty) {
        try {
          final workers = await supa
              .from('users')
              .select('id, name, email, phone')
              .inFilter('id', workerIds);

          for (final worker in workers) {
            workerMap[worker['id'].toString()] = Map<String, dynamic>.from(worker);
          }
        } catch (e) {
          debugPrint('Error fetching worker info: $e');
        }
      }

      // Fetch ratings for bookings
      final bookingIds = bookings.map((b) => b['id'].toString()).toList();
      Map<String, Map<String, dynamic>> ratingMap = {};
      
      if (bookingIds.isNotEmpty) {
        try {
          final ratings = await supa
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

      // Merge worker and rating info into bookings
      for (final booking in bookings) {
        final workerId = booking['worker_id']?.toString();
        final bookingId = booking['id'].toString();
        
        if (workerId != null && workerMap.containsKey(workerId)) {
          booking['worker'] = workerMap[workerId];
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
        final scheduledTime = scheduledTimeStr != null 
            ? DateTime.tryParse(scheduledTimeStr) 
            : null;
        
        final status = (booking['status']?.toString() ?? '').toLowerCase();
        final isCompleted = status == 'completed';
        final isCancelled = status == 'cancelled' || status == 'declined';
        final isPending = status == 'pending';
        final isAccepted = status == 'accepted';
        final isInProgress = status == 'inprogress';
        
        // Upcoming: scheduled in the future AND (pending OR accepted) - not completed/cancelled
        final isUpcoming = scheduledTime != null && 
                          scheduledTime.isAfter(now) && 
                          (isPending || isAccepted) && 
                          !isCompleted && 
                          !isCancelled;
        
        // Ongoing: accepted or inprogress status (regardless of date)
        final isOngoing = (isAccepted || isInProgress) && 
                         !isCompleted && 
                         !isCancelled;

        switch (_selectedFilter) {
          case 'upcoming':
            return isUpcoming;
          case 'ongoing':
            return isOngoing;
          case 'past':
            // Past: only completed or cancelled/declined bookings
            return (isCompleted || isCancelled);
          case 'all':
          default:
            return true;
        }
      }).toList();
      
      // Sort by most recent first (created_at or scheduled_time, descending)
      _filteredBookings.sort((a, b) {
        // Try created_at first, then scheduled_time
        final aCreated = a['created_at']?.toString();
        final bCreated = b['created_at']?.toString();
        final aScheduled = a['scheduled_time']?.toString();
        final bScheduled = b['scheduled_time']?.toString();
        
        DateTime? aDate;
        DateTime? bDate;
        
        if (aCreated != null) {
          aDate = DateTime.tryParse(aCreated);
        }
        if (aDate == null && aScheduled != null) {
          aDate = DateTime.tryParse(aScheduled);
        }
        
        if (bCreated != null) {
          bDate = DateTime.tryParse(bCreated);
        }
        if (bDate == null && bScheduled != null) {
          bDate = DateTime.tryParse(bScheduled);
        }
        
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        
        return bDate.compareTo(aDate); // Descending (most recent first)
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFED9121);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Booking History"),
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
            Tab(text: 'Upcoming'),
            Tab(text: 'Ongoing'),
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
      case 'upcoming':
        message = 'No upcoming bookings.';
        icon = Icons.schedule_outlined;
        break;
      case 'ongoing':
        message = 'No ongoing bookings.';
        icon = Icons.work_outline;
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

  Widget _buildProgressTimeline(String status) {
    const steps = ['pending', 'accepted', 'inprogress', 'completed'];
    final currentIndex = steps.indexOf(status.toLowerCase());
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Progress',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: List.generate(steps.length, (index) {
              final isCompleted = index <= currentIndex;
              final isCurrent = index == currentIndex;
              
              return Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isCompleted
                                  ? (isCurrent
                                      ? _getStatusColor(status)
                                      : Colors.green)
                                  : Colors.grey[300],
                              border: Border.all(
                                color: isCompleted
                                    ? (isCurrent
                                        ? _getStatusColor(status)
                                        : Colors.green)
                                    : Colors.grey[400]!,
                                width: 2,
                              ),
                            ),
                            child: isCompleted
                                ? Icon(
                                    isCurrent
                                        ? _getStatusIcon(status)
                                        : Icons.check,
                                    size: 14,
                                    color: Colors.white,
                                  )
                                : null,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _getStatusLabel(steps[index]),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                              color: isCompleted
                                  ? (isCurrent
                                      ? _getStatusColor(status)
                                      : Colors.green)
                                  : Colors.grey,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (index < steps.length - 1)
                      Expanded(
                        child: Container(
                          height: 2,
                          color: index < currentIndex
                              ? Colors.green
                              : Colors.grey[300],
                          margin: const EdgeInsets.only(bottom: 12),
                        ),
                      ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      case 'inprogress':
        return Colors.blue;
      case 'accepted':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return Icons.check_circle;
      case 'cancelled':
        return Icons.cancel;
      case 'inprogress':
        return Icons.work;
      case 'accepted':
        return Icons.check;
      default:
        return Icons.pending;
    }
  }

  String _getStatusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return 'Pending';
      case 'accepted':
        return 'Accepted';
      case 'inprogress':
        return 'In Progress';
      case 'completed':
        return 'Completed';
      default:
        return status;
    }
  }

  Widget _buildBookingCard(Map<String, dynamic> booking) {
    const accent = Color(0xFFED9121);
    
    final scheduledTimeStr = booking['scheduled_time']?.toString();
    final scheduledTime = scheduledTimeStr != null 
        ? DateTime.tryParse(scheduledTimeStr) 
                          : null;
    
    final status = (booking['status']?.toString() ?? 'Pending').toLowerCase();
    final worker = booking['worker'] as Map<String, dynamic>?;
    final workerName = worker?['name']?.toString() ?? 'Unknown Worker';
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
                                workerName,
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
              
              // Progress Timeline
              _buildProgressTimeline(status),
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
              
              // Rating
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
              
              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (status == 'completed' && rating == null)
                    OutlinedButton.icon(
                      onPressed: () => _showRatingDialog(booking),
                      icon: const Icon(Icons.star_outline),
                      label: const Text('Rate'),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: accent),
                      ),
                    ),
                  if (status == 'completed' && worker != null)
                    const SizedBox(width: 8),
                  if (status == 'completed' && worker != null)
                    ElevatedButton.icon(
                      onPressed: () => _repeatBooking(booking, worker),
                      icon: const Icon(Icons.repeat),
                      label: const Text('Book Again'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  if (status != 'completed' && status != 'cancelled')
                    const SizedBox(width: 8),
                  if (status != 'completed' && status != 'cancelled')
                    TextButton.icon(
                      onPressed: () => _cancelBooking(booking['id'].toString()),
                      icon: const Icon(Icons.cancel, color: Colors.red),
                      label: const Text('Cancel', style: TextStyle(color: Colors.red)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _repeatBooking(Map<String, dynamic> booking, Map<String, dynamic> worker) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProviderProfileScreen(workerId: worker['id'].toString()),
      ),
    );
  }

  Future<void> _showRatingDialog(Map<String, dynamic> booking) async {
    const accent = Color(0xFFED9121);
    int rating = 0;
    final commentController = TextEditingController();
    final workerId = booking['worker_id']?.toString();
    final bookingId = booking['id'].toString();
    final serviceType = booking['service_type']?.toString() ?? 'Service';
    final worker = booking['worker'] as Map<String, dynamic>?;
    final workerName = worker?['name']?.toString() ?? 'Service Provider';

    if (workerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Worker information not available')),
      );
      return;
    }

    // Check if booking is completed
    final status = (booking['status']?.toString() ?? '').toLowerCase();
    if (status != 'completed') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You can only rate completed services'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            padding: const EdgeInsets.all(24),
            constraints: const BoxConstraints(maxWidth: 400),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: accent.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.star, color: accent, size: 32),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Rate Your Experience',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              workerName,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                            Text(
                              serviceType,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  
                  // Rating Question
                  const Text(
                    'How would you rate this service?',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Star Rating
                  Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (index) {
                        return GestureDetector(
                          onTap: () {
                            setDialogState(() => rating = index + 1);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.all(8),
                            child: Icon(
                              index < rating ? Icons.star : Icons.star_border,
                              color: Colors.amber,
                              size: 48,
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                  
                  // Rating Label
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        rating == 0
                            ? 'Tap to rate'
                            : rating == 1
                                ? 'Poor'
                                : rating == 2
                                    ? 'Fair'
                                    : rating == 3
                                        ? 'Good'
                                        : rating == 4
                                            ? 'Very Good'
                                            : 'Excellent',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: rating == 0
                              ? Colors.grey[400]
                              : rating <= 2
                                  ? Colors.red
                                  : rating == 3
                                      ? Colors.orange
                                      : Colors.green,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Comment Section
                  const Text(
                    'Share your experience (optional)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: commentController,
                    decoration: InputDecoration(
                      hintText: 'What did you like? What could be improved?',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                      contentPadding: const EdgeInsets.all(16),
                    ),
                    maxLines: 4,
                    maxLength: 500,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your feedback helps improve service quality for everyone',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.grey[300]!),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text(
                            'Skip',
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: rating > 0
                              ? () async {
                                  final user = supa.auth.currentUser;
                                  if (user == null) {
                                    Navigator.pop(ctx);
                                    return;
                                  }

                                  try {
                                    await supa.from('ratings').insert({
                                      'booking_id': bookingId,
                                      'worker_id': workerId,
                                      'rater_id': user.id,
                                      'score': rating,
                                      'comment': commentController.text.trim().isEmpty
                                          ? null
                                          : commentController.text.trim(),
                                    });

                                    if (mounted) {
                                      Navigator.pop(ctx);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Thank you! Your rating helps improve service quality.'),
                                          backgroundColor: Colors.green,
                                          duration: Duration(seconds: 3),
                                        ),
                                      );
                                      _loadBookings();
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      Navigator.pop(ctx);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Error submitting rating: $e'),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    }
                                  }
                                }
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            elevation: rating > 0 ? 2 : 0,
                          ),
                          child: const Text(
                            'Submit Rating',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
                  ),
      ),
    );
  }

  Future<void> _cancelBooking(String bookingId) async {
    // Get current booking status
    final booking = _allBookings.firstWhere(
      (b) => b['id'].toString() == bookingId,
      orElse: () => {},
    );
    
    final currentStatus = booking['status']?.toString();
    
    // Show cancellation dialog
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => CancellationDialog(
        isClient: true,
        currentStatus: currentStatus,
        bookingId: bookingId,
      ),
    );

    if (result == null || result['confirmed'] != true) return;

    // Check if user has exceeded cancellation limit
    final user = supa.auth.currentUser;
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
                'You have exceeded the cancellation limit for this month. Please contact support if you need assistance.',
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
      final cancellationResult = await BookingCancellationService.cancelByClient(
        bookingId: bookingId,
        reason: result['reason']?.toString(),
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
}
