import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_audit_logs_screen.dart';
import 'screens/categories_management_screen.dart';

class AdminSettings extends StatefulWidget {
  const AdminSettings({Key? key}) : super(key: key);

  @override
  State<AdminSettings> createState() => _AdminSettingsState();
}

class _AdminSettingsState extends State<AdminSettings> {
  bool _isLoading = true;
  bool _isSaving = false;
  Map<String, dynamic> _settings = {};
  final _formKey = GlobalKey<FormState>();

  // Form controllers
  final _platformNameController = TextEditingController();
  final _supportEmailController = TextEditingController();
  final _verificationDaysController = TextEditingController();
  final _maxJobsPerDayController = TextEditingController();
  final _maxPendingJobsController = TextEditingController();
  final _minHoursBeforeCancellationController = TextEditingController();
  final _maintenanceMessageController = TextEditingController();

  // Lists for cancellation reasons
  final List<String> _cancellationReasons = [
    'Emergency',
    'Incomplete client information',
    'Safety concern',
    'Double booking',
    'Weather conditions',
    'Health issue',
    'Other',
  ];
  Set<String> _selectedCancellationReasons = {};

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      setState(() {
        _isLoading = true;
      });

      // TODO: Load from database table 'admin_settings' when created
      // For now, use defaults
      final defaultSettings = {
        'platform_name': 'SerbisyoKo',
        'support_email': 'support@serbisyoko.com',
        'verification_review_days': 3,
        'auto_approve_workers': false,
        'max_jobs_per_day': 5,
        'max_pending_jobs': 3,
        'min_hours_before_cancellation': 2,
        'allowed_cancellation_reasons': [
          'Emergency',
          'Incomplete client information',
          'Safety concern',
          'Double booking',
          'Other'
        ],
        'require_phone_verification': true,
        'enable_notifications': true,
        'maintenance_mode': false,
        'maintenance_message':
            'We are currently performing maintenance. Please check back soon.',
      };

      setState(() {
        _settings = defaultSettings;
        _platformNameController.text = _settings['platform_name'] ?? '';
        _supportEmailController.text = _settings['support_email'] ?? '';
        _verificationDaysController.text =
            (_settings['verification_review_days'] ?? 3).toString();
        _maxJobsPerDayController.text =
            (_settings['max_jobs_per_day'] ?? 5).toString();
        _maxPendingJobsController.text =
            (_settings['max_pending_jobs'] ?? 3).toString();
        _minHoursBeforeCancellationController.text =
            (_settings['min_hours_before_cancellation'] ?? 2).toString();
        _maintenanceMessageController.text =
            _settings['maintenance_message'] ?? '';
        _selectedCancellationReasons =
            Set<String>.from(_settings['allowed_cancellation_reasons'] ?? []);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading settings: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      // Update settings map
      setState(() {
        _settings = {
          'platform_name': _platformNameController.text.trim(),
          'support_email': _supportEmailController.text.trim(),
          'verification_review_days':
              int.parse(_verificationDaysController.text),
          'auto_approve_workers': _settings['auto_approve_workers'] ?? false,
          'max_jobs_per_day': int.parse(_maxJobsPerDayController.text),
          'max_pending_jobs': int.parse(_maxPendingJobsController.text),
          'min_hours_before_cancellation':
              int.parse(_minHoursBeforeCancellationController.text),
          'allowed_cancellation_reasons': _selectedCancellationReasons.toList(),
          'require_phone_verification':
              _settings['require_phone_verification'] ?? true,
          'enable_notifications': _settings['enable_notifications'] ?? true,
          'maintenance_mode': _settings['maintenance_mode'] ?? false,
          'maintenance_message': _maintenanceMessageController.text.trim(),
        };
      });

      // TODO: Save to database table 'admin_settings' when created
      // For now, just show success message
      await Future.delayed(
          const Duration(milliseconds: 500)); // Simulate save delay

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Settings saved successfully'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving settings: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _resetToDefaults() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Settings'),
        content: const Text(
          'Are you sure you want to reset all settings to default values? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      _loadSettings();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Settings reset to defaults'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 16),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFED9121), size: 24),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFFED9121),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? helperText,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    bool enabled = true,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        border: const OutlineInputBorder(),
        enabled: enabled,
      ),
      keyboardType: keyboardType ?? TextInputType.text,
      validator: validator,
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    Color? activeColor,
  }) {
    return SwitchListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: onChanged,
      activeColor: activeColor ?? const Color(0xFFED9121),
    );
  }

  Widget _buildChipSelector({
    required String title,
    required String subtitle,
    required List<String> options,
    required Set<String> selected,
    required Function(Set<String>) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((reason) {
            final isSelected = selected.contains(reason);
            return FilterChip(
              label: Text(reason),
              selected: isSelected,
              onSelected: (shouldSelect) {
                final newSelection = Set<String>.from(selected);
                if (shouldSelect) {
                  newSelection.add(reason);
                } else {
                  newSelection.remove(reason);
                }
                onChanged(newSelection);
              },
              selectedColor: const Color(0xFFED9121).withOpacity(0.2),
              checkmarkColor: const Color(0xFFED9121),
            );
          }).toList(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFED9121);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Settings'),
        backgroundColor: accent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFED9121)),
              ),
            )
          : Form(
              key: _formKey,
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // GENERAL SETTINGS
                          _buildSectionHeader(
                              'GENERAL SETTINGS', Icons.settings),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  _buildTextField(
                                    controller: _platformNameController,
                                    label: 'Platform Name',
                                    validator: (value) {
                                      if (value == null ||
                                          value.trim().isEmpty) {
                                        return 'Platform name is required';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  _buildTextField(
                                    controller: _supportEmailController,
                                    label: 'Support Email',
                                    keyboardType: TextInputType.emailAddress,
                                    validator: (value) {
                                      if (value == null ||
                                          value.trim().isEmpty) {
                                        return 'Support email is required';
                                      }
                                      if (!value.contains('@') ||
                                          !value.contains('.')) {
                                        return 'Please enter a valid email address';
                                      }
                                      return null;
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // VERIFICATION SETTINGS
                          _buildSectionHeader(
                              'VERIFICATION SETTINGS', Icons.verified_user),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  _buildTextField(
                                    controller: _verificationDaysController,
                                    label: 'Verification Review Days',
                                    helperText:
                                        'Number of days to review verification documents',
                                    keyboardType: TextInputType.number,
                                    validator: (value) {
                                      if (value == null ||
                                          value.trim().isEmpty) {
                                        return 'Review days is required';
                                      }
                                      final days = int.tryParse(value);
                                      if (days == null || days < 1) {
                                        return 'Please enter a valid number (min: 1)';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 8),
                                  _buildSwitchTile(
                                    title: 'Auto-approve Workers',
                                    subtitle:
                                        'Automatically approve workers with complete documents',
                                    value: _settings['auto_approve_workers'] ??
                                        false,
                                    onChanged: (value) {
                                      setState(() {
                                        _settings['auto_approve_workers'] =
                                            value;
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // WORKER ACTIVITY RULES
                          _buildSectionHeader(
                              'WORKER ACTIVITY RULES', Icons.work),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  _buildTextField(
                                    controller: _maxJobsPerDayController,
                                    label: 'Max Jobs Per Worker Per Day',
                                    helperText:
                                        'Maximum number of jobs a worker can accept per day',
                                    keyboardType: TextInputType.number,
                                    validator: (value) {
                                      if (value == null ||
                                          value.trim().isEmpty) {
                                        return 'Max jobs per day is required';
                                      }
                                      final max = int.tryParse(value);
                                      if (max == null || max < 1) {
                                        return 'Please enter a valid number (min: 1)';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  _buildTextField(
                                    controller: _maxPendingJobsController,
                                    label: 'Max Pending Jobs Per Worker',
                                    helperText:
                                        'Maximum number of pending jobs a worker can have',
                                    keyboardType: TextInputType.number,
                                    validator: (value) {
                                      if (value == null ||
                                          value.trim().isEmpty) {
                                        return 'Max pending jobs is required';
                                      }
                                      final max = int.tryParse(value);
                                      if (max == null || max < 1) {
                                        return 'Please enter a valid number (min: 1)';
                                      }
                                      return null;
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // BOOKING & CANCELLATION RULES
                          _buildSectionHeader(
                              'BOOKING & CANCELLATION RULES', Icons.event_busy),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  _buildTextField(
                                    controller:
                                        _minHoursBeforeCancellationController,
                                    label: 'Minimum Hours Before Cancellation',
                                    helperText:
                                        'Minimum hours before scheduled time to allow cancellation',
                                    keyboardType: TextInputType.number,
                                    validator: (value) {
                                      if (value == null ||
                                          value.trim().isEmpty) {
                                        return 'Minimum hours is required';
                                      }
                                      final hours = int.tryParse(value);
                                      if (hours == null || hours < 0) {
                                        return 'Please enter a valid number (min: 0)';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  _buildChipSelector(
                                    title: 'Allowed Cancellation Reasons',
                                    subtitle:
                                        'Select reasons that workers can use when cancelling bookings',
                                    options: _cancellationReasons,
                                    selected: _selectedCancellationReasons,
                                    onChanged: (newSelection) {
                                      setState(() {
                                        _selectedCancellationReasons =
                                            newSelection;
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // SECURITY SETTINGS
                          _buildSectionHeader(
                              'SECURITY SETTINGS', Icons.security),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: _buildSwitchTile(
                                title: 'Require Phone Verification',
                                subtitle:
                                    'Users must verify their phone number to use the platform',
                                value:
                                    _settings['require_phone_verification'] ??
                                        true,
                                onChanged: (value) {
                                  setState(() {
                                    _settings['require_phone_verification'] =
                                        value;
                                  });
                                },
                              ),
                            ),
                          ),

                          // CATEGORIES & SERVICES MANAGEMENT
                          _buildSectionHeader(
                              'CATEGORIES & SERVICES', Icons.category),
                          Card(
                            child: ListTile(
                              leading: const Icon(Icons.settings_applications,
                                  color: Color(0xFFED9121)),
                              title: const Text(
                                  'Manage Categories & Subcategories'),
                              subtitle: const Text(
                                  'Add, edit, or delete service categories and subcategories'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const CategoriesManagementScreen(),
                                  ),
                                );
                              },
                            ),
                          ),

                          // SYSTEM SETTINGS
                          _buildSectionHeader('SYSTEM SETTINGS', Icons.build),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  _buildSwitchTile(
                                    title: 'Enable Notifications',
                                    subtitle:
                                        'Send notifications for important events and updates',
                                    value: _settings['enable_notifications'] ??
                                        true,
                                    onChanged: (value) {
                                      setState(() {
                                        _settings['enable_notifications'] =
                                            value;
                                      });
                                    },
                                  ),
                                  const Divider(height: 32),
                                  _buildSwitchTile(
                                    title: 'Maintenance Mode',
                                    subtitle:
                                        'Temporarily disable platform access for maintenance',
                                    value:
                                        _settings['maintenance_mode'] ?? false,
                                    onChanged: (value) {
                                      setState(() {
                                        _settings['maintenance_mode'] = value;
                                      });
                                    },
                                    activeColor: Colors.red,
                                  ),
                                  if (_settings['maintenance_mode'] ==
                                      true) ...[
                                    const SizedBox(height: 16),
                                    _buildTextField(
                                      controller: _maintenanceMessageController,
                                      label: 'Maintenance Mode Message',
                                      helperText:
                                          'Message to display when maintenance mode is enabled',
                                      keyboardType: TextInputType.multiline,
                                      validator: (value) {
                                        if ((_settings['maintenance_mode'] ??
                                                false) &&
                                            (value == null ||
                                                value.trim().isEmpty)) {
                                          return 'Maintenance message is required when maintenance mode is enabled';
                                        }
                                        return null;
                                      },
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Security Notice
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.orange[50],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.orange[200]!),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline,
                                    color: Colors.orange[700], size: 24),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Changes to these settings will affect all users. Please review carefully before saving.',
                                    style: TextStyle(
                                      color: Colors.orange[700],
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(
                              height: 100), // Space for action buttons
                        ],
                      ),
                    ),
                  ),

                  // ACTIONS - Fixed at bottom
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, -2),
                        ),
                      ],
                    ),
                    child: SafeArea(
                      child: Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isSaving ? null : _saveSettings,
                              icon: _isSaving
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                                Colors.white),
                                      ),
                                    )
                                  : const Icon(Icons.save),
                              label: Text(
                                  _isSaving ? 'Saving...' : 'Save Settings'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: accent,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _isSaving ? null : _resetToDefaults,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Reset to Defaults'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                side: const BorderSide(color: Colors.red),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  @override
  void dispose() {
    _platformNameController.dispose();
    _supportEmailController.dispose();
    _verificationDaysController.dispose();
    _maxJobsPerDayController.dispose();
    _maxPendingJobsController.dispose();
    _minHoursBeforeCancellationController.dispose();
    _maintenanceMessageController.dispose();
    super.dispose();
  }
}
