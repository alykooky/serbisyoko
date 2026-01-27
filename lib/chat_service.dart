import 'package:supabase_flutter/supabase_flutter.dart';

class ChatService {
  ChatService._();
  static final instance = ChatService._();
  final sb = Supabase.instance.client;

  /// List conversations for the current user via the view
  Future<List<Map<String, dynamic>>> listConversations() async {
    final rows = await sb
        .from('conversations_view')
        .select()
        .order('last_message_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  /// Get or create a conversation id for current user and otherUserId
  Future<String> getOrCreateConversationId(String otherUserId) async {
    final me = sb.auth.currentUser?.id;
    if (me == null) {
      throw 'Not signed in';
    }
    final res = await sb.rpc('get_or_create_conversation', params: {
      'p_a': me,
      'p_b': otherUserId,
    });
    return res as String;
  }

  /// Load messages for a conversation (ascending)
  Future<List<Map<String, dynamic>>> loadMessages(String conversationId) async {
    final rows = await sb
        .from('messages')
        .select('id,sender_id,receiver_id,content,created_at,is_read')
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  /// Send message to otherUserId in a given conversation
  Future<void> sendMessage({
    required String conversationId,
    required String toUserId,
    required String text,
  }) async {
    final me = sb.auth.currentUser!.id;
    await sb.from('messages').insert({
      'conversation_id': conversationId,
      'sender_id': me,
      'receiver_id': toUserId,
      'content': text,
      'message_type': 'text',
      'is_read': false,
    });
  }
}
