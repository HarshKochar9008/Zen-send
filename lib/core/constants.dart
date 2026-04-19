class AppConstants {
  static const supabaseUrl = 'https://ontlldqoqeanaeodlxah.supabase.co';
  static const supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9udGxsZHFvcWVhbmFlb2RseGFoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY0NTM2NjEsImV4cCI6MjA5MjAyOTY2MX0.V7-lRSMu6pSTNBz4IXVKI1hL3D19JjeOFTrcENegGbo';

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
