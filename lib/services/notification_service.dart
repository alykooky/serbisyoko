import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationService {
  static SupabaseClient get _sb => Supabase.instance.client;

  /// Create a notification for a user
  /// Uses database function to bypass RLS restrictions
  static Future<bool> createNotification({
    required String userId,
    required String type,
    required String title,
    required String message,
    String? relatedId,
    String? relatedType, // 'booking', 'application', 'request', etc.
  }) async {
    try {
      debugPrint('🔔 Creating notification for user: $userId');
      debugPrint('   Type: $type');
      debugPrint('   Title: $title');
      debugPrint('   Message: $message');
      
      // Try using the database function first (bypasses RLS completely)
      try {
        debugPrint('🔔 Attempting to create notification via function...');
        final result = await _sb.rpc('create_notification', params: {
          'p_user_id': userId,
          'p_type': type,
          'p_title': title,
          'p_message': message,
          'p_related_id': relatedId,
          'p_related_type': relatedType,
        });
        
        debugPrint('✅ Notification created successfully via function. ID: $result');
        return true;
      } catch (functionError) {
        debugPrint('⚠️ Function call failed: $functionError');
        debugPrint('⚠️ Attempting direct insert as fallback...');
        
        // Fallback: Try direct insert (should work if permissive policy exists)
        try {
          final result = await _sb.from('notifications').insert({
            'user_id': userId,
            'type': type,
            'title': title,
            'message': message,
            'related_id': relatedId,
            'related_type': relatedType,
            'is_read': false,
          }).select();
          
          debugPrint('✅ Notification created successfully via direct insert: ${result.toString()}');
          return true;
        } catch (insertError) {
          debugPrint('❌ Direct insert also failed: $insertError');
          rethrow; // Re-throw so outer catch can log it
        }
      }
    } catch (e, stackTrace) {
      debugPrint('❌ ERROR creating notification: $e');
      debugPrint('   Stack trace: $stackTrace');
      debugPrint('   User ID: $userId');
      debugPrint('   Type: $type');
      debugPrint('   Title: $title');
      debugPrint('   Current user: ${_sb.auth.currentUser?.id}');
      // Don't throw - notifications are not critical, but log the error
      return false;
    }
  }

  /// Get all notifications for a user
  static Future<List<Map<String, dynamic>>> getUserNotifications({
    String? userId,
    bool? unreadOnly,
    int? limit,
  }) async {
    try {
      final uid = userId ?? _sb.auth.currentUser?.id;
      if (uid == null) return [];

      // Build the query step by step, building it all in one chain
      dynamic query = _sb.from('notifications').select().eq('user_id', uid);
      
      if (unreadOnly == true) {
        query = query.eq('is_read', false);
      }
      
      query = query.order('created_at', ascending: false);
      
      if (limit != null) {
        query = query.limit(limit);
      }

      final results = await query;
      return (results as List).map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e) {
      debugPrint('Error fetching notifications: $e');
      return [];
    }
  }

  /// Mark notification as read
  static Future<void> markAsRead(String notificationId) async {
    try {
      await _sb
          .from('notifications')
          .update({'is_read': true})
          .eq('id', notificationId);
    } catch (e) {
      debugPrint('Error marking notification as read: $e');
    }
  }

  /// Mark all notifications as read for a user
  static Future<void> markAllAsRead({String? userId}) async {
    try {
      final uid = userId ?? _sb.auth.currentUser?.id;
      if (uid == null) return;

      await _sb
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', uid)
          .eq('is_read', false);
    } catch (e) {
      debugPrint('Error marking all notifications as read: $e');
    }
  }

  /// Get unread notification count
  static Future<int> getUnreadCount({String? userId}) async {
    try {
      final uid = userId ?? _sb.auth.currentUser?.id;
      if (uid == null) return 0;

      final result = await _sb
          .from('notifications')
          .select('id')
          .eq('user_id', uid)
          .eq('is_read', false);

      return (result as List).length;
    } catch (e) {
      debugPrint('Error getting unread count: $e');
      return 0;
    }
  }

  /// Delete notification
  static Future<void> deleteNotification(String notificationId) async {
    try {
      await _sb.from('notifications').delete().eq('id', notificationId);
    } catch (e) {
      debugPrint('Error deleting notification: $e');
    }
  }
}

