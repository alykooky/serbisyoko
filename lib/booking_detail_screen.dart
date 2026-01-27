import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'live_navigation_screen.dart';
import 'services/notification_service.dart';
import 'ServiceProviderDashboard.dart';

class BookingDetailScreen extends StatefulWidget {
  final String bookingId;
  const BookingDetailScreen({super.key, required this.bookingId});

  @override
  State<BookingDetailScreen> createState() => _BookingDetailScreenState();
}

class _BookingDetailScreenState extends State<BookingDetailScreen> {
  final sb = Supabase.instance.client;

  bool _loading = true;
  String? _error; // <-- show why it failed instead of spinning forever
  Map<String, dynamic>? _booking; // booking + (optional) client
  Position? _me;
  List<LatLng> _route = [];
  bool _isWorker = false; // Track if current user is the worker

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _booking = null;
      _route.clear();
      _me = null;
    });

    try {
      // 1) Fetch booking (only query columns that exist)
      final row = await sb
          .from('bookings')
          .select('id, client_id, worker_id, status, service_type, scheduled_time, scheduled_end, duration_minutes, location, client_address, problem_details, price, estimated_price, booking_fee, client_lat, client_lng')
          .eq('id', widget.bookingId)
          .maybeSingle();

      if (row == null) {
        setState(() => _error = 'Booking not found.');
        return;
      }

      final booking = Map<String, dynamic>.from(row);
      
      // Debug: Log the location fields to see what's stored
      debugPrint('📍 Booking location fields:');
      debugPrint('   location: ${booking['location']}');
      debugPrint('   client_address: ${booking['client_address']}');
      debugPrint('   client_lat: ${booking['client_lat']}');
      debugPrint('   client_lng: ${booking['client_lng']}');

      // 2) Fetch client "public" info (try a view first, fall back to users)
      try {
        final pubClient = await sb
            .from('users_public') // recommended safer view
            .select('id, name, phone, email')
            .eq('id', booking['client_id'])
            .maybeSingle();

        if (pubClient != null) {
          booking['client'] = Map<String, dynamic>.from(pubClient);
        }
      } catch (_) {
        // If the view doesn't exist, try a narrow select on users
        try {
          final cli = await sb
              .from('users')
              .select('id, name, first_name, last_name, email, phone')
              .eq('id', booking['client_id'])
              .maybeSingle();
          if (cli != null) booking['client'] = Map<String, dynamic>.from(cli);
        } catch (_) {}
      }

      _booking = booking;

      // Check if current user is the worker
      final currentUser = sb.auth.currentUser;
      if (currentUser != null) {
        _isWorker = booking['worker_id']?.toString() == currentUser.id;
      }

      // 3) Current worker location (don't block UI if it fails)
      await _getLocation().timeout(const Duration(seconds: 4), onTimeout: () {});

      // 4) Build route polyline (timeout so it never stalls UI)
      await _buildRoute().timeout(const Duration(seconds: 6), onTimeout: () {});
    } on PostgrestException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _getLocation() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return;

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse) {
        _me = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
        );
      }
    } catch (_) {}
  }

  Future<void> _buildRoute() async {
    final lat = (_booking?['client_lat'] as num?)?.toDouble();
    final lng = (_booking?['client_lng'] as num?)?.toDouble();
    if (lat == null || lng == null || _me == null) return;

    final start = '${_me!.longitude},${_me!.latitude}';
    final end = '$lng,$lat';
    final url = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/$start;$end?overview=full&geometries=geojson',
    );

    try {
      final r = await http.get(url);
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body);
        final coords =
            (j['routes']?[0]?['geometry']?['coordinates'] ?? []) as List;
        _route = coords
            .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
            .toList();
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  Future<void> _openExternalNav() async {
    final lat = (_booking?['client_lat'] as num?)?.toDouble();
    final lng = (_booking?['client_lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return;

    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: _appBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: _appBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.red),
                const SizedBox(height: 8),
                Text(
                  'Failed to load booking:\n$_error',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _load,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_booking == null) {
      return Scaffold(
        appBar: _appBar(),
        body: const Center(child: Text('Booking not found')),
      );
    }

    final b = _booking!;
    
    // Parse scheduled time safely
    DateTime? startAt;
    try {
      final scheduledTime = b['scheduled_time'];
      if (scheduledTime != null) {
        startAt = scheduledTime is DateTime 
            ? scheduledTime 
            : DateTime.parse(scheduledTime.toString());
      }
    } catch (e) {
      debugPrint('Error parsing scheduled_time: $e');
    }

    if (startAt == null) {
      startAt = DateTime.now(); // Fallback
    }

    // Calculate end time
    final int? durationMin = (b['duration_minutes'] as num?)?.toInt();
    DateTime? endAt;
    
    try {
      if (b['scheduled_end'] != null) {
        final scheduledEnd = b['scheduled_end'];
        endAt = scheduledEnd is DateTime
            ? scheduledEnd
            : DateTime.parse(scheduledEnd.toString());
      }
    } catch (e) {
      debugPrint('Error parsing scheduled_end: $e');
    }

    // If no end time, calculate from duration
    if (endAt == null && durationMin != null && durationMin > 0) {
      endAt = startAt.add(Duration(minutes: durationMin));
    } else if (endAt == null) {
      endAt = startAt; // Same as start if no duration
    }

    // Format date
    final String dateStr = DateFormat('EEEE, dd/MM/yyyy').format(startAt);
    
    // Format time slot - only show range if times are different
    final String slotStr;
    if (endAt.difference(startAt).inMinutes <= 1) {
      // Same time or less than 1 minute difference
      slotStr = DateFormat('h:mm a').format(startAt);
    } else {
      slotStr = '${DateFormat('h:mm a').format(startAt)} - ${DateFormat('h:mm a').format(endAt)}';
    }

    // Format duration
    final String durStr;
    if (durationMin == null || durationMin <= 0) {
      durStr = '—';
    } else if (durationMin < 60) {
      durStr = '$durationMin min';
    } else if (durationMin % 60 == 0) {
      final hours = durationMin ~/ 60;
      durStr = hours == 1 ? '1 hour' : '$hours hours';
    } else {
      final hours = durationMin ~/ 60;
      final minutes = durationMin % 60;
      durStr = '${hours}h ${minutes}m';
    }


    return Scaffold(
      appBar: _appBar(),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Header(b: b),
          const SizedBox(height: 12),
          _InfoRow(
            icon: Icons.build_outlined,
            label: 'Service',
            value: _getServiceType(b),
          ),
          _InfoRow(
            icon: Icons.notes,
            label: 'What to fix / do',
            value: _getProblemDetails(b),
          ),
          _InfoRow(
            icon: Icons.payments_outlined,
            label: 'Estimated Price',
            value: _getPriceDisplay(b),
          ),
          _InfoRow(
            icon: Icons.place_outlined,
            label: 'Address',
            value: _getAddress(b),
          ),
          _InfoRow(
            icon: Icons.event,
            label: 'Date',
            value: dateStr,
          ),
          _InfoRow(
            icon: Icons.schedule,
            label: 'Time Slot',
            value: slotStr,
          ),
          _InfoRow(
            icon: Icons.timelapse,
            label: 'Duration',
            value: durStr,
          ),

          const SizedBox(height: 12),
          _MapBox(
            clientLat: _getClientLat(b),
            clientLng: _getClientLng(b),
            clientAddress: (b['client_address'] ?? b['location'] ?? '').toString(),
            me: _me == null ? null : LatLng(_me!.latitude, _me!.longitude),
            route: _route,
          ),
          const SizedBox(height: 12),
          
          // Show different buttons based on user role and booking status
          if (_isWorker) ...[
            // Worker view - show navigation and finish job buttons
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFED9121),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
              ),
              icon: const Icon(Icons.navigation),
              label: const Text('Start Navigation'),
              onPressed: () async {
                final b = _booking;
                if (b == null) return;

                // Update status to InProgress when starting navigation (if currently Accepted)
                final currentStatus = (b['status']?.toString() ?? '').toLowerCase();
                if (currentStatus == 'accepted' || currentStatus == 'pending') {
                  try {
                    await sb
                        .from('bookings')
                        .update({'status': 'InProgress'})
                        .eq('id', b['id'].toString());
                    
                    // Notify client that worker is on the way
                    final clientId = b['client_id']?.toString();
                    final serviceType = b['service_type']?.toString() ?? 'Service';
                    
                    if (clientId != null) {
                      await NotificationService.createNotification(
                        userId: clientId,
                        type: 'booking_status_changed',
                        title: 'Worker On The Way!',
                        message: 'Your worker is now heading to your location for "$serviceType". You can track their location in the booking details.',
                        relatedId: b['id'].toString(),
                        relatedType: 'booking',
                      );
                    }
                    
                    // Reload booking data
                    await _load();
                  } catch (e) {
                    debugPrint('Error updating status to InProgress: $e');
                  }
                }

                final client = (b['client'] ?? {}) as Map<String, dynamic>;
                final name = (client['name'] ??
                    '${(client['first_name'] ?? '').toString().trim()}'
                    '${(client['last_name'] ?? '').toString().trim()}')
                    .toString()
                    .trim();
                
                if (!mounted) return;
                
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => LiveNavigationScreen(
                      bookingId: b['id'].toString(),
                      clientName: ((b['client']?['name'] ??
                      '${(b['client']?['first_name'] ?? '').toString().trim()}'
                      '${(b['client']?['last_name'] ?? '').toString().trim()}') as String)
                      .trim(),
                      clientPhone: (b['client']?['phone'] ?? '').toString(),
                      clientEmail: (b['client']?['email'] ?? '').toString(),
                      clientAddress: (b['client_address'] ?? b['location'] ?? '').toString(),
                      problemDetails: (b['problem_details'] ?? '').toString(),
                      price: (b['price'] as num?)?.toDouble(),
                      clientLat: (b['client_lat'] as num?)?.toDouble(),
                      clientLng: (b['client_lng'] as num?)?.toDouble(),
                    ),
                  ),
                ).then((_) {
                  // Reload when returning from navigation
                  if (mounted) _load();
                });
              },
            ),
            const SizedBox(height: 8),
            // Finish Job button for workers (when status is Accepted or InProgress)
            if ((b['status']?.toString().toLowerCase() == 'accepted' ||
                b['status']?.toString().toLowerCase() == 'inprogress'))
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                ),
                icon: const Icon(Icons.check_circle),
                label: const Text('Finish Job'),
                onPressed: () => _finishJob(b['id'].toString()),
              ),
          ] else ...[
            // Client view - just navigation button
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFED9121),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
              ),
              icon: const Icon(Icons.navigation),
              label: const Text('View Location'),
              onPressed: _openExternalNav,
            ),
          ],
        ],
      ),
    );
  }

  String _getPriceDisplay(Map<String, dynamic> booking) {
    // Try price first, then estimated_price, then booking_fee
    final price = (booking['price'] as num?)?.toInt();
    if (price != null && price > 0) {
      return '₱${price.toStringAsFixed(0)}';
    }
    
    final estimatedPrice = (booking['estimated_price'] as num?)?.toInt();
    if (estimatedPrice != null && estimatedPrice > 0) {
      return '₱${estimatedPrice.toStringAsFixed(0)}';
    }
    
    final bookingFee = (booking['booking_fee'] as num?)?.toInt();
    if (bookingFee != null && bookingFee > 0) {
      return '₱${bookingFee.toStringAsFixed(0)}';
    }
    
    return '—';
  }

  String _getServiceType(Map<String, dynamic> booking) {
    final serviceType = booking['service_type']?.toString().trim();
    if (serviceType != null && serviceType.isNotEmpty && serviceType != 'null') {
      return serviceType;
    }
    return '—';
  }

  String _getProblemDetails(Map<String, dynamic> booking) {
    final problemDetails = booking['problem_details']?.toString().trim();
    if (problemDetails != null && 
        problemDetails.isNotEmpty && 
        problemDetails != 'null' &&
        problemDetails != '-') {
      return problemDetails;
    }
    return '—';
  }

  String _getAddress(Map<String, dynamic> booking) {
    // Try client_address first (most reliable), then location field
    // Display exactly what the client provided
    final clientAddress = booking['client_address']?.toString().trim();
    if (clientAddress != null && 
        clientAddress.isNotEmpty && 
        clientAddress != 'null') {
      return clientAddress;
    }
    
    final location = booking['location']?.toString().trim();
    if (location != null && 
        location.isNotEmpty && 
        location != 'null') {
      return location;
    }
    
    // If we have coordinates but no address text, indicate location is on map
    final lat = _getClientLat(booking);
    final lng = _getClientLng(booking);
    
    if (lat != null && lng != null && lat != 0 && lng != 0) {
      // Coordinates exist - location is available on map
      return 'Location available (see map)';
    }
    
    // No address or coordinates available
    return '—';
  }

  double? _getClientLat(Map<String, dynamic> booking) {
    // Only use client_lat (lat/lng columns don't exist)
    final clientLat = (booking['client_lat'] as num?)?.toDouble();
    if (clientLat != null && clientLat != 0) return clientLat;
    return null;
  }

  double? _getClientLng(Map<String, dynamic> booking) {
    // Only use client_lng (lat/lng columns don't exist)
    final clientLng = (booking['client_lng'] as num?)?.toDouble();
    if (clientLng != null && clientLng != 0) return clientLng;
    return null;
  }

  AppBar _appBar() => AppBar(
        title: const Text('Job Details'),
        backgroundColor: const Color(0xFFED9121),
        foregroundColor: Colors.white,
      );

  Future<void> _finishJob(String bookingId) async {
    const accent = Color(0xFFED9121);
    
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Finish Job?'),
        content: const Text(
          'Are you sure you have completed the service? This will mark the job as completed and notify the client.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Yes, Finish Job'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // Update booking status to Completed
      await sb
          .from('bookings')
          .update({'status': 'Completed'})
          .eq('id', bookingId);

      // Fetch booking to get client ID
      final booking = await sb
          .from('bookings')
          .select('client_id, service_type')
          .eq('id', bookingId)
          .maybeSingle();

      if (booking != null) {
        final clientId = booking['client_id']?.toString();
        final serviceType = booking['service_type']?.toString() ?? 'Service';

        // Send notification to client
        if (clientId != null) {
          await NotificationService.createNotification(
            userId: clientId,
            type: 'booking_status_changed',
            title: 'Service Completed',
            message: 'Your $serviceType service has been completed. Please rate your experience!',
            relatedId: bookingId,
            relatedType: 'booking',
          );
        }
      }

      if (!mounted) return;

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Job marked as completed! Client has been notified.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );

      // Reload booking data
      await _load();

      // Navigate back to dashboard after a short delay
      await Future.delayed(const Duration(seconds: 1));
      
      if (mounted) {
        // Pop all screens until we're at root
        Navigator.popUntil(context, (route) => route.isFirst);
        
        // Navigate to dashboard
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ServiceProviderDashboard()),
        );
      }
    } catch (e) {
      debugPrint('Error finishing job: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.b});
  final Map<String, dynamic> b;

  @override
  Widget build(BuildContext context) {
    final c = (b['client'] ?? {}) as Map<String, dynamic>;
    final name = (c['name'] ??
            '${(c['first_name'] ?? '').toString().trim()} ${(c['last_name'] ?? '').toString().trim()}')
        .toString()
        .trim();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: const Color(0xFFED9121).withOpacity(.15),
              child: Text((name.isEmpty ? 'C' : name[0]).toUpperCase()),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name.isEmpty ? 'Client' : name,
                      style:
                          const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  if ((c['email'] ?? '').toString().isNotEmpty) Text(c['email']),
                  if ((c['phone'] ?? '').toString().isNotEmpty) Text(c['phone']),
                ],
              ),
            ),
            Chip(label: Text((b['status'] ?? 'pending').toString())),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: const Color(0xFFED9121)),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(value),
    );
  }
}

class _MapBox extends StatelessWidget {
  const _MapBox({
    this.clientLat,
    this.clientLng,
    required this.clientAddress,
    this.me,
    required this.route,
  });
  final double? clientLat;
  final double? clientLng;
  final String clientAddress;
  final LatLng? me;
  final List<LatLng> route;

  @override
  Widget build(BuildContext context) {
    // Check if we have valid client coordinates
    final hasClientLocation = clientLat != null && 
                              clientLng != null && 
                              clientLat != 0 && 
                              clientLng != 0;

    if (!hasClientLocation) {
      return Container(
        height: 200,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.grey.shade100,
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.location_off, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 8),
            Text(
              'No client location provided',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
            ),
            // Show address if valid, otherwise show coordinates
            if (clientAddress.isNotEmpty && 
                clientAddress != '—' &&
                !['Unknown Location', 'Unknown location', 'unknown location'].contains(clientAddress))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  clientAddress,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 12,
                  ),
                ),
              )
            else if (clientLat != null && clientLng != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Coordinates: ${clientLat!.toStringAsFixed(6)}, ${clientLng!.toStringAsFixed(6)}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
          ],
        ),
      );
    }

    final clientLocation = LatLng(clientLat!, clientLng!);
    final center = me ?? clientLocation;

    return SizedBox(
      height: 260,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: FlutterMap(
          options: MapOptions(
            initialCenter: center,
            initialZoom: me != null ? 14 : 15, // Zoom in more if only showing client
            minZoom: 10,
            maxZoom: 18,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
              subdomains: const ['a', 'b', 'c'],
              userAgentPackageName: 'com.example.app',
            ),
            if (route.isNotEmpty)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: route,
                    strokeWidth: 4,
                    color: Colors.blue,
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                // Client location marker (always shown)
                Marker(
                  point: clientLocation,
                  width: 50,
                  height: 60,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.withOpacity(0.3),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.location_pin,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: Text(
                          'Client',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.red[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Worker location marker (if available)
                if (me != null)
                  Marker(
                    point: me!,
                    width: 40,
                    height: 50,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.blue.withOpacity(0.3),
                                blurRadius: 6,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.my_location,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                        Container(
                          margin: const EdgeInsets.only(top: 2),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 2,
                              ),
                            ],
                          ),
                          child: Text(
                            'You',
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue[700],
                            ),
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
    );
  }
}
