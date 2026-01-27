import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'provider_profile.dart';

class AvailableProvidersScreen extends StatefulWidget {
  final String? serviceName; // ✅ allow passing skill/service filter

  const AvailableProvidersScreen({super.key, this.serviceName});

  @override
  State<AvailableProvidersScreen> createState() =>
      _AvailableProvidersScreenState();
}

class _AvailableProvidersScreenState extends State<AvailableProvidersScreen> {
  final supa = Supabase.instance.client;

  final Map<String, Map<String, dynamic>> _userById = {};
  final Map<String, Map<String, dynamic>> _profileById = {};
  final Map<String, List<Map<String, dynamic>>> _availById = {};

  List<String> _availableIds = [];
  List<String> _skillMatchedIds = [];

  Stream<List<Map<String, dynamic>>> _statusStream() {
    return supa
        .from('worker_status')
        .stream(primaryKey: ['user_id']).eq('is_available', true);
  }

  Future<void> _fetchDetailsFor(List<String> ids) async {
    if (ids.isEmpty) return;

    final users = await supa
        .from('users')
        .select('id, first_name, last_name, name, email')
        .inFilter('id', ids);

    final profiles = await supa
        .from('worker_profiles')
        .select(
            'user_id, hourly_rate, service_area, availability_status, is_verified, latitude, longitude')
        .inFilter('user_id', ids);

    List<dynamic> av = [];
    try {
      av = await supa
          .from('worker_availability')
          .select(
              'user_id, weekday, start_at, start_time, end_at, end_time, is_active')
          .inFilter('user_id', ids);
    } catch (_) {
      av = const [];
    }

    final u = <String, Map<String, dynamic>>{};
    for (final r in users) {
      u[r['id'] as String] = Map<String, dynamic>.from(r);
    }

    final p = <String, Map<String, dynamic>>{};
    for (final r in profiles) {
      p[r['user_id'] as String] = Map<String, dynamic>.from(r);
    }

    final a = <String, List<Map<String, dynamic>>>{};
    for (final r in av) {
      final uid = r['user_id'] as String?;
      if (uid == null) continue;
      (a[uid] ??= []).add(Map<String, dynamic>.from(r));
    }

    if (!mounted) return;
    setState(() {
      _userById.addAll(u);
      _profileById.addAll(p);
      _availById.addAll(a);
    });
  }

  bool _isNowInsideAnySlot(String userId) {
    final slots = _availById[userId];
    if (slots == null || slots.isEmpty) return true;

    final now = DateTime.now();
    final today = now.weekday;
    final yesterday = (today == 1) ? 7 : today - 1;

    int _secs(String hhmmss) {
      final p = hhmmss.split(':');
      final h = int.tryParse(p.elementAt(0)) ?? 0;
      final m = int.tryParse(p.elementAt(1)) ?? 0;
      final s = int.tryParse(p.elementAt(2)) ?? 0;
      return h * 3600 + m * 60 + s;
    }

    final nowSecs = now.hour * 3600 + now.minute * 60 + now.second;

    for (final s in slots) {
      if (s['is_active'] != true) continue;

      final startStr =
          (s['start_at'] ?? s['start_time'] ?? '00:00:00').toString();
      final endStr = (s['end_at'] ?? s['end_time'] ?? '23:59:59').toString();
      final wd = s['weekday'] as int?;
      if (wd == null) continue;

      final startSecs = _secs(startStr);
      final endSecs = _secs(endStr);

      if (wd == today && startSecs <= endSecs) {
        if (nowSecs >= startSecs && nowSecs < endSecs) return true;
      }

      if (startSecs > endSecs) {
        if (wd == today && nowSecs >= startSecs) return true;
        if (wd == yesterday && nowSecs < endSecs) return true;
      }
    }
    return false;
  }

  /// ✅ Fetch worker IDs that have the selected skill
  Future<void> _fetchSkillMatches() async {
    if (widget.serviceName == null) return;

    try {
      final result = await supa
          .from('worker_skills')
          .select('worker_id, skills(name)')
          .eq('skills.name', widget.serviceName!);

      final ids = (result as List)
          .map((r) => r['worker_id'] as String)
          .whereType<String>()
          .toList();

      setState(() => _skillMatchedIds = ids);
    } catch (e) {
      debugPrint('Error fetching skill matches: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchSkillMatches();
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFED9121);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.serviceName ?? 'Available Providers'),
        backgroundColor: accent,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _statusStream(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }

          final raw = snap.data ?? const [];
          final cutoff = DateTime.now().subtract(const Duration(minutes: 2));

          var rows = raw.where((r) {
            final s = r['last_seen'] as String?;
            if (s == null) return false;
            try {
              final seen = DateTime.parse(s);
              return seen.isAfter(cutoff);
            } catch (_) {
              return false;
            }
          }).toList();

          // online + skill match
          var ids = rows.map((r) => r['user_id'] as String).toList();

          // If skill filter applied, intersect with matched workers
          if (widget.serviceName != null && _skillMatchedIds.isNotEmpty) {
            ids = ids.where((id) => _skillMatchedIds.contains(id)).toList();
          }

          // if skill filter applied but no matches yet
          if (widget.serviceName != null &&
              _skillMatchedIds.isEmpty &&
              snap.connectionState == ConnectionState.active) {
            return const Center(child: Text('No workers with this skill.'));
          }

          // refetch profile data
          if (ids.toSet().difference(_availableIds.toSet()).isNotEmpty ||
              _availableIds.toSet().difference(ids.toSet()).isNotEmpty) {
            _availableIds = ids;
            unawaited(_fetchDetailsFor(ids));
          }

          ids = ids.where(_isNowInsideAnySlot).toList();

          if (ids.isEmpty) {
            return const Center(
                child: Text('No providers matched your criteria.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: ids.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final id = ids[i];
              final user = _userById[id];
              final prof = _profileById[id];

              final name =
                  user?['first_name'] != null && user?['last_name'] != null
                      ? "${user!['first_name']} ${user['last_name']}"
                      : (user?['name'] ?? 'Worker');
              final rate = prof?['hourly_rate'] ?? 0;
              final area = prof?['service_area'] ?? '—';

              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(name),
                subtitle: Text('₱$rate / hr • $area'),
                trailing: const Chip(
                  label: Text('ONLINE'),
                  backgroundColor: Color(0xFFE6F6EA),
                  labelStyle: TextStyle(color: Colors.green),
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProviderProfileScreen(workerId: id),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
