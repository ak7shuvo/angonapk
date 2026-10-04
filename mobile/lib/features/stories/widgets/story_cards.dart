import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/time_format.dart';
import '../../../models/story.dart';
import '../../../routing/routes.dart';
import '../../../shared/widgets/widgets.dart';
import '../story_controllers.dart';

/// Network image with warm placeholder/fallback, used for story covers.
class CoverImage extends StatelessWidget {
  const CoverImage({
    super.key,
    required this.image,
    this.aspectRatio = 16 / 10,
  });
  final StoryImage? image;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? AppColors.nightCard : AppColors.paperDeep;
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: image == null
          ? ColoredBox(color: bg)
          : Image.network(
              image!.url,
              fit: BoxFit.cover,
              semanticLabel: 'Story cover photo',
              loadingBuilder: (_, child, p) =>
                  p == null ? child : ColoredBox(color: bg),
              errorBuilder: (_, _, _) => ColoredBox(
                color: bg,
                child: const Center(
                  child: Icon(
                    Icons.image_not_supported_outlined,
                    color: AppColors.inkFaint,
                  ),
                ),
              ),
            ),
    );
  }
}

/// A story in a list. [featured] makes the first story of a feed larger.
class StoryCard extends ConsumerWidget {
  const StoryCard({
    super.key,
    required this.story,
    this.featured = false,
    this.compact = false,
  });
  final StorySummary story;
  final bool featured;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final engagement = ref.watch(
      storyEngagementProvider.select(
        (m) => m[story.id]?.likeCount ?? story.likeCount,
      ),
    );
    final overline = [
      if (story.tags.isNotEmpty) story.tags.first.toUpperCase(),
      ?story.locationText,
    ].join('  ·  ');
    final hasCover = story.cover != null;

    final text = Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        hasCover ? AppSpacing.md : AppSpacing.lg,
        AppSpacing.gutter,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (overline.isNotEmpty)
            Text(
              overline,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          if (overline.isNotEmpty) const SizedBox(height: AppSpacing.sm),
          Text(
            story.displayTitle,
            style: AppTypography.serif(
              size: featured ? 30 : (compact ? 20 : 24),
              weight: 650,
              height: 1.25,
            ).copyWith(color: theme.colorScheme.onSurface),
            maxLines: featured ? 4 : 3,
            overflow: TextOverflow.ellipsis,
          ),
          if (story.summary.isNotEmpty && !compact) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              story.summary,
              style: theme.textTheme.bodyMedium,
              maxLines: featured ? 4 : 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              UserAvatar(
                name: story.author.name,
                seed: story.author.username,
                size: 22,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '${story.author.name}  ·  ${story.readingMinutes} min read'
                  '${story.publishedAt != null ? '  ·  ${formatRelativeTime(story.publishedAt!)}' : ''}',
                  style: theme.textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (story.isDraft)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.inkFaint),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('DRAFT', style: theme.textTheme.labelSmall),
                )
              else if (engagement > 0) ...[
                const Icon(
                  Icons.favorite_rounded,
                  size: 14,
                  color: AppColors.inkFaint,
                ),
                const SizedBox(width: 4),
                Text('$engagement', style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ],
      ),
    );

    return Semantics(
      button: true,
      label: story.displayTitle,
      child: InkWell(
        onTap: () => story.isDraft
            ? context.push(AppRoutes.storyEditPath(story.id))
            : context.push(AppRoutes.storyReadPath(story.slug), extra: story),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasCover)
              CoverImage(
                image: story.cover,
                aspectRatio: featured ? 4 / 5 : 16 / 10,
              ),
            text,
            Divider(color: theme.dividerTheme.color),
          ],
        ),
      ),
    );
  }
}
