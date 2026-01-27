import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class SideGigDetailScreen extends StatefulWidget {
  final String gigId;
  const SideGigDetailScreen({super.key, required this.gigId});

  @override
  State<SideGigDetailScreen> createState() => _SideGigDetailScreenState();
}

class _SideGigDetailScreenState extends State<SideGigDetailScreen> {
  final _supabase = Supabase.instance.client;
  bool _loading = true;
  Map<String, dynamic>? _gig;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadGig();
  }

  Future<void> _loadGig() async {
    setState(() {
      _loading = true;
      _error = null;
      _gig = null;
    });

    try {
      final gig = await _supabase
          .from('side_gigs')
          .select('id, title, description, location, price_offer, status, created_at, user_id, assigned_provider_id')
          .eq('id', widget.gigId)
          .maybeSingle();

      if (gig == null) {
        setState(() => _error = 'Gig not found.');
        return;
      }

      setState(() => _gig = Map<String, dynamic>.from(gig));
    } catch (e) {
      setState(() => _error = 'Error loading gig: $e');
      debugPrint('Error loading gig: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _acceptGig() async {
    if (_gig == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Accept Gig?'),
        content: Text(
          'Are you sure you want to accept "${_gig!['title']}"?',
        ),
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

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please sign in to accept gigs.')),
        );
        return;
      }

      // Update gig to assign it to current worker
      final updated = await _supabase
          .from('side_gigs')
          .update({
            'assigned_provider_id': user.id,
            'status': 'assigned',
          })
          .eq('id', widget.gigId)
          .eq('status', 'open') // Guard if someone else accepted already
          .select()
          .maybeSingle();

      if (updated == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Gig is no longer available or was already taken.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        // Reload to get updated status
        await _loadGig();
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gig accepted successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        
        // Navigate back after a short delay
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            Navigator.pop(context, true); // Return true to indicate refresh needed
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error accepting gig: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      debugPrint('Error accepting gig: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFED9121);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gig Details'),
        backgroundColor: accent,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: accent))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            color: Colors.red, size: 48),
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          style: const TextStyle(fontSize: 16),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadGig,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : _gig == null
                  ? const Center(child: Text('Gig not found'))
                  : RefreshIndicator(
                      onRefresh: _loadGig,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          // Title Card
                          Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          _gig!['title']?.toString() ??
                                              'Untitled Gig',
                                          style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      if (_gig!['status'] == 'open')
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.green,
                                            borderRadius:
                                                BorderRadius.circular(20),
                                          ),
                                          child: const Text(
                                            'OPEN',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        )
                                      else
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.orange,
                                            borderRadius:
                                                BorderRadius.circular(20),
                                          ),
                                          child: const Text(
                                            'ASSIGNED',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  // Price
                                  Row(
                                    children: [
                                      const Icon(Icons.payments,
                                          color: accent, size: 24),
                                      const SizedBox(width: 8),
                                      Text(
                                        '₱${_gig!['price_offer'] ?? 0}',
                                        style: const TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                          color: accent,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Description
                          if ((_gig!['description']?.toString() ?? '')
                              .isNotEmpty)
                            Card(
                              elevation: 1,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Row(
                                      children: [
                                        Icon(Icons.description,
                                            color: accent, size: 20),
                                        SizedBox(width: 8),
                                        Text(
                                          'Description',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      _gig!['description']?.toString() ?? '',
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                          const SizedBox(height: 16),

                          // Location
                          Card(
                            elevation: 1,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  const Icon(Icons.location_on,
                                      color: accent, size: 24),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Location',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _gig!['location']?.toString() ??
                                              'Not specified',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Posted Date
                          Card(
                            elevation: 1,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  const Icon(Icons.calendar_today,
                                      color: accent, size: 24),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Posted',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _gig!['created_at'] != null
                                              ? DateFormat('MMM dd, yyyy • hh:mm a').format(
                                                  DateTime.parse(
                                                      _gig!['created_at']))
                                              : 'Not specified',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Accept Button (only if status is 'open')
                          if (_gig!['status'] == 'open')
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _acceptGig,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: accent,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.check_circle, size: 24),
                                    SizedBox(width: 8),
                                    Text(
                                      'Accept This Gig',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.orange.shade200),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.info_outline, color: Colors.orange),
                                  SizedBox(width: 8),
                                  Text(
                                    'This gig has already been assigned',
                                    style: TextStyle(
                                      color: Colors.orange,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
    );
  }
}

