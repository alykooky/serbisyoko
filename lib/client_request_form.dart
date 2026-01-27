import 'package:flutter/material.dart';
import 'smart_matching_results.dart';
import 'screens/match_map_page.dart';
import 'package:latlong2/latlong.dart';

class ClientServiceRequestForm extends StatefulWidget {
  final String serviceType;
  final double clientLat;
  final double clientLng;
  final String location;

  const ClientServiceRequestForm({
    super.key,
    required this.serviceType,
    required this.clientLat,
    required this.clientLng,
    required this.location,
  });

  @override
  State<ClientServiceRequestForm> createState() =>
      _ClientServiceRequestFormState();
}

class _ClientServiceRequestFormState extends State<ClientServiceRequestForm> {
  final _formKey = GlobalKey<FormState>();

  int minBudget = 100;
  int maxBudget = 500;
  String description = "";
  DateTime? selectedDate;
  TimeOfDay? selectedTime;

  // Location state (can be updated)
  late double _clientLat;
  late double _clientLng;
  late String _location;

  Future<void> pickDate() async {
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      initialDate: DateTime.now(),
    );
    if (d != null) setState(() => selectedDate = d);
  }

  Future<void> pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (t != null) setState(() => selectedTime = t);
  }

  @override
  void initState() {
    super.initState();
    // Initialize with provided location or defaults
    _clientLat = widget.clientLat;
    _clientLng = widget.clientLng;
    _location = widget.location;

    // If location is invalid (0 or missing), prompt to set it
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_clientLat == 0 ||
          _clientLng == 0 ||
          _location.isEmpty ||
          _location == 'Unknown Location') {
        _showLocationRequiredDialog();
      }
    });
  }

  Future<void> _showLocationRequiredDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Location Required'),
        content: const Text(
          'Please set your service location to continue. You can select it on the map.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFED9121),
            ),
            child: const Text('Set Location'),
          ),
        ],
      ),
    );

    if (result == true) {
      await _pickLocation();
    }
  }

  Future<void> _pickLocation() async {
    // Use current location or default to Davao if invalid
    final defaultLat = _clientLat != 0 ? _clientLat : 7.0731;
    final defaultLng = _clientLng != 0 ? _clientLng : 125.6128;

    // Open map picker to select location
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MatchMapPage(
          clientPos: LatLng(defaultLat, defaultLng),
          isPicker: true,
        ),
      ),
    );

    if (result != null && result is Map<String, dynamic>) {
      final lat = result['lat'] as double?;
      final lng = result['lng'] as double?;
      final address = result['address']?.toString();

      if (lat != null && lng != null && lat != 0 && lng != 0) {
        setState(() {
          _clientLat = lat;
          _clientLng = lng;
          _location = address ?? widget.location;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location set successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a valid location on the map.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFED9121);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.serviceType),
        backgroundColor: accent,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              // Description
              const Text("Describe your request",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              TextFormField(
                maxLines: 3,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: "What do you need?",
                ),
                onChanged: (v) => description = v,
              ),

              const SizedBox(height: 20),

              // Location Section
              const Text("Service Location",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Card(
                child: ListTile(
                  leading:
                      const Icon(Icons.location_on, color: Color(0xFFED9121)),
                  title: const Text("Location"),
                  subtitle: Text(
                    _location.isEmpty || _location == 'Unknown Location'
                        ? "Tap to set location"
                        : _location,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _pickLocation,
                ),
              ),

              const SizedBox(height: 20),

              // Budget Range
              const Text("Budget Range (₱)",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: "100",
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: "Min"),
                      onChanged: (v) =>
                          minBudget = int.tryParse(v) ?? minBudget,
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: TextFormField(
                      initialValue: "500",
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: "Max"),
                      onChanged: (v) =>
                          maxBudget = int.tryParse(v) ?? maxBudget,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Schedule picker
              const Text("Preferred Schedule",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ElevatedButton(
                    onPressed: pickDate,
                    child: const Text("Select Date"),
                  ),
                  Text(selectedDate == null
                      ? "No date"
                      : "${selectedDate!.month}/${selectedDate!.day}/${selectedDate!.year}"),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ElevatedButton(
                    onPressed: pickTime,
                    child: const Text("Select Time"),
                  ),
                  Text(selectedTime == null
                      ? "No time"
                      : selectedTime!.format(context)),
                ],
              ),

              const SizedBox(height: 30),

              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () async {
                  if (selectedDate == null || selectedTime == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Please select both date and time."),
                      ),
                    );
                    return;
                  }

                  // Validate location
                  if (_location.isEmpty ||
                      _location == 'Unknown Location' ||
                      _location == 'Tap to set location' ||
                      _clientLat == 0 ||
                      _clientLng == 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Please select a service location."),
                        backgroundColor: Colors.orange,
                      ),
                    );
                    // Auto-open location picker if not set
                    await _pickLocation();
                    return;
                  }

                  final scheduledDateTime = DateTime(
                    selectedDate!.year,
                    selectedDate!.month,
                    selectedDate!.day,
                    selectedTime!.hour,
                    selectedTime!.minute,
                  );

                  // Validate location one more time before proceeding
                  if (_clientLat == 0 || _clientLng == 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            "Please select a valid service location on the map."),
                        backgroundColor: Colors.red,
                      ),
                    );
                    await _pickLocation();
                    return;
                  }

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SmartMatchingResultsScreen(
                        serviceType: widget.serviceType,
                        clientLat: _clientLat, // Use updated location
                        clientLng: _clientLng, // Use updated location
                        location: _location, // Use updated address
                        description: description, // Pass description
                        budgetMin: minBudget.toDouble(),
                        budgetMax: maxBudget.toDouble(),
                        preferredStartTime: scheduledDateTime,
                        preferredEndTime:
                            scheduledDateTime.add(const Duration(hours: 2)),
                        results: [],
                      ),
                    ),
                  );
                },
                child: const Text("Find Available Workers"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
