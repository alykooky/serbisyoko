import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'chat_screen.dart';
import 'new_chat_screen.dart';

class ClientChatsList extends StatefulWidget {
  const ClientChatsList({super.key});

  @override
  State<ClientChatsList> createState() => _ClientChatsListState();
}

class _ClientChatsListState extends State<ClientChatsList> {
  final sb = Supabase.instance.client;

  bool _loading = true;

  /// Rows from `conversations` plus last message preview/time.
  /// Each item contains: id, user_a, user_b, created_at, last_preview, last_at
  List<Map<String, dynamic>> _items = [];

  /// Cache of user info so we can show names without refetching.
  /// key = user_id, value = { id, name, email }
  Map<String, Map<String, dynamic>> _userCache = {};

  // --- NEW: realtime listener so the list auto updates when new messages arrive
  RealtimeChannel? _msgChannel;

  @override
  void initState() {
    super.initState();
    _load();

    // Subscribe to message inserts/updates; refresh the list when anything changes
    _msgChannel = sb
        .channel('public:messages:listener')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (_) {
            if (mounted) _load();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'messages',
          callback: (_) {
            if (mounted) _load();
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _msgChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final me = sb.auth.currentUser?.id;
      if (me == null) throw Exception('Not signed in');

      // 1) Fetch my conversations (either side)
      final convs = await sb
          .from('conversations')
          .select('id,user_a,user_b,created_at')
          .or('user_a.eq.$me,user_b.eq.$me')
          .order('created_at', ascending: false);

      final list = List<Map<String, dynamic>>.from(convs as List);

      // 2) For each conversation, get last message (preview + timestamp)
      final withPreview = <Map<String, dynamic>>[];
      for (final c in list) {
        final cid = c['id'] as String;
        final last = await sb
            .from('messages')
            .select('content,created_at')
            .eq('conversation_id', cid)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();

        withPreview.add({
          ...c,
          'last_preview': last?['content'] ?? '',
          'last_at': last?['created_at'],
        });
      }

      // 3) Build set of the "other user ids" and fetch their names/emails
      final otherIds = <String>{};
      for (final c in withPreview) {
        final ua = c['user_a'] as String;
        final ub = c['user_b'] as String;
        otherIds.add(ua == me ? ub : ua);
      }

      if (otherIds.isNotEmpty) {
        final users = await sb
            .from('users')
            .select('id,name,email')
            .inFilter('id', otherIds.toList()); // NOTE: if your SDK complains, use .in_('id', ...)

        _userCache = {
          for (final u in users as List)
            (u['id'] as String): Map<String, dynamic>.from(u)
        };
      } else {
        _userCache = {};
      }

      if (!mounted) return;
      setState(() => _items = withPreview);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Load failed: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _relativeTime(dynamic isoString) {
    if (isoString == null) return '';
    DateTime? t;
    try {
      t = DateTime.parse(isoString.toString());
    } catch (_) {}
    if (t == null) return '';

    final now = DateTime.now();
    final diff = now.difference(t);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFED9121);
    final me = sb.auth.currentUser?.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
        backgroundColor: accent,
        foregroundColor: Colors.white,
        actions: [
          // Top-right "New chat" button (opens the user picker)
          IconButton(
            tooltip: 'New chat',
            icon: const Icon(Icons.chat),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NewChatScreen()),
              );
              if (mounted) _load(); // refresh after returning
            },
          ),
        ],
      ),

      // Floating “+” to start a new chat as well
      floatingActionButton: FloatingActionButton(
        backgroundColor: accent,
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const NewChatScreen()),
          );
          if (mounted) _load();
        },
        child: const Icon(Icons.add, color: Colors.white),
      ),

      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(child: Text('No conversations yet'))
              : RefreshIndicator(
                  onRefresh: _load,
                  color: accent,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(8),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final c = _items[i];
                      final ua = c['user_a'] as String;
                      final ub = c['user_b'] as String;
                      final otherId = ua == me ? ub : ua;

                      final other = _userCache[otherId];
                      final name = (other?['name'] as String?) ?? 'User';
                      final preview = ((c['last_preview'] ?? '') as String).trim();
                      final when = _relativeTime(c['last_at']);

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: accent.withOpacity(.15),
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: const TextStyle(color: Colors.black87),
                          ),
                        ),
                        title: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis, // nicer on small screens
                        ),
                        subtitle: Text(
                          preview.isEmpty ? 'Start the conversation' : preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Text(
                          when,
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                // If your ChatScreen supports starting without an id,
                                // you can pass only otherUserId/Name.
                                conversationId: c['id'] as String,
                                otherUserId: otherId,
                                otherUserName: name,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
    );
  }
}
