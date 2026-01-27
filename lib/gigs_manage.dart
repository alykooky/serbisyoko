import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/notification_service.dart';

class GigsManageScreen extends StatefulWidget {
  const GigsManageScreen({super.key});

  @override
  State<GigsManageScreen> createState() => _GigsManageScreenState();
}

class _GigsManageScreenState extends State<GigsManageScreen> {
  final sb = Supabase.instance.client;
  static const accent = Color(0xFFED9121);

  Future<void> _complete(String id) async {
    try {
      // Get gig details before updating
      final gig = await sb
          .from('side_gigs')
          .select('id, title, user_id, status')
          .eq('id', id)
          .maybeSingle();

      if (gig == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gig not found')),
        );
        return;
      }

      // Update status
      await sb.from('side_gigs').update({'status': 'completed'}).eq('id', id);

      // Notify the client who posted the gig
      final clientId = gig['user_id']?.toString();
      final gigTitle = gig['title']?.toString() ?? 'Side Gig';

      if (clientId != null) {
        try {
          // Get worker name
          final me = sb.auth.currentUser;
          if (me != null) {
            final workerData = await sb
                .from('users')
                .select('name, first_name, last_name')
                .eq('id', me.id)
                .maybeSingle();

            final workerName = workerData?['name']?.toString() ??
                '${workerData?['first_name'] ?? ''} ${workerData?['last_name'] ?? ''}'.trim();
            final displayName = workerName.isNotEmpty ? workerName : 'Worker';

            await NotificationService.createNotification(
              userId: clientId,
              type: 'gig_status_changed',
              title: 'Gig Completed!',
              message: '$displayName has completed your gig "$gigTitle". Please check your gig history for details.',
              relatedId: id,
              relatedType: 'side_gig',
            );
          }
        } catch (e) {
          debugPrint('Error sending completion notification: $e');
          // Don't fail the completion if notification fails
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Marked completed. Client has been notified.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
    }
  }

  Future<void> _unassign(String id) async {
    try {
      await sb
          .from('side_gigs')
          .update({'assigned_provider_id': null, 'status': 'open'})
          .eq('id', id);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = sb.auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Assigned Gigs', style: TextStyle(color: Colors.white)),
        backgroundColor: accent,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: me == null
          ? const Center(child: Text('Not signed in'))
          : StreamBuilder<List<Map<String, dynamic>>>(
              stream: sb
                  .from('side_gigs')
                  .stream(primaryKey: ['id'])
                  .eq('assigned_provider_id', me.id)
                  // optionally, sort client-side by updated_at desc below
                  ,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation(accent),
                    ),
                  );
                }
                if (snap.hasError) {
                  return Center(child: Text('Error: ${snap.error}'));
                }

                final data = (snap.data ?? const [])
                  ..sort((a, b) {
                    final sa = DateTime.tryParse((a['updated_at'] ?? '').toString()) ?? DateTime(1970);
                    final sbb = DateTime.tryParse((b['updated_at'] ?? '').toString()) ?? DateTime(1970);
                    return sbb.compareTo(sa);
                  });

                if (data.isEmpty) {
                  return const Center(child: Text('No gigs assigned yet.'));
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    // stream auto-refreshes; just wait briefly to show indicator
                    await Future.delayed(const Duration(milliseconds: 300));
                  },
                  color: accent,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: data.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final g = data[i];
                      return Card(
                        child: ListTile(
                          title: Text(
                            g['title'] ?? '',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if ((g['description'] ?? '').toString().trim().isNotEmpty)
                                Text(g['description']),
                              const SizedBox(height: 6),
                              Text('₱${g['price_offer'] ?? 0}  •  ${g['location'] ?? '—'}'),
                              const SizedBox(height: 4),
                              Text('Status: ${g['status']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                            ],
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (v) {
                              if (v == 'complete') _complete(g['id'] as String);
                              if (v == 'unassign') _unassign(g['id'] as String);
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'complete', child: Text('Mark Completed')),
                              PopupMenuItem(value: 'unassign', child: Text('Unassign')),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}
