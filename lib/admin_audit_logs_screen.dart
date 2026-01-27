import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'services/admin_audit_service.dart';

class AdminAuditLogsScreen extends StatefulWidget {
  const AdminAuditLogsScreen({super.key});

  @override
  State<AdminAuditLogsScreen> createState() => _AdminAuditLogsScreenState();
}

class _AdminAuditLogsScreenState extends State<AdminAuditLogsScreen> {
  List<Map<String, dynamic>> _auditLogs = [];
  bool _isLoading = true;
  String? _selectedActionType;
  String? _selectedEntityType;
  DateTime? _startDate;
  DateTime? _endDate;

  final List<String> _actionTypes = [
    'All',
    'verification_approved',
    'verification_rejected',
  ];

  final List<String> _entityTypes = [
    'All',
    'verification_request',
    'user',
    'booking',
  ];

  @override
  void initState() {
    super.initState();
    _loadAuditLogs();
  }

  Future<void> _loadAuditLogs() async {
    setState(() => _isLoading = true);
    try {
      // Set end date to end of day if selected
      DateTime? endDate = _endDate;
      if (_endDate != null) {
        endDate = DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59);
      }
      
      // Set start date to beginning of day if selected
      DateTime? startDate = _startDate;
      if (_startDate != null) {
        startDate = DateTime(_startDate!.year, _startDate!.month, _startDate!.day, 0, 0, 0);
      }
      
      final logs = await AdminAuditService.getAuditLogs(
        actionType: _selectedActionType == 'All' ? null : _selectedActionType,
        entityType: _selectedEntityType == 'All' ? null : _selectedEntityType,
        startDate: startDate,
        endDate: endDate,
        limit: 100,
      );
      setState(() {
        _auditLogs = logs;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error loading audit logs: $e'),
              backgroundColor: Colors.red),
        );
      }
      setState(() => _isLoading = false);
    }
  }
  
  Future<void> _selectDateRange() async {
    final now = DateTime.now();
    final firstDate = DateTime(now.year - 1);
    final lastDate = now;
    
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: firstDate,
      lastDate: lastDate,
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFED9121),
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _loadAuditLogs();
    }
  }
  
  void _clearDateFilter() {
    setState(() {
      _startDate = null;
      _endDate = null;
    });
    _loadAuditLogs();
  }

  String _formatActionType(String? actionType) {
    if (actionType == null) return 'Unknown';
    return actionType
        .split('_')
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }

  Color _getActionColor(String? actionType) {
    if (actionType == null) return Colors.grey;
    if (actionType.contains('approved')) return Colors.green;
    if (actionType.contains('rejected'))
      return Colors.red;
    return Colors.blue;
  }

  IconData _getActionIcon(String? actionType) {
    if (actionType == null) return Icons.info;
    if (actionType.contains('approved')) return Icons.check_circle;
    if (actionType.contains('rejected')) return Icons.cancel;
    return Icons.info;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audit Logs'),
        backgroundColor: const Color(0xFFED9121),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAuditLogs,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // Filters
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[100],
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButton<String>(
                        value: _selectedActionType ?? 'All',
                        isExpanded: true,
                        items: _actionTypes.map((type) {
                          return DropdownMenuItem(
                            value: type,
                            child: Text(type == 'All'
                                ? 'All Actions'
                                : _formatActionType(type)),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedActionType = value;
                          });
                          _loadAuditLogs();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButton<String>(
                        value: _selectedEntityType ?? 'All',
                        isExpanded: true,
                        items: _entityTypes.map((type) {
                          return DropdownMenuItem(
                            value: type,
                            child: Text(type == 'All'
                                ? 'All Entities'
                                : type.replaceAll('_', ' ').toUpperCase()),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedEntityType = value;
                          });
                          _loadAuditLogs();
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Date Range Filter
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _selectDateRange,
                        icon: const Icon(Icons.calendar_today, size: 18),
                        label: Text(
                          _startDate != null && _endDate != null
                              ? '${DateFormat('MMM dd, yyyy').format(_startDate!)} - ${DateFormat('MMM dd, yyyy').format(_endDate!)}'
                              : 'Select Date Range',
                          style: const TextStyle(fontSize: 13),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFED9121),
                          side: const BorderSide(color: Color(0xFFED9121)),
                        ),
                      ),
                    ),
                    if (_startDate != null || _endDate != null) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        color: Colors.red,
                        onPressed: _clearDateFilter,
                        tooltip: 'Clear date filter',
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          // Logs List
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Color(0xFFED9121)),
                    ),
                  )
                : _auditLogs.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.description_outlined,
                                size: 64, color: Colors.grey),
                            const SizedBox(height: 16),
                            Text(
                              'No audit logs found',
                              style: TextStyle(
                                  fontSize: 18, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadAuditLogs,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _auditLogs.length,
                          itemBuilder: (context, index) {
                            final log = _auditLogs[index];
                            final actionType = log['action_type']?.toString();
                            final createdAt = log['created_at']?.toString();
                            final adminEmail =
                                log['admin_email']?.toString() ?? 'Unknown';
                            final details =
                                log['details'] as Map<String, dynamic>?;

                            DateTime? dateTime;
                            if (createdAt != null) {
                              try {
                                dateTime = DateTime.parse(createdAt);
                              } catch (e) {
                                // Handle parse error
                              }
                            }

                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: ExpansionTile(
                                leading: CircleAvatar(
                                  backgroundColor: _getActionColor(actionType)
                                      .withOpacity(0.2),
                                  child: Icon(
                                    _getActionIcon(actionType),
                                    color: _getActionColor(actionType),
                                    size: 24,
                                  ),
                                ),
                                title: Text(
                                  _formatActionType(actionType),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    Text('By: $adminEmail'),
                                    if (dateTime != null)
                                      Text(
                                        DateFormat('MMM dd, yyyy • hh:mm a')
                                            .format(dateTime),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                  ],
                                ),
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        _buildDetailRow(
                                            'Entity Type',
                                            log['entity_type']?.toString() ??
                                                'N/A'),
                                        if (log['entity_id'] != null)
                                          _buildDetailRow('Entity ID',
                                              log['entity_id']!.toString()),
                                        if (details != null) ...[
                                          const Divider(height: 24),
                                          const Text(
                                            'Details:',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          ...details.entries.map((entry) {
                                            return _buildDetailRow(
                                              entry.key
                                                  .replaceAll('_', ' ')
                                                  .toUpperCase(),
                                              entry.value?.toString() ?? 'N/A',
                                            );
                                          }),
                                        ],
                                        if (log['ip_address'] != null)
                                          _buildDetailRow('IP Address',
                                              log['ip_address']!.toString()),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
