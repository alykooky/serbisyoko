// chat_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'chat_repo.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.otherUserId,
    required this.otherUserName,

    /// May be empty when you only know the other user.
    this.conversationId = '',
  });

  final String conversationId; // can be ''
  final String otherUserId;
  final String otherUserName;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final sb = Supabase.instance.client;
  late final ChatRepo repo;

  final TextEditingController _input = TextEditingController();

  String? _conversationId; // becomes non-null after ensure
  Stream<List<Map<String, dynamic>>>? _stream;
  StreamSubscription? _firstEventSub;
  bool _loading = true;
  bool? _isOtherUserAdmin; // Cache admin status
  Map<String, bool> _senderAdminCache = {}; // Cache admin status for each sender

  @override
  void initState() {
    super.initState();
    repo = ChatRepo(sb);
    _checkIfAdmin();
    _bootstrap();
  }

  Future<void> _checkIfAdmin() async {
    try {
      final userData = await sb
          .from('users')
          .select('role')
          .eq('id', widget.otherUserId)
          .maybeSingle();
      
      if (mounted) {
        setState(() {
          _isOtherUserAdmin = (userData?['role']?.toString().toLowerCase() == 'admin');
        });
      }
    } catch (e) {
      debugPrint('Error checking admin status: $e');
    }
  }

  Future<bool> _isUserAdmin(String userId) async {
    if (_senderAdminCache.containsKey(userId)) {
      return _senderAdminCache[userId] ?? false;
    }

    try {
      final userData = await sb
          .from('users')
          .select('role')
          .eq('id', userId)
          .maybeSingle();
      
      final isAdmin = (userData?['role']?.toString().toLowerCase() == 'admin');
      _senderAdminCache[userId] = isAdmin;
      return isAdmin;
    } catch (e) {
      debugPrint('Error checking admin status for $userId: $e');
      return false;
    }
  }

  Future<void> _bootstrap() async {
    try {
      // If we weren't given a conversation id, create/find it now.
      final cid = (widget.conversationId.isNotEmpty)
          ? widget.conversationId
          : await repo.ensureConversationId(widget.otherUserId);

      if (!mounted) return;
      setState(() => _conversationId = cid);

      // Start the stream only when cid is ready.
      _stream = repo.streamMessages(cid);

      // Turn off the spinner after the first event (even if empty).
      _firstEventSub = _stream!.listen((_) {
        if (_loading && mounted) setState(() => _loading = false);
      }, onError: (e) {
        if (mounted) {
          setState(() => _loading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Stream error: $e')),
          );
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open chat: $e')),
      );
    }
  }

  @override
  void dispose() {
    _firstEventSub?.cancel();
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final me = sb.auth.currentUser?.id;
    final text = _input.text.trim();
    if (me == null || text.isEmpty || _conversationId == null) return;

    try {
      await repo.sendMessage(
        conversationId: _conversationId!,
        toUserId: widget.otherUserId,
        content: text,
      );
      _input.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Send failed: $e')),
      );
    }
  }

  String _getDisplayName(String userId, bool isAdmin) {
    if (isAdmin) {
      return 'SerbisyoKo';
    }
    return widget.otherUserName;
  }

  Widget _buildAvatar(String userId, bool isAdmin) {
    if (isAdmin) {
      return CircleAvatar(
        radius: 20,
        backgroundColor: const Color(0xFFED9121),
        backgroundImage: const AssetImage('assets/mascot.png'),
        onBackgroundImageError: (_, __) {
          // If image fails to load, show text
        },
        child: const Icon(Icons.business, color: Colors.white, size: 24),
      );
    }
    return CircleAvatar(
      radius: 20,
      backgroundColor: Colors.grey[300],
      child: Text(
        widget.otherUserName.isNotEmpty
            ? widget.otherUserName[0].toUpperCase()
            : '?',
        style: const TextStyle(color: Colors.grey, fontSize: 16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFED9121);
    final displayName = _isOtherUserAdmin == true 
        ? 'SerbisyoKo' 
        : widget.otherUserName;

    return Scaffold(
      appBar: AppBar(
        leading: _isOtherUserAdmin == true
            ? Padding(
                padding: const EdgeInsets.all(8.0),
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.white,
                  backgroundImage: const AssetImage('assets/mascot.png'),
                  onBackgroundImageError: (_, __) {
                    // If image fails to load
                  },
                  child: const Icon(Icons.business, color: accent, size: 20),
                ),
              )
            : null,
        title: Text(displayName),
        backgroundColor: accent,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: (_conversationId == null || _stream == null)
                ? const Center(child: CircularProgressIndicator())
                : StreamBuilder<List<Map<String, dynamic>>>(
                    stream: _stream!,
                    builder: (context, snap) {
                      if (_loading &&
                          snap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snap.hasError) {
                        return Center(child: Text('Error: ${snap.error}'));
                      }
                      final msgs = snap.data ?? const [];
                      if (msgs.isEmpty) {
                        return const Center(child: Text('Say hi 👋'));
                      }

                      final me = sb.auth.currentUser?.id;
                      return ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: msgs.length,
                        itemBuilder: (_, i) {
                          final m = msgs[i];
                          final senderId = m['sender_id'] as String? ?? '';
                          final mine = senderId == me;
                          
                          return FutureBuilder<bool>(
                            future: mine ? Future.value(false) : _isUserAdmin(senderId),
                            builder: (context, adminSnap) {
                              final senderIsAdmin = adminSnap.data ?? false;
                              
                              return Align(
                                alignment: mine
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: Row(
                                  mainAxisAlignment: mine
                                      ? MainAxisAlignment.end
                                      : MainAxisAlignment.start,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    if (!mine && senderIsAdmin) ...[
                                      _buildAvatar(senderId, true),
                                      const SizedBox(width: 8),
                                    ],
                                    Flexible(
                                      child: Container(
                                        margin: const EdgeInsets.symmetric(vertical: 4),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 8,
                                          horizontal: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          color: mine
                                              ? accent.withOpacity(.12)
                                              : Colors.white,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: mine ? accent : Colors.black12,
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            if (!mine && senderIsAdmin) ...[
                                              Text(
                                                'SerbisyoKo',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                  color: accent,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                            ],
                                            Text(m['content'] ?? ''),
                                          ],
                                        ),
                                      ),
                                    ),
                                    if (mine) ...[
                                      const SizedBox(width: 8),
                                      const CircleAvatar(
                                        radius: 16,
                                        backgroundColor: Color(0xFFED9121),
                                        child: Text(
                                          'You',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: TextField(
                      controller: _input,
                      decoration: const InputDecoration(
                        hintText: 'Message…',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _send,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
