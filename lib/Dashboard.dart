// ✅ UPDATED RESPONSIVE DASHBOARDPAGE (Mobile + Web + Tablet)
// Fixes "too much spacing" on Web by using Center + ConstrainedBox (max width)
// Also makes Grid crossAxisCount responsive.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:latlong2/latlong.dart';

// Screens
import 'screens/match_map_page.dart';
import 'post_task.dart';
import 'my_bookings.dart';
import 'login.dart';
import 'provider_profile.dart';
import 'chat_list_screen.dart';
import 'profile.dart';
import 'available_providers_screen.dart';
import 'subcategories.dart';
import 'smart_matching_results.dart';
import 'screens/post_service_request.dart';
import 'screens/more_services_screen.dart';
import 'request_applicants_page.dart';
import 'screens/notifications_screen.dart';
import 'services/notification_service.dart';

// 🚀 REQUIRED FOR FIXED MATCHING
import '../services/advanced_matching_service.dart';

class DashboardPage extends StatefulWidget {
  final String title;
  const DashboardPage({super.key, required this.title});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _currentIndex = 0;
  bool _loading = true;

  String searchQuery = "";
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _allServices = [];
  List<Map<String, dynamic>> _filteredServices = [];

  Map<String, dynamic>? _currentUser;
  List<Map<String, dynamic>> _providers = [];
  List<Map<String, dynamic>> _myServiceRequests = [];
  List<Map<String, dynamic>> _topWorkers = [];

  double? _clientLat;
  double? _clientLng;
  String? _clientAddress;

  // Notifications
  int _notificationCount = 0;
  RealtimeChannel? _notificationsChannel;

  RealtimeChannel? _workerRealtime;
  RealtimeChannel? _userRealtime;
  Timer? _refreshThrottle;

  @override
  void initState() {
    super.initState();
    _initDashboard();
    _subscribeToWorkerRealtime();
    _subscribeToUserRealtime();
    _loadNotificationCount();
    _subscribeToNotifications();
  }

  @override
  void dispose() {
    _workerRealtime?.unsubscribe();
    _userRealtime?.unsubscribe();
    _notificationsChannel?.unsubscribe();
    _refreshThrottle?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initDashboard() async {
    await _fetchCurrentUser();
    await _updateUserLocation();
    await _fetchProvidersNearby();
    await _fetchMyServiceRequests();
    await _fetchAllServices();
    await _fetchTopWorkers();
    await _loadNotificationCount();
    if (mounted) setState(() => _loading = false);
  }

  // =========================
  // Fetch all services (search)
  // =========================
  Future<void> _fetchAllServices() async {
    try {
      final services = await Supabase.instance.client
          .from('services')
          .select('id, name, category')
          .order('name');

      setState(() {
        _allServices = (services as List)
            .map((s) => Map<String, dynamic>.from(s))
            .toList();
        _filteredServices = _allServices;
      });
    } catch (e) {
      debugPrint('Error fetching services: $e');
      setState(() {
        _allServices = [
          {'name': 'Cleaning', 'category': 'Cleaning'},
          {'name': 'Repairing', 'category': 'Repair'},
          {'name': 'Electrician', 'category': 'Electrical'},
          {'name': 'Aircon Technician', 'category': 'HVAC'},
          {'name': 'Plumber', 'category': 'Plumbing'},
        ];
        _filteredServices = _allServices;
      });
    }
  }

  void _filterServices(String query) {
    setState(() {
      searchQuery = query;
      if (query.isEmpty) {
        _filteredServices = _allServices;
      } else {
        final lowerQuery = query.toLowerCase();
        _filteredServices = _allServices.where((service) {
          final name = (service['name'] ?? '').toString().toLowerCase();
          final category = (service['category'] ?? '').toString().toLowerCase();
          return name.contains(lowerQuery) || category.contains(lowerQuery);
        }).toList();
      }
    });
  }

  void _navigateToService(Map<String, dynamic> service) {
    _searchController.clear();
    _filterServices('');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SubcategoriesScreen(
          service: service,
          clientLat: _clientLat ?? 0,
          clientLng: _clientLng ?? 0,
          location: _clientAddress ?? "Unknown",
        ),
      ),
    );
  }

  // =========================
  // Notification Management
  // =========================
  Future<void> _loadNotificationCount() async {
    try {
      final count = await NotificationService.getUnreadCount();
      if (mounted) setState(() => _notificationCount = count);
    } catch (e) {
      debugPrint('Error loading notification count: $e');
    }
  }

  void _subscribeToNotifications() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    _notificationsChannel?.unsubscribe();
    _notificationsChannel = Supabase.instance.client
        .channel('notifications_${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: user.id,
          ),
          callback: (_) => _loadNotificationCount(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: user.id,
          ),
          callback: (_) => _loadNotificationCount(),
        )
        .subscribe();
  }

  // =========================
  // USER FETCH
  // =========================
  Future<void> _fetchCurrentUser() async {
    final supa = Supabase.instance.client;
    final user = supa.auth.currentUser;

    if (user == null) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const SignInScreen()),
      );
      return;
    }

    try {
      final data = await supa
          .from('users')
          .select('id, name, location_address, latitude, longitude')
          .eq('id', user.id)
          .maybeSingle();

      final name = data?['name'] ??
          user.userMetadata?['name'] ??
          user.email?.split('@').first ??
          'User';

      setState(() {
        _currentUser = {...?data, 'name': name};
        _clientLat = (data?['latitude'] as num?)?.toDouble();
        _clientLng = (data?['longitude'] as num?)?.toDouble();
        _clientAddress =
            data?['location_address'] ?? "Tap to update your location";
      });
    } catch (e) {
      debugPrint('Error fetching user info: $e');
    }
  }

  // =========================
  // UPDATE LOCATION
  // =========================
  Future<void> _updateUserLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) return;

      Position pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.bestForNavigation,
          timeLimit: const Duration(seconds: 15),
        );
      } catch (e) {
        debugPrint('BestForNavigation failed, using best: $e');
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
          timeLimit: const Duration(seconds: 15),
        );
      }

      String readable = "Unknown location";

      // Nominatim reverse geocode
      try {
        final url =
            'https://nominatim.openstreetmap.org/reverse?format=json&lat=${pos.latitude}&lon=${pos.longitude}&zoom=18&addressdetails=1';
        final response = await http.get(Uri.parse(url), headers: {
          'User-Agent': 'SerbisyoKoApp/1.0 (contact@serbisyo.com)',
        });

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final address = data['address'];

          if (address != null && address is Map) {
            final addr = address as Map<String, dynamic>;
            final parts = <String>[];

            if (addr['name'] != null) parts.add(addr['name'].toString());
            if (addr['building'] != null)
              parts.add(addr['building'].toString());
            if (addr['amenity'] != null) parts.add(addr['amenity'].toString());
            if (addr['house_number'] != null)
              parts.add(addr['house_number'].toString());

            if (addr['road'] != null) parts.add(addr['road'].toString());
            if (addr['street'] != null &&
                !parts.contains(addr['street'].toString())) {
              parts.add(addr['street'].toString());
            }

            if (addr['quarter'] != null) parts.add(addr['quarter'].toString());
            if (addr['neighbourhood'] != null)
              parts.add(addr['neighbourhood'].toString());
            if (addr['village'] != null)
              parts.add(addr['village'].toString());
            else if (addr['suburb'] != null)
              parts.add(addr['suburb'].toString());
            if (addr['residential'] != null &&
                !parts.contains(addr['residential'].toString())) {
              parts.add(addr['residential'].toString());
            }

            if (addr['barangay'] != null)
              parts.add(addr['barangay'].toString());

            if (addr['town'] != null)
              parts.add(addr['town'].toString());
            else if (addr['city'] != null)
              parts.add(addr['city'].toString());
            else if (addr['municipality'] != null)
              parts.add(addr['municipality'].toString());

            if (addr['district'] != null)
              parts.add(addr['district'].toString());
            if (addr['region'] != null) parts.add(addr['region'].toString());

            if (addr['state'] != null)
              parts.add(addr['state'].toString());
            else if (addr['province'] != null)
              parts.add(addr['province'].toString());

            if (addr['country'] != null) parts.add(addr['country'].toString());

            if (parts.isNotEmpty) {
              readable = parts.join(', ');
            } else if (data['display_name'] != null) {
              readable = data['display_name'].toString();
            }
          } else if (data['display_name'] != null) {
            readable = data['display_name'].toString();
          }
        }
      } catch (e) {
        debugPrint("Reverse geocoding error: $e");
        try {
          final placemarks =
              await placemarkFromCoordinates(pos.latitude, pos.longitude);
          if (placemarks.isNotEmpty) {
            final p = placemarks.first;
            final parts = <String>[];
            if (p.subThoroughfare?.isNotEmpty ?? false)
              parts.add(p.subThoroughfare!);
            if (p.thoroughfare?.isNotEmpty ?? false) parts.add(p.thoroughfare!);
            if (p.subLocality?.isNotEmpty ?? false) parts.add(p.subLocality!);
            if (p.locality?.isNotEmpty ?? false) parts.add(p.locality!);
            if (p.administrativeArea?.isNotEmpty ?? false)
              parts.add(p.administrativeArea!);
            if (p.country?.isNotEmpty ?? false) parts.add(p.country!);
            if (parts.isNotEmpty) readable = parts.join(', ');
          }
        } catch (_) {}
      }

      if (readable.isEmpty || readable.toLowerCase() == 'unknown location') {
        readable =
            "${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}";
      }

      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        await Supabase.instance.client.from('users').update({
          'latitude': pos.latitude,
          'longitude': pos.longitude,
          'location_address': readable,
        }).eq('id', user.id);
      }

      if (!mounted) return;
      setState(() {
        _clientLat = pos.latitude;
        _clientLng = pos.longitude;
        _clientAddress = readable;
      });
    } catch (e) {
      debugPrint("Error updating location: $e");
    }
  }

  // =========================
  // FETCH WORKERS NEARBY
  // =========================
  Future<void> _fetchProvidersNearby() async {
    setState(() => _loading = true);
    final supa = Supabase.instance.client;

    try {
      final workers = await supa
          .from('users')
          .select('id, name, role')
          .eq('role', 'Worker');

      final profiles = await supa.from('worker_profiles').select(
          'user_id, is_verified, availability_status, lat, lng, hourly_rate');

      final ratings = await supa.from('ratings').select('worker_id, score');

      final Map<String, List<num>> ratingMap = {};
      for (final r in ratings) {
        final wid = r['worker_id'] as String?;
        final score = r['score'] as num?;
        if (wid != null && score != null) {
          ratingMap.putIfAbsent(wid, () => []).add(score);
        }
      }

      final List<Map<String, dynamic>> combined = [];

      for (final w in workers) {
        final profile = profiles.firstWhere((p) => p['user_id'] == w['id'],
            orElse: () => {});
        if (profile.isEmpty) continue;

        if (profile['is_verified'] != true) continue;
        if (profile['availability_status'] != 'ON') continue;

        final scores = ratingMap[w['id']] ?? [];
        final avg = scores.isEmpty
            ? 0.0
            : scores.reduce((a, b) => a + b) / scores.length;

        final lat = (profile['lat'] as num?)?.toDouble();
        final lng = (profile['lng'] as num?)?.toDouble();

        double? dist;
        if (_clientLat != null &&
            _clientLng != null &&
            lat != null &&
            lng != null) {
          dist = _calculateDistance(_clientLat!, _clientLng!, lat, lng);
        }

        combined.add({
          'id': w['id'],
          'name': w['name'] ?? 'Unknown Worker',
          'rating': avg,
          'hourly_rate': profile['hourly_rate'],
          'distance_km': dist,
        });
      }

      combined.sort((a, b) =>
          (a['distance_km'] ?? 9999).compareTo(b['distance_km'] ?? 9999));

      if (!mounted) return;
      setState(() {
        _providers = combined;
        _loading = false;
      });
    } catch (e) {
      debugPrint("Error fetching providers: $e");
      if (mounted) setState(() => _loading = false);
    }
  }

  // =========================
  // Fetch Top Workers
  // =========================
  Future<void> _fetchTopWorkers() async {
    final supa = Supabase.instance.client;

    try {
      final workers = await supa
          .from('users')
          .select('id, name, role')
          .eq('role', 'Worker');
      final profiles = await supa
          .from('worker_profiles')
          .select('user_id, is_verified, availability_status, hourly_rate');
      final ratings = await supa.from('ratings').select('worker_id, score');

      final Map<String, List<num>> ratingMap = {};
      for (final r in ratings) {
        final wid = r['worker_id'] as String?;
        final score = r['score'] as num?;
        if (wid != null && score != null) {
          ratingMap.putIfAbsent(wid, () => []).add(score);
        }
      }

      final List<Map<String, dynamic>> topWorkersList = [];

      for (final w in workers) {
        final profile = profiles.firstWhere((p) => p['user_id'] == w['id'],
            orElse: () => {});
        if (profile.isEmpty) continue;
        if (profile['is_verified'] != true) continue;

        final scores = ratingMap[w['id']] ?? [];
        final reviewCount = scores.length;
        final avgRating = scores.isEmpty
            ? 0.0
            : scores.reduce((a, b) => a + b) / scores.length;

        if (reviewCount > 0) {
          final weightedScore =
              avgRating * (1 + (reviewCount / 10.0).clamp(0.0, 0.5));
          topWorkersList.add({
            'id': w['id'],
            'name': w['name'] ?? 'Unknown Worker',
            'rating': avgRating,
            'review_count': reviewCount,
            'hourly_rate': profile['hourly_rate'] ?? 0,
            'profile_image': null,
            'weighted_score': weightedScore,
            'has_reviews': true,
          });
        }
      }

      topWorkersList.sort((a, b) {
        final scoreDiff =
            (b['weighted_score'] as num).compareTo(a['weighted_score'] as num);
        if (scoreDiff != 0) return scoreDiff;

        final ratingDiff = (b['rating'] as num).compareTo(a['rating'] as num);
        if (ratingDiff != 0) return ratingDiff;

        return (b['review_count'] as int).compareTo(a['review_count'] as int);
      });

      if (!mounted) return;
      setState(() => _topWorkers = topWorkersList.take(6).toList());
    } catch (e) {
      debugPrint("❌ Error fetching top workers: $e");
    }
  }

  // =========================
  // Realtime subscriptions
  // =========================
  void _subscribeToWorkerRealtime() {
    final client = Supabase.instance.client;
    _workerRealtime = client
        .channel('worker_profiles_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'worker_profiles',
          callback: (_) => _throttledRefresh('Worker profile update'),
        )
        .subscribe();
  }

  void _subscribeToUserRealtime() {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;

    _userRealtime = client
        .channel('user_location_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'users',
          callback: (payload) {
            final newLat = payload.newRecord['latitude'];
            final newLng = payload.newRecord['longitude'];

            if (newLat != null && newLng != null) {
              setState(() {
                _clientLat = (newLat as num).toDouble();
                _clientLng = (newLng as num).toDouble();
              });
              _throttledRefresh('User location change');
            }
          },
        )
        .subscribe();
  }

  void _throttledRefresh(String src) {
    _refreshThrottle?.cancel();
    _refreshThrottle = Timer(const Duration(seconds: 2), _fetchProvidersNearby);
  }

  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295;
    final c = cos;
    final a = 0.5 -
        c((lat2 - lat1) * p) / 2 +
        c(lat1 * p) * c(lat2 * p) * (1 - c((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a));
  }

  // =========================
  // Fetch My Service Requests
  // =========================
  Future<void> _fetchMyServiceRequests() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final requests = await Supabase.instance.client
          .from('service_requests')
          .select(
              'id, service_type, description, location, status, created_at, preferred_date')
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      if (requests.isEmpty) {
        if (mounted) setState(() => _myServiceRequests = []);
        return;
      }

      final requestIds =
          (requests as List).map((r) => r['id'].toString()).toList();

      final applications = await Supabase.instance.client
          .from('job_applications')
          .select('request_id, status')
          .inFilter('request_id', requestIds);

      final applicantCounts = <String, int>{};
      final pendingCounts = <String, int>{};

      for (final app in applications) {
        final requestId = app['request_id'].toString();
        applicantCounts[requestId] = (applicantCounts[requestId] ?? 0) + 1;
        if (app['status'] == 'pending') {
          pendingCounts[requestId] = (pendingCounts[requestId] ?? 0) + 1;
        }
      }

      final List<Map<String, dynamic>> requestsWithCounts = [];
      for (final req in requests) {
        final requestId = req['id'].toString();
        requestsWithCounts.add({
          ...req,
          'applicant_count': applicantCounts[requestId] ?? 0,
          'pending_count': pendingCounts[requestId] ?? 0,
        });
      }

      if (mounted) setState(() => _myServiceRequests = requestsWithCounts);
    } catch (e) {
      debugPrint('Error fetching my service requests: $e');
    }
  }

  // =========================================================
  // ✅ UI BUILD (RESPONSIVE)
  // =========================================================
  @override
  Widget build(BuildContext context) {
    final fullName = _currentUser?['name'] ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F2),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const PostServiceRequestPage()));
        },
        label: const Text("Book Service"),
        icon: const Icon(Icons.search),
        backgroundColor: const Color(0xFFED9121),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.orange))
          : SafeArea(
              child: RefreshIndicator(
                onRefresh: () async {
                  await _fetchProvidersNearby();
                  await _fetchMyServiceRequests();
                  await _fetchTopWorkers();
                  await _loadNotificationCount();
                },
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final w = constraints.maxWidth;

                    // ✅ This is the MAIN FIX for web spacing:
                    // center content + limit max width.
                    double maxContentWidth = 520;
                    if (w >= 700) maxContentWidth = 720; // tablets
                    if (w >= 1000) maxContentWidth = 920; // web/desktop

                    return SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: Center(
                        child: ConstrainedBox(
                          constraints:
                              BoxConstraints(maxWidth: maxContentWidth),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildHeader(fullName),
                                const SizedBox(height: 20),
                                _actionButtons(),
                                const SizedBox(height: 24),
                                _servicesGrid(w),
                                const SizedBox(height: 24),
                                _myJobPostsSection(),
                                const SizedBox(height: 24),
                                _topWorkersSection(w),
                                const SizedBox(height: 24),
                                _bannerSection(),
                                const SizedBox(height: 24),
                                _nearbyProvidersSection(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
      bottomNavigationBar: _bottomNavBar(),
    );
  }

  // =========================
  // Header
  // =========================
  Widget _buildHeader(String fullName) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFED9121),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    "Good Day, ${fullName.isNotEmpty ? fullName : 'User'}!",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    IconButton(
                      icon:
                          const Icon(Icons.notifications, color: Colors.white),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const NotificationsScreen()),
                        ).then((_) {
                          _loadNotificationCount();
                          _fetchMyServiceRequests();
                        });
                      },
                    ),
                    if (_notificationCount > 0)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          constraints:
                              const BoxConstraints(minWidth: 16, minHeight: 16),
                          child: Text(
                            _notificationCount > 99
                                ? '99+'
                                : '$_notificationCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.account_circle,
                      color: Colors.white, size: 28),
                  onPressed: () {
                    Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const ProfilePage()));
                  },
                ),
              ],
            ),
            const SizedBox(height: 6),

            GestureDetector(
              onTap: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MatchMapPage(
                      clientPos:
                          LatLng(_clientLat ?? 7.07, _clientLng ?? 125.6),
                      isPicker: true,
                      matches: const [],
                      serviceType: null,
                      budgetMin: null,
                      budgetMax: null,
                    ),
                  ),
                );

                if (result != null) {
                  setState(() {
                    _clientLat = result['lat'];
                    _clientLng = result['lng'];
                    _clientAddress = result['address'];
                  });

                  final user = Supabase.instance.client.auth.currentUser;
                  if (user != null) {
                    await Supabase.instance.client.from('users').update({
                      'latitude': _clientLat,
                      'longitude': _clientLng,
                      'location_address': _clientAddress,
                    }).eq('id', user.id);
                  }
                }
              },
              child: Row(
                children: [
                  const Icon(Icons.location_on, color: Colors.white, size: 16),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _clientAddress ?? "Tap to update your location",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ✅ FIXED: padding typo removed
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(32),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: "Search for Services or Location",
                        border: InputBorder.none,
                        suffixIcon: searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear,
                                    size: 20, color: Colors.grey),
                                onPressed: () {
                                  _searchController.clear();
                                  _filterServices('');
                                },
                              )
                            : null,
                      ),
                      onChanged: _filterServices,
                      onSubmitted: (query) {
                        if (query.isNotEmpty && _filteredServices.isNotEmpty) {
                          _navigateToService(_filteredServices[0]);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),

            if (searchQuery.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: _filteredServices.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(Icons.search_off, color: Colors.grey[400]),
                            const SizedBox(width: 8),
                            Text(
                              'No services found for "$searchQuery"',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _filteredServices.length > 5
                            ? 5
                            : _filteredServices.length,
                        itemBuilder: (context, index) {
                          final service = _filteredServices[index];
                          return ListTile(
                            leading: const Icon(Icons.build,
                                color: Color(0xFFED9121)),
                            title: Text(service['name'] ?? 'Service'),
                            subtitle: service['category'] != null
                                ? Text(service['category'].toString())
                                : null,
                            trailing:
                                const Icon(Icons.arrow_forward_ios, size: 16),
                            onTap: () => _navigateToService(service),
                          );
                        },
                      ),
              ),
            ],
          ],
        ),
      );

  // =========================
  // Action Buttons
  // =========================
  Widget _actionButtons() => Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFED9121),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.handshake, color: Colors.white),
              label: const Text("Hire a Service Provider",
                  style: TextStyle(color: Colors.white)),
              onPressed: () {},
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFED9121)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.add_task, color: Color(0xFFED9121)),
              label: const Text("Post for Side Gig",
                  style: TextStyle(color: Color(0xFFED9121))),
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const PostTaskPage())),
            ),
          ),
        ],
      );

  // =========================
  // Services Grid (Responsive)
  // =========================
  Widget _servicesGrid(double screenWidth) {
    int crossAxisCount = 3;
    if (screenWidth >= 700) crossAxisCount = 4;
    if (screenWidth >= 1000) crossAxisCount = 6;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Services",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          children: [
            _serviceTile("assets/cleaning.png", "Cleaning"),
            _serviceTile("assets/repairing.png", "Repairing"),
            _serviceTile("assets/electrician.png", "Electrician"),
            _serviceTile("assets/aircon.png", "Aircon Technician"),
            _serviceTile("assets/plumber.png", "Plumber"),
            _moreServicesTile(),
          ],
        ),
      ],
    );
  }

  Widget _moreServicesTile() => GestureDetector(
        onTap: () {
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const MoreServicesScreen()));
        },
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(blurRadius: 3, color: Colors.black12)],
              ),
              child: Image.asset(
                "assets/more.png",
                height: 40,
                errorBuilder: (c, e, s) =>
                    const Icon(Icons.more_horiz, color: Colors.grey, size: 40),
              ),
            ),
            const SizedBox(height: 6),
            const Text("More", style: TextStyle(fontSize: 12)),
          ],
        ),
      );

  Widget _serviceTile(String path, String label) => GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SubcategoriesScreen(
                service: {'name': label},
                clientLat: _clientLat ?? 0,
                clientLng: _clientLng ?? 0,
                location: _clientAddress ?? "Unknown",
              ),
            ),
          );
        },
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(blurRadius: 3, color: Colors.black12)],
              ),
              child: Image.asset(
                path,
                height: 40,
                errorBuilder: (c, e, s) =>
                    const Icon(Icons.build, color: Colors.grey, size: 40),
              ),
            ),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      );

  // =========================
  // My Job Posts Section (your same code)
  // =========================
  Widget _myJobPostsSection() {
    final openRequests = _myServiceRequests
        .where((req) => req['status'] == 'open' || req['status'] == 'assigned')
        .toList();

    final requestsWithApplicants =
        openRequests.where((req) => (req['applicant_count'] ?? 0) > 0).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text("My Job Posts",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Spacer(),
            TextButton(
              onPressed: () async => _fetchMyServiceRequests(),
              child: const Text("Refresh",
                  style: TextStyle(color: Color(0xFFED9121))),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (requestsWithApplicants.isEmpty && openRequests.isEmpty)
          Transform.translate(
            offset: const Offset(-16, 0),
            child: Container(
              width: MediaQuery.of(context).size.width,
              decoration: BoxDecoration(
                color: const Color(0xFFED9121).withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.work_outline, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No job posts yet',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Post a service request to see applicants here',
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        else if (requestsWithApplicants.isEmpty && openRequests.isNotEmpty)
          Transform.translate(
            offset: const Offset(-16, 0),
            child: Container(
              width: MediaQuery.of(context).size.width,
              decoration: BoxDecoration(
                color: const Color(0xFFED9121).withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No applicants yet',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Workers will appear here once they apply to your job posts',
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        else
          const SizedBox.shrink(),
        const SizedBox(height: 12),
        ...requestsWithApplicants.map((request) {
          final applicantCount = request['applicant_count'] ?? 0;
          final pendingCount = request['pending_count'] ?? 0;
          final serviceType = request['service_type'] ?? 'Service';
          final location = request['location'] ?? 'No location';
          final preferredDate = request['preferred_date'];

          String dateStr = 'No date set';
          if (preferredDate != null) {
            final date = DateTime.tryParse(preferredDate.toString());
            if (date != null)
              dateStr = '${date.day}/${date.month}/${date.year}';
          }

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            elevation: 2,
            child: ListTile(
              contentPadding: const EdgeInsets.all(12),
              leading: CircleAvatar(
                backgroundColor: const Color(0xFFED9121),
                child: Text(
                  '${applicantCount > 9 ? '9+' : applicantCount}',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
              title: Text(serviceType,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('📍 $location'),
                  Text('📅 $dateStr'),
                  if (pendingCount > 0)
                    Text(
                      '$pendingCount pending application${pendingCount > 1 ? 's' : ''}',
                      style: const TextStyle(
                          color: Color(0xFFED9121),
                          fontWeight: FontWeight.w600),
                    ),
                ],
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RequestApplicantsPage(
                      requestId: request['id'].toString(),
                      serviceType: serviceType,
                    ),
                  ),
                ).then((_) => _fetchMyServiceRequests());
              },
            ),
          );
        }),
      ],
    );
  }

  // =========================
  // Banner Section
  // =========================
  Widget _bannerSection() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.orange[200],
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Welcome to SerbisyoKo!",
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    const Text(
                        "Book Your First Service Now, with our trusted and verified workers."),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: () async {
                        final matches =
                            await AdvancedMatchingService.findBestMatches(
                          serviceType: "Any Service",
                          clientLatitude: _clientLat ?? 0,
                          clientLongitude: _clientLng ?? 0,
                          preferredStartTime: DateTime.now(),
                          preferredEndTime:
                              DateTime.now().add(const Duration(hours: 2)),
                          budgetMin: 0,
                          budgetMax: 99999,
                        );

                        if (!mounted) return;

                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SmartMatchingResultsScreen(
                              serviceType: "Any Service",
                              clientLat: _clientLat ?? 0,
                              clientLng: _clientLng ?? 0,
                              location: _clientAddress ?? "Unknown",
                              budgetMin: 0,
                              budgetMax: 99999,
                              preferredStartTime: DateTime.now(),
                              preferredEndTime:
                                  DateTime.now().add(const Duration(hours: 2)),
                              results: matches,
                            ),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFED9121),
                        foregroundColor: Colors.white,
                      ),
                      child: const Text("Book now"),
                    ),
                  ]),
            ),
            Image.asset('assets/worker.png', height: 80),
          ],
        ),
      );

  // =========================
  // Top Workers (slightly responsive card width)
  // =========================
  Widget _topWorkersSection(double screenWidth) {
    final double cardWidth = screenWidth >= 1000 ? 220 : 200;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFED9121).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.star,
                      color: Color(0xFFED9121), size: 20),
                ),
                const SizedBox(width: 8),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Top Workers",
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    Text("Best rated by reviews",
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ],
            ),
            const Spacer(),
            TextButton(
              onPressed: () {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AvailableProvidersScreen()));
              },
              child: const Text("See All",
                  style: TextStyle(
                      color: Color(0xFFED9121), fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_topWorkers.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Column(
              children: [
                Icon(Icons.star_border, size: 48, color: Colors.grey[400]),
                const SizedBox(height: 12),
                Text('No top workers yet',
                    style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Text('Top rated workers will appear here\nbased on reviews',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    textAlign: TextAlign.center),
              ],
            ),
          )
        else
          SizedBox(
            height: 220,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _topWorkers.length,
              itemBuilder: (context, index) {
                final worker = _topWorkers[index];
                final rating = (worker['rating'] as num).toDouble();
                final reviewCount = worker['review_count'] as int;
                final isTopRated = index == 0;

                return Container(
                  width: cardWidth,
                  margin: const EdgeInsets.only(right: 16),
                  child: Card(
                    elevation: isTopRated ? 4 : 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: isTopRated
                          ? const BorderSide(color: Color(0xFFED9121), width: 2)
                          : BorderSide.none,
                    ),
                    child: InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => ProviderProfileScreen(
                                  workerId: worker['id'])),
                        );
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (isTopRated)
                              Container(
                                margin: const EdgeInsets.only(bottom: 4),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFED9121),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text('⭐ BEST',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold)),
                              ),
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                CircleAvatar(
                                  radius: 40,
                                  backgroundColor:
                                      const Color(0xFFED9121).withOpacity(0.1),
                                  backgroundImage: worker['profile_image'] !=
                                              null &&
                                          worker['profile_image']
                                              .toString()
                                              .isNotEmpty
                                      ? NetworkImage(
                                          worker['profile_image'].toString())
                                      : null,
                                  child: (worker['profile_image'] == null ||
                                          worker['profile_image']
                                              .toString()
                                              .isEmpty)
                                      ? const Icon(Icons.person,
                                          color: Color(0xFFED9121), size: 40)
                                      : null,
                                ),
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: rating >= 4.5
                                          ? Colors.green
                                          : Colors.amber,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: Colors.white, width: 2),
                                    ),
                                    child: const Icon(Icons.star,
                                        size: 14, color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              worker['name'] ?? 'Worker',
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(5, (i) {
                                return Icon(
                                  i < rating.round()
                                      ? Icons.star
                                      : Icons.star_border,
                                  color: Colors.amber,
                                  size: 16,
                                );
                              }),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${rating.toStringAsFixed(1)} ($reviewCount ${reviewCount == 1 ? "review" : "reviews"})',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w500),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  // =========================
  // Nearby Providers (wrapped in Card to look better on web)
  // =========================
  Widget _nearbyProvidersSection() => Column(
        children: [
          Row(
            children: [
              const Text("Near You",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Spacer(),
              TextButton(
                onPressed: () {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AvailableProvidersScreen()));
                },
                child: const Text("See All",
                    style: TextStyle(color: Color(0xFFED9121))),
              ),
            ],
          ),
          if (_providers.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                  child: Text("No verified or available providers nearby.")),
            )
          else
            Column(
              children: _providers.map((p) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFED9121),
                      child: Icon(Icons.verified, color: Colors.white),
                    ),
                    title: Text(p['name']),
                    subtitle: Text(
                      "⭐ ${p['rating'].toStringAsFixed(1)} | ₱${p['hourly_rate']} / hr | ${(p['distance_km'] ?? 0).toStringAsFixed(1)} km away",
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              ProviderProfileScreen(workerId: p['id'])),
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      );

  // =========================
  // Bottom Nav
  // =========================
  Widget _bottomNavBar() => BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentIndex,
        selectedItemColor: Colors.orange,
        unselectedItemColor: Colors.grey,
        onTap: (i) {
          setState(() => _currentIndex = i);
          switch (i) {
            case 1:
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const MyBookingsScreen()));
              break;
            case 2:
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ChatListScreen()));
              break;
            case 3:
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ProfilePage()));
              break;
          }
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
          BottomNavigationBarItem(icon: Icon(Icons.book), label: "Bookings"),
          BottomNavigationBarItem(icon: Icon(Icons.chat), label: "Chats"),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: "Profile"),
        ],
      );
}
