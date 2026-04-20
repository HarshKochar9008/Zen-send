import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConstants {
  static String _cleanEnvValue(String value) {
    final trimmed = value.trim();
    if (trimmed.length >= 2) {
      final startsWithSingle = trimmed.startsWith("'");
      final endsWithSingle = trimmed.endsWith("'");
      final startsWithDouble = trimmed.startsWith('"');
      final endsWithDouble = trimmed.endsWith('"');
      if ((startsWithSingle && endsWithSingle) ||
          (startsWithDouble && endsWithDouble)) {
        return trimmed.substring(1, trimmed.length - 1).trim();
      }
    }
    return trimmed;
  }

  static String get supabaseUrl {
    const fromDefine = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
    if (fromDefine.isNotEmpty) return _cleanEnvValue(fromDefine);
    return _cleanEnvValue(dotenv.env['SUPABASE_URL'] ?? '');
  }

  static String get supabaseAnonKey {
    const fromDefine =
        String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');
    if (fromDefine.isNotEmpty) return _cleanEnvValue(fromDefine);
    return _cleanEnvValue(dotenv.env['SUPABASE_ANON_KEY'] ?? '');
  }

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
