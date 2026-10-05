import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/media_url.dart';
import '../../services/providers.dart';

/// Profile photo, or — until the person adds one — the first letter of their
/// name on a warm, per-user colour. Bengali initials are grapheme-safe.
class UserAvatar extends ConsumerWidget {
  const UserAvatar({
    super.key,
    required this.name,
    required this.seed,
    this.imageUrl,
    this.size = 40,
  });

  final String name;

  /// Stable value (username) so the same person always gets the same colour.
  final String seed;

  /// Raw `avatar_url` from the API (may be storage-relative).
  final String? imageUrl;
  final double size;

  static const _palette = [
    AppColors.terracotta,
    AppColors.delta,
    AppColors.terracottaDeep,
    Color(0xFF8A6A1F),
    Color(0xFF4F4A7A),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trimmed = name.trim().replaceFirst(RegExp(r'^\[[^\]]*\]\s*'), '');
    final initial = (trimmed.isEmpty ? seed : trimmed).characters.first
        .toUpperCase();
    final color =
        _palette[seed.codeUnits.fold<int>(0, (a, b) => a + b) %
            _palette.length];
    final fallback = Container(
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
    if (imageUrl == null) return fallback;
    final url = resolveMediaUrl(
      ref.watch(appConfigProvider).apiBaseUrl,
      imageUrl!,
    );
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          cacheWidth: (size * 3).round(),
          semanticLabel: 'Profile photo of $name',
          loadingBuilder: (_, child, p) => p == null ? child : fallback,
          errorBuilder: (_, _, _) => fallback,
        ),
      ),
    );
  }
}
