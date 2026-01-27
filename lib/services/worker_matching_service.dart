import 'package:supabase_flutter/supabase_flutter.dart';

class WorkerMatchingService {
  static final client = Supabase.instance.client;

  static Future<List<Map<String, dynamic>>> matchWorkers({
    required String serviceType,
    required double clientLat,
    required double clientLng,
    required int minBudget,
    required int maxBudget,
    int limit = 10,
  }) async {
    final response = await client.rpc(
      'match_workers',
      params: {
        'p_service': serviceType,
        'p_client_lat': clientLat,
        'p_client_lng': clientLng,
        'p_budget_min': minBudget,
        'p_budget_max': maxBudget,
        'p_limit': limit,
      },
    );

    if (response == null) return [];

    return List<Map<String, dynamic>>.from(response);
  }
}
