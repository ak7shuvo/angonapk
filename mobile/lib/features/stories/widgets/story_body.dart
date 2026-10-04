import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../models/story.dart';
import '../story_markup.dart';

/// Renders story content as editorial typography: serif body with generous
/// leading (Bengali-safe), headings, pull quotes and full-bleed photographs.
class StoryBody extends StatelessWidget {
  const StoryBody({super.key, required this.content, required this.media});
  final String content;
  final List<StoryImage> media;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = theme.colorScheme.onSurface;
    final images = {for (final m in media) m.id: m};
    final blocks = parseStory(content);
    final children = <Widget>[];
    var firstParagraph = true;

    for (final block in blocks) {
      switch (block) {
        case ParagraphBlock(:final text):
          children.add(
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.gutter,
                vertical: 10,
              ),
              child: SelectableText(
                text,
                style: AppTypography.serif(
                  size: firstParagraph ? 21 : 19,
                  weight: 400,
                  height: 1.85,
                  letterSpacing: 0,
                ).copyWith(color: ink),
              ),
            ),
          );
          firstParagraph = false;
        case HeadingBlock(:final text):
          children.add(
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                28,
                AppSpacing.gutter,
                6,
              ),
              child: Semantics(
                header: true,
                child: Text(
                  text,
                  style: AppTypography.serif(
                    size: 26,
                    weight: 700,
                    height: 1.35,
                  ).copyWith(color: ink),
                ),
              ),
            ),
          );
        case QuoteBlock(:final text):
          children.add(
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.gutter + 4,
                18,
                AppSpacing.gutter,
                18,
              ),
              child: Container(
                padding: const EdgeInsets.only(left: AppSpacing.md + 4),
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: theme.colorScheme.primary,
                      width: 3,
                    ),
                  ),
                ),
                child: Text(
                  text,
                  style: AppTypography.serif(
                    size: 23,
                    weight: 500,
                    height: 1.6,
                    letterSpacing: 0,
                  ).copyWith(color: ink, fontStyle: FontStyle.italic),
                ),
              ),
            ),
          );
        case ImageBlock(:final assetId, :final caption):
          final image = images[assetId];
          if (image == null) break;
          children.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AspectRatio(
                    aspectRatio: (image.aspectRatio ?? 4 / 3).clamp(0.8, 1.8),
                    child: Image.network(
                      image.url,
                      fit: BoxFit.cover,
                      semanticLabel: caption.isEmpty ? 'Story photo' : caption,
                      loadingBuilder: (_, child, p) => p == null
                          ? child
                          : const ColoredBox(color: AppColors.paperDeep),
                      errorBuilder: (_, _, _) => const ColoredBox(
                        color: AppColors.paperDeep,
                        child: Center(
                          child: Icon(
                            Icons.image_not_supported_outlined,
                            color: AppColors.inkFaint,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (caption.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.gutter,
                        8,
                        AppSpacing.gutter,
                        0,
                      ),
                      child: Text(
                        caption,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}
