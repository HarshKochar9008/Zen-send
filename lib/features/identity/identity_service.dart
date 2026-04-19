import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants.dart';
import '../../core/supabase_config.dart';
import '../../core/utils/short_code_generator.dart';

class UserIdentity {
  final String id;
  final String shortCode;

  const UserIdentity({required this.id, required this.shortCode});
}

class IdentityService {
  static UserIdentity? _cached;
  static const _maxCodeAttempts = 10;

  /// Returns the user's identity.
  /// First launch: anonymous sign-in → generate unique short code → persist.
  /// Subsequent launches: restore from SharedPreferences.
  static Future<UserIdentity> initialize() async {
    if (_cached != null) return _cached!;

    final prefs = await SharedPreferences.getInstance();
    final savedCode = prefs.getString(AppConstants.prefShortCode);
    final savedId = prefs.getString(AppConstants.prefUserDbId);

    if (SupabaseConfig.client.auth.currentSession != null &&
        savedCode != null &&
        savedId != null) {
      _cached = UserIdentity(id: savedId, shortCode: savedCode);
      return _cached!;
    }

    final authResponse =
        await SupabaseConfig.client.auth.signInAnonymously();

    if (authResponse.user == null) {
      throw Exception(
        'Anonymous sign-in failed. '
        'Ensure anonymous auth is enabled in Supabase → Auth → Settings.',
      );
    }

    // Atomic collision handling: INSERT directly; retry on unique violation.
    for (var attempt = 0; attempt < _maxCodeAttempts; attempt++) {
      final code = ShortCodeGenerator.generate();
      try {
        final dbUser = await SupabaseConfig.client
            .from('users')
            .insert({
              'auth_uid': authResponse.user!.id,
              'short_code': code,
            })
            .select()
            .single();

        final userId = dbUser['id'] as String;
        await prefs.setString(AppConstants.prefShortCode, code);
        await prefs.setString(AppConstants.prefUserDbId, userId);

        _cached = UserIdentity(id: userId, shortCode: code);
        return _cached!;
      } on PostgrestException catch (e) {
        // 23505 = unique_violation — short_code already taken
        final isDuplicate = e.code == '23505';
        if (!isDuplicate || attempt == _maxCodeAttempts - 1) rethrow;
      }
    }

    throw Exception(
      'Could not generate a unique short code after $_maxCodeAttempts '
      'attempts. Please restart the app to try again.',
    );
  }

  /// Look up a recipient by their short code. Returns null if not found.
  static Future<Map<String, dynamic>?> findUserByCode(String code) async {
    return await SupabaseConfig.client
        .from('users')
        .select('id, short_code')
        .eq('short_code', code.toUpperCase().trim())
        .maybeSingle();
  }

  static void clearCache() => _cached = null;
}
