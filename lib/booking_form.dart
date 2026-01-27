import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'smart_matching_results.dart';
import 'services/advanced_matching_service.dart';

class BookingFormPage extends StatefulWidget {
  final String? initialService;
  final String? workerId;
  final String? workerName;
  final int? suggestedFee;

  const BookingFormPage({
    super.key,
    this.initialService,
    this.workerId,
    this.workerName,
    this.suggestedFee,
  });

  @override
  State<BookingFormPage> createState() => _BookingFormPageState();
}

class _BookingFormPageState extends State<BookingFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _serviceTypeController = TextEditingController();
  final _locationController = TextEditingController();
  final _notesController = TextEditingController();

  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  double? _latitude;
  double? _longitude;
  String _address = "Fetching current location...";
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Location services are disabled.")),
        );
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Location permission denied.")),
        );
        return;
      }

      final pos = await Geolocator.getCurrentPosition();
      final placemarks = await placemarkFromCoordinates(
        pos.latitude,
        pos.longitude,
      );
      final place = placemarks.first;

      setState(() {
        _latitude = pos.latitude;
        _longitude = pos.longitude;
        _address =
            "${place.street ?? ''}, ${place.locality ?? ''}, ${place.administrativeArea ?? ''}";
        _locationController.text = _address;
      });
    } catch (e) {
      debugPrint("Location error: $e");
    }
  }

  Future<void> _submitBooking() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDate == null || _selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select date and time.")),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw "User not logged in";

      final scheduledDateTime = DateTime(
        _selectedDate!.year,
        _selectedDate!.month,
        _selectedDate!.day,
        _selectedTime!.hour,
        _selectedTime!.minute,
      );

      // save booking
      final booking = await Supabase.instance.client
          .from('bookings')
          .insert({
            'client_id': user.id,
            'service_type': _serviceTypeController.text.trim(),
            'location': _address,
            'latitude': _latitude,
            'longitude': _longitude,
            'scheduled_time': scheduledDateTime.toIso8601String(),
            'notes': _notesController.text.trim(),
            'status': 'pending',
          })
          .select()
          .single();

      // find best matches
      final matches = await AdvancedMatchingService.findBestMatches(
        serviceType: _serviceTypeController.text.trim(),
        clientLatitude: _latitude ?? 7.0667,
        clientLongitude: _longitude ?? 125.6000,
        preferredStartTime: scheduledDateTime,
        preferredEndTime: scheduledDateTime.add(const Duration(hours: 2)),
        budgetMin: 300,
        budgetMax: 800,
      );

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => SmartMatchingResultsScreen(
            serviceType: _serviceTypeController.text.trim(),
            clientLat: _latitude ?? 0,
            clientLng: _longitude ?? 0,
            location: _address,
            budgetMin: 300,
            budgetMax: 800,
            preferredStartTime: scheduledDateTime,
            preferredEndTime: scheduledDateTime.add(const Duration(hours: 2)),
            results: matches,
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFED9121);
    return Scaffold(
      appBar: AppBar(
        title: const Text("Book a Service"),
        backgroundColor: accent,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: accent))
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: ListView(
                  children: [
                    TextFormField(
                      controller: _serviceTypeController,
                      decoration:
                          const InputDecoration(labelText: "Service Type *"),
                      validator: (v) =>
                          v == null || v.isEmpty ? "Required field" : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _locationController,
                      decoration: InputDecoration(
                        labelText: "Location *",
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.my_location),
                          onPressed: _getCurrentLocation,
                        ),
                      ),
                      validator: (v) =>
                          v == null || v.isEmpty ? "Required field" : null,
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text("Select Date"),
                      subtitle: Text(_selectedDate == null
                          ? "Tap to choose"
                          : _selectedDate!.toLocal().toString().split(' ')[0]),
                      onTap: () async {
                        final now = DateTime.now();
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: now,
                          firstDate: now,
                          lastDate: DateTime(now.year + 1),
                        );
                        if (picked != null) {
                          setState(() => _selectedDate = picked);
                        }
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text("Select Time"),
                      subtitle: Text(_selectedTime == null
                          ? "Tap to choose"
                          : _selectedTime!.format(context)),
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.now(),
                        );
                        if (picked != null) {
                          setState(() => _selectedTime = picked);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _notesController,
                      maxLines: 3,
                      decoration:
                          const InputDecoration(labelText: "Notes (optional)"),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text("Confirm & Find Provider"),
                      onPressed: _loading ? null : _submitBooking,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    )
                  ],
                ),
              ),
            ),
    );
  }
}
