import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class WorkerProfileEditScreen extends StatefulWidget {
  const WorkerProfileEditScreen({super.key});

  @override
  State<WorkerProfileEditScreen> createState() =>
      _WorkerProfileEditScreenState();
}

class _WorkerProfileEditScreenState extends State<WorkerProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _aboutController = TextEditingController();
  final _phoneController = TextEditingController();
  final _hourlyRateController = TextEditingController();
  final _serviceAreaController = TextEditingController();

  bool _isLoading = false;
  bool _isSaving = false;

  String? _profileImageUrl;
  XFile? _selectedImage;
  Uint8List? _webImageBytes;

  Map<String, dynamic>? _userProfile;
  Map<String, dynamic>? _workerProfile;

  static const accent = Color(0xFFED9121);

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _aboutController.dispose();
    _phoneController.dispose();
    _hourlyRateController.dispose();
    _serviceAreaController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final userProfile = await Supabase.instance.client
          .from('users')
          .select('*')
          .eq('id', user.id)
          .single();

      final workerProfile = await Supabase.instance.client
          .from('worker_profiles')
          .select('*')
          .eq('user_id', user.id)
          .maybeSingle();

      setState(() {
        _userProfile = userProfile;
        _workerProfile = workerProfile;

        _aboutController.text = workerProfile?['about'] ?? '';
        _phoneController.text = userProfile['phone'] ?? '';
        _hourlyRateController.text =
            workerProfile?['hourly_rate']?.toString() ?? '';
        _serviceAreaController.text = workerProfile?['service_area'] ?? '';
        _profileImageUrl = workerProfile?['profile_image']?.toString();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading profile: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked != null) {
        if (kIsWeb) {
          _webImageBytes = await picked.readAsBytes();
        }
        setState(() {
          _selectedImage = picked;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
    }
  }

  Future<String?> _uploadProfileImage() async {
    if (_selectedImage == null) return _profileImageUrl;

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return null;

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final ext = _selectedImage!.path.split('.').last;
      final path = 'profile-images/${user.id}_$timestamp.$ext';

      Uint8List bytes;
      if (kIsWeb) {
        bytes = _webImageBytes ?? await _selectedImage!.readAsBytes();
        await Supabase.instance.client.storage
            .from('worker-assets')
            .uploadBinary(path, bytes);
      } else {
        await Supabase.instance.client.storage
            .from('worker-assets')
            .upload(path, File(_selectedImage!.path));
      }

      return Supabase.instance.client.storage
          .from('worker-assets')
          .getPublicUrl(path);
    } catch (e) {
      debugPrint('Error uploading profile image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error uploading image: $e')),
        );
      }
      return null;
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      // Upload profile image if selected
      String? imageUrl = _profileImageUrl;
      if (_selectedImage != null) {
        imageUrl = await _uploadProfileImage();
      }

      // Update worker profile (phone is in users table, not worker_profiles)
      final updates = <String, dynamic>{
        'about': _aboutController.text.trim(),
        'hourly_rate': _hourlyRateController.text.isEmpty
            ? null
            : int.tryParse(_hourlyRateController.text),
        'service_area': _serviceAreaController.text.trim(),
        if (imageUrl != null) 'profile_image': imageUrl,
      };

      await Supabase.instance.client
          .from('worker_profiles')
          .update(updates)
          .eq('user_id', user.id);

      // Update user phone in users table
      if (_phoneController.text.trim().isNotEmpty) {
        await Supabase.instance.client
            .from('users')
            .update({'phone': _phoneController.text.trim()}).eq('id', user.id);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully!')),
        );
        Navigator.pop(context, true); // Return true to indicate success
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving profile: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Edit Profile'),
          backgroundColor: accent,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final displayName = _userProfile?['name'] ?? 'Worker';
    final email = _userProfile?['email'] ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        backgroundColor: accent,
        foregroundColor: Colors.white,
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            )
          else
            TextButton(
              onPressed: _saveProfile,
              child: const Text('Save', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Profile Picture
              Stack(
                children: [
                  CircleAvatar(
                    radius: 60,
                    backgroundColor: accent,
                    backgroundImage: _selectedImage != null
                        ? (kIsWeb
                                ? MemoryImage(_webImageBytes!)
                                : FileImage(File(_selectedImage!.path)))
                            as ImageProvider
                        : (_profileImageUrl != null &&
                                _profileImageUrl!.isNotEmpty)
                            ? NetworkImage(_profileImageUrl!)
                            : null,
                    child: (_selectedImage == null &&
                            (_profileImageUrl == null ||
                                _profileImageUrl!.isEmpty))
                        ? Text(
                            displayName.isNotEmpty
                                ? displayName[0].toUpperCase()
                                : 'W',
                            style: const TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          )
                        : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: CircleAvatar(
                      radius: 20,
                      backgroundColor: accent,
                      child: IconButton(
                        icon: const Icon(Icons.camera_alt,
                            color: Colors.white, size: 20),
                        onPressed: _pickImage,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                displayName,
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              Text(
                email,
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 24),

              // About/Bio
              TextFormField(
                controller: _aboutController,
                decoration: InputDecoration(
                  labelText: 'About / Bio',
                  hintText: 'Tell clients about yourself and your services',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.person_outline),
                ),
                maxLines: 4,
              ),
              const SizedBox(height: 16),

              // Phone
              TextFormField(
                controller: _phoneController,
                decoration: InputDecoration(
                  labelText: 'Phone Number',
                  hintText: '+63 9XX XXX XXXX',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.phone),
                ),
                keyboardType: TextInputType.phone,
                validator: (value) {
                  if (value != null && value.trim().isNotEmpty) {
                    if (value.trim().length < 10) {
                      return 'Please enter a valid phone number';
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Hourly Rate
              TextFormField(
                controller: _hourlyRateController,
                decoration: InputDecoration(
                  labelText: 'Hourly Rate (₱)',
                  hintText: '350',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixText: '₱ ',
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value != null && value.trim().isNotEmpty) {
                    final rate = double.tryParse(value.trim());
                    if (rate == null || rate <= 0) {
                      return 'Please enter a valid hourly rate';
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Service Area
              TextFormField(
                controller: _serviceAreaController,
                decoration: InputDecoration(
                  labelText: 'Service Area',
                  hintText: 'e.g., Metro Manila, Quezon City',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.location_on),
                ),
              ),
              const SizedBox(height: 32),

              // Save Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Save Changes',
                      style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
