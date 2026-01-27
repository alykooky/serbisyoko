import 'package:flutter/material.dart';
import 'login.dart';
import 'signup.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  static const _accent = Color.fromARGB(255, 243, 153, 44);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Column(
            children: [
              const Spacer(flex: 2),
              const CircleAvatar(
                radius: 80,
                backgroundImage: AssetImage('assets/icon_loading.png'),
                backgroundColor: Colors.transparent,
              ),
              const SizedBox(height: 1),
              RichText(
                text: const TextSpan(
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
                  children: [
                    TextSpan(
                        text: 'Serbisyo', style: TextStyle(color: _accent)),
                    TextSpan(
                        text: 'Ko',
                        style:
                            TextStyle(color: Color.fromARGB(255, 12, 12, 12))),
                  ],
                ),
              ),
              const SizedBox(height: 15),
              const Text("Let's get started!",
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color.fromARGB(255, 22, 22, 22))),
              const SizedBox(height: 3),
              const Text('Trusted Services, Anytime You Need Them',
                  style: TextStyle(
                      fontSize: 13, color: Color.fromARGB(255, 22, 22, 22))),
              const Spacer(flex: 3),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accent,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28)),
                        ),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const SignInScreen()),
                        ),
                        child: const Text('Log in',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: _accent, width: 2),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28)),
                        ),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const SignUpScreen()),
                        ),
                        child: const Text('Sign up',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: _accent)),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}
