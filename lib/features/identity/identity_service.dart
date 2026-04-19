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

  static Future<UserIdentity> initialize() async {
    if (_cached != null) return _cached!;

    final prefs = await SharedPreferences.getInstance();
    final savedCode = prefs.getString(AppConstants.prefShortCode);
    final savedId = prefs.getString(AppConstants.prefUserDbId);

    // Try to restore from existing session + saved identity
    if (savedCode != null && savedId != null) {
      final session = SupabaseConfig.client.auth.currentSession;
      if (session != null) {
        await SupabaseConfig.ensureValidSession();
        _cached = UserIdentity(id: savedId, shortCode: savedCode);
        return _cached!;
      }

      // Session expired but identity exists — try to re-authenticate
      try {
        await SupabaseConfig.client.auth.signInAnonymously();
        _cached = UserIdentity(id: savedId, shortCode: savedCode);
        return _cached!;
      } catch (_) {
        // Fall through to full re-provisioning
      }
    }

    // First launch or full re-provisioning
    final authResponse =
        await SupabaseConfig.client.auth.signInAnonymously();

    if (authResponse.user == null) {
      throw AuthFailedException(
        'Anonymous sign-in failed. '
        'Ensure anonymous auth is enabled in Supabase Dashboard '
        '→ Auth → Settings.',
      );
    }

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
        final isDuplicate = e.code == '23505';
        if (!isDuplicate || attempt == _maxCodeAttempts - 1) rethrow;
      }
    }

    throw CodeGenerationException(
      'Could not generate a unique short code after $_maxCodeAttempts '
      'attempts. Please restart the app.',
    );
  }

  static Future<Map<String, dynamic>?> findUserByCode(String code) async {
    await SupabaseConfig.ensureValidSession();
    return await SupabaseConfig.client
        .from('users')
        .select('id, short_code')
        .eq('short_code', code.toUpperCase().trim())
        .maybeSingle();
  }

  static void clearCache() => _cached = null;
}

class AuthFailedException implements Exception {
  final String message;
  AuthFailedException(this.message);
  @override
  String toString() => message;
}

class CodeGenerationException implements Exception {
  final String message;
  CodeGenerationException(this.message);
  @override
  String toString() => message;
}
