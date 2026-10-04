import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

abstract final class AppTheme {
  static ThemeData light() => _build(
    brightness: Brightness.light,
    scheme:
        ColorScheme.fromSeed(
          seedColor: AppColors.terracotta,
          brightness: Brightness.light,
        ).copyWith(
          primary: AppColors.terracotta,
          onPrimary: Colors.white,
          secondary: AppColors.delta,
          surface: AppColors.paper,
          onSurface: AppColors.ink,
          error: AppColors.error,
          outlineVariant: AppColors.line,
        ),
    scaffold: AppColors.paper,
    card: AppColors.card,
    ink: AppColors.ink,
    inkSoft: AppColors.inkSoft,
    line: AppColors.line,
  );

  static ThemeData dark() => _build(
    brightness: Brightness.dark,
    scheme:
        ColorScheme.fromSeed(
          seedColor: AppColors.terracotta,
          brightness: Brightness.dark,
        ).copyWith(
          primary: const Color(0xFFE08A5F),
          onPrimary: AppColors.nightPaper,
          secondary: const Color(0xFF7FB3A2),
          surface: AppColors.nightPaper,
          onSurface: AppColors.nightInk,
          outlineVariant: AppColors.nightLine,
        ),
    scaffold: AppColors.nightPaper,
    card: AppColors.nightCard,
    ink: AppColors.nightInk,
    inkSoft: AppColors.nightInkSoft,
    line: AppColors.nightLine,
  );

  static ThemeData _build({
    required Brightness brightness,
    required ColorScheme scheme,
    required Color scaffold,
    required Color card,
    required Color ink,
    required Color inkSoft,
    required Color line,
  }) {
    final text = AppTypography.textTheme(ink, inkSoft);
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold,
      textTheme: text,
      fontFamily: 'Inter',
      fontFamilyFallback: const ['NotoSansBengali'],
      dividerTheme: DividerThemeData(color: line, space: 1, thickness: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: scaffold,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          side: BorderSide(color: line),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          textStyle: text.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          textStyle: text.labelLarge,
          foregroundColor: ink,
          side: BorderSide(color: line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: card,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scaffold,
        indicatorColor: scheme.primary.withValues(alpha: 0.12),
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStatePropertyAll(text.labelSmall),
      ),
    );
  }
}
