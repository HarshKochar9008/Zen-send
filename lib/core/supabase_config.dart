import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'constants.dart';

Future<void> initSupabase() async {
  if (AppConstants.supabaseUrl.isEmpty || AppConstants.supabaseAnonKey.isEmpty) {
    throw StateError(
      'Missing Supabase config. Pass --dart-define=SUPABASE_URL=... '
      'and --dart-define=SUPABASE_ANON_KEY=...',
    );
  }
  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    anonKey: AppConstants.supabaseAnonKey,
  );
}

class SupabaseConfig {
  static SupabaseClient get client => Supabase.instance.client;

  static StreamSubscription<AuthState>? _authSub;

  /// Listens for token-expired events and refreshes the session automatically.
  static void startAuthListener() {
    _authSub?.cancel();
    _authSub = client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.tokenRefreshed) {
        // Token was refreshed — nothing to do, SDK handles it.
      }
    });
  }

  static void stopAuthListener() {
    _authSub?.cancel();
    _authSub = null;
  }

  /// Ensures we have a valid session, refreshing if needed.
  static Future<void> ensureValidSession() async {
    final session = client.auth.currentSession;
    if (session == null) return;

    final expiresAt = session.expiresAt;
    if (expiresAt == null) return;

    final expiryDate =
        DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000, isUtc: true);
    final now = DateTime.now().toUtc();

    // Refresh if token expires within 60 seconds
    if (expiryDate.difference(now).inSeconds < 60) {
      await client.auth.refreshSession();
    }
  }
}
