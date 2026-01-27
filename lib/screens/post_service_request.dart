import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;

import '../request_applicants_page.dart';
import 'match_map_page.dart';

class PostServiceRequestPage extends StatefulWidget {
  const PostServiceRequestPage({super.key});

  @override
  State<PostServiceRequestPage> createState() => _PostServiceRequestPageState();
}

class _PostServiceRequestPageState extends State<PostServiceRequestPage> {
  final _formKey = GlobalKey<FormState>();
  final _description = TextEditingController();
  final _budgetMin = TextEditingController();
  final _budgetMax = TextEditingController();
  final _location = TextEditingController();

  String? _selectedService;
  List<String> _serviceList = [];

  double? _latitude;
  double? _longitude;
  DateTime? _preferredDate;
  bool _submitting = false;

  final supa = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _fetchServices();
  }

  // ----------------------------------------------------------
  // 🗂️ Fetch services from Supabase
  // ----------------------------------------------------------
  Future<void> _fetchServices() async {
    try {
      final data = await supa.from('services').select('name');
      setState(() {
        _serviceList = (data as List).map((e) => e['name'].toString()).toList();
      });
    } catch (e) {
      debugPrint("Error fetching services: $e");
      // fallback list
      setState(() {
        _serviceList = const [
          'Plumber',
          'Electrician',
          'Aircon Technician',
          'Cleaner',
          'Appliance Repair',
          'Carpenter',
        ];
      });
    }
  }

  // ----------------------------------------------------------
  // 📍 Get current GPS location
  // ----------------------------------------------------------
  Future<void> _getLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enable location services.')),
        );
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission denied.')),
        );
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _latitude = pos.latitude;
        _longitude = pos.longitude;
      });

      await _reverseGeocodeAddress(pos.latitude, pos.longitude);
    } catch (e) {
      debugPrint("Error fetching location: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error getting location: $e')),
      );
    }
  }

  // ----------------------------------------------------------
  // 🌐 Reverse geocode lat/lng to readable address
  // ----------------------------------------------------------
  Future<void> _reverseGeocodeAddress(double lat, double lng) async {
    try {
      final url =
          'https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lng&zoom=18&addressdetails=1';
      final response = await http.get(
        Uri.parse(url),
        headers: {
          // Nominatim requires a proper User-Agent
          'User-Agent': 'SerbisyoKoApp/1.0 (contact@serbisyoko.com)',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final display = data['display_name'] ??
            "${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}";

        setState(() {
          _location.text = display;
        });
      } else {
        setState(() {
          _location.text =
              "Lat: ${lat.toStringAsFixed(5)}, Lng: ${lng.toStringAsFixed(5)}";
        });
      }
    } catch (e) {
      debugPrint("Reverse geocoding error: $e");
      setState(() {
        _location.text =
            "Lat: ${lat.toStringAsFixed(5)}, Lng: ${lng.toStringAsFixed(5)}";
      });
    }
  }

  // ----------------------------------------------------------
  // 🗺️ Open map picker
  // ----------------------------------------------------------
  Future<void> _openMapPicker() async {
    // if we don't have a starting point yet, try to get GPS first
    if (_latitude == null || _longitude == null) {
      await _getLocation();
      if (_latitude == null || _longitude == null) return;
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MatchMapPage(
          clientPos: LatLng(_latitude!, _longitude!),
          isPicker: true,
        ),
      ),
    );

    if (result != null && result is Map<String, dynamic>) {
      setState(() {
        _latitude = result['lat'] as double?;
        _longitude = result['lng'] as double?;
        _location.text = result['address']?.toString() ?? "Custom location";
      });
    }
  }

  // ----------------------------------------------------------
  // 🚀 Submit request (for workers to browse & apply)
  // ----------------------------------------------------------
  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate()) return;

    final me = supa.auth.currentUser;
    if (me == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to post a request.')),
      );
      return;
    }

    // 🔴 IMPORTANT: make sure we have coordinates
    if (_latitude == null || _longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please set your location first.')),
      );
      return;
    }

    setState(() => _submitting = true);

    final desc = _description.text.trim();
    final serviceType = _selectedService ?? "General Service";

    // budgets (allow empty, but normalize)
    double min = double.tryParse(_budgetMin.text.trim()) ?? 0;
    double max = double.tryParse(_budgetMax.text.trim()) ?? 0;

    // If user swapped them, fix silently
    if (max > 0 && min > max) {
      final tmp = min;
      min = max;
      max = tmp;
    }

    final loc = _location.text.trim();
    final lat = _latitude!;
    final lng = _longitude!;
    final date = _preferredDate ?? DateTime.now();

    // preferred time window: simple 2-hour block for now
    final preferredStart = DateTime(date.year, date.month, date.day, 14, 0);
    final preferredEnd = preferredStart.add(const Duration(hours: 2));

    try {
      // Save service request for workers to browse and apply
      final response = await supa.from('service_requests').insert({
        'user_id': me.id,
        'service_type': serviceType,
        'description': desc,
        'budget_min': min,
        'budget_max': max,
        'location': loc,
        'latitude': lat,
        'longitude': lng,
        'preferred_date': date.toIso8601String(),
        'status': 'open',
      }).select('id').single();

      final requestId = response['id'].toString();

      if (!mounted) return;

      // Show success and navigate to view applicants page
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Service request posted! Workers can now browse and apply.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );

      // Navigate to view applicants page (or back to dashboard)
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => RequestApplicantsPage(
            requestId: requestId,
            serviceType: serviceType,
          ),
        ),
      );
    } catch (e) {
      debugPrint("Error posting request: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error posting request: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ----------------------------------------------------------
  // 🧱 UI
  // ----------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFED9121);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Post Service Request"),
        backgroundColor: accent,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Service Details",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),

              // Service Type Dropdown
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: "Service Type *",
                  border: UnderlineInputBorder(),
                ),
                value: _selectedService,
                items: _serviceList
                    .map(
                      (service) => DropdownMenuItem<String>(
                        value: service,
                        child: Text(service),
                      ),
                    )
                    .toList(),
                onChanged: (val) => setState(() => _selectedService = val),
                validator: (v) => v == null || v.isEmpty
                    ? 'Please select a service type'
                    : null,
              ),

              TextFormField(
                controller: _description,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: "Description (optional)",
                ),
              ),

              const SizedBox(height: 16),
              const Text(
                "Location",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),

              TextFormField(
                controller: _location,
                readOnly: true,
                decoration: InputDecoration(
                  labelText: "Your location",
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.my_location),
                        onPressed: _getLocation,
                        tooltip: "Use current location",
                      ),
                      IconButton(
                        icon: const Icon(Icons.map),
                        onPressed: _openMapPicker,
                        tooltip: "Open map picker",
                      ),
                    ],
                  ),
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Location is required' : null,
              ),

              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _budgetMin,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: "Budget Min (₱)"),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _budgetMax,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: "Budget Max (₱)"),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text("Preferred Date"),
                subtitle: Text(
                  _preferredDate == null
                      ? "Select a date"
                      : _preferredDate!.toLocal().toString().split(' ')[0],
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.calendar_today, color: accent),
                  onPressed: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: now,
                      firstDate: now,
                      lastDate: DateTime(now.year + 1),
                    );
                    if (picked != null) {
                      setState(() => _preferredDate = picked);
                    }
                  },
                ),
              ),

              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.send),
                  label: Text(_submitting ? "Posting..." : "Post Request"),
                  onPressed: _submitting ? null : _submitRequest,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
