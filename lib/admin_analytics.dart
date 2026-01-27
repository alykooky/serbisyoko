import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminAnalytics extends StatefulWidget {
  const AdminAnalytics({Key? key}) : super(key: key);

  @override
  State<AdminAnalytics> createState() => _AdminAnalyticsState();
}

class _AdminAnalyticsState extends State<AdminAnalytics> {
  Map<String, dynamic> _analytics = {};
  bool _isLoading = true;
  String _selectedPeriod = '7d';

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  Future<void> _loadAnalytics() async {
    try {
      setState(() {
        _isLoading = true;
      });

      final now = DateTime.now();
      final days = int.parse(_selectedPeriod.replaceAll('d', ''));
      final startDate = now.subtract(Duration(days: days));

      // Load data individually to avoid Future.wait issues
      final userRegistrations = await Supabase.instance.client
          .from('users')
          .select('id, created_at')
          .gte('created_at', startDate.toIso8601String());

      final workerVerifications = await Supabase.instance.client
          .from('worker_profiles')
          .select('id, verified_at')
          .gte('verified_at', startDate.toIso8601String());

      final totalBookings = await Supabase.instance.client
          .from('bookings')
          .select('id, created_at')
          .gte('created_at', startDate.toIso8601String());

      final completedBookings = await Supabase.instance.client
          .from('bookings')
          .select('id, created_at')
          .eq('status', 'Completed')
          .gte('created_at', startDate.toIso8601String());

      final revenueData = await Supabase.instance.client
          .from('bookings')
          .select('estimated_price')
          .eq('status', 'Completed')
          .gte('created_at', startDate.toIso8601String());

      // Calculate revenue
      final totalRevenue = revenueData.fold<int>(0, (sum, booking) {
        return sum + (booking['estimated_price'] as int? ?? 0);
      });

      setState(() {
        _analytics = {
          'userRegistrations': userRegistrations.length,
          'workerVerifications': workerVerifications.length,
          'totalBookings': totalBookings.length,
          'completedBookings': completedBookings.length,
          'totalRevenue': totalRevenue,
          'completionRate': totalBookings.length > 0
              ? (completedBookings.length / totalBookings.length * 100)
                  .toStringAsFixed(1)
              : '0.0',
        };
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading analytics: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildMetricCard(
      String title, String value, IconData icon, Color color, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 24),
              const Spacer(),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartCard(String title, Widget content) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          content,
        ],
      ),
    );
  }

  Widget _buildProgressBar(String label, double value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text('${(value * 100).toStringAsFixed(1)}%'),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: value,
          backgroundColor: Colors.grey[200],
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Platform Analytics'),
        backgroundColor: const Color(0xFFED9121),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          DropdownButton<String>(
            value: _selectedPeriod,
            items: const [
              DropdownMenuItem(value: '7d', child: Text('Last 7 days')),
              DropdownMenuItem(value: '30d', child: Text('Last 30 days')),
              DropdownMenuItem(value: '90d', child: Text('Last 90 days')),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _selectedPeriod = value;
                });
                _loadAnalytics();
              }
            },
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFED9121)),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Key Metrics
                  const Text(
                    'Key Metrics',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFED9121),
                    ),
                  ),
                  const SizedBox(height: 16),

                  GridView.count(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 1.2,
                    children: [
                      _buildMetricCard(
                        'New Users',
                        _analytics['userRegistrations']?.toString() ?? '0',
                        Icons.people,
                        Colors.blue,
                        'registrations',
                      ),
                      _buildMetricCard(
                        'Verified Workers',
                        _analytics['workerVerifications']?.toString() ?? '0',
                        Icons.verified_user,
                        Colors.green,
                        'verifications',
                      ),
                      _buildMetricCard(
                        'Total Bookings',
                        _analytics['totalBookings']?.toString() ?? '0',
                        Icons.book_online,
                        Colors.purple,
                        'bookings',
                      ),
                      _buildMetricCard(
                        'Revenue',
                        '₱${_analytics['totalRevenue']?.toString() ?? '0'}',
                        Icons.attach_money,
                        Colors.orange,
                        'earnings',
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Performance Metrics
                  _buildChartCard(
                    'Performance Metrics',
                    Column(
                      children: [
                        _buildProgressBar(
                          'Booking Completion Rate',
                          double.tryParse(
                                  _analytics['completionRate'] ?? '0')! /
                              100,
                          Colors.green,
                        ),
                        const SizedBox(height: 16),
                        _buildProgressBar(
                          'Worker Verification Rate',
                          _analytics['workerVerifications'] > 0
                              ? (_analytics['workerVerifications'] /
                                  (_analytics['workerVerifications'] +
                                      5)) // Assuming 5 pending
                              : 0.0,
                          Colors.blue,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Activity Summary
                  _buildChartCard(
                    'Activity Summary',
                    Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Completed Bookings',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    '${_analytics['completedBookings'] ?? 0}',
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Pending Bookings',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    '${(_analytics['totalBookings'] ?? 0) - (_analytics['completedBookings'] ?? 0)}',
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Insights
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue[200]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.lightbulb,
                                color: Colors.blue[600], size: 24),
                            const SizedBox(width: 8),
                            Text(
                              'Insights',
                              style: TextStyle(
                                color: Colors.blue[700],
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _getInsights(),
                          style: TextStyle(
                            color: Colors.blue[600],
                            fontSize: 14,
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

  String _getInsights() {
    final userRegistrations = _analytics['userRegistrations'] ?? 0;
    final completedBookings = _analytics['completedBookings'] ?? 0;
    final completionRate =
        double.tryParse(_analytics['completionRate'] ?? '0') ?? 0;

    if (userRegistrations > 10) {
      return 'Great user growth! Consider expanding verification capacity.';
    } else if (completionRate > 80) {
      return 'Excellent booking completion rate! Users are highly satisfied.';
    } else if (completedBookings < 5) {
      return 'Low booking activity. Consider promotional campaigns.';
    } else {
      return 'Platform is performing well. Monitor key metrics for optimization opportunities.';
    }
  }
}
