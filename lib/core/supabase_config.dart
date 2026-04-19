import 'package:supabase_flutter/supabase_flutter.dart';
import 'constants.dart';

/// Call this once in main() before runApp()
Future<void> initSupabase() async {
  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    anonKey: AppConstants.supabaseAnonKey,
  );
}

/// Shortcut used throughout the app: SupabaseConfig.client
class SupabaseConfig {
  static SupabaseClient get client => Supabase.instance.client;
}
