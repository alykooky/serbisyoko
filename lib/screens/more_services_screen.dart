import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../subcategories.dart';

class MoreServicesScreen extends StatefulWidget {
  const MoreServicesScreen({super.key});

  @override
  State<MoreServicesScreen> createState() => _MoreServicesScreenState();
}

class _MoreServicesScreenState extends State<MoreServicesScreen> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> services = [];
  bool loading = true;
  double? clientLat;
  double? clientLng;
  String clientLocation = 'Unknown';

  static const Color accentColor = Color(0xFFED9121);

  @override
  void initState() {
    super.initState();
    _fetchClientLocation();
    _fetchServices();
  }

  Future<void> _fetchClientLocation() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final data = await supabase
          .from('users')
          .select('latitude, longitude, location_address')
          .eq('id', user.id)
          .maybeSingle();

      if (data != null && mounted) {
        setState(() {
          clientLat = (data['latitude'] as num?)?.toDouble();
          clientLng = (data['longitude'] as num?)?.toDouble();
          clientLocation = data['location_address']?.toString() ?? 'Unknown';
        });
      }
    } catch (e) {
      debugPrint('Error fetching client location: $e');
    }
  }

  Future<void> _fetchServices() async {
    setState(() => loading = true);
    try {
      final data = await supabase
          .from('services')
          .select('id, name, category')
          .order('category')
          .order('name');

      if (mounted) {
        setState(() {
          services = List<Map<String, dynamic>>.from(data);
          loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching services: $e');
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  void _navigateToService(Map<String, dynamic> service) {
    if (clientLat == null || clientLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please update your location first in your dashboard.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SubcategoriesScreen(
          service: service,
          clientLat: clientLat ?? 0,
          clientLng: clientLng ?? 0,
          location: clientLocation,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: accentColor,
          title: const Text('All Services', style: TextStyle(color: Colors.white)),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: const Center(
          child: CircularProgressIndicator(color: accentColor),
        ),
      );
    }

    // Group services by category
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final service in services) {
      final category = service['category']?.toString() ?? 'Other';
      grouped.putIfAbsent(category, () => []).add(service);
    }

    // Sort categories alphabetically
    final sortedCategories = grouped.keys.toList()..sort();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: accentColor,
        title: const Text('All Services', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: grouped.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.build_outlined, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text(
                      'No services available',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Services will appear here once they are added',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[500],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              itemCount: sortedCategories.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final category = sortedCategories[index];
                final categoryServices = grouped[category]!;

                return ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  iconColor: accentColor,
                  collapsedIconColor: Colors.grey,
                  title: Text(
                    category,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  children: categoryServices.map((service) {
                    final serviceName = service['name']?.toString() ?? 'Service';
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 4,
                      ),
                      title: Text(serviceName),
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: Colors.grey,
                      ),
                      onTap: () => _navigateToService(service),
                    );
                  }).toList(),
                );
              },
            ),
    );
  }
}
