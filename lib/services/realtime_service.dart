import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/worker_model.dart';
import '../models/worker_profile.dart';
import '../models/service_request.dart';

class RealtimeService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static RealtimeChannel? _workerChannel;
  static RealtimeChannel? _requestChannel;

  static final List<Function(WorkerProfile)> _workerUpdateCallbacks = [];
  static final List<Function(ServiceRequest)> _requestUpdateCallbacks = [];

  /// Initialize real-time subscriptions
  static Future<void> initializeRealtime() async {
    try {
      debugPrint('🔄 Initializing real-time services...');

      // Subscribe to worker profile updates
      _workerChannel = _supabase
          .channel('worker-updates')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'worker_profiles',
            callback: _handleWorkerUpdate,
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'worker_profiles',
            callback: _handleWorkerInsert,
          );

      // Subscribe to service request updates
      _requestChannel = _supabase
          .channel('request-updates')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'service_requests',
            callback: _handleRequestUpdate,
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'service_requests',
            callback: _handleRequestInsert,
          );

      _workerChannel?.subscribe();
      _requestChannel?.subscribe();

      debugPrint('✅ Real-time services initialized successfully');
    } catch (e) {
      debugPrint('❌ Error initializing real-time services: $e');
    }
  }

  /// Handle worker profile updates
  static void _handleWorkerUpdate(PostgresChangePayload payload) {
    try {
      final workerData = payload.newRecord;
      final worker = WorkerProfile.fromJson(workerData);

      debugPrint(
          '📡 Worker update received: ${worker.name} - ${worker.availabilityStatus}');

      // Notify all callbacks
      for (final callback in _workerUpdateCallbacks) {
        callback(worker);
      }
    } catch (e) {
      debugPrint('❌ Error handling worker update: $e');
    }
  }

  /// Handle new worker registrations
  static void _handleWorkerInsert(PostgresChangePayload payload) {
    try {
      final workerData = payload.newRecord;
      final worker = WorkerProfile.fromJson(workerData);

      debugPrint('📡 New worker registered: ${worker.name}');

      // Notify all callbacks
      for (final callback in _workerUpdateCallbacks) {
        callback(worker);
      }
    } catch (e) {
      debugPrint('❌ Error handling worker insert: $e');
    }
  }

  /// Handle service request updates
  static void _handleRequestUpdate(PostgresChangePayload payload) {
    try {
      final requestData = payload.newRecord;
      final request = ServiceRequest.fromJson(requestData);

      debugPrint(
          '📡 Service request update: ${request.id} - ${request.status}');

      // Notify all callbacks
      for (final callback in _requestUpdateCallbacks) {
        callback(request);
      }
    } catch (e) {
      debugPrint('❌ Error handling request update: $e');
    }
  }

  /// Handle new service requests
  static void _handleRequestInsert(PostgresChangePayload payload) {
    try {
      final requestData = payload.newRecord;
      final request = ServiceRequest.fromJson(requestData);

      debugPrint(
          '📡 New service request: ${request.id} - ${request.serviceType}');

      // Notify all callbacks
      for (final callback in _requestUpdateCallbacks) {
        callback(request);
      }
    } catch (e) {
      debugPrint('❌ Error handling request insert: $e');
    }
  }

  /// Subscribe to worker updates
  static void subscribeToWorkerUpdates(Function(WorkerProfile) callback) {
    _workerUpdateCallbacks.add(callback);
  }

  /// Subscribe to service request updates
  static void subscribeToRequestUpdates(Function(ServiceRequest) callback) {
    _requestUpdateCallbacks.add(callback);
  }

  /// Unsubscribe from worker updates
  static void unsubscribeFromWorkerUpdates(Function(WorkerProfile) callback) {
    _workerUpdateCallbacks.remove(callback);
  }

  /// Unsubscribe from request updates
  static void unsubscribeFromRequestUpdates(Function(ServiceRequest) callback) {
    _requestUpdateCallbacks.remove(callback);
  }

  /// Update worker availability status
  static Future<void> updateWorkerAvailability({
    required String workerId,
    required String status,
  }) async {
    try {
      await _supabase.from('worker_profiles').update({
        'availability_status': status,
        'last_seen': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', workerId);

      debugPrint('✅ Worker availability updated: $workerId -> $status');
    } catch (e) {
      debugPrint('❌ Error updating worker availability: $e');
    }
  }

  /// Update worker location
  static Future<void> updateWorkerLocation({
    required String workerId,
    required double latitude,
    required double longitude,
  }) async {
    try {
      await _supabase.from('worker_profiles').update({
        'latitude': latitude,
        'longitude': longitude,
        'last_seen': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', workerId);

      debugPrint('✅ Worker location updated: $workerId');
    } catch (e) {
      debugPrint('❌ Error updating worker location: $e');
    }
  }

  /// Create a new service request
  static Future<String?> createServiceRequest({
    required String clientId,
    required String clientName,
    required String serviceType,
    required String description,
    required double clientLatitude,
    required double clientLongitude,
    required String clientAddress,
    required DateTime preferredStartTime,
    required DateTime preferredEndTime,
    required double budgetMin,
    required double budgetMax,
    required bool isUrgent,
  }) async {
    try {
      final response = await _supabase
          .from('service_requests')
          .insert({
            'client_id': clientId,
            'client_name': clientName,
            'service_type': serviceType,
            'description': description,
            'client_latitude': clientLatitude,
            'client_longitude': clientLongitude,
            'client_address': clientAddress,
            'preferred_start_time': preferredStartTime.toIso8601String(),
            'preferred_end_time': preferredEndTime.toIso8601String(),
            'budget_min': budgetMin,
            'budget_max': budgetMax,
            'is_urgent': isUrgent,
            'status': 'pending',
            'created_at': DateTime.now().toIso8601String(),
          })
          .select('id')
          .single();

      final requestId = response['id'] as String;
      debugPrint('✅ Service request created: $requestId');
      return requestId;
    } catch (e) {
      debugPrint('❌ Error creating service request: $e');
      return null;
    }
  }

  /// Assign worker to service request
  static Future<void> assignWorkerToRequest({
    required String requestId,
    required String workerId,
  }) async {
    try {
      await _supabase.from('service_requests').update({
        'assigned_worker_id': workerId,
        'status': 'assigned',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', requestId);

      debugPrint('✅ Worker assigned to request: $workerId -> $requestId');
    } catch (e) {
      debugPrint('❌ Error assigning worker: $e');
    }
  }

  /// Clean up real-time subscriptions
  static Future<void> dispose() async {
    try {
      await _workerChannel?.unsubscribe();
      await _requestChannel?.unsubscribe();
      _workerUpdateCallbacks.clear();
      _requestUpdateCallbacks.clear();
      debugPrint('🧹 Real-time services disposed');
    } catch (e) {
      debugPrint('❌ Error disposing real-time services: $e');
    }
  }
}
