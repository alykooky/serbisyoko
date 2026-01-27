import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'services/notification_service.dart';
import 'ServiceProviderDashboard.dart';

class LiveNavigationScreen extends StatefulWidget {
  const LiveNavigationScreen({
    super.key,
    required this.bookingId,
    required this.clientName,
    required this.clientPhone,
    required this.clientEmail,
    required this.clientAddress,
    required this.problemDetails,
    required this.price,
    required this.clientLat,
    required this.clientLng,
  });

  final String bookingId;
  final String clientName;
  final String clientPhone;
  final String clientEmail;
  final String clientAddress;
  final String problemDetails;
  final double? price;
  final double? clientLat;
  final double? clientLng;

  @override
  State<LiveNavigationScreen> createState() => _LiveNavigationScreenState();
}

class _LiveNavigationScreenState extends State<LiveNavigationScreen> {
  final _distance = const Distance();
  final _sb = Supabase.instance.client;
  Position? _me;
  StreamSubscription<Position>? _posSub;
  List<LatLng> _route = [];
  bool _loadingRoute = false;
  Map<String, dynamic>? _booking; // Store booking status
  double? _fetchedClientLat; // Coordinates fetched from database
  double? _fetchedClientLng;

  LatLng? get _client {
    // Use widget coordinates first, then fallback to fetched ones
    final lat = widget.clientLat ?? _fetchedClientLat;
    final lng = widget.clientLng ?? _fetchedClientLng;
    
    if (lat != null && lng != null && lat != 0 && lng != 0) {
      return LatLng(lat, lng);
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadBookingStatus();
    _ensureLocation();
  }

  Future<void> _loadBookingStatus() async {
    try {
      // Fetch booking with coordinates and status
      final booking = await _sb
          .from('bookings')
          .select('status, client_lat, client_lng, client_address, location')
          .eq('id', widget.bookingId)
          .maybeSingle();
      
      if (booking != null && mounted) {
        // Store booking data
        setState(() {
          _booking = Map<String, dynamic>.from(booking);
          
          // Fetch coordinates from database if not provided or invalid in widget
          final widgetLat = widget.clientLat;
          final widgetLng = widget.clientLng;
          final hasValidWidgetCoords = widgetLat != null && 
                                       widgetLng != null && 
                                       widgetLat != 0 && 
                                       widgetLng != 0;
          
          if (!hasValidWidgetCoords) {
            // Try to fetch from database
            final lat = (booking['client_lat'] as num?)?.toDouble();
            final lng = (booking['client_lng'] as num?)?.toDouble();
            
            if (lat != null && lng != null && lat != 0 && lng != 0) {
              _fetchedClientLat = lat;
              _fetchedClientLng = lng;
              debugPrint('✅ Fetched client coordinates from booking: $lat, $lng');
              
              // Force rebuild to show marker and build route
              if (mounted) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _client != null) {
                    setState(() {});
                    _buildRoute();
                  }
                });
              }
            } else {
              debugPrint('⚠️ No client coordinates found in booking');
              debugPrint('   Booking ID: ${widget.bookingId}');
              debugPrint('   Booking data: $booking');
            }
          } else {
            debugPrint('✅ Using widget-provided coordinates: $widgetLat, $widgetLng');
          }
        });
        
        // Build route if we have coordinates
        if (_client != null) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              _buildRoute();
            }
          });
        }
      }

      // If status is Accepted or Pending, update to InProgress when navigation starts
      final status = booking?['status']?.toString().toLowerCase();
      if (status == 'accepted' || status == 'pending') {
        try {
          await _sb
              .from('bookings')
              .update({'status': 'InProgress'})
              .eq('id', widget.bookingId);
          
          // Notify client that worker is on the way
          final bookingFull = await _sb
              .from('bookings')
              .select('client_id, service_type')
              .eq('id', widget.bookingId)
              .maybeSingle();
          
          if (bookingFull != null) {
            final clientId = bookingFull['client_id']?.toString();
            final serviceType = bookingFull['service_type']?.toString() ?? 'Service';
            
            if (clientId != null) {
              await NotificationService.createNotification(
                userId: clientId,
                type: 'booking_status_changed',
                title: 'Worker On The Way!',
                message: 'Your worker is now heading to your location for "$serviceType". You can track their location in the booking details.',
                relatedId: widget.bookingId,
                relatedType: 'booking',
              );
            }
          }
          
          // Reload status
          final updated = await _sb
              .from('bookings')
              .select('status')
              .eq('id', widget.bookingId)
              .maybeSingle();
          
          if (updated != null && mounted) {
            setState(() {
              _booking = Map<String, dynamic>.from(updated);
            });
          }
        } catch (e) {
          debugPrint('Error updating status to InProgress: $e');
        }
      }
    } catch (e) {
      debugPrint('Error loading booking status: $e');
      debugPrint('Error details: $e');
    }
  }

  @override
  void dispose() {
    _posSub?.cancel();
    super.dispose();
  }

  Future<void> _ensureLocation() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return;

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm != LocationPermission.always && perm != LocationPermission.whileInUse) return;

    // current
    final now = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    if (!mounted) return;
    setState(() => _me = now);

    // updates
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5),
    ).listen((pos) {
      setState(() => _me = pos);
      // lazily refresh route every ~150m (cheap heuristic)
      _throttleRouteRebuild();
    });

    // first route (will build if coordinates are available)
    if (_client != null) {
      _buildRoute();
    } else {
      // Try to fetch coordinates from booking if not available yet
      _loadBookingStatus().then((_) {
        if (_client != null) {
          _buildRoute();
        }
      });
    }
  }

  Timer? _recalcTimer;
  void _throttleRouteRebuild() {
    if (_loadingRoute) return;
    _recalcTimer?.cancel();
    _recalcTimer = Timer(const Duration(seconds: 4), _buildRoute);
  }

  Future<void> _buildRoute() async {
    if (_client == null || _me == null) return;
    setState(() => _loadingRoute = true);

    final start = '${_me!.longitude},${_me!.latitude}';
    final end = '${_client!.longitude},${_client!.latitude}';
    final url = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/$start;$end?overview=full&geometries=geojson',
    );

    try {
      final r = await http.get(url);
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body);
        final coords = (j['routes']?[0]?['geometry']?['coordinates'] ?? []) as List;
        final pts = coords
            .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
            .toList();
        if (mounted) setState(() => _route = pts);
      }
    } catch (_) {
      // swallow – map will still show pins
    } finally {
      if (mounted) setState(() => _loadingRoute = false);
    }
  }

  String _prettyDistanceAndEta() {
    if (_me == null || _client == null) return '—';
    final meters = _distance.as(LengthUnit.Meter,
        LatLng(_me!.latitude, _me!.longitude), _client!);
    final km = meters / 1000.0;
    // simple ETA: 28 km/h city avg → minutes
    final etaMin = (km / 28.0) * 60.0;
    final d = km < 1 ? '${meters.toStringAsFixed(0)} m' : '${km.toStringAsFixed(1)} km';
    final e = etaMin < 1 ? '<1 min' : '${etaMin.round()} min';
    return '$d • $e';
    }

  Future<void> _callClient() async {
    final phone = widget.clientPhone.trim();
    if (phone.isEmpty) return;
    final uri = Uri.parse('tel:${Uri.encodeComponent(phone)}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _messageClient() async {
    // If you already have a chat thread screen, push it here instead.
    final phone = widget.clientPhone.trim();
    if (phone.isNotEmpty) {
      final uri = Uri.parse('sms:${Uri.encodeComponent(phone)}');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    }
    // Fallback: open any messaging app chooser by using a blank sms:
    final alt = Uri.parse('sms:');
    await launchUrl(alt, mode: LaunchMode.externalApplication);
  }

  Future<void> _openExternalNav() async {
    if (_client == null) return;
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${_client!.latitude},${_client!.longitude}&travelmode=driving',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final meLL = (_me == null) ? null : LatLng(_me!.latitude, _me!.longitude);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            // MAP
            Positioned.fill(
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
                child: FlutterMap(
                  options: MapOptions(
                    // Center on client location if available, otherwise worker location
                    initialCenter: _client ?? meLL ?? const LatLng(14.5995, 120.9842),
                    initialZoom: _client != null ? 15 : 14,
                    interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
                    onMapReady: () {
                      // Ensure client location is visible when map loads
                      if (_client != null && mounted) {
                        setState(() {});
                      }
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                      subdomains: const ['a', 'b', 'c'],
                      userAgentPackageName: 'com.example.app',
                    ),
                    if (_route.isNotEmpty)
                      PolylineLayer(polylines: [
                        Polyline(points: _route, strokeWidth: 5, color: Colors.blue),
                      ]),
                    MarkerLayer(markers: [
                      // Worker location marker (blue, smaller)
                      if (meLL != null)
                        Marker(
                          point: meLL,
                          width: 50,
                          height: 50,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.blue.withOpacity(0.4),
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: const Icon(Icons.my_location, color: Colors.white, size: 28),
                          ),
                        ),
                      // Client location marker (green, prominent, pulsating)
                      if (_client != null)
                        Marker(
                          point: _client!,
                          width: 80,
                          height: 80,
                          child: _PulsatingClientMarker(),
                        ),
                    ]),
                  ],
                ),
              ),
            ),

            // TOP BAR
            Positioned(
              left: 8,
              right: 8,
              top: 8,
              child: Row(
                children: [
                  _RoundedIconButton(
                    icon: Icons.arrow_back,
                    onTap: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  _RoundedIconButton(
                    icon: Icons.navigation_outlined,
                    onTap: _openExternalNav,
                  ),
                ],
              ),
            ),

            // BOTTOM SHEET
            DraggableScrollableSheet(
              initialChildSize: 0.33,
              minChildSize: 0.22,
              maxChildSize: 0.85,
              builder: (ctx, controller) {
                final initials = (widget.clientName.isEmpty
                        ? 'C'
                        : widget.clientName[0])
                    .toUpperCase();

                return Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                    boxShadow: [BoxShadow(blurRadius: 12, color: Colors.black26)],
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: ListView(
                    controller: controller,
                    children: [
                      Center(
                        child: Container(
                          width: 36, height: 4,
                          decoration: BoxDecoration(
                            color: Colors.black12,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundColor: const Color(0xFFED9121).withOpacity(.15),
                            child: Text(initials, style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(widget.clientName.isEmpty ? 'Client' : widget.clientName,
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text(_prettyDistanceAndEta(), style: const TextStyle(color: Colors.grey)),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.chat_bubble_outline),
                            onPressed: _messageClient,
                          ),
                          IconButton(
                            icon: const Icon(Icons.call),
                            onPressed: _callClient,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _InfoRow(icon: Icons.place_outlined, label: 'Address', value: widget.clientAddress),
                      _InfoRow(icon: Icons.build_outlined, label: 'What to fix / do',
                          value: (widget.problemDetails.isEmpty ? '—' : widget.problemDetails)),
                      _InfoRow(
                        icon: Icons.payments_outlined,
                        label: 'Estimated Price',
                        value: widget.price == null ? '—' : '₱${widget.price!.toStringAsFixed(0)}',
                      ),
                      if (_loadingRoute)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFED9121),
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: _openExternalNav,
                        icon: const Icon(Icons.directions),
                        label: const Text('Open in Maps'),
                      ),
                      
                      // Finish Job button (only show if status is Accepted or InProgress)
                      if (_booking != null &&
                          (_booking!['status']?.toString().toLowerCase() == 'accepted' ||
                           _booking!['status']?.toString().toLowerCase() == 'inprogress'))
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(48),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            icon: const Icon(Icons.check_circle),
                            label: const Text('Finish Job'),
                            onPressed: () => _finishJob(),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _finishJob() async {
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
      await _sb
          .from('bookings')
          .update({'status': 'Completed'})
          .eq('id', widget.bookingId);

      // Fetch booking to get client ID
      final booking = await _sb
          .from('bookings')
          .select('client_id, service_type')
          .eq('id', widget.bookingId)
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
            relatedId: widget.bookingId,
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

      // Navigate back to dashboard
      await Future.delayed(const Duration(seconds: 1));
      
      if (mounted) {
        // Pop all screens until dashboard
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

// Pulsating client location marker (green, like reference)
class _PulsatingClientMarker extends StatefulWidget {
  @override
  State<_PulsatingClientMarker> createState() => _PulsatingClientMarkerState();
}

class _PulsatingClientMarkerState extends State<_PulsatingClientMarker>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
    
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.5).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // Outer pulsating circle (green)
            Transform.scale(
              scale: _pulseAnimation.value,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            // Middle circle (green)
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.4),
                shape: BoxShape.circle,
              ),
            ),
            // Inner circle with icon (solid green)
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.green.withOpacity(0.5),
                    blurRadius: 12,
                    spreadRadius: 3,
                  ),
                ],
              ),
              child: const Icon(
                Icons.location_pin,
                color: Colors.white,
                size: 24,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RoundedIconButton extends StatelessWidget {
  const _RoundedIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black26)],
        ),
        child: Icon(icon, color: Colors.black87),
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
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(icon, color: const Color(0xFFED9121)),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(value.isEmpty ? '—' : value),
    );
  }
}