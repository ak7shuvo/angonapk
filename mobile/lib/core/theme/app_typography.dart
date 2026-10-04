import 'package:flutter/material.dart';

/// Typography system.
///
/// * Display / headings: Newsreader (serif) for an editorial voice.
/// * UI / body: Inter.
/// * Bengali glyphs: Noto Serif Bengali / Noto Sans Bengali, supplied through
///   `fontFamilyFallback` so mixed Bengali + English strings render correctly
///   with the same styles. Bengali needs extra line height, so heights are
///   generous.
abstract final class AppTypography {
  static const _serifFallback = ['NotoSerifBengali'];
  static const _sansFallback = ['NotoSansBengali'];

  static TextStyle serif({
    required double size,
    double weight = 600,
    double height = 1.3,
    double letterSpacing = -0.2,
  }) => TextStyle(
    fontFamily: 'Newsreader',
    fontFamilyFallback: _serifFallback,
    fontSize: size,
    height: height,
    letterSpacing: letterSpacing,
    fontWeight: _weight(weight),
    fontVariations: [FontVariation('wght', weight)],
  );

  static TextStyle sans({
    required double size,
    double weight = 400,
    double height = 1.5,
    double letterSpacing = 0,
  }) => TextStyle(
    fontFamily: 'Inter',
    fontFamilyFallback: _sansFallback,
    fontSize: size,
    height: height,
    letterSpacing: letterSpacing,
    fontWeight: _weight(weight),
    fontVariations: [FontVariation('wght', weight)],
  );

  static FontWeight _weight(double w) =>
      FontWeight.values[((w / 100).round().clamp(1, 9)) - 1];

  static TextTheme textTheme(Color ink, Color inkSoft) => TextTheme(
    displayLarge: serif(
      size: 40,
      weight: 700,
      height: 1.2,
    ).copyWith(color: ink),
    displayMedium: serif(
      size: 32,
      weight: 700,
      height: 1.25,
    ).copyWith(color: ink),
    headlineMedium: serif(size: 26, height: 1.3).copyWith(color: ink),
    headlineSmall: serif(size: 22, height: 1.35).copyWith(color: ink),
    titleLarge: serif(size: 20, height: 1.4).copyWith(color: ink),
    titleMedium: sans(size: 16, weight: 600).copyWith(color: ink),
    titleSmall: sans(size: 14, weight: 600).copyWith(color: ink),
    bodyLarge: sans(size: 17, height: 1.65).copyWith(color: ink),
    bodyMedium: sans(size: 15, height: 1.6).copyWith(color: ink),
    bodySmall: sans(size: 13, height: 1.5).copyWith(color: inkSoft),
    labelLarge: sans(
      size: 15,
      weight: 600,
      letterSpacing: 0.2,
    ).copyWith(color: ink),
    labelMedium: sans(
      size: 12,
      weight: 600,
      letterSpacing: 0.6,
    ).copyWith(color: inkSoft),
    labelSmall: sans(
      size: 11,
      weight: 500,
      letterSpacing: 0.6,
    ).copyWith(color: inkSoft),
  );
}
