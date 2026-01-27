// lib/worker_availability_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'presence_service.dart';

/// Expected table (weekly-first design; date is optional future):
/// public.worker_availability (you already created columns)
///   id uuid pk default gen_random_uuid()
///   user_id uuid not null
///   weekday int check(weekday between 1 and 7)  -- nullable if you add date rows
///   date date                                   -- nullable (for one-off days)
///   start_time time not null
///   end_time time not null
///   is_recurring boolean default true           -- optional
///   is_active boolean not null default true
///   created_at timestamptz default now()
/// Unique index you actually have (pick one and keep onConflict in code aligned):
///   unique(user_id, weekday)                         -- one row per weekday
///   -- or unique(user_id, weekday, start_time)       -- multiple slots per weekday
///   -- and for date rows: unique(user_id, date, start_time)

class WorkerAvailabilityScreen extends StatefulWidget {
  const WorkerAvailabilityScreen({super.key});

  @override
  State<WorkerAvailabilityScreen> createState() =>
      _WorkerAvailabilityScreenState();
}

class _WorkerAvailabilityScreenState extends State<WorkerAvailabilityScreen> {
  final sb = Supabase.instance.client;

  bool _loading = true;
  bool _online = false;

  // Map weekday(1..7) -> {id, start, end, is_active}
  final Map<int, Map<String, dynamic>> _rows = {
    for (var d = 1; d <= 7; d++)
      d: {
        'id': null,
        'start': const TimeOfDay(hour: 9, minute: 0),
        'end': const TimeOfDay(hour: 17, minute: 0),
        'is_active': false,
      }
  };

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final u = sb.auth.currentUser;
      if (u == null) throw 'Not signed in';

      // presence (worker_status)
      final ws = await sb
          .from('worker_status')
          .select('is_available')
          .eq('user_id', u.id)
          .maybeSingle();
      _online = (ws?['is_available'] == true);

      // availability rows
      final rows = await sb
          .from('worker_availability')
          .select('id, weekday, start_at, end_at, is_active')
          .eq('user_id', u.id)
          .order('weekday');

      for (final r in rows) {
        final wd = (r['weekday'] as int);
        final start = _parseTimeOfDay(r['start_at']);
        final end = _parseTimeOfDay(r['end_at']);
        _rows[wd] = {
          'id': r['id'],
          'start': start,
          'end': end,
          'is_active': r['is_active'] == true,
        };
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  TimeOfDay _parseTimeOfDay(dynamic v) {
    if (v == null) return const TimeOfDay(hour: 9, minute: 0);
    final s = v.toString();
    final parts = s.split(':');
    final h = int.tryParse(parts[0]) ?? 9;
    final m = int.tryParse(parts[1]) ?? 0;
    return TimeOfDay(hour: h, minute: m);
  }

  Future<void> _pickTime(int wd, String key) async {
    final initial = _rows[wd]![key] as TimeOfDay;
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (picked != null) {
      setState(() => _rows[wd]![key] = picked);
    }
  }

  String _fmt(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// Generic saver that builds the exact payload and handles insert/update
  /// Uses delete-and-insert strategy to avoid trigger issues
  Future<void> _saveRow({
    required String userId,
    required int weekday, // weekly mode
    DateTime? date,       // optional one-off future support
    required TimeOfDay start,
    required TimeOfDay end,
    required bool isActive,
    String? existingId,   // If row exists, we have the ID
  }) async {
    // Build strings
    String two(int n) => n.toString().padLeft(2, '0');
    final startTimeStr = '${two(start.hour)}:${two(start.minute)}:00';
    final endTimeStr = '${two(end.hour)}:${two(end.minute)}:00';

    // Prepare payload (only columns that exist in your table)
    // DO NOT include any timestamp fields to avoid trigger issues
    final payload = <String, dynamic>{
      'user_id': userId,
      'weekday': weekday,
      'start_at': startTimeStr,
      'end_at': endTimeStr,
      'is_active': isActive,
    };

    try {
      // Strategy: Delete existing row if it exists, then insert fresh
      // This avoids update triggers that might expect updated_at
      
      // First, check if row exists (by user_id and weekday)
      final existing = await sb
          .from('worker_availability')
          .select('id')
          .eq('user_id', userId)
          .eq('weekday', weekday)
          .maybeSingle();

      // Delete existing row if found
      if (existing != null && existing['id'] != null) {
        await sb
            .from('worker_availability')
            .delete()
            .eq('id', existing['id']);
      }

      // Insert new row (this will be a fresh insert, avoiding update triggers)
      // Only insert if isActive is true OR if we had an existing row (to preserve settings)
      if (isActive || existing != null) {
        await sb.from('worker_availability').insert(payload);
      }
      
    } catch (e) {
      debugPrint('❌ Error saving availability row for weekday $weekday: $e');
      debugPrint('   Payload: $payload');
      // Re-throw with more context
      throw Exception('Failed to save availability for weekday $weekday: $e');
    }
  }

  Future<void> _save() async {
    final u = sb.auth.currentUser;
    if (u == null) return;

    setState(() => _loading = true);
    try {
      // 1) Presence: updates worker_status (and bumps last_seen)
      await PresenceService.instance.setOnline(_online);

      // 2) Save all weekdays using the new generic saver
      // Save all days (even inactive) so users can easily reactivate them later
      final errors = <String>[];
      for (var wd = 1; wd <= 7; wd++) {
        try {
          final row = _rows[wd]!;
          final start = row['start'] as TimeOfDay;
          final end = row['end'] as TimeOfDay;
          final active = row['is_active'] == true;
          final existingId = row['id']?.toString();

          await _saveRow(
            userId: u.id,
            weekday: wd,
            start: start,
            end: end,
            isActive: active,
            existingId: existingId,
          );
        } catch (e) {
          final dayName = _days[wd - 1];
          errors.add('$dayName: $e');
          debugPrint('Error saving $dayName: $e');
        }
      }
      
      if (errors.isNotEmpty && mounted) {
        throw 'Failed to save some days: ${errors.join(", ")}';
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Availability saved')),
      );
    } catch (e) {
      if (!mounted) return;
      
      // Provide helpful error message
      String errorMessage = 'Save failed: $e';
      if (e.toString().contains('updated_at')) {
        errorMessage = 'Database error: Please run the SQL migration file "fix_worker_availability_table.sql" in your Supabase SQL Editor to fix this issue.';
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFED9121);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Availability'),
        backgroundColor: accent,
        foregroundColor: Colors.white,
        actions: [
          Switch(
            value: _online,
            activeColor: Colors.white,
            onChanged: (v) => setState(() => _online = v),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                const Text(
                  'Weekly schedule (local time)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                for (var wd = 1; wd <= 7; wd++) _row(wd),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Save'),
                ),
              ],
            ),
    );
  }

  Widget _row(int wd) {
    final name = _days[wd - 1];
    final row = _rows[wd]!;
    final active = row['is_active'] == true;
    final start = row['start'] as TimeOfDay;
    final end = row['end'] as TimeOfDay;

    return Card(
      child: ListTile(
        title: Text(name),
        subtitle: active
            ? Text('${_fmt(start)} – ${_fmt(end)}')
            : const Text('Not available'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: active ? () => _pickTime(wd, 'start') : null,
              child: const Text('Start'),
            ),
            TextButton(
              onPressed: active ? () => _pickTime(wd, 'end') : null,
              child: const Text('End'),
            ),
            Switch(
              value: active,
              onChanged: (v) => setState(() => _rows[wd]!['is_active'] = v),
            ),
          ],
        ),
      ),
    );
  }
}
