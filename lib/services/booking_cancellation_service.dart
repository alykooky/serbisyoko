// lib/services/booking_cancellation_service.dart
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'notification_service.dart';

class BookingCancellationService {
  static SupabaseClient get _sb => Supabase.instance.client;

  // Predefined reasons for worker cancellations
  static const List<String> workerCancellationReasons = [
    'Emergency',
    'Incomplete client information',
    'Safety concern',
    'Double booking (system issue)',
    'Other',
  ];

  // Predefined reasons for client cancellations (after acceptance)
  static const List<String> clientCancellationReasons = [
    'Found another worker',
    'Service no longer needed',
    'Scheduling conflict',
    'Price concern',
    'Other',
  ];

  /// Check if client can cancel without reason (before worker accepts)
  static bool canClientCancelFreely(String? currentStatus) {
    final status = (currentStatus ?? '').toLowerCase();
    return status == 'pending';
  }

  /// Check if cancellation requires a reason
  static bool requiresReason(String? currentStatus, bool isClient) {
    final status = (currentStatus ?? '').toLowerCase();
    
    if (isClient) {
      // Client needs reason after worker accepts
      return status == 'accepted' || status == 'inprogress';
    } else {
      // Worker always needs reason (to track cancellations)
      return true;
    }
  }

  /// Cancel booking by client
  static Future<Map<String, dynamic>> cancelByClient({
    required String bookingId,
    required String? reason,
    String? additionalNotes,
  }) async {
    try {
      // Get booking details first
      final booking = await _sb
          .from('bookings')
          .select('status, worker_id, service_type, client_id')
          .eq('id', bookingId)
          .maybeSingle();

      if (booking == null) {
        throw Exception('Booking not found');
      }

      final currentStatus = (booking['status'] ?? '').toString().toLowerCase();
      final newStatus = currentStatus == 'pending' 
          ? 'cancelled_by_client' 
          : 'cancelled_by_client';

      // Update booking
      final updated = await _sb
          .from('bookings')
          .update({
            'status': newStatus,
            'cancelled_at': DateTime.now().toIso8601String(),
            'cancelled_by': 'client',
            'cancellation_reason': reason,
            'cancellation_notes': additionalNotes,
          })
          .eq('id', bookingId)
          .select()
          .maybeSingle();

      // Track cancellation for abuse prevention
      await _trackCancellation(
        userId: booking['client_id']?.toString() ?? '',
        userType: 'client',
        bookingId: bookingId,
        reason: reason ?? 'No reason provided',
      );

      // Notify worker
      final workerId = booking['worker_id']?.toString();
      final serviceType = booking['service_type']?.toString() ?? 'service';
      
      if (workerId != null) {
        await NotificationService.createNotification(
          userId: workerId,
          type: 'booking_cancelled',
          title: 'Booking Cancelled by Client',
          message: 'The client has cancelled the booking for "$serviceType". This booking has been removed from your schedule.',
          relatedId: bookingId,
          relatedType: 'booking',
        );
      }

      debugPrint('✅ Booking cancelled by client: $bookingId');
      return {'success': true, 'data': updated};
    } catch (e) {
      debugPrint('❌ Error cancelling booking: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Cancel booking by worker
  static Future<Map<String, dynamic>> cancelByWorker({
    required String bookingId,
    required String reason,
    String? additionalNotes,
  }) async {
    try {
      // Get booking details first
      final booking = await _sb
          .from('bookings')
          .select('status, worker_id, service_type, client_id')
          .eq('id', bookingId)
          .maybeSingle();

      if (booking == null) {
        throw Exception('Booking not found');
      }

      // Update booking
      final updated = await _sb
          .from('bookings')
          .update({
            'status': 'cancelled_by_worker',
            'cancelled_at': DateTime.now().toIso8601String(),
            'cancelled_by': 'worker',
            'cancellation_reason': reason,
            'cancellation_notes': additionalNotes,
          })
          .eq('id', bookingId)
          .select()
          .maybeSingle();

      // Track cancellation for abuse prevention
      await _trackCancellation(
        userId: booking['worker_id']?.toString() ?? '',
        userType: 'worker',
        bookingId: bookingId,
        reason: reason,
      );

      // Notify client with suggestion to find another worker
      final clientId = booking['client_id']?.toString();
      final serviceType = booking['service_type']?.toString() ?? 'service';
      
      if (clientId != null) {
        await NotificationService.createNotification(
          userId: clientId,
          type: 'booking_cancelled',
          title: 'Booking Cancelled',
          message: 'The worker has cancelled your booking for "$serviceType". Reason: $reason. You can find another available worker in your bookings.',
          relatedId: bookingId,
          relatedType: 'booking',
        );
      }

      debugPrint('✅ Booking cancelled by worker: $bookingId');
      return {'success': true, 'data': updated};
    } catch (e) {
      debugPrint('❌ Error cancelling booking: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Track cancellation in database (for abuse prevention)
  static Future<void> _trackCancellation({
    required String userId,
    required String userType,
    required String bookingId,
    required String reason,
  }) async {
    try {
      await _sb.from('booking_cancellations').insert({
        'user_id': userId,
        'user_type': userType, // 'client' or 'worker'
        'booking_id': bookingId,
        'reason': reason,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('⚠️ Error tracking cancellation: $e');
      // Don't fail the cancellation if tracking fails
    }
  }

  /// Get cancellation count for a user (for abuse prevention)
  static Future<int> getCancellationCount(String userId, {int days = 30}) async {
    try {
      final cutoffDate = DateTime.now().subtract(Duration(days: days));
      
      final cancellations = await _sb
          .from('booking_cancellations')
          .select('id')
          .eq('user_id', userId)
          .gte('created_at', cutoffDate.toIso8601String());
      
      return cancellations.length;
    } catch (e) {
      debugPrint('⚠️ Error getting cancellation count: $e');
      return 0;
    }
  }

  /// Check if user has exceeded cancellation limit
  static Future<bool> hasExceededCancellationLimit(String userId, {int maxCancellations = 5, int days = 30}) async {
    final count = await getCancellationCount(userId, days: days);
    return count >= maxCancellations;
  }

  /// Auto-cancel booking if worker didn't respond (call this from a scheduled job)
  static Future<void> autoCancelUnrespondedBookings({int minutesThreshold = 30}) async {
    try {
      final cutoffTime = DateTime.now().subtract(Duration(minutes: minutesThreshold));
      
      // Find pending bookings older than threshold
      final unresponded = await _sb
          .from('bookings')
          .select('id, client_id, service_type, worker_id')
          .eq('status', 'pending')
          .lt('created_at', cutoffTime.toIso8601String());

      for (final booking in unresponded) {
        final bookingId = booking['id'].toString();
        
        // Auto-cancel
        await _sb
            .from('bookings')
            .update({
              'status': 'auto_cancelled_no_response',
              'cancelled_at': DateTime.now().toIso8601String(),
              'cancelled_by': 'system',
              'cancellation_reason': 'Worker did not respond within $minutesThreshold minutes',
            })
            .eq('id', bookingId);

        // Notify client
        final clientId = booking['client_id']?.toString();
        if (clientId != null) {
          await NotificationService.createNotification(
            userId: clientId,
            type: 'booking_auto_cancelled',
            title: 'Booking Auto-Cancelled',
            message: 'Your booking was cancelled because the worker did not respond. You can try booking again with another worker.',
            relatedId: bookingId,
            relatedType: 'booking',
          );
        }

        debugPrint('🔄 Auto-cancelled booking: $bookingId (no response)');
      }
    } catch (e) {
      debugPrint('❌ Error in auto-cancel: $e');
    }
  }

  /// Auto-cancel booking if client didn't confirm after worker accepts (call this from a scheduled job)
  static Future<void> autoCancelUnconfirmedBookings({int hoursThreshold = 24}) async {
    try {
      final cutoffTime = DateTime.now().subtract(Duration(hours: hoursThreshold));
      
      // Find accepted bookings where client hasn't confirmed (you might need to add a confirmed_at field)
      // For now, we'll just check accepted bookings older than threshold
      final unconfirmed = await _sb
          .from('bookings')
          .select('id, client_id, service_type, worker_id')
          .eq('status', 'accepted')
          .lt('updated_at', cutoffTime.toIso8601String());

      for (final booking in unconfirmed) {
        final bookingId = booking['id'].toString();
        
        // Auto-cancel
        await _sb
            .from('bookings')
            .update({
              'status': 'auto_cancelled_unconfirmed',
              'cancelled_at': DateTime.now().toIso8601String(),
              'cancelled_by': 'system',
              'cancellation_reason': 'Client did not confirm within $hoursThreshold hours',
            })
            .eq('id', bookingId);

        // Notify both parties
        final clientId = booking['client_id']?.toString();
        final workerId = booking['worker_id']?.toString();
        
        if (clientId != null) {
          await NotificationService.createNotification(
            userId: clientId,
            type: 'booking_auto_cancelled',
            title: 'Booking Auto-Cancelled',
            message: 'Your booking was cancelled because it was not confirmed in time.',
            relatedId: bookingId,
            relatedType: 'booking',
          );
        }

        if (workerId != null) {
          await NotificationService.createNotification(
            userId: workerId,
            type: 'booking_auto_cancelled',
            title: 'Booking Auto-Cancelled',
            message: 'A booking you accepted was cancelled because the client did not confirm.',
            relatedId: bookingId,
            relatedType: 'booking',
          );
        }

        debugPrint('🔄 Auto-cancelled booking: $bookingId (unconfirmed)');
      }
    } catch (e) {
      debugPrint('❌ Error in auto-cancel unconfirmed: $e');
    }
  }
}

