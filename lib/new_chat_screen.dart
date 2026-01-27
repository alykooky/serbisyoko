import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'chat_repo.dart';
import 'chat_screen.dart';

class NewChatScreen extends StatefulWidget {
  const NewChatScreen({super.key});

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  final sb = Supabase.instance.client;
  late final ChatRepo repo;

  final TextEditingController _q = TextEditingController();
  bool _loading = true;
  List<Map<String, dynamic>> _users = [];

  @override
  void initState() {
    super.initState();
    repo = ChatRepo(sb);
    _load();
  }

  Future<void> _load([String q = '']) async {
    setState(() => _loading = true);
    try {
      final me = sb.auth.currentUser?.id;
      if (me == null) throw Exception('Not signed in');

      // Build FILTERS first
      var query = sb
          .from('users')
          .select('id,name,email')
          .neq('id', me); // exclude myself

      final term = q.trim();
      if (term.isNotEmpty) {
        // Chain filter on the same builder before order/limit
        query = query.ilike('name', '%$term%');
      }

      // Then ORDER/LIMIT
      final rows = await query.order('name').limit(50);

      if (!mounted) return;
      setState(() => _users = List<Map<String, dynamic>>.from(rows as List));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Load failed: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _startChat(Map<String, dynamic> user) async {
    try {
      final otherId = user['id'] as String;
      final name = (user['name'] as String?) ?? 'User';

      // Create/find conversation up front
      final cid = await repo.ensureConversationId(otherId);

      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            conversationId: cid,        // ✅ pass the conversation
            otherUserId: otherId,       // ✅ use the right variable
            otherUserName: name,        // ✅ use the right variable
          ),
        ),
      );

      if (mounted) Navigator.pop(context); // return to list
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not start chat: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFED9121);

    return Scaffold(
      appBar: AppBar(
        title: const Text('New chat'),
        backgroundColor: accent,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: TextField(
              controller: _q,
              decoration: InputDecoration(
                hintText: 'Search users…',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: _load, // same as (v) => _load(v)
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _users.isEmpty
                    ? const Center(child: Text('No users found'))
                    : ListView.separated(
                        itemCount: _users.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final u = _users[i];
                          final name = (u['name'] as String?) ?? 'User';
                          final email = (u['email'] as String?) ?? '';
                          return ListTile(
                            leading: const CircleAvatar(child: Icon(Icons.person)),
                            title: Text(name),
                            subtitle: Text(email),
                            onTap: () => _startChat(u),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
