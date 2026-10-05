import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../models/post.dart';
import '../../models/story.dart';
import '../../routing/routes.dart';
import '../../shared/paged/paged_views.dart';
import '../../shared/widgets/widgets.dart';
import '../feed/widgets/post_tile.dart';
import '../stories/widgets/story_cards.dart';
import 'explore_controllers.dart';

/// Everything tagged with a category such as "heritage" or "food".
class CategoryScreen extends ConsumerStatefulWidget {
  const CategoryScreen({super.key, required this.slug});
  final String slug;

  @override
  ConsumerState<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends ConsumerState<CategoryScreen> {
  bool _stories = false;

  String get _label => widget.slug.isEmpty
      ? ''
      : '${widget.slug[0].toUpperCase()}${widget.slug.substring(1)}';

  @override
  Widget build(BuildContext context) {
    final slug = widget.slug;
    final theme = Theme.of(context);

    late final List<Widget> slivers;
    late final Future<void> Function() refresh;
    late final VoidCallback loadMore;
    if (_stories) {
      final s = ref.watch(categoryStoriesProvider(slug));
      final c = ref.read(categoryStoriesProvider(slug).notifier);
      slivers = pagedSlivers<StorySummary>(
        state: s,
        onRetry: c.retry,
        onLoadMore: c.loadMore,
        empty: EmptyState(
          icon: Icons.auto_stories_outlined,
          title: 'No $_label stories yet',
          message: 'Tag a story with “$slug” and it will appear here.',
        ),
        itemBuilder: (context, st) =>
            StoryCard(key: ValueKey(st.id), story: st),
      );
      refresh = c.refresh;
      loadMore = c.loadMore;
    } else {
      final s = ref.watch(categoryPostsProvider(slug));
      final c = ref.read(categoryPostsProvider(slug).notifier);
      slivers = pagedSlivers<Post>(
        state: s,
        onRetry: c.retry,
        onLoadMore: c.loadMore,
        empty: EmptyState(
          icon: Icons.photo_camera_outlined,
          title: 'No $_label posts yet',
          message: 'Tag a post with “$slug” and it will appear here.',
          actionLabel: 'Share a discovery',
          onAction: () => context.go(AppRoutes.create),
        ),
        itemBuilder: (context, p) => PostTile(key: ValueKey(p.id), post: p),
      );
      refresh = c.refresh;
      loadMore = c.loadMore;
    }

    return Scaffold(
      body: PagedScrollView(
        onRefresh: refresh,
        onLoadMore: loadMore,
        headerSlivers: [
          SliverAppBar(
            pinned: true,
            title: Text(_label, style: theme.textTheme.titleMedium),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                AppSpacing.md,
                AppSpacing.gutter,
                AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      _label,
                      style: AppTypography.serif(
                        size: 38,
                        weight: 700,
                        height: 1.2,
                      ).copyWith(color: theme.colorScheme.onSurface),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      ChoiceChip(
                        label: const Text('Posts'),
                        selected: !_stories,
                        onSelected: (_) => setState(() => _stories = false),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      ChoiceChip(
                        label: const Text('Stories'),
                        selected: _stories,
                        onSelected: (_) => setState(() => _stories = true),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
        slivers: slivers,
      ),
    );
  }
}
