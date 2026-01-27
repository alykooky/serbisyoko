import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static SupabaseClient? _client;
  static bool _isInitialized = false;
  static bool _isInitializing = false;

  /// Lazily obtain the Supabase client.
  static SupabaseClient get client {
    if (!_isInitialized && !_isInitializing) {
      _initializeSupabase();
    }
    return _client ?? Supabase.instance.client;
  }

  static bool get isReady => _isInitialized;

  /// Ensure Supabase is ready before use.
  static Future<void> ensureInitialized() async {
    if (_isInitialized) return;

    if (_isInitializing) {
      while (_isInitializing) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      return;
    }

    await _initializeSupabase();
  }

  /// Initialize Supabase ONE TIME only.
  static Future<void> _initializeSupabase() async {
    if (_isInitialized || _isInitializing) return;

    _isInitializing = true;

    try {
      await Supabase.initialize(
        url: 'https://jfglfvvbmqxsmbqetugk.supabase.co',
        anonKey:
            'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpmZ2xmdnZibXF4c21icWV0dWdrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDk1NTE3ODgsImV4cCI6MjA2NTEyNzc4OH0.FmpK6IK3-slZMKKHDZ42LZ4RFn8qh5oD0vtEgJn1wVs',
      );

      _client = Supabase.instance.client;
      _isInitialized = true;
      debugPrint('[SupabaseService] Supabase initialized');
    } catch (error) {
      debugPrint('[SupabaseService] Initialization failed: $error');
    } finally {
      _isInitializing = false;
    }
  }

  // =======================================================================
  // ✅ TRANS-ENCODING FUNCTION — PROPER LOCATION
  // =======================================================================
  static Future<void> transEncodeWorkerProfile(String workerId) async {
    final sb = Supabase.instance.client;

    // 1. Fetch worker profile
    final prof = await sb
        .from('worker_profiles')
        .select()
        .eq('user_id', workerId)
        .single();

    // 2. Fetch ratings
    final ratings =
        await sb.from('ratings').select('score').eq('worker_id', workerId);

    double avgRating = 0;
    if (ratings.isNotEmpty) {
      avgRating =
          ratings.map((e) => e['score'] as num).reduce((a, b) => a + b) /
              ratings.length;
    }

    // 3. Fetch completed jobs
    final jobs =
        await sb.from('bookings').select('status').eq('worker_id', workerId);

    int completed = jobs.where((j) => j['status'] == 'completed').length;

    // 4. Check verification
    final ver = await sb
        .from('verification_request')
        .select('status')
        .eq('worker_id', workerId)
        .maybeSingle();

    bool isVerified = ver != null && ver['status'] == 'approved';

    // 5. Update encoded / normalized fields
    await sb.from('worker_profiles').update({
      'average_rating': avgRating,
      'completed_jobs': completed,
      'total_jobs': jobs.length,
      'is_verified': isVerified,
      'availability_status':
          prof['availability_status'] ?? 'ON', // fallback for null
    }).eq('user_id', workerId);

    debugPrint("🔥 Worker $workerId has been trans-encoded successfully.");
  }
}
