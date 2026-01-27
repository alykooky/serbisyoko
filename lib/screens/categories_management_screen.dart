import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CategoriesManagementScreen extends StatefulWidget {
  const CategoriesManagementScreen({super.key});

  @override
  State<CategoriesManagementScreen> createState() => _CategoriesManagementScreenState();
}

class _CategoriesManagementScreenState extends State<CategoriesManagementScreen> with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  static const Color accentColor = Color(0xFFED9121);
  
  // Categories data
  List<Map<String, dynamic>> _categories = [];
  Map<String, List<Map<String, dynamic>>> _categoryServices = {};
  
  // Subcategories data
  Map<String, List<Map<String, dynamic>>> _serviceSubcategories = {};
  
  bool _isLoading = true;
  late TabController _tabController;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() {}); // Rebuild when tab changes
    });
    _loadData();
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
  
  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      await Future.wait([
        _loadCategories(),
        _loadServices(),
        _loadSubcategories(),
      ]);
    } catch (e) {
      debugPrint('Error loading data: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
  
  Future<void> _loadCategories() async {
    try {
      final services = await _supabase
          .from('services')
          .select('category')
          .order('category');
      
      final categories = <String>{};
      for (final service in services) {
        final category = service['category']?.toString();
        if (category != null && category.isNotEmpty) {
          categories.add(category);
        }
      }
      
      setState(() {
        _categories = categories.map((cat) => {'name': cat}).toList()
          ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
      });
    } catch (e) {
      debugPrint('Error loading categories: $e');
    }
  }
  
  Future<void> _loadServices() async {
    try {
      final services = await _supabase
          .from('services')
          .select('id, name, category')
          .order('category')
          .order('name');
      
      final grouped = <String, List<Map<String, dynamic>>>{};
      for (final service in services) {
        final category = service['category']?.toString() ?? 'Other';
        grouped.putIfAbsent(category, () => []).add(service);
      }
      
      setState(() {
        _categoryServices = grouped;
      });
    } catch (e) {
      debugPrint('Error loading services: $e');
    }
  }
  
  Future<void> _loadSubcategories() async {
    try {
      final subs = await _supabase
          .from('service_subcategories')
          .select('id, title, service_name')
          .order('service_name')
          .order('title');
      
      final grouped = <String, List<Map<String, dynamic>>>{};
      for (final sub in subs) {
        final serviceName = sub['service_name']?.toString() ?? 'Unknown';
        grouped.putIfAbsent(serviceName, () => []).add(sub);
      }
      
      setState(() {
        _serviceSubcategories = grouped;
      });
    } catch (e) {
      debugPrint('Error loading subcategories: $e');
      // Table might not exist, that's okay
    }
  }
  
  Future<void> _addCategory() async {
    final nameController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Category'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Category Name',
            hintText: 'e.g., Home Repair',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: accentColor),
            child: const Text('Add', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    
    if (result == true && nameController.text.trim().isNotEmpty) {
      // Categories are created when services are added, so just refresh
      _loadData();
    }
  }
  
  Future<void> _addService(String? category) async {
    final nameController = TextEditingController();
    final categoryController = TextEditingController(text: category ?? '');
    
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Service'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Service Name',
                hintText: 'e.g., Plumber',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: categoryController,
              decoration: const InputDecoration(
                labelText: 'Category',
                hintText: 'e.g., Home Repair',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: accentColor),
            child: const Text('Add', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    
    if (result == true && nameController.text.trim().isNotEmpty) {
      try {
        await _supabase.from('services').insert({
          'name': nameController.text.trim(),
          'category': categoryController.text.trim().isEmpty 
              ? 'Other' 
              : categoryController.text.trim(),
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Service added successfully'),
              backgroundColor: Colors.green,
            ),
          );
          _loadData();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error adding service: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
  
  Future<void> _editService(Map<String, dynamic> service) async {
    final nameController = TextEditingController(text: service['name']?.toString() ?? '');
    final categoryController = TextEditingController(text: service['category']?.toString() ?? '');
    
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Service'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Service Name',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: categoryController,
              decoration: const InputDecoration(
                labelText: 'Category',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: accentColor),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    
    if (result == true && nameController.text.trim().isNotEmpty) {
      try {
        await _supabase.from('services').update({
          'name': nameController.text.trim(),
          'category': categoryController.text.trim().isEmpty 
              ? 'Other' 
              : categoryController.text.trim(),
        }).eq('id', service['id']);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Service updated successfully'),
              backgroundColor: Colors.green,
            ),
          );
          _loadData();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error updating service: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
  
  Future<void> _deleteService(Map<String, dynamic> service) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Service'),
        content: Text('Are you sure you want to delete "${service['name']}"? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      try {
        await _supabase.from('services').delete().eq('id', service['id']);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Service deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
          _loadData();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting service: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
  
  Future<void> _addSubcategory(String serviceName) async {
    final titleController = TextEditingController();
    final priceController = TextEditingController();
    
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add Subcategory for $serviceName'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: 'Subcategory Title',
                hintText: 'e.g., Maintenance',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: priceController,
              decoration: const InputDecoration(
                labelText: 'Default Price (Optional)',
                hintText: '₱ 0',
                prefixText: '₱ ',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: accentColor),
            child: const Text('Add', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    
    if (result == true && titleController.text.trim().isNotEmpty) {
      try {
        await _supabase.from('service_subcategories').insert({
          'service_name': serviceName,
          'title': titleController.text.trim(),
          'default_price': priceController.text.trim().isEmpty 
              ? null 
              : double.tryParse(priceController.text.trim()) ?? 0,
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Subcategory added successfully'),
              backgroundColor: Colors.green,
            ),
          );
          _loadData();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error adding subcategory: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
  
  Future<void> _editSubcategory(Map<String, dynamic> subcategory) async {
    final titleController = TextEditingController(text: subcategory['title']?.toString() ?? '');
    final priceController = TextEditingController(
      text: subcategory['default_price'] != null 
          ? subcategory['default_price'].toString() 
          : '',
    );
    
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Subcategory'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: 'Subcategory Title',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: priceController,
              decoration: const InputDecoration(
                labelText: 'Default Price (Optional)',
                prefixText: '₱ ',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: accentColor),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    
    if (result == true && titleController.text.trim().isNotEmpty) {
      try {
        await _supabase.from('service_subcategories').update({
          'title': titleController.text.trim(),
          'default_price': priceController.text.trim().isEmpty 
              ? null 
              : double.tryParse(priceController.text.trim()),
        }).eq('id', subcategory['id']);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Subcategory updated successfully'),
              backgroundColor: Colors.green,
            ),
          );
          _loadData();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error updating subcategory: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
  
  Future<void> _deleteSubcategory(Map<String, dynamic> subcategory) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Subcategory'),
        content: Text('Are you sure you want to delete "${subcategory['title']}"? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      try {
        await _supabase.from('service_subcategories').delete().eq('id', subcategory['id']);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Subcategory deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
          _loadData();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting subcategory: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Categories & Services'),
        backgroundColor: accentColor,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Categories'),
            Tab(text: 'Subcategories'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: accentColor),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                _buildCategoriesTab(),
                _buildSubcategoriesTab(),
              ],
            ),
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton(
              onPressed: () => _addService(null),
              backgroundColor: accentColor,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
    );
  }
  
  Widget _buildCategoriesTab() {
    if (_categories.isEmpty && _categoryServices.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.category_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No categories yet',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              'Add a service to create a category',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _addService(null),
              icon: const Icon(Icons.add),
              label: const Text('Add Service'),
              style: ElevatedButton.styleFrom(backgroundColor: accentColor),
            ),
          ],
        ),
      );
    }
    
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final category = _categories[index];
          final categoryName = category['name'] as String;
          final services = _categoryServices[categoryName] ?? [];
          
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ExpansionTile(
              leading: const Icon(Icons.category, color: accentColor),
              title: Text(
                categoryName,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text('${services.length} service${services.length == 1 ? '' : 's'}'),
              children: [
                ...services.map((service) {
                  return ListTile(
                    title: Text(service['name']?.toString() ?? 'Unknown'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, size: 20),
                          color: accentColor,
                          onPressed: () => _editService(service),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, size: 20),
                          color: Colors.red,
                          onPressed: () => _deleteService(service),
                        ),
                      ],
                    ),
                  );
                }),
                ListTile(
                  leading: const Icon(Icons.add, color: accentColor),
                  title: const Text('Add Service'),
                  onTap: () => _addService(categoryName),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
  
  Widget _buildSubcategoriesTab() {
    // Get all services for subcategories
    final allServices = <String>{};
    for (final services in _categoryServices.values) {
      for (final service in services) {
        final serviceName = service['name']?.toString();
        if (serviceName != null) {
          allServices.add(serviceName);
        }
      }
    }
    
    if (allServices.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.list_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No services available',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              'Add services first to manage subcategories',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }
    
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: allServices.length,
        itemBuilder: (context, index) {
          final serviceName = allServices.elementAt(index);
          final subcategories = _serviceSubcategories[serviceName] ?? [];
          
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ExpansionTile(
              leading: const Icon(Icons.build, color: accentColor),
              title: Text(
                serviceName,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text('${subcategories.length} subcategor${subcategories.length == 1 ? 'y' : 'ies'}'),
              children: [
                ...subcategories.map((sub) {
                  final price = sub['default_price'];
                  return ListTile(
                    title: Text(sub['title']?.toString() ?? 'Unknown'),
                    subtitle: price != null && price > 0
                        ? Text('Default: ₱${price.toStringAsFixed(0)}')
                        : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, size: 20),
                          color: accentColor,
                          onPressed: () => _editSubcategory(sub),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, size: 20),
                          color: Colors.red,
                          onPressed: () => _deleteSubcategory(sub),
                        ),
                      ],
                    ),
                  );
                }),
                ListTile(
                  leading: const Icon(Icons.add, color: accentColor),
                  title: const Text('Add Subcategory'),
                  onTap: () => _addSubcategory(serviceName),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

