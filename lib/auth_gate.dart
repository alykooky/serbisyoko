import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Import your app screens
import 'Dashboard.dart';
import 'welcome.dart';
import 'ServiceProviderDashboard.dart';
import 'admin_dashboard.dart';
import 'complete_profile.dart'; // 🔸 Create this file if not yet

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checkAuthState();
  }

  Future<void> _checkAuthState() async {
    try {
      await Future.delayed(const Duration(milliseconds: 500));

      final session = Supabase.instance.client.auth.currentSession;
      debugPrint(
          '🔐 Auth check - Session: ${session != null ? "exists" : "null"}');

      if (session != null) {
        final user = Supabase.instance.client.auth.currentUser;
        debugPrint('👤 User ID: ${user?.id}');
        debugPrint('📦 Metadata: ${user?.userMetadata}');

        // --- Step 1: Check user_type from metadata ---
        String? role =
            user?.userMetadata?['user_type']?.toString().toLowerCase();
        debugPrint('🧭 Role (metadata): $role');

        // --- Step 2: Fallback to users table if missing ---
        if (role == null || role.isEmpty) {
          try {
            final row = await Supabase.instance.client
                .from('users')
                .select('role')
                .eq('id', user?.id ?? '')
                .maybeSingle();

            role = (row?['role'] as String?)?.toLowerCase();
            debugPrint('🧭 Role (database): $role');
          } catch (e) {
            debugPrint('⚠️ Error fetching role: $e');
          }
        }

        // --- Step 3: Check for first/last name completeness ---
        try {
          final profile = await Supabase.instance.client
              .from('users')
              .select('first_name, last_name')
              .eq('id', user?.id ?? '')
              .maybeSingle();

          final first = profile?['first_name'];
          final last = profile?['last_name'];

          if (first == null ||
              first.toString().trim().isEmpty ||
              last == null ||
              last.toString().trim().isEmpty) {
            debugPrint(
                '🧾 Missing name details → Redirecting to CompleteProfile');
            if (mounted) {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                    builder: (_) => const CompleteProfileScreen()),
                (_) => false,
              );
              return;
            }
          }
        } catch (e) {
          debugPrint('⚠️ Error checking profile completeness: $e');
        }

        // --- Step 4: Decide destination based on role ---
        Widget destination;
        if (role == 'worker') {
          destination = const ServiceProviderDashboard();
          debugPrint('🚀 Navigating to Worker Dashboard');
        } else if (role == 'admin') {
          destination = const AdminDashboard();
          debugPrint('🚀 Navigating to Admin Dashboard');
        } else {
          destination = const DashboardPage(title: 'SerbisyoKo');
          debugPrint('🚀 Navigating to Client Dashboard');
        }

        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => destination),
            (_) => false,
          );
        }
      } else {
        // --- No active session ---
        debugPrint('🚪 No session → Redirecting to Welcome');
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const WelcomeScreen()),
            (_) => false,
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Auth check failed: $e');
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const WelcomeScreen()),
          (_) => false,
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xFFED9121)),
              SizedBox(height: 16),
              Text(
                'Checking your account...',
                style: TextStyle(color: Colors.black54, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    // Fallback (should not show normally)
    return const WelcomeScreen();
  }
}
