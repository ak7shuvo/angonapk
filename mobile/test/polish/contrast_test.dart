// WCAG contrast of the colour pairs the UI actually uses (AA text = 4.5:1).
import 'dart:math' as math;

import 'package:angon/core/theme/app_colors.dart';
import 'package:angon/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _lum(Color c) {
  double ch(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double contrast(Color a, Color b) {
  final hi = math.max(_lum(a), _lum(b)), lo = math.min(_lum(a), _lum(b));
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  const aa = 4.5;

  test('light theme text and controls meet AA', () {
    expect(contrast(AppColors.ink, AppColors.paper), greaterThan(aa));
    expect(contrast(AppColors.ink, AppColors.card), greaterThan(aa));
    expect(contrast(AppColors.inkSoft, AppColors.paper), greaterThan(aa));
    expect(contrast(AppColors.inkSoft, AppColors.paperDeep), greaterThan(aa));
    expect(contrast(Colors.white, AppColors.terracotta), greaterThan(aa));
    expect(contrast(AppColors.terracotta, AppColors.paper), greaterThan(aa));
    expect(contrast(AppColors.error, AppColors.paper), greaterThan(aa));
  });

  test('dark theme text and controls meet AA', () {
    for (final bg in [AppColors.nightPaper, AppColors.nightCard]) {
      expect(contrast(AppColors.nightInk, bg), greaterThan(aa));
      expect(contrast(AppColors.nightInkSoft, bg), greaterThan(aa));
      expect(
        contrast(AppTheme.dark().colorScheme.primary, bg),
        greaterThan(aa),
      );
    }
    expect(
      contrast(
        AppTheme.dark().colorScheme.onPrimary,
        AppTheme.dark().colorScheme.primary,
      ),
      greaterThan(aa),
    );
  });

  testWidgets('context neutrals follow the theme', (tester) async {
    late Color lightSoft, darkSoft;
    Widget app(Brightness b, void Function(BuildContext) read) => MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: b == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      home: Builder(
        builder: (c) {
          read(c);
          return const SizedBox();
        },
      ),
    );
    await tester.pumpWidget(
      app(Brightness.light, (c) => lightSoft = c.inkSoft),
    );
    await tester.pumpWidget(app(Brightness.dark, (c) => darkSoft = c.inkSoft));
    await tester.pumpAndSettle(); // theme changes animate
    expect(lightSoft, AppColors.inkSoft);
    expect(darkSoft, AppColors.nightInkSoft);
    expect(contrast(darkSoft, AppColors.nightPaper), greaterThan(aa));
  });
}
