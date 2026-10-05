import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/time_format.dart';
import '../../models/story.dart';
import '../../routing/routes.dart';
import '../../shared/widgets/widgets.dart';
import '../auth/auth_controller.dart';
import '../feed/widgets/coming_soon.dart';
import '../social/follow_button.dart';
import '../../services/providers.dart';
import 'story_controllers.dart';
import 'widgets/story_body.dart';
import 'widgets/story_cards.dart';

/// Story reader: cover-led, serif, calm. Deliberately not a social post.
class StoryReaderScreen extends ConsumerWidget {
  const StoryReaderScreen({super.key, required this.refId});

  /// Slug or id.
  final String refId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(storyProvider(refId));
    return async.when(
      data: (story) => _Reader(story: story, refId: refId),
      loading: () => Scaffold(appBar: AppBar(), body: const LoadingView()),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: ErrorState(
          error: e,
          onRetry: () => ref.invalidate(storyProvider(refId)),
        ),
      ),
    );
  }
}

class _Reader extends ConsumerStatefulWidget {
  const _Reader({required this.story, required this.refId});
  final Story story;
  final String refId;

  @override
  ConsumerState<_Reader> createState() => _ReaderState();
}

class _ReaderState extends ConsumerState<_Reader> {
  final _scroll = ScrollController();
  final _progress = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final max = _scroll.position.maxScrollExtent;
      _progress.value = max <= 0 ? 0 : (_scroll.offset / max).clamp(0, 1);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _progress.dispose();
    super.dispose();
  }

  Future<void> _menu(String action) async {
    final story = widget.story;
    final repo = ref.read(storyRepositoryProvider);
    switch (action) {
      case 'edit':
        await context.push(AppRoutes.storyEditPath(story.id));
        ref.invalidate(storyProvider(widget.refId));
      case 'unpublish':
        await guarded(context, () async {
          await repo.unpublish(story.id);
          invalidateStoryLists(ref);
          ref.invalidate(storyProvider(widget.refId));
        });
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Delete this story?'),
            content: const Text(
              'This removes the story and its photos for everyone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (ok != true || !mounted) return;
        await guarded(context, () async {
          await repo.delete(story.id);
          invalidateStoryLists(ref);
          if (mounted) context.pop();
        }, fallback: 'Could not delete the story.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final story = widget.story;
    final theme = Theme.of(context);
    final auth = ref.watch(authControllerProvider);
    final isMine = auth is Authenticated && auth.user.id == story.author.id;
    final hasCover = story.cover != null;
    final related = ref.watch(relatedStoriesProvider(story.id));
    final overline = [
      if (story.tags.isNotEmpty) story.tags.first.toUpperCase(),
      ?story.locationText,
    ].join('  ·  ');
    final byline = [
      '${story.readingMinutes} min read',
      if (story.publishedAt != null) formatRelativeTime(story.publishedAt!),
    ].join('  ·  ');

    return Scaffold(
      body: Stack(
        children: [
          CustomScrollView(
            controller: _scroll,
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: hasCover
                    ? MediaQuery.sizeOf(context).height * 0.52
                    : null,
                leading: Padding(
                  padding: const EdgeInsets.all(6),
                  child: IconButton.filled(
                    tooltip: 'Back',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black45,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () => context.canPop()
                        ? context.pop()
                        : context.go(AppRoutes.stories),
                  ),
                ),
                actions: [
                  if (isMine)
                    PopupMenuButton<String>(
                      tooltip: 'Story options',
                      onSelected: _menu,
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Text('Edit story'),
                        ),
                        if (story.status == StoryStatus.published)
                          const PopupMenuItem(
                            value: 'unpublish',
                            child: Text('Move to drafts'),
                          ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete story'),
                        ),
                      ],
                    ),
                ],
                flexibleSpace: hasCover
                    ? FlexibleSpaceBar(
                        collapseMode: CollapseMode.parallax,
                        background: SizedBox.expand(
                          child: Image.network(
                            story.cover!.url,
                            fit: BoxFit.cover,
                            semanticLabel: 'Story cover photo',
                            errorBuilder: (_, _, _) =>
                                const ColoredBox(color: AppColors.paperDeep),
                          ),
                        ),
                      )
                    : null,
              ),
              SliverToBoxAdapter(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.gutter,
                            AppSpacing.lg,
                            AppSpacing.gutter,
                            0,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (story.isDraft)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: AppSpacing.sm,
                                  ),
                                  child: Text(
                                    'DRAFT — only you can see this',
                                    style: theme.textTheme.labelMedium,
                                  ),
                                ),
                              if (overline.isNotEmpty)
                                InkWell(
                                  onTap: story.place == null
                                      ? null
                                      : () => context.push(
                                          AppRoutes.placePath(
                                            story.place!.slug,
                                          ),
                                        ),
                                  child: Text(
                                    overline,
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                          color: theme.colorScheme.primary,
                                        ),
                                  ),
                                ),
                              const SizedBox(height: AppSpacing.md),
                              Semantics(
                                header: true,
                                child: Text(
                                  story.displayTitle,
                                  style:
                                      AppTypography.serif(
                                        size: 36,
                                        weight: 700,
                                        height: 1.22,
                                      ).copyWith(
                                        color: theme.colorScheme.onSurface,
                                      ),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              Row(
                                children: [
                                  UserAvatar(
                                    name: story.author.name,
                                    seed: story.author.username,
                                    imageUrl: story.author.avatarUrl,
                                    size: 36,
                                  ),
                                  const SizedBox(width: AppSpacing.md - 4),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          story.author.name,
                                          style: theme.textTheme.titleSmall,
                                        ),
                                        Text(
                                          byline,
                                          style: theme.textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              Divider(color: theme.dividerTheme.color),
                            ],
                          ),
                        ),
                        StoryBody(content: story.content, media: story.media),
                        const SizedBox(height: AppSpacing.lg),
                        if (story.tags.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.gutter,
                            ),
                            child: Wrap(
                              spacing: AppSpacing.sm,
                              children: [
                                for (final t in story.tags)
                                  Text(
                                    '#$t',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.secondary,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        if (!story.isDraft) _ActionRow(story: story),
                        _AuthorCard(story: story, isMine: isMine),
                        if (!story.isDraft)
                          related.maybeWhen(
                            data: (items) => items.isEmpty
                                ? const SizedBox.shrink()
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          AppSpacing.gutter,
                                          AppSpacing.lg,
                                          AppSpacing.gutter,
                                          AppSpacing.sm,
                                        ),
                                        child: Text(
                                          'MORE STORIES',
                                          style: theme.textTheme.labelMedium,
                                        ),
                                      ),
                                      for (final s in items)
                                        StoryCard(story: s, compact: true),
                                    ],
                                  ),
                            orElse: () => const SizedBox.shrink(),
                          ),
                        const SizedBox(height: AppSpacing.xxl),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: SafeArea(
              bottom: false,
              child: ValueListenableBuilder<double>(
                valueListenable: _progress,
                builder: (_, value, _) => value <= 0
                    ? const SizedBox.shrink()
                    : Semantics(
                        label: 'Reading progress',
                        value: '${(value * 100).round()}%',
                        child: LinearProgressIndicator(
                          value: value,
                          minHeight: 2,
                          backgroundColor: Colors.transparent,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends ConsumerWidget {
  const _ActionRow({required this.story});
  final Story story;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e =
        ref.watch(storyEngagementProvider.select((m) => m[story.id])) ??
        ref.read(storyEngagementProvider.notifier).of(story);
    final scheme = Theme.of(context).colorScheme;
    final controller = ref.read(storyEngagementProvider.notifier);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.sm,
        0,
      ),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: () => guarded(
              context,
              () => controller.toggleLike(story),
              fallback: 'Could not update your like.',
            ),
            icon: Icon(
              e.liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: e.liked ? scheme.primary : AppColors.inkSoft,
            ),
            label: Text(e.likeCount > 0 ? '${e.likeCount}' : 'Like'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.inkSoft,
              minimumSize: const Size(48, 48),
            ),
          ),
          TextButton.icon(
            onPressed: () => guarded(
              context,
              () => controller.toggleSave(story),
              fallback: 'Could not update saved stories.',
            ),
            icon: Icon(
              e.saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
              color: e.saved ? scheme.primary : AppColors.inkSoft,
            ),
            label: Text(e.saved ? 'Saved' : 'Save'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.inkSoft,
              minimumSize: const Size(48, 48),
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

class _AuthorCard extends StatelessWidget {
  const _AuthorCard({required this.story, required this.isMine});
  final Story story;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.lg,
        AppSpacing.gutter,
        0,
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerTheme.color ?? AppColors.line),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Row(
        children: [
          UserAvatar(
            name: story.author.name,
            seed: story.author.username,
            imageUrl: story.author.avatarUrl,
            size: 48,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('WRITTEN BY', style: theme.textTheme.labelSmall),
                Text(story.author.name, style: theme.textTheme.titleMedium),
                Text(
                  '@${story.author.username}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (!isMine)
            FollowButton(
              username: story.author.username,
              initiallyFollowing: story.followingAuthor,
              compact: true,
            ),
        ],
      ),
    );
  }
}
