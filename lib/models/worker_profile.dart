class WorkerProfile {
  final String id;
  final String userId;

  final String name;
  final String email;
  final String phone;

  final String address;
  final double latitude;
  final double longitude;

  final double hourlyRate;
  final bool isVerified;
  final String verificationStatus;

  final String availabilityStatus;
  final DateTime? lastSeen;

  final DateTime createdAt;
  final DateTime updatedAt;

  final String? profileImage;
  final String? bio;

  List<String> skills; // Always populated (never null)
  double averageRating; // Defaults to 0
  int totalJobs; // Defaults to 0
  int completedJobs; // Defaults to 0
  bool isCurrentlyAvailable; // Dynamically checked based on schedule

  WorkerProfile({
    required this.id,
    required this.userId,
    required this.name,
    required this.email,
    required this.phone,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.hourlyRate,
    required this.isVerified,
    required this.verificationStatus,
    required this.availabilityStatus,
    required this.createdAt,
    required this.updatedAt,
    required this.skills,
    required this.averageRating,
    required this.totalJobs,
    required this.completedJobs,
    this.lastSeen,
    this.profileImage,
    this.bio,
    this.isCurrentlyAvailable = true, // Default to true, will be checked dynamically
  });

  factory WorkerProfile.fromJson(Map<String, dynamic> json) {
    // Safe number parsing
    double safeDouble(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0;
    }

    int safeInt(dynamic v) {
      if (v == null) return 0;
      if (v is int) return v;
      return int.tryParse(v.toString()) ?? 0;
    }

    // Skills normalization
    List<String> parseSkills(dynamic raw) {
      if (raw == null) return [];
      if (raw is List) {
        return raw.map((s) => s.toString().trim()).toList();
      }
      if (raw is String && raw.contains(",")) {
        return raw.split(",").map((s) => s.trim()).toList();
      }
      return [];
    }

    return WorkerProfile(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',

      name: json['display_name'] ??
          json['full_name'] ??
          json['name'] ??
          'Unnamed Worker',

      email: json['email']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      address: json['address']?.toString() ?? '',

      // FIXED: Latitude / longitude unified encoding
      latitude: safeDouble(json['latitude'] ?? json['lat']),
      longitude: safeDouble(json['longitude'] ?? json['lng']),

      hourlyRate: safeDouble(json['hourly_rate']),
      isVerified: json['is_verified'] == true,

      // FIXED: Proper fallback for verification status
      verificationStatus: json['verification_status'] ??
          (json['is_verified'] == true ? 'verified' : 'unverified'),

      // FIXED: Unified availability
      availabilityStatus: json['availability_status']?.toString() ?? 'OFF',

      lastSeen: json['last_seen'] != null
          ? DateTime.tryParse(json['last_seen'].toString())
          : null,

      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] ?? '') ?? DateTime.now(),

      profileImage: json['profile_image'],
      bio: json['bio'],

      // FIXED: Always returns a list (never null)
      skills: parseSkills(json['skills']),

      // FIXED: Ratings & Jobs fallbacks
      averageRating: safeDouble(json['average_rating']),
      totalJobs: safeInt(json['total_jobs']),
      completedJobs: safeInt(json['completed_jobs']),
      
      // Default to true, will be checked dynamically based on schedule
      isCurrentlyAvailable: true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'name': name,
        'email': email,
        'phone': phone,
        'address': address,
        'latitude': latitude,
        'longitude': longitude,
        'hourly_rate': hourlyRate,
        'is_verified': isVerified,
        'verification_status': verificationStatus,
        'availability_status': availabilityStatus,
        'last_seen': lastSeen?.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'profile_image': profileImage,
        'bio': bio,
        'skills': skills,
        'average_rating': averageRating,
        'total_jobs': totalJobs,
        'completed_jobs': completedJobs,
      };
}
