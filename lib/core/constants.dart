class AppConstants {
  static final supabaseUrl = const String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );
  static final supabaseAnonKey = const String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  // Short code alphabet — ambiguous chars excluded (O, 0, I, 1, L)
  static const codeAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  static const codeLength = 6;

  // File limits
  static const maxFileSizeBytes = 1024 * 1024 * 1024; // 1 GB
  static const maxFilesPerTransfer = 20;

  // Transfer TTL
  static const transferTtlHours = 24;

  // Pagination
  static const transfersPageSize = 50;

  // SharedPreferences keys
  static const prefShortCode = 'short_code';
  static const prefUserDbId = 'user_db_id';
}
