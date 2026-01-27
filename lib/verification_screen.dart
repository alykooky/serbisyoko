import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';

class VerificationScreen extends StatefulWidget {
  const VerificationScreen({Key? key}) : super(key: key);

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _aboutController = TextEditingController();
  final _serviceAreaController = TextEditingController();
  final _hourlyRateController = TextEditingController();
  
  bool _isLoading = false;
  bool _isVerified = false;
  
  // Document files
  File? _governmentIdDocument;
  File? _nbiClearanceDocument;
  File? _barangayClearanceDocument;
  File? _tesdaCertificateDocument;
  File? _vehicleRegistrationDocument;
  File? _driverLicenseDocument;
  File? _portfolioDocument;
  
  // Document names for display
  String _governmentIdDocumentName = '';
  String _nbiClearanceDocumentName = '';
  String _barangayClearanceDocumentName = '';
  String _tesdaCertificateDocumentName = '';
  String _vehicleRegistrationDocumentName = '';
  String _driverLicenseDocumentName = '';
  String _portfolioDocumentName = '';
  
  // Service types that require vehicle documents
  List<String> _mobileServices = ['Errands', 'Deliveries', 'Service Visits'];
  String _selectedServiceType = '';

  @override
  void initState() {
    super.initState();
    _loadWorkerProfile();
  }

  Future<void> _loadWorkerProfile() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final response = await Supabase.instance.client
          .from('worker_profiles')
          .select('*')
          .eq('user_id', user.id)
          .single();

      if (response != null) {
        setState(() {
          _aboutController.text = response['about'] ?? '';
          _serviceAreaController.text = response['service_area'] ?? '';
          _hourlyRateController.text = response['hourly_rate']?.toString() ?? '';
          _isVerified = response['is_verified'] ?? false;
          
          // Load existing documents
          final documents = response['documents'] as List<dynamic>? ?? [];
          for (var doc in documents) {
            final docData = doc as Map<String, dynamic>;
            final docType = docData['type'] as String?;
            final docName = docData['name'] as String?;
            
            switch (docType) {
              case 'government_id':
                _governmentIdDocumentName = docName ?? '';
                break;
              case 'nbi_clearance':
                _nbiClearanceDocumentName = docName ?? '';
                break;
              case 'barangay_clearance':
                _barangayClearanceDocumentName = docName ?? '';
                break;
              case 'tesda_certificate':
                _tesdaCertificateDocumentName = docName ?? '';
                break;
              case 'vehicle_registration':
                _vehicleRegistrationDocumentName = docName ?? '';
                break;
              case 'driver_license':
                _driverLicenseDocumentName = docName ?? '';
                break;
              case 'portfolio':
                _portfolioDocumentName = docName ?? '';
                break;
            }
          }
        });
      }
    } catch (e) {
      print('Error loading worker profile: $e');
    }
  }

  Future<void> _pickDocument(String type) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
        allowMultiple: false,
      );

      if (result != null) {
        File file = File(result.files.single.path!);
        String fileName = result.files.single.name;
        
        setState(() {
          switch (type) {
            case 'government_id':
              _governmentIdDocument = file;
              _governmentIdDocumentName = fileName;
              break;
            case 'nbi_clearance':
              _nbiClearanceDocument = file;
              _nbiClearanceDocumentName = fileName;
              break;
            case 'barangay_clearance':
              _barangayClearanceDocument = file;
              _barangayClearanceDocumentName = fileName;
              break;
            case 'tesda_certificate':
              _tesdaCertificateDocument = file;
              _tesdaCertificateDocumentName = fileName;
              break;
            case 'vehicle_registration':
              _vehicleRegistrationDocument = file;
              _vehicleRegistrationDocumentName = fileName;
              break;
            case 'driver_license':
              _driverLicenseDocument = file;
              _driverLicenseDocumentName = fileName;
              break;
            case 'portfolio':
              _portfolioDocument = file;
              _portfolioDocumentName = fileName;
              break;
          }
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error picking file: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<String> _uploadDocument(File file, String type) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final fileName = '${user.id}_${type}_${DateTime.now().millisecondsSinceEpoch}';
      final fileExtension = file.path.split('.').last;
      final fullFileName = '$fileName.$fileExtension';
      
      final fileBytes = await file.readAsBytes();
      
      final response = await Supabase.instance.client.storage
          .from('verification-documents')
          .uploadBinary(fullFileName, fileBytes);

      return response;
    } catch (e) {
      throw Exception('Failed to upload document: $e');
    }
  }

  Future<void> _submitVerification() async {
    if (!_formKey.currentState!.validate()) return;
    
    // Check required documents
    if (_governmentIdDocumentName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Government ID is required'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    if (_nbiClearanceDocumentName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('NBI Clearance is required'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    if (_barangayClearanceDocumentName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Barangay Clearance is required'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    if (_tesdaCertificateDocumentName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('TESDA Certificate is required'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    // Check vehicle documents for mobile services
    if (_mobileServices.contains(_selectedServiceType)) {
      if (_vehicleRegistrationDocumentName.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Vehicle Registration is required for mobile services'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      
      if (_driverLicenseDocumentName.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Driver\'s License is required for mobile services'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }
    
    setState(() {
      _isLoading = true;
    });

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      // Upload documents
      List<Map<String, dynamic>> documents = [];
      
      if (_governmentIdDocument != null) {
        final idPath = await _uploadDocument(_governmentIdDocument!, 'government_id');
        documents.add({
          'type': 'government_id',
          'name': _governmentIdDocumentName,
          'path': idPath,
          'uploaded_at': DateTime.now().toIso8601String(),
        });
      }
      
      if (_nbiClearanceDocument != null) {
        final nbiPath = await _uploadDocument(_nbiClearanceDocument!, 'nbi_clearance');
        documents.add({
          'type': 'nbi_clearance',
          'name': _nbiClearanceDocumentName,
          'path': nbiPath,
          'uploaded_at': DateTime.now().toIso8601String(),
        });
      }
      
      if (_barangayClearanceDocument != null) {
        final barangayPath = await _uploadDocument(_barangayClearanceDocument!, 'barangay_clearance');
        documents.add({
          'type': 'barangay_clearance',
          'name': _barangayClearanceDocumentName,
          'path': barangayPath,
          'uploaded_at': DateTime.now().toIso8601String(),
        });
      }
      
      if (_tesdaCertificateDocument != null) {
        final tesdaPath = await _uploadDocument(_tesdaCertificateDocument!, 'tesda_certificate');
        documents.add({
          'type': 'tesda_certificate',
          'name': _tesdaCertificateDocumentName,
          'path': tesdaPath,
          'uploaded_at': DateTime.now().toIso8601String(),
        });
      }
      
      if (_vehicleRegistrationDocument != null) {
        final vehiclePath = await _uploadDocument(_vehicleRegistrationDocument!, 'vehicle_registration');
        documents.add({
          'type': 'vehicle_registration',
          'name': _vehicleRegistrationDocumentName,
          'path': vehiclePath,
          'uploaded_at': DateTime.now().toIso8601String(),
        });
      }
      
      if (_driverLicenseDocument != null) {
        final driverPath = await _uploadDocument(_driverLicenseDocument!, 'driver_license');
        documents.add({
          'type': 'driver_license',
          'name': _driverLicenseDocumentName,
          'path': driverPath,
          'uploaded_at': DateTime.now().toIso8601String(),
        });
      }
      
      if (_portfolioDocument != null) {
        final portfolioPath = await _uploadDocument(_portfolioDocument!, 'portfolio');
        documents.add({
          'type': 'portfolio',
          'name': _portfolioDocumentName,
          'path': portfolioPath,
          'uploaded_at': DateTime.now().toIso8601String(),
        });
      }

      // Update worker profile
      await Supabase.instance.client
          .from('worker_profiles')
          .upsert({
            'user_id': user.id,
            'about': _aboutController.text.trim(),
            'service_area': _serviceAreaController.text.trim(),
            'hourly_rate': int.tryParse(_hourlyRateController.text) ?? 0,
            'documents': documents,
            'is_verified': false, // Will be verified by admin
            'updated_at': DateTime.now().toIso8601String(),
          });

      // Update user profile
      await Supabase.instance.client
          .from('users')
          .update({
            'name': _aboutController.text.split(' ').first, // Use first word as name
          })
          .eq('id', user.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Verification documents submitted successfully!'),
            backgroundColor: Color(0xFFED9121),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error submitting verification: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildDocumentUpload(String type, String title, String description, String currentFileName, {bool isRequired = false}) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFFED9121),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 12),
            
            if (currentFileName.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green[600], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        currentFileName,
                        style: TextStyle(
                          color: Colors.green[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            
            ElevatedButton.icon(
              onPressed: () => _pickDocument(type),
              icon: const Icon(Icons.upload_file),
              label: Text(currentFileName.isEmpty ? 'Upload Document' : 'Replace Document'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFED9121),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verification'),
        backgroundColor: const Color(0xFFED9121),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFED9121)),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Status Card
                    Card(
                      color: _isVerified ? Colors.green[50] : Colors.orange[50],
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(
                              _isVerified ? Icons.verified : Icons.pending,
                              color: _isVerified ? Colors.green[600] : Colors.orange[600],
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _isVerified ? 'Verified Worker' : 'Verification Pending',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: _isVerified ? Colors.green[700] : Colors.orange[700],
                                    ),
                                  ),
                                  Text(
                                    _isVerified 
                                        ? 'Your account has been verified by our admin team.'
                                        : 'Submit your documents for verification.',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: _isVerified ? Colors.green[600] : Colors.orange[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Profile Information
                    const Text(
                      'Profile Information',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFED9121),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    TextFormField(
                      controller: _aboutController,
                      decoration: const InputDecoration(
                        labelText: 'About You',
                        hintText: 'Tell us about your experience and skills',
                        border: OutlineInputBorder(),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFFED9121)),
                        ),
                      ),
                      maxLines: 3,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please tell us about yourself';
                        }
                        return null;
                      },
                    ),
                    
                    const SizedBox(height: 16),
                    
                    TextFormField(
                      controller: _serviceAreaController,
                      decoration: const InputDecoration(
                        labelText: 'Service Area',
                        hintText: 'e.g., Davao City, Buhangin District',
                        border: OutlineInputBorder(),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFFED9121)),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please specify your service area';
                        }
                        return null;
                      },
                    ),
                    
                    const SizedBox(height: 16),
                    
                    TextFormField(
                      controller: _hourlyRateController,
                      decoration: const InputDecoration(
                        labelText: 'Hourly Rate (PHP)',
                        hintText: 'e.g., 500',
                        border: OutlineInputBorder(),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFFED9121)),
                        ),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please specify your hourly rate';
                        }
                        if (int.tryParse(value) == null) {
                          return 'Please enter a valid number';
                        }
                        return null;
                      },
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Service Type Selection
                    const Text(
                      'Service Type',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFED9121),
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _selectedServiceType.isEmpty ? null : _selectedServiceType,
                      decoration: const InputDecoration(
                        labelText: 'Select your primary service type',
                        border: OutlineInputBorder(),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFFED9121)),
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Plumber', child: Text('Plumber')),
                        DropdownMenuItem(value: 'Electrician', child: Text('Electrician')),
                        DropdownMenuItem(value: 'Aircon Technician', child: Text('Aircon Technician')),
                        DropdownMenuItem(value: 'House Cleaning', child: Text('House Cleaning')),
                        DropdownMenuItem(value: 'Carpentry', child: Text('Carpentry')),
                        DropdownMenuItem(value: 'Errands', child: Text('Errands')),
                        DropdownMenuItem(value: 'Deliveries', child: Text('Deliveries')),
                        DropdownMenuItem(value: 'Service Visits', child: Text('Service Visits')),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedServiceType = value ?? '';
                        });
                      },
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please select your service type';
                        }
                        return null;
                      },
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Document Upload Section
                    const Text(
                      'Required Verification Documents',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFED9121),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Government ID (Required)
                    _buildDocumentUpload(
                      'government_id',
                      'Government ID *',
                      'Upload a clear photo of your valid government ID (Driver\'s License, Passport, National ID, etc.)',
                      _governmentIdDocumentName,
                      isRequired: true,
                    ),
                    
                    // NBI Clearance (Required)
                    _buildDocumentUpload(
                      'nbi_clearance',
                      'NBI Clearance *',
                      'Upload your NBI Clearance document. This will be verified through the official NBI Clearance Verification System.',
                      _nbiClearanceDocumentName,
                      isRequired: true,
                    ),
                    
                    // Barangay Clearance (Required)
                    _buildDocumentUpload(
                      'barangay_clearance',
                      'Barangay Clearance *',
                      'Upload your Barangay Clearance document. This will be verified through local government agencies.',
                      _barangayClearanceDocumentName,
                      isRequired: true,
                    ),
                    
                    // TESDA Certificate (Required)
                    _buildDocumentUpload(
                      'tesda_certificate',
                      'TESDA Certificate *',
                      'Upload your TESDA NC II certificate or other professional certifications. This will be verified using the official TESDA Registry.',
                      _tesdaCertificateDocumentName,
                      isRequired: true,
                    ),
                    
                    // Vehicle Documents (Required for mobile services)
                    if (_mobileServices.contains(_selectedServiceType)) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange[200]!),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info, color: Colors.orange[600], size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Additional documents required for mobile services:',
                                style: TextStyle(
                                  color: Colors.orange[700],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      _buildDocumentUpload(
                        'vehicle_registration',
                        'Vehicle Registration *',
                        'Upload your vehicle or motorcycle registration document.',
                        _vehicleRegistrationDocumentName,
                        isRequired: true,
                      ),
                      
                      _buildDocumentUpload(
                        'driver_license',
                        'Driver\'s License *',
                        'Upload your valid driver\'s license.',
                        _driverLicenseDocumentName,
                        isRequired: true,
                      ),
                    ],
                    
                    // Portfolio (Optional)
                    _buildDocumentUpload(
                      'portfolio',
                      'Portfolio/Work Samples',
                      'Upload photos of your previous work or portfolio (optional but recommended)',
                      _portfolioDocumentName,
                      isRequired: false,
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isVerified ? null : _submitVerification,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFED9121),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator(color: Colors.white)
                            : Text(
                                _isVerified ? 'Already Verified' : 'Submit for Verification',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Info Text
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue[200]!),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info, color: Colors.blue[600], size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Your documents will be reviewed by our admin team within 24-48 hours. You\'ll receive a notification once verified.',
                              style: TextStyle(
                                color: Colors.blue[700],
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  @override
  void dispose() {
    _aboutController.dispose();
    _serviceAreaController.dispose();
    _hourlyRateController.dispose();
    super.dispose();
  }
}
