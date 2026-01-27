class ServiceRequest {
  final String id;
  final String clientId;
  final String serviceType;
  final String description;
  final String location;
  final double latitude;
  final double longitude;
  final DateTime scheduledTime;
  final String status;
  final double? budgetMin;
  final double? budgetMax;

  ServiceRequest({
    required this.id,
    required this.clientId,
    required this.serviceType,
    required this.description,
    required this.location,
    required this.latitude,
    required this.longitude,
    required this.scheduledTime,
    required this.status,
    this.budgetMin,
    this.budgetMax,
  });

  factory ServiceRequest.fromJson(Map<String, dynamic> json) {
    return ServiceRequest(
      id: json['id'] ?? '',
      clientId: json['client_id'] ?? '',
      serviceType: json['service_type'] ?? '',
      description: json['description'] ?? '',
      location: json['location'] ?? '',
      latitude: (json['latitude'] ?? 0).toDouble(),
      longitude: (json['longitude'] ?? 0).toDouble(),
      scheduledTime:
          DateTime.tryParse(json['scheduled_time'] ?? '') ?? DateTime.now(),
      status: json['status'] ?? 'pending',
      budgetMin: json['budget_min'] != null
          ? double.tryParse(json['budget_min'].toString())
          : null,
      budgetMax: json['budget_max'] != null
          ? double.tryParse(json['budget_max'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'client_id': clientId,
        'service_type': serviceType,
        'description': description,
        'location': location,
        'latitude': latitude,
        'longitude': longitude,
        'scheduled_time': scheduledTime.toIso8601String(),
        'status': status,
        'budget_min': budgetMin,
        'budget_max': budgetMax,
      };
}
