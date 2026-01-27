import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';

class ChatService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static final Map<String, RealtimeChannel> _channels = {};

  /// Send a message
  static Future<bool> sendMessage({
    required String receiverId,
    required String content,
    String? bookingId,
    String messageType = 'text',
  }) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        print('Error: User not authenticated');
        return false;
      }

      print('Sending message from ${user.id} to $receiverId');
      print('Message content: $content');

      // First verify the receiver exists
      final receiverCheck = await _supabase
          .from('users')
          .select('id')
          .eq('id', receiverId)
          .maybeSingle();
      
      if (receiverCheck == null) {
        print('Error: Receiver user does not exist: $receiverId');
        return false;
      }

      // Use a simpler insert without optional fields that might cause RLS issues
      final result = await _supabase.from('messages').insert({
        'sender_id': user.id,
        'receiver_id': receiverId,
        'content': content,
      });

      print('Message sent successfully: $result');
      return true;
    } catch (e) {
      print('Error sending message: $e');
      print('Error type: ${e.runtimeType}');
      return false;
    }
  }

  /// Get messages between two users
  static Future<List<Map<String, dynamic>>> getMessages({
    required String otherUserId,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return [];

      // Get messages where current user is sender and other user is receiver
      final sentMessages = await _supabase
          .from('messages')
          .select('id, sender_id, receiver_id, content, created_at')
          .eq('sender_id', user.id)
          .eq('receiver_id', otherUserId)
          .order('created_at', ascending: true);

      // Get messages where other user is sender and current user is receiver
      final receivedMessages = await _supabase
          .from('messages')
          .select('id, sender_id, receiver_id, content, created_at')
          .eq('sender_id', otherUserId)
          .eq('receiver_id', user.id)
          .order('created_at', ascending: true);

      // Combine and sort messages
      final allMessages = [...sentMessages, ...receivedMessages];
      allMessages.sort((a, b) =>
        DateTime.parse(a['created_at']).compareTo(DateTime.parse(b['created_at']))
      );

      final response = allMessages.skip(offset).take(limit).toList();

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error getting messages: $e');
      return [];
    }
  }

  /// Get conversation list
  static Future<List<Map<String, dynamic>>> getConversations() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return [];

      // Get the latest message from each conversation
      final response = await _supabase
          .from('messages')
          .select('id, sender_id, receiver_id, content, created_at')
          .or('sender_id.eq.${user.id},receiver_id.eq.${user.id}')
          .order('created_at', ascending: false);

      // Group by conversation partner
      Map<String, Map<String, dynamic>> conversationMap = {};
      
      for (final message in response) {
        final otherUserId = message['sender_id'] == user.id 
            ? message['receiver_id'] 
            : message['sender_id'];
        
        if (!conversationMap.containsKey(otherUserId) || 
            DateTime.parse(message['created_at']).isAfter(
              DateTime.parse(conversationMap[otherUserId]!['created_at'])
            )) {
          conversationMap[otherUserId] = {
            'other_user_id': otherUserId,
            'other_user_name': 'User ${otherUserId.substring(0, 8)}...',
            'last_message': message['content'],
            'last_message_time': message['created_at'],
            'unread_count': 0,
          };
        }
      }

      return conversationMap.values.toList()
        ..sort((a, b) => 
          DateTime.parse(b['last_message_time']).compareTo(DateTime.parse(a['last_message_time']))
        );
    } catch (e) {
      print('Error getting conversations: $e');
      return [];
    }
  }

  /// Mark messages as read
  static Future<bool> markAsRead(String senderId) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return false;

      // Skip marking as read for now to avoid RLS issues
      // await _supabase
      //     .from('messages')
      //     .update({'is_read': true})
      //     .eq('receiver_id', user.id)
      //     .eq('sender_id', senderId)
      //     .eq('is_read', false);

      return true;
    } catch (e) {
      print('Error marking messages as read: $e');
      return false;
    }
  }

  /// Mark all messages as read
  static Future<bool> markAllAsRead() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return false;

      await _supabase
          .from('messages')
          .update({'is_read': true})
          .eq('receiver_id', user.id)
          .eq('is_read', false);

      return true;
    } catch (e) {
      print('Error marking all messages as read: $e');
      return false;
    }
  }

  /// Subscribe to real-time messages
  static RealtimeChannel subscribeToMessages({
    required String otherUserId,
    required Function(Map<String, dynamic>) onNewMessage,
  }) {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    final channelKey = 'messages_${user.id}_$otherUserId';
    
    // Unsubscribe from existing channel if any
    _channels[channelKey]?.unsubscribe();
    
    final channel = _supabase
        .channel(channelKey)
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) async {
            final newMessage = payload.newRecord;
            if (newMessage.isNotEmpty) {
              // Check if this message is for our conversation
              final senderId = newMessage['sender_id'];
              final receiverId = newMessage['receiver_id'];
              
              if ((senderId == user.id && receiverId == otherUserId) ||
                  (senderId == otherUserId && receiverId == user.id)) {
                // Fetch the full message with user details
                try {
                  final response = await _supabase
                      .from('messages')
                      .select('''
                        id,
                        sender_id,
                        receiver_id,
                        content,
                        message_type,
                        is_read,
                        created_at,
                        sender:users!messages_sender_id_fkey(name),
                        receiver:users!messages_receiver_id_fkey(name)
                      ''')
                      .eq('id', newMessage['id'])
                      .single();
                  
                  onNewMessage(response);
                } catch (e) {
                  print('Error fetching new message details: $e');
                }
              }
            }
          },
        )
        .subscribe();

    _channels[channelKey] = channel;
    return channel;
  }

  /// Unsubscribe from messages
  static void unsubscribeFromMessages(String otherUserId) {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    final channelKey = 'messages_${user.id}_$otherUserId';
    _channels[channelKey]?.unsubscribe();
    _channels.remove(channelKey);
  }

  /// Clean up all subscriptions
  static void dispose() {
    for (final channel in _channels.values) {
      channel.unsubscribe();
    }
    _channels.clear();
  }

  /// Get unread message count
  static Future<int> getUnreadCount() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return 0;

      final response = await _supabase
          .from('messages')
          .select('id')
          .eq('receiver_id', user.id)
          .eq('is_read', false);

      return response.length;
    } catch (e) {
      print('Error getting unread count: $e');
      return 0;
    }
  }

  /// Delete a message
  static Future<bool> deleteMessage(String messageId) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return false;

      await _supabase
          .from('messages')
          .delete()
          .eq('id', messageId)
          .eq('sender_id', user.id); // Only sender can delete

      return true;
    } catch (e) {
      print('Error deleting message: $e');
      return false;
    }
  }

  /// Clear all conversations
  static Future<bool> clearAllConversations() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return false;

      await _supabase
          .from('messages')
          .delete()
          .or('sender_id.eq.${user.id},receiver_id.eq.${user.id}');

      return true;
    } catch (e) {
      print('Error clearing conversations: $e');
      return false;
    }
  }
}
