import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_spacing.dart';
import '../../models/story.dart';
import '../../routing/routes.dart';
import '../../shared/paged/paged_controller.dart';
import '../../shared/paged/paged_views.dart';
import '../../shared/widgets/widgets.dart';
import 'story_controllers.dart';
import 'widgets/story_cards.dart';

enum _Section { discover, drafts, published }

/// The Stories tab: editorial feed, plus your own drafts and published stories.
class StoriesScreen extends ConsumerStatefulWidget {
  const StoriesScreen({super.key});

  @override
  ConsumerState<StoriesScreen> createState() => _StoriesScreenState();
}

class _StoriesScreenState extends ConsumerState<StoriesScreen> {
  _Section _section = _Section.discover;

  NotifierProvider<PagedController<StorySummary>, PagedState<StorySummary>>
  get _provider => switch (_section) {
    _Section.discover => storiesFeedProvider,
    _Section.drafts => myStoriesProvider('draft'),
    _Section.published => myStoriesProvider('published'),
  };

  @override
  Widget build(BuildContext context) {
    final provider = _provider;
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    listenForRefreshErrors(ref, provider, context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stories'),
        actions: [
          IconButton(
            tooltip: 'Write a story',
            icon: const Icon(Icons.edit_note_rounded, size: 28),
            onPressed: () => context.push(AppRoutes.storyNew),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.gutter,
                vertical: 8,
              ),
              children: [
                for (final (s, label) in [
                  (_Section.discover, 'Discover'),
                  (_Section.drafts, 'My drafts'),
                  (_Section.published, 'Published'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: _section == s,
                      onSelected: (_) => setState(() => _section = s),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      body: PagedScrollView(
        onRefresh: controller.refresh,
        onLoadMore: controller.loadMore,
        slivers: pagedSlivers<StorySummary>(
          state: state,
          onRetry: controller.retry,
          onLoadMore: controller.loadMore,
          empty: _empty(),
          itemBuilder: (context, story) => StoryCard(
            key: ValueKey(story.id),
            story: story,
            featured:
                _section == _Section.discover &&
                state.items.first.id == story.id,
          ),
        ),
      ),
    );
  }

  Widget _empty() => switch (_section) {
    _Section.discover => EmptyState(
      icon: Icons.auto_stories_outlined,
      title: 'No stories yet',
      message: 'Long-form travel and cultural stories will appear here. Be the first to write one.',
      actionLabel: 'Write a story',
      onAction: () => context.push(AppRoutes.storyNew),
    ),
    _Section.drafts => EmptyState(
      icon: Icons.edit_note_rounded,
      title: 'No drafts',
      message: 'Start a story and save it as a draft to finish later.',
      actionLabel: 'Write a story',
      onAction: () => context.push(AppRoutes.storyNew),
    ),
    _Section.published => const EmptyState(
      icon: Icons.menu_book_outlined,
      title: 'Nothing published yet',
      message: 'Stories you publish will appear here.',
    ),
  };
}
