import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'verification_process_screen.dart';

class VerificationStatusScreen extends StatefulWidget {
  const VerificationStatusScreen({super.key});

  @override
  State<VerificationStatusScreen> createState() =>
      _VerificationStatusScreenState();
}

class _VerificationStatusScreenState extends State<VerificationStatusScreen> {
  bool _loading = true;
  Map<String, dynamic>? _request; // latest verification_requests row
  
  String? _workerName;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user != null) {

        final worker = await client
            .from('users')
            .select('full_name')
            .eq('id', user.id)
            .maybeSingle();

            _workerName = worker?['full_name'] ?? 'Unknown Worker';

        final req = await client
            .from('verification_requests')
            .select('''
              id,
              status,
              created_at,
              reviewed_at,
              verification_photo_url,
              nbi_clearance_url,
              tesda_url,
              certificate_url,
              barangay_clearance_url,
              work_photo_urls,
              video_intro_url
            ''')
            .eq('user_id', user.id)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
        setState(() => _request = req);
      } else {
        setState(() => _request = null);
      }
    } catch (_) {
      // ignore UI errors; log if needed
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _hasUrl(dynamic v) {
    if (v == null) return false;
    if (v is String) return v.trim().isNotEmpty;
    if (v is List) return v.isNotEmpty;
    return false;
  }

  int _progressPercent(Map<String, dynamic>? req) {
    if (req == null) return 0;
    final hasId = _hasUrl(req['verification_photo_url']);
    final hasNbi = _hasUrl(req['nbi_clearance_url']);
    final hasTesda = _hasUrl(req['tesda_url']);
    final hasCert = _hasUrl(req['certificate_url']);
    final parts = [hasId, hasNbi, hasTesda, hasCert];
    final have = parts.where((b) => b).length;
    return ((have / parts.length) * 100).round();
  }

  @override
  Widget build(BuildContext context) {
    final accent = const Color(0xFFED9121);
    final status = (_request?['status'] as String?) ?? 'pending';
    final progress = _progressPercent(_request);

    final hasId = _hasUrl(_request?['verification_photo_url']);
    final hasNbi = _hasUrl(_request?['nbi_clearance_url']);
    final hasTesda = _hasUrl(_request?['tesda_url']);
    final hasCert = _hasUrl(_request?['certificate_url']);

    return Scaffold(
      appBar: AppBar(
        title:
            const Text('Verification Status', style: TextStyle(color: Colors.white)),
        backgroundColor: accent,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFED9121)),
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const CircleAvatar(
                        radius: 22,
                        backgroundImage: AssetImage('assets/worker.png'),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _workerName ?? 'Worker',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const Text('Service Provider',
                                style: TextStyle(fontSize: 12, color: Colors.black54),
                                ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                          child: _statusTile(
                              'Status',
                              status[0].toUpperCase() +
                                  status.substring(1))),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _statusTile('Progress', '$progress% Complete')),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('Upload Documents',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),

                  _docRow(Icons.badge, 'ID', hasId),
                  const Divider(),
                  _docRow(Icons.verified_user, 'NBI Clearance', hasNbi),
                  const Divider(),
                  _docRow(Icons.school, 'TESDA', hasTesda),
                  const Divider(),
                  _docRow(Icons.card_membership, 'Certifications', hasCert),

                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const VerificationProcessScreen()),
                        );
                        _load();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('Submit Documents'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _statusTile(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _docRow(IconData icon, String title, bool uploaded) {
    final color = uploaded ? Colors.green : Colors.black54;
    final label = uploaded ? 'Uploaded' : 'Upload Required';
    return Row(
      children: [
        Icon(icon, color: const Color(0xFFED9121)),
        const SizedBox(width: 12),
        Expanded(child: Text(title)),
        Text(label, style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }
}
