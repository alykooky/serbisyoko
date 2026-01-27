import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../services/matching_service.dart';
import 'match_map_page.dart';

class EnhancedBookingFormScreen extends StatefulWidget {
  const EnhancedBookingFormScreen({super.key});

  @override
  State<EnhancedBookingFormScreen> createState() =>
      _EnhancedBookingFormScreenState();
}

class _EnhancedBookingFormScreenState extends State<EnhancedBookingFormScreen> {
  final _formKey = GlobalKey<FormState>();

  // Defaults: downtown Davao
  final _serviceCtrl =
      TextEditingController(text: 'Plumber'); // 'any' also works
  final _latCtrl = TextEditingController(text: '7.0667');
  final _lngCtrl = TextEditingController(text: '125.6000');
  final _minCtrl = TextEditingController(text: '400');
  final _maxCtrl = TextEditingController(text: '600');
  final _limitCtrl = TextEditingController(text: '10');

  bool _loading = false;
  String? _error;

  Future<void> _useMyLocation() async {
    try {
      bool enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        await Geolocator.openLocationSettings();
        return;
      }
      LocationPermission p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) {
        p = await Geolocator.requestPermission();
        if (p == LocationPermission.denied) return;
      }
      if (p == LocationPermission.deniedForever) return;

      final pos = await Geolocator.getCurrentPosition();
      setState(() {
        _latCtrl.text = pos.latitude.toStringAsFixed(6);
        _lngCtrl.text = pos.longitude.toStringAsFixed(6);
      });
    } catch (e) {
      setState(() => _error = 'Failed to get location: $e');
    }
  }

  Future<void> _findMatches() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final matches = await MatchingService.findBestMatches(
        clientLatitude: double.parse(_latCtrl.text),
        clientLongitude: double.parse(_lngCtrl.text),
        serviceType: _serviceCtrl.text.trim(),
        budgetMin: double.parse(_minCtrl.text),
        budgetMax: double.parse(_maxCtrl.text),
        limit: int.parse(_limitCtrl.text),
      );

      if (!mounted) return;
      if (matches.isEmpty) {
        setState(() => _error = 'No providers matched your criteria.');
        _loading = false;
        return;
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MatchMapPage(
            clientPos: LatLng(
              double.parse(_latCtrl.text),
              double.parse(_lngCtrl.text),
            ),
            matches: matches,
            serviceType: _serviceCtrl.text.trim(),
            budgetMin: double.parse(_minCtrl.text),
            budgetMax: double.parse(_maxCtrl.text),
          ),
        ),
      );
      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Error running smart matching: $e';
      });
    }
  }

  @override
  void dispose() {
    _serviceCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _minCtrl.dispose();
    _maxCtrl.dispose();
    _limitCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = const Color(0xFFED9121);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Find a Service Provider'),
        backgroundColor: accent,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _field('Service (e.g. Plumber, Electrician, any)', _serviceCtrl),
              Row(
                children: [
                  Expanded(child: _field('Latitude', _latCtrl, number: true)),
                  const SizedBox(width: 12),
                  Expanded(child: _field('Longitude', _lngCtrl, number: true)),
                  IconButton(
                    onPressed: _useMyLocation,
                    tooltip: 'Use my location',
                    icon: const Icon(Icons.my_location),
                  )
                ],
              ),
              Row(
                children: [
                  Expanded(
                      child: _field('Budget Min (₱)', _minCtrl, number: true)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _field('Budget Max (₱)', _maxCtrl, number: true)),
                ],
              ),
              _field('Max Results', _limitCtrl, number: true),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _loading ? null : _findMatches,
                  icon: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search),
                  label: Text(_loading ? 'Finding…' : 'Find Best Matches'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ]
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController c, {bool number = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
    );
  }
}
