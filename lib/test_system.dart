import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TestSystemScreen extends StatefulWidget {
  const TestSystemScreen({super.key});

  @override
  State<TestSystemScreen> createState() => _TestSystemScreenState();
}

class _TestSystemScreenState extends State<TestSystemScreen> {
  List<String> _testResults = [];
  bool _isLoading = false;

  Future<void> _runTests() async {
    setState(() {
      _isLoading = true;
      _testResults.clear();
    });

    try {
      // Test 1: Database Connection
      _addResult('Testing database connection...');
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        _addResult('❌ No authenticated user');
        return;
      }
      _addResult('✅ User authenticated: ${user.email}');

      // Test 2: Users table
      _addResult('Testing users table...');
      final users = await Supabase.instance.client
          .from('users')
          .select('id, name, role')
          .limit(1);
      _addResult('✅ Users table accessible');

      // Test 3: Worker profiles table
      _addResult('Testing worker_profiles table...');
      final profiles = await Supabase.instance.client
          .from('worker_profiles')
          .select('user_id, availability_status')
          .limit(1);
      _addResult('✅ Worker profiles table accessible');

      // Test 4: Bookings table
      _addResult('Testing bookings table...');
      final bookings = await Supabase.instance.client
          .from('bookings')
          .select('id, status')
          .limit(1);
      _addResult('✅ Bookings table accessible');

      // Test 5: Messages table
      _addResult('Testing messages table...');
      final messages = await Supabase.instance.client
          .from('messages')
          .select('id, content')
          .limit(1);
      _addResult('✅ Messages table accessible');

      // Test 6: Ratings table
      _addResult('Testing ratings table...');
      final ratings = await Supabase.instance.client
          .from('ratings')
          .select('id, score')
          .limit(1);
      _addResult('✅ Ratings table accessible');

      // Test 7: Gigs table
      _addResult('Testing gigs table...');
      final gigs = await Supabase.instance.client
          .from('gigs')
          .select('id, title')
          .limit(1);
      _addResult('✅ Gigs table accessible');

      _addResult('🎉 All database tests passed!');

    } catch (e) {
      _addResult('❌ Test failed: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _addResult(String result) {
    setState(() {
      _testResults.add(result);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('System Test'),
        backgroundColor: const Color(0xFFED9121),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ElevatedButton(
              onPressed: _isLoading ? null : _runTests,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFED9121),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isLoading
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                        SizedBox(width: 12),
                        Text('Running Tests...'),
                      ],
                    )
                  : const Text('Run System Tests'),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.builder(
                itemCount: _testResults.length,
                itemBuilder: (context, index) {
                  final result = _testResults[index];
                  final isError = result.startsWith('❌');
                  final isSuccess = result.startsWith('✅');
                  final isInfo = result.startsWith('🎉');

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isError
                          ? Colors.red[50]
                          : isSuccess
                              ? Colors.green[50]
                              : isInfo
                                  ? Colors.blue[50]
                                  : Colors.grey[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isError
                            ? Colors.red[200]!
                            : isSuccess
                                ? Colors.green[200]!
                                : isInfo
                                    ? Colors.blue[200]!
                                    : Colors.grey[200]!,
                      ),
                    ),
                    child: Text(
                      result,
                      style: TextStyle(
                        color: isError
                            ? Colors.red[700]
                            : isSuccess
                                ? Colors.green[700]
                                : isInfo
                                    ? Colors.blue[700]
                                    : Colors.grey[700],
                        fontWeight: isError || isSuccess || isInfo
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}




