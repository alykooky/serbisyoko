import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'utils/matching.dart';
import 'provider_profile.dart';

class ProviderResultsScreen extends StatefulWidget {
  final String serviceName;
  final String? subcategory;
  const ProviderResultsScreen({super.key, required this.serviceName, this.subcategory});

  @override
  State<ProviderResultsScreen> createState() => _ProviderResultsScreenState();
}

class _ProviderResultsScreenState extends State<ProviderResultsScreen> {
  bool _loading = true;
  List<MatchResult> _results = [];
  double? _myLat;
  double? _myLng;
  RealtimeChannel? _availabilityChannel;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribeToAvailability();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // location
      try {
        final enabled = await Geolocator.isLocationServiceEnabled();
        if (enabled) {
          var perm = await Geolocator.checkPermission();
          if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
          if (perm != LocationPermission.denied && perm != LocationPermission.deniedForever) {
            final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
            _myLat = pos.latitude;
            _myLng = pos.longitude;
          }
        }
      } catch (_) {}

      final supa = Supabase.instance.client;
      final users = await supa.from('users').select('id,name,role').eq('role', 'Worker');
      final profiles = await supa
          .from('worker_profiles')
          .select('user_id,is_verified,availability_status,lat,lng,hourly_rate');
      final skillsRows = await supa
          .from('worker_skills')
          .select('worker_id, service:service_id(name)');
      // Try aggregated view first, fallback to raw ratings
      Map<String, Map<String, num>> ratingAgg = {};
      try {
        final ratingView = await supa.from('worker_rating_agg').select('worker_id, avg_score, num_ratings');
        ratingAgg = {
          for (final r in ratingView as List)
            (r['worker_id'] as String): {
              'avg': (r['avg_score'] as num?) ?? 0,
              'count': (r['num_ratings'] as num?) ?? 0,
            }
        };
      } catch (_) {
        // Fallback to raw ratings calculation
        final ratingsRaw = await supa.from('ratings').select('worker_id, score');
        final Map<String, List<num>> acc = {};
        for (final row in ratingsRaw as List) {
          final wid = row['worker_id'] as String?;
          final score = row['score'] as num?;
          if (wid != null && score != null) {
            acc.putIfAbsent(wid, () => []).add(score);
          }
        }
        ratingAgg = {
          for (final entry in acc.entries)
            entry.key: {
              'avg': entry.value.isEmpty ? 0.0 : entry.value.reduce((a, b) => a + b) / entry.value.length,
              'count': entry.value.length,
            }
        };
      }

      final Map<String, Map<String, dynamic>> profileByUser = {
        for (final p in profiles as List) (p['user_id'] as String): p as Map<String, dynamic>
      };
      final Map<String, List<String>> skillsByUser = {};
      for (final s in skillsRows as List) {
        final wid = s['worker_id'] as String?;
        final service = (s['service'] as Map?)?['name'] as String?;
        if (wid != null && service != null) {
          skillsByUser.putIfAbsent(wid, () => []).add(service);
        }
      }

      final List<WorkerCandidate> candidates = [];
      for (final u in users as List) {
        final id = u['id'] as String;
        final name = (u['name'] as String?) ?? 'Worker';
        final prof = profileByUser[id];
        if (prof == null) continue;
        final double avg = (ratingAgg[id]?['avg']?.toDouble()) ?? 0.0;
        final int jobs = (ratingAgg[id]?['count']?.toInt()) ?? 0;
        final bool available = (prof['availability_status'] == 'ON');
        if (!available) continue;
        final bool verified = (prof['is_verified'] == true);
        final double? wlat = (prof['lat'] as num?)?.toDouble();
        final double? wlng = (prof['lng'] as num?)?.toDouble();
        final int? fee = (prof['hourly_rate'] as num?)?.toInt();

        candidates.add(WorkerCandidate(
          userId: id,
          name: name,
          skills: skillsByUser[id] ?? const [],
          lat: wlat,
          lng: wlng,
          ratingAverage: avg,
          jobsDone: jobs,
          isAvailable: available,
          isVerified: verified,
          estimatedFee: fee,
        ));
      }

      final ranked = rankWorkers(
        workers: candidates,
        requiredService: widget.serviceName,
        clientLat: _myLat,
        clientLng: _myLng,
      );
      setState(() => _results = ranked);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Search error: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _subscribeToAvailability() {
    try {
      _availabilityChannel = Supabase.instance.client
          .channel('worker_profiles_availability')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'worker_profiles',
            callback: (payload) {
              final newRow = payload.newRecord as Map<String, dynamic>?;
              final oldRow = payload.oldRecord as Map<String, dynamic>?;
              if (newRow == null) return;
              // Refresh only when availability or location/fee that affects ranking changes
              final newAvail = newRow['availability_status'];
              final oldAvail = oldRow != null ? oldRow['availability_status'] : null;
              final changedAvailability = oldAvail != newAvail;
              final changedLat = oldRow != null ? oldRow['lat'] != newRow['lat'] : false;
              final changedLng = oldRow != null ? oldRow['lng'] != newRow['lng'] : false;
              final changedRate = oldRow != null ? oldRow['hourly_rate'] != newRow['hourly_rate'] : false;
              final changedVerified = oldRow != null ? oldRow['is_verified'] != newRow['is_verified'] : false;
              if (changedAvailability || changedLat || changedLng || changedRate || changedVerified) {
                _load();
              }
            },
          )
          .subscribe();
    } catch (_) {}
  }

  @override
  void dispose() {
    if (_availabilityChannel != null) {
      Supabase.instance.client.removeChannel(_availabilityChannel!);
      _availabilityChannel = null;
    }
    super.dispose();
  }

  double? _distanceKm(double? lat, double? lng) {
    if (_myLat == null || _myLng == null || lat == null || lng == null) return null;
    const Distance d = Distance();
    return d.as(LengthUnit.Kilometer, LatLng(_myLat!, _myLng!), LatLng(lat, lng));
  }

  @override
  Widget build(BuildContext context) {
    final accent = const Color(0xFFED9121);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: accent,
        title: Text(
          widget.subcategory == null
              ? widget.serviceName
              : '${widget.serviceName} · ${widget.subcategory}',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFED9121)))
          : ListView.separated(
              itemCount: _results.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final r = _results[i];
                final w = r.worker;
                final dkm = _distanceKm(w.lat, w.lng);
                return ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(w.name),
                  subtitle: Text(
                      '₱${w.estimatedFee ?? 0} / hour • ${w.ratingAverage.toStringAsFixed(1)} ★ • ${dkm != null ? dkm.toStringAsFixed(2) + ' km' : 'distance n/a'}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ProviderProfileScreen(workerId: w.userId),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}


