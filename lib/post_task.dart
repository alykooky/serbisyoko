import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PostTaskPage extends StatefulWidget {
  const PostTaskPage({super.key});

  @override
  State<PostTaskPage> createState() => _PostTaskPageState();
}

class _PostTaskPageState extends State<PostTaskPage> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _location = TextEditingController();
  final _price = TextEditingController();

  bool _loading = true;
  List<Map<String, dynamic>> _mine = [];

  final supa = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadMine();
  }

  Future<void> _loadMine() async {
    setState(() => _loading = true);
    try {
      final me = supa.auth.currentUser;
      if (me == null) throw 'Please sign in';

      final rows = await supa
          .from('side_gigs')
          .select('id,title,description,location,price_offer,status,created_at,updated_at')
          .eq('user_id', me.id)
          .order('updated_at', ascending: false);

      setState(() => _mine = List<Map<String, dynamic>>.from(rows));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Load failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _post() async {
    try {
      final me = supa.auth.currentUser;
      if (me == null) throw 'Please sign in';

      final title = _title.text.trim();
      if (title.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Title is required')),
        );
        return;
      }

      final price = int.tryParse(_price.text.trim()) ?? 0;

      await supa.from('side_gigs').insert({
        'user_id': me.id,
        'title': title,
        'description': _desc.text.trim(),
        'location': _location.text.trim(),
        'price_offer': price,
        // status defaults to 'open'
      });

      _title.clear();
      _desc.clear();
      _location.clear();
      _price.clear();
      await _loadMine();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Posted')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Post failed: $e')),
        );
      }
    }
  }

  Future<void> _edit(Map<String, dynamic> gig) async {
    final t = TextEditingController(text: gig['title'] ?? '');
    final d = TextEditingController(text: gig['description'] ?? '');
    final l = TextEditingController(text: gig['location'] ?? '');
    final p = TextEditingController(text: (gig['price_offer'] ?? 0).toString());

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          top: 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Edit Side Gig', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 12),
            TextField(controller: t, decoration: const InputDecoration(labelText: 'Title *')),
            TextField(controller: d, decoration: const InputDecoration(labelText: 'Description'), maxLines: 3),
            TextField(controller: l, decoration: const InputDecoration(labelText: 'Location')),
            TextField(controller: p, decoration: const InputDecoration(labelText: 'Price offer (₱)'), keyboardType: TextInputType.number),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  try {
                    final price = int.tryParse(p.text.trim()) ?? 0;
                    await supa
                        .from('side_gigs')
                        .update({
                          'title': t.text.trim(),
                          'description': d.text.trim(),
                          'location': l.text.trim(),
                          'price_offer': price,
                        })
                        .eq('id', gig['id']);
                    if (mounted) Navigator.pop(ctx);
                    await _loadMine();
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Update failed: $e')),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFED9121), foregroundColor: Colors.white),
                child: const Text('Save'),
              ),
            )
          ],
        ),
      ),
    );
  }

  Future<void> _cancel(String gigId) async {
    try {
      await supa
          .from('side_gigs')
          .update({'status': 'cancelled'})
          .eq('id', gigId);
      await _loadMine();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cancelled')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cancel failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFED9121);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Post a Side Gig'),
        backgroundColor: accent,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Describe your task', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(controller: _title, decoration: const InputDecoration(labelText: 'Title *')),
          TextField(controller: _desc, decoration: const InputDecoration(labelText: 'Description'), maxLines: 3),
          TextField(controller: _location, decoration: const InputDecoration(labelText: 'Location')),
          TextField(controller: _price, decoration: const InputDecoration(labelText: 'Price offer (₱)'), keyboardType: TextInputType.number),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _post,
              style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white),
              child: const Text('Post'),
            ),
          ),
          const SizedBox(height: 16),
          const Text('My side gigs', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
          else if (_mine.isEmpty)
            const Padding(padding: EdgeInsets.all(24), child: Text('No gigs yet'))
          else
            ..._mine.map((g) => Card(
                  child: ListTile(
                    title: Text(g['title'] ?? ''),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if ((g['description'] ?? '').toString().isNotEmpty) Text(g['description']),
                        const SizedBox(height: 4),
                        Text('₱${g['price_offer'] ?? 0} • ${g['location'] ?? '—'}'),
                        Text('Status: ${g['status']}'),
                      ],
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'edit') _edit(g);
                        if (value == 'cancel') _cancel(g['id']);
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'edit', child: Text('Edit')),
                        const PopupMenuItem(value: 'cancel', child: Text('Cancel')),
                      ],
                    ),
                  ),
                )),
        ],
      ),
    );
  }
}
