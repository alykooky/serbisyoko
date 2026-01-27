import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MatchingService {
  static final SupabaseClient _sb = Supabase.instance.client;

  /// Weights based on your paper (w1..w6)
  static const Map<String, double> _weights = {
    'skills': 0.25,
    'performance': 0.20,
    'availability': 0.15,
    'credentials': 0.15,
    'location': 0.15,
    'estimated_fee': 0.10,
  };

  /// Calls Supabase `rpc('match_workers', ...)` and returns ranked matches.
  /// Service naming:
  ///   - pass `'any'` to match any skill
  static Future<List<Map<String, dynamic>>> findBestMatches({
    required double clientLatitude,
    required double clientLongitude,
    required String serviceType, // e.g. 'Plumber', 'Electrician', or 'any'
    required double budgetMin,
    required double budgetMax,
    int limit = 10,
  }) async {
    try {
      final params = {
        'p_service': (serviceType.isEmpty) ? 'any' : serviceType,
        'p_client_lat': clientLatitude,
        'p_client_lng': clientLongitude,
        'p_budget_min': budgetMin.round(),
        'p_budget_max': budgetMax.round(),
        'p_limit': limit,
      };

      final result = await _sb.rpc('match_workers', params: params);

      // Expecting a List of rows
      final rows = (result as List<dynamic>).cast<Map<String, dynamic>>();

      // Normalize each row + compute total_score if missing
      final matches = rows.map((row) {
        // From SQL we expect: worker_id, worker_name, service?, skills[],
        // distance_km, hourly_rate, is_verified, availability_status,
        // (optional) scores jsonb, (optional) total_score
        final scores = _ensureScoresJson(row, budgetMin, budgetMax);
        final total = row['total_score'] is num
            ? (row['total_score'] as num).toDouble()
            : _weightedTotal(scores);

        return {
          'worker': {
            'id': row['worker_id'],
            'name': row['worker_name'] ?? 'Unknown',
            'service': row['service'],
            'skills': row['skills'],
            'is_verified': row['is_verified'] ?? false,
            'availability_status': row['availability_status'] ?? 'unavailable',
          },
          'hourly_rate': _toDouble(row['hourly_rate']),
          'distance_km': _toDouble(row['distance_km']),
          'scores': scores,
          'total_score': total,
        };
      }).toList();

      // Sort by total_score desc, then tie-breakers
      matches.sort((a, b) {
        final t =
            (b['total_score'] as double).compareTo(a['total_score'] as double);
        if (t != 0) return t;
        final d =
            (a['distance_km'] as double).compareTo(b['distance_km'] as double);
        if (d != 0) return d;
        final ra = _toDouble(a['hourly_rate']);
        final rb = _toDouble(b['hourly_rate']);
        return ra.compareTo(rb); // cheaper wins
      });

      return matches;
    } catch (e, st) {
      debugPrint('❌ match_workers rpc failed: $e\n$st');
      rethrow;
    }
  }

  /// If the SQL already returned scores jsonb, keep it.
  /// If not, approximate scores client-side so total still works.
  static Map<String, double> _ensureScoresJson(
      Map<String, dynamic> row, double budgetMin, double budgetMax) {
    if (row['scores'] is Map<String, dynamic>) {
      // Convert values to double
      final m = <String, double>{};
      (row['scores'] as Map<String, dynamic>).forEach((k, v) {
        if (v is num) m[k] = v.toDouble();
      });
      return m;
    }

    // Build a reasonable fallback using the returned fields.
    final distanceKm = _toDouble(row['distance_km']);
    final rate = _toDouble(row['hourly_rate']);
    final isAvail =
        (row['availability_status']?.toString().toLowerCase() == 'available');
    final isVerified = (row['is_verified'] == true);

    // Location score (nearer = higher)
    final loc = (distanceKm <= 1)
        ? 1.0
        : (distanceKm <= 3)
            ? 0.8
            : (distanceKm <= 5)
                ? 0.6
                : (distanceKm <= 10)
                    ? 0.4
                    : 0.2;

    // Fee score (within budget center is best)
    final center = (budgetMin + budgetMax) / 2;
    final span = (budgetMax - budgetMin).abs().clamp(1, 999999).toDouble();
    final diff = (rate - center).abs();
    final fee = (diff <= span * 0.1)
        ? 1.0
        : (diff <= span * 0.2)
            ? 0.8
            : (diff <= span * 0.3)
                ? 0.6
                : (diff <= span * 0.5)
                    ? 0.4
                    : 0.2;

    // Availability & credentials approximations
    final avail = isAvail ? 1.0 : 0.0;
    final cred = isVerified ? 1.0 : 0.3;

    // We don’t have past jobs/rating here—give neutral baseline 0.6
    const perf = 0.6;

    // Skills presence (SQL already filtered), assume good = 1.0
    const skl = 1.0;

    return {
      'skills': skl,
      'performance': perf,
      'availability': avail,
      'credentials': cred,
      'location': loc,
      'estimated_fee': fee,
    };
  }

  static double _weightedTotal(Map<String, double> scores) {
    double t = 0;
    _weights.forEach((k, w) {
      t += (scores[k] ?? 0.0) * w;
    });
    return t.clamp(0.0, 1.0);
  }

  static double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  // Optional: if you ever need haversine distance locally
  static double haversine(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    double dLat = _deg2rad(lat2 - lat1);
    double dLon = _deg2rad(lon2 - lon1);
    double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return r * 2.0 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _deg2rad(double d) => d * (math.pi / 180.0);
}
