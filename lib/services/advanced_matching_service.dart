// lib/services/advanced_matching_service.dart

import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/matching_models.dart';
import '../models/worker_profile.dart';

class AdvancedMatchingService {
  static SupabaseClient get _sb => Supabase.instance.client;

  /// Weights
  static const Map<String, double> _w = {
    'skills': 0.25,
    'performance': 0.20,
    'availability': 0.15,
    'credentials': 0.15,
    'location': 0.15,
    'estimatedFee': 0.10,
  };

  // ------------------------------------------------------------
  // 🔵 PUBLIC API — main entry for matching
  // ------------------------------------------------------------
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
    final input = MatchInput(
      serviceType: serviceType,
      clientLat: clientLatitude,
      clientLng: clientLongitude,
      budgetMin: budgetMin,
      budgetMax: budgetMax,
      preferredStart: preferredStartTime,
      preferredEnd: preferredEndTime,
      limit: limit,
      searchRadiusKm: searchRadiusKm,
      isUrgent: isUrgent,
    );

    debugPrint("\n▶️ MATCHING STARTED");
    debugPrint("Service: ${input.serviceType}");
    debugPrint("Location: ${input.clientLat}, ${input.clientLng}");
    debugPrint("Budget: ${input.budgetMin} - ${input.budgetMax}");
    debugPrint("Preferred Start Time: ${input.preferredStart}");
    debugPrint("Preferred End Time: ${input.preferredEnd}");
    debugPrint("────");

    try {
      final workers = await _fetchCandidates(input);

      if (workers.isEmpty) {
        debugPrint("⚠️ No workers found with matching skills.");
        debugPrint("   This could mean:");
        debugPrint(
            "   - No skills match the service type '${input.serviceType}'");
        debugPrint("   - No workers have those skills");
        debugPrint("   - No workers are available (status != 'OFF')");
        debugPrint("   - No workers within ${input.searchRadiusKm}km radius");
        return [];
      }

      debugPrint(
          "✅ Found ${workers.length} candidate workers, attaching ratings...");
      await _attachRatings(workers);

      debugPrint("✅ Calculating scores for ${workers.length} workers...");
      final ranked = _scoreCandidates(workers, input);

      ranked.sort((a, b) {
        final t = b.totalScore.compareTo(a.totalScore);
        if (t != 0) return t;

        final da = a.distanceKm ?? double.infinity;
        final db = b.distanceKm ?? double.infinity;
        final d = da.compareTo(db);
        if (d != 0) return d;

        final r = b.worker.averageRating.compareTo(a.worker.averageRating);
        if (r != 0) return r;

        final j = b.worker.completedJobs.compareTo(a.worker.completedJobs);
        if (j != 0) return j;

        final aSeen =
            a.worker.lastSeen ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bSeen =
            b.worker.lastSeen ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bSeen.compareTo(aSeen);
      });

      final top = ranked.take(limit).toList();
      _printDebugTable(top, input);

      return top.map((r) => r.toMap()).toList();
    } catch (e, st) {
      debugPrint("❌ MATCH ERROR: $e");
      debugPrint(st.toString());
      return [];
    }
  }

  // ------------------------------------------------------------
  // 🔵 Fetch + Normalize Workers
  // ------------------------------------------------------------
  static Future<List<WorkerProfile>> _fetchCandidates(MatchInput input) async {
    final latRadius = input.searchRadiusKm / 111.0;
    final cosLat = cos(input.clientLat * pi / 180.0);
    final lonRadius =
        input.searchRadiusKm / (111.0 * cosLat.abs().clamp(0.1, 1));

    final minLat = input.clientLat - latRadius;
    final maxLat = input.clientLat + latRadius;
    final minLng = input.clientLng - lonRadius;
    final maxLng = input.clientLng + lonRadius;

    // Normalize service text for matching - preserve hyphens for better matching
    final normService = input.serviceType.trim().toLowerCase();
    // Split into search terms (words)
    final searchTerms = normService
        .split(RegExp(r'[\s\-_]+'))
        .where((t) => t.length > 2) // Only meaningful words
        .toList();

    debugPrint("🔍 Searching for skills with terms: ${searchTerms.join(', ')}");

    // Try multiple search strategies - use 'services' table (not 'skills')
    List<Map<String, dynamic>> skillRows = [];

    // Strategy 1: Search by individual terms (more flexible)
    if (searchTerms.isNotEmpty) {
      try {
        // Build OR conditions for each term
        final orConditions = <String>[];
        for (final term in searchTerms) {
          final escapedTerm =
              term.replaceAll('%', '\\%').replaceAll('_', '\\_');
          orConditions.add('name.ilike.%$escapedTerm%');
          if (orConditions.length < 20) {
            // PostgREST has limits
            orConditions.add('category.ilike.%$escapedTerm%');
          }
        }

        skillRows = await _sb
            .from('services') // Use 'services' table, not 'skills'
            .select('id, name, category')
            .or(orConditions.join(',')) as List<Map<String, dynamic>>;

        debugPrint(
            "   Strategy 1 (term matching): Found ${skillRows.length} services");
      } catch (e) {
        debugPrint("   Strategy 1 failed: $e");
        skillRows = [];
      }
    }

    // Strategy 2: If no results, try full service name match
    if (skillRows.isEmpty) {
      try {
        final escapedFull =
            normService.replaceAll('%', '\\%').replaceAll('_', '\\_');
        skillRows = await _sb
                .from('services') // Use 'services' table
                .select('id, name, category')
                .or('name.ilike.%$escapedFull%,category.ilike.%$escapedFull%')
            as List<Map<String, dynamic>>;
        debugPrint(
            "   Strategy 2 (full name): Found ${skillRows.length} services");
      } catch (e) {
        debugPrint("   Strategy 2 failed: $e");
        skillRows = [];
      }
    }

    if (skillRows.isEmpty) {
      debugPrint("⚠️ No service found for: '${input.serviceType}'");
      debugPrint("   Searched terms: ${searchTerms.join(', ')}");
      debugPrint("   Searched in: services table");
      debugPrint("   💡 Tip: Make sure services exist in the 'services' table");
      return [];
    }

    debugPrint("✅ Found ${skillRows.length} matching services");

    final skillIds =
        skillRows.map<String>((e) => e['id'].toString()).toSet().toList();

    // 2) Worker IDs with those services - try skill_id first (most common)
    List<dynamic> ws = [];
    try {
      ws = await _sb
          .from('worker_skills')
          .select('worker_id, skill_id')
          .inFilter('skill_id', skillIds);
      debugPrint("   Using skill_id column in worker_skills");
    } catch (e) {
      debugPrint("   skill_id failed, trying service_id: $e");
      try {
        ws = await _sb
            .from('worker_skills')
            .select('worker_id, service_id')
            .inFilter('service_id', skillIds);
        debugPrint("   Using service_id column in worker_skills");
      } catch (e2) {
        debugPrint("❌ Both skill_id and service_id failed: $e2");
        return [];
      }
    }

    final workerIds = ws.map((e) => e['worker_id'].toString()).toSet().toList();

    if (workerIds.isEmpty) {
      debugPrint("⚠️ Workers exist but none have this skill.");
      return [];
    }

    // Map worker → human-readable service names
    final serviceNameById = {
      for (final s in skillRows) s['id'].toString(): s['name'].toString()
    };

    final skillsByWorker = <String, List<String>>{};
    for (final row in ws) {
      final wid = row['worker_id'].toString();
      // Try both skill_id and service_id to handle different database schemas
      final sid = (row['skill_id'] ?? row['service_id'])?.toString();
      if (sid != null) {
        final serviceName = serviceNameById[sid];
        if (serviceName != null && serviceName.isNotEmpty) {
          (skillsByWorker[wid] ??= []).add(serviceName);
        }
      }
    }

    // 3) Pull worker profiles
    // Don't filter by availability_status here - let schedule check decide
    // This allows workers with schedules to be matched even if status is currently OFF
    final prof = await _sb
        .from('worker_profiles')
        .select('*')
        .inFilter('user_id', workerIds)
        .gte('lat', minLat)
        .lte('lat', maxLat)
        .gte('lng', minLng)
        .lte('lng', maxLng);

    if (prof.isEmpty) {
      debugPrint("⚠️ No workers meet the location filter.");
      return [];
    }

    // 4) Fetch user data to get names, emails, phones
    final userData = await _sb
        .from('users')
        .select('id, name, email, phone')
        .inFilter('id', workerIds);

    final userMap = <String, Map<String, dynamic>>{};
    for (final u in userData) {
      userMap[u['id'].toString()] = Map<String, dynamic>.from(u);
    }

    final workers = <WorkerProfile>[];
    for (final raw in prof) {
      final m = Map<String, dynamic>.from(raw);
      final id = m['user_id'].toString();

      // Merge user data into worker profile
      final userInfo = userMap[id];
      if (userInfo != null) {
        m['name'] = userInfo['name'] ?? m['name'] ?? 'Unnamed Worker';
        m['email'] = userInfo['email'] ?? m['email'] ?? '';
        m['phone'] = userInfo['phone'] ?? m['phone'] ?? '';
      } else {
        // Ensure name exists
        m['name'] = m['name'] ?? 'Unnamed Worker';
      }

      final w = WorkerProfile.fromJson(m);
      w.skills = skillsByWorker[id] ?? [];

      // DEBUG
      debugPrint(
          "🟢 Worker Loaded: ${w.name}, email: ${w.email}, phone: ${w.phone}, skills=${w.skills}");

      workers.add(w);
    }

    // 4.5) Filter workers by ACTUAL distance (not just bounding box)
    // The bounding box is an approximation - we need to check actual distance
    workers.removeWhere((w) {
      final distance = _distanceKm(
        input.clientLat,
        input.clientLng,
        w.latitude,
        w.longitude,
      );
      
      if (distance == null) {
        debugPrint("⚠️ Worker ${w.name}: Invalid coordinates, excluding");
        return true; // Remove workers with invalid coordinates
      }
      
      if (distance > input.searchRadiusKm) {
        debugPrint("🚫 Worker ${w.name}: Distance ${distance.toStringAsFixed(2)} km exceeds search radius ${input.searchRadiusKm} km, excluding");
        return true; // Remove workers beyond search radius
      }
      
      debugPrint("✅ Worker ${w.name}: Distance ${distance.toStringAsFixed(2)} km is within search radius ${input.searchRadiusKm} km");
      return false; // Keep this worker
    });

    // 5) Fetch and check worker availability schedules (filter by actual schedule)
    // Check availability at the BOOKING TIME, not current time
    if (workers.isNotEmpty) {
      await _checkAvailabilitySchedules(workers, input.preferredStart);
      // Remove workers who are not available based on their schedule at booking time
      workers.removeWhere((w) => !w.isCurrentlyAvailable);
    }

    return workers;
  }

  // ------------------------------------------------------------
  // 🔵 Check if workers are available at the booking time based on schedule
  // ------------------------------------------------------------
  static Future<void> _checkAvailabilitySchedules(List<WorkerProfile> workers, DateTime bookingTime) async {
    if (workers.isEmpty) return;

    final workerIds = workers.map((w) => w.userId).toList();

    try {
      // Fetch availability schedules for all workers
      final schedules = await _sb
          .from('worker_availability')
          .select('user_id, weekday, start_at, end_at, is_active')
          .inFilter('user_id', workerIds)
          .eq('is_active', true);

      // Group schedules by worker ID
      final schedulesByWorker = <String, List<Map<String, dynamic>>>{};
      for (final s in schedules) {
        final uid = s['user_id']?.toString();
        if (uid != null) {
          (schedulesByWorker[uid] ??= []).add(Map<String, dynamic>.from(s));
        }
      }

      // Check each worker's availability at the BOOKING TIME (not current time)
      final bookingWeekday = bookingTime.weekday; // 1 = Monday, 7 = Sunday
      final bookingTimeSeconds = bookingTime.hour * 3600 + bookingTime.minute * 60 + bookingTime.second;

      debugPrint("📅 Checking availability for booking time: ${bookingTime.year}-${bookingTime.month.toString().padLeft(2, '0')}-${bookingTime.day.toString().padLeft(2, '0')} ${bookingTime.hour.toString().padLeft(2, '0')}:${bookingTime.minute.toString().padLeft(2, '0')} (Weekday: $bookingWeekday)");

      for (final worker in workers) {
        final workerSchedules = schedulesByWorker[worker.userId] ?? [];
        worker.isCurrentlyAvailable = _isWorkerAvailableAtTime(
          workerSchedules,
          bookingWeekday,
          bookingTimeSeconds,
          worker.availabilityStatus,
        );
        
        if (!worker.isCurrentlyAvailable) {
          debugPrint("⏰ Worker ${worker.name} is NOT available at booking time (outside schedule window)");
          debugPrint("   Status: ${worker.availabilityStatus}, Booking time: ${bookingTime.hour}:${bookingTime.minute}:${bookingTime.second}, Weekday: $bookingWeekday");
          if (workerSchedules.isNotEmpty) {
            for (final s in workerSchedules) {
              debugPrint("   Schedule: weekday=${s['weekday']}, ${s['start_at']} - ${s['end_at']}, active=${s['is_active']}");
            }
          } else {
            debugPrint("   No active schedules found");
          }
        } else {
          debugPrint("✅ Worker ${worker.name} IS available at booking time (within schedule window)");
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error checking availability schedules: $e');
      // If schedule check fails, fall back to status only
      for (final worker in workers) {
        worker.isCurrentlyAvailable = worker.availabilityStatus.toUpperCase() == 'ON';
      }
    }
  }

  /// Check if worker is available at a specific time based on their schedule
  /// This checks availability at the BOOKING TIME, not current time
  /// Priority: Schedule > Status (if schedule exists, check schedule first)
  static bool _isWorkerAvailableAtTime(
    List<Map<String, dynamic>> schedules,
    int targetWeekday,
    int targetTimeSeconds,
    String availabilityStatus,
  ) {
    // If worker has schedules set, check schedule first (ignore status)
    // This allows workers to be matched for future bookings even if status is currently OFF
    if (schedules.isNotEmpty) {
      // Check if target time (booking time) is within any active schedule slot
      for (final schedule in schedules) {
        if (schedule['is_active'] != true) continue;

        final weekday = schedule['weekday'] as int?;
        if (weekday == null) continue;

        final startStr = (schedule['start_at'] ?? schedule['start_time'] ?? '00:00:00').toString();
        final endStr = (schedule['end_at'] ?? schedule['end_time'] ?? '23:59:59').toString();

        // Parse time strings (HH:MM:SS)
        int _parseTime(String timeStr) {
          final parts = timeStr.split(':');
          final h = int.tryParse(parts[0]) ?? 0;
          final m = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
          return h * 3600 + m * 60;
        }

        final startSeconds = _parseTime(startStr);
        final endSeconds = _parseTime(endStr);

        // Check if target weekday matches and time is within range
        if (weekday == targetWeekday) {
          if (startSeconds <= endSeconds) {
            // Normal time range (e.g., 9:00 - 17:00)
            if (targetTimeSeconds >= startSeconds && targetTimeSeconds < endSeconds) {
              debugPrint("✅ Worker matches schedule: weekday=$targetWeekday, time=${targetTimeSeconds}s is within ${startSeconds}s - ${endSeconds}s");
              return true;
            }
          } else {
            // Overnight range (e.g., 22:00 - 06:00)
            // For overnight, check if we're past start OR before end
            if (targetTimeSeconds >= startSeconds || targetTimeSeconds < endSeconds) {
              debugPrint("✅ Worker matches overnight schedule: weekday=$targetWeekday, time=${targetTimeSeconds}s");
              return true;
            }
          }
        }
      }
      
      // No matching schedule found - worker is not available at this booking time
      debugPrint("❌ Worker does not match any schedule for weekday=$targetWeekday, time=${targetTimeSeconds}s");
      return false;
    }

    // If no schedules set, fall back to availability status (for workers who don't use schedules)
    // This allows workers without schedules to still be matched based on toggle
    final isAvailable = availabilityStatus.toUpperCase() == 'ON';
    debugPrint("⚠️ Worker has no schedule, using status: ${availabilityStatus} = ${isAvailable}");
    return isAvailable;
  }

  // ------------------------------------------------------------
  // 🔵 Attach Ratings (average + count)
  // ------------------------------------------------------------
  static Future<void> _attachRatings(List<WorkerProfile> workers) async {
    final ids = workers.map((e) => e.userId).toSet().toList();
    if (ids.isEmpty) return;

    final rows = await _sb
        .from('ratings')
        .select('worker_id, score')
        .inFilter('worker_id', ids);

    final map = <String, List<num>>{};

    for (final r in rows) {
      final wid = r['worker_id'];
      final score = r['score'];
      if (score == null) continue;
      (map[wid] ??= []).add(score);
    }

    for (final w in workers) {
      final list = map[w.userId] ?? [];
      if (list.isNotEmpty) {
        w.averageRating = list.reduce((a, b) => a + b) / list.length.toDouble();
        w.completedJobs = list.length;
      }
    }
  }

  // ------------------------------------------------------------
  // 🔵 Scoring Logic
  // ------------------------------------------------------------
  static List<RankedProvider> _scoreCandidates(
      List<WorkerProfile> workers, MatchInput input) {
    final ranked = <RankedProvider>[];
    final distances = <double>[];

    int maxJobs = 0;

    for (final w in workers) {
      final d = _distanceKm(
          input.clientLat, input.clientLng, w.latitude, w.longitude);
      if (d != null) distances.add(d);
      maxJobs = max(maxJobs, w.completedJobs);
    }

    final nearest = distances.isEmpty ? null : distances.reduce(min);

    for (final w in workers) {
      final rp = _evaluate(w, input, nearest, maxJobs);
      if (rp != null) ranked.add(rp);
    }

    return ranked;
  }

  static RankedProvider? _evaluate(
    WorkerProfile w,
    MatchInput input,
    double? nearest,
    int maxJobs,
  ) {
    // --------------------
    // ✔ SKILL SCORE
    // --------------------
    final normService = _norm(input.serviceType);
    final normSkills = w.skills.map(_norm).toList();
    final tokens = normService.split(RegExp(r'[\s_\-]+'));

    final matches = <String>[];
    for (final s in w.skills) {
      final ns = _norm(s);
      if (ns == normService || tokens.any((t) => ns.contains(t))) {
        matches.add(s);
      }
    }

    final skillsScore = matches.isNotEmpty ? 1.0 : 0.0;
    if (skillsScore == 0.0) return null;

    // --------------------
    // ✔ LOCATION SCORE
    // Formula: Location Score = Nearest Distance / Worker Distance
    // Closest worker gets 1.00, others get proportional score
    // --------------------
    final d =
        _distanceKm(input.clientLat, input.clientLng, w.latitude, w.longitude);
    double locScore = 0.0;

    if (d != null && d > 0) {
      if (nearest != null && nearest > 0) {
        // Location = Nearest Distance / Worker Distance
        locScore = (nearest / d).clamp(0.0, 1.0);
      } else {
        // If no nearest distance, use inverse distance (fallback)
        locScore = (1.0 / (1.0 + d)).clamp(0.0, 1.0);
      }
    }

    // --------------------
    // ✔ PERFORMANCE SCORE
    // Formula: Performance = (Jobs Done / Highest Jobs Done) × (Rating / 5)
    // --------------------
    double perfScore = 0.0;
    if (maxJobs > 0 && w.completedJobs >= 0) {
      final jobsRatio = (w.completedJobs / maxJobs).clamp(0.0, 1.0);
      final ratingRatio = (w.averageRating / 5.0).clamp(0.0, 1.0);
      perfScore = (jobsRatio * ratingRatio).clamp(0.0, 1.0);
    } else if (w.averageRating > 0) {
      // If no jobs done yet, use rating only
      perfScore = (w.averageRating / 5.0).clamp(0.0, 1.0);
    }

    // --------------------
    // ✔ AVAILABILITY SCORE (based on actual schedule check)
    // --------------------
    // Use isCurrentlyAvailable which checks both status AND schedule
    final availabilityScore = w.isCurrentlyAvailable
        ? 1.0
        : (w.availabilityStatus.toUpperCase() == 'BUSY' ? 0.4 : 0.0);

    // --------------------
    // ✔ CREDENTIALS SCORE
    // --------------------
    final credScore = w.isVerified ? 1.0 : 0.0;

    // --------------------
    // ✔ FEE SCORE
    // --------------------
    final rate = w.hourlyRate;
    double feeScore = 0.5;

    if (rate >= input.budgetMin && rate <= input.budgetMax) {
      feeScore = 1.0;
    } else if (rate < input.budgetMin) {
      final diff = input.budgetMin - rate;
      feeScore = max(0.4, 1 - diff / max(input.budgetMin, 1));
    } else if (rate > input.budgetMax) {
      final diff = rate - input.budgetMax;
      feeScore = max(0.0, 1 - diff / max(input.budgetMax, 1));
    }

    // --------------------
    // ✔ TOTAL SCORE
    // --------------------
    final skillsWeighted = _w['skills']! * skillsScore;
    final performanceWeighted = _w['performance']! * perfScore;
    final availabilityWeighted = _w['availability']! * availabilityScore;
    final credentialsWeighted = _w['credentials']! * credScore;
    final locationWeighted = _w['location']! * locScore;
    final feeWeighted = _w['estimatedFee']! * feeScore;

    double total = skillsWeighted +
        performanceWeighted +
        availabilityWeighted +
        credentialsWeighted +
        locationWeighted +
        feeWeighted;

    total = total.clamp(0, 1);

    // --------------------
    // ✔ CONSOLE LOGGING FOR EACH FACTOR
    // --------------------
    debugPrint("\n📊 [${w.name}] Score Breakdown:");
    debugPrint(
        "  ┌─ Skills:       ${skillsScore.toStringAsFixed(3)} × ${_w['skills']} = ${skillsWeighted.toStringAsFixed(3)}");
    debugPrint(
        "  ├─ Performance:  ${perfScore.toStringAsFixed(3)} × ${_w['performance']} = ${performanceWeighted.toStringAsFixed(3)}");
    debugPrint(
        "  │  └─ (Jobs Done: ${w.completedJobs}/${maxJobs}, Rating: ${w.averageRating.toStringAsFixed(1)}/5.0)");
    debugPrint(
        "  ├─ Availability: ${availabilityScore.toStringAsFixed(3)} × ${_w['availability']} = ${availabilityWeighted.toStringAsFixed(3)}");
    debugPrint(
        "  ├─ Credentials:  ${credScore.toStringAsFixed(3)} × ${_w['credentials']} = ${credentialsWeighted.toStringAsFixed(3)}");
    debugPrint(
        "  ├─ Location:     ${locScore.toStringAsFixed(3)} × ${_w['location']} = ${locationWeighted.toStringAsFixed(3)}");
    debugPrint(
        "  │  └─ Distance: ${d?.toStringAsFixed(2) ?? 'N/A'} km (Nearest: ${nearest?.toStringAsFixed(2) ?? 'N/A'} km)");
    debugPrint(
        "  ├─ Fee:          ${feeScore.toStringAsFixed(3)} × ${_w['estimatedFee']} = ${feeWeighted.toStringAsFixed(3)}");
    debugPrint(
        "  │  └─ Hourly Rate: ₱${rate.toStringAsFixed(0)} (Budget: ₱${input.budgetMin}-₱${input.budgetMax})");
    debugPrint("  └─ TOTAL SCORE:  ${total.toStringAsFixed(4)}");
    debugPrint("");

    // --------------------
    // ✔ ESTIMATE TIME
    // --------------------
    final eta = (d != null) ? (d / (input.isUrgent ? 35 : 25)) * 60 : null;

    return RankedProvider(
      worker: w,
      totalScore: double.parse(total.toStringAsFixed(4)),
      breakdown: MatchScoreBreakdown(
        skills: skillsScore,
        performance: perfScore,
        availability: availabilityScore,
        credentials: credScore,
        location: locScore,
        estimatedFee: feeScore,
      ),
      distanceKm: d,
      matchedSkills: matches,
      etaMinutes: eta,
      notes: [
        if (rate >= input.budgetMin && rate <= input.budgetMax) 'Within budget',
        if (d != null && d < 3) 'Nearby',
        if (w.isVerified) 'Verified',
      ],
    );
  }

  // ------------------------------------------------------------
  // 🔵 UTILITIES
  // ------------------------------------------------------------
  static double? _distanceKm(
      double lat1, double lng1, double lat2, double lng2) {
    if (!_valid(lat1, lng1) || !_valid(lat2, lng2)) return null;

    const R = 6371.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_deg2rad(lat1)) *
            cos(_deg2rad(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  static double _deg2rad(double d) => d * pi / 180.0;
  static bool _valid(double lat, double lng) =>
      lat.abs() <= 90 && lng.abs() <= 180;
  static String _norm(String v) => v.toLowerCase().trim().replaceAll('-', '_');

  // ------------------------------------------------------------
  // 🔵 DEBUG OUTPUT TABLE (for adviser)
  // ------------------------------------------------------------
  static void _printDebugTable(List<RankedProvider> ranked, MatchInput input) {
    debugPrint("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    debugPrint("🎯 Results for '${input.serviceType}'");
    debugPrint("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");

    for (final r in ranked) {
      final w = r.worker;
      final b = r.breakdown;

      debugPrint("\n# ${w.name} (${w.userId})");
      debugPrint("Distance: ${r.distanceKm?.toStringAsFixed(2)} km");
      debugPrint("Rate: ₱${w.hourlyRate}");
      debugPrint("Rating: ${w.averageRating}");
      debugPrint("Jobs: ${w.completedJobs}");
      debugPrint("Verified: ${w.isVerified}");
      debugPrint("--- Scores ---");
      debugPrint(
          "Skills:       ${b.skills} × ${_w['skills']} = ${(b.skills * _w['skills']!).toStringAsFixed(3)}");
      debugPrint(
          "Performance:  ${b.performance} × ${_w['performance']} = ${(b.performance * _w['performance']!).toStringAsFixed(3)}");
      debugPrint(
          "Availability: ${b.availability} × ${_w['availability']} = ${(b.availability * _w['availability']!).toStringAsFixed(3)}");
      debugPrint(
          "Credentials:  ${b.credentials} × ${_w['credentials']} = ${(b.credentials * _w['credentials']!).toStringAsFixed(3)}");
      debugPrint(
          "Location:     ${b.location} × ${_w['location']} = ${(b.location * _w['location']!).toStringAsFixed(3)}");
      debugPrint(
          "Fee:          ${b.estimatedFee} × ${_w['estimatedFee']} = ${(b.estimatedFee * _w['estimatedFee']!).toStringAsFixed(3)}");
      debugPrint("TOTAL SCORE:  ${r.totalScore}");
    }

    debugPrint("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
  }
}
