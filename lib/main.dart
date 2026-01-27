import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// --- Screens ---
import 'welcome.dart';
import 'categories.dart';
import 'chat_screen.dart';
import 'booking_form.dart';
import 'smart_matching_results.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://jfglfvvbmqxsmbqetugk.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpmZ2xmdnZibXF4c21icWV0dWdrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDk1NTE3ODgsImV4cCI6MjA2NTEyNzc4OH0.FmpK6IK3-slZMKKHDZ42LZ4RFn8qh5oD0vtEgJn1wVs',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Serbisyo Ko',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color.fromARGB(255, 247, 151, 35),
        ),
        useMaterial3: true,
      ),

      // ROUTE MANAGEMENT
      onGenerateRoute: (settings) {
        // BOOKING FORM
        if (settings.name == '/bookingFormFromProfile') {
          final args = settings.arguments as Map<String, dynamic>?;
          return MaterialPageRoute(
            builder: (_) => BookingFormPage(
              initialService: null,
              workerId: args?['workerId'],
              workerName: args?['workerName'],
              suggestedFee: args?['suggestedFee'],
            ),
          );
        }

        // CHAT SCREEN
        if (settings.name == '/chat') {
          final args = settings.arguments as Map<String, dynamic>;
          return MaterialPageRoute(
            builder: (_) => ChatScreen(
              otherUserId: args['otherUserId'],
              otherUserName: args['otherUserName'],
              conversationId: '',
            ),
          );
        }

        // FIXED SMART MATCHING RESULTS SCREEN
        if (settings.name == '/smartMatchingResults') {
          final args = settings.arguments as Map<String, dynamic>;
          return MaterialPageRoute(
            builder: (_) => SmartMatchingResultsScreen(
              serviceType: args['serviceType'] ?? '',
              clientLat: args['clientLat'] ?? 0.0,
              clientLng: args['clientLng'] ?? 0.0,
              location: args['location'] ?? '',
              budgetMin: args['budgetMin']?.toDouble() ?? 0.0,
              budgetMax: args['budgetMax']?.toDouble() ?? 99999.0,
              preferredStartTime:
                  args['preferredStartTime'] as DateTime? ?? DateTime.now(),
              preferredEndTime: args['preferredEndTime'] as DateTime? ??
                  DateTime.now().add(const Duration(hours: 2)),
              results: args['results'] ?? const [],
            ),
          );
        }

        return null;
      },

      home: const SplashScreen(),
    );
  }
}

// SPLASH SCREEN
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 4), () {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5A122), // your orange color
      body: Stack(
        children: [
          // Center everything vertically
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/icon_loading.png',
                  width: 180, // matches your Figma proportions
                ),
                const SizedBox(height: 2), // small gap like your screenshot
                const Text(
                  'SerbisyoKo',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
