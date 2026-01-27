import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/matching_models.dart';
import '../models/worker_model.dart';
import '/services/supabase_service.dart';
import 'worker_profile.dart';

class AdvancedMatchingService {
  static SupabaseClient get _supabase => Supabase.instance.client;

  static const _weights = <String, double>{
    'skills': 0.25,
    'performance': 0.20,
    'availability': 0.15,
    'credentials': 0.15,
    'location': 0.15,
    'estimatedFee': 0.10,
  };

  /// Fetch and rank matching providers
  static Future<List<Map<String, dynamic>>> findBestMatches({
    required String serviceType,
    required double clientLatitude,
    required double clientLongitude,
    required DateTime preferredStartTime,
    required DateTime preferredEndTime,
    required double budgetMin,
    required double budgetMax,
    bool isUrgent = false,
    int limit = 10,
    double searchRadiusKm = 15,
  }) async {
    await SupabaseService.ensureInitialized();

    final input = MatchInput(
      serviceType: serviceType,
      clientLat: clientLatitude,
      clientLng: clientLongitude,
      budgetMin: budgetMin,
      budgetMax: budgetMax,
      preferredStart: preferredStartTime,
      preferredEnd: preferredEndTime,
      isUrgent: isUrgent,
      limit: limit,
      searchRadiusKm: searchRadiusKm,
    );

    try {
      final workers = await _fetchCandidateWorkers(input);
      if (workers.isEmpty) {
        debugPrint(
            '[AdvancedMatchingService] ❌ No providers found for ${input.serviceType}');
        return [];
      }

      final ranked = _scoreCandidates(workers, input);
      if (ranked.isEmpty) return [];

      ranked.sort((a, b) {
        final primary = b.totalScore.compareTo(a.totalScore);
        if (primary != 0) return primary;

        final aDist = a.distanceKm ?? double.infinity;
        final bDist = b.distanceKm ?? double.infinity;
        final distCompare = aDist.compareTo(bDist);
        if (distCompare != 0) return distCompare;

        final ratingCompare =
            b.worker.averageRating.compareTo(a.worker.averageRating);
        if (ratingCompare != 0) return ratingCompare;

        final jobCompare =
            b.worker.completedJobs.compareTo(a.worker.completedJobs);
        if (jobCompare != 0) return jobCompare;

        final aSeen =
            a.worker.lastSeen ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bSeen =
            b.worker.lastSeen ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bSeen.compareTo(aSeen);
      });

      final limited = ranked.take(input.limit).toList();

      debugPrint(
          '\n🎯 [AdvancedMatchingService] Ranked Matches for "${input.serviceType}":');
      for (final rp in limited) {
        final w = rp.worker;
        debugPrint(
            '→ ${w.name} | Score: ${rp.totalScore.toStringAsFixed(3)} | Dist: ${(rp.distanceKm ?? 0).toStringAsFixed(2)} km | Skills: ${w.skills.join(", ")}');
      }
      debugPrint('-----------------------------------------------------------');

      return limited.map((rp) => rp.toMap()).toList();
    } catch (e, st) {
      debugPrint('[AdvancedMatchingService] ❌ Error: $e');
      debugPrint(st.toString());
      return [];
    }
  }

  /// Fetch candidates based on skills and proximity
  static Future<List<WorkerProfile>> _fetchCandidateWorkers(
      MatchInput input) async {
    final latRadius = input.searchRadiusKm / 111.0;
    final cosLat = cos(input.clientLat * pi / 180.0);
    final lonDivisor = cosLat.abs() < 0.0001 ? 0.0001 : cosLat;
    final lonRadius = input.searchRadiusKm / (111.0 * lonDivisor);

    final minLat = input.clientLat - latRadius;
    final maxLat = input.clientLat + latRadius;
    final minLng = input.clientLng - lonRadius;
    final maxLng = input.clientLng + lonRadius;

    final normalizedService = _normalizeSkill(input.serviceType);

    // 1️⃣ Match skills
    final skillsResponse = await _supabase
        .from('skills')
        .select('id, name, category')
        .or('ilike(name,%$normalizedService%),ilike(category,%$normalizedService%)');

    if (skillsResponse.isEmpty) {
      debugPrint('[MATCH] ❌ No matching skills for $normalizedService');
      return [];
    }

    final skillIds = skillsResponse.map((e) => e['id'] as String).toList();
    final skillNames = {
      for (final s in skillsResponse) s['id']: s['name'] ?? ''
    };
    debugPrint('[MATCH] ✅ Found ${skillIds.length} matching skills');

    // 2️⃣ Find workers by skill_id
    final ws = await _supabase
        .from('worker_skills')
        .select('worker_id, skill_id')
        .inFilter('skill_id', skillIds);

    final workerIds = ws.map((r) => r['worker_id'].toString()).toSet().toList();
    if (workerIds.isEmpty) {
      debugPrint('[MATCH] ❌ No workers with those skills');
      return [];
    }

    // Map worker → skills
    final skillsByWorker = <String, List<String>>{};
    for (final row in ws) {
      final wid = row['worker_id'].toString();
      final sid = row['skill_id'] as String?;
      final sname = (sid != null ? skillNames[sid] : null)?.toString() ?? '';
      if (sname.isNotEmpty) (skillsByWorker[wid] ??= []).add(sname);
    }

    // 3️⃣ Fetch worker profiles within area
    var profiles = await _supabase
        .from('worker_profiles')
        .select('*')
        .inFilter('user_id', workerIds)
        .neq('availability_status', 'OFF')
        .gte('lat', minLat)
        .lte('lat', maxLat)
        .gte('lng', minLng)
        .lte('lng', maxLng);

    if (profiles is List && profiles.isEmpty) {
      debugPrint('[MATCH] ⚠️ Retrying with latitude/longitude');
      profiles = await _supabase
          .from('worker_profiles')
          .select('*')
          .inFilter('user_id', workerIds)
          .neq('availability_status', 'OFF')
          .gte('latitude', minLat)
          .lte('latitude', maxLat)
          .gte('longitude', minLng)
          .lte('longitude', maxLng);
    }

    if (profiles is! List || profiles.isEmpty) {
      debugPrint('[MATCH] ❌ No worker profiles matched area');
      return [];
    }

    // 4️⃣ Convert to WorkerProfile objects
    final workers = <WorkerProfile>[];
    for (final raw in profiles) {
      final data = Map<String, dynamic>.from(raw);
      final id = (data['user_id'] ?? data['worker_id'])?.toString();
      if (id == null) continue;

      final lat = (data['lat'] ?? data['latitude']) as num?;
      final lng = (data['lng'] ?? data['longitude']) as num?;
      final skills = skillsByWorker[id] ?? const <String>[];

      workers.add(WorkerProfile(
        id: id,
        userId: id,
        name: (data['display_name'] ?? data['full_name'] ?? 'Worker') as String,
        email: (data['email'] ?? '') as String, // ✅ added email
        phone: (data['phone'] ?? '') as String,
        address: (data['address'] ?? '') as String,
        latitude: (lat is num) ? (lat as num).toDouble() : 0.0, // ✅ safe cast
        longitude: (lng is num) ? (lng as num).toDouble() : 0.0, // ✅ safe cast
        hourlyRate: (data['hourly_rate'] is num)
            ? (data['hourly_rate'] as num).toDouble()
            : 0.0,
        isVerified: data['is_verified'] == true,
        verificationStatus:
            (data['verification_status'] ?? 'Unverified') as String,
        availabilityStatus: (data['availability_status'] ?? 'OFF') as String,
        lastSeen: data['last_seen'] != null
            ? DateTime.tryParse(data['last_seen'].toString())
            : null,
        createdAt: data['created_at'] != null
            ? DateTime.tryParse(data['created_at'].toString()) ?? DateTime.now()
            : DateTime.now(),
        updatedAt: data['updated_at'] != null
            ? DateTime.tryParse(data['updated_at'].toString()) ?? DateTime.now()
            : DateTime.now(),
        profileImage: data['profile_image'],
        bio: data['bio'],
        skills: skills,
        averageRating: (data['average_rating'] ?? 0.0).toDouble(),
        totalJobs: (data['total_jobs'] ?? 0) as int,
        completedJobs: (data['completed_jobs'] ?? 0) as int,
      ));
    }

    debugPrint(
        '[MATCH] ✅ Returning ${workers.length} candidate workers (with skills)');
    return workers;
  }

  /// Calculate weighted scores
  static List<RankedProvider> _scoreCandidates(
      List<WorkerProfile> workers, MatchInput input) {
    final ranked = <RankedProvider>[];
    final distances = <double>[];
    var highestCompletedJobs = 0;

    for (final w in workers) {
      final d = _distanceKm(
          input.clientLat, input.clientLng, w.latitude, w.longitude);
      if (d != null) distances.add(d);
      if (w.completedJobs > highestCompletedJobs)
        highestCompletedJobs = w.completedJobs;
    }

    final nearest = distances.isEmpty ? null : distances.reduce(min);

    for (final w in workers) {
      final rp = _evaluateWorker(w, input, nearest, highestCompletedJobs);
      if (rp != null) ranked.add(rp);
    }

    return ranked;
  }

  static RankedProvider? _evaluateWorker(
    WorkerProfile worker,
    MatchInput input,
    double? nearestDistance,
    int highestCompletedJobs,
  ) {
    final normalizedSkills =
        worker.skills.map(_normalizeSkill).toList(growable: false);
    final normalizedService = _normalizeSkill(input.serviceType);
    final tokens = normalizedService
        .split(RegExp(r'[\s_\-]+'))
        .where((t) => t.isNotEmpty)
        .toList();

    final matchedSkills = <String>[];
    for (final s in worker.skills) {
      final norm = _normalizeSkill(s);
      if (norm == normalizedService || tokens.any((t) => norm.contains(t))) {
        matchedSkills.add(s);
      }
    }

    final hasDirectMatch = normalizedSkills.contains(normalizedService);
    final skillScore = hasDirectMatch
        ? 1.0
        : matchedSkills.isNotEmpty
            ? 0.6
            : 0.0;
    if (skillScore == 0.0) return null;

    final distance = _distanceKm(
        input.clientLat, input.clientLng, worker.latitude, worker.longitude);

    double locationScore = 0.0;
    if (distance != null) {
      if (distance <= 0.5) {
        locationScore = 1.0;
      } else if (distance > input.searchRadiusKm) {
        locationScore = 0.0;
      } else if (nearestDistance != null && nearestDistance > 0) {
        locationScore = _clamp01(nearestDistance / distance);
      } else {
        locationScore = _clamp01(1 / distance);
      }
    }

    final ratingScore = _clamp01(worker.averageRating / 5.0);
    double performanceScore;
    if (highestCompletedJobs > 0) {
      final jobsRatio =
          _clamp01(worker.completedJobs / highestCompletedJobs.toDouble());
      performanceScore = _clamp01(0.7 * ratingScore + 0.3 * jobsRatio);
    } else {
      performanceScore = ratingScore;
    }

    double availabilityScore;
    switch (worker.availabilityStatus.toUpperCase()) {
      case 'ON':
        availabilityScore = 1.0;
        break;
      case 'BUSY':
        availabilityScore = 0.4;
        break;
      default:
        availabilityScore = 0.0;
    }

    final credentialsScore = worker.isVerified ? 1.0 : 0.0;

    final rate = worker.hourlyRate;
    double feeScore = 0.5;
    if (rate > 0) {
      if (rate >= input.budgetMin && rate <= input.budgetMax) {
        feeScore = 1.0;
      } else if (rate < input.budgetMin) {
        final diff = input.budgetMin - rate;
        feeScore =
            max(0.4, 1 - diff / (input.budgetMin == 0 ? 1 : input.budgetMin));
      } else {
        final diff = rate - input.budgetMax;
        feeScore = max(
            0.0, 1 - diff / (input.budgetMax == 0 ? rate : input.budgetMax));
      }
    }

    double total = (_weights['skills']! * skillScore) +
        (_weights['performance']! * performanceScore) +
        (_weights['availability']! * availabilityScore) +
        (_weights['credentials']! * credentialsScore) +
        (_weights['location']! * locationScore) +
        (_weights['estimatedFee']! * feeScore);

    total = _clamp01(total);

    final etaMin =
        distance != null ? (distance / (input.isUrgent ? 35 : 25)) * 60 : null;

    return RankedProvider(
      worker: worker,
      totalScore: double.parse(total.toStringAsFixed(4)),
      breakdown: MatchScoreBreakdown(
        skills: skillScore,
        performance: performanceScore,
        availability: availabilityScore,
        credentials: credentialsScore,
        location: locationScore,
        estimatedFee: feeScore,
      ),
      distanceKm: distance,
      matchedSkills: matchedSkills,
      etaMinutes: etaMin,
      notes: [
        if (rate >= input.budgetMin && rate <= input.budgetMax) 'Within budget',
        if (distance != null && distance <= 3) 'Nearby',
        if (worker.isVerified) 'Verified',
        if (worker.averageRating >= 4.5) 'Highly rated',
      ],
    );
  }

  // --- Helpers ---
  static double? _distanceKm(
      double lat1, double lng1, double lat2, double lng2) {
    if (!_validCoordinate(lat1, lng1) || !_validCoordinate(lat2, lng2))
      return null;
    const r = 6371.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_deg2rad(lat1)) *
            cos(_deg2rad(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  static double _deg2rad(double deg) => deg * pi / 180;
  static bool _validCoordinate(double lat, double lng) =>
      lat.abs() <= 90 && lng.abs() <= 180;
  static double _clamp01(double v) => v.isNaN ? 0 : v.clamp(0.0, 1.0);
  static String _normalizeSkill(String v) =>
      v.trim().toLowerCase().replaceAll('-', '_');
}
