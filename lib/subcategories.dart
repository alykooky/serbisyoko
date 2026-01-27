import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// NEW import: client form screen
import '../client_request_form.dart';

class SubcategoriesScreen extends StatefulWidget {
  final Map<String, dynamic> service;
  final double clientLat;
  final double clientLng;
  final String location;

  const SubcategoriesScreen({
    super.key,
    required this.service,
    required this.clientLat,
    required this.clientLng,
    required this.location,
  });

  @override
  State<SubcategoriesScreen> createState() => _SubcategoriesScreenState();
}

class _SubcategoriesScreenState extends State<SubcategoriesScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _subs = [];

  @override
  void initState() {
    super.initState();
    _fetchSubcategories();
  }

  /// Fetch subcategories from Supabase or fallback to static list.
  Future<void> _fetchSubcategories() async {
    final supa = Supabase.instance.client;
    final serviceName = widget.service['name']?.toString() ?? '';

    setState(() => _loading = true);

    try {
      final data = await supa
          .from('service_subcategories')
          .select('id, title')
          .eq('service_name', serviceName);

      if (data is List && data.isNotEmpty) {
        _subs = List<Map<String, dynamic>>.from(data);
      } else {
        _subs = _generateStaticSubcategories(serviceName);
      }
    } catch (e) {
      debugPrint("Error fetching subcategories: $e");
      _subs = _generateStaticSubcategories(serviceName);
    }

    setState(() => _loading = false);
  }

  /// Static fallback if subcategories are not stored in Supabase.
  List<Map<String, dynamic>> _generateStaticSubcategories(String serviceName) {
    final name = serviceName.toLowerCase();
    List<String> list = [];

    if (name.contains('electric')) {
      list = ['General Electrician', 'Inspection', 'Installation', 'Repair'];
    } else if (name.contains('plumb')) {
      list = ['Pipe Repair', 'Drain Cleaning', 'Installation', 'Maintenance'];
    } else if (name.contains('aircon')) {
      list = ['Installation', 'Repair', 'Maintenance'];
    } else if (name.contains('clean')) {
      list = ['House Cleaning', 'Office Cleaning', 'Deep Cleaning'];
    } else if (name.contains('repair')) {
      list = ['Appliances', 'Gadgets', 'Furniture'];
    } else {
      list = ['General', 'Inspection', 'Repair'];
    }

    return list.map((s) => {'title': s}).toList();
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFED9121);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: accent,
        title: Text(
          widget.service['name'] ?? 'Service',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.orange),
            )
          : ListView.separated(
              itemCount: _subs.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final sub = _subs[i];
                final subTitle = sub['title'].toString();

                return ListTile(
                  title: Text(subTitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    // Combine main service + subcategory
                    final fullServiceName =
                        "${widget.service['name']} - $subTitle";

                    // → Go to new Client Request Form
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ClientServiceRequestForm(
                          serviceType: fullServiceName,
                          clientLat: widget.clientLat,
                          clientLng: widget.clientLng,
                          location: widget.location,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
