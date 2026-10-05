import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/media_url.dart';
import '../../models/post.dart';
import '../../models/public_profile.dart';
import '../../models/report.dart';
import '../../models/story.dart';
import '../../models/user.dart';
import '../../routing/routes.dart';
import '../auth/auth_controller.dart';
import '../../services/providers.dart';
import '../../shared/paged/paged_controller.dart';
import '../../shared/paged/paged_views.dart';
import '../../shared/widgets/widgets.dart';
import '../feed/widgets/post_tile.dart';
import '../moderation/report_sheet.dart';
import '../places/place_controllers.dart';
import '../places/widgets/place_tile.dart';
import '../social/follow_button.dart';
import '../social/follow_controller.dart';
import '../stories/widgets/story_cards.dart';
import 'profile_controllers.dart';

enum ProfileTab { posts, photos, stories, places, saved }

/// Which sections lead for which kind of creator (everyone gets all of them).
List<ProfileTab> tabsFor(CreatorType? type, {required bool isMe}) {
  final order = switch (type) {
    CreatorType.photographer || CreatorType.videographer => [
      ProfileTab.photos,
      ProfileTab.posts,
      ProfileTab.stories,
    ],
    CreatorType.storyteller ||
    CreatorType.blogger ||
    CreatorType.localStoryteller ||
    CreatorType.researcher => [
      ProfileTab.stories,
      ProfileTab.posts,
      ProfileTab.photos,
    ],
    _ => [ProfileTab.posts, ProfileTab.stories, ProfileTab.photos],
  };
  return [...order, ProfileTab.places, if (isMe) ProfileTab.saved];
}

String _tabLabel(ProfileTab t) => switch (t) {
  ProfileTab.posts => 'Posts',
  ProfileTab.photos => 'Photos',
  ProfileTab.stories => 'Stories',
  ProfileTab.places => 'Places',
  ProfileTab.saved => 'Saved',
};

/// A creator profile: cover, identity, stats and the person's work.
/// Used for the signed-in user's tab and for everyone else's profile.
class ProfileView extends ConsumerStatefulWidget {
  const ProfileView({super.key, required this.username, this.isOwnTab = false});
  final String username;
  final bool isOwnTab;

  @override
  ConsumerState<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends ConsumerState<ProfileView> {
  ProfileTab? _tab;
  bool _savedStories = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(userProfileProvider(widget.username));
    return async.when(
      loading: () => Scaffold(
        appBar: widget.isOwnTab ? null : AppBar(),
        body: const LoadingView(),
      ),
      error: (e, _) => Scaffold(
        appBar: widget.isOwnTab ? null : AppBar(),
        body: ErrorState(
          error: e,
          onRetry: () => ref.invalidate(userProfileProvider(widget.username)),
        ),
      ),
      data: _content,
    );
  }

  Widget _content(PublicProfile profile) {
    final tabs = tabsFor(profile.creatorType, isMe: profile.isMe);
    final tab = _tab != null && tabs.contains(_tab) ? _tab! : tabs.first;

    // Which paged list feeds the current tab (and what the pull-to-refresh refetches).
    late final List<Widget> slivers;
    final user = widget.username;

    Future<void> refreshAll() async {
      ref.invalidate(userProfileProvider(user));
    }

    switch (tab) {
      case ProfileTab.posts || ProfileTab.photos:
        final s = ref.watch(userPostsProvider(user));
        final c = ref.read(userPostsProvider(user).notifier);
        slivers = tab == ProfileTab.posts
            ? pagedSlivers<Post>(
                state: s,
                onRetry: c.retry,
                onLoadMore: c.loadMore,
                empty: EmptyState(
                  icon: Icons.photo_camera_outlined,
                  title: profile.isMe
                      ? 'Share your first discovery'
                      : 'No posts yet',
                  message: profile.isMe
                      ? 'Posts you share will appear here.'
                      : null,
                ),
                itemBuilder: (context, p) =>
                    PostTile(key: ValueKey(p.id), post: p),
              )
            : _photoSlivers(s, c);
        return _scaffold(
          profile,
          tabs,
          tab,
          slivers,
          refresh: () async {
            await refreshAll();
            await c.refresh();
          },
          loadMore: c.loadMore,
        );
      case ProfileTab.stories:
        final s = ref.watch(userStoriesProvider(user));
        final c = ref.read(userStoriesProvider(user).notifier);
        slivers = pagedSlivers<StorySummary>(
          state: s,
          onRetry: c.retry,
          onLoadMore: c.loadMore,
          empty: EmptyState(
            icon: Icons.auto_stories_outlined,
            title: profile.isMe ? 'Write your first story' : 'No stories yet',
            message: profile.isMe
                ? 'Long-form stories you publish will appear here.'
                : null,
            actionLabel: profile.isMe ? 'Write a story' : null,
            onAction: profile.isMe
                ? () => context.push(AppRoutes.storyNew)
                : null,
          ),
          itemBuilder: (context, st) =>
              StoryCard(key: ValueKey(st.id), story: st),
        );
        return _scaffold(
          profile,
          tabs,
          tab,
          slivers,
          refresh: () async {
            await refreshAll();
            await c.refresh();
          },
          loadMore: c.loadMore,
        );
      case ProfileTab.places:
        final places = ref.watch(userPlacesProvider(user));
        slivers = [
          places.when(
            loading: () => const SliverFillRemaining(
              hasScrollBody: false,
              child: LoadingView(),
            ),
            error: (e, _) => SliverFillRemaining(
              hasScrollBody: false,
              child: ErrorState(
                error: e,
                onRetry: () => ref.invalidate(userPlacesProvider(user)),
              ),
            ),
            data: (items) => items.isEmpty
                ? SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      icon: Icons.place_outlined,
                      title: profile.isMe
                          ? 'No places yet'
                          : 'No places documented yet',
                      message: profile.isMe
                          ? 'Tag a place when you post or write a story and it will appear here.'
                          : null,
                    ),
                  )
                : SliverList.builder(
                    itemCount: items.length,
                    itemBuilder: (context, i) => PlaceTile(place: items[i]),
                  ),
          ),
        ];
        return _scaffold(
          profile,
          tabs,
          tab,
          slivers,
          refresh: () async {
            await refreshAll();
            ref.invalidate(userPlacesProvider(user));
          },
          loadMore: () {},
        );
      case ProfileTab.saved:
        if (_savedStories) {
          final s = ref.watch(savedStoriesProvider);
          final c = ref.read(savedStoriesProvider.notifier);
          slivers = [
            _savedToggle(),
            ...pagedSlivers<StorySummary>(
              state: s,
              onRetry: c.retry,
              onLoadMore: c.loadMore,
              empty: const EmptyState(
                icon: Icons.bookmark_border_rounded,
                title: 'No saved stories',
                message: 'Tap Save on a story to keep it here.',
              ),
              itemBuilder: (context, st) =>
                  StoryCard(key: ValueKey(st.id), story: st),
            ),
          ];
          return _scaffold(
            profile,
            tabs,
            tab,
            slivers,
            refresh: c.refresh,
            loadMore: c.loadMore,
          );
        }
        final s = ref.watch(savedPostsProvider);
        final c = ref.read(savedPostsProvider.notifier);
        slivers = [
          _savedToggle(),
          ...pagedSlivers<Post>(
            state: s,
            onRetry: c.retry,
            onLoadMore: c.loadMore,
            empty: const EmptyState(
              icon: Icons.bookmark_border_rounded,
              title: 'No saved posts',
              message: 'Tap the bookmark on a post to keep it here.',
            ),
            itemBuilder: (context, p) => PostTile(key: ValueKey(p.id), post: p),
          ),
        ];
        return _scaffold(
          profile,
          tabs,
          tab,
          slivers,
          refresh: c.refresh,
          loadMore: c.loadMore,
        );
    }
  }

  Widget _savedToggle() => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.gutter,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          ChoiceChip(
            label: const Text('Posts'),
            selected: !_savedStories,
            onSelected: (_) => setState(() => _savedStories = false),
          ),
          const SizedBox(width: AppSpacing.sm),
          ChoiceChip(
            label: const Text('Stories'),
            selected: _savedStories,
            onSelected: (_) => setState(() => _savedStories = true),
          ),
        ],
      ),
    ),
  );

  /// Photography-first grid made from the user's post images.
  List<Widget> _photoSlivers(PagedState<Post> s, UserPostsController c) {
    final photos = [
      for (final p in s.items)
        for (final m in p.media)
          if (m.type == MediaType.image) (post: p, media: m),
    ];
    if (s.status == PagedStatus.ready && photos.isEmpty && !s.hasMore) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: Icons.photo_library_outlined,
            title: 'No photos yet',
          ),
        ),
      ];
    }
    if (s.status != PagedStatus.ready) {
      return pagedSlivers<Post>(
        state: s,
        onRetry: c.retry,
        onLoadMore: c.loadMore,
        empty: const SizedBox.shrink(),
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
          itemCount: photos.length,
          itemBuilder: (context, i) {
            final item = photos[i];
            return Semantics(
              button: true,
              label: item.media.altText ?? 'Photo from a post',
              child: InkWell(
                onTap: () => context.push(
                  AppRoutes.postPath(item.post.id),
                  extra: item.post,
                ),
                child: Image.network(
                  item.media.url,
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

  Widget _scaffold(
    PublicProfile profile,
    List<ProfileTab> tabs,
    ProfileTab tab,
    List<Widget> slivers, {
    required Future<void> Function() refresh,
    required VoidCallback loadMore,
  }) {
    return Scaffold(
      body: PagedScrollView(
        onRefresh: refresh,
        onLoadMore: loadMore,
        headerSlivers: [
          _ProfileAppBar(profile: profile, isOwnTab: widget.isOwnTab),
          SliverToBoxAdapter(child: _Header(profile: profile)),
          SliverToBoxAdapter(
            child: _TabRow(
              tabs: tabs,
              selected: tab,
              onSelect: (t) => setState(() => _tab = t),
            ),
          ),
        ],
        slivers: slivers,
      ),
    );
  }
}

class _ProfileAppBar extends ConsumerWidget {
  const _ProfileAppBar({required this.profile, required this.isOwnTab});
  final PublicProfile profile;
  final bool isOwnTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SliverAppBar(
    pinned: true,
    automaticallyImplyLeading: !isOwnTab,
    title: Text(
      '@${profile.username}',
      style: Theme.of(context).textTheme.titleMedium,
    ),
    actions: [
      if (profile.isMe) ...[
        IconButton(
          tooltip: 'Edit profile',
          icon: const Icon(Icons.edit_outlined),
          onPressed: () => context.push(AppRoutes.profileEdit),
        ),
        IconButton(
          tooltip: 'Account menu',
          icon: const Icon(Icons.more_vert),
          onPressed: () => _accountMenu(context, ref),
        ),
      ] else
        PopupMenuButton<String>(
          tooltip: 'Profile options',
          onSelected: (_) => showReportSheet(
            context,
            target: ReportTarget.user,
            targetId: profile.id,
          ),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'report', child: Text('Report profile')),
          ],
        ),
    ],
  );

  void _accountMenu(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Sign out'),
          onTap: () {
            Navigator.pop(sheet);
            ref.read(authControllerProvider.notifier).logout();
          },
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.profile});
  final PublicProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final base = ref.watch(appConfigProvider).apiBaseUrl;
    final overlay = ref.watch(
      followProvider.select((m) => m[profile.username]),
    );
    final followers = overlay?.followersCount ?? profile.counts.followers;
    final dark = theme.brightness == Brightness.dark;
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 18;
    final Widget action = profile.isMe
        ? OutlinedButton(
            onPressed: () => context.push(AppRoutes.profileEdit),
            style: OutlinedButton.styleFrom(minimumSize: const Size(110, 40)),
            child: const Text('Edit profile'),
          )
        : FollowButton(
            username: profile.username,
            initiallyFollowing: profile.isFollowing,
            followersCount: profile.counts.followers,
          );

    Widget stat(String label, int value, {VoidCallback? onTap}) => Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Column(
            children: [
              Text(
                '$value',
                style: AppTypography.serif(
                  size: 22,
                  weight: 650,
                  height: 1.2,
                ).copyWith(color: theme.colorScheme.onSurface),
              ),
              const SizedBox(height: 2),
              Text(label, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            AspectRatio(
              aspectRatio: 16 / 7,
              child: profile.coverUrl == null
                  ? ColoredBox(
                      color: dark ? AppColors.nightCard : AppColors.paperDeep,
                    )
                  : Image.network(
                      resolveMediaUrl(base, profile.coverUrl!),
                      fit: BoxFit.cover,
                      semanticLabel: 'Cover photo',
                      errorBuilder: (_, _, _) =>
                          ColoredBox(color: context.placeholder),
                    ),
            ),
            Positioned(
              left: AppSpacing.gutter,
              bottom: -44,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: theme.scaffoldBackgroundColor,
                  shape: BoxShape.circle,
                ),
                child: UserAvatar(
                  name: profile.name,
                  seed: profile.username,
                  imageUrl: profile.avatarUrl,
                  size: 88,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 52),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            profile.name,
                            style: AppTypography.serif(
                              size: 28,
                              weight: 700,
                              height: 1.25,
                            ).copyWith(color: theme.colorScheme.onSurface),
                          ),
                        ),
                        Text(
                          '@${profile.username}',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  if (!largeText) action,
                ],
              ),
              // With large text the button no longer fits beside the name.
              if (largeText) ...[const SizedBox(height: AppSpacing.sm), action],
              if (profile.creatorType != null || profile.location != null) ...[
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.sm,
                  children: [
                    if (profile.creatorType != null)
                      Text(
                        profile.creatorType!.label.toUpperCase(),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    if (profile.location != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.place_outlined,
                            size: 16,
                            color: context.inkSoft,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              profile.location!,
                              style: theme.textTheme.bodySmall,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
              if (profile.bio != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(profile.bio!, style: theme.textTheme.bodyLarge),
              ],
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  stat('Posts', profile.counts.posts),
                  stat('Stories', profile.counts.stories),
                  stat(
                    'Followers',
                    followers,
                    onTap: () =>
                        context.push(AppRoutes.followersPath(profile.username)),
                  ),
                  stat(
                    'Following',
                    profile.counts.following,
                    onTap: () =>
                        context.push(AppRoutes.followingPath(profile.username)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TabRow extends StatelessWidget {
  const _TabRow({
    required this.tabs,
    required this.selected,
    required this.onSelect,
  });
  final List<ProfileTab> tabs;
  final ProfileTab selected;
  final ValueChanged<ProfileTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.dividerTheme.color ?? AppColors.line),
        ),
      ),
      child: Row(
        children: [
          for (final t in tabs)
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
                      _tabLabel(t),
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
