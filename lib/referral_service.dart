// lib/referral_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';

class ReferralService {
  ReferralService(this.sb);
  final SupabaseClient sb;

  static const int kBonus = 50; // ₱50

  // -----------------------------
  // CODE & BALANCE
  // -----------------------------

  /// Returns your own referral code (creates one if missing).
  Future<String> myReferralCode() async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) throw 'Not signed in';

    final row = await sb
        .from('referrals')
        .select('code')
        .eq('user_id', uid)
        .maybeSingle();

    if (row != null && (row['code'] as String?)?.isNotEmpty == true) {
      return row['code'] as String;
    }

    // simple, stable generator: SRV-<first 6 of uid>
    final code = 'SRV-${uid.substring(0, 6).toUpperCase()}';

    await sb.from('referrals').upsert(
      {
        'user_id': uid,
        'code': code,
        'referrer_id': null,
        'created_at': DateTime.now().toIso8601String(),
      },
      onConflict: 'user_id',
    );

    return code;
  }

  /// Returns your wallet balance (0 if none yet).
  Future<num> myWalletBalance() async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) throw 'Not signed in';

    final row = await sb
        .from('wallets')
        .select('balance')
        .eq('user_id', uid)
        .maybeSingle();

    return (row?['balance'] as num?) ?? 0;
  }

  // -----------------------------
  // APPLY A FRIEND'S CODE
  // -----------------------------

  /// Apply a referral code I received from someone else.
  /// Returns: {'ok': true} on success; otherwise {'ok': false, 'error': '...'}.
  Future<Map<String, dynamic>> applyCode(String code) async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) throw 'Not signed in';

    final trimmed = code.trim().toUpperCase();
    if (trimmed.isEmpty) {
      return {'ok': false, 'error': 'Empty code'};
    }

    // 1) Ensure *my* referrals row exists and has a non-null code
    //    (prevents NOT NULL violation when user applies before opening their code)
    await myReferralCode();

    // 2) Find owner of the entered code
    final owner = await sb
        .from('referrals')
        .select('user_id')
        .eq('code', trimmed)
        .maybeSingle();

    if (owner == null) return {'ok': false, 'error': 'Code not found'};

    final ownerId = owner['user_id'] as String;
    if (ownerId == uid) {
      return {'ok': false, 'error': 'You cannot apply your own code'};
    }

    // 3) Block duplicate apply if referrer_id is already set
    final mine = await sb
        .from('referrals')
        .select('referrer_id')
        .eq('user_id', uid)
        .maybeSingle();

    if (mine?['referrer_id'] != null) {
      return {'ok': false, 'error': 'Referral code already applied'};
    }

    // 4) Update only referrer_id (no upsert, row now definitely exists with code)
    await sb
        .from('referrals')
        .update({'referrer_id': ownerId})
        .eq('user_id', uid);

    return {'ok': true};
  }

  // -----------------------------
  // AWARD ₱50 AFTER FIRST BOOKING
  // -----------------------------

  /// Award the "first booking" bonus (₱50) to both the **referred user** and
  /// their **referrer**. Safe to call multiple times; it won’t duplicate
  /// because we check for a prior transaction with a unique reason key.
  ///
  /// Call this from your booking flow *after* you consider the booking done
  /// (e.g., in your booking confirmation screen or job completion flow).
  Future<void> awardIfFirstBookingCompleted() async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) throw 'Not signed in';

    // If user wasn’t referred by anyone, nothing to award.
    final referrerId = await _getReferrerForUser(uid);
    if (referrerId == null) return;

    // Use a unique reason to prevent double-awards.
    final myReason = 'first_booking_bonus_$uid';
    final refReason = 'referral_bonus_from_$uid';

    final already = await _hasTransaction(uid, myReason);
    if (already) return; // already rewarded before

    // Credit referred user
    await creditWallet(uid, kBonus, myReason);

    // Credit referrer
    await creditWallet(referrerId, kBonus, refReason);
  }

  // -----------------------------
  // Helpers
  // -----------------------------

  Future<String?> _getReferrerForUser(String userId) async {
    final row = await sb
        .from('referrals')
        .select('referrer_id')
        .eq('user_id', userId)
        .maybeSingle();

    final ref = row?['referrer_id'] as String?;
    return (ref != null && ref.isNotEmpty) ? ref : null;
  }

  Future<bool> _hasTransaction(String userId, String reason) async {
    final row = await sb
        .from('wallet_transactions')
        .select('id')
        .eq('user_id', userId)
        .eq('reason', reason)
        .maybeSingle();

    return row != null;
  }

  /// Increases wallet balance and writes a transaction row.
  /// Creates a wallet row if missing.
  Future<void> creditWallet(
    String userId,
    int amount,
    String reason,
  ) async {
    // Ensure wallet exists
    await sb.from('wallets').upsert(
      {'user_id': userId, 'balance': 0},
      onConflict: 'user_id',
    );

    // Fetch current balance
    final current = await sb
        .from('wallets')
        .select('balance')
        .eq('user_id', userId)
        .single();

    final oldBal = (current['balance'] as num?)?.toInt() ?? 0;
    final newBal = oldBal + amount;

    // Update balance
    await sb
        .from('wallets')
        .update({'balance': newBal})
        .eq('user_id', userId);

    // Record transaction
    await sb.from('wallet_transactions').insert({
      'user_id': userId,
      'amount': amount,
      'reason': reason,
      'created_at': DateTime.now().toIso8601String(),
    });
  }
}
