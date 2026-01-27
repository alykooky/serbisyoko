import 'package:latlong2/latlong.dart';

import 'worker_model.dart';
import 'worker_profile.dart';

/// Encapsulates the inputs needed to compute smart matches.
class MatchInput {
  MatchInput({
    required this.serviceType,
    required this.clientLat,
    required this.clientLng,
    required this.budgetMin,
    required this.budgetMax,
    required this.preferredStart,
    required this.preferredEnd,
    this.isUrgent = false,
    this.limit = 10,
    this.searchRadiusKm = 15,
  });

  final String serviceType;
  final double clientLat;
  final double clientLng;
  final double budgetMin;
  final double budgetMax;
  final DateTime preferredStart;
  final DateTime preferredEnd;
  final bool isUrgent;
  final int limit;
  final double searchRadiusKm;

  LatLng get clientPosition => LatLng(clientLat, clientLng);

  MatchInput copyWith({
    String? serviceType,
    double? clientLat,
    double? clientLng,
    double? budgetMin,
    double? budgetMax,
    DateTime? preferredStart,
    DateTime? preferredEnd,
    bool? isUrgent,
    int? limit,
    double? searchRadiusKm,
  }) {
    return MatchInput(
      serviceType: serviceType ?? this.serviceType,
      clientLat: clientLat ?? this.clientLat,
      clientLng: clientLng ?? this.clientLng,
      budgetMin: budgetMin ?? this.budgetMin,
      budgetMax: budgetMax ?? this.budgetMax,
      preferredStart: preferredStart ?? this.preferredStart,
      preferredEnd: preferredEnd ?? this.preferredEnd,
      isUrgent: isUrgent ?? this.isUrgent,
      limit: limit ?? this.limit,
      searchRadiusKm: searchRadiusKm ?? this.searchRadiusKm,
    );
  }
}

/// Holds the normalized scoring details for a ranked provider.
class MatchScoreBreakdown {
  MatchScoreBreakdown({
    required this.skills,
    required this.performance,
    required this.availability,
    required this.credentials,
    required this.location,
    required this.estimatedFee,
  });

  final double skills;
  final double performance;
  final double availability;
  final double credentials;
  final double location;
  final double estimatedFee;

  Map<String, double> toMap() => {
        'skills': skills,
        'performance': performance,
        'availability': availability,
        'credentials': credentials,
        'location': location,
        'estimatedFee': estimatedFee,
      };
}

/// A ranked provider with the computed total score and helper metadata.
class RankedProvider {
  final WorkerProfile worker;
  final double totalScore;
  final MatchScoreBreakdown breakdown;
  final double? distanceKm;
  final List<String> matchedSkills;
  final double? etaMinutes;
  final List<String> notes;

  RankedProvider({
    required this.worker,
    required this.totalScore,
    required this.breakdown,
    this.distanceKm,
    required this.matchedSkills,
    this.etaMinutes,
    required this.notes,
  });

  /// ✅ Converts this provider to a map for easy access in UI
  Map<String, dynamic> toMap() {
    return {
      'id': worker.userId, // Use userId for booking (references users.id)
      'workerId': worker.userId, // Also include as workerId for clarity
      'name': worker.name,
      'email': worker.email,
      'phone': worker.phone,
      'address': worker.address,
      'bio': worker.bio,
      'hourlyRate': worker.hourlyRate,
      'averageRating': worker.averageRating,
      'totalJobs': worker.totalJobs,
      'completedJobs': worker.completedJobs,
      'isVerified': worker.isVerified,
      'verificationStatus': worker.verificationStatus,
      'profileImage': worker.profileImage,
      'score': totalScore,
      'distance_km': distanceKm,
      'matchedSkills': matchedSkills,
      'eta_minutes': etaMinutes,
      'notes': notes,
      'estimatedFee': worker.hourlyRate,
      'breakdown': {
        'skills': breakdown.skills,
        'performance': breakdown.performance,
        'availability': breakdown.availability,
        'credentials': breakdown.credentials,
        'location': breakdown.location,
        'estimatedFee': breakdown.estimatedFee,
      },
    };
  }
}
