import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppColors {
  static const primary = Color(0xFF3366FF);
  static const primaryLight = Color(0xFF5B8AFF);
  static const primaryContainer = Color(0xFF1A3DB8);
  static const onPrimary = Color(0xFFFFFFFF);

  static const secondary = Color(0xFF2E7D4F);
  static const secondaryContainer = Color(0xFFD4EDDA);

  static const tertiary = Color(0xFFD4880F);
  static const tertiaryContainer = Color(0xFFFFF3CD);

  static const scaffold = Color(0xFFF7F8FA);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceContainerLowest = Color(0xFFFFFFFF);
  static const surfaceContainerLow = Color(0xFFF5F6F8);
  static const surfaceContainer = Color(0xFFF0F1F4);
  static const surfaceContainerHigh = Color(0xFFF3F4F6);
  static const surfaceContainerHighest = Color(0xFFE5E7EB);
  static const surfaceBright = Color(0xFFFFFFFF);

  static const onSurface = Color(0xFF111827);
  static const onSurfaceVariant = Color(0xFF6B7280);
  static const outline = Color(0xFF9CA3AF);
  static const outlineVariant = Color(0xFFE5E7EB);

  static const success = Color(0xFF16A34A);
  static const warning = Color(0xFFD97706);
  static const error = Color(0xFFDC2626);

  static const dialogBg = Color(0xFFFFFFFF);

  static const cardBg = Color(0xFFFFFFFF);
  static const cardText = Color(0xFF111827);
  static const cardTextSecondary = Color(0xFF6B7280);
  static const cardBorder = Color(0xFFE5E7EB);

  static const navBarBg = Color(0xFFFFFFFF);

  static const snackBarBg = Color(0xFF1F2937);
  static const snackBarText = Color(0xFFFFFFFF);
}

class ThemeController {
  static const _themeModeKey = 'theme_mode';
  static final ValueNotifier<ThemeMode> themeMode =
      ValueNotifier<ThemeMode>(ThemeMode.light);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMode = prefs.getString(_themeModeKey);
    switch (savedMode) {
      case 'dark':
        themeMode.value = ThemeMode.dark;
        break;
      case 'system':
        themeMode.value = ThemeMode.system;
        break;
      case 'light':
      default:
        themeMode.value = ThemeMode.light;
    }
  }

  static Future<void> setThemeMode(ThemeMode mode) async {
    themeMode.value = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, mode.name);
  }
}

ThemeData buildAppTheme() {
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
      surface: AppColors.surface,
      onSurface: AppColors.onSurface,
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      secondary: AppColors.secondary,
      tertiary: AppColors.tertiary,
      error: AppColors.error,
      outline: AppColors.outline,
      outlineVariant: AppColors.outlineVariant,
    ),
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.scaffold,
    fontFamily: 'Inter',
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      titleTextStyle: TextStyle(
        fontFamily: 'Inter',
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppColors.onSurface,
        letterSpacing: -0.02,
      ),
      iconTheme: IconThemeData(color: AppColors.onSurfaceVariant),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        textStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.snackBarBg,
      contentTextStyle: TextStyle(
        fontFamily: 'Inter',
        color: AppColors.snackBarText,
        fontSize: 13,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.primary,
      linearTrackColor: Color(0x1A000000),
    ),
  );
}

ThemeData buildDarkAppTheme() {
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
    ),
    useMaterial3: true,
    fontFamily: 'Inter',
    scaffoldBackgroundColor: const Color(0xFF0B1220),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
    ),
  );
}
