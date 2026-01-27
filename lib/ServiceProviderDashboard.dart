import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:latlong2/latlong.dart';

// ==== SCREENS (adjust paths if needed) ====
import 'login.dart';
import 'profile.dart';
import 'verification_status_screen.dart';
import 'admin_verification_dashboard.dart';
import 'gigs_manage.dart';
import 'presence_service.dart';
import 'worker_availability_screen.dart';
import 'worker_calendar_screen.dart';
import 'browse_side_gigs.dart';
import 'worker_chats_list.dart';
import 'my_bookings.dart';
import 'booking_detail_screen.dart';
import 'screens/match_map_page.dart';
import 'screens/manage_skills_screen.dart';
import 'worker_browse_jobs_page.dart';
import 'worker_bookings_history.dart';
import 'worker_earnings_screen.dart';
import 'side_gig_detail_screen.dart';
import 'services/notification_service.dart';
import 'screens/notifications_screen.dart';

class ServiceProviderDashboard extends StatefulWidget {
  const ServiceProviderDashboard({super.key});

  @override
  State<ServiceProviderDashboard> createState() =>
      _ServiceProviderDashboardState();
}

class _ServiceProviderDashboardState extends State<ServiceProviderDashboard> {
  final _supabase = Supabase.instance.client;

  // ====== Loading & heartbeat ======
  bool _loading = true;
  Timer? _heartbeatTimer;
  Timer?
      _scheduleCheckTimer; // Timer to check schedule availability periodically
  RealtimeChannel? _availabilityChannel;
  RealtimeChannel? _bookingsChannel;

  // ====== Worker & profile ======
  String _uid = '';
  String _workerName = '';
  String _address = 'Tap to update location';
  double? _lat;
  double? _lng;

  bool _isVerified = false;
  bool _isAvailable = false;

  // NEW: enum-style verification status (from code2)
  // Values: 'unverified', 'requested', 'pending', 'verified'
  String _verificationStatus = 'unverified';

  // ====== Stats ======
  int _jobsToday = 0;
  int _weekJobs = 0;
  double _rating = 0.0;

  // ====== Upcoming jobs (accepted/confirmed, scheduled for future) ======
  List<Map<String, dynamic>> _upcomingJobs = [];

  // ====== Matched jobs (pending bookings that need accept/decline action) ======
  List<Map<String, dynamic>> _matchedJobs = [];

  // ====== Notifications (bell) ======
  int _notifCount = 0;
  final List<Map<String, dynamic>> _notiFeed = [];
  int _newAssignedCount = 0;

  // ====== Bottom bar ======
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    PresenceService.instance.start(online: false);
    _bootstrap();
  }

  @override
  void dispose() {
    _availabilityChannel?.unsubscribe();
    _bookingsChannel?.unsubscribe();
    PresenceService.instance.stop();
    _heartbeatTimer?.cancel();
    _scheduleCheckTimer?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      // Not logged in → go to sign-in
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const SignInScreen()),
        (r) => false,
      );
      return;
    }
    _uid = user.id;

    await _initDashboard();
    _listenToAvailability();
    _listenToBookings();

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _initDashboard() async {
    await _fetchWorkerProfileAndLocation();
    await _fetchStats();
    await _fetchUpcomingJobs();
    await _fetchMatchedJobs();
  }

  // ====== Worker profile + location (merged, with enum verification) ======
  Future<void> _fetchWorkerProfileAndLocation() async {
    try {
      final userRow = await _supabase
          .from('users')
          .select(
              'first_name, last_name, location_address, latitude, longitude')
          .eq('id', _uid)
          .maybeSingle();

      final profile = await _supabase
          .from('worker_profiles')
          .select('is_verified, availability_status, verification_status')
          .eq('user_id', _uid)
          .maybeSingle();

      _workerName =
          "${userRow?['first_name'] ?? ''} ${userRow?['last_name'] ?? ''}"
              .trim();

      _address = userRow?['location_address'] ?? 'Tap to update location';
      _lat = (userRow?['latitude'] as num?)?.toDouble();
      _lng = (userRow?['longitude'] as num?)?.toDouble();

      final rawVerifStatus =
          profile?['verification_status']?.toString() ?? 'unverified';

      _verificationStatus = rawVerifStatus;
      _isVerified = rawVerifStatus == 'verified' ||
          (profile?['is_verified'] == true); // backward-compatible

      _isAvailable = (profile?['availability_status'] ?? 'OFF') == 'ON';

      // Check actual schedule to determine if worker should be available now
      final shouldBeAvailable = await _checkScheduleAvailability();

      // Auto-update availability status if it doesn't match schedule
      if (_isAvailable != shouldBeAvailable) {
        debugPrint(
            '🕐 Schedule check: Status is ${_isAvailable ? "ON" : "OFF"} but schedule says ${shouldBeAvailable ? "available" : "unavailable"}. Auto-updating...');
        _isAvailable = shouldBeAvailable;
        // Update the database status to match schedule
        try {
          await _supabase.from('worker_profiles').update({
            'availability_status': shouldBeAvailable ? 'ON' : 'OFF'
          }).eq('user_id', _uid);
        } catch (e) {
          debugPrint('⚠️ Error auto-updating availability status: $e');
        }
      }

      if (mounted) {
        setState(() {});
      }
      _startOrStopHeartbeat(_isAvailable);
      _startScheduleCheckTimer(); // Start periodic schedule checking
    } catch (e) {
      debugPrint("❌ Error fetching worker profile/location: $e");
    }
  }

  // ====== Schedule Check Timer ======
  void _startScheduleCheckTimer() {
    _scheduleCheckTimer?.cancel();
    // Check schedule every 30 seconds to update availability status in real-time
    _scheduleCheckTimer =
        Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!mounted) return;
      try {
        final shouldBeAvailable = await _checkScheduleAvailability();
        if (_isAvailable != shouldBeAvailable) {
          debugPrint(
              '🕐 Schedule check: Updating availability from ${_isAvailable ? "ON" : "OFF"} to ${shouldBeAvailable ? "ON" : "OFF"}');
          _isAvailable = shouldBeAvailable;
          // Update the database status to match schedule
          try {
            await _supabase.from('worker_profiles').update({
              'availability_status': shouldBeAvailable ? 'ON' : 'OFF'
            }).eq('user_id', _uid);
            if (mounted) {
              setState(() {});
              _startOrStopHeartbeat(_isAvailable);
            }
          } catch (e) {
            debugPrint('⚠️ Error auto-updating availability status: $e');
          }
        }
      } catch (e) {
        debugPrint('⚠️ Error in schedule check timer: $e');
      }
    });
  }

  // ====== Stats ======
  Future<void> _fetchStats() async {
    try {
      final today = DateTime.now();
      final startOfWeek =
          today.subtract(Duration(days: today.weekday - 1)); // Monday

      final bookings = await _supabase
          .from('bookings')
          .select('status, scheduled_time')
          .eq('worker_id', _uid);

      final todayCount = bookings.where((b) {
        final dt = DateTime.tryParse(b['scheduled_time'] ?? '');
        if (dt == null) return false;
        return dt.year == today.year &&
            dt.month == today.month &&
            dt.day == today.day &&
            (b['status'] ?? '') != 'cancelled';
      }).length;

      final weekCount = bookings.where((b) {
        final dt = DateTime.tryParse(b['scheduled_time'] ?? '');
        if (dt == null) return false;
        return dt.isAfter(startOfWeek);
      }).length;

      final ratings =
          await _supabase.from('ratings').select('score').eq('worker_id', _uid);

      double avgRating = 0;
      if (ratings.isNotEmpty) {
        final total =
            ratings.fold<num>(0, (a, b) => a + ((b['score'] ?? 0) as num));
        avgRating = total / ratings.length;
      }

      if (mounted) {
        setState(() {
          _jobsToday = todayCount;
          _weekJobs = weekCount;
          _rating = avgRating;
        });
      }
    } catch (e) {
      debugPrint("❌ Error fetching stats: $e");
    }
  }

  // ====== Upcoming jobs (accepted/confirmed, scheduled for future) ======
  Future<void> _fetchUpcomingJobs() async {
    try {
      final now = DateTime.now();
      debugPrint('🔍 Fetching upcoming jobs for worker: $_uid');

      // Fetch all bookings first
      final allData = await _supabase.from('bookings').select('''
            id, service_type, scheduled_time, location, status,
            price, problem_details, client_lat, client_lng, client_address,
            client:client_id ( id, name, first_name, last_name, email, phone )
          ''').eq('worker_id', _uid).order('scheduled_time', ascending: true);

      debugPrint('📊 Fetched ${allData.length} total bookings for worker');

      final bookings =
          (allData as List).map((b) => Map<String, dynamic>.from(b)).toList();

      // Filter by status (case-insensitive) - show all accepted/inprogress regardless of date
      // This ensures accepted bookings are visible even if scheduled in the past
      final upcoming = bookings.where((booking) {
        // Check status (case-insensitive)
        final status = (booking['status']?.toString() ?? '').toLowerCase();
        debugPrint('   Checking booking ${booking['id']}: status="$status"');

        // Only filter by status - accept all accepted/inprogress bookings
        final isAcceptedOrInProgress =
            status == 'accepted' || status == 'inprogress';

        if (!isAcceptedOrInProgress) {
          debugPrint(
              '     ❌ Status "$status" does not match accepted/inprogress');
          return false;
        }

        // Log the scheduled time for reference but don't filter by date
        final scheduledTimeStr = booking['scheduled_time']?.toString();
        if (scheduledTimeStr != null) {
          final scheduledTime = DateTime.tryParse(scheduledTimeStr);
          if (scheduledTime != null) {
            final isFuture = scheduledTime.isAfter(now);
            final isToday = scheduledTime.year == now.year &&
                scheduledTime.month == now.month &&
                scheduledTime.day == now.day;
            final dateLabel =
                isFuture ? "future" : (isToday ? "today" : "past");
            debugPrint('     📅 Scheduled: $scheduledTime ($dateLabel)');
          }
        }

        debugPrint(
            '   ✅ UPCOMING: Booking ${booking['id']} with status "$status"');
        return true; // Accept all accepted/inprogress bookings regardless of date
      }).toList();

      debugPrint(
          '✅ Found ${upcoming.length} upcoming jobs out of ${bookings.length} total');

      if (mounted) {
        setState(() => _upcomingJobs = upcoming);
      }
    } catch (e) {
      debugPrint("❌ Error fetching upcoming jobs: $e");
      debugPrint("   Stack trace: ${StackTrace.current}");
    }
  }

  // ====== Matched jobs (pending bookings that need action) ======
  Future<void> _fetchMatchedJobs() async {
    try {
      debugPrint('🔍 Fetching matched jobs for worker: $_uid');

      // Fetch all bookings for this worker first to debug
      final allBookings = await _supabase
          .from('bookings')
          .select('id, status, worker_id')
          .eq('worker_id', _uid);

      debugPrint('📊 All bookings for worker: ${allBookings.length}');
      for (var b in allBookings) {
        debugPrint('   - Booking ${b['id']}: status="${b['status']}"');
      }

      // Fetch all bookings and filter by status (case-insensitive)
      final allData = await _supabase.from('bookings').select('''
            id, service_type, scheduled_time, location, status,
            price, problem_details, client_lat, client_lng, client_address,
            client:client_id ( id, name, first_name, last_name, email, phone )
          ''').eq('worker_id', _uid).order('scheduled_time', ascending: true);

      // Filter for pending status (case-insensitive)
      final pendingData = (allData as List).where((booking) {
        final status = (booking['status']?.toString() ?? '').toLowerCase();
        return status == 'pending';
      }).toList();

      debugPrint(
          '✅ Found ${pendingData.length} pending bookings out of ${allData.length} total');

      if (mounted) {
        setState(
            () => _matchedJobs = List<Map<String, dynamic>>.from(pendingData));
      }
    } catch (e) {
      debugPrint("❌ Error fetching matched jobs: $e");
      debugPrint("   Stack trace: ${StackTrace.current}");
    }
  }

  // ====== Heartbeat (worker_status.last_seen) ======
  void _startOrStopHeartbeat(bool on) {
    _heartbeatTimer?.cancel();
    if (!on) return;

    _heartbeatTimer = Timer.periodic(const Duration(seconds: 45), (_) async {
      if (!mounted) return;
      try {
        await _supabase.from('worker_status').update({
          'last_seen': DateTime.now().toIso8601String(),
        }).eq('user_id', _uid);
      } catch (_) {}
    });
  }

  // ====== Availability realtime (now also listens to verification_status) ======
  void _listenToAvailability() {
    _availabilityChannel?.unsubscribe();
    _availabilityChannel = _supabase.channel('worker_profile_changes')
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'worker_profiles',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: _uid,
        ),
        callback: (payload) {
          final newStatus = payload.newRecord['availability_status'];
          final newVerif = payload.newRecord['verification_status'];

          if (newStatus != null && mounted) {
            setState(() => _isAvailable = newStatus == 'ON');
            _startOrStopHeartbeat(_isAvailable);
          }

          if (newVerif != null && mounted) {
            setState(() {
              _verificationStatus = newVerif.toString();
              _isVerified = _verificationStatus == 'verified';
            });
          }
        },
      )
      ..subscribe();
  }

  // ====== Bookings realtime ======
  void _listenToBookings() {
    _bookingsChannel?.unsubscribe();
    _bookingsChannel = _supabase
        .channel('public:bookings:worker:$_uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'bookings',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'worker_id',
            value: _uid,
          ),
          callback: (payload) => _onBookingEvent(payload, isInsert: true),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'bookings',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'worker_id',
            value: _uid,
          ),
          callback: (payload) => _onBookingStatusChange(payload),
        )
        .subscribe();
  }

  void _onBookingEvent(PostgresChangePayload payload,
      {required bool isInsert}) {
    final rec = payload.newRecord;
    if (rec == null) return;

    final status = (rec['status'] ?? '').toString().toLowerCase();
    if (status == 'cancelled') return;

    final service = (rec['service_type'] ?? 'Service').toString();
    final when = (rec['scheduled_time'] ?? '').toString();

    if (!mounted) return;

    setState(() {
      _notifCount += 1;
      _notiFeed.insert(0, {
        'title': isInsert ? 'New booking' : 'Booking updated',
        'service': service,
        'when': when,
        'status': status,
      });
      _newAssignedCount += 1;
    });

    // Refresh both lists to ensure proper categorization
    _fetchUpcomingJobs();
    _fetchMatchedJobs();
    _fetchStats();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('${isInsert ? 'New' : 'Updated'} booking: $service')),
    );
  }

  void _onBookingStatusChange(PostgresChangePayload payload) {
    final old = payload.oldRecord ?? {};
    final now = payload.newRecord ?? {};
    final prev = (old['status'] ?? '').toString().toLowerCase();
    final curr = (now['status'] ?? '').toString().toLowerCase();

    if (prev == curr) return;

    debugPrint('🔄 Booking status changed: "$prev" → "$curr"');

    // Always refresh lists when status changes (not just for assigned/confirmed)
    _fetchStats();
    _fetchUpcomingJobs();
    _fetchMatchedJobs();

    // Show notification for certain status changes
    if (curr == 'assigned' || curr == 'confirmed' || curr == 'accepted') {
      _onBookingEvent(payload, isInsert: false);
    }
  }

  // ====== Accept / Decline ======
  Future<void> _confirmAndUpdateStatus({
    required String bookingId,
    required String newStatus, // 'accepted' | 'declined'
    String? serviceType,
  }) async {
    final verb = newStatus == 'accepted' ? 'Accept' : 'Decline';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$verb booking?'),
        content: Text(
          'Are you sure you want to $verb'
          '${serviceType != null ? ' "$serviceType"' : ''} this booking?',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true), child: Text(verb)),
        ],
      ),
    );
    if (ok == true) {
      final row = await _updateBookingStatus(
          bookingId: bookingId, newStatus: newStatus);
      if (row != null && newStatus == 'accepted' && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => BookingDetailScreen(bookingId: bookingId)),
        );
      }
    }
  }

  Future<Map<String, dynamic>?> _updateBookingStatus({
    required String bookingId,
    required String newStatus,
  }) async {
    try {
      // Get booking details before updating to get client_id
      final bookingBefore = await _supabase
          .from('bookings')
          .select('client_id, service_type')
          .eq('id', bookingId)
          .maybeSingle();

      final updated = await _supabase
          .from('bookings')
          .update({'status': newStatus})
          .eq('id', bookingId)
          .select()
          .maybeSingle();

      // Send notification to client
      if (bookingBefore != null) {
        final clientId = bookingBefore['client_id']?.toString();
        final serviceType =
            bookingBefore['service_type']?.toString() ?? 'service';

        if (clientId != null) {
          try {
            if (newStatus.toLowerCase() == 'accepted') {
              await NotificationService.createNotification(
                userId: clientId,
                type: 'booking_status_changed',
                title: 'Booking Accepted',
                message:
                    'Your booking for "$serviceType" has been accepted by the worker.',
                relatedId: bookingId,
                relatedType: 'booking',
              );
            } else if (newStatus.toLowerCase() == 'declined' ||
                newStatus.toLowerCase() == 'cancelled') {
              await NotificationService.createNotification(
                userId: clientId,
                type: 'booking_status_changed',
                title: 'Booking Declined',
                message:
                    'Your booking for "$serviceType" has been declined by the worker. You can find another available worker in your bookings.',
                relatedId: bookingId,
                relatedType: 'booking',
              );
            }
          } catch (e) {
            debugPrint('Error sending notification to client: $e');
            // Don't fail the update if notification fails
          }
        }
      }

      await _fetchStats();
      // Refresh both lists after status change
      await _fetchUpcomingJobs();
      await _fetchMatchedJobs();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Booking $newStatus')),
        );
      }

      return updated as Map<String, dynamic>?;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to update: $e')));
      }
      return null;
    }
  }

  // ====== Check if worker should be available based on schedule ======
  Future<bool> _checkScheduleAvailability() async {
    try {
      // Fetch worker's availability schedule
      final schedules = await _supabase
          .from('worker_availability')
          .select('weekday, start_at, end_at, is_active')
          .eq('user_id', _uid)
          .eq('is_active', true);

      if (schedules.isEmpty) {
        // No schedule set - return current status
        return _isAvailable;
      }

      final now = DateTime.now();
      final currentWeekday = now.weekday; // 1 = Monday, 7 = Sunday
      final currentTimeSeconds = now.hour * 3600 + now.minute * 60 + now.second;

      // Parse time string (HH:MM:SS or HH:MM)
      int _parseTime(String timeStr) {
        final parts = timeStr.split(':');
        final h = int.tryParse(parts[0]) ?? 0;
        final m = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
        return h * 3600 + m * 60;
      }

      // Check if current time is within any active schedule slot
      for (final schedule in schedules) {
        if (schedule['is_active'] != true) continue;

        final weekday = schedule['weekday'] as int?;
        if (weekday == null) continue;

        final startStr =
            (schedule['start_at'] ?? schedule['start_time'] ?? '00:00:00')
                .toString();
        final endStr =
            (schedule['end_at'] ?? schedule['end_time'] ?? '23:59:59')
                .toString();

        final startSeconds = _parseTime(startStr);
        final endSeconds = _parseTime(endStr);

        // Check if current weekday matches and time is within range
        if (weekday == currentWeekday) {
          debugPrint(
              '🕐 Checking schedule: weekday=$currentWeekday, start=$startStr ($startSeconds), end=$endStr ($endSeconds), current=${now.hour}:${now.minute} ($currentTimeSeconds)');

          if (startSeconds <= endSeconds) {
            // Normal time range (e.g., 9:00 - 17:00)
            final withinRange = currentTimeSeconds >= startSeconds &&
                currentTimeSeconds < endSeconds;
            debugPrint(
                '   Normal range check: $currentTimeSeconds >= $startSeconds && $currentTimeSeconds < $endSeconds = $withinRange');
            if (withinRange) {
              debugPrint(
                  '✅ Worker is within schedule: $currentWeekday, ${startStr} - ${endStr}');
              return true;
            }
          } else {
            // Overnight range (e.g., 22:00 - 06:00)
            final withinRange = currentTimeSeconds >= startSeconds ||
                currentTimeSeconds < endSeconds;
            debugPrint(
                '   Overnight range check: $currentTimeSeconds >= $startSeconds || $currentTimeSeconds < $endSeconds = $withinRange');
            if (withinRange) {
              debugPrint(
                  '✅ Worker is within overnight schedule: $currentWeekday, ${startStr} - ${endStr}');
              return true;
            }
          }
        } else {
          debugPrint(
              '   Weekday mismatch: schedule weekday=$weekday, current weekday=$currentWeekday');
        }
      }

      // No matching schedule found - worker should be unavailable
      debugPrint('⏰ Worker is outside scheduled availability window');
      return false;
    } catch (e) {
      debugPrint('⚠️ Error checking schedule availability: $e');
      // On error, return current status
      return _isAvailable;
    }
  }

  // ====== Availability toggle ======
  // Workers can always toggle ON/OFF regardless of schedule
  // This allows workers who don't want to use schedules to work with just the toggle
  Future<void> _toggleAvailability(bool value) async {
    setState(() => _isAvailable = value);
    try {
      await _supabase.from('worker_profiles').update(
          {'availability_status': value ? 'ON' : 'OFF'}).eq('user_id', _uid);

      _startOrStopHeartbeat(value);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Availability ${value ? 'ON' : 'OFF'}")),
        );
      }
    } catch (e) {
      debugPrint("❌ Error updating availability: $e");
    }
  }

  // ====== Posted gigs (merged: code1 + code2 filters) ======
  Future<List<Map<String, dynamic>>> _fetchPostedGigs() async {
    // Try the newer side_gigs schema first (code2)
    try {
      final rows = await _supabase
          .from('side_gigs')
          .select(
              'id, title, description, location, price_offer, status, is_active, assigned_provider_id, created_at')
          .eq('status', 'open')
          .eq('is_active', true)
          .isFilter('assigned_provider_id', null)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      debugPrint("❌ Error fetching side_gigs advanced: $e");
    }

    // Fallback: old gigs table (from code1)
    try {
      final data = await _supabase
          .from('gigs')
          .select('id, title, price, location')
          .order('created_at', ascending: false)
          .limit(5);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint("❌ Error fetching gigs: $e");
    }

    // Final fallback: simple side_gigs
    try {
      final data = await _supabase
          .from('side_gigs')
          .select('id, title, price_offer, location')
          .eq('status', 'open')
          .order('created_at', ascending: false)
          .limit(5);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint("❌ Error fetching fallback side_gigs: $e");
      return [];
    }
  }

  // ====== Clickable Location Picker ======
  Future<void> _openLocationPicker() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MatchMapPage(
          clientPos: LatLng(_lat ?? 7.07, _lng ?? 125.6),
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
        _lat = (result['lat'] as num?)?.toDouble();
        _lng = (result['lng'] as num?)?.toDouble();
        _address = (result['address'] as String?) ?? _address;
      });

      await _supabase.from('users').update({
        'latitude': _lat,
        'longitude': _lng,
        'location_address': _address,
      }).eq('id', _uid);
    }
  }

  // ====== UI ======
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
            child: CircularProgressIndicator(color: const Color(0xFFED9121))),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F2),
      appBar: AppBar(
        backgroundColor: const Color(0xFFED9121),
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _workerName.isNotEmpty ? "Good Day, $_workerName!" : "Good Day!",
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
            GestureDetector(
              onTap: _openLocationPicker,
              child: Row(
                children: [
                  const Icon(Icons.location_on, size: 14, color: Colors.white),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      _address,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // 🔔 Bell + badge - navigate to full notifications screen
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications, color: Colors.white),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const NotificationsScreen(),
                    ),
                  );
                },
              ),
              if (_notifCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('$_notifCount',
                        style:
                            const TextStyle(color: Colors.white, fontSize: 10)),
                  ),
                ),
            ],
          ),
          IconButton(
            icon:
                const Icon(Icons.account_circle, color: Colors.white, size: 28),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfilePage()),
              );
            },
          ),
        ],
      ),

      // ====== BODY ======
      body: RefreshIndicator(
        onRefresh: () async {
          await _initDashboard();
          if (mounted) setState(() => _newAssignedCount = 0);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Stats grid
              GridView.count(
                crossAxisCount: 4,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 0.85, // ⭐ para mas mubo
                children: [
                  StatCard(label: "Jobs\nToday", value: "$_jobsToday"),
                  StatCard(label: "Week's\nJob", value: "$_weekJobs"),
                  StatCard(
                      label: "Average\nRating",
                      value: _rating.toStringAsFixed(1)),
                  StatCard(
                    label: "Active\nStatus",
                    value: _isAvailable ? "ON" : "OFF",
                    isActive: _isAvailable,
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Availability Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: const Color(0xFFED9121).withOpacity(0.3)),
                  boxShadow: const [
                    BoxShadow(
                        color: Colors.black12,
                        blurRadius: 6,
                        offset: Offset(0, 2))
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.power_settings_new,
                            color: Color(0xFFED9121)),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text('Availability',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                        Switch(
                          value: _isAvailable,
                          activeColor: Colors.white,
                          activeTrackColor: const Color(0xFFED9121),
                          onChanged: _toggleAvailability,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const WorkerCalendarScreen(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.calendar_month, size: 18),
                          label: const Text('View Calendar'),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFFED9121),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    const WorkerAvailabilityScreen(),
                              ),
                            ).then((_) {
                              // Refresh availability status after returning
                              _fetchWorkerProfileAndLocation();
                            });
                          },
                          icon: const Icon(Icons.schedule, size: 18),
                          label: const Text('Set schedule'),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFFED9121),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Verification (replaced with enum-based card from code2)
              sectionTitle("Verification Status"),
              _verificationCard(),

              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.build),
                  label: const Text("Manage My Skills"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFED9121),
                    side: const BorderSide(color: Color(0xFFED9121)),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ManageSkillsScreen(workerId: _uid),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 20),

              // Upcoming Jobs (Confirmed & Scheduled) - Different UI
              sectionTitle(
                "Upcoming Jobs",
                icon: Icons.schedule,
                color: Colors.green,
                onSeeAll: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const WorkerBookingsHistoryScreen(
                        initialTabIndex: 2, // Upcoming tab
                      ),
                    ),
                  ).then((_) {
                    // Refresh after returning
                    _fetchUpcomingJobs();
                    _fetchMatchedJobs();
                  });
                },
              ),
              _upcomingJobs.isEmpty
                  ? Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today_outlined,
                              color: Colors.grey[600]),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              "No upcoming confirmed jobs.",
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: _upcomingJobs.take(3).map((job) {
                        final scheduledTimeStr =
                            job['scheduled_time']?.toString();
                        DateTime? scheduledTime;
                        if (scheduledTimeStr != null) {
                          scheduledTime = DateTime.tryParse(scheduledTimeStr);
                        }

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                                color: Colors.green.withOpacity(0.3)),
                          ),
                          child: ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.check_circle,
                                  color: Colors.green),
                            ),
                            title: Text(
                              job['service_type'] ?? 'Service',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (scheduledTime != null) ...[
                                  Text(
                                      '📅 ${scheduledTime.day}/${scheduledTime.month}/${scheduledTime.year}'),
                                  Text(
                                      '🕐 ${scheduledTime.hour.toString().padLeft(2, '0')}:${scheduledTime.minute.toString().padLeft(2, '0')}'),
                                ],
                                if (job['location'] != null)
                                  Text('📍 ${job['location']}'),
                              ],
                            ),
                            trailing: ElevatedButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => BookingDetailScreen(
                                      bookingId: job['id'].toString(),
                                    ),
                                  ),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text("View"),
                            ),
                          ),
                        );
                      }).toList(),
                    ),

              const SizedBox(height: 20),

              // Browse Jobs Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.search),
                  label: const Text("Browse Job Posts"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFED9121),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const WorkerBrowseJobsPage(),
                      ),
                    ).then((_) {
                      // Refresh after returning from browse jobs
                      _fetchMatchedJobs();
                      _fetchUpcomingJobs();
                    });
                  },
                ),
              ),

              const SizedBox(height: 20),

              // Matched Jobs (Pending - Need Action) - Different UI
              sectionTitle(
                "Pending Requests",
                icon: Icons.pending_actions,
                color: const Color(0xFFED9121),
                onSeeAll: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const WorkerBookingsHistoryScreen(
                        initialTabIndex: 1, // Pending tab
                      ),
                    ),
                  ).then((_) {
                    // Refresh after returning
                    _fetchMatchedJobs();
                    _fetchUpcomingJobs();
                  });
                },
              ),
              _matchedJobs.isEmpty
                  ? Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFED9121).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: const Color(0xFFED9121).withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline,
                              color: const Color(0xFFED9121)),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              "No pending booking requests. Browse job posts to find opportunities.",
                              style: TextStyle(color: Colors.black87),
                            ),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: _matchedJobs.take(3).map((job) {
                        final id = job['id'].toString();
                        final scheduledTimeStr =
                            job['scheduled_time']?.toString();
                        DateTime? scheduledTime;
                        if (scheduledTimeStr != null) {
                          scheduledTime = DateTime.tryParse(scheduledTimeStr);
                        }

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                                color:
                                    const Color(0xFFED9121).withOpacity(0.5)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFED9121)
                                            .withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Icon(Icons.pending,
                                          color: Color(0xFFED9121), size: 20),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            job['service_type'] ?? 'Service',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                          if (job['client'] != null)
                                            Text(
                                              'Client: ${job['client']['name'] ?? 'Unknown'}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey[600],
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFED9121)
                                            .withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Text(
                                        'PENDING',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFFED9121),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                if (scheduledTime != null) ...[
                                  Row(
                                    children: [
                                      Icon(Icons.calendar_today,
                                          size: 14, color: Colors.grey[600]),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${scheduledTime.day}/${scheduledTime.month}/${scheduledTime.year} at ${scheduledTime.hour.toString().padLeft(2, '0')}:${scheduledTime.minute.toString().padLeft(2, '0')}',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[700]),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                ],
                                if (job['location'] != null) ...[
                                  Row(
                                    children: [
                                      Icon(Icons.location_on,
                                          size: 14, color: Colors.grey[600]),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          job['location'],
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey[700]),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                ],
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton.icon(
                                      onPressed: () => _confirmAndUpdateStatus(
                                        bookingId: id,
                                        newStatus: 'cancelled',
                                        serviceType:
                                            job['service_type'] as String?,
                                      ),
                                      icon: const Icon(Icons.close, size: 16),
                                      label: const Text('Decline'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.red,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    ElevatedButton.icon(
                                      onPressed: () => _confirmAndUpdateStatus(
                                        bookingId: id,
                                        newStatus: 'accepted',
                                        serviceType:
                                            job['service_type'] as String?,
                                      ),
                                      icon: const Icon(Icons.check, size: 16),
                                      label: const Text('Accept'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                        foregroundColor: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),

              const SizedBox(height: 20),

              // Browse posted gigs
              sectionTitle(
                "Browse posted gig",
                onSeeAll: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const BrowseSideGigsScreen(),
                    ),
                  );
                },
              ),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _fetchPostedGigs(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                        child: CircularProgressIndicator(
                            color: const Color(0xFFED9121)));
                  }
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Text("No posted gigs available.");
                  }
                  final gigs = snapshot.data!;
                  return Column(
                    children: gigs.map((gig) {
                      final title = gig['title']?.toString() ?? 'Untitled Gig';
                      final price = gig['price_offer'] ??
                          gig['price'] ??
                          gig['budget'] ??
                          0;
                      final gigId = gig['id']?.toString();
                      return Card(
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          title:
                              Text(title, style: const TextStyle(fontSize: 14)),
                          subtitle: Text("₱$price",
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFFED9121))),
                          trailing:
                              const Icon(Icons.arrow_forward_ios, size: 16),
                          onTap: gigId != null
                              ? () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => SideGigDetailScreen(
                                        gigId: gigId,
                                      ),
                                    ),
                                  ).then((refresh) {
                                    // Refresh if needed (when gig is accepted)
                                    if (refresh == true) {
                                      // Could refresh the gig list here if needed
                                    }
                                  });
                                }
                              : null,
                        ),
                      );
                    }).toList(),
                  );
                },
              ),

              const SizedBox(height: 30),

              // Manage gigs
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const GigsManageScreen()),
                    );
                  },
                  icon: const Icon(Icons.work_outline),
                  label: const Text('Manage Gigs'),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFED9121)),
                    foregroundColor: const Color(0xFFED9121),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),

      // ====== Bottom bar (keep Code 1 structure with Earnings) ======
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFFED9121),
        unselectedItemColor: Colors.black87,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
          BottomNavigationBarItem(icon: Icon(Icons.chat), label: "Chats"),
          BottomNavigationBarItem(
              icon: Icon(Icons.assignment), label: "My Bookings"),
          BottomNavigationBarItem(
              icon: Icon(Icons.account_balance_wallet), label: "Earnings"),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: "Profile"),
        ],
      ),
    );
  }

  Widget sectionTitle(String text,
      {IconData? icon, Color? color, VoidCallback? onSeeAll}) {
    final textColor = color ?? Colors.black87;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: textColor, size: 20),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: textColor,
              ),
            ),
          ),
          if (onSeeAll != null)
            TextButton(
              onPressed: onSeeAll,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'See All',
                style: TextStyle(
                  color: color ?? const Color(0xFFED9121),
                  fontSize: 14,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);

    if (index == 1) {
      // Chats
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const WorkerChatsList()),
      );
    } else if (index == 2) {
      // My Bookings
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const WorkerBookingsHistoryScreen()),
      );
    } else if (index == 3) {
      // Earnings
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const WorkerEarningsScreen()),
      );
    } else if (index == 4) {
      // Profile
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ProfilePage()),
      );
    }
  }

  // === NEW verification card from code2 (enum-based) ===
  Widget _verificationCard() {
    // Using Map structure instead of records for compatibility
    final Map<String, Map<String, dynamic>> statusMap = {
      'unverified': {
        'label': 'Not Verified',
        'color': const Color(0xFFED9121),
        'help': 'Submit your documents to get started.'
      },
      'requested': {
        'label': 'Requested',
        'color': Colors.blue,
        'help': 'We received your request. Please complete any missing items.'
      },
      'pending': {
        'label': 'Under Review',
        'color': Colors.amber,
        'help': 'An admin is checking your documents.'
      },
      'verified': {
        'label': 'Verified',
        'color': Colors.green,
        'help': 'Your account is verified and visible to clients.'
      },
    };

    final entry = statusMap[_verificationStatus] ?? statusMap['unverified']!;
    final label = entry['label'] as String;
    final color = entry['color'] as Color;
    final help = entry['help'] as String;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(.08),
        border: Border.all(color: color.withOpacity(.35)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.verified_user, color: color, size: 24),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          ]),
          const SizedBox(height: 8),
          Text(help, style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 12),
          if (_verificationStatus != 'verified')
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const VerificationStatusScreen()),
                  );
                },
                icon: const Icon(Icons.upload_file),
                label: const Text("Go to Verification"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFED9121),
                  foregroundColor: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ====== Helper Widgets (unified) ======

class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final bool isActive;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isActive
            ? Colors.green.shade50
            : const Color(0xFFED9121).withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: isActive ? Colors.green : const Color(0xFFED9121))),
          const SizedBox(height: 4),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class JobCard extends StatelessWidget {
  final String icon, title, time, buttonLabel;
  final Color buttonColor;
  const JobCard(
      {super.key,
      required this.icon,
      required this.title,
      required this.time,
      required this.buttonLabel,
      required this.buttonColor});
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(children: [
          Image.asset(icon, width: 40, height: 40),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(time)
              ])),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: buttonColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
            ),
            onPressed: () {},
            child: Text(buttonLabel),
          ),
        ]),
      ),
    );
  }
}

class JobCardWithActions extends StatelessWidget {
  final String icon, title, time;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final String status; // pending/assigned/accepted/declined/completed
  final VoidCallback? onTap; // from code2

  const JobCardWithActions({
    super.key,
    required this.icon,
    required this.title,
    required this.time,
    required this.onAccept,
    required this.onDecline,
    this.status = 'pending',
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isFinal =
        status == 'accepted' || status == 'declined' || status == 'completed';

    return InkWell(
      onTap: onTap,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              Row(children: [
                Image.asset(icon, width: 40, height: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        Text(time),
                        const SizedBox(height: 4),
                        Row(children: [
                          const Icon(Icons.info_outline,
                              size: 14, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text('Status: $status',
                              style: const TextStyle(color: Colors.grey)),
                        ]),
                      ]),
                ),
                if (!isFinal)
                  TextButton(
                    onPressed: onDecline,
                    child: const Text("Decline",
                        style: TextStyle(color: Color(0xFFED9121))),
                  ),
              ]),
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                if (!isFinal)
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFED9121),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                    ),
                    onPressed: onAccept,
                    child: const Text("Accept"),
                  ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
