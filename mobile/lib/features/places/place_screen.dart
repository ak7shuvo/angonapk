import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/media_url.dart';
import '../../models/place.dart';
import '../../models/post.dart';
import '../../models/story.dart';
import '../../routing/routes.dart';
import '../../services/providers.dart';
import '../../shared/paged/paged_controller.dart';
import '../../shared/paged/paged_views.dart';
import '../../shared/widgets/widgets.dart';
import '../feed/widgets/post_tile.dart';
import '../social/user_list_screen.dart';
import '../stories/widgets/story_cards.dart';
import 'place_controllers.dart';

enum _PlaceTab { posts, stories, photos, creators }

/// A destination page: where posts, stories, photographs and creators meet.
class PlaceScreen extends ConsumerStatefulWidget {
  const PlaceScreen({super.key, required this.slug});
  final String slug;

  @override
  ConsumerState<PlaceScreen> createState() => _PlaceScreenState();
}

class _PlaceScreenState extends ConsumerState<PlaceScreen> {
  _PlaceTab _tab = _PlaceTab.posts;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(placeProvider(widget.slug));
    return async.when(
      loading: () => Scaffold(appBar: AppBar(), body: const LoadingView()),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: ErrorState(
          error: e,
          onRetry: () => ref.invalidate(placeProvider(widget.slug)),
        ),
      ),
      data: _content,
    );
  }

  Widget _content(PlaceDetail place) {
    final slug = widget.slug;
    late final List<Widget> slivers;
    late final Future<void> Function() refresh;
    late final VoidCallback loadMore;

    switch (_tab) {
      case _PlaceTab.posts:
        final s = ref.watch(placePostsProvider(slug));
        final c = ref.read(placePostsProvider(slug).notifier);
        slivers = pagedSlivers<Post>(
          state: s,
          onRetry: c.retry,
          onLoadMore: c.loadMore,
          empty: EmptyState(
            icon: Icons.photo_camera_outlined,
            title: 'No posts from ${place.name} yet',
            message: 'Share a moment from here and tag the place.',
            actionLabel: 'Share a discovery',
            onAction: () => context.go(AppRoutes.create),
          ),
          itemBuilder: (context, p) => PostTile(key: ValueKey(p.id), post: p),
        );
        refresh = c.refresh;
        loadMore = c.loadMore;
      case _PlaceTab.stories:
        final s = ref.watch(placeStoriesProvider(slug));
        final c = ref.read(placeStoriesProvider(slug).notifier);
        slivers = pagedSlivers<StorySummary>(
          state: s,
          onRetry: c.retry,
          onLoadMore: c.loadMore,
          empty: EmptyState(
            icon: Icons.auto_stories_outlined,
            title: 'No stories about ${place.name} yet',
            actionLabel: 'Write a story',
            onAction: () => context.push(AppRoutes.storyNew),
          ),
          itemBuilder: (context, st) =>
              StoryCard(key: ValueKey(st.id), story: st),
        );
        refresh = c.refresh;
        loadMore = c.loadMore;
      case _PlaceTab.photos:
        final s = ref.watch(placePhotosProvider(slug));
        final c = ref.read(placePhotosProvider(slug).notifier);
        slivers = _photoSlivers(s, c);
        refresh = c.refresh;
        loadMore = c.loadMore;
      case _PlaceTab.creators:
        final async = ref.watch(placeCreatorsProvider(slug));
        slivers = [
          async.when(
            loading: () => const SliverFillRemaining(
              hasScrollBody: false,
              child: LoadingView(),
            ),
            error: (e, _) => SliverFillRemaining(
              hasScrollBody: false,
              child: ErrorState(
                error: e,
                onRetry: () => ref.invalidate(placeCreatorsProvider(slug)),
              ),
            ),
            data: (users) => users.isEmpty
                ? const SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      icon: Icons.people_outline,
                      title: 'No creators yet',
                    ),
                  )
                : SliverList.builder(
                    itemCount: users.length,
                    itemBuilder: (context, i) => UserTile(
                      user: users[i],
                      onTap: () =>
                          context.push(AppRoutes.userPath(users[i].username)),
                    ),
                  ),
          ),
        ];
        refresh = () async => ref.invalidate(placeCreatorsProvider(slug));
        loadMore = () {};
    }

    return Scaffold(
      body: PagedScrollView(
        onRefresh: () async {
          ref.invalidate(placeProvider(slug));
          await refresh();
        },
        onLoadMore: loadMore,
        headerSlivers: [
          _PlaceAppBar(place: place),
          SliverToBoxAdapter(child: _PlaceHeader(place: place)),
          SliverToBoxAdapter(
            child: _Tabs(
              selected: _tab,
              onSelect: (t) => setState(() => _tab = t),
            ),
          ),
        ],
        slivers: slivers,
      ),
    );
  }

  List<Widget> _photoSlivers(
    PagedState<PlacePhoto> s,
    PlacePhotosController c,
  ) {
    if (s.status != PagedStatus.ready || s.isEmpty) {
      return pagedSlivers<PlacePhoto>(
        state: s,
        onRetry: c.retry,
        onLoadMore: c.loadMore,
        empty: const EmptyState(
          icon: Icons.photo_library_outlined,
          title: 'No photos yet',
        ),
        itemBuilder: (_, _) => const SizedBox.shrink(),
      );
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.all(2),
        sliver: SliverGrid.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 2,
            crossAxisSpacing: 2,
          ),
          itemCount: s.items.length,
          itemBuilder: (context, i) {
            final photo = s.items[i];
            return Semantics(
              button: true,
              label: 'Photo from ${widget.slug}',
              child: InkWell(
                onTap: () => context.push(AppRoutes.postPath(photo.postId)),
                child: Image.network(
                  photo.url,
                  fit: BoxFit.cover,
                  cacheWidth: 400,
                  errorBuilder: (_, _, _) =>
                      ColoredBox(color: context.placeholder),
                ),
              ),
            );
          },
        ),
      ),
      SliverToBoxAdapter(
        child: s.hasMore
            ? const Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            : const SizedBox(height: AppSpacing.xl),
      ),
    ];
  }
}

class _PlaceAppBar extends ConsumerWidget {
  const _PlaceAppBar({required this.place});
  final PlaceDetail place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasCover = place.coverUrl != null;
    final base = ref.watch(appConfigProvider).apiBaseUrl;
    return SliverAppBar(
      pinned: true,
      expandedHeight: hasCover
          ? MediaQuery.sizeOf(context).height * 0.34
          : null,
      leadingWidth: 56,
      leading: Padding(
        padding: const EdgeInsets.all(4), // 48dp tap target
        child: IconButton.filled(
          tooltip: 'Back',
          style: IconButton.styleFrom(
            backgroundColor: hasCover ? Colors.black45 : null,
            foregroundColor: hasCover ? Colors.white : null,
          ),
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(AppRoutes.home),
        ),
      ),
      actions: [
        IconButton(
          tooltip: 'Show on map',
          icon: const Icon(Icons.map_outlined),
          onPressed: () => context.push('${AppRoutes.map}?place=${place.slug}'),
        ),
      ],
      flexibleSpace: hasCover
          ? FlexibleSpaceBar(
              collapseMode: CollapseMode.parallax,
              background: SizedBox.expand(
                child: Image.network(
                  resolveMediaUrl(base, place.coverUrl!),
                  fit: BoxFit.cover,
                  semanticLabel: 'Photo of ${place.name}',
                  errorBuilder: (_, _, _) =>
                      ColoredBox(color: context.placeholder),
                ),
              ),
            )
          : null,
    );
  }
}

class _PlaceHeader extends StatelessWidget {
  const _PlaceHeader({required this.place});
  final PlaceDetail place;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.lg,
        AppSpacing.gutter,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (place.locationLine.isNotEmpty)
            Text(
              place.locationLine.toUpperCase(),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          Semantics(
            header: true,
            child: Text(
              place.name,
              style: AppTypography.serif(
                size: 34,
                weight: 700,
                height: 1.2,
              ).copyWith(color: theme.colorScheme.onSurface),
            ),
          ),
          if (place.nameLocal != null)
            Text(
              place.nameLocal!,
              style: AppTypography.serif(
                size: 22,
                weight: 500,
                height: 1.5,
              ).copyWith(color: context.inkSoft),
            ),
          if (place.description.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(place.description, style: theme.textTheme.bodyLarge),
          ],
          if (place.isSeed) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Development sample content — not verified information.',
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Text(
            '${place.postCount} posts  ·  ${place.storyCount} stories',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.selected, required this.onSelect});
  final _PlaceTab selected;
  final ValueChanged<_PlaceTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String label(_PlaceTab t) => switch (t) {
      _PlaceTab.posts => 'Posts',
      _PlaceTab.stories => 'Stories',
      _PlaceTab.photos => 'Photos',
      _PlaceTab.creators => 'Creators',
    };
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.dividerTheme.color ?? AppColors.line),
        ),
      ),
      child: Row(
        children: [
          for (final t in _PlaceTab.values)
            Expanded(
              child: Semantics(
                selected: t == selected,
                button: true,
                child: InkWell(
                  onTap: () => onSelect(t),
                  child: Container(
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: t == selected
                              ? theme.colorScheme.primary
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Text(
                      label(t),
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: t == selected
                            ? theme.colorScheme.onSurface
                            : theme.textTheme.bodySmall?.color,
                      ),
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

/// Convenience used by posts/stories to open a place.
void openPlace(BuildContext context, PlaceBrief place) =>
    context.push(AppRoutes.placePath(place.slug));
