import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;

const String supabaseUrl = 'https://jfglfvvbmqxsmbqetugk.supabase.co';
const String supabaseAnonKey =
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpmZ2xmdnZibXF4c21icWV0dWdrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDk1NTE3ODgsImV4cCI6MjA2NTEyNzc4OH0.FmpK6IK3-slZMKKHDZ42LZ4RFn8qh5oD0vtEgJn1wVs';

final supabase = Supabase.instance.client;

class VerificationProcessScreen extends StatefulWidget {
  const VerificationProcessScreen({super.key});

  @override
  State<VerificationProcessScreen> createState() =>
      _VerificationProcessScreenState();
}

class _VerificationProcessScreenState extends State<VerificationProcessScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _dobController = TextEditingController();
  final _referralCodeController = TextEditingController();

  XFile? _idPhoto;
  Uint8List? _webImageBytes;
  final List<XFile> _workPhotos = [];

  PlatformFile? _certificateFile;
  PlatformFile? _barangayClearanceFile;

  PlatformFile? _nbiFile;
  PlatformFile? _tesdaFile;
  String? _nbiUploadedUrl;
  String? _tesdaUploadedUrl;
  bool _nbiDone = false;
  bool _tesdaDone = false;

  PlatformFile? _videoIntroFile;
  XFile? _videoIntro;

  bool _isLoading = false;
  final accent = const Color(0xFFED9121);

  // File/image picking and upload helpers
  Future<void> _pickIdPhoto() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked != null) {
        if (kIsWeb) {
          _webImageBytes = await picked.readAsBytes();
        }
        setState(() => _idPhoto = picked);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Photo selected.')));
      }
    } catch (e) {
      debugPrint('Error picking ID photo: $e');
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick photo: $e')));
    }
  }

  Future<void> _pickWorkPhotos() async {
    try {
      final picker = ImagePicker();
      final files = await picker.pickMultiImage();
      if (files.isNotEmpty) {
        setState(() => _workPhotos.addAll(files));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${files.length} work photos added.')),
        );
      }
    } catch (e) {
      debugPrint('Error picking work photos: $e');
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick work photos: $e')));
    }
  }

  Future<void> _pickFile(
    void Function(PlatformFile?) onPicked,
    List<String> exts,
  ) async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: exts,
        withData: true,
      );
      if (res != null && res.files.isNotEmpty) {
        onPicked(res.files.single);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${res.files.single.name} selected.')),
        );
      }
    } catch (e) {
      debugPrint('Error picking file: $e');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to pick file: $e')));
    }
  }

  Future<void> _pickVideoIntro() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.video,
        withData: true,
      );
      if (res != null && res.files.isNotEmpty) {
        setState(() {
          _videoIntroFile = res.files.single;
          _videoIntro = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_videoIntroFile!.name} selected.')),
        );
      }
    } catch (e) {
      debugPrint('Error picking video intro: $e');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to pick video intro: $e')));
    }
  }

  Future<String?> _uploadPlatformFile(
      PlatformFile file, String bucket, String folder) async {
    try {
      final ext =
          file.extension ?? (file.name.contains('.') ? file.name.split('.').last : 'bin');
      final path = '$folder/${DateTime.now().millisecondsSinceEpoch}.$ext';
      if (file.bytes != null) {
        await supabase.storage.from(bucket).uploadBinary(path, file.bytes!);
      } else if (file.path != null) {
        await supabase.storage.from(bucket).upload(path, File(file.path!));
      } else {
        throw Exception('No bytes or path for ${file.name}');
      }
      return supabase.storage.from(bucket).getPublicUrl(path);
    } catch (e) {
      debugPrint('Upload PlatformFile error: $e');
      return null;
    }
  }

  Future<String?> _uploadXFile(
      XFile x, String bucket, String folder, String fallbackExt) async {
    try {
      String ext = fallbackExt;
      if (!kIsWeb && x.path.contains('.')) ext = x.path.split('.').last;
      final path = '$folder/${DateTime.now().millisecondsSinceEpoch}.$ext';
      if (kIsWeb) {
        await supabase.storage
            .from(bucket)
            .uploadBinary(path, await x.readAsBytes());
      } else {
        await supabase.storage.from(bucket).upload(path, File(x.path));
      }
      return supabase.storage.from(bucket).getPublicUrl(path);
    } catch (e) {
      debugPrint('Upload XFile error: $e');
      return null;
    }
  }

  // Upload NBI and TESDA files - specialized uploaders
  Future<void> _uploadNbi() async {
    await _pickFile((f) => _nbiFile = f, ['pdf', 'jpg', 'png', 'jpeg']);
    if (_nbiFile == null) return;
    final url = await _uploadPlatformFile(_nbiFile!, 'verification-files', 'nbi-clearances');
    if (url != null) {
      setState(() {
        _nbiUploadedUrl = url;
        _nbiDone = true;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('NBI Clearance uploaded.')),
        );
      }
    }
  }

  Future<void> _uploadTesda() async {
    await _pickFile((f) => _tesdaFile = f, ['pdf', 'jpg', 'png', 'jpeg']);
    if (_tesdaFile == null) return;
    final url = await _uploadPlatformFile(_tesdaFile!, 'verification-files', 'tesda-certs');
    if (url != null) {
      setState(() {
        _tesdaUploadedUrl = url;
        _tesdaDone = true;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('TESDA certificate uploaded.')),
        );
      }
    }
  }

  // Submission: Update or insert verification request; sync worker_profile verification_status
  Future<void> _submitVerification() async {
    if (!_formKey.currentState!.validate()) return;
    if (_idPhoto == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please upload a verification photo.')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final client = Supabase.instance.client;
      final authUser = client.auth.currentUser ?? client.auth.currentSession?.user;
      if (authUser == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You must be logged in to submit.')),
        );
        setState(() => _isLoading = false);
        return;
      }
      final uid = authUser.id;

      final idPhotoUrl =
          await _uploadXFile(_idPhoto!, 'verification-files', 'id-photos', 'jpg');
      if (idPhotoUrl == null) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error uploading ID photo.')),
        );
        return;
      }

      final workPhotoUrls = <String>[];
      for (final x in _workPhotos) {
        final url =
            await _uploadXFile(x, 'verification-files', 'work-photos', 'jpg');
        if (url != null) workPhotoUrls.add(url);
      }

      String? certUrl;
      if (_certificateFile != null) {
        certUrl = await _uploadPlatformFile(
            _certificateFile!, 'verification-files', 'certificates');
      }

      String? clearanceUrl;
      if (_barangayClearanceFile != null) {
        clearanceUrl = await _uploadPlatformFile(
            _barangayClearanceFile!, 'verification-files', 'clearances');
      }

      String? videoUrl;
      if (_videoIntroFile != null) {
        videoUrl = await _uploadPlatformFile(
            _videoIntroFile!, 'verification-files', 'video-intros');
      } else if (_videoIntro != null) {
        videoUrl = await _uploadXFile(
            _videoIntro!, 'verification-files', 'video-intros', 'mp4');
      }

      // Check for existing row & update or insert accordingly
      final existingRequest = await client
          .from('verification_requests')
          .select('id')
          .eq('user_id', uid)
          .maybeSingle();

      final verificationData = {
        'full_name': _fullNameController.text.trim(),
        'date_of_birth': _dobController.text.trim(),
        'verification_photo_url': idPhotoUrl,
        'work_photo_urls': workPhotoUrls,
        'certificate_url': certUrl,
        'barangay_clearance_url': clearanceUrl,
        'nbi_clearance_url': _nbiUploadedUrl,
        'tesda_url': _tesdaUploadedUrl,
        'video_intro_url': videoUrl,
        'referral_code': _referralCodeController.text.isEmpty ? null : _referralCodeController.text,
        'status': 'pending',
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (existingRequest != null && existingRequest['id'] != null) {
        await client
            .from('verification_requests')
            .update(verificationData)
            .eq('id', existingRequest['id']);
      } else {
        await client
            .from('verification_requests')
            .insert({'user_id': uid, ...verificationData});
      }

      // Update worker_profiles verification_status accordingly
      await client
          .from('worker_profiles')
          .update({
            'verification_status': 'pending',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('user_id', uid);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verification submitted successfully!')),
      );
      Navigator.pop(context);
    } catch (e) {
      debugPrint('Submit error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Submission failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Build method: widget tree for the whole screen
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text('Verification Process', style: TextStyle(color: Colors.white)),
        backgroundColor: accent,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _textField('Full Name', 'Enter your full name', _fullNameController,
                      validator: (v) => v!.isEmpty ? 'Full name is required' : null),
                  _dateField('Date of Birth', 'Select your date of birth', _dobController,
                      validator: (v) => v!.isEmpty ? 'Date of birth is required' : null),
                  const SizedBox(height: 16),

                  // --- Upload Verification Photo (required)
                  const Text('Verification Photo (Required)',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Container(
                    height: 200,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _idPhoto == null
                            ? Colors.red.shade200
                            : Colors.green.shade200,
                        width: 2,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: _idPhoto == null
                        ? const Text('Upload a photo for verification')
                        : kIsWeb
                            ? Image.memory(_webImageBytes!,
                                fit: BoxFit.cover, width: double.infinity)
                            : Image.file(File(_idPhoto!.path),
                                fit: BoxFit.cover, width: double.infinity),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _pickIdPhoto,
                    icon: const Icon(Icons.image),
                    label: const Text('Upload from Gallery'),
                  ),

                  // --- Work Photos (optional)
                  const SizedBox(height: 16),
                  const Text('Show Your Skills (Optional)',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _pickWorkPhotos,
                    icon: const Icon(Icons.photo),
                    label: const Text('Upload Work Photos'),
                  ),

                  // --- NBI Clearance
                  const SizedBox(height: 16),
                  const Text('NBI Clearance',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _uploadNbi,
                    icon: const Icon(Icons.verified_user),
                    label: Text(_nbiDone
                        ? 'NBI Clearance Uploaded'
                        : 'Upload NBI Clearance'),
                  ),

                  // --- TESDA Certificate
                  const SizedBox(height: 16),
                  const Text('TESDA',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _uploadTesda,
                    icon: const Icon(Icons.school),
                    label:
                        Text(_tesdaDone ? 'TESDA Certificate Uploaded' : 'Upload TESDA'),
                  ),

                  // --- Certifications (optional)
                  const SizedBox(height: 16),
                  const Text('Certifications (Optional)',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () => _pickFile(
                      (f) => setState(() => _certificateFile = f),
                      ['pdf', 'jpg', 'png'],
                    ),
                    icon: const Icon(Icons.file_present),
                    label: Text(_certificateFile?.name ?? 'Upload Certificate'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                    ),
                  ),

                  // --- Referral / Barangay Clearance / Video Intro
                  const SizedBox(height: 16),
                  const Text('Referral / Barangay Endorsement (Optional)',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  _textField('Referral Code', 'Enter your referral code',
                      _referralCodeController),
                  OutlinedButton.icon(
                    onPressed: _pickVideoIntro,
                    icon: const Icon(Icons.video_camera_back_outlined),
                    label: Text(_videoIntroFile?.name ??
                        (_videoIntro == null ? 'Upload Video Intro' : 'Video selected')),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _pickFile(
                      (f) => setState(() => _barangayClearanceFile = f),
                      ['pdf', 'jpg', 'png'],
                    ),
                    icon: const Icon(Icons.home_work_outlined),
                    label: Text(
                        _barangayClearanceFile?.name ?? 'Upload Barangay Clearance'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                    ),
                  ),

                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _submitVerification,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Submit Documents'),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _textField(String label, String hint, TextEditingController c,
      {String? Function(String?)? validator}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextFormField(
        controller: c,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  Widget _dateField(String label, String hint, TextEditingController c,
      {String? Function(String?)? validator}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextFormField(
        controller: c,
        validator: validator,
        readOnly: true,
        onTap: () => _selectDate(context, c),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          suffixIcon: const Icon(Icons.calendar_today),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  Future<void> _selectDate(
      BuildContext context, TextEditingController controller) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      controller.text =
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Verification App',
      theme: ThemeData(primarySwatch: Colors.deepOrange),
      home: const VerificationProcessScreen(),
    );
  }
}