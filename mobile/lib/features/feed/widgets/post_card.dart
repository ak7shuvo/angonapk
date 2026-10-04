import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/time_format.dart';
import '../../../models/post.dart';
import '../../../models/social.dart';
import '../../../shared/widgets/widgets.dart';
import '../../social/engagement_controller.dart';
import '../../social/follow_button.dart';
import '../../social/follow_controller.dart';
import 'coming_soon.dart';
import 'post_media_view.dart';

/// A feed post. Media leads; text follows; text-only posts get an editorial
/// pull-quote treatment so they feel like writing, not a status update.
class PostCard extends ConsumerWidget {
  const PostCard({
    super.key,
    required this.post,
    this.onAuthorTap,
    this.onDelete,
    this.onOpenComments,
    this.isMine = false,
    this.now,
  });

  final Post post;
  final VoidCallback? onAuthorTap;

  /// Provided only for the signed-in author; shows a "Delete post" menu entry.
  final VoidCallback? onDelete;

  /// Opens the post's comments; null when already on the post screen.
  final VoidCallback? onOpenComments;
  final bool isMine;

  /// Injectable clock for deterministic tests.
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            isMine: isMine,
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
        _ActionBar(post: post, onOpenComments: onOpenComments),
        Divider(color: theme.dividerTheme.color, height: 1),
      ],
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({
    required this.post,
    required this.onTap,
    required this.onDelete,
    required this.isMine,
    required this.now,
  });
  final bool isMine;
  final Post post;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final author = post.author;
    final following = ref.watch(
      followProvider.select(
        (m) => m[author.username]?.following ?? post.followingAuthor,
      ),
    );
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
            if (!isMine && !following)
              FollowButton(
                username: author.username,
                initiallyFollowing: post.followingAuthor,
                compact: true,
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

/// Like / Comment / Save are real and server-backed (optimistic, then reconciled
/// with the server's answer). Share has no backend yet and says so.
class _ActionBar extends ConsumerWidget {
  const _ActionBar({required this.post, required this.onOpenComments});
  final Post post;
  final VoidCallback? onOpenComments;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engagement = ref.watch(
      engagementProvider.select((m) => m[post.id] ?? Engagement.of(post)),
    );
    final scheme = Theme.of(context).colorScheme;
    final controller = ref.read(engagementProvider.notifier);

    Widget counted({
      required IconData icon,
      required Color? color,
      required String label,
      required String tooltip,
      required VoidCallback? onPressed,
      int count = 0,
    }) => Semantics(
      label: label,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          transitionBuilder: (child, anim) =>
              ScaleTransition(scale: anim, child: child),
          child: Icon(icon, key: ValueKey(icon), color: color, size: 24),
        ),
        label: Text(
          count > 0 ? '$count' : '',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.inkSoft,
          minimumSize: const Size(48, 44),
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          counted(
            icon: engagement.liked
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            color: engagement.liked ? scheme.primary : AppColors.inkSoft,
            label: engagement.liked ? 'Unlike' : 'Like',
            tooltip: 'Like',
            count: engagement.likeCount,
            onPressed: () => guarded(
              context,
              () => controller.toggleLike(post),
              fallback: 'Could not update your like.',
            ),
          ),
          counted(
            icon: Icons.chat_bubble_outline_rounded,
            color: AppColors.inkSoft,
            label: 'Comments',
            tooltip: 'Comments',
            count: engagement.commentCount,
            onPressed: onOpenComments,
          ),
          counted(
            icon: engagement.saved
                ? Icons.bookmark_rounded
                : Icons.bookmark_border_rounded,
            color: engagement.saved ? scheme.primary : AppColors.inkSoft,
            label: engagement.saved ? 'Remove from saved' : 'Save',
            tooltip: 'Save',
            onPressed: () => guarded(
              context,
              () => controller.toggleSave(post),
              fallback: 'Could not update saved posts.',
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.ios_share_rounded),
            color: AppColors.inkSoft,
            tooltip: 'Share (coming soon)',
            onPressed: () => showComingSoon(context, 'Share'),
          ),
        ],
      ),
    );
  }
}
