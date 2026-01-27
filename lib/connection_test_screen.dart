import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ConnectionTestScreen extends StatefulWidget {
  const ConnectionTestScreen({super.key});

  @override
  State<ConnectionTestScreen> createState() => _ConnectionTestScreenState();
}

class _ConnectionTestScreenState extends State<ConnectionTestScreen> {
  String _status = 'Press the button to test Supabase connection';

  Future<void> _testConnection() async {
    setState(() {
      _status = 'Checking connection...';
    });

    try {
      // Simple test query (replace with a real table if you have one)
      final result =
          await Supabase.instance.client.from('profiles').select().limit(1);
      setState(() {
        _status =
            '✅ Connection successful!\nFound ${result.length} row(s) in "profiles" table.';
      });
    } catch (error) {
      setState(() {
        _status = '❌ Connection failed:\n$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connection Test'),
        backgroundColor: const Color(0xFFED9121),
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _status,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _testConnection,
                icon: const Icon(Icons.wifi),
                label: const Text('Run Test'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFED9121),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
