import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../models/explore.dart';
import '../../models/place.dart';
import '../../models/post.dart';
import '../../models/social.dart';
import '../../models/story.dart';
import '../../routing/routes.dart';
import '../../shared/widgets/widgets.dart';
import '../places/widgets/place_tile.dart';
import '../social/follow_button.dart';
import '../stories/widgets/story_cards.dart';
import 'explore_controllers.dart';

/// Explore: categories, what is trending, featured stories, places and creators.
class ExploreScreen extends ConsumerWidget {
  const ExploreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(exploreProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Explore'),
        actions: [
          IconButton(
            tooltip: 'Map',
            icon: const Icon(Icons.map_outlined),
            onPressed: () => context.push(AppRoutes.map),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(exploreProvider);
          await ref
              .read(exploreProvider.future)
              .catchError(
                (_) => const ExploreData(
                  categories: [],
                  trendingPosts: [],
                  featuredStories: [],
                  popularPlaces: [],
                  creators: [],
                ),
              );
        },
        child: async.when(
          loading: () => ListView(
            children: const [SizedBox(height: 240, child: LoadingView())],
          ),
          error: (e, _) => ListView(
            children: [
              SizedBox(
                height: 320,
                child: ErrorState(
                  error: e,
                  onRetry: () => ref.invalidate(exploreProvider),
                ),
              ),
            ],
          ),
          data: (data) => _Content(data: data),
        ),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.data});
  final ExploreData data;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
      children: [
        const _SearchField(),
        _Section(
          title: 'Categories',
          child: _Categories(items: data.categories),
        ),
        if (data.trendingPosts.isNotEmpty)
          _Section(
            title: 'Trending now',
            child: _TrendingPosts(posts: data.trendingPosts),
          ),
        if (data.featuredStories.isNotEmpty)
          _Section(
            title: 'Stories',
            child: _FeaturedStories(stories: data.featuredStories),
          ),
        if (data.popularPlaces.isNotEmpty)
          _Section(
            title: 'Places',
            action: TextButton(
              onPressed: () => context.push(AppRoutes.map),
              child: const Text('Open map'),
            ),
            child: _Places(places: data.popularPlaces),
          ),
        if (data.creators.isNotEmpty)
          _Section(
            title: 'Creators',
            child: _Creators(users: data.creators),
          ),
        if (!data.hasContent)
          const Padding(
            padding: EdgeInsets.only(top: AppSpacing.lg),
            child: EmptyState(
              icon: Icons.explore_outlined,
              title: 'Nothing to discover yet',
              message: 'As people share posts, stories and places they will appear here.',
            ),
          ),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.sm,
        AppSpacing.gutter,
        AppSpacing.sm,
      ),
      child: Semantics(
        button: true,
        label: 'Search places, people and stories',
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          onTap: () => context.push(AppRoutes.search),
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: BoxDecoration(
              color: theme.cardTheme.color,
              border: Border.all(
                color: theme.dividerTheme.color ?? AppColors.line,
              ),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: Row(
              children: [
                const Icon(Icons.search, color: AppColors.inkSoft),
                const SizedBox(width: AppSpacing.sm + 2),
                Text(
                  'Search places, people, stories',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.action});
  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.lg,
          AppSpacing.gutter,
          AppSpacing.sm,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Semantics(
              header: true,
              child: Text(
                title,
                style: AppTypography.serif(
                  size: 24,
                  weight: 650,
                  height: 1.3,
                ).copyWith(color: Theme.of(context).colorScheme.onSurface),
              ),
            ),
            ?action,
          ],
        ),
      ),
      child,
    ],
  );
}

/// Horizontally scrolling row whose height follows its tallest child, so cards
/// never overflow regardless of font metrics or the user's text-size setting.
class _Rail extends StatelessWidget {
  const _Rail({required this.children, this.gap = AppSpacing.md - 4});
  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(width: gap),
          children[i],
        ],
      ],
    ),
  );
}

class _Categories extends StatelessWidget {
  const _Categories({required this.items});
  final List<Category> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return _Rail(
      gap: AppSpacing.sm + 2,
      children: [
        for (final c in items)
          Semantics(
            button: true,
            label: '${c.label}, ${c.postCount + c.storyCount} items',
            child: InkWell(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              onTap: () => context.push(AppRoutes.categoryPath(c.slug)),
              child: Container(
                width: 132,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.md,
                ),
                decoration: BoxDecoration(
                  color: dark ? AppColors.nightCard : AppColors.paperDeep,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.label,
                      style: AppTypography.serif(
                        size: 19,
                        weight: 650,
                        height: 1.2,
                      ).copyWith(color: theme.colorScheme.onSurface),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${c.postCount + c.storyCount} ${c.postCount + c.storyCount == 1 ? 'item' : 'items'}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _TrendingPosts extends StatelessWidget {
  const _TrendingPosts({required this.posts});
  final List<Post> posts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Rail(
      children: [
        for (final post in posts)
          Builder(
            builder: (context) {
              final image = post.media
                  .where((m) => m.type == MediaType.image)
                  .firstOrNull;
              return Semantics(
                button: true,
                label: 'Post by ${post.author.name}',
                child: InkWell(
                  onTap: () =>
                      context.push(AppRoutes.postPath(post.id), extra: post),
                  child: SizedBox(
                    width: 200,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusSm,
                          ),
                          child: SizedBox(
                            height: 150,
                            width: 200,
                            child: image == null
                                ? Container(
                                    padding: const EdgeInsets.all(
                                      AppSpacing.md,
                                    ),
                                    color: AppColors.paperDeep,
                                    alignment: Alignment.topLeft,
                                    child: Text(
                                      post.body ?? '',
                                      maxLines: 5,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTypography.serif(
                                        size: 16,
                                        weight: 500,
                                        height: 1.5,
                                      ).copyWith(color: AppColors.ink),
                                    ),
                                  )
                                : Image.network(
                                    image.url,
                                    fit: BoxFit.cover,
                                    cacheWidth: 500,
                                    errorBuilder: (_, _, _) => const ColoredBox(
                                      color: AppColors.paperDeep,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          children: [
                            UserAvatar(
                              name: post.author.name,
                              seed: post.author.username,
                              imageUrl: post.author.avatarUrl,
                              size: 20,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                post.author.name,
                                style: theme.textTheme.bodySmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (post.likeCount > 0) ...[
                              const Icon(
                                Icons.favorite_rounded,
                                size: 13,
                                color: AppColors.inkFaint,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                '${post.likeCount}',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ],
                        ),
                        if (post.locationText != null || post.place != null)
                          Text(
                            post.locationText ?? post.place!.name,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _FeaturedStories extends StatelessWidget {
  const _FeaturedStories({required this.stories});
  final List<StorySummary> stories;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Rail(
      gap: AppSpacing.md,
      children: [
        for (final s in stories)
          Semantics(
            button: true,
            label: s.displayTitle,
            child: InkWell(
              onTap: () =>
                  context.push(AppRoutes.storyReadPath(s.slug), extra: s),
              child: SizedBox(
                width: 260,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                      child: SizedBox(
                        width: 260,
                        child: CoverImage(image: s.cover, aspectRatio: 16 / 10),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm + 2),
                    Text(
                      s.displayTitle,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.serif(
                        size: 19,
                        weight: 650,
                        height: 1.3,
                      ).copyWith(color: theme.colorScheme.onSurface),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${s.author.name}  ·  ${s.readingMinutes} min read',
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Places extends StatelessWidget {
  const _Places({required this.places});
  final List<PlaceSummary> places;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Rail(
      children: [
        for (final p in places)
          Semantics(
            button: true,
            label: p.name,
            child: InkWell(
              onTap: () => context.push(AppRoutes.placePath(p.slug)),
              child: SizedBox(
                width: 150,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PlaceThumb(
                      coverUrl: p.coverUrl,
                      size: 150,
                      radius: AppSpacing.radiusSm,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      p.name,
                      style: AppTypography.serif(
                        size: 17,
                        weight: 650,
                        height: 1.25,
                      ).copyWith(color: theme.colorScheme.onSurface),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (p.nameLocal != null)
                      Text(
                        p.nameLocal!,
                        style: theme.textTheme.bodySmall,
                        maxLines: 1,
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Creators extends StatelessWidget {
  const _Creators({required this.users});
  final List<UserSummary> users;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Rail(
      children: [
        for (final u in users)
          Container(
            width: 148,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              border: Border.all(
                color: theme.dividerTheme.color ?? AppColors.line,
              ),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: Column(
              children: [
                InkWell(
                  onTap: () => context.push(AppRoutes.userPath(u.username)),
                  child: Column(
                    children: [
                      UserAvatar(
                        name: u.name,
                        seed: u.username,
                        imageUrl: u.avatarUrl,
                        size: 52,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        u.name,
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _typeLabel(u.creatorType),
                        style: theme.textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sm + 2),
                FollowButton(
                  username: u.username,
                  initiallyFollowing: u.isFollowing,
                  compact: true,
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _typeLabel(String? api) {
    if (api == null) return '';
    return api
        .split('_')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}
