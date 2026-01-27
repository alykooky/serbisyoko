// lib/referral_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';            // <-- for Clipboard
import 'package:share_plus/share_plus.dart';       // <-- for Share.share
import 'package:supabase_flutter/supabase_flutter.dart';

import 'referral_service.dart';                    // <-- your service

class ReferralScreen extends StatefulWidget {
  const ReferralScreen({super.key});

  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  final sb = Supabase.instance.client;

  late final ReferralService svc;

  final TextEditingController _input = TextEditingController();
  bool _loading = true;
  String _code = '—';
  num _balance = 0;

  @override
  void initState() {
    super.initState();
    svc = ReferralService(sb);      // <-- create the service
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final code = await svc.myReferralCode();       // <-- OK
      final bal  = await svc.myWalletBalance();     // <-- OK
      if (!mounted) return;
      setState(() {
        _code = code;
        _balance = bal;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _apply() async {
    final code = _input.text.trim().toUpperCase();
    if (code.isEmpty) return;

    try {
      final res = await svc.applyCode(code); // returns {ok:bool, error:String?}
      if (!mounted) return;

      if (res['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Referral code applied!')),
        );
        _input.clear();
        _load(); // refresh balance (optional)
      } else {
        final err = res['error'] ?? 'Unknown error';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not apply: $err')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFED9121);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Referral program'),
        backgroundColor: accent,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Wallet / balance
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.account_balance_wallet),
                      title: const Text('Wallet balance'),
                      subtitle: Text('₱$_balance'),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Your code + copy & share
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Your referral code',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: SelectableText(
                                  _code,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    letterSpacing: 1.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Copy',
                                icon: const Icon(Icons.copy),
                                onPressed: () async {
                                  await Clipboard.setData(
                                      ClipboardData(text: _code)); // <-- FIX
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Copied to clipboard'),
                                    ),
                                  );
                                },
                              ),
                              IconButton(
                                tooltip: 'Share',
                                icon: const Icon(Icons.share),
                                onPressed: () {
                                  Share.share(
                                    'Join me on SerbisyoKo! Use my code $_code to get ₱50 after your first booking.',
                                  ); // <-- uses share_plus
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Apply a code
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Have a code?',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _input,
                                  textCapitalization: TextCapitalization.characters,
                                  decoration: const InputDecoration(
                                    hintText: 'Enter referral code',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: accent,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: _apply,
                                child: const Text('Apply'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
