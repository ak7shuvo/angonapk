import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_spacing.dart';
import '../../routing/routes.dart';
import '../../shared/widgets/widgets.dart';
import '../auth/auth_controller.dart';
import '../feed/feed_controller.dart';
import '../feed/widgets/post_tile.dart';

/// ANGON Home: header with profile entry point, a Discover / Following switch
/// and the live feed.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  FeedScope _scope = FeedScope.all;

  NotifierProvider<FeedController, FeedState> get _provider =>
      _scope == FeedScope.all ? feedControllerProvider : followingFeedProvider;

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.extentAfter < 800) {
      ref.read(_provider.notifier).loadMore();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(_provider);
    final controller = ref.read(_provider.notifier);
    final me = switch (ref.watch(authControllerProvider)) {
      Authenticated(:final user) => user,
      _ => null,
    };

    ref.listen(_provider.select((s) => s.refreshError), (_, error) {
      if (error != null) {
        showAppSnack(
          context,
          errorMessage(error, fallback: 'Could not refresh your feed.'),
        );
      }
    });

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: controller.refresh,
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverAppBar(
                floating: true,
                snap: true,
                titleSpacing: AppSpacing.gutter,
                title: const AngonWordmark(size: 22),
                actions: [
                  IconButton(
                    tooltip: 'Search',
                    icon: const Icon(Icons.search),
                    onPressed: () => context.push(AppRoutes.search),
                  ),
                  if (me != null)
                    Padding(
                      padding: const EdgeInsets.only(
                        right: AppSpacing.gutter - 4,
                      ),
                      child: IconButton(
                        tooltip: 'Your profile',
                        onPressed: () => context.go(AppRoutes.profile),
                        icon: UserAvatar(
                          name: me.displayName,
                          seed: me.username,
                          imageUrl: me.profile.avatarUrl,
                          size: 32,
                        ),
                      ),
                    ),
                ],
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(44),
                  child: _ScopeTabs(
                    scope: _scope,
                    onChanged: (s) => setState(() => _scope = s),
                  ),
                ),
              ),
              ..._body(feed, controller),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _body(FeedState feed, FeedController controller) {
    switch (feed.status) {
      case FeedStatus.loading:
        return const [
          SliverFillRemaining(hasScrollBody: false, child: LoadingView()),
        ];
      case FeedStatus.error:
        return [
          SliverFillRemaining(
            hasScrollBody: false,
            child: ErrorState(error: feed.error!, onRetry: controller.retry),
          ),
        ];
      case FeedStatus.ready when feed.isEmpty:
        return [
          SliverFillRemaining(
            hasScrollBody: false,
            child: _scope == FeedScope.following
                ? EmptyState(
                    icon: Icons.people_outline,
                    title: 'Follow storytellers',
                    message: 'Posts from the travellers, photographers and writers you follow will appear here.',
                    actionLabel: 'Discover',
                    onAction: () => setState(() => _scope = FeedScope.all),
                  )
                : EmptyState(
                    icon: Icons.auto_awesome_outlined,
                    title: 'Nothing here yet',
                    message: 'Be the first to share a place you discovered. Posts from travellers and storytellers will gather here.',
                    actionLabel: 'Share a discovery',
                    onAction: () => context.go(AppRoutes.create),
                  ),
          ),
        ];
      case FeedStatus.ready:
        return [
          SliverList.builder(
            itemCount: feed.posts.length,
            itemBuilder: (context, i) =>
                PostTile(key: ValueKey(feed.posts[i].id), post: feed.posts[i]),
          ),
          SliverToBoxAdapter(
            child: _Footer(feed: feed, onRetry: controller.loadMore),
          ),
        ];
    }
  }
}

class _ScopeTabs extends StatelessWidget {
  const _ScopeTabs({required this.scope, required this.onChanged});
  final FeedScope scope;
  final ValueChanged<FeedScope> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget tab(FeedScope value, String label) {
      final selected = scope == value;
      return Expanded(
        child: Semantics(
          selected: selected,
          button: true,
          child: InkWell(
            onTap: () => onChanged(value),
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: selected
                        ? theme.colorScheme.primary
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Text(
                label,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: selected
                      ? theme.colorScheme.onSurface
                      : theme.textTheme.bodySmall?.color,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 44,
      child: Row(
        children: [
          tab(FeedScope.all, 'Discover'),
          tab(FeedScope.following, 'Following'),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.feed, required this.onRetry});
  final FeedState feed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget child;
    if (feed.loadMoreError != null) {
      child = TextButton(
        onPressed: onRetry,
        child: const Text('Could not load more. Tap to retry'),
      );
    } else if (feed.hasMore) {
      child = const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else {
      child = Text("You're all caught up", style: theme.textTheme.bodySmall);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Center(child: child),
    );
  }
}
