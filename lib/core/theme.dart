import 'package:flutter/material.dart';

class AppColors {
  // Zenith Void — "The Silent Curator" design system by Stitch
  static const primary = Color(0xFFA6C8FD);
  static const primaryContainer = Color(0xFF7092C4);
  static const onPrimary = Color(0xFF02315D);

  static const secondary = Color(0xFF88D7A6);
  static const secondaryContainer = Color(0xFF005F38);

  static const tertiary = Color(0xFFF8BB73);
  static const tertiaryContainer = Color(0xFFBB8644);

  static const scaffold = Color(0xFF0E0E13);
  static const surface = Color(0xFF131318);
  static const surfaceContainerLowest = Color(0xFF0E0E13);
  static const surfaceContainerLow = Color(0xFF1B1B20);
  static const surfaceContainer = Color(0xFF1F1F25);
  static const surfaceContainerHigh = Color(0xFF2A292F);
  static const surfaceContainerHighest = Color(0xFF35343A);
  static const surfaceBright = Color(0xFF39383E);

  static const onSurface = Color(0xFFE4E1E9);
  static const onSurfaceVariant = Color(0xFFC3C6D0);
  static const outline = Color(0xFF8D919A);
  static const outlineVariant = Color(0xFF43474F);

  static const success = Color(0xFF88D7A6);
  static const warning = Color(0xFFF8BB73);
  static const error = Color(0xFFFFB4AB);

  static const dialogBg = Color(0xFF1F1F25);
}

ThemeData buildAppTheme() {
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
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
      backgroundColor: AppColors.surfaceContainerHigh,
      contentTextStyle: TextStyle(
        fontFamily: 'Inter',
        color: AppColors.onSurface,
        fontSize: 13,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.primary,
      linearTrackColor: Color(0x1AFFFFFF),
    ),
  );
}
