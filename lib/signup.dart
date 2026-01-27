import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'Dashboard.dart';
import 'login.dart';
import 'ServiceProviderDashboard.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final firstNameController = TextEditingController();
  final lastNameController = TextEditingController();
  final emailController = TextEditingController();
  final phoneController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  bool isLoading = false;
  bool isClient = true; // ✅ Default role Client
  bool agreedToTerms = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  
  static const Color accentColor = Color(0xFFED9121);

  Future<void> _signUp() async {
    if (!agreedToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Palihug og agree sa Terms and Conditions')),
      );
      return;
    }

    if (passwordController.text != confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Dili pareho ang password ug confirm password')),
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      final email = emailController.text.trim();
      final password = passwordController.text.trim();

      // ✅ Sign up sa supabase.auth
      final response = await Supabase.instance.client.auth.signUp(
        email: email,
        password: password,
      );

      final user = response.user;
      if (user == null) throw 'Walay user na-create.';

      // ✅ I-insert sa users table with first_name, last_name, full_name, and name
      final firstName = firstNameController.text.trim();
      final lastName = lastNameController.text.trim();
      final fullName = "$firstName $lastName";

      await Supabase.instance.client.from('users').insert({
        'id': user.id, // para match sa auth.users
        'email': email,
        'first_name': firstName,
        'last_name': lastName,
        'full_name': fullName,
        'name': fullName, // Set 'name' to full_name for consistency
        'phone': phoneController.text.trim(),
        'role': isClient ? 'Client' : 'Worker',
      });

      // NEW: For Workers only, insert into worker_profiles and verification_requests to appear in unverified
      if (!isClient) {
        // Insert into worker_profiles
        await Supabase.instance.client.from('worker_profiles').insert({
          'user_id': user.id,
          'verification_status': 'requested',
          'is_verified': false,
        });

        // Insert into verification_requests with status 'requested'
        await Supabase.instance.client.from('verification_requests').insert({
          'user_id': user.id,
          'full_name': fullName,
          'date_of_birth': null,
          'status': 'requested',
          'created_at': DateTime.now().toIso8601String(),
          'verification_photo_url': null,
          'work_photo_urls': [],
          'certificate_url': null,
          'barangay_clearance_url': null,
          'nbi_clearance_url': null,
          'tesda_url': null,
          'video_intro_url': null,
          'referral_code': null,
        });
      }
      
      print('Inserted verification request for user: ${user.id}, status: requested');

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Successful ang pag-sign up!')),
      );

      // ✅ Redirect base sa role
      if (isClient) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const DashboardPage(title: 'SerbisyoKo'),
          ),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const ServiceProviderDashboard(),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  Widget buildInputField({
    required String hint,
    required IconData icon,
    required TextEditingController controller,
    bool obscure = false,
    bool isPassword = false,
    VoidCallback? onToggleVisibility,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        decoration: InputDecoration(
          hintText: hint,
          filled: true,
          fillColor: Colors.grey[100],
          prefixIcon: Icon(icon, color: accentColor),
          suffixIcon: isPassword
              ? IconButton(
                  icon: Icon(
                    obscure ? Icons.visibility_off : Icons.visibility,
                    color: Colors.grey[600],
                  ),
                  onPressed: onToggleVisibility,
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: BorderSide(color: accentColor, width: 2),
          ),
        ),
      ),
    );
  }

  Widget buildSocialIcon(String assetPath, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: CircleAvatar(
        backgroundColor: Colors.black12,
        radius: 24,
        child: Image.asset(assetPath, height: 24, width: 24),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Text(
                    'Sign up',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              buildInputField(
                hint: 'Enter your first name',
                icon: Icons.person,
                controller: firstNameController,
              ),
              buildInputField(
                hint: 'Enter your last name',
                icon: Icons.person_outline,
                controller: lastNameController,
              ),
              buildInputField(
                hint: 'Enter your email',
                icon: Icons.email,
                controller: emailController,
              ),
              buildInputField(
                hint: 'Enter your phone number',
                icon: Icons.phone,
                controller: phoneController,
              ),
              buildInputField(
                hint: 'Enter your password',
                icon: Icons.lock,
                controller: passwordController,
                obscure: _obscurePassword,
                isPassword: true,
                onToggleVisibility: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              ),
              buildInputField(
                hint: 'Confirm your password',
                icon: Icons.lock_outline,
                controller: confirmPasswordController,
                obscure: _obscureConfirmPassword,
                isPassword: true,
                onToggleVisibility: () {
                  setState(() {
                    _obscureConfirmPassword = !_obscureConfirmPassword;
                  });
                },
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: const Text('Are you?', style: TextStyle(fontSize: 14)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              isClient ? accentColor : Colors.white,
                          foregroundColor:
                              isClient ? Colors.white : accentColor,
                          side: const BorderSide(color: accentColor),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        onPressed: () => setState(() => isClient = true),
                        child: const Text('Client'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              isClient ? Colors.white : accentColor,
                          foregroundColor:
                              isClient ? accentColor : Colors.white,
                          side: const BorderSide(color: accentColor),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        onPressed: () => setState(() => isClient = false),
                        child: const Text('Worker'),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Checkbox(
                      value: agreedToTerms,
                      onChanged: (val) =>
                          setState(() => agreedToTerms = val ?? false),
                      activeColor: accentColor,
                    ),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          text: 'I agree to the ',
                          children: [
                            TextSpan(
                              text: 'Terms and Conditions',
                              style: const TextStyle(color: accentColor),
                            ),
                            const TextSpan(
                                text: ' as set out by the user agreement.'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ElevatedButton(
                  onPressed: isLoading ? null : _signUp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Sign up', style: TextStyle(fontSize: 16, color: Colors.white)),
                ),
              ),
              const SizedBox(height: 16),
              const Row(
                children: [
                  Expanded(child: Divider(indent: 24, endIndent: 12)),
                  Text('OR'),
                  Expanded(child: Divider(indent: 12, endIndent: 24)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  buildSocialIcon('assets/google.png', () {}),
                ],
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SignInScreen()),
                ),
                child: Text.rich(
                  TextSpan(
                    text: "Already have an account? ",
                    children: [
                      TextSpan(
                        text: "Login",
                        style: const TextStyle(color: accentColor),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}