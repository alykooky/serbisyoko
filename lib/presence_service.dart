// lib/presence_service.dart
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Light-weight online presence pinger.
/// - Writes to public.worker_status (user_id, is_available, last_seen)
/// - Call start() in your worker dashboard and stop() on dispose/sign out.
class PresenceService {
  PresenceService._();
  static final PresenceService instance = PresenceService._();

  Timer? _timer;
  bool _online = false;

  /// Begin 25s heartbeat. Call once when the worker opens their dashboard.
  Future<void> start({bool online = false}) async {
    _online = online;
    _timer?.cancel();
    await _tick(); // write immediately
    _timer = Timer.periodic(const Duration(seconds: 25), (_) => _tick());
  }

  /// End the heartbeat and mark offline.
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _online = false;
    await _tick();
  }

  /// Toggle online/offline and ping immediately.
  Future<void> setOnline(bool v) async {
    _online = v;
    await _tick();
  }

  Future<void> _tick() async {
    final sb = Supabase.instance.client;
    final u = sb.auth.currentUser;
    if (u == null) return;

    // Upsert on user_id; ensure worker_status has UNIQUE(user_id)
    await sb.from('worker_status').upsert({
      'user_id': u.id,
      'is_available': _online,
      'last_seen': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id');
  }
}
