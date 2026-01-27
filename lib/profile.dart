import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'login.dart';
import 'referral_screen.dart';
import 'worker_profile_edit.dart';
import 'screens/manage_skills_screen.dart';
import 'screens/client_profile_edit_screen.dart';
import 'screens/notifications_screen.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Map<String, dynamic>? _userProfile;
  Map<String, dynamic>? _workerProfile;
  bool _isLoading = true;
  String _userRole = '';
  
  // Portfolio and Ratings data
  List<Map<String, dynamic>> _completedBookings = [];
  List<Map<String, dynamic>> _ratings = [];
  double _averageRating = 0.0;
  int _totalRatings = 0;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    setState(() => _isLoading = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final userProfile = await Supabase.instance.client
          .from('users')
          .select('*')
          .eq('id', user.id)
          .single();

      _userRole = userProfile['role'] as String? ?? '';

      if (_userRole == 'Worker') {
        final workerProfile = await Supabase.instance.client
            .from('worker_profiles')
            .select('*')
            .eq('user_id', user.id)
            .maybeSingle();

        setState(() {
          _userProfile = userProfile;
          _workerProfile = workerProfile;
        });
        // Load portfolio and ratings after profile is loaded
        _loadPortfolioAndRatings();
      } else {
        setState(() {
          _userProfile = userProfile;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading profile: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadPortfolioAndRatings() async {
    if (_userRole != 'Worker') return;
    
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      // Fetch completed bookings for portfolio
      final bookingsData = await Supabase.instance.client
          .from('bookings')
          .select('id, service_type, scheduled_time, status, problem_details')
          .eq('worker_id', user.id)
          .order('scheduled_time', ascending: false);

      final allBookings = (bookingsData as List)
          .map((b) => Map<String, dynamic>.from(b))
          .toList();

      final completed = allBookings.where((booking) {
        final status = (booking['status']?.toString() ?? '').toLowerCase();
        return status == 'completed';
      }).take(5).toList(); // Show only last 5 completed jobs

      // Fetch ratings
      final ratingsData = await Supabase.instance.client
          .from('ratings')
          .select('''
            id, score, comment, created_at, booking_id,
            rater:rater_id ( id, name )
          ''')
          .eq('worker_id', user.id)
          .order('created_at', ascending: false);

      final ratings = (ratingsData as List)
          .map((r) => Map<String, dynamic>.from(r))
          .toList();

      // Calculate average rating
      double avgRating = 0.0;
      if (ratings.isNotEmpty) {
        final scores = ratings
            .map((r) => r['score'] as int?)
            .where((s) => s != null)
            .cast<int>()
            .toList();
        if (scores.isNotEmpty) {
          avgRating = scores.reduce((a, b) => a + b) / scores.length;
        }
      }

      if (mounted) {
        setState(() {
          _completedBookings = completed;
          _ratings = ratings.take(3).toList(); // Show only last 3 ratings
          _averageRating = avgRating;
          _totalRatings = ratings.length;
        });
      }
    } catch (e) {
      debugPrint('Error loading portfolio and ratings: $e');
    }
  }

  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await Supabase.instance.client.auth.signOut();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const SignInScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFED9121);

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_userProfile == null) {
      return const Scaffold(
        body: Center(child: Text('Error loading profile')),
      );
    }

    final displayName = (_userProfile!['name'] as String?) ?? '';
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(_userRole == 'Worker' ? 'Worker Profile' : 'Profile'),
        backgroundColor: accent,
        foregroundColor: Colors.white,
        centerTitle: true,
        actions: [
          if (_userRole == 'Worker')
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const WorkerProfileEditScreen(),
                  ),
                );
                if (result == true) {
                  // Refresh profile after edit
                  _loadUserProfile();
                  _loadPortfolioAndRatings();
                }
              },
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ==== Profile Header ====
            CircleAvatar(
              radius: 60,
              backgroundColor: accent,
              child: Text(
                initial,
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              displayName.isEmpty ? 'Unknown User' : displayName,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            Text(
              (_userProfile!['email'] as String?) ?? '',
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
            if (_userRole == 'Worker' && _workerProfile != null) ...[
              const SizedBox(height: 4),
              Text(
                (_workerProfile!['about'] as String?) ?? 'Service Provider',
                style: const TextStyle(fontSize: 16, color: Colors.grey),
              ),
              if (_workerProfile!['hourly_rate'] != null) ...[
                const SizedBox(height: 4),
                Text(
                  '₱${_workerProfile!['hourly_rate']} / hour',
                  style: const TextStyle(
                    fontSize: 16,
                    color: accent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ],
            const SizedBox(height: 20),

            // ==== Verification (workers) ====
            if (_userRole == 'Worker' && _workerProfile != null)
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  leading: Icon(
                    _workerProfile!['is_verified'] == true
                        ? Icons.verified
                        : Icons.pending,
                    color: _workerProfile!['is_verified'] == true
                        ? Colors.green
                        : Colors.orange,
                  ),
                  title: Text(
                    _workerProfile!['is_verified'] == true
                        ? 'Verified Identity'
                        : 'Pending Verification',
                  ),
                  subtitle: Text(
                    _workerProfile!['is_verified'] == true
                        ? 'ID and Certificates approved by Admin'
                        : 'Complete verification to get verified',
                  ),
                ),
              ),
            const SizedBox(height: 16),

            // ==== Portfolio ====
            // Only show portfolio section if worker has completed bookings
            if (_userRole == 'Worker' && _completedBookings.isNotEmpty) ...[
              sectionTitle('Portfolio'),
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                        children: [
                          ...List.generate(_completedBookings.length, (index) {
                            final booking = _completedBookings[index];
                            final serviceType = booking['service_type']?.toString() ?? 'Service';
                            final scheduledTime = booking['scheduled_time']?.toString();
                            DateTime? completedDate;
                            if (scheduledTime != null) {
                              completedDate = DateTime.tryParse(scheduledTime);
                            }
                            final formattedDate = completedDate != null
                                ? DateFormat('MMM dd, yyyy').format(completedDate)
                                : 'Date not available';

                            IconData serviceIcon;
                            Color iconColor;
                            switch (serviceType.toLowerCase()) {
                              case 'aircon':
                              case 'aircon technician':
                                serviceIcon = Icons.ac_unit;
                                iconColor = Colors.orange;
                                break;
                              case 'plumber':
                              case 'plumbing':
                                serviceIcon = Icons.plumbing;
                                iconColor = Colors.blue;
                                break;
                              case 'electrician':
                              case 'electrical':
                                serviceIcon = Icons.electrical_services;
                                iconColor = Colors.yellow[700]!;
                                break;
                              case 'cleaning':
                                serviceIcon = Icons.cleaning_services;
                                iconColor = Colors.green;
                                break;
                              default:
                                serviceIcon = Icons.build;
                                iconColor = Colors.blue;
                            }

                            return Column(
                              children: [
                                if (index > 0) const Divider(),
                                ListTile(
                                  leading: Icon(serviceIcon, color: iconColor),
                                  title: Text(serviceType),
                                  subtitle: Text('Completed on $formattedDate'),
                                ),
                              ],
                            );
                          }),
                        ],
                      ),
              ),
              const SizedBox(height: 16),
            ],

            // ==== Rewards & Referrals (moved out, not const) ====
            sectionTitle('Rewards & Credits'),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                leading: const Icon(Icons.card_giftcard, color: accent),
                title: const Text('Referral & Credits'),
                subtitle: const Text('Invite friends • Get ₱50'),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ReferralScreen(),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            // ==== Ratings & Feedback ====
            if (_userRole == 'Worker')
              sectionTitle('Ratings & Feedback'),
            if (_userRole == 'Worker')
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.star, color: Colors.amber),
                      title: const Text('Overall Rating'),
                      subtitle: Text(
                        _totalRatings == 0
                            ? 'No ratings yet'
                            : '${_averageRating.toStringAsFixed(1)} ★ based on $_totalRatings review${_totalRatings == 1 ? '' : 's'}',
                      ),
                    ),
                    if (_ratings.isNotEmpty) ...[
                      ...List.generate(_ratings.length, (index) {
                        final rating = _ratings[index];
                        final score = rating['score'] as int? ?? 0;
                        final comment = rating['comment']?.toString();
                        final createdAt = rating['created_at']?.toString();
                        final rater = rating['rater'] as Map<String, dynamic>?;
                        final clientName = rater?['name']?.toString() ?? 'Anonymous';
                        
                        DateTime? reviewDate;
                        if (createdAt != null) {
                          reviewDate = DateTime.tryParse(createdAt);
                        }
                        String timeAgo = 'Recently';
                        if (reviewDate != null) {
                          final now = DateTime.now();
                          final difference = now.difference(reviewDate);
                          if (difference.inDays == 0) {
                            timeAgo = 'Today';
                          } else if (difference.inDays == 1) {
                            timeAgo = 'Yesterday';
                          } else if (difference.inDays < 7) {
                            timeAgo = '${difference.inDays} days ago';
                          } else {
                            timeAgo = DateFormat('MMM dd, yyyy').format(reviewDate);
                          }
                        }

                        return Column(
                          children: [
                            const Divider(),
                            ListTile(
                              leading: const Icon(Icons.person, color: Colors.grey),
                              title: Text('Customer: $clientName'),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: List.generate(5, (i) {
                                      return Icon(
                                        i < score ? Icons.star : Icons.star_border,
                                        color: Colors.amber,
                                        size: 16,
                                      );
                                    }),
                                  ),
                                  if (comment != null && comment.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text('"$comment"'),
                                  ],
                                  const SizedBox(height: 4),
                                  Text(
                                    timeAgo,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      }),
                    ] else if (_totalRatings == 0) ...[
                      const Divider(),
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Icon(Icons.star_outline, size: 48, color: Colors.grey[400]),
                            const SizedBox(height: 12),
                            Text(
                              'No ratings yet',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Complete jobs to receive ratings',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[500],
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 16),

            // ==== Settings ====
            sectionTitle('Settings'),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.edit, color: accent),
                    title: const Text('Edit Profile'),
                    subtitle: const Text('Update your profile information'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => _userRole == 'Worker'
                              ? const WorkerProfileEditScreen()
                              : const ClientProfileEditScreen(),
                        ),
                      );
                      if (result == true) {
                        _loadUserProfile();
                        if (_userRole == 'Worker') {
                          _loadPortfolioAndRatings();
                        }
                      }
                    },
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.notifications, color: accent),
                    title: const Text('Notifications'),
                    subtitle: const Text('View and manage your notifications'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const NotificationsScreen(),
                        ),
                      );
                    },
                  ),
                  if (_userRole == 'Worker') ...[
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.construction, color: accent),
                      title: const Text('Manage Skills'),
                      subtitle: const Text('Add or remove your service skills'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        final userId = Supabase.instance.client.auth.currentUser?.id;
                        if (userId != null) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ManageSkillsScreen(workerId: userId),
                            ),
                          ).then((_) {
                            // Refresh profile after managing skills
                            _loadUserProfile();
                          });
                        }
                      },
                    ),
                  ],
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.security, color: accent),
                    title: const Text('Privacy & Security'),
                    subtitle: const Text('Manage your privacy settings'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Privacy settings coming soon')),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ==== Terms & Conditions ====
            sectionTitle('Legal'),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.description, color: accent),
                    title: const Text('Terms and Conditions'),
                    subtitle: const Text('Read our terms of service'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      _showTermsAndConditions();
                    },
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.privacy_tip, color: accent),
                    title: const Text('Privacy Policy'),
                    subtitle: const Text('How we protect your data'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      _showPrivacyPolicy();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ==== Log Out ====
            ElevatedButton.icon(
              onPressed: _handleLogout,
              icon: const Icon(Icons.logout),
              label: const Text('Log Out'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget sectionTitle(String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 4),
        child: Text(
          text,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  void _showTermsAndConditions() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Terms and Conditions'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: const [
              Text(
                'Last Updated: January 2025',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              SizedBox(height: 16),
              Text(
                '1. Acceptance of Terms',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'By using SerbisyoKo, you agree to be bound by these Terms and Conditions. If you do not agree, please do not use our service.',
              ),
              SizedBox(height: 16),
              Text(
                '2. Service Provider Responsibilities',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'Service providers must provide accurate information, maintain professional standards, and complete agreed-upon services in a timely manner.',
              ),
              SizedBox(height: 16),
              Text(
                '3. Client Responsibilities',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'Clients must provide accurate information, be available during scheduled service times, and pay agreed-upon fees promptly.',
              ),
              SizedBox(height: 16),
              Text(
                '4. Payment and Cancellation',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'Payment terms and cancellation policies are as specified in individual service agreements. Cancellation penalties may apply.',
              ),
              SizedBox(height: 16),
              Text(
                '5. Dispute Resolution',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'Any disputes will be resolved through our customer support team. We reserve the right to suspend accounts that violate our terms.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showPrivacyPolicy() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Privacy Policy'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: const [
              Text(
                'Last Updated: January 2025',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              SizedBox(height: 16),
              Text(
                '1. Information We Collect',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'We collect information you provide directly (name, email, phone, location) and automatically (device information, usage data) to provide and improve our services.',
              ),
              SizedBox(height: 16),
              Text(
                '2. How We Use Your Information',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'We use your information to connect you with service providers, process transactions, send notifications, and improve our platform.',
              ),
              SizedBox(height: 16),
              Text(
                '3. Information Sharing',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'We share necessary information between clients and service providers to facilitate services. We do not sell your personal information to third parties.',
              ),
              SizedBox(height: 16),
              Text(
                '4. Data Security',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'We implement security measures to protect your data, but no system is 100% secure. Please use strong passwords and keep your account secure.',
              ),
              SizedBox(height: 16),
              Text(
                '5. Your Rights',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'You have the right to access, update, or delete your personal information. Contact us at support@serbisyo.com for assistance.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
