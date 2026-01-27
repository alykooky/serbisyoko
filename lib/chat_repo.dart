import 'package:supabase_flutter/supabase_flutter.dart';

class ChatRepo {
  ChatRepo(this.sb);
  final SupabaseClient sb;

  
  Future<String> ensureConversationId(String otherUserId) async {
    final me = sb.auth.currentUser?.id;
    if (me == null) throw Exception('Not signed in');
    if (otherUserId.isEmpty) throw Exception('otherUserId empty');

    final a = (me.compareTo(otherUserId) < 0) ? me : otherUserId;
    final b = (me.compareTo(otherUserId) < 0) ? otherUserId : me;

    final row = await sb
        .from('conversations')
        .upsert({'user_a': a, 'user_b': b}, onConflict: 'user_a,user_b')
        .select('id')
        .single();

    return row['id'] as String;
  }

  Future<void> sendMessage({
    required String conversationId,
    required String toUserId,
    required String content,
  }) async {
    final me = sb.auth.currentUser?.id;
    if (me == null) throw Exception('Not signed in');

    final text = content.trim();
    if (text.isEmpty) return;

    await sb.from('messages').insert({
      'conversation_id': conversationId,
      'sender_id': me,
      'receiver_id': toUserId,
      'content': text,
      'is_read': false,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Stream all messages in a conversation in chronological order.
  Stream<List<Map<String, dynamic>>> streamMessages(String conversationId) {
    return sb
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true);
  }

  /// List all conversations that involve the current user, with last message preview.
  Future<List<Map<String, dynamic>>> listMyConversations() async {
    final me = sb.auth.currentUser?.id;
    if (me == null) return [];

    final convs = await sb
        .from('conversations')
        .select('id,user_a,user_b,created_at')
        .or('user_a.eq.$me,user_b.eq.$me')
        .order('created_at', ascending: false);

    final out = <Map<String, dynamic>>[];
    for (final c in convs as List) {
      final cid = c['id'] as String;
      final last = await sb
          .from('messages')
          .select('content,created_at')
          .eq('conversation_id', cid)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      out.add({
        ...c,
        'last_preview': last?['content'] ?? '',
        'last_at': last?['created_at'],
      });
    }
    return out;
  }

  /// Convenience: fetch user rows for a set of IDs.
  Future<Map<String, Map<String, dynamic>>> fetchUsersByIds(
      List<String> ids) async {
    if (ids.isEmpty) return {};
    final rows =
        await sb.from('users').select('id,name,email').inFilter('id', ids);
    final map = <String, Map<String, dynamic>>{};
    for (final r in rows as List) {
      map[r['id'] as String] = Map<String, dynamic>.from(r);
    }
    return map;
  }
}
