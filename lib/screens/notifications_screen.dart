import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

import '../services/notification_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

const accent = Color(0xFFED9121);

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _notifications = [];

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() => _loading = true);
    try {
      final notifications = await NotificationService.getUserNotifications();
      setState(() {
        _notifications = notifications;
      });
    } catch (e) {
      debugPrint('Error loading notifications: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleNotificationTap(Map<String, dynamic> notification) async {
    // Mark as read
    await NotificationService.markAsRead(notification['id'].toString());
    
    final relatedType = notification['related_type']?.toString();
    final relatedId = notification['related_id']?.toString();
    final type = notification['type']?.toString();

    if (!mounted) return;

    // Handle time suggestion with action dialog
    if (type == 'time_suggestion') {
      if (relatedId != null && relatedType == 'booking') {
        await _handleTimeSuggestion(relatedId, notification);
        _loadNotifications();
        return;
      }
    }

    // For all other notifications, show details dialog (no navigation)
    _showNotificationDetails(notification);
    
    // Refresh notifications to update read status
    _loadNotifications();
  }

  void _showNotificationDetails(Map<String, dynamic> notification) {
    final type = notification['type']?.toString() ?? '';
    final title = notification['title']?.toString() ?? 'Notification';
    final message = notification['message']?.toString() ?? '';
    final createdAt = notification['created_at']?.toString();
    final relatedType = notification['related_type']?.toString();
    final relatedId = notification['related_id']?.toString();

    // Get icon based on type
    IconData icon;
    Color iconColor;
    switch (type) {
      case 'application_accepted':
      case 'booking_created':
        icon = Icons.check_circle;
        iconColor = Colors.green;
        break;
      case 'new_application':
        icon = Icons.person_add;
        iconColor = accent;
        break;
      case 'application_rejected':
        icon = Icons.cancel;
        iconColor = Colors.red;
        break;
      case 'booking_status_changed':
        icon = Icons.update;
        iconColor = Colors.blue;
        break;
      case 'time_suggestion':
        icon = Icons.schedule;
        iconColor = accent;
        break;
      default:
        icon = Icons.notifications;
        iconColor = Colors.grey;
    }

    // Format date
    String formattedDate = 'Date not available';
    if (createdAt != null) {
      try {
        final date = DateTime.tryParse(createdAt);
        if (date != null) {
          formattedDate = DateFormat('EEEE, MMMM dd, yyyy\nh:mm a').format(date);
        }
      } catch (e) {
        debugPrint('Error formatting date: $e');
      }
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: iconColor.withOpacity(0.2),
              child: Icon(icon, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Text(
                message,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      formattedDate,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
                      ),
                    ),
                  ),
                ],
              ),
              if (relatedType != null && relatedId != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Type: ${_formatRelatedType(relatedType)}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[700],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _formatRelatedType(String type) {
    switch (type.toLowerCase()) {
      case 'booking':
        return 'Booking';
      case 'request':
        return 'Service Request';
      case 'application':
        return 'Application';
      default:
        return type;
    }
  }

  Future<void> _markAllAsRead() async {
    await NotificationService.markAllAsRead();
    _loadNotifications();
  }

  Future<void> _deleteNotification(String notificationId) async {
    await NotificationService.deleteNotification(notificationId);
    _loadNotifications();
  }

  Future<void> _handleTimeSuggestion(String bookingId, Map<String, dynamic> notification) async {
    try {
      // Fetch booking to get suggested time
      final booking = await Supabase.instance.client
          .from('bookings')
          .select('id, scheduled_time, suggested_time, service_type')
          .eq('id', bookingId)
          .maybeSingle();

      if (booking == null || booking['suggested_time'] == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Time suggestion not found')),
          );
        }
        return;
      }

      final currentTime = DateTime.tryParse(booking['scheduled_time'].toString());
      final suggestedTime = DateTime.tryParse(booking['suggested_time'].toString());

      if (currentTime == null || suggestedTime == null) return;

      if (!mounted) return;

      final accepted = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Time Suggestion'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('The worker suggests a different time for "${booking['service_type']}"'),
              const SizedBox(height: 16),
              const Text('Current Time:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(DateFormat('EEEE, MMMM dd, yyyy\nh:mm a').format(currentTime)),
              const SizedBox(height: 12),
              const Text('Suggested Time:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(
                DateFormat('EEEE, MMMM dd, yyyy\nh:mm a').format(suggestedTime),
                style: const TextStyle(color: accent, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Reject'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: accent),
              child: const Text('Accept'),
            ),
          ],
        ),
      );

      if (accepted == null) return;

      // Update booking
      if (accepted == true) {
        // Accept suggestion - update scheduled_time
        await Supabase.instance.client
            .from('bookings')
            .update({
              'scheduled_time': suggestedTime.toIso8601String(),
              'suggested_time': null, // Clear suggestion
              'suggested_by': null,
            })
            .eq('id', bookingId);

        // Notify worker
        final bookingFull = await Supabase.instance.client
            .from('bookings')
            .select('worker_id')
            .eq('id', bookingId)
            .maybeSingle();

        if (bookingFull?['worker_id'] != null) {
          await NotificationService.createNotification(
            userId: bookingFull!['worker_id'].toString(),
            type: 'booking_status_changed',
            title: 'Time Change Accepted',
            message: 'Client accepted your time suggestion.',
            relatedId: bookingId,
            relatedType: 'booking',
          );
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Time suggestion accepted'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        // Reject suggestion - clear suggested_time
        await Supabase.instance.client
            .from('bookings')
            .update({
              'suggested_time': null,
              'suggested_by': null,
            })
            .eq('id', bookingId);

        // Notify worker
        final bookingFull = await Supabase.instance.client
            .from('bookings')
            .select('worker_id')
            .eq('id', bookingId)
            .maybeSingle();

        if (bookingFull?['worker_id'] != null) {
          await NotificationService.createNotification(
            userId: bookingFull!['worker_id'].toString(),
            type: 'booking_status_changed',
            title: 'Time Suggestion Rejected',
            message: 'Client rejected your time suggestion.',
            relatedId: bookingId,
            relatedType: 'booking',
          );
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Time suggestion rejected'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }

      // Mark notification as read
      await NotificationService.markAsRead(notification['id'].toString());
      _loadNotifications();
    } catch (e) {
      debugPrint('Error handling time suggestion: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: accent,
        foregroundColor: Colors.white,
        actions: [
          if (_notifications.any((n) => !(n['is_read'] ?? false)))
            TextButton(
              onPressed: _markAllAsRead,
              child: const Text(
                'Mark all read',
                style: TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadNotifications,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _notifications.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.notifications_none, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            'No notifications',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'You\'ll see notifications here for bookings and applications',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _notifications.length,
                    itemBuilder: (context, index) {
                      final notif = _notifications[index];
                      final isRead = notif['is_read'] ?? false;
                      final type = notif['type']?.toString() ?? '';

                      // Get icon based on type
                      IconData icon;
                      Color iconColor;
                      switch (type) {
                        case 'application_accepted':
                        case 'booking_created':
                          icon = Icons.check_circle;
                          iconColor = Colors.green;
                          break;
                        case 'new_application':
                          icon = Icons.person_add;
                          iconColor = accent;
                          break;
                        case 'application_rejected':
                          icon = Icons.cancel;
                          iconColor = Colors.red;
                          break;
                        case 'booking_status_changed':
                          icon = Icons.update;
                          iconColor = Colors.blue;
                          break;
                        case 'time_suggestion':
                          icon = Icons.schedule;
                          iconColor = accent;
                          break;
                        default:
                          icon = Icons.notifications;
                          iconColor = Colors.grey;
                      }

                      return Dismissible(
                        key: Key(notif['id'].toString()),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          color: Colors.red,
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        onDismissed: (_) => _deleteNotification(notif['id'].toString()),
                        child: Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          color: isRead ? Colors.white : Colors.blue.shade50,
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: iconColor.withOpacity(0.2),
                              child: Icon(icon, color: iconColor),
                            ),
                            title: Text(
                              notif['title'] ?? 'Notification',
                              style: TextStyle(
                                fontWeight:
                                    isRead ? FontWeight.normal : FontWeight.bold,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(notif['message'] ?? ''),
                                const SizedBox(height: 4),
                                Text(
                                  _formatDate(notif['created_at']),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                            trailing: isRead
                                ? null
                                : const Icon(Icons.circle, size: 8, color: Colors.blue),
                            onTap: () => _handleNotificationTap(notif),
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }

  String _formatDate(dynamic dateStr) {
    if (dateStr == null) return '';
    try {
      final date = DateTime.tryParse(dateStr.toString());
      if (date == null) return '';
      
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inMinutes < 1) {
        return 'Just now';
      } else if (difference.inMinutes < 60) {
        return '${difference.inMinutes}m ago';
      } else if (difference.inHours < 24) {
        return '${difference.inHours}h ago';
      } else if (difference.inDays < 7) {
        return '${difference.inDays}d ago';
      } else {
        return '${date.day}/${date.month}/${date.year}';
      }
    } catch (e) {
      return '';
    }
  }
}

