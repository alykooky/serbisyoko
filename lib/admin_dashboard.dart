import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_verification_dashboard.dart';
import 'admin_user_management.dart';
import 'admin_analytics.dart';
import 'admin_settings.dart';
import 'admin_audit_logs_screen.dart';
import 'login.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({Key? key}) : super(key: key);

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _selectedIndex = 0;
  String _adminName = 'Admin';
  String _adminEmail = '';
  bool _isLoading = true;
  bool _isAuthenticated = false;
  Map<String, dynamic> _stats = {};
  DateTime? _lastActivity;
  bool _redirected = false;

  @override
  void initState() {
    super.initState();
    _initializeAdmin();
  }

  Future<void> _initializeAdmin() async {
    try {
      setState(() {
        _isLoading = true;
      });

      // Verify admin authentication
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        _redirectToLogin();
        return;
      }

      // Verify admin role
      final userResponse = await Supabase.instance.client
          .from('users')
          .select('name, email, role, created_at')
          .eq('id', user.id)
          .single();

      if (userResponse == null || userResponse['role'] != 'Admin') {
        _showSecurityAlert('Unauthorized access detected');
        _redirectToLogin();
        return;
      }

      // Load admin info and stats
      await Future.wait([
        _loadAdminInfo(userResponse),
        _loadDashboardStats(),
      ]);

      setState(() {
        _isAuthenticated = true;
        _lastActivity = DateTime.now();
        _isLoading = false;
      });

      // Immediately route admins to the Verification workspace (single-purpose admin)
      if (!_redirected && mounted) {
        _redirected = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (_) => const AdminVerificationDashboard()),
          );
        });
      }
    } catch (e) {
      print('Error initializing admin: $e');
      _showSecurityAlert('Authentication failed: $e');
      _redirectToLogin();
    }
  }

  Future<void> _loadAdminInfo(Map<String, dynamic> userData) async {
    setState(() {
      _adminName = userData['name'] ?? 'Admin';
      _adminEmail = userData['email'] ?? '';
    });
  }

  Future<void> _loadDashboardStats() async {
    try {
      // Load comprehensive statistics individually
      final totalUsers =
          await Supabase.instance.client.from('users').select('id');

      final pendingVerifications = await Supabase.instance.client
          .from('worker_profiles')
          .select('id')
          .eq('verification_status', 'pending');

      final verifiedWorkers = await Supabase.instance.client
          .from('worker_profiles')
          .select('id')
          .eq('is_verified', true);

      final totalBookings =
          await Supabase.instance.client.from('bookings').select('id');

      final recentActivity = await Supabase.instance.client
          .from('bookings')
          .select('id')
          .gte(
              'created_at',
              DateTime.now()
                  .subtract(const Duration(hours: 24))
                  .toIso8601String());

      setState(() {
        _stats = {
          'totalUsers': totalUsers.length,
          'pendingVerifications': pendingVerifications.length,
          'verifiedWorkers': verifiedWorkers.length,
          'totalBookings': totalBookings.length,
          'recentActivity': recentActivity.length,
        };
      });
    } catch (e) {
      print('Error loading stats: $e');
    }
  }

  void _showSecurityAlert(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  void _redirectToLogin() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const SignInScreen()),
      (route) => false,
    );
  }

  void _updateLastActivity() {
    setState(() {
      _lastActivity = DateTime.now();
    });
  }

  void _onItemTapped(int index) {
    _updateLastActivity();
    setState(() {
      _selectedIndex = index;
    });
    // Navigate to corresponding admin section
    switch (index) {
      case 1:
        _navigateToScreen(const AdminVerificationDashboard());
        break;
      case 2:
        _navigateToScreen(const AdminUserManagement());
        break;
      case 3:
        _navigateToScreen(const AdminAnalytics());
        break;
      case 4:
        _navigateToScreen(const AdminSettings());
        break;
      default:
        break; // Dashboard stays on this screen
    }
  }

  Future<void> _logout() async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await Supabase.instance.client.auth.signOut();
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const SignInScreen()),
            (route) => false,
          );
        }
      } catch (e) {
        _showSecurityAlert('Logout failed: $e');
      }
    }
  }

  Future<void> _refreshData() async {
    _updateLastActivity();
    await _loadDashboardStats();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Data refreshed successfully'),
        backgroundColor: Color(0xFFED9121),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _navigateToScreen(Widget screen) {
    _updateLastActivity();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => screen),
    );
  }

  Widget _buildDashboardContent() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFED9121)),
            ),
            SizedBox(height: 16),
            Text('Loading admin dashboard...'),
          ],
        ),
      );
    }

    if (!_isAuthenticated) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.security, size: 64, color: Colors.red),
            SizedBox(height: 16),
            Text(
              'Authentication Required',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text('Please login to access admin features'),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshData,
      color: const Color(0xFFED9121),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Enhanced Welcome Card with Security Info
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFED9121), Color(0xFFFFB366)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.orange.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.admin_panel_settings,
                        color: Colors.white,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Admin Dashboard',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Welcome back, $_adminName!',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.security, color: Colors.white, size: 16),
                            SizedBox(width: 4),
                            Text(
                              'Secure',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _adminEmail,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                  if (_lastActivity != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Last activity: ${_formatTime(_lastActivity!)}',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Real-time Stats
            const Text(
              'Platform Overview',
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
                _buildStatCard(
                  'Total Users',
                  _stats['totalUsers']?.toString() ?? '0',
                  Icons.people,
                  Colors.blue,
                  _stats['totalUsers'] ?? 0,
                ),
                _buildStatCard(
                  'Pending Verification',
                  _stats['pendingVerifications']?.toString() ?? '0',
                  Icons.pending_actions,
                  Colors.orange,
                  _stats['pendingVerifications'] ?? 0,
                ),
                _buildStatCard(
                  'Verified Workers',
                  _stats['verifiedWorkers']?.toString() ?? '0',
                  Icons.verified_user,
                  Colors.green,
                  _stats['verifiedWorkers'] ?? 0,
                ),
                _buildStatCard(
                  'Total Bookings',
                  _stats['totalBookings']?.toString() ?? '0',
                  Icons.book_online,
                  Colors.purple,
                  _stats['totalBookings'] ?? 0,
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Recent Activity
            Container(
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
                      const Icon(Icons.trending_up, color: Color(0xFFED9121)),
                      const SizedBox(width: 8),
                      const Text(
                        'Recent Activity (24h)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${_stats['recentActivity'] ?? 0} activities',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: (_stats['recentActivity'] ?? 0) / 100.0,
                    backgroundColor: Colors.grey[200],
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Color(0xFFED9121)),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Admin Actions
            const Text(
              'Admin Actions',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFFED9121),
              ),
            ),
            const SizedBox(height: 16),

            _buildActionCard(
              'Worker Verification',
              'Review and approve worker verification documents',
              Icons.verified_user,
              Colors.green,
              () => _navigateToScreen(const AdminVerificationDashboard()),
              badge: _stats['pendingVerifications'] ?? 0,
            ),

            const SizedBox(height: 12),

            _buildActionCard(
              'User Management',
              'Manage users, roles, and permissions',
              Icons.people_alt,
              Colors.blue,
              () => _navigateToScreen(const AdminUserManagement()),
            ),

            const SizedBox(height: 12),

            _buildActionCard(
              'Platform Analytics',
              'View platform usage and performance metrics',
              Icons.analytics,
              Colors.purple,
              () => _navigateToScreen(const AdminAnalytics()),
            ),

            const SizedBox(height: 12),

            _buildActionCard(
              'System Settings',
              'Configure platform settings and preferences',
              Icons.settings,
              Colors.grey,
              () => _navigateToScreen(const AdminSettings()),
            ),

            const SizedBox(height: 12),

            _buildActionCard(
              'Audit Logs',
              'View all admin actions and system activity logs',
              Icons.description,
              Colors.orange,
              () => _navigateToScreen(const AdminAuditLogsScreen()),
            ),

            const SizedBox(height: 24),

            // Security Notice
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.security, color: Colors.blue[600], size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Security Notice',
                          style: TextStyle(
                            color: Colors.blue[700],
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'All admin actions are logged and monitored for security purposes.',
                          style: TextStyle(
                            color: Colors.blue[600],
                            fontSize: 12,
                          ),
                        ),
                      ],
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

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  Widget _buildStatCard(
      String title, String value, IconData icon, Color color, int count) {
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
              if (count > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    count.toString(),
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
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
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(
    String title,
    String description,
    IconData icon,
    Color color,
    VoidCallback onTap, {
    int badge = 0,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (badge > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            badge.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              color: Colors.grey[400],
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        backgroundColor: const Color(0xFFED9121),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _refreshData,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Data',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'logout') {
                _logout();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    const Icon(Icons.logout, color: Colors.red),
                    const SizedBox(width: 8),
                    const Text('Logout'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _buildDashboardContent(),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        selectedItemColor: const Color(0xFFED9121),
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.verified_user),
            label: 'Verification',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people),
            label: 'Users',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.analytics),
            label: 'Analytics',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
