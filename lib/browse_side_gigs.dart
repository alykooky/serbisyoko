import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'side_gig_detail_screen.dart';
import 'services/notification_service.dart';

class BrowseSideGigsScreen extends StatefulWidget {
  const BrowseSideGigsScreen({super.key});

  @override
  State<BrowseSideGigsScreen> createState() => _BrowseSideGigsScreenState();
}

class _BrowseSideGigsScreenState extends State<BrowseSideGigsScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _rows = [];
  final supa = Supabase.instance.client;
  String _searchQuery = '';
  String _sortBy = 'newest'; // 'newest', 'price_high', 'price_low'

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await supa
          .from('side_gigs')
          .select('id,title,description,location,price_offer,status,created_at,user_id')
          .eq('status', 'open')
          .order('created_at', ascending: false);

      List<Map<String, dynamic>> filteredRows = List<Map<String, dynamic>>.from(rows);

      // Apply search filter
      if (_searchQuery.isNotEmpty) {
        filteredRows = filteredRows.where((gig) {
          final title = (gig['title'] ?? '').toString().toLowerCase();
          final desc = (gig['description'] ?? '').toString().toLowerCase();
          final location = (gig['location'] ?? '').toString().toLowerCase();
          final query = _searchQuery.toLowerCase();
          return title.contains(query) || desc.contains(query) || location.contains(query);
        }).toList();
      }

      // Apply sorting
      filteredRows.sort((a, b) {
        switch (_sortBy) {
          case 'price_high':
            final priceA = (a['price_offer'] as num?)?.toInt() ?? 0;
            final priceB = (b['price_offer'] as num?)?.toInt() ?? 0;
            return priceB.compareTo(priceA);
          case 'price_low':
            final priceA = (a['price_offer'] as num?)?.toInt() ?? 0;
            final priceB = (b['price_offer'] as num?)?.toInt() ?? 0;
            return priceA.compareTo(priceB);
          case 'newest':
          default:
            final dateA = DateTime.tryParse(a['created_at']?.toString() ?? '') ?? DateTime(1970);
            final dateB = DateTime.tryParse(b['created_at']?.toString() ?? '') ?? DateTime(1970);
            return dateB.compareTo(dateA);
        }
      });

      setState(() => _rows = filteredRows);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Load failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _accept(Map<String, dynamic> gig) async {
    try {
      final me = supa.auth.currentUser;
      if (me == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please sign in to accept gigs')),
        );
        return;
      }

      // Confirmation dialog
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Accept Gig?'),
          content: Text('Are you sure you want to accept "${gig['title']}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFED9121),
                foregroundColor: Colors.white,
              ),
              child: const Text('Accept'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      // Update gig status
      final updated = await supa
          .from('side_gigs')
          .update({
            'assigned_provider_id': me.id,
            'status': 'assigned',
          })
          .eq('id', gig['id'])
          .eq('status', 'open')
          .select()
          .maybeSingle();

      if (updated == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gig is no longer available or was already taken.')),
        );
        await _load();
        return;
      }

      // Notify the client who posted the gig
      final clientId = gig['user_id']?.toString();
      final gigTitle = gig['title']?.toString() ?? 'Side Gig';
      
      if (clientId != null) {
        try {
          // Get worker name
          final workerData = await supa
              .from('users')
              .select('name, first_name, last_name')
              .eq('id', me.id)
              .maybeSingle();
          
          final workerName = workerData?['name']?.toString() ?? 
              '${workerData?['first_name'] ?? ''} ${workerData?['last_name'] ?? ''}'.trim();
          final displayName = workerName.isNotEmpty ? workerName : 'A worker';

          await NotificationService.createNotification(
            userId: clientId,
            type: 'gig_status_changed',
            title: 'Gig Accepted!',
            message: '$displayName has accepted your gig "$gigTitle". They will start working on it soon!',
            relatedId: gig['id'].toString(),
            relatedType: 'side_gig',
          );
        } catch (e) {
          debugPrint('Error sending notification to client: $e');
          // Don't fail the accept action if notification fails
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gig accepted successfully! Client has been notified.'),
            backgroundColor: Colors.green,
          ),
        );
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Accept failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFED9121);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Browse Side Gigs'),
        backgroundColor: accent,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Search and Filter Bar
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.grey[100],
            child: Column(
              children: [
                // Search Bar
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Search gigs...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              setState(() => _searchQuery = '');
                              _load();
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (value) {
                    setState(() => _searchQuery = value);
                    _load();
                  },
                ),
                const SizedBox(height: 8),
                // Sort Options
                Row(
                  children: [
                    const Text('Sort by: ', style: TextStyle(fontWeight: FontWeight.w500)),
                    Expanded(
                      child: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'newest', label: Text('Newest')),
                          ButtonSegment(value: 'price_high', label: Text('Price: High')),
                          ButtonSegment(value: 'price_low', label: Text('Price: Low')),
                        ],
                        selected: {_sortBy},
                        onSelectionChanged: (Set<String> newSelection) {
                          setState(() {
                            _sortBy = newSelection.first;
                            _load();
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Gigs List
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _rows.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.work_outline, size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isEmpty
                                  ? 'No open gigs right now'
                                  : 'No gigs match your search',
                              style: TextStyle(color: Colors.grey[600], fontSize: 16),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: _rows.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (_, i) {
                            final g = _rows[i];
                            final createdAt = DateTime.tryParse(g['created_at']?.toString() ?? '');
                            
                            return Card(
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: InkWell(
                                onTap: () async {
                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => SideGigDetailScreen(gigId: g['id'].toString()),
                                    ),
                                  );
                                  if (result == true) {
                                    _load();
                                  }
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  g['title'] ?? 'Untitled Gig',
                                                  style: const TextStyle(
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                if (createdAt != null) ...[
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    DateFormat('MMM dd, yyyy • hh:mm a').format(createdAt),
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.grey[600],
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: accent,
                                              borderRadius: BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              '₱${g['price_offer'] ?? 0}',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      if ((g['description'] ?? '').toString().isNotEmpty) ...[
                                        const SizedBox(height: 12),
                                        Text(
                                          g['description'],
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey[700],
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          Icon(Icons.location_on, size: 16, color: Colors.grey[600]),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              g['location'] ?? 'Location not specified',
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: Colors.grey[600],
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton.icon(
                                          onPressed: () => _accept(g),
                                          icon: const Icon(Icons.check_circle, size: 20),
                                          label: const Text('Accept Gig'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: accent,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(vertical: 12),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
