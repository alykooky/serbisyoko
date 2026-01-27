import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminAuditService {
  static SupabaseClient get _sb => Supabase.instance.client;

  /// Create an audit log entry for admin actions
  static Future<void> logAction({
    required String actionType, // 'verification_approved', 'verification_rejected', etc.
    required String entityType, // 'verification_request', 'user', 'booking', etc.
    String? entityId,
    Map<String, dynamic>? details, // Additional details like reason, old_value, new_value
    String? ipAddress,
    String? userAgent,
  }) async {
    try {
      final currentUser = _sb.auth.currentUser;
      if (currentUser == null) {
        debugPrint('⚠️ Cannot log audit: No current user');
        return;
      }

      // Get admin email
      String? adminEmail;
      try {
        final userData = await _sb
            .from('users')
            .select('email')
            .eq('id', currentUser.id)
            .maybeSingle();
        adminEmail = userData?['email']?.toString();
      } catch (e) {
        debugPrint('⚠️ Could not fetch admin email: $e');
      }

      await _sb.from('admin_audit_logs').insert({
        'admin_id': currentUser.id,
        'admin_email': adminEmail,
        'action_type': actionType,
        'entity_type': entityType,
        'entity_id': entityId,
        'details': details,
        'ip_address': ipAddress,
        'user_agent': userAgent,
        'created_at': DateTime.now().toIso8601String(),
      });

      debugPrint('✅ Audit log created: $actionType for $entityType');
    } catch (e) {
      debugPrint('❌ Error creating audit log: $e');
      // Don't throw - audit logs shouldn't break the main flow
    }
  }

  /// Get audit logs (for admin viewing)
  static Future<List<Map<String, dynamic>>> getAuditLogs({
    String? actionType,
    String? entityType,
    DateTime? startDate,
    DateTime? endDate,
    int? limit,
  }) async {
    try {
      dynamic query = _sb
          .from('admin_audit_logs')
          .select()
          .order('created_at', ascending: false);

      if (actionType != null) {
        query = query.eq('action_type', actionType);
      }

      if (entityType != null) {
        query = query.eq('entity_type', entityType);
      }

      if (startDate != null) {
        query = query.gte('created_at', startDate.toIso8601String());
      }

      if (endDate != null) {
        query = query.lte('created_at', endDate.toIso8601String());
      }

      if (limit != null) {
        query = query.limit(limit);
      }

      final results = await query;
      return (results as List).map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e) {
      debugPrint('❌ Error fetching audit logs: $e');
      return [];
    }
  }
}

