import 'package:flutter/material.dart';

class AppColors {
  static const primary = Color(0xFF4A9FE5);
  static const primaryDark = Color(0xFF1E76CC);
  static const accent = Color(0xFF5BC0F5);
  static const surface = Color(0xFF1A1A24);
  static const scaffold = Color(0xFF0D0D14);
  static const dialogBg = Color(0xFF1C1C28);
  static const success = Color(0xFF4CAF50);
  static const warning = Color(0xFFFFA726);
  static const error = Color(0xFFFF7043);
}

ThemeData buildAppTheme() {
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
    ),
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.scaffold,
    fontFamily: 'SF Pro Display',
  );
}
