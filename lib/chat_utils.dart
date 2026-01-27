import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// Reuse an existing conversation id if the two users already talked,
/// otherwise return a fresh UUID.
Future<String> getOrCreateConversationId(String otherUserId) async {
  final sb = Supabase.instance.client;
  final me = sb.auth.currentUser!;
  final existing = await sb
      .from('messages')
      .select('conversation_id')
      .or('and(sender_id.eq.${me.id},receiver_id.eq.$otherUserId),and(sender_id.eq.$otherUserId,receiver_id.eq.${me.id})')
      .limit(1)
      .maybeSingle();

  if (existing != null && (existing['conversation_id'] as String?)?.isNotEmpty == true) {
    return existing['conversation_id'] as String;
  }
  return const Uuid().v4();
}
