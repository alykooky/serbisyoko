import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class JobApplicationService {
  static SupabaseClient get _sb => Supabase.instance.client;

  /// Worker applies to a service request
  static Future<void> applyToRequest({
    required String requestId,
    required String workerId,
    double? rateOffer,
    String? note,
  }) async {
    await _sb.from('job_applications').upsert({
      'request_id': requestId,
      'worker_id': workerId,
      'rate_offer': rateOffer,
      'note': note,
      // status defaults to 'pending'
    });

    // Send notification to client
    try {
      // Get service request to find client
      final request = await _sb
          .from('service_requests')
          .select('user_id, service_type')
          .eq('id', requestId)
          .maybeSingle();

      if (request != null) {
        final clientId = request['user_id']?.toString();
        final serviceType = request['service_type']?.toString() ?? 'service';

        if (clientId != null) {
          // Import NotificationService dynamically to avoid circular dependency
          // For now, we'll create notification directly
          await _sb.from('notifications').insert({
            'user_id': clientId,
            'type': 'new_application',
            'title': 'New Application Received',
            'message': 'A worker has applied to your "$serviceType" job post.',
            'related_id': requestId,
            'related_type': 'request',
            'is_read': false,
          });
        }
      }
    } catch (e) {
      debugPrint('Error sending application notification: $e');
      // Don't fail the application if notification fails
    }
  }

  /// Worker views open service requests they can apply to (filtered by their skills)
  static Future<List<Map<String, dynamic>>> fetchOpenRequests({
    String? workerId,
  }) async {
    debugPrint('🔍 fetchOpenRequests called with workerId: $workerId');
    
    // Fetch all open service requests first
    final allRequests = await _sb
        .from('service_requests')
        .select(
            'id, user_id, service_type, description, location, budget_min, budget_max, latitude, longitude, preferred_date, status')
        .eq('status', 'open')
        .order('preferred_date', ascending: true);

    debugPrint('📋 Found ${allRequests.length} total open service requests');

    if (allRequests.isEmpty) {
      debugPrint('⚠️ No open service requests found');
      return [];
    }

    // If no workerId, return all requests (for testing/admin)
    if (workerId == null) {
      debugPrint('ℹ️ No workerId provided, returning all requests');
      return (allRequests as List).map((e) => Map<String, dynamic>.from(e)).toList();
    }

    // Get worker's skills/services
    List<String> workerServiceNames = [];
    try {
      // Try service_id first (from schema)
      List<dynamic> workerSkills = [];
      try {
        workerSkills = await _sb
            .from('worker_skills')
            .select('service_id')
            .eq('worker_id', workerId);
        debugPrint('   Using service_id column');
      } catch (e) {
        debugPrint('   service_id failed, trying skill_id: $e');
        try {
          workerSkills = await _sb
              .from('worker_skills')
              .select('skill_id')
              .eq('worker_id', workerId);
          debugPrint('   Using skill_id column');
        } catch (e2) {
          debugPrint('❌ Both columns failed: $e2');
        }
      }

      debugPrint('👷 Worker has ${workerSkills.length} skills/services');

      if (workerSkills.isNotEmpty) {
        // Extract service/skill IDs
        final serviceIds = workerSkills
            .map((ws) => (ws['service_id'] ?? ws['skill_id'])?.toString())
            .where((id) => id != null && id.isNotEmpty)
            .toSet()
            .toList();

        debugPrint('   Service IDs: $serviceIds');

        if (serviceIds.isNotEmpty) {
          // Get service names from services table
          final services = await _sb
              .from('services')
              .select('name, category')
              .inFilter('id', serviceIds);

          workerServiceNames = services
              .map((s) => [
                    s['name']?.toString(),
                    s['category']?.toString(),
                  ])
              .expand((list) => list)
              .where((name) => name != null && name.isNotEmpty)
              .cast<String>()
              .toList();

          debugPrint('   Worker service names: $workerServiceNames');
        }
      }
    } catch (e) {
      debugPrint('❌ Error fetching worker skills: $e');
      // If we can't get worker skills, return all requests (lenient fallback)
      debugPrint('   Returning all requests as fallback');
      return (allRequests as List).map((e) => Map<String, dynamic>.from(e)).toList();
    }

    // If worker has no skills, show all requests (let them see everything)
    // This is more lenient - workers can apply to any job
    if (workerServiceNames.isEmpty) {
      debugPrint('⚠️ Worker has no skills configured, showing all requests');
      return (allRequests as List).map((e) => Map<String, dynamic>.from(e)).toList();
    }

    // Filter requests by matching service_type with worker's skills
    final matchingRequests = <Map<String, dynamic>>[];
    
    for (final request in allRequests) {
      final requestServiceType = (request['service_type']?.toString() ?? '').toLowerCase().trim();
      
      if (requestServiceType.isEmpty) {
        // Include requests with empty service type
        matchingRequests.add(Map<String, dynamic>.from(request));
        continue;
      }

      // Check if request service type matches any of worker's services
      // Use very flexible matching (partial, case-insensitive, word-based)
      final matches = workerServiceNames.any((workerService) {
        final wsLower = workerService.toLowerCase().trim();
        
        // Extract key words from both
        final requestWords = requestServiceType.split(RegExp(r'[\s\-_]+')).where((w) => w.length > 2).toList();
        final workerWords = wsLower.split(RegExp(r'[\s\-_]+')).where((w) => w.length > 2).toList();
        
        // Check exact match
        if (requestServiceType == wsLower) return true;
        
        // Check if one contains the other
        if (requestServiceType.contains(wsLower) || wsLower.contains(requestServiceType)) return true;
        
        // Check if any key words match
        if (requestWords.any((rw) => workerWords.any((ww) => rw == ww || rw.contains(ww) || ww.contains(rw)))) {
          return true;
        }
        
        return false;
      });

      if (matches) {
        matchingRequests.add(Map<String, dynamic>.from(request));
        debugPrint('   ✅ Match: "$requestServiceType" matches worker skills');
      } else {
        debugPrint('   ❌ No match: "$requestServiceType" (worker skills: $workerServiceNames)');
      }
    }

    debugPrint('✅ Worker has ${workerServiceNames.length} skills, found ${matchingRequests.length} matching jobs out of ${allRequests.length} total');
    
    // If no matches found but worker has skills, show all requests anyway (very lenient)
    // This ensures workers can always see and apply to jobs
    if (matchingRequests.isEmpty && workerServiceNames.isNotEmpty) {
      debugPrint('⚠️ No matches found, but showing all requests anyway (lenient mode)');
      return (allRequests as List).map((e) => Map<String, dynamic>.from(e)).toList();
    }
    
    return matchingRequests;
  }

  /// Client views applicants for a given request
  static Future<List<Map<String, dynamic>>> fetchApplicantsForRequest(
      String requestId) async {
    try {
      // Fetch job applications
      final apps = await _sb
          .from('job_applications')
          .select('id, worker_id, rate_offer, note, status, created_at')
          .eq('request_id', requestId)
          .order('created_at', ascending: true);

      if (apps.isEmpty) return [];

      // Extract worker IDs
      final workerIds = apps
          .map((app) => app['worker_id']?.toString())
          .where((id) => id != null && id.isNotEmpty)
          .toSet()
          .toList();

      if (workerIds.isEmpty) {
        return (apps as List).map((e) => Map<String, dynamic>.from(e)).toList();
      }

      // Fetch worker profiles separately
      List<dynamic> profiles = [];
      try {
        profiles = await _sb
            .from('worker_profiles')
            .select('user_id, hourly_rate, is_verified')
            .inFilter('user_id', workerIds);
      } catch (e) {
        debugPrint('Error fetching worker profiles: $e');
      }

      // Fetch user names
      List<dynamic> users = [];
      try {
        users = await _sb
            .from('users')
            .select('id, name')
            .inFilter('id', workerIds);
      } catch (e) {
        debugPrint('Error fetching users: $e');
      }

    // Create lookup maps
    final profileMap = <String, Map<String, dynamic>>{};
    for (final profile in profiles) {
      profileMap[profile['user_id'].toString()] = Map<String, dynamic>.from(profile);
    }

    final userMap = <String, Map<String, dynamic>>{};
    for (final user in users) {
      userMap[user['id'].toString()] = Map<String, dynamic>.from(user);
    }

    // Fetch ratings for average rating calculation
    List<dynamic> ratings = [];
    try {
      ratings = await _sb
          .from('ratings')
          .select('worker_id, score')
          .inFilter('worker_id', workerIds);
    } catch (e) {
      debugPrint('Error fetching ratings: $e');
    }

      final ratingMap = <String, List<int>>{};
      final jobCountMap = <String, int>{};
      for (final rating in ratings) {
        final workerId = rating['worker_id']?.toString();
        final score = rating['score'] as int?;
        if (score != null && workerId != null) {
          (ratingMap[workerId] ??= []).add(score);
          jobCountMap[workerId] = (jobCountMap[workerId] ?? 0) + 1;
        }
      }

      // Merge data
      final result = <Map<String, dynamic>>[];
      for (final app in apps) {
        final workerId = app['worker_id']?.toString();
        if (workerId == null) continue;

        final profile = profileMap[workerId] ?? {};
        final user = userMap[workerId] ?? {};
        final scores = ratingMap[workerId] ?? [];
        final avgRating = scores.isEmpty
            ? 0.0
            : scores.reduce((a, b) => a + b) / scores.length.toDouble();
        final completedJobs = jobCountMap[workerId] ?? 0;

        result.add({
          ...app,
          'worker_profiles': {
            'display_name': user['name'] ?? 'Unnamed Worker',
            'hourly_rate': profile['hourly_rate'] ?? 0,
            'is_verified': profile['is_verified'] ?? false,
            'average_rating': avgRating,
            'completed_jobs': completedJobs,
          },
        });
      }

      return result;
    } catch (e) {
      debugPrint('Error in fetchApplicantsForRequest: $e');
      rethrow;
    }
  }
}
