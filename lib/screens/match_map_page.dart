import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;

class MatchMapPage extends StatefulWidget {
  final LatLng? clientPos;
  final bool isPicker;
  final List<Map<String, dynamic>>? matches;
  final String? serviceType;
  final double? budgetMin;
  final double? budgetMax;

  const MatchMapPage({
    super.key,
    this.clientPos,
    this.isPicker = false,
    this.matches,
    this.serviceType,
    this.budgetMin,
    this.budgetMax,
  });

  @override
  State<MatchMapPage> createState() => _MatchMapPageState();
}

class _MatchMapPageState extends State<MatchMapPage> {
  late MapController _mapController;
  LatLng? _currentPos;
  String? _currentAddress;
  bool _loading = true;
  bool _fetchingAddress = false;

  // Location search
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  FocusNode _searchFocusNode = FocusNode();
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _searchController.addListener(_onSearchChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initLocation();
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();

    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      _searchLocation(query);
    });
  }

  Future<void> _initLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _loading = false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        setState(() => _loading = false);
        return;
      }

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

      LatLng position = widget.clientPos ?? LatLng(pos.latitude, pos.longitude);

      setState(() {
        _currentPos = position;
      });

      _updateAddress(position);

      setState(() {
        _loading = false;
      });

      await Future.delayed(const Duration(milliseconds: 100));
      if (mounted) {
        _mapController.move(position, 17);
      }
    } catch (e) {
      debugPrint("Error getting location: $e");
      setState(() => _loading = false);
    }
  }

  Future<void> _updateAddress(LatLng pos) async {
    if (!mounted) return;

    setState(() => _fetchingAddress = true);

    try {
      final url =
          'https://nominatim.openstreetmap.org/reverse?format=json&lat=${pos.latitude}&lon=${pos.longitude}&zoom=18&addressdetails=1';

      final response = await http.get(Uri.parse(url), headers: {
        'User-Agent': 'SerbisyoKoApp/1.0',
      });

      if (response.statusCode == 200 && mounted) {
        final data = json.decode(response.body);
        String displayName = data['display_name'] ?? '';

        if (displayName.isEmpty ||
            displayName.toLowerCase().contains('unknown')) {
          displayName =
              "${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}";
        }

        if (mounted) {
          setState(() {
            _currentAddress = displayName;
            _fetchingAddress = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _currentAddress =
                "${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}";
            _fetchingAddress = false;
          });
        }
      }
    } catch (e) {
      debugPrint("Reverse geocode error: $e");
      if (mounted) {
        setState(() {
          _currentAddress =
              "${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}";
          _fetchingAddress = false;
        });
      }
    }
  }

  Future<void> _searchLocation(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }

    try {
      final url =
          'https://nominatim.openstreetmap.org/search?format=json&q=${Uri.encodeComponent(query)}&limit=5&addressdetails=1';

      final response = await http.get(Uri.parse(url), headers: {
        'User-Agent': 'SerbisyoKoApp/1.0',
      });

      if (response.statusCode == 200 && mounted) {
        final data = json.decode(response.body) as List;
        setState(() {
          _searchResults =
              data.map((item) => Map<String, dynamic>.from(item)).toList();
        });
      }
    } catch (e) {
      debugPrint("Location search error: $e");
    }
  }

  Future<void> _selectSearchResult(Map<String, dynamic> result) async {
    final lat = double.tryParse(result['lat'].toString());
    final lon = double.tryParse(result['lon'].toString());

    if (lat == null || lon == null) return;

    final location = LatLng(lat, lon);

    _searchController.clear();
    _searchFocusNode.unfocus();
    setState(() {
      _searchResults = [];
      _currentPos = location;
    });

    if (mounted) {
      _mapController.move(location, 17);
    }

    await _updateAddress(location);
  }

  void _centerToCurrentLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      final newLoc = LatLng(pos.latitude, pos.longitude);

      if (mounted) {
        _mapController.move(newLoc, 17);
      }

      await _updateAddress(newLoc);
      setState(() => _currentPos = newLoc);
    } catch (e) {
      debugPrint("Error centering map: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    // ✅ Key comes from build: flutter build web --dart-define=MAPTILER_KEY=xxxx
    const mapTilerKey = String.fromEnvironment('MAPTILER_KEY');

    final bool hasMapTilerKey = mapTilerKey.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFED9121),
        title: const Text(
          "Add Location",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFED9121)),
            )
          : Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _currentPos ?? LatLng(7.0731, 125.6128),
                    initialZoom: 17,
                    onTap: (tapPos, point) async {
                      setState(() => _currentPos = point);
                      await _updateAddress(point);
                    },
                  ),
                  children: [
                    // ✅ If key exists, use MapTiler. If not, fallback to OSM (no key needed).
                    TileLayer(
                      urlTemplate: hasMapTilerKey
                          ? "https://api.maptiler.com/maps/streets/{z}/{x}/{y}.png?key=$mapTilerKey"
                          : "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                      userAgentPackageName: 'com.example.serbisyoko',
                    ),

                    // ✅ REQUIRED attribution
                    RichAttributionWidget(
                      attributions: [
                        const TextSourceAttribution(
                            '© OpenStreetMap contributors'),
                        if (hasMapTilerKey)
                          const TextSourceAttribution('© MapTiler'),
                      ],
                    ),

                    if (_currentPos != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            width: 40,
                            height: 40,
                            point: _currentPos!,
                            child: const Icon(Icons.location_pin,
                                color: Colors.red, size: 40),
                          ),
                        ],
                      ),
                  ],
                ),

                // Search bar at the top
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      children: [
                        TextField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          decoration: InputDecoration(
                            hintText: 'Search for a location...',
                            prefixIcon: const Icon(Icons.search,
                                color: Color(0xFFED9121)),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      _searchController.clear();
                                      _searchFocusNode.unfocus();
                                    },
                                  )
                                : null,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  const BorderSide(color: Color(0xFFED9121)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                  color: Color(0xFFED9121), width: 2),
                            ),
                            filled: true,
                            fillColor: Colors.grey[100],
                          ),
                        ),
                        if (_searchResults.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            constraints: const BoxConstraints(maxHeight: 200),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 4,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: _searchResults.length,
                              itemBuilder: (context, index) {
                                final result = _searchResults[index];
                                final displayName =
                                    result['display_name']?.toString() ??
                                        '${result['lat']}, ${result['lon']}';
                                return ListTile(
                                  leading: const Icon(Icons.location_on,
                                      color: Color(0xFFED9121)),
                                  title: Text(
                                    displayName,
                                    style: const TextStyle(fontSize: 14),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onTap: () => _selectSearchResult(result),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                // Floating "center to location" button
                Positioned(
                  bottom: 160,
                  right: 20,
                  child: FloatingActionButton(
                    backgroundColor: Colors.white,
                    mini: true,
                    onPressed: _centerToCurrentLocation,
                    child: const Icon(Icons.my_location,
                        color: Colors.orange, size: 24),
                  ),
                ),

                // Address + Confirm button panel
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(20)),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black26,
                            blurRadius: 6,
                            offset: Offset(0, -2))
                      ],
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Add Location",
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.location_on,
                                color: Color(0xFFED9121)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _fetchingAddress
                                  ? const Row(
                                      children: [
                                        SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Color(0xFFED9121),
                                          ),
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          "Fetching address...",
                                          style: TextStyle(
                                              fontSize: 14,
                                              fontStyle: FontStyle.italic),
                                        ),
                                      ],
                                    )
                                  : Text(
                                      _currentAddress ??
                                          "Tap on map to select location",
                                      style: const TextStyle(fontSize: 14),
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFED9121),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () {
                              if (_currentPos == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Please select a location on the map first.'),
                                    backgroundColor: Colors.orange,
                                  ),
                                );
                                return;
                              }

                              Navigator.pop(context, {
                                'lat': _currentPos!.latitude,
                                'lng': _currentPos!.longitude,
                                'address': _currentAddress ??
                                    "Lat: ${_currentPos!.latitude.toStringAsFixed(6)}, Lng: ${_currentPos!.longitude.toStringAsFixed(6)}",
                              });
                            },
                            child: const Text(
                              "Confirm Location",
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
