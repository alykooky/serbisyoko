import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:characters/characters.dart';
import 'chat_screen.dart';


class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  List<Map<String, dynamic>> _conversations = [];
  bool _isLoading = true;
  String _currentUserId = '';

  String _initialOf(Object? value) {
    final s = (value is String) ? value.trim() : '';
    if (s.isEmpty) return '?';
    final chars = s.characters;
    return chars.isEmpty ? '?' : chars.first.toUpperCase();
  }

  @override
  void initState() {
    super.initState();
    final me = Supabase.instance.client.auth.currentUser;
    _currentUserId = me?.id ?? '';
    _loadConversations();
  }

  Future<void> _loadConversations() async {
    if (_currentUserId.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      final messages = await Supabase.instance.client
          .from('messages')
          .select('''
            sender_id,
            receiver_id,
            created_at,
            content,
            sender:sender_id(name, email),
            receiver:receiver_id(name, email)
          ''')
          .or('sender_id.eq.$_currentUserId,receiver_id.eq.$_currentUserId')
          .order('created_at', ascending: false);

      final Map<String, Map<String, dynamic>> conversations = {};
      for (final message in messages as List) {
        final senderId = message['sender_id'] as String;
        final receiverId = message['receiver_id'] as String;
        final otherUserId = senderId == _currentUserId ? receiverId : senderId;
        final otherUser = senderId == _currentUserId
            ? message['receiver'] as Map<String, dynamic>
            : message['sender'] as Map<String, dynamic>;

        conversations.putIfAbsent(otherUserId, () {
          return {
            'other_user_id': otherUserId,
            'other_user_name': (otherUser['name'] ?? 'User') as String,
            'other_user_email': (otherUser['email'] ?? '') as String,
            'last_message': (message['content'] ?? '') as String,
            'last_message_time': message['created_at'] as String,
            'unread_count': 0,
          };
        });
      }

      setState(() {
        _conversations = conversations.values.toList()
          ..sort((a, b) => (b['last_message_time'] as String)
              .compareTo(a['last_message_time'] as String));
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading conversations: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFED9121);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
        backgroundColor: accent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _conversations.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('No conversations yet',
                          style: TextStyle(fontSize: 18, color: Colors.grey)),
                      SizedBox(height: 8),
                      Text('Wait for someone to message you from a booking',
                          style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _conversations.length,
                  itemBuilder: (context, index) {
                    final c = _conversations[index];
                    final displayName =
                        ((c['other_user_name'] as String?)?.trim().isEmpty ?? true)
                            ? 'User'
                            : (c['other_user_name'] as String).trim();

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: accent,
                        child: Text(
                          _initialOf(displayName),
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                      title: Text(
                        displayName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        (c['last_message'] as String),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text(
                        _formatTime(c['last_message_time'] as String),
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatScreen(
                              otherUserId: c['other_user_id'] as String,
                              otherUserName: displayName,
                              conversationId: '',
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
    );
  }

  String _formatTime(String dateTime) {
    final time = DateTime.tryParse(dateTime);
    if (time == null) return '';
    final diff = DateTime.now().difference(time);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }
}
