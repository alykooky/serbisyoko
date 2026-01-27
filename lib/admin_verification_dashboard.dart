import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'login.dart';
import 'services/admin_audit_service.dart';
import 'services/notification_service.dart';
import 'chat_screen.dart';
import 'admin_settings.dart';
import 'admin_audit_logs_screen.dart';

class AdminVerificationDashboard extends StatefulWidget {
  const AdminVerificationDashboard({Key? key}) : super(key: key);

  @override
  State<AdminVerificationDashboard> createState() =>
      _AdminVerificationDashboardState();
}

class _AdminVerificationDashboardState
    extends State<AdminVerificationDashboard> {
  String _initialOf(Object? value) {
    final s = (value is String) ? value.trim() : '';
    if (s.isEmpty) return '?';
    final chars = s.characters;
    return chars.isEmpty ? '?' : chars.first.toUpperCase();
  }

  // 3 buckets
  List<Map<String, dynamic>> _pendingRequests = [];
  List<Map<String, dynamic>> _verifiedRequests = [];
  List<Map<String, dynamic>> _rejectedRequests = [];

  bool _isLoading = true;
  String _selectedTab = 'pending';

  RealtimeChannel? _realtimeChannel; // Added for realtime subscriptions

  @override
  void initState() {
    super.initState();
    _loadRequests();
    _setupRealtime(); // Added to setup realtime listener
  }

  @override
  void dispose() {
    _realtimeChannel?.unsubscribe(); // Clean up realtime on dispose
    super.dispose();
  }

  // Setup realtime subscription to listen for new inserts
  void _setupRealtime() {
    final supabase = Supabase.instance.client;
    _realtimeChannel = supabase
        .channel('verification_requests_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'verification_requests',
          callback: (payload) {
            // Reload when new verification requests are added with 'pending' status
            final status = payload.newRecord?['status']?.toString();
            if (status == 'pending' || status == 'requested') {
              _loadRequests();
            }
          },
        )
        .subscribe();
  }

  // Open helper links in external browser
  Future<void> _openExternal(String url) async {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open link')),
      );
    }
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Log out')),
        ],
      ),
    );
    if (ok == true) _logout();
  }

  Future<void> _logout() async {
    try {
      await Supabase.instance.client.auth.signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const SignInScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sign out failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _loadRequests() async {
    try {
      setState(() => _isLoading = true);
      final supabase = Supabase.instance.client;

      // Log current user
      final currentUser = supabase.auth.currentUser;
      print('Current user ID: ${currentUser?.id}, Email: ${currentUser?.email}');

      // Fetch pending requests
      final pending = await supabase
          .from('verification_requests')
          .select('''
            id, user_id, full_name, date_of_birth, status, created_at,
            reviewed_at, reviewed_by, rejection_reason,
            verification_photo_url, work_photo_urls, certificate_url,
            barangay_clearance_url, nbi_clearance_url, tesda_url, video_intro_url,
            referral_code
          ''')
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      // Fetch verified (approved) requests
      final verified = await supabase
          .from('verification_requests')
          .select('''
            id, user_id, full_name, date_of_birth, status, created_at,
            reviewed_at, reviewed_by, rejection_reason,
            verification_photo_url, work_photo_urls, certificate_url,
            barangay_clearance_url, nbi_clearance_url, tesda_url, video_intro_url,
            referral_code
          ''')
          .eq('status', 'approved')
          .order('reviewed_at', ascending: false);

      // Fetch rejected requests
      final rejected = await supabase
          .from('verification_requests')
          .select('''
            id, user_id, full_name, date_of_birth, status, created_at,
            reviewed_at, reviewed_by, rejection_reason,
            verification_photo_url, work_photo_urls, certificate_url,
            barangay_clearance_url, nbi_clearance_url, tesda_url, video_intro_url,
            referral_code
          ''')
          .eq('status', 'rejected')
          .order('reviewed_at', ascending: false);

      // user map
      final userIds = {
        ...pending.map((r) => r['user_id']),
        ...verified.map((r) => r['user_id']),
        ...rejected.map((r) => r['user_id']),
      }.where((id) => id != null).toSet().toList();

      Map<String, dynamic> userMap = {};
      if (userIds.isNotEmpty) {
        final users = await supabase
            .from('users')
            .select('id, name, email, phone')
            .inFilter('id', userIds);
        for (var u in users) {
          userMap[u['id']] = u;
        }
      }

      setState(() {
        _pendingRequests = List<Map<String, dynamic>>.from(
          pending.map((req) => {...req, 'users': userMap[req['user_id']] ?? {}}),
        );
        _verifiedRequests = List<Map<String, dynamic>>.from(
          verified.map((req) => {...req, 'users': userMap[req['user_id']] ?? {}}),
        );
        _rejectedRequests = List<Map<String, dynamic>>.from(
          rejected.map((req) => {...req, 'users': userMap[req['user_id']] ?? {}}),
        );
        _isLoading = false;
      });
    } catch (e) {
      print('Error in _loadRequests: $e');  // This should catch RLS errors
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading verification requests: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _showRejectionDialog(Map<String, dynamic> request) async {
    final reasonController = TextEditingController();
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Verification'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Please provide a reason for rejection:'),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Enter rejection reason...',
                border: OutlineInputBorder(),
                labelText: 'Reason',
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              final reason = reasonController.text.trim();
              if (reason.isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text('Please provide a rejection reason'),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }
              Navigator.pop(ctx, {'reason': reason});
            },
            child: const Text('Reject', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (result != null && result['reason'] != null) {
      await _verifyRequest(
        request['id'],
        request,
        false,
        rejectionReason: result['reason'] as String,
      );
    }
  }

  Future<void> _verifyRequest(
    dynamic requestId,
    Map<String, dynamic> request,
    bool approved, {
    String? rejectionReason,
  }) async {
    try {
      // minimal check: when approving, make sure they uploaded required docs
      if (approved) {
        final verificationPhoto = request['verification_photo_url'];
        final workPhotos = request['work_photo_urls'];

        final bool hasVerificationPhoto =
            verificationPhoto != null && verificationPhoto.toString().isNotEmpty;

        bool hasWorkPhotos = false;
        if (workPhotos != null) {
          if (workPhotos is String && workPhotos.trim().isNotEmpty) {
            hasWorkPhotos = true;
          } else if (workPhotos is List && workPhotos.isNotEmpty) {
            hasWorkPhotos = true;
          }
        }

        if (!hasVerificationPhoto || !hasWorkPhotos) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please make sure required documents are uploaded before approving.'),
              backgroundColor: Colors.orange,
            ),
          );
          return;
        }
      }

      final supabase = Supabase.instance.client;
      final currentUser = supabase.auth.currentUser;
      final id = requestId ?? request['id'];
      final nowIso = DateTime.now().toIso8601String();

      // Prepare update data
      final updateData = {
        'status': approved ? 'approved' : 'rejected',
        'reviewed_at': nowIso,
        'reviewed_by': currentUser?.id,
      };

      // Add rejection reason if provided
      if (!approved && rejectionReason != null && rejectionReason.isNotEmpty) {
        updateData['rejection_reason'] = rejectionReason;
      }

      // Update the request row
      await supabase
          .from('verification_requests')
          .update(updateData)
          .eq('id', id);

      // OPTIONAL: also stamp worker_profiles
      await supabase
          .from('worker_profiles')
          .update({
            'verification_status': approved ? 'verified' : 'pending',
            'is_verified': approved,
            'verified_at': approved ? nowIso : null,
            'verified_by': currentUser?.id,
          })
          .eq('user_id', request['user_id']);

      // Create audit log
      try {
        await AdminAuditService.logAction(
          actionType: approved ? 'verification_approved' : 'verification_rejected',
          entityType: 'verification_request',
          entityId: id.toString(),
          details: {
            'user_id': request['user_id']?.toString(),
            'full_name': request['full_name']?.toString(),
            'rejection_reason': rejectionReason,
          },
        );
      } catch (e) {
        debugPrint('⚠️ Error logging audit: $e');
        // Don't fail the operation if audit logging fails
      }

      // reflect in UI
      setState(() {
        _pendingRequests.removeWhere((r) => r['id'] == id);
        if (approved) {
          _verifiedRequests.insert(0, {
            ...request,
            'status': 'approved',
            'reviewed_at': nowIso,
            'reviewed_by': currentUser?.id,
            'rejection_reason': null,
          });
          _selectedTab = 'verified';
        } else {
          _rejectedRequests.insert(0, {
            ...request,
            'status': 'rejected',
            'reviewed_at': nowIso,
            'reviewed_by': currentUser?.id,
            'rejection_reason': rejectionReason,
          });
          _selectedTab = 'rejected';
        }
      });

      // Show notification/message options after successful approval/rejection
      if (mounted) {
        final workerId = request['user_id']?.toString();
        final workerName = (request['users'] as Map?)?['name']?.toString() ?? 'Worker';
        
        if (workerId != null && workerId.isNotEmpty) {
          final nonNullWorkerId = workerId; // Capture for type promotion
          final action = await showDialog<String>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(approved ? 'Request Approved' : 'Request Rejected'),
              content: Text(
                approved
                    ? 'The worker verification has been approved. Would you like to notify or message the worker?'
                    : 'The worker verification has been rejected. Would you like to notify or message the worker about what documents are needed?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'skip'),
                  child: const Text('Skip'),
                ),
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(ctx, 'message'),
                  icon: const Icon(Icons.message),
                  label: const Text('Message'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFED9121),
                    side: const BorderSide(color: Color(0xFFED9121)),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(ctx, 'notify'),
                  icon: const Icon(Icons.notifications),
                  label: const Text('Notify'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFED9121),
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          );

          if (action == 'notify') {
            await _sendNotificationToWorker(
              nonNullWorkerId,
              approved,
              rejectionReason: rejectionReason,
              workerName: workerName,
            );
          } else if (action == 'message') {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatScreen(
                  otherUserId: nonNullWorkerId,
                  otherUserName: workerName, // Chat screen will show "SerbisyoKo" if admin
                  conversationId: '',
                ),
              ),
            );
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(approved ? 'Request approved successfully' : 'Request rejected'),
            backgroundColor: approved ? Colors.green : Colors.orange,
          ),
        );
      }
    } on PostgrestException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update failed: ${e.message}'), backgroundColor: Colors.red),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating request: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _sendNotificationToWorker(
    String workerId,
    bool approved, {
    String? rejectionReason,
    String? workerName,
  }) async {
    try {
      debugPrint('🔔 Sending notification to worker: $workerId');
      final message = approved
          ? 'Congratulations! Your worker verification has been approved. You can now start receiving bookings.'
          : 'Your worker verification has been rejected. Reason: ${rejectionReason ?? "Please review your submitted documents and try again."}';
      
      final success = await NotificationService.createNotification(
        userId: workerId,
        type: approved ? 'verification_approved' : 'verification_rejected',
        title: approved ? 'Verification Approved' : 'Verification Rejected',
        message: message,
        relatedId: null,
        relatedType: 'verification_request',
      );

      if (mounted) {
        if (success) {
          debugPrint('✅ Notification successfully sent to worker: $workerId');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Notification sent to worker'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          debugPrint('❌ Notification service returned false for worker: $workerId');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to send notification. Please check logs.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Error sending notification: $e');
      debugPrint('   Stack trace: $stackTrace');
      debugPrint('   Worker ID: $workerId');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send notification: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _notifyWorker(Map<String, dynamic> request) async {
    final workerId = request['user_id']?.toString();
    if (workerId == null) return;

    final status = request['status']?.toString() ?? '';
    final isApproved = status == 'approved';
    final rejectionReason = request['rejection_reason']?.toString();

    await _sendNotificationToWorker(
      workerId,
      isApproved,
      rejectionReason: rejectionReason,
      workerName: (request['users'] as Map?)?['name']?.toString() ?? 'Worker',
    );
  }

  void _openDetails(Map<String, dynamic> request) {
    final user = request['users'] ?? {};
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: CircleAvatar(
                backgroundColor: const Color(0xFFED9121),
                child: Text(
                  _initialOf(user['name']),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              title: Text(user['name'] ?? 'Unknown'),
              subtitle: Text(user['email'] ?? ''),
            ),
            const SizedBox(height: 8),
            Text('Full name: ${request['full_name'] ?? 'N/A'}'),
            Text('Date of birth: ${request['date_of_birth'] ?? 'N/A'}'),
            Text('Referral code: ${request['referral_code'] ?? 'N/A'}'),
            if (request['status'] == 'rejected' && request['rejection_reason'] != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  border: Border.all(color: Colors.red.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Rejection Reason:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(request['rejection_reason'] ?? 'N/A'),
                  ],
                ),
              ),
            ],
            const Divider(height: 24),
            const Text('Uploaded Documents:', style: TextStyle(fontWeight: FontWeight.bold)),
            _docLink('Verification Photo', request['verification_photo_url']),
            _docLink('NBI Clearance Document', request['nbi_clearance_url']),
            _docLink('TESDA Certificate', request['tesda_url']),
            _docLink('Work Photos', request['work_photo_urls']),
            _docLink('Certificates', request['certificate_url']),
            _docLink('Barangay Clearance', request['barangay_clearance_url']),
            _docLink('Video Intro', request['video_intro_url']),
            const SizedBox(height: 16),
            // Only show Approve/Reject buttons if status is pending
            if (request['status'] == 'pending' || request['status'] == 'requested') ...[
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.check),
                      label: const Text('Approve'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () async {
                        Navigator.pop(context);
                        await _verifyRequest(request['id'], request, true);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.close),
                      label: const Text('Reject'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                      ),
                      onPressed: () async {
                        Navigator.pop(context);
                        await _showRejectionDialog(request);
                      },
                    ),
                  ),
                ],
              ),
            ] else ...[
              // For already processed requests, show status and action buttons
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (request['status'] == 'approved') 
                      ? Colors.green.shade50 
                      : Colors.red.shade50,
                  border: Border.all(
                    color: (request['status'] == 'approved') 
                        ? Colors.green.shade300 
                        : Colors.red.shade300,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      request['status'] == 'approved' 
                          ? Icons.check_circle 
                          : Icons.cancel,
                      color: request['status'] == 'approved' 
                          ? Colors.green 
                          : Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Status: ${(request['status'] as String).toUpperCase()}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: request['status'] == 'approved' 
                            ? Colors.green.shade700 
                            : Colors.red.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.message),
                      label: const Text('Message Worker'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFED9121),
                        side: const BorderSide(color: Color(0xFFED9121)),
                      ),
                      onPressed: () {
                        final userId = request['user_id']?.toString();
                        final userName = (request['users'] as Map?)?['name']?.toString() ?? 'Worker';
                        if (userId != null && userId.isNotEmpty) {
                          final nonNullUserId = userId; // Capture for type promotion
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                otherUserId: nonNullUserId,
                                otherUserName: userName, // Chat screen will show "SerbisyoKo" if admin
                                conversationId: '',
                              ),
                            ),
                          );
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.notifications),
                      label: const Text('Notify'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFED9121),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () async {
                        await _notifyWorker(request);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _docLink(String title, dynamic url) {
    if (url == null) {
      return ListTile(
        leading: const Icon(Icons.error, color: Colors.red),
        title: Text(title),
        subtitle: const Text('No document uploaded'),
      );
    }
    List<String> urls = [];
    if (url is String) {
      if (url.trim().isNotEmpty) urls = [url];
    } else if (url is List) {
      urls = url.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList();
    }
    if (urls.isEmpty) {
      return ListTile(
        leading: const Icon(Icons.error, color: Colors.red),
        title: Text(title),
        subtitle: const Text('No document uploaded'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        ...urls.map(
          (link) => ListTile(
            leading: const Icon(Icons.file_present, color: Colors.green),
            title: Text(link),
            trailing: IconButton(
              icon: const Icon(Icons.open_in_new),
              onPressed: () async {
                final uri = Uri.parse(link);
                if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Could not open document')),
                  );
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  String _getEmptyStateMessage(String tab) {
    switch (tab) {
      case 'pending':
        return 'No pending verification requests';
      case 'verified':
        return 'No approved verification requests';
      case 'rejected':
        return 'No rejected verification requests';
      default:
        return 'No requests available';
    }
  }

  // Added: Build empty state widget for better UX
  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.inbox, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(message, style: const TextStyle(fontSize: 18, color: Colors.grey)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final requests = switch (_selectedTab) {
      'pending'   => _pendingRequests,
      'verified'  => _verifiedRequests,
      'rejected'  => _rejectedRequests,
      _           => _pendingRequests,
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Worker Verification'),
        backgroundColor: const Color(0xFFED9121),
        foregroundColor: Colors.white,
        actions: [
          // TESDA Button with Label
          Tooltip(
            message: 'TESDA Certificate Verification (RWAC)',
            child: InkWell(
              onTap: () => _openExternal('https://www.tesda.gov.ph/RWAC'),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'TESDA',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const Icon(Icons.school, size: 20, color: Colors.white),
                  ],
                ),
              ),
            ),
          ),
          // NBI Button with Label
          Tooltip(
            message: 'NBI Clearance Verification',
            child: InkWell(
              onTap: () => _openExternal('https://verification.nbi-clearance.io/'),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'NBI',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const Icon(Icons.verified_user, size: 20, color: Colors.white),
                  ],
                ),
              ),
            ),
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadRequests, tooltip: 'Refresh'),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'More options',
            onSelected: (value) {
              if (value == 'settings') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AdminSettings()),
                );
              } else if (value == 'audit_logs') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AdminAuditLogsScreen()),
                );
              } else if (value == 'logout') {
                _confirmLogout();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'settings',
                child: Row(
                  children: [
                    Icon(Icons.settings, color: Colors.grey),
                    SizedBox(width: 8),
                    Text('Settings'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'audit_logs',
                child: Row(
                  children: [
                    Icon(Icons.description, color: Colors.grey),
                    SizedBox(width: 8),
                    Text('Audit Logs'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Logout'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFED9121)),
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadRequests,
              child: requests.isEmpty
                  ? _buildEmptyState(_getEmptyStateMessage(_selectedTab))
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: requests.length,
                      itemBuilder: (context, i) {
                        final req = requests[i];
                        final user = req['users'] ?? {};
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: const Color(0xFFED9121),
                              child: Text(
                                _initialOf(user['name']),
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                            title: Text(user['name'] ?? 'Unknown'),
                            subtitle: Text('Status: ${req['status']}'),
                            trailing: IconButton(
                              icon: const Icon(Icons.visibility),
                              onPressed: () => _openDetails(req),
                            ),
                          ),
                        );
                      },
                    ),
            ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: switch (_selectedTab) {
          'pending'   => 0,
          'verified'  => 1,
          'rejected'  => 2,
          _           => 0,
        },
        onTap: (i) => setState(() {
          _selectedTab = switch (i) {
            0 => 'pending',
            1 => 'verified',
            2 => 'rejected',
            _ => 'pending',
          };
        }),
        selectedItemColor: const Color(0xFFED9121),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.hourglass_empty), label: 'Pending'),
          BottomNavigationBarItem(icon: Icon(Icons.verified), label: 'Verified'),
          BottomNavigationBarItem(icon: Icon(Icons.cancel), label: 'Rejected'),
        ],
      ),
    );
  }
}