// lib/worker_calendar_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class WorkerCalendarScreen extends StatefulWidget {
  const WorkerCalendarScreen({super.key});

  @override
  State<WorkerCalendarScreen> createState() => _WorkerCalendarScreenState();
}

class _WorkerCalendarScreenState extends State<WorkerCalendarScreen> {
  final _supabase = Supabase.instance.client;
  bool _loading = true;
  
  // Current month/year being displayed
  DateTime _currentMonth = DateTime.now();
  
  // Map of date -> list of bookings for that day
  final Map<String, List<Map<String, dynamic>>> _bookingsByDate = {};
  
  // Selected date and its bookings
  DateTime? _selectedDate;
  List<Map<String, dynamic>> _selectedDateBookings = [];

  @override
  void initState() {
    super.initState();
    _loadBookings();
  }

  Future<void> _loadBookings() async {
    setState(() => _loading = true);
    
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      // Fetch all bookings for this worker (past and future)
      final bookings = await _supabase
          .from('bookings')
          .select('''
            id, service_type, scheduled_time, status, price,
            client:client_id ( id, name, first_name, last_name )
          ''')
          .eq('worker_id', user.id)
          .order('scheduled_time', ascending: true);

      // Group bookings by date
      _bookingsByDate.clear();
      for (final booking in bookings) {
        final scheduledTimeStr = booking['scheduled_time']?.toString();
        if (scheduledTimeStr == null) continue;
        
        final scheduledTime = DateTime.tryParse(scheduledTimeStr);
        if (scheduledTime == null) continue;
        
        // Get date key (YYYY-MM-DD)
        final dateKey = DateFormat('yyyy-MM-dd').format(scheduledTime);
        
        // Get client name
        final client = booking['client'];
        String clientName = 'Unknown Client';
        if (client != null) {
          if (client['name'] != null) {
            clientName = client['name'].toString();
          } else if (client['first_name'] != null || client['last_name'] != null) {
            clientName = '${client['first_name'] ?? ''} ${client['last_name'] ?? ''}'.trim();
          }
        }
        
        final bookingData = Map<String, dynamic>.from(booking);
        bookingData['scheduled_time_parsed'] = scheduledTime;
        bookingData['client_name'] = clientName;
        
        (_bookingsByDate[dateKey] ??= []).add(bookingData);
      }

      if (mounted) {
        setState(() {
          _loading = false;
          // Select today if available
          final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
          if (_bookingsByDate.containsKey(todayKey)) {
            _selectedDate = DateTime.now();
            _selectedDateBookings = _bookingsByDate[todayKey] ?? [];
          }
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading bookings: $e');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  // Get bookings for a specific date
  List<Map<String, dynamic>> _getBookingsForDate(DateTime date) {
    final dateKey = DateFormat('yyyy-MM-dd').format(date);
    return _bookingsByDate[dateKey] ?? [];
  }

  // Get status color
  Color _getStatusColor(String? status) {
    final s = (status ?? '').toLowerCase();
    switch (s) {
      case 'completed':
        return Colors.green;
      case 'accepted':
      case 'inprogress':
        return Colors.blue;
      case 'pending':
        return Colors.orange;
      case 'cancelled':
      case 'declined':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  // Build calendar month view
  Widget _buildCalendar() {
    final year = _currentMonth.year;
    final month = _currentMonth.month;
    final firstDay = DateTime(year, month, 1);
    final lastDay = DateTime(year, month + 1, 0);
    final firstWeekday = firstDay.weekday; // 1 = Monday, 7 = Sunday
    
    // Get all days in month
    final daysInMonth = lastDay.day;
    final days = List.generate(daysInMonth, (i) => DateTime(year, month, i + 1));
    
    // Pad start to align with weekday
    final padding = firstWeekday - 1;
    final paddedDays = List<DateTime?>.generate(padding, (_) => null)..addAll(days);

    return Column(
      children: [
        // Month navigation
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () {
                setState(() {
                  _currentMonth = DateTime(year, month - 1, 1);
                });
              },
            ),
            Text(
              DateFormat('MMMM yyyy').format(_currentMonth),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () {
                setState(() {
                  _currentMonth = DateTime(year, month + 1, 1);
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        
        // Weekday headers
        Row(
          children: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
              .map((day) => Expanded(
                    child: Center(
                      child: Text(
                        day,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 8),
        
        // Calendar grid
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            childAspectRatio: 1.2,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
          ),
          itemCount: paddedDays.length,
          itemBuilder: (context, index) {
            final day = paddedDays[index];
            if (day == null) {
              return const SizedBox.shrink();
            }

            final isToday = day.year == DateTime.now().year &&
                           day.month == DateTime.now().month &&
                           day.day == DateTime.now().day;
            final isSelected = _selectedDate != null &&
                              day.year == _selectedDate!.year &&
                              day.month == _selectedDate!.month &&
                              day.day == _selectedDate!.day;
            final bookings = _getBookingsForDate(day);
            final hasBookings = bookings.isNotEmpty;

            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedDate = day;
                  _selectedDateBookings = bookings;
                });
              },
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFFED9121)
                      : isToday
                          ? Colors.orange.withOpacity(0.2)
                          : Colors.transparent,
                  border: Border.all(
                    color: isToday ? Colors.orange : Colors.grey.shade300,
                    width: isToday ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${day.day}',
                      style: TextStyle(
                        fontWeight: isSelected || isToday ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? Colors.white : Colors.black87,
                        fontSize: 14,
                      ),
                    ),
                    if (hasBookings)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.white : Colors.orange,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${bookings.length}',
                          style: TextStyle(
                            color: isSelected ? const Color(0xFFED9121) : Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // Build bookings list for selected date
  Widget _buildBookingsList() {
    if (_selectedDate == null) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Center(
          child: Text(
            'Select a date to view bookings',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ),
      );
    }

    if (_selectedDateBookings.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.event_busy, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 8),
              Text(
                'No bookings on ${DateFormat('MMM d, yyyy').format(_selectedDate!)}',
                style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 4),
              Text(
                'You are free this day!',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _selectedDateBookings.length,
      itemBuilder: (context, index) {
        final booking = _selectedDateBookings[index];
        final scheduledTime = booking['scheduled_time_parsed'] as DateTime;
        final status = booking['status']?.toString() ?? 'unknown';
        final serviceType = booking['service_type']?.toString() ?? 'Service';
        final clientName = booking['client_name']?.toString() ?? 'Unknown Client';
        final price = booking['price'] ?? booking['estimated_price'] ?? 0;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ListTile(
            leading: Container(
              width: 4,
              decoration: BoxDecoration(
                color: _getStatusColor(status),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            title: Text(
              serviceType,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Client: $clientName'),
                Text('Time: ${DateFormat('h:mm a').format(scheduledTime)}'),
                if (price > 0) Text('Price: ₱${price.toStringAsFixed(2)}'),
              ],
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _getStatusColor(status).withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                status.toUpperCase(),
                style: TextStyle(
                  color: _getStatusColor(status),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            onTap: () {
              // Navigate to booking details
              // You can add navigation here if needed
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFED9121);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Calendar'),
        backgroundColor: accent,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: accent))
          : RefreshIndicator(
              onRefresh: _loadBookings,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildCalendar(),
                    const SizedBox(height: 24),
                    const Text(
                      'Bookings',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildBookingsList(),
                  ],
                ),
              ),
            ),
    );
  }
}


