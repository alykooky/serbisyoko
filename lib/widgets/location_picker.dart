import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:ui' as ui;
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async';

// Ensure we have StreamSubscription and Completer

class LocationPicker extends StatefulWidget {
  final String currentLocation;
  final double? currentLat;
  final double? currentLng;
  final Function(String location, double lat, double lng) onLocationSelected;

  const LocationPicker({
    super.key,
    required this.currentLocation,
    this.currentLat,
    this.currentLng,
    required this.onLocationSelected,
  });

  @override
  State<LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends State<LocationPicker> {
  late MapController _mapController;
  late LatLng _selectedLocation;
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _fetchingAddress = false;
  String _currentAddress = '';
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _selectedLocation = LatLng(
      widget.currentLat ?? 7.0731,
      widget.currentLng ?? 125.6128,
    );
    _currentAddress = widget.currentLocation;
    _searchController.text = widget.currentLocation;
    
    // If we have coordinates, update address immediately
    if (widget.currentLat != null && widget.currentLng != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateAddress(_selectedLocation);
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location services are disabled.')),
        );
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }

      if (permission == LocationPermission.deniedForever) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission is permanently denied.')),
        );
        return;
      }

      // Show loading indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Getting your exact location... Please wait.'),
            duration: Duration(seconds: 2),
          ),
        );
      }

      // Use location stream to wait for better GPS accuracy
      // This is better than getCurrentPosition for poor accuracy situations
      Position? bestPosition;
      bool foundGoodAccuracy = false;
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Getting precise GPS location... This may take 10-20 seconds.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      
      // Listen to location stream to get progressively better accuracy
      final locationStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 0, // Get all updates
          timeLimit: Duration(seconds: 30), // Maximum wait time
        ),
      );
      
      StreamSubscription<Position>? streamSub;
      final completer = Completer<Position?>();
      int updateCount = 0;
      const maxUpdates = 40; // Listen to more GPS updates for better accuracy
      
      streamSub = locationStream.listen((position) {
        updateCount++;
        debugPrint('📍 GPS Update $updateCount: ${position.latitude}, ${position.longitude} (accuracy: ${position.accuracy}m)');
        
        // PINPOINT ACCURACY: Strictly reject cached/network locations
        // With 2362m accuracy, this is definitely a cached location - reject it completely!
        // Only accept positions with accuracy < 100m
        if (position.accuracy > 100) {
          debugPrint('   ❌❌ REJECTING cached/network location (accuracy: ${position.accuracy}m - WAY TOO POOR!)');
          debugPrint('   ⏳ Waiting for actual GPS fix with accuracy < 100m...');
          // Continue listening for better GPS fixes - don't use this position at all
          return;
        }
        
        // Reject positions older than 30 seconds (likely cached)
        final now = DateTime.now();
        final ageInSeconds = now.difference(position.timestamp).inSeconds;
        if (ageInSeconds > 30) {
          debugPrint('   ❌ REJECTING old cached location (${ageInSeconds}s old)');
          return;
        }
        
        // Accept position if accuracy is excellent (< 20m for pinpoint accuracy)
        if (position.accuracy < 20) {
          debugPrint('   ✅✅ EXCELLENT accuracy found! (${position.accuracy.toStringAsFixed(1)}m)');
          bestPosition = position;
          foundGoodAccuracy = true;
          streamSub?.cancel();
          if (!completer.isCompleted) {
            completer.complete(position);
          }
          return;
        }
        
        // Accept position if accuracy is good enough (< 50m)
        if (position.accuracy < 50) {
          debugPrint('   ✅ Good accuracy found! (${position.accuracy.toStringAsFixed(1)}m)');
          // Track best position, but keep listening for even better accuracy
          if (bestPosition == null || position.accuracy < bestPosition!.accuracy) {
            bestPosition = position;
          }
        }
        
        // Track best position so far
        if (bestPosition == null || position.accuracy < bestPosition!.accuracy) {
          bestPosition = position;
        }
        
        // Stop after max updates
        if (updateCount >= maxUpdates) {
          streamSub?.cancel();
          if (!completer.isCompleted) {
            completer.complete(bestPosition);
          }
        }
      }, onError: (error) {
        debugPrint('❌ Location stream error: $error');
        streamSub?.cancel();
        if (!completer.isCompleted) {
          completer.complete(bestPosition);
        }
      });
      
      // Wait for stream with longer timeout for pinpoint accuracy
      bestPosition = await completer.future.timeout(
        const Duration(seconds: 60), // Longer timeout for GPS to acquire satellites
        onTimeout: () {
          debugPrint('⏱️ Location stream timeout (60s) - using best position so far');
          streamSub?.cancel();
          return bestPosition;
        },
      );
      
      // CRITICAL: Don't accept positions with poor accuracy - they're cached/network locations
      // For pinpoint accuracy, reject any position with accuracy > 50m
      if (bestPosition != null && bestPosition!.accuracy > 50) {
        debugPrint('❌❌ REJECTED: Position accuracy ${bestPosition!.accuracy}m is too poor (likely cached location)');
        debugPrint('   Need accuracy < 50m for pinpoint precision. Waiting for actual GPS fix...');
        
        // Clear the poor position and wait longer for real GPS
        bestPosition = null;
        foundGoodAccuracy = false;
        
        // Wait longer for GPS to get a proper fix - give it more time
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Getting pinpoint accurate GPS location... This may take 15-30 seconds. Please stay in an open area.'),
              duration: Duration(seconds: 4),
            ),
          );
        }
        
        // Wait longer for GPS satellites to acquire
        await Future.delayed(const Duration(seconds: 15));
        
        // Try multiple times to get accurate GPS
        for (int attempt = 1; attempt <= 3; attempt++) {
          debugPrint('   🔄 GPS Attempt $attempt/3 - waiting for accurate fix...');
          await Future.delayed(const Duration(seconds: 5));
          
          try {
            final freshPosition = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.bestForNavigation,
              timeLimit: const Duration(seconds: 30),
            );
            
            debugPrint('   📍 Attempt $attempt: ${freshPosition.latitude}, ${freshPosition.longitude} (accuracy: ${freshPosition.accuracy}m)');
            
            if (freshPosition.accuracy < 50) {
              bestPosition = freshPosition;
              foundGoodAccuracy = true;
              debugPrint('   ✅✅ Got accurate GPS! (${freshPosition.accuracy.toStringAsFixed(1)}m)');
              break;
            } else if (bestPosition == null || freshPosition.accuracy < bestPosition!.accuracy) {
              bestPosition = freshPosition;
            }
          } catch (e) {
            debugPrint('   ⚠️ Attempt $attempt failed: $e');
          }
        }
      }
      
      // Final check - if we still don't have good accuracy, reject it
      if (!foundGoodAccuracy || bestPosition == null || (bestPosition != null && bestPosition!.accuracy > 50)) {
        debugPrint('⚠️ Best accuracy from stream: ${bestPosition!.accuracy}m - trying fresh GPS reading...');
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Waiting for better GPS signal...'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        
        // Wait a bit more for GPS to stabilize
        await Future.delayed(const Duration(seconds: 5));
        
        try {
          final freshPosition = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.bestForNavigation,
            timeLimit: const Duration(seconds: 30),
          );
          
          if (freshPosition.accuracy < bestPosition!.accuracy) {
            bestPosition = freshPosition;
            debugPrint('✅ Got better position: ${freshPosition.accuracy}m');
          }
        } catch (e) {
          debugPrint('⚠️ Fresh GPS read failed: $e');
        }
      }
      
      // Use best position found, or error if none
      if (bestPosition == null) {
        throw Exception('Could not get GPS location');
      }
      
      final position = bestPosition!;
      
      // Warn user if accuracy is still poor
      if (position.accuracy > 200) {
        debugPrint('⚠️⚠️ WARNING: Location accuracy is poor (${position.accuracy}m). For better results:');
        debugPrint('   1. Move to an open area with clear sky view');
        debugPrint('   2. Wait a few seconds for GPS to improve');
        debugPrint('   3. Make sure location services are enabled');
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Location accuracy: ${position.accuracy.toStringAsFixed(0)}m\n'
                'For better accuracy, move to an open area.',
              ),
              duration: const Duration(seconds: 5),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }

      debugPrint('✅ Location: ${position.latitude}, ${position.longitude}');
      debugPrint('   Accuracy: ${position.accuracy} meters');

      if (!mounted) return;

      setState(() {
        _selectedLocation = LatLng(position.latitude, position.longitude);
      });

      // Wait for map to be ready before moving
      await Future.delayed(const Duration(milliseconds: 300));
      
      // Move map to exact location with very high zoom (18 = building level)
      if (mounted) {
        _mapController.move(_selectedLocation, 18.0);
        // Get exact address using reverse geocoding
        await _updateAddress(_selectedLocation);
      }
    } catch (e) {
      debugPrint('Error getting current location: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error getting location: $e')),
        );
      }
    }
  }

  Future<void> _updateAddress(LatLng pos) async {
    if (!mounted) return;
    
    setState(() => _fetchingAddress = true);
    
    try {
      // Use OpenStreetMap Nominatim Reverse Geocoding API for exact address
      final url =
          'https://nominatim.openstreetmap.org/reverse?format=json&lat=${pos.latitude}&lon=${pos.longitude}&zoom=18&addressdetails=1';

      final response = await http.get(Uri.parse(url), headers: {
        'User-Agent': 'SerbisyoKoApp/1.0 (contact@serbisyo.com)',
      });

      if (response.statusCode == 200 && mounted) {
        final data = json.decode(response.body);
        final address = data['address'];
        String displayName = data['display_name'] ?? '';
        
        // Format address with complete location name details
        if (address != null && address is Map) {
          final addr = address as Map<String, dynamic>;
          final parts = <String>[];
          
          // Named place (highest priority - most specific location name)
          if (addr['name'] != null) parts.add(addr['name'].toString());
          
          // Building/Property name
          if (addr['building'] != null) parts.add(addr['building'].toString());
          
          // Amenity name (shops, restaurants, landmarks)
          if (addr['amenity'] != null) parts.add(addr['amenity'].toString());
          
          // House/Building number
          if (addr['house_number'] != null) parts.add(addr['house_number'].toString());
          
          // Street/Road name
          if (addr['road'] != null) parts.add(addr['road'].toString());
          if (addr['street'] != null && !parts.contains(addr['street'].toString())) {
            parts.add(addr['street'].toString());
          }
          
          // Quarter/Residential area
          if (addr['quarter'] != null) parts.add(addr['quarter'].toString());
          
          // Neighborhood/Village/Suburb
          if (addr['neighbourhood'] != null) parts.add(addr['neighbourhood'].toString());
          if (addr['village'] != null) parts.add(addr['village'].toString());
          else if (addr['suburb'] != null) parts.add(addr['suburb'].toString());
          if (addr['residential'] != null && !parts.contains(addr['residential'].toString())) {
            parts.add(addr['residential'].toString());
          }
          
          // Barangay (Philippines specific)
          if (addr['barangay'] != null) parts.add(addr['barangay'].toString());
          
          // City/Town/Municipality
          if (addr['town'] != null) parts.add(addr['town'].toString());
          else if (addr['city'] != null) parts.add(addr['city'].toString());
          else if (addr['municipality'] != null) parts.add(addr['municipality'].toString());
          
          // District
          if (addr['district'] != null) parts.add(addr['district'].toString());
          
          // State/Province/Region
          if (addr['region'] != null) parts.add(addr['region'].toString());
          if (addr['state'] != null) parts.add(addr['state'].toString());
          else if (addr['province'] != null) parts.add(addr['province'].toString());
          
          // Country
          if (addr['country'] != null) parts.add(addr['country'].toString());
          
          if (parts.isNotEmpty) {
            displayName = parts.join(', ');
          }
        }
        
        // Fallback to display_name if formatted address is empty
        if (displayName.isEmpty) {
          displayName = data['display_name'] ?? '';
        }
        
        // Final fallback - format coordinates
        if (displayName.isEmpty || displayName.toLowerCase().contains('unknown')) {
          displayName = "${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}";
        }
        
        if (mounted) {
          setState(() {
            _currentAddress = displayName;
            _searchController.text = displayName;
            _fetchingAddress = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _currentAddress = "${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}";
            _searchController.text = _currentAddress;
            _fetchingAddress = false;
          });
        }
      }
    } catch (e) {
      debugPrint("Reverse geocode error: $e");
      if (mounted) {
        setState(() {
          _currentAddress = "${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}";
          _searchController.text = _currentAddress;
          _fetchingAddress = false;
        });
      }
    }
  }

  void _onMapTap(TapPosition tapPosition, LatLng point) {
    setState(() {
      _selectedLocation = point;
    });
    _updateAddress(point);
  }

  Future<void> _searchLocation(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }

    // Cancel previous debounce timer
    _searchDebounce?.cancel();

    // Debounce search by 500ms
    _searchDebounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final url =
            'https://nominatim.openstreetmap.org/search?format=json&q=${Uri.encodeComponent(query)}&limit=5&addressdetails=1';

        final response = await http.get(Uri.parse(url), headers: {
          'User-Agent': 'SerbisyoKoApp/1.0 (contact@serbisyo.com)',
        });

        if (response.statusCode == 200 && mounted) {
          final data = json.decode(response.body) as List;
          final results = <Map<String, dynamic>>[];
          
          for (final item in data) {
            final itemMap = Map<String, dynamic>.from(item);
            final address = itemMap['address'];
            
            // Build full extended location name
            String displayName = itemMap['display_name'] ?? '';
            if (address != null && address is Map) {
              final addr = address as Map<String, dynamic>;
              final parts = <String>[];
              
              // Named place (highest priority - most specific location name)
              if (addr['name'] != null) parts.add(addr['name'].toString());
              
              // Building/Property name
              if (addr['building'] != null) parts.add(addr['building'].toString());
              
              // Amenity name
              if (addr['amenity'] != null) parts.add(addr['amenity'].toString());
              
              // Street/Road name
              if (addr['road'] != null) parts.add(addr['road'].toString());
              if (addr['street'] != null && !parts.contains(addr['street'].toString())) {
                parts.add(addr['street'].toString());
              }
              
              // Quarter/Residential area
              if (addr['quarter'] != null) parts.add(addr['quarter'].toString());
              
              // Neighborhood/Village/Suburb
              if (addr['neighbourhood'] != null) parts.add(addr['neighbourhood'].toString());
              if (addr['village'] != null) parts.add(addr['village'].toString());
              else if (addr['suburb'] != null) parts.add(addr['suburb'].toString());
              if (addr['residential'] != null && !parts.contains(addr['residential'].toString())) {
                parts.add(addr['residential'].toString());
              }
              
              // Barangay (Philippines specific)
              if (addr['barangay'] != null) parts.add(addr['barangay'].toString());
              
              // City/Town/Municipality
              if (addr['town'] != null) parts.add(addr['town'].toString());
              else if (addr['city'] != null) parts.add(addr['city'].toString());
              else if (addr['municipality'] != null) parts.add(addr['municipality'].toString());
              
              // District
              if (addr['district'] != null) parts.add(addr['district'].toString());
              
              // State/Province/Region
              if (addr['region'] != null) parts.add(addr['region'].toString());
              if (addr['state'] != null) parts.add(addr['state'].toString());
              else if (addr['province'] != null) parts.add(addr['province'].toString());
              
              // Country
              if (addr['country'] != null) parts.add(addr['country'].toString());
              
              if (parts.isNotEmpty) {
                displayName = parts.join(', ');
              }
              
              if (addr['house_number'] != null) parts.add(addr['house_number'].toString());
              if (addr['road'] != null) parts.add(addr['road'].toString());
              if (addr['village'] != null) parts.add(addr['village'].toString());
              else if (addr['suburb'] != null) parts.add(addr['suburb'].toString());
              if (addr['town'] != null) parts.add(addr['town'].toString());
              else if (addr['city'] != null) parts.add(addr['city'].toString());
              if (addr['state'] != null) parts.add(addr['state'].toString());
              if (addr['country'] != null) parts.add(addr['country'].toString());
              
              if (parts.isNotEmpty) {
                displayName = parts.join(', ');
              }
            }
            
            results.add({
              'name': itemMap['display_name'] ?? displayName,
              'address': displayName,
              'lat': double.parse(itemMap['lat']?.toString() ?? '0'),
              'lng': double.parse(itemMap['lon']?.toString() ?? '0'),
            });
          }
          
          if (mounted) {
            setState(() {
              _searchResults = results;
            });
          }
        }
      } catch (e) {
        debugPrint("Location search error: $e");
      }
    });
  }

  void _selectLocation(Map<String, dynamic> location) {
    final lat = location['lat'] is double 
        ? location['lat'] as double
        : double.parse(location['lat'].toString());
    final lng = location['lng'] is double 
        ? location['lng'] as double
        : double.parse(location['lng'].toString());
    
    setState(() {
      _selectedLocation = LatLng(lat, lng);
      _searchController.text = location['address'] ?? location['name'] ?? '';
      _currentAddress = location['address'] ?? location['name'] ?? '';
    });
    _mapController.move(_selectedLocation, 17.0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Select your location',
          style: TextStyle(
              color: Colors.black, fontSize: 18, fontWeight: FontWeight.w500),
        ),
        actions: [
          // Support icon like in the reference
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFED9121),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.headset_mic,
                  color: Colors.white,
                  size: 16,
                ),
              ),
              onPressed: () {
                // Handle support action
              },
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Enhanced Search Bar - Like MyKuya reference
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                onChanged: _searchLocation,
                decoration: InputDecoration(
                  hintText: 'Search for a location',
                  hintStyle: TextStyle(color: Colors.grey.shade500),
                  prefixIcon: Container(
                    margin: const EdgeInsets.all(8),
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.search,
                      color: Colors.grey.shade600,
                      size: 18,
                    ),
                  ),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(Icons.clear,
                                  color: Colors.grey.shade600, size: 20),
                              onPressed: () {
                                _searchController.clear();
                                _searchLocation('');
                              },
                            ),
                            const Padding(
                              padding: EdgeInsets.only(right: 8),
                              child: Text(
                                'Cancel',
                                style: TextStyle(
                                  color: Color(0xFFED9121),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                ),
              ),
            ),
          ),

          // Search Results or Map
          Expanded(
            child: _searchController.text.isNotEmpty
                ? _buildSearchResults()
                : _buildMap(),
          ),

          // Enhanced Bottom Panel - Shows exact location address
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Display exact location address
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.location_on,
                          color: Color(0xFFED9121),
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _fetchingAddress
                              ? const Row(
                                  children: [
                                    SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Getting exact location...',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                )
                              : Text(
                                  _currentAddress.isNotEmpty
                                      ? _currentAddress
                                      : _searchController.text.isNotEmpty
                                          ? _searchController.text
                                          : 'Select a location on the map',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _currentAddress.isEmpty && _searchController.text.isEmpty
                          ? null
                          : () {
                              widget.onLocationSelected(
                                _currentAddress.isNotEmpty
                                    ? _currentAddress
                                    : _searchController.text,
                                _selectedLocation.latitude,
                                _selectedLocation.longitude,
                              );
                              Navigator.pop(context);
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFED9121),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey[300],
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                        shadowColor: const Color(0xFFED9121).withValues(alpha: 0.3),
                      ),
                      child: const Text(
                        'Confirm Location',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
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

  Widget _buildSearchResults() {
    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filter Tabs
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _buildFilterTab('Recent', true),
                const SizedBox(width: 16),
                _buildFilterTab('Suggested', false),
                const SizedBox(width: 16),
                _buildFilterTab('Saved', false),
              ],
            ),
          ),

          // Search Results
          Expanded(
            child: ListView.builder(
              itemCount: _searchResults.length,
              itemBuilder: (context, index) {
                final location = _searchResults[index];
                return _buildLocationTile(location);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTab(String title, bool isSelected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isSelected ? Colors.blue.shade100 : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        title,
        style: TextStyle(
          color: isSelected ? Colors.blue : Colors.grey.shade600,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _buildLocationTile(Map<String, dynamic> location) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: location['isCurrent'] == true
                ? const Color(0xFFED9121).withValues(alpha: 0.1)
                : Colors.grey.shade100,
            shape: BoxShape.circle,
          ),
          child: Icon(
            location['isCurrent'] == true
                ? Icons.my_location
                : Icons.location_on,
            color: location['isCurrent'] == true
                ? const Color(0xFFED9121)
                : Colors.grey.shade600,
            size: 20,
          ),
        ),
        title: Text(
          location['name'],
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              location['address'],
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 14,
              ),
            ),
            if (location['distance'] != null)
              Text(
                location['distance'],
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 12,
                ),
              ),
          ],
        ),
        trailing: Icon(
          Icons.arrow_forward_ios,
          color: Colors.grey.shade400,
          size: 16,
        ),
        onTap: () => _selectLocation(location),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    );
  }

  Widget _buildMap() {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          // Map
          Expanded(
            flex: 3,
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _selectedLocation,
                initialZoom: 15.0,
                onTap: _onMapTap,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.serbisyoko',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _selectedLocation,
                      child: SizedBox(
                        width: 40,
                        height: 50,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Red teardrop marker like MyKuya reference
                            CustomPaint(
                              size: const Size(40, 50),
                              painter: _TeardropMarkerPainter(),
                            ),
                            // White center dot
                            Container(
                              width: 12,
                              height: 12,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Map Controls
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                FloatingActionButton(
                  onPressed: _getCurrentLocation,
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  elevation: 4,
                  child: const Icon(Icons.my_location),
                ),
                // Google attribution like in reference
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: const Text(
                    'Google',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom painter for the teardrop marker like MyKuya reference
class _TeardropMarkerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;

    final path = ui.Path();

    // Create teardrop shape
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final radius = size.width / 2 - 2;

    // Top circle
    path.addOval(Rect.fromCircle(
      center: Offset(centerX, centerY - 5),
      radius: radius,
    ));

    // Bottom point
    path.moveTo(centerX - radius + 2, centerY + 2);
    path.lineTo(centerX, size.height - 2);
    path.lineTo(centerX + radius - 2, centerY + 2);
    path.close();

    canvas.drawPath(path, paint);

    // Add white border
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
