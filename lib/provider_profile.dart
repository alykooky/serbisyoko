import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'booking_confirmation.dart';

class ProviderProfileScreen extends StatefulWidget {
  final String workerId;
  const ProviderProfileScreen({super.key, required this.workerId});

  @override
  State<ProviderProfileScreen> createState() => _ProviderProfileScreenState();
}

class _ProviderProfileScreenState extends State<ProviderProfileScreen>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? profile;
  Map<String, dynamic>? user;
  List<Map<String, dynamic>> reviews = [];
  List<String> workerServices = []; // Dynamic services/skills list
  late TabController _tab;

  bool _loading = true;

  // --- location/distance ---
  Position? _clientLocation;
  LatLng? _workerLocation;
  double? _distance;

  // --- booking ---
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  // --- ratings summary ---
  double _avgScore = 0.0;
  int _ratingsCount = 0;
  bool _hasUserBookedWorker = false; // Check if current user has booked this worker

  // --- Portfolio ---
  List<Map<String, dynamic>> _completedBookings = [];

  // --- AVAILABILITY (from worker_profiles.availability_status) ---
  bool _isAvailable = false;
  RealtimeChannel? _statusChannel; // Realtime subscription for availability
  RealtimeChannel? _locationChannel; // Realtime subscription for location

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _load(); // load profile + reviews + availability
    _getLocation(); // client location
    _subscribeAvailability(); // Live updates for availability
    _subscribeLocation(); // Live updates for worker location
  }

  @override
  void dispose() {
    _statusChannel?.unsubscribe();
    _locationChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final supa = Supabase.instance.client;

      // basic info
      user = await supa
          .from('users')
          .select()
          .eq('id', widget.workerId)
          .maybeSingle();
      profile = await supa
          .from('worker_profiles')
          .select()
          .eq('user_id', widget.workerId)
          .maybeSingle();

      // availability from worker_profiles.availability_status
      _isAvailable = (profile?['availability_status']?.toString().toUpperCase() ?? 'OFF') == 'ON';

      // reviews - fetch with client information
      final ratingsData = await supa
          .from('ratings')
          .select('id, booking_id, rater_id, score, comment, created_at')
          .eq('worker_id', widget.workerId)
          .order('created_at', ascending: false);

      reviews = (ratingsData as List).map((r) => Map<String, dynamic>.from(r)).toList();
      
      // Fetch client names for reviews
      final raterIds = reviews
          .map((r) => r['rater_id']?.toString())
          .where((id) => id != null && id.isNotEmpty)
          .toSet()
          .toList();
      
      if (raterIds.isNotEmpty) {
        try {
          final clients = await supa
              .from('users')
              .select('id, name, first_name, last_name')
              .inFilter('id', raterIds);
          
          final clientMap = <String, Map<String, dynamic>>{};
          for (final client in clients) {
            clientMap[client['id'].toString()] = Map<String, dynamic>.from(client);
          }
          
          // Add client info to reviews
          for (final review in reviews) {
            final raterId = review['rater_id']?.toString();
            if (raterId != null && clientMap.containsKey(raterId)) {
              final client = clientMap[raterId]!;
              review['client_name'] = client['name'] ?? 
                  '${client['first_name'] ?? ''} ${client['last_name'] ?? ''}'.trim() ??
                  'Anonymous';
            } else {
              review['client_name'] = 'Anonymous';
            }
          }
        } catch (e) {
          debugPrint('Error fetching client names: $e');
          for (final review in reviews) {
            review['client_name'] = 'Anonymous';
          }
        }
      }

      final scores =
          reviews.map((r) => (r['score'] as num?)?.toDouble() ?? 0.0).toList();
      _ratingsCount = scores.length;
      _avgScore =
          scores.isEmpty ? 0.0 : scores.reduce((a, b) => a + b) / scores.length;

      // worker pin for map - get from users table (real-time GPS coordinates)
      if (user?['latitude'] != null && user?['longitude'] != null) {
        _workerLocation = LatLng(
          (user!['latitude'] as num).toDouble(),
          (user!['longitude'] as num).toDouble(),
        );
      } else if (profile?['latitude'] != null && profile?['longitude'] != null) {
        // Fallback to worker_profiles if users table doesn't have coordinates
        _workerLocation = LatLng(
          (profile!['latitude'] as num).toDouble(),
          (profile!['longitude'] as num).toDouble(),
        );
      } else {
        _workerLocation = const LatLng(7.0722, 125.6111); // Davao default
      }

      // Fetch worker services/skills dynamically
      await _fetchWorkerServices();
      
      // Check if current user has booked this worker
      await _checkIfUserHasBookedWorker();
      
      // Load completed bookings for portfolio
      await _loadCompletedBookings();
    } catch (e) {
      debugPrint('Error loading profile: $e');
    }
    if (mounted) setState(() => _loading = false);
  }
  
  Future<void> _checkIfUserHasBookedWorker() async {
    try {
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser == null) {
        _hasUserBookedWorker = false;
        return;
      }
      
      // Check if user has any completed bookings with this worker
      final bookings = await Supabase.instance.client
          .from('bookings')
          .select('id, status')
          .eq('client_id', currentUser.id)
          .eq('worker_id', widget.workerId);
      
      final hasCompleted = (bookings as List).any((booking) {
        final status = (booking['status']?.toString() ?? '').toLowerCase();
        return status == 'completed';
      });
      
      setState(() {
        _hasUserBookedWorker = hasCompleted;
      });
    } catch (e) {
      debugPrint('Error checking if user has booked worker: $e');
      setState(() {
        _hasUserBookedWorker = false;
      });
    }
  }
  
  Future<void> _loadCompletedBookings() async {
    try {
      final bookings = await Supabase.instance.client
          .from('bookings')
          .select('id, service_type, scheduled_time, status, problem_details')
          .eq('worker_id', widget.workerId)
          .order('scheduled_time', ascending: false);
      
      final allBookings = (bookings as List)
          .map((b) => Map<String, dynamic>.from(b))
          .toList();
      
      final completed = allBookings.where((booking) {
        final status = (booking['status']?.toString() ?? '').toLowerCase();
        return status == 'completed';
      }).take(10).toList(); // Show up to 10 completed jobs
      
      setState(() {
        _completedBookings = completed;
      });
    } catch (e) {
      debugPrint('Error loading completed bookings: $e');
    }
  }

  // Fetch worker services/skills from database
  Future<void> _fetchWorkerServices() async {
    try {
      final supa = Supabase.instance.client;
      workerServices.clear();

      // Try to fetch from worker_skills table
      List<dynamic> workerSkills = [];
      try {
        // Try service_id first (current schema)
        workerSkills = await supa
            .from('worker_skills')
            .select('service_id')
            .eq('worker_id', widget.workerId);
      } catch (e) {
        // Fallback to skill_id if service_id doesn't exist
        try {
          workerSkills = await supa
              .from('worker_skills')
              .select('skill_id')
              .eq('worker_id', widget.workerId);
        } catch (e2) {
          debugPrint('Error fetching worker skills: $e2');
          return;
        }
      }

      if (workerSkills.isNotEmpty) {
        // Extract service/skill IDs
        final serviceIds = workerSkills
            .map((ws) => (ws['service_id'] ?? ws['skill_id'])?.toString())
            .where((id) => id != null && id.isNotEmpty)
            .toSet()
            .toList();

        if (serviceIds.isNotEmpty) {
          // Get service names from services table
          final services = await supa
              .from('services')
              .select('name, category')
              .inFilter('id', serviceIds);

          final serviceNames = services
              .map((s) => s['name']?.toString())
              .where((name) => name != null && name.isNotEmpty)
              .cast<String>()
              .toList();

          if (mounted) {
            setState(() {
              workerServices = serviceNames;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching worker services: $e');
    }
  }

  // --- realtime subscription to worker_profiles.availability_status ---
  void _subscribeAvailability() {
    final client = Supabase.instance.client;
    _statusChannel = client
        .channel('worker_availability_${widget.workerId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'worker_profiles',
          callback: (payload) {
            final newRec = payload.newRecord;
            if (newRec == null) return;
            if (newRec['user_id']?.toString() == widget.workerId) {
              final status = newRec['availability_status']?.toString().toUpperCase() ?? 'OFF';
              if (mounted) {
                setState(() {
                  _isAvailable = status == 'ON';
                });
              }
            }
          },
        )
        .subscribe();
  }

  // --- realtime subscription to users table for worker location updates ---
  void _subscribeLocation() {
    final client = Supabase.instance.client;
    _locationChannel = client
        .channel('worker_location_${widget.workerId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'users',
          callback: (payload) {
            final newRec = payload.newRecord;
            if (newRec == null) return;
            if (newRec['id']?.toString() == widget.workerId) {
              final lat = newRec['latitude'];
              final lng = newRec['longitude'];
              if (lat != null && lng != null && mounted) {
                final newLocation = LatLng(
                  (lat as num).toDouble(),
                  (lng as num).toDouble(),
                );
                setState(() {
                  _workerLocation = newLocation;
                  // Recalculate distance
                  if (_clientLocation != null) {
                    _distance = Geolocator.distanceBetween(
                      _clientLocation!.latitude,
                      _clientLocation!.longitude,
                      newLocation.latitude,
                      newLocation.longitude,
                    ) / 1000.0;
                  }
                });
              }
            }
          },
        )
        .subscribe();
  }

  Future<void> _getLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      double? distance;
      if (_workerLocation != null) {
        distance = Geolocator.distanceBetween(
              position.latitude,
              position.longitude,
              _workerLocation!.latitude,
              _workerLocation!.longitude,
            ) /
            1000.0;
      }
      if (mounted) {
        setState(() {
          _clientLocation = position;
          _distance = distance;
        });
      }
    } catch (e) {
      // fallback
      if (mounted) {
        setState(() {
          _clientLocation = null;
          _distance = 5.0;
        });
      }
    }
  }

  Future<void> _createBooking() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final bookingResult = await Supabase.instance.client
          .from('bookings')
          .insert({
        'service_type': 'Service',
        'scheduled_time': DateTime(
          _selectedDate!.year,
          _selectedDate!.month,
          _selectedDate!.day,
          _selectedTime!.hour,
          _selectedTime!.minute,
        ).toIso8601String(),
        'location': 'Client Location',
        'booking_fee': 0,
        'estimated_price': profile?['hourly_rate'] ?? 0,
        'mode_of_payment': 'Cash',
        'status': 'pending',
        'client_id': user.id,
        'worker_id': widget.workerId,
      }).select().single();

      if (!mounted) return;
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

  // --- review composer unchanged (trimmed for brevity) ---
  @override
  Widget build(BuildContext context) {
    final accent = const Color(0xFFED9121);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: accent,
        title: const Text('Profile', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFED9121)))
          : Column(
              children: [
                // --- header card (unchanged) ---
                _summaryCard(accent),

                // --- action buttons (unchanged) ---
                _actionsRow(accent),

                // --- tabs ---
                Container(
                  color: Colors.white,
                  child: TabBar(
                    controller: _tab,
                    labelColor: accent,
                    unselectedLabelColor: Colors.grey,
                    indicatorColor: accent,
                    indicatorWeight: 3,
                    tabs: const [
                      Tab(text: 'About'),
                      Tab(text: 'Reviews'),
                      Tab(text: 'Portfolio'),
                    ],
                  ),
                ),

                Expanded(
                  child: TabBarView(
                    controller: _tab,
                    children: [
                      _aboutTab(accent), // <-- shows _isAvailable now
                      _reviewsTab(),
                      _portfolioTab(),
                    ],
                  ),
                ),
              ],
            ),
      bottomNavigationBar: Container(
        width: double.infinity,
        height: 60,
        color: accent,
        child: ElevatedButton.icon(
          onPressed: _showBookingModal,
          icon: const Icon(Icons.check, color: Colors.white),
          label: const Text(
            'Book Now',
            style: TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
          ),
        ),
      ),
    );
  }

  Widget _summaryCard(Color accent) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      color: Colors.white,
      child: Row(
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: accent.withOpacity(0.1),
            child: CircleAvatar(
              radius: 38,
              backgroundImage: (profile?['profile_image'] != null &&
                      profile!['profile_image'].toString().isNotEmpty)
                  ? NetworkImage(profile!['profile_image'].toString())
                  : const AssetImage('assets/worker.png') as ImageProvider,
              onBackgroundImageError: (_, __) {
                // Fallback to default image on error
              },
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      user?['name'] ?? 'Service Provider',
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    if (profile?['is_verified'] == true)
                      _pill('Verified', Colors.green, Icons.verified)
                    else
                      _pill('Pending', Colors.orange, Icons.pending),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '₱${(profile?['hourly_rate'] ?? 100).toString()} / Hour',
                  style: const TextStyle(fontSize: 16, color: Colors.black87),
                ),
                const SizedBox(height: 4),
                if (_distance != null)
                  Text(
                    '${_distance!.toStringAsFixed(2)} km',
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87),
                  ),
                Text('away from you',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _avgScore.toStringAsFixed(2),
                style: TextStyle(
                    fontSize: 24, fontWeight: FontWeight.bold, color: accent),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star, color: Colors.green, size: 16),
                  const SizedBox(width: 4),
                  Text('$_ratingsCount rating(s)',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pill(String text, Color color, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration:
          BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 2),
          Text(text,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _actionsRow(Color accent) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () {
                final phoneNumber = profile?['phone']?.toString() ?? 
                                  user?['phone']?.toString() ?? 
                                  'Phone number not available';
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Call Worker'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Call ${user?['name'] ?? 'this worker'}?'),
                        if (phoneNumber != 'Phone number not available') ...[
                          const SizedBox(height: 8),
                          Text(
                            'Phone: $phoneNumber',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel')),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          // TODO: Implement actual phone call functionality
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(phoneNumber != 'Phone number not available'
                                    ? 'Calling $phoneNumber...'
                                    : 'Phone number not available'),
                                backgroundColor: const Color(0xFFED9121)),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFED9121)),
                        child: const Text('Call'),
                      ),
                    ],
                  ),
                );
              },
              icon: Icon(Icons.phone, color: accent),
              label: Text('Call now', style: TextStyle(color: accent)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                side: BorderSide(color: accent),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          Container(
              width: 1,
              height: 40,
              color: Colors.grey[300],
              margin: const EdgeInsets.symmetric(horizontal: 16)),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Message Worker'),
                    content: Text(
                        'Send a message to ${user?['name'] ?? 'this worker'}?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel')),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Opening chat...'),
                                backgroundColor: Color(0xFFED9121)),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFED9121)),
                        child: const Text('Message'),
                      ),
                    ],
                  ),
                );
              },
              icon: Icon(Icons.message, color: accent),
              label: Text('Message', style: TextStyle(color: accent)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                side: BorderSide(color: accent),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ABOUT TAB – shows dynamic availability and location from real-time updates
  Widget _aboutTab(Color accent) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Dynamic About/Bio section
        if (profile?['about'] != null &&
            profile!['about'].toString().trim().isNotEmpty) ...[
          const Text('About',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            profile!['about'].toString().trim(),
            style: const TextStyle(fontSize: 14, color: Colors.black87),
          ),
        ] else ...[
          const Text('About',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'Professional service provider committed to delivering quality work and excellent customer service.',
            style: TextStyle(
                fontSize: 14,
                color: Colors.black87,
                fontStyle: FontStyle.italic),
          ),
        ],
        const SizedBox(height: 24),
        Text('Services',
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: accent)),
        const SizedBox(height: 12),
        // Dynamic services list (comma-separated like reference)
        if (workerServices.isNotEmpty)
          Text(
            workerServices.join(', '),
            style: const TextStyle(fontSize: 14, color: Colors.black87, height: 1.5),
          )
        else
          Text(
            'No services listed yet.',
            style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic),
          ),
        const SizedBox(height: 24),
        Card(
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.location_on, color: accent, size: 20),
                    const SizedBox(width: 8),
                    const Text('Location & Distance',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
              ),
              if (_workerLocation != null)
                Container(
                  height: 200,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: FlutterMap(
                      options: MapOptions(
                        initialCenter: _workerLocation!,
                        initialZoom: 18.0, // Pinpoint accuracy - building level zoom
                      ),
                      children: [
                        // <-- CHANGED: TileLayer must NOT be const
                        TileLayer(
                          urlTemplate:
                              'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                          subdomains: const ['a', 'b', 'c'],
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              width: 50,
                              height: 50,
                              point: _workerLocation!,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: accent,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                        color: accent.withOpacity(0.4),
                                        blurRadius: 10,
                                        spreadRadius: 3),
                                  ],
                                ),
                                child: const Icon(Icons.location_pin,
                                    color: Colors.white, size: 30),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_distance != null)
                      Text(
                        'Distance: ${_distance!.toStringAsFixed(1)} km away',
                        style: TextStyle(
                            fontSize: 14,
                            color: accent,
                            fontWeight: FontWeight.w500),
                      ),
                    const SizedBox(height: 4),
                    Text(
                        'Service Area: ${profile?['service_area'] ?? 'Davao City'}',
                        style: const TextStyle(fontSize: 14)),
                    const SizedBox(height: 4),

                    // Dynamic availability from worker_profiles.availability_status
                    Text(
                      'Availability: ${_isAvailable ? 'ON' : 'OFF'}',
                      style: TextStyle(
                        fontSize: 14,
                        color: _isAvailable ? Colors.green : Colors.red,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _reviewsTab() {
    if (reviews.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.star_border, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'No reviews yet',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Reviews will appear here once clients rate this provider',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[500], fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    // Calculate rating distribution
    final ratingDistribution = <int, int>{1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
    for (final review in reviews) {
      final score = (review['score'] as num?)?.toInt() ?? 0;
      if (score >= 1 && score <= 5) {
        ratingDistribution[score] = (ratingDistribution[score] ?? 0) + 1;
      }
    }

    final accent = const Color(0xFFED9121);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Rating Statistics Card
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Rating Distribution',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 16),
                ...ratingDistribution.entries.toList().reversed.map((entry) {
                  final stars = entry.key;
                  final count = entry.value;
                  final percentage = _ratingsCount > 0
                      ? (count / _ratingsCount * 100).toStringAsFixed(0)
                      : '0';
                  
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 60,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('$stars', style: const TextStyle(fontWeight: FontWeight.bold)),
                              const Icon(Icons.star, color: Colors.amber, size: 16),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: _ratingsCount > 0 ? count / _ratingsCount : 0,
                              backgroundColor: Colors.grey[200],
                              valueColor: AlwaysStoppedAnimation<Color>(
                                stars >= 4 ? Colors.green : stars >= 3 ? Colors.orange : Colors.red,
                              ),
                              minHeight: 8,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 60,
                          child: Text(
                            '$count ($percentage%)',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        
        // Reviews List
        Text(
          'All Reviews (${reviews.length})',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        
        ...reviews.map((r) => _buildReviewCard(r, accent)),
      ],
    );
  }

  Widget _buildReviewCard(Map<String, dynamic> review, Color accent) {
    final score = (review['score'] as num?)?.toInt() ?? 0;
    final comment = review['comment']?.toString() ?? '';
    final clientName = review['client_name']?.toString() ?? 'Anonymous';
    final createdAt = review['created_at']?.toString();
    
    String dateStr = '';
    if (createdAt != null) {
      try {
        final date = DateTime.tryParse(createdAt);
        if (date != null) {
          final now = DateTime.now();
          final difference = now.difference(date);
          
          if (difference.inDays == 0) {
            dateStr = 'Today';
          } else if (difference.inDays == 1) {
            dateStr = 'Yesterday';
          } else if (difference.inDays < 7) {
            dateStr = '${difference.inDays} days ago';
          } else if (difference.inDays < 30) {
            dateStr = '${(difference.inDays / 7).floor()} weeks ago';
          } else {
            dateStr = '${date.day}/${date.month}/${date.year}';
          }
        }
      } catch (e) {
        dateStr = '';
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: accent.withOpacity(0.1),
                  child: Text(
                    clientName.isNotEmpty ? clientName[0].toUpperCase() : 'A',
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        clientName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (dateStr.isNotEmpty)
                        Text(
                          dateStr,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                    ],
                  ),
                ),
                Row(
                  children: List.generate(5, (index) {
                    return Icon(
                      index < score ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                      size: 20,
                    );
                  }),
                ),
              ],
            ),
            if (comment.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                comment,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.black87,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _portfolioTab() {
    if (_completedBookings.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.work_outline, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'No portfolio items yet',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Completed services will appear here',
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
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _completedBookings.length,
      itemBuilder: (context, index) {
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
        
        // Get icon based on service type
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
        
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: iconColor.withOpacity(0.2),
              child: Icon(serviceIcon, color: iconColor),
            ),
            title: Text(
              serviceType,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text('Completed on $formattedDate'),
                if (booking['problem_details'] != null &&
                    booking['problem_details'].toString().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    booking['problem_details'].toString(),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
            trailing: const Icon(Icons.check_circle, color: Colors.green),
          ),
        );
      },
    );
  }

  void _showBookingModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20), topRight: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Container(
                        width: 4,
                        height: 24,
                        decoration: BoxDecoration(
                            color: const Color(0xFFED9121),
                            borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 12),
                    const Text('Select Date and Time',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close)),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      // date picker (unchanged)
                      GestureDetector(
                        onTap: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: _selectedDate ?? DateTime.now(),
                            firstDate: DateTime.now(),
                            lastDate:
                                DateTime.now().add(const Duration(days: 30)),
                          );
                          if (date != null)
                            setState(() => _selectedDate = date);
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFED9121).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color:
                                    const Color(0xFFED9121).withOpacity(0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.calendar_today,
                                      color: const Color(0xFFED9121)),
                                  const SizedBox(width: 8),
                                  const Text('Date',
                                      style: TextStyle(
                                          fontSize: 14, color: Colors.grey)),
                                  const Spacer(),
                                  Icon(Icons.arrow_drop_down,
                                      color: const Color(0xFFED9121)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _selectedDate != null
                                    ? '${_getDayName(_selectedDate!.weekday)} ${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}'
                                    : 'Tap to select date',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: _selectedDate != null
                                      ? Colors.black87
                                      : Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // time picker (unchanged)
                      GestureDetector(
                        onTap: () async {
                          final time = await showTimePicker(
                              context: context,
                              initialTime: _selectedTime ?? TimeOfDay.now());
                          if (time != null)
                            setState(() => _selectedTime = time);
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: Colors.green.withOpacity(0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Row(
                                children: [
                                  Icon(Icons.access_time, color: Colors.green),
                                  SizedBox(width: 8),
                                  Text('Time',
                                      style: TextStyle(
                                          fontSize: 14, color: Colors.grey)),
                                  Spacer(),
                                  Icon(Icons.arrow_drop_down,
                                      color: Colors.green),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total:',
                              style:
                                  TextStyle(fontSize: 16, color: Colors.grey)),
                          Text('₱${(profile?['hourly_rate'] ?? 0).toString()}',
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                              onPressed: () {},
                              child: const Text('View Details')),
                          const Icon(Icons.keyboard_arrow_up, size: 16),
                        ],
                      ),
                      const Spacer(),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            if (_selectedDate != null &&
                                _selectedTime != null) {
                              Navigator.pop(context);
                              _createBooking();
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content:
                                      Text('Please select both date and time'),
                                  backgroundColor: Color(0xFFED9121),
                                ),
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                (_selectedDate != null && _selectedTime != null)
                                    ? const Color(0xFFED9121)
                                    : Colors.grey[300],
                            foregroundColor:
                                (_selectedDate != null && _selectedTime != null)
                                    ? Colors.white
                                    : Colors.black87,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Confirm Booking',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
}
