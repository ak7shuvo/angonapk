import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// Avatar placeholder: the first letter of the name on a warm, per-user colour.
/// (Profile photos arrive with uploads; Bengali initials are grapheme-safe.)
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.name,
    required this.seed,
    this.size = 40,
  });

  final String name;

  /// Stable value (username) so the same person always gets the same colour.
  final String seed;
  final double size;

  static const _palette = [
    AppColors.terracotta,
    AppColors.delta,
    AppColors.terracottaDeep,
    Color(0xFF8A6A1F),
    Color(0xFF4F4A7A),
  ];

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim().replaceFirst(RegExp(r'^\[[^\]]*\]\s*'), '');
    final initial = (trimmed.isEmpty ? seed : trimmed).characters.first
        .toUpperCase();
    final color =
        _palette[seed.codeUnits.fold<int>(0, (a, b) => a + b) %
            _palette.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Text(
        initial,
        style: AppTypography.serif(
          size: size * 0.45,
          weight: 600,
          height: 1,
        ).copyWith(color: Colors.white),
      ),
    );
  }
}
