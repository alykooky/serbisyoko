import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'subcategories.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  final TextEditingController _search = TextEditingController();
  List<Map<String, dynamic>> _services = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  /// ✅ Fetch all services from Supabase
  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final rows = await Supabase.instance.client
          .from('services')
          .select('id, name, category')
          .order('name');

      setState(() {
        _services = (rows as List).cast<Map<String, dynamic>>();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// ✅ Fetch client location from Supabase
  Future<Map<String, dynamic>?> _fetchClientLocation() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return null;

      final data = await Supabase.instance.client
          .from('users')
          .select('latitude, longitude, location_address')
          .eq('id', user.id)
          .maybeSingle();

      return data;
    } catch (e) {
      debugPrint('Error fetching client location: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = const Color(0xFFED9121);
    final String q = _search.text.toLowerCase();
    final items = _services
        .where((s) => s['name'].toString().toLowerCase().contains(q))
        .toList();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: accent,
        title: const Text('Hire a Service Provider',
            style: TextStyle(color: Colors.white)),
        centerTitle: false,
      ),
      body: Column(
        children: [
          // 🔍 Search bar
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.grey[200],
                hintText: 'Search for service or category',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),

          // 🧩 Service grid
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFFED9121)))
                : GridView.builder(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: .95,
                    ),
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final s = items[i];
                      return GestureDetector(
                        onTap: () async {
                          // ✅ Fetch client’s real location before opening
                          final loc = await _fetchClientLocation();
                          if (loc == null ||
                              loc['latitude'] == null ||
                              loc['longitude'] == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Please update your location first in your profile or dashboard.'),
                              ),
                            );
                            return;
                          }

                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => SubcategoriesScreen(
                                service: s,
                                clientLat:
                                    (loc['latitude'] as num?)?.toDouble() ??
                                        0.0,
                                clientLng:
                                    (loc['longitude'] as num?)?.toDouble() ??
                                        0.0,
                                location: loc['location_address'] ??
                                    'Unknown Location',
                              ),
                            ),
                          );
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: const [
                              BoxShadow(blurRadius: 3, color: Colors.black12)
                            ],
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.widgets, color: accent),
                              const SizedBox(height: 6),
                              Text(
                                s['name'] ?? '',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
