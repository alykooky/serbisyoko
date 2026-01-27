import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminUserManagement extends StatefulWidget {
  const AdminUserManagement({Key? key}) : super(key: key);

  @override
  State<AdminUserManagement> createState() => _AdminUserManagementState();
}

class _AdminUserManagementState extends State<AdminUserManagement> {
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _selectedRole = 'All';
  String _selectedStatus = 'All';

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    try {
      setState(() {
        _isLoading = true;
      });

      final response = await Supabase.instance.client
          .from('users')
          .select('''
            *,
            worker_profiles!left(
              is_verified,
              verification_status,
              hourly_rate,
              service_area
            )
          ''')
          .order('created_at', ascending: false);

      setState(() {
        _users = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading users: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _updateUserRole(String userId, String newRole) async {
    try {
      await Supabase.instance.client
          .from('users')
          .update({'role': newRole})
          .eq('id', userId);

      await _loadUsers();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('User role updated to $newRole'),
          backgroundColor: const Color(0xFFED9121),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating user role: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  List<Map<String, dynamic>> get _filteredUsers {
    return _users.where((user) {
      final matchesSearch = _searchQuery.isEmpty ||
          user['name']?.toLowerCase().contains(_searchQuery.toLowerCase()) == true ||
          user['email']?.toLowerCase().contains(_searchQuery.toLowerCase()) == true;
      
      final matchesRole = _selectedRole == 'All' || user['role'] == _selectedRole;
      
      final matchesStatus = _selectedStatus == 'All' ||
          (_selectedStatus == 'Verified' && user['worker_profiles']?['is_verified'] == true) ||
          (_selectedStatus == 'Pending' && user['worker_profiles']?['verification_status'] == 'pending') ||
          (_selectedStatus == 'Unverified' && user['worker_profiles']?['is_verified'] == false);

      return matchesSearch && matchesRole && matchesStatus;
    }).toList();
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    final workerProfile = user['worker_profiles'] as Map<String, dynamic>?;
    final isVerified = workerProfile?['is_verified'] == true;
    final verificationStatus = workerProfile?['verification_status'] ?? 'none';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFFED9121),
                  child: Text(
                    (user['name'] ?? 'U').substring(0, 1).toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user['name'] ?? 'Unknown',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        user['email'] ?? '',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        'Joined: ${_formatDate(user['created_at'])}',
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getRoleColor(user['role']).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        user['role'] ?? 'Unknown',
                        style: TextStyle(
                          color: _getRoleColor(user['role']),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (workerProfile != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _getVerificationColor(verificationStatus).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _getVerificationText(verificationStatus),
                          style: TextStyle(
                            color: _getVerificationColor(verificationStatus),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            
            if (workerProfile != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Worker Profile',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('Service Area: ${workerProfile['service_area'] ?? 'Not specified'}'),
                    Text('Hourly Rate: ₱${workerProfile['hourly_rate'] ?? 0}'),
                  ],
                ),
              ),
            ],
            
            const SizedBox(height: 12),
            
            // Action buttons
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: user['role'],
                    decoration: const InputDecoration(
                      labelText: 'Role',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Client', child: Text('Client')),
                      DropdownMenuItem(value: 'Worker', child: Text('Worker')),
                      DropdownMenuItem(value: 'Admin', child: Text('Admin')),
                    ],
                    onChanged: (value) {
                      if (value != null && value != user['role']) {
                        _updateUserRole(user['id'], value);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  onPressed: () => _showUserDetails(user),
                  icon: const Icon(Icons.info_outline),
                  tooltip: 'View Details',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getRoleColor(String? role) {
    switch (role) {
      case 'Admin':
        return Colors.red;
      case 'Worker':
        return Colors.blue;
      case 'Client':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  Color _getVerificationColor(String status) {
    switch (status) {
      case 'approved':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getVerificationText(String status) {
    switch (status) {
      case 'approved':
        return 'Verified';
      case 'pending':
        return 'Pending';
      case 'rejected':
        return 'Rejected';
      default:
        return 'Not Applied';
    }
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return 'Unknown';
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return 'Unknown';
    }
  }

  void _showUserDetails(Map<String, dynamic> user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('User Details - ${user['name']}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('Email', user['email'] ?? 'N/A'),
              _buildDetailRow('Role', user['role'] ?? 'N/A'),
              _buildDetailRow('Phone', user['phone'] ?? 'N/A'),
              _buildDetailRow('Created', _formatDate(user['created_at'])),
              if (user['worker_profiles'] != null) ...[
                const SizedBox(height: 8),
                const Text('Worker Profile:', style: TextStyle(fontWeight: FontWeight.bold)),
                _buildDetailRow('Service Area', user['worker_profiles']['service_area'] ?? 'N/A'),
                _buildDetailRow('Hourly Rate', '₱${user['worker_profiles']['hourly_rate'] ?? 0}'),
                _buildDetailRow('Verification Status', _getVerificationText(user['worker_profiles']['verification_status'])),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('User Management'),
        backgroundColor: const Color(0xFFED9121),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Search and Filter Bar
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Column(
              children: [
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search users...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedRole,
                        decoration: const InputDecoration(
                          labelText: 'Role',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'All', child: Text('All Roles')),
                          DropdownMenuItem(value: 'Client', child: Text('Client')),
                          DropdownMenuItem(value: 'Worker', child: Text('Worker')),
                          DropdownMenuItem(value: 'Admin', child: Text('Admin')),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _selectedRole = value ?? 'All';
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedStatus,
                        decoration: const InputDecoration(
                          labelText: 'Status',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'All', child: Text('All Status')),
                          DropdownMenuItem(value: 'Verified', child: Text('Verified')),
                          DropdownMenuItem(value: 'Pending', child: Text('Pending')),
                          DropdownMenuItem(value: 'Unverified', child: Text('Unverified')),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _selectedStatus = value ?? 'All';
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Users List
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFED9121)),
                    ),
                  )
                : _filteredUsers.isEmpty
                    ? const Center(
                        child: Text('No users found'),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _filteredUsers.length,
                        itemBuilder: (context, index) {
                          return _buildUserCard(_filteredUsers[index]);
                        },
                      ),
          ),
        ],
      ),
    );
  }
}



