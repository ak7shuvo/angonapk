import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/media_url.dart';
import '../../../models/place.dart';
import '../../../routing/routes.dart';
import '../../../services/providers.dart';

/// Square place thumbnail: cover photo or a warm block with a pin.
class PlaceThumb extends ConsumerWidget {
  const PlaceThumb({
    super.key,
    required this.coverUrl,
    this.size = 64,
    this.radius = 8,
  });
  final String? coverUrl;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fallback = ColoredBox(
      color: dark ? AppColors.nightCard : AppColors.paperDeep,
      child: Icon(
        Icons.place_outlined,
        color: AppColors.inkFaint,
        size: size * 0.4,
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: coverUrl == null
            ? fallback
            : Image.network(
                resolveMediaUrl(
                  ref.watch(appConfigProvider).apiBaseUrl,
                  coverUrl!,
                ),
                fit: BoxFit.cover,
                cacheWidth: (size * 3).round(),
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

/// A place in a list: thumbnail, names (English + local script), area, counts.
class PlaceTile extends StatelessWidget {
  const PlaceTile({super.key, required this.place, this.onTap, this.trailing});
  final PlaceSummary place;

  /// Defaults to opening the place page.
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta = [
      if (place.locationLine.isNotEmpty) place.locationLine,
      if (place.postCount + place.storyCount > 0)
        '${place.postCount} posts · ${place.storyCount} stories',
      if (place.distanceKm != null)
        '${place.distanceKm!.toStringAsFixed(place.distanceKm! < 10 ? 1 : 0)} km away',
    ].join('  ·  ');
    return InkWell(
      onTap: onTap ?? () => context.push(AppRoutes.placePath(place.slug)),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.gutter,
          vertical: AppSpacing.sm + 2,
        ),
        child: Row(
          children: [
            PlaceThumb(coverUrl: place.coverUrl),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          place.name,
                          style: AppTypography.serif(
                            size: 18,
                            weight: 650,
                            height: 1.3,
                          ).copyWith(color: theme.colorScheme.onSurface),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (place.nameLocal != null) ...[
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          place.nameLocal!,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ],
                  ),
                  if (meta.isNotEmpty)
                    Text(
                      meta,
                      style: theme.textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}
