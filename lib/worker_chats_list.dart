import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'chat_repo.dart';
import 'chat_screen.dart';

class WorkerChatsList extends StatefulWidget {
  const WorkerChatsList({super.key});

  @override
  State<WorkerChatsList> createState() => _WorkerChatsListState();
}

class _WorkerChatsListState extends State<WorkerChatsList> {
  final sb = Supabase.instance.client;
  late final ChatRepo repo;

  bool _loading = true;
  List<Map<String, dynamic>> _items = [];
  Map<String, Map<String, dynamic>> _userCache = {};
  

  @override
  void initState() {
    super.initState();
    repo = ChatRepo(sb);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final me = sb.auth.currentUser?.id;
      if (me == null) throw Exception('Not signed in');

      final rows = await repo.listMyConversations();

      // 2) Collect the "other user" ids
      final Set<String> otherIds = <String>{};
      for (final c in rows) {
        final ua = c['user_a'] as String;
        final ub = c['user_b'] as String;
        otherIds.add(ua == me ? ub : ua);
      }

      // 3) Fetch user profiles for those ids
      _userCache = await repo.fetchUsersByIds(otherIds.toList());

      if (mounted) setState(() => _items = rows);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Load failed: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = sb.auth.currentUser?.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
        backgroundColor: const Color(0xFFED9121),
        foregroundColor: Colors.white,
      ),


      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(child: Text('No conversations yet'))
              : RefreshIndicator(
                  onRefresh: _load,
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
                      final preview = (c['last_preview'] ?? '') as String;

                      return ListTile(
                        leading:
                            const CircleAvatar(child: Icon(Icons.person)),
                        title: Text(name),
                        subtitle: Text(
                          preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(
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
