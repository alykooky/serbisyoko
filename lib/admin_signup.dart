import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminSignupPage extends StatefulWidget {
  const AdminSignupPage({super.key});

  @override
  _AdminSignupPageState createState() => _AdminSignupPageState();
}

class _AdminSignupPageState extends State<AdminSignupPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final nameController = TextEditingController();

  final supabase = Supabase.instance.client;

  Future<void> _signupAdmin() async {
    try {
      final authResponse = await supabase.auth.signUp(
        email: emailController.text,
        password: passwordController.text,
      );

      final user = authResponse.user;
      if (user != null) {
        await Supabase.instance.client.from('users').insert({
          'id': user.id, // ✅ this is already UUID
          'email': user.email,
          'name': 'Boss Admin',
          'phone': '09123456789',
          'role': 'admin',
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Admin account created!")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Admin Signup")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: "Name")),
            TextField(
                controller: emailController,
                decoration: const InputDecoration(labelText: "Email")),
            TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: "Password")),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _signupAdmin,
              child: const Text("Create Admin Account"),
            ),
          ],
        ),
      ),
    );
  }
}
