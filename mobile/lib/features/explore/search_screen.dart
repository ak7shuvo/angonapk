import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_spacing.dart';
import '../../models/explore.dart';
import '../../routing/routes.dart';
import '../../shared/widgets/widgets.dart';
import '../feed/widgets/post_tile.dart';
import '../places/widgets/place_tile.dart';
import '../social/user_list_screen.dart';
import '../stories/widgets/story_cards.dart';
import 'explore_controllers.dart';

/// Search people, stories, posts and places, with debounced results.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _field = TextEditingController();

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchControllerProvider);
    final controller = ref.read(searchControllerProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _field,
          autofocus: true,
          onChanged: controller.setQuery,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search places, people, stories',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            suffixIcon: state.query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _field.clear();
                      controller.setQuery('');
                    },
                  ),
          ),
        ),
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
                for (final (t, label) in [
                  (SearchType.all, 'All'),
                  (SearchType.places, 'Places'),
                  (SearchType.users, 'People'),
                  (SearchType.stories, 'Stories'),
                  (SearchType.posts, 'Posts'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: state.type == t,
                      onSelected: (_) => controller.setType(t),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      body: _body(state, controller, theme),
    );
  }

  Widget _body(
    SearchState state,
    DiscoverySearchController controller,
    ThemeData theme,
  ) {
    if (state.idle) {
      return const EmptyState(
        icon: Icons.search,
        title: 'Search ANGON',
        message: 'Find a destination like Jaflong, a storyteller, or a story by its title.',
      );
    }
    if (state.error != null) {
      return ErrorState(error: state.error!, onRetry: controller.retry);
    }
    if (state.loading && state.results.isEmpty) return const LoadingView();
    if (!state.loading && state.results.isEmpty) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: 'No results for “${state.query.trim()}”',
        message: 'Check the spelling or try a broader word.',
      );
    }
    final r = state.results;
    final single = state.type != SearchType.all;
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (single && n.metrics.extentAfter < 600) controller.loadMore();
        return false;
      },
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          if (r.places.isNotEmpty) ...[
            _Header(
              'Places',
              show: !single,
              onMore: () => controller.setType(SearchType.places),
            ),
            for (final p in r.places) PlaceTile(place: p),
          ],
          if (r.users.isNotEmpty) ...[
            _Header(
              'People',
              show: !single,
              onMore: () => controller.setType(SearchType.users),
            ),
            for (final u in r.users)
              UserTile(
                user: u,
                onTap: () => context.push(AppRoutes.userPath(u.username)),
              ),
          ],
          if (r.stories.isNotEmpty) ...[
            _Header(
              'Stories',
              show: !single,
              onMore: () => controller.setType(SearchType.stories),
            ),
            for (final s in r.stories) StoryCard(story: s, compact: true),
          ],
          if (r.posts.isNotEmpty) ...[
            _Header(
              'Posts',
              show: !single,
              onMore: () => controller.setType(SearchType.posts),
            ),
            for (final p in r.posts) PostTile(post: p),
          ],
          if (state.hasMore || state.loadingMore)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.title, {required this.show, required this.onMore});
  final String title;

  /// Section headers (with "See all") only appear in the combined view.
  final bool show;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    if (!show) return const SizedBox(height: AppSpacing.sm);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.md,
        AppSpacing.sm,
        0,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium,
          ),
          TextButton(onPressed: onMore, child: const Text('See all')),
        ],
      ),
    );
  }
}
