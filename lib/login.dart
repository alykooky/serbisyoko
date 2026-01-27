import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'signup.dart';
import 'Dashboard.dart';
import 'ServiceProviderDashboard.dart';
import 'admin_dashboard.dart';
import 'admin_verification_dashboard.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool isLoading = false;
  bool _obscurePassword = true;

  static const Color accentColor = Color(0xFFED9121);

  Future<void> _signIn() async {
    setState(() => isLoading = true);

    try {
      final email = emailController.text.trim();
      final password = passwordController.text.trim();

      if (email.isEmpty || password.isEmpty) {
        _showSnackBar('Please enter email and password.');
        return;
      }

      // 🧹 Step 0: Clear any previous (Arnold) session
      await Supabase.instance.client.auth.signOut();

      // ✅ Step 1: Authenticate user
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final user = response.user;
      if (user == null) {
        _showSnackBar('Invalid login credentials.');
        return;
      }

      print('✅ Logged in as ${user.email} | ID: ${user.id}');

      // ✅ Step 2: Continue with your existing logic
      final adminData = await Supabase.instance.client
          .from('admins')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (adminData != null) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminVerificationDashboard()),
        );
        return;
      }

      if (user.email == "luigi@gmail.com") {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminVerificationDashboard()),
        );
        return;
      }

      var userData = await Supabase.instance.client
          .from('users')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (userData == null) {
        await Supabase.instance.client.from('users').insert({
          'id': user.id, // ✅ important! link with auth.users
          'email': user.email,
          'role': 'Client',
        });

        userData = {
          'email': user.email,
          'role': 'Client',
        };
      }

      final role = userData['role'].toString().trim().toLowerCase();

      if (!mounted) return;
      if (role == 'worker') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const ServiceProviderDashboard(),
          ),
        );
      } else if (role == 'client') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (_) => const DashboardPage(title: 'SerbisyoKo')),
        );
      } else if (role == 'admin') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminVerificationDashboard()),
        );
      } else {
        _showSnackBar('Unknown role: $role');
      }
    } on AuthException catch (e) {
      _showSnackBar('Login failed: ${e.message}');
    } on PostgrestException catch (e) {
      _showSnackBar('Database error: ${e.message}');
    } catch (e) {
      _showSnackBar('Unexpected error: $e');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _handleForgotPassword() async {
    final email = emailController.text.trim();

    if (email.isEmpty) {
      // Show dialog to enter email
      final TextEditingController resetEmailController =
          TextEditingController();
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Reset Password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                  'Enter your email address to receive a password reset link.'),
              const SizedBox(height: 16),
              TextField(
                controller: resetEmailController,
                decoration: InputDecoration(
                  labelText: 'Email',
                  hintText: 'Enter your email',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.email_outlined),
                ),
                keyboardType: TextInputType.emailAddress,
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
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
              ),
              child: const Text('Send Reset Link',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );

      if (result == true && resetEmailController.text.trim().isNotEmpty) {
        await _sendPasswordReset(resetEmailController.text.trim());
      }
    } else {
      // Use existing email from field
      await _sendPasswordReset(email);
    }
  }

  Future<void> _sendPasswordReset(String email) async {
    try {
      setState(() => isLoading = true);

      await Supabase.instance.client.auth.resetPasswordForEmail(
        email,
        redirectTo:
            null, // You can add a redirect URL if you have a custom reset page
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password reset email sent! Please check your inbox.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error sending reset email: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Widget _socialButton(String label, String asset, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 40),
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          foregroundColor: Colors.black,
          backgroundColor: Colors.white,
          minimumSize: const Size.fromHeight(48),
          side: const BorderSide(color: Colors.black12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        icon: Image.asset(asset, width: 24, height: 24),
        label: Text(label),
        onPressed: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Header with overlapping mascot leaning on the card
            SizedBox(
              height: 200,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFFED9121), Color(0xFFF5A64A)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ),
                  const Positioned(
                    top: 65,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Text(
                        'Login',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: -30,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Image.asset('assets/icon_login.png', height: 140),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Login form
            Container(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  )
                ],
              ),
              child: Column(
                children: [
                  TextField(
                    controller: emailController,
                    decoration: InputDecoration(
                      prefixIcon:
                          const Icon(Icons.email_outlined, color: accentColor),
                      hintText: 'Enter your email',
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide:
                            const BorderSide(color: accentColor, width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      prefixIcon:
                          const Icon(Icons.lock_outline, color: accentColor),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: Colors.grey[600],
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                      hintText: 'Enter your password',
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide:
                            const BorderSide(color: accentColor, width: 2),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: isLoading ? null : _handleForgotPassword,
                      child: const Text(
                        'Forgot your password?',
                        style: TextStyle(color: accentColor),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: isLoading ? null : _signIn,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFED9121),
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            'Login',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("Don't have an account? "),
                      InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const SignUpScreen()),
                          );
                        },
                        child: const Text(
                          'Sign up',
                          style: TextStyle(
                            color: Color(0xFFED9121),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Social login buttons
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Row(
                children: [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('OR'),
                  ),
                  Expanded(child: Divider()),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _socialButton('Sign in with Google', 'assets/google.png', () {
              Supabase.instance.client.auth
                  .signInWithOAuth(OAuthProvider.google);
            }),
            //_socialButton('Sign in with Apple', 'assets/apple.png', () {
            // Supabase.instance.client.auth
            //   .signInWithOAuth(OAuthProvider.apple);
            // }),
            // _socialButton('Sign in with Facebook', 'assets/facebook.png', () {
            // Supabase.instance.client.auth
            //    .signInWithOAuth(OAuthProvider.facebook);
            // }),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}
