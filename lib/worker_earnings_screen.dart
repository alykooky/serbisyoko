import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class WorkerEarningsScreen extends StatefulWidget {
  const WorkerEarningsScreen({super.key});

  @override
  State<WorkerEarningsScreen> createState() => _WorkerEarningsScreenState();
}

class _WorkerEarningsScreenState extends State<WorkerEarningsScreen> {
  final _sb = Supabase.instance.client;
  bool _loading = true;
  
  // Earnings data
  double _todayEarnings = 0.0;
  double _weekEarnings = 0.0;
  double _monthEarnings = 0.0;
  int _completedJobs = 0;
  
  // Detailed earnings list
  List<Map<String, dynamic>> _completedBookings = [];

  @override
  void initState() {
    super.initState();
    _loadEarnings();
  }

  Future<void> _loadEarnings() async {
    setState(() => _loading = true);
    try {
      final user = _sb.auth.currentUser;
      if (user == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final weekStart = now.subtract(Duration(days: now.weekday - 1));
      final monthStart = DateTime(now.year, now.month, 1);

      // Fetch all bookings for this worker
      final bookingsData = await _sb
          .from('bookings')
          .select()
          .eq('worker_id', user.id)
          .order('scheduled_time', ascending: false);

      // Filter for completed bookings (case-insensitive)
      final allBookings = (bookingsData as List)
          .map((b) => Map<String, dynamic>.from(b))
          .toList();
      
      final bookings = allBookings.where((booking) {
        final status = (booking['status']?.toString() ?? '').toLowerCase();
        return status == 'completed';
      }).toList();

      // Calculate earnings
      double todayTotal = 0.0;
      double weekTotal = 0.0;
      double monthTotal = 0.0;
      int completedCount = 0;

      for (final booking in bookings) {
        final scheduledTimeStr = booking['scheduled_time']?.toString();
        final scheduledTime = scheduledTimeStr != null
            ? DateTime.tryParse(scheduledTimeStr)
            : null;

        if (scheduledTime == null) continue;

        // Get price (prefer price, fallback to estimated_price)
        final price = (booking['price'] as num?)?.toDouble() ??
            (booking['estimated_price'] as num?)?.toDouble() ??
            0.0;

        if (price <= 0) continue;

        completedCount++;

        // Calculate by period
        if (scheduledTime.isAfter(todayStart)) {
          todayTotal += price;
        }
        if (scheduledTime.isAfter(weekStart.subtract(const Duration(seconds: 1)))) {
          weekTotal += price;
        }
        if (scheduledTime.isAfter(monthStart.subtract(const Duration(seconds: 1)))) {
          monthTotal += price;
        }
      }

      if (mounted) {
        setState(() {
          _todayEarnings = todayTotal;
          _weekEarnings = weekTotal;
          _monthEarnings = monthTotal;
          _completedJobs = completedCount;
          _completedBookings = bookings;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading earnings: $e');
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading earnings: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  double _getBookingPrice(Map<String, dynamic> booking) {
    final price = (booking['price'] as num?)?.toDouble() ??
        (booking['estimated_price'] as num?)?.toDouble() ??
        0.0;
    return price;
  }

  String _formatDate(DateTime date) {
    return DateFormat('MMM dd, yyyy').format(date);
  }

  String _formatTime(DateTime date) {
    return DateFormat('hh:mm a').format(date);
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFED9121);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Earnings'),
        backgroundColor: accent,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadEarnings,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Summary Cards
                    _buildSummaryCard(
                      'Today\'s Earnings',
                      _todayEarnings,
                      Icons.today,
                      Colors.orange,
                    ),
                    const SizedBox(height: 12),
                    _buildSummaryCard(
                      'This Week',
                      _weekEarnings,
                      Icons.calendar_view_week,
                      Colors.blue,
                    ),
                    const SizedBox(height: 12),
                    _buildSummaryCard(
                      'This Month',
                      _monthEarnings,
                      Icons.calendar_month,
                      Colors.green,
                    ),
                    const SizedBox(height: 12),
                    _buildSummaryCard(
                      'Completed Jobs',
                      _completedJobs.toDouble(),
                      Icons.check_circle,
                      accent,
                      isCount: true,
                    ),
                    const SizedBox(height: 24),
                    
                    // Divider
                    const Divider(height: 32),
                    
                    // Completed Jobs List
                    const Text(
                      'Completed Jobs',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    _completedBookings.isEmpty
                        ? _buildEmptyState()
                        : ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _completedBookings.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final booking = _completedBookings[index];
                              return _buildJobCard(booking);
                            },
                          ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSummaryCard(String title, double value, IconData icon, Color color, {bool isCount = false}) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isCount
                        ? '${value.toInt()} jobs'
                        : '₱${value.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJobCard(Map<String, dynamic> booking) {
    const accent = Color(0xFFED9121);
    
    final scheduledTimeStr = booking['scheduled_time']?.toString();
    final scheduledTime = scheduledTimeStr != null
        ? DateTime.tryParse(scheduledTimeStr)
        : null;
    
    final serviceType = booking['service_type']?.toString() ?? 'Service';
    final price = _getBookingPrice(booking);
    
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: accent.withOpacity(0.1),
          child: Icon(Icons.work, color: accent),
        ),
        title: Text(
          serviceType,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        subtitle: scheduledTime != null
            ? Text(
                '${_formatDate(scheduledTime)} • ${_formatTime(scheduledTime)}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              )
            : null,
        trailing: Text(
          '₱${price.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.green[700],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No completed jobs yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Complete jobs to see your earnings here',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

