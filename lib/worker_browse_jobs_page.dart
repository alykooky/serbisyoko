import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'services/job_application_service.dart';

class WorkerBrowseJobsPage extends StatefulWidget {
  const WorkerBrowseJobsPage({super.key});

  @override
  State<WorkerBrowseJobsPage> createState() => _WorkerBrowseJobsPageState();
}

class _WorkerBrowseJobsPageState extends State<WorkerBrowseJobsPage> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  List<Map<String, dynamic>> _requests = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final user = _sb.auth.currentUser;
      if (user == null) {
        debugPrint("⚠️ User not logged in");
        setState(() => _requests = []);
        return;
      }

      debugPrint("👤 Loading requests for worker: ${user.id}");
      final rows = await JobApplicationService.fetchOpenRequests(
        workerId: user.id,
      );
      
      debugPrint("📊 Received ${rows.length} requests");
      setState(() {
        _requests = rows;
      });
    } catch (e) {
      debugPrint("❌ Error loading requests: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading jobs: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _apply(Map<String, dynamic> req) async {
    final user = _sb.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in as worker.')),
      );
      return;
    }

    final rateController = TextEditingController(
      text: (req['budget_min'] ?? '').toString(),
    );
    final noteController = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Apply to ${req['service_type']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Client location: ${req['location'] ?? 'N/A'}'),
              const SizedBox(height: 8),
              TextField(
                controller: rateController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Rate offer (₱/hr)',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: noteController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Message to client (optional)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final rate = double.tryParse(rateController.text.trim());
                final note = noteController.text.trim().isEmpty
                    ? null
                    : noteController.text.trim();

                try {
                  await JobApplicationService.applyToRequest(
                    requestId: req['id'].toString(),
                    workerId: user.id,
                    rateOffer: rate,
                    note: note,
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Application sent!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                    // Refresh the list to show updated status
                    _load();
                  }
                  Navigator.pop(ctx);
                } catch (e) {
                  debugPrint('Apply error: $e');
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
                  }
                }
              },
              child: const Text('Send'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFED9121);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Browse Job Posts'),
        backgroundColor: accent,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _requests.isEmpty
              ? const Center(
                  child: Text('No open service requests yet.'),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _requests.length,
                    itemBuilder: (ctx, i) {
                      final req = _requests[i];
                      final preferredDate = req['preferred_date']?.toString();
                      DateTime? date;
                      if (preferredDate != null && preferredDate.isNotEmpty) {
                        date = DateTime.tryParse(preferredDate);
                      }
                      
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      req['service_type'] ?? 'Service',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  ElevatedButton(
                                    onPressed: () => _apply(req),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: accent,
                                      foregroundColor: Colors.white,
                                    ),
                                    child: const Text('Apply'),
                                  ),
                                ],
                              ),
                              if (req['description'] != null &&
                                  req['description'].toString().isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  req['description'],
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ],
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(Icons.location_on, size: 16, color: Colors.grey),
                                  Expanded(
                                    child: Text(
                                      ' ${req['location'] ?? 'N/A'}',
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.money, size: 16, color: Colors.grey),
                                  Text(
                                    ' Budget: ₱${(req['budget_min'] ?? 0)} - ₱${(req['budget_max'] ?? 0)}',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ],
                              ),
                              if (date != null) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                                    Text(
                                      ' Preferred: ${date.day}/${date.month}/${date.year}',
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
