import 'dart:math';

class WorkerCandidate {
  final String userId;
  final String name;
  final List<String> skills; // normalized lower-case service names
  final double? lat;
  final double? lng;
  final double ratingAverage; // 0..5 (Performance part 1)
  final int jobsDone; // Performance part 2 (scaled)
  final bool isAvailable; // ON/OFF
  final bool isVerified; // Credentials
  final int? estimatedFee; // for requested job (lower is better)

  WorkerCandidate({
    required this.userId,
    required this.name,
    required this.skills,
    required this.lat,
    required this.lng,
    required this.ratingAverage,
    required this.jobsDone,
    required this.isAvailable,
    required this.isVerified,
    this.estimatedFee,
  });
}

class MatchResult {
  final WorkerCandidate worker;
  final double score; // 0..1

  MatchResult({required this.worker, required this.score});
}

// Haversine distance in kilometers
double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
  const double r = 6371.0;
  double dLat = _deg2rad(lat2 - lat1);
  double dLon = _deg2rad(lon2 - lon1);
  double a =
      sin(dLat / 2) * sin(dLat / 2) + cos(_deg2rad(lat1)) * cos(_deg2rad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
  double c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return r * c;
}

double _deg2rad(double deg) => deg * pi / 180.0;

List<MatchResult> rankWorkers({
  required List<WorkerCandidate> workers,
  required String requiredService,
  double? clientLat,
  double? clientLng,
}) {
  final String requiredSkill = requiredService.trim().toLowerCase();
  final List<MatchResult> results = [];

  for (final w in workers) {
    // Skills (w1 = 0.25)
    final bool skillMatch = w.skills.map((s) => s.toLowerCase()).contains(requiredSkill);
    final double skillScore = skillMatch ? 1.0 : 0.0;

    // Location (w5 = 0.15): 1.0 within 1km, 0.0 at 15km+, linear in between
    double distanceScore = 0.0;
    if (clientLat != null && clientLng != null && w.lat != null && w.lng != null) {
      final km = _distanceKm(clientLat, clientLng, w.lat!, w.lng!);
      if (km <= 1) distanceScore = 1.0;
      else if (km >= 15) distanceScore = 0.0;
      else distanceScore = (15 - km) / 14.0; // normalize
    }

    // Availability (w3 = 0.15)
    final double availabilityScore = w.isAvailable ? 1.0 : 0.0;

    // Performance (w2 = 0.20): rating and jobs done combined
    final double ratingScore = (w.ratingAverage).clamp(0.0, 5.0) / 5.0;
    // Scale jobsDone: 0 at 0 jobs, 1.0 at 50+ jobs
    final double jobsScore = (w.jobsDone >= 50) ? 1.0 : (w.jobsDone / 50.0).clamp(0.0, 1.0);
    final double performanceScore = (0.7 * ratingScore) + (0.3 * jobsScore);

    // Credentials (w4 = 0.15)
    final double credentialsScore = w.isVerified ? 1.0 : 0.0;

    // Estimated Fee (w6 = 0.10): lower fee is better. Normalize relative to peers.
    double feeScore = 0.5; // neutral default if unknown for many
    final fees = workers.map((x) => x.estimatedFee).whereType<int>().toList();
    if (w.estimatedFee != null && fees.isNotEmpty) {
      final minFee = fees.reduce(min);
      final maxFee = fees.reduce(max);
      if (maxFee == minFee) {
        feeScore = 1.0; // all equal
      } else {
        // Lower fee -> closer to 1
        feeScore = 1.0 - ((w.estimatedFee! - minFee) / (maxFee - minFee));
        feeScore = feeScore.clamp(0.0, 1.0);
      }
    }

    // Weighted sum
    final double score = (
      0.25 * skillScore +
      0.20 * performanceScore +
      0.15 * availabilityScore +
      0.15 * credentialsScore +
      0.15 * distanceScore +
      0.10 * feeScore
    );

    if (skillScore > 0) {
      results.add(MatchResult(worker: w, score: double.parse(score.toStringAsFixed(4))));
    }
  }

  results.sort((a, b) => b.score.compareTo(a.score));
  return results;
}


