import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/time_format.dart';
import '../../../models/post.dart';
import '../../../shared/widgets/widgets.dart';
import 'coming_soon.dart';
import 'post_media_view.dart';

/// A feed post. Media leads; text follows; text-only posts get an editorial
/// pull-quote treatment so they feel like writing, not a status update.
class PostCard extends StatelessWidget {
  const PostCard({
    super.key,
    required this.post,
    this.onAuthorTap,
    this.onDelete,
    this.now,
  });

  final Post post;
  final VoidCallback? onAuthorTap;

  /// Provided only for the signed-in author; shows a "Delete post" menu entry.
  final VoidCallback? onDelete;

  /// Injectable clock for deterministic tests.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.md,
            AppSpacing.gutter,
            AppSpacing.md,
          ),
          child: _Header(
            post: post,
            onTap: onAuthorTap,
            onDelete: onDelete,
            now: now,
          ),
        ),
        if (post.hasMedia) PostMediaView(media: post.media),
        if (post.hasText)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              AppSpacing.md,
              AppSpacing.gutter,
              0,
            ),
            child: _Body(post: post),
          ),
        if (post.tags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              AppSpacing.sm,
              AppSpacing.gutter,
              0,
            ),
            child: Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final tag in post.tags)
                  Text(
                    '#$tag',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.secondary,
                    ),
                  ),
              ],
            ),
          ),
        const _ActionBar(),
        Divider(color: theme.dividerTheme.color, height: 1),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.post,
    required this.onTap,
    required this.onDelete,
    required this.now,
  });
  final Post post;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final author = post.author;
    final who = Row(
      children: [
        UserAvatar(name: author.name, seed: author.username),
        const SizedBox(width: AppSpacing.md - 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                author.name,
                style: theme.textTheme.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '@${author.username} · ${formatRelativeTime(post.createdAt, now: now)}',
                style: theme.textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: onTap == null
                  ? who
                  : InkWell(
                      onTap: onTap,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                      child: who,
                    ),
            ),
            if (onDelete != null)
              PopupMenuButton<String>(
                tooltip: 'Post options',
                icon: const Icon(
                  Icons.more_horiz_rounded,
                  color: AppColors.inkSoft,
                ),
                onSelected: (_) => onDelete!(),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'delete', child: Text('Delete post')),
                ],
              ),
          ],
        ),
        if (post.locationText != null) ...[
          const SizedBox(height: AppSpacing.sm + 2),
          Row(
            children: [
              Icon(
                Icons.place_outlined,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  post.locationText!,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Body extends StatefulWidget {
  const _Body({required this.post});
  final Post post;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  static const _collapseAfter = 280;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = widget.post.body!.trim();
    final long = text.length > _collapseAfter;
    final textOnly = !widget.post.hasMedia;

    final style = textOnly
        ? AppTypography.serif(
            size: 22,
            weight: 500,
            height: 1.5,
          ).copyWith(color: theme.colorScheme.onSurface)
        : theme.textTheme.bodyMedium;
    final body = Text(
      text,
      style: style,
      maxLines: long && !_expanded ? (textOnly ? 8 : 5) : null,
      overflow: long && !_expanded ? TextOverflow.ellipsis : null,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        textOnly
            ? Container(
                padding: const EdgeInsets.only(left: AppSpacing.md),
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: theme.colorScheme.primary,
                      width: 3,
                    ),
                  ),
                ),
                child: body,
              )
            : body,
        if (long)
          TextButton(
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 36),
              alignment: Alignment.centerLeft,
            ),
            onPressed: () => setState(() => _expanded = !_expanded),
            child: Text(_expanded ? 'Show less' : 'Read more'),
          ),
      ],
    );
  }
}

/// Like / Comment / Save / Share. Visible, but their backends arrive in later
/// phases, so tapping says so instead of faking a result.
class _ActionBar extends StatelessWidget {
  const _ActionBar();

  @override
  Widget build(BuildContext context) {
    Widget action(IconData icon, String label) => IconButton(
      icon: Icon(icon),
      color: AppColors.inkSoft,
      tooltip: '$label (coming soon)',
      onPressed: () => showComingSoon(context, label),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          action(Icons.favorite_border_rounded, 'Like'),
          action(Icons.chat_bubble_outline_rounded, 'Comment'),
          action(Icons.bookmark_border_rounded, 'Save'),
          const Spacer(),
          action(Icons.ios_share_rounded, 'Share'),
        ],
      ),
    );
  }
}
