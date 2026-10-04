import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_spacing.dart';
import '../../routing/routes.dart';
import '../../models/post.dart';
import '../../shared/widgets/widgets.dart';
import '../auth/auth_controller.dart';
import '../feed/feed_controller.dart';
import '../feed/widgets/post_card.dart';

/// ANGON Home: header with profile entry point + the live feed.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _onScroll(ScrollNotification n) {
    if (n.metrics.extentAfter < 800) {
      ref.read(feedControllerProvider.notifier).loadMore();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(feedControllerProvider);
    final controller = ref.read(feedControllerProvider.notifier);
    final me = switch (ref.watch(authControllerProvider)) {
      Authenticated(:final user) => user,
      _ => null,
    };

    ref.listen(feedControllerProvider.select((s) => s.refreshError), (
      _,
      error,
    ) {
      if (error == null) return;
      final message = error is AppException
          ? error.message
          : 'Could not refresh your feed.';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
        );
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
                          size: 32,
                        ),
                      ),
                    ),
                ],
              ),
              ..._body(feed, controller, me?.id),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(Post post) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this post?'),
        content: const Text(
          'It will be removed for everyone, along with its photos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(feedControllerProvider.notifier).deletePost(post.id);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e is AppException ? e.message : 'Could not delete the post.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  List<Widget> _body(FeedState feed, FeedController controller, String? myId) {
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
            child: EmptyState(
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
            itemBuilder: (context, i) {
              final post = feed.posts[i];
              return PostCard(
                key: ValueKey(post.id),
                post: post,
                // Only your own identity has a profile screen so far (Phase 07 adds others).
                onAuthorTap: post.author.id == myId
                    ? () => context.go(AppRoutes.profile)
                    : null,
                onDelete: post.author.id == myId
                    ? () => _confirmDelete(post)
                    : null,
              );
            },
          ),
          SliverToBoxAdapter(
            child: _Footer(feed: feed, onRetry: controller.loadMore),
          ),
        ];
    }
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
