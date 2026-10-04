import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_spacing.dart';
import '../../models/social.dart';
import '../../services/providers.dart';
import '../../shared/widgets/widgets.dart';
import 'follow_button.dart';

enum UserListKind { followers, following }

typedef UserListArgs = ({String username, UserListKind kind});

class UserListState {
  const UserListState({
    this.loading = true,
    this.items = const [],
    this.nextCursor,
    this.error,
    this.loadingMore = false,
  });
  final bool loading;
  final List<UserSummary> items;
  final String? nextCursor;
  final Object? error;
  final bool loadingMore;

  bool get hasMore => nextCursor != null;
}

class UserListController extends Notifier<UserListState> {
  UserListController(this.args);
  final UserListArgs args;

  Future<UserPage> _fetch(String? cursor) {
    final repo = ref.read(userRepositoryProvider);
    return args.kind == UserListKind.followers
        ? repo.followers(args.username, cursor: cursor)
        : repo.following(args.username, cursor: cursor);
  }

  @override
  UserListState build() {
    Future.microtask(load);
    return const UserListState();
  }

  Future<void> load() async {
    state = const UserListState();
    try {
      final page = await _fetch(null);
      if (ref.mounted) {
        state = UserListState(
          loading: false,
          items: page.items,
          nextCursor: page.nextCursor,
        );
      }
    } catch (e) {
      if (ref.mounted) state = UserListState(loading: false, error: e);
    }
  }

  Future<void> loadMore() async {
    if (state.loading || state.loadingMore || !state.hasMore) return;
    state = UserListState(
      loading: false,
      items: state.items,
      nextCursor: state.nextCursor,
      loadingMore: true,
    );
    try {
      final page = await _fetch(state.nextCursor);
      if (!ref.mounted) return;
      final known = {for (final u in state.items) u.id};
      state = UserListState(
        loading: false,
        items: [
          ...state.items,
          ...page.items.where((u) => !known.contains(u.id)),
        ],
        nextCursor: page.nextCursor,
      );
    } catch (_) {
      if (ref.mounted) {
        state = UserListState(
          loading: false,
          items: state.items,
          nextCursor: state.nextCursor,
        );
      }
    }
  }
}

final userListControllerProvider = NotifierProvider.autoDispose
    .family<UserListController, UserListState, UserListArgs>(
      UserListController.new,
    );

/// Followers or following of a user, with follow buttons.
class UserListScreen extends ConsumerWidget {
  const UserListScreen({super.key, required this.username, required this.kind});
  final String username;
  final UserListKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = (username: username, kind: kind);
    final state = ref.watch(userListControllerProvider(args));
    final controller = ref.read(userListControllerProvider(args).notifier);
    final title = kind == UserListKind.followers ? 'Followers' : 'Following';

    Widget body;
    if (state.loading) {
      body = const LoadingView();
    } else if (state.error != null) {
      body = ErrorState(error: state.error!, onRetry: controller.load);
    } else if (state.items.isEmpty) {
      body = EmptyState(
        icon: Icons.people_outline,
        title: kind == UserListKind.followers
            ? 'No followers yet'
            : 'Not following anyone yet',
      );
    } else {
      body = NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.extentAfter < 300) controller.loadMore();
          return false;
        },
        child: ListView.builder(
          itemCount: state.items.length + (state.hasMore ? 1 : 0),
          itemBuilder: (context, i) {
            if (i >= state.items.length) {
              return const Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            return UserTile(user: state.items[i]);
          },
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: body,
    );
  }
}

/// A person row: avatar, name, handle and a follow button.
class UserTile extends StatelessWidget {
  const UserTile({super.key, required this.user, this.onTap});
  final UserSummary user;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.gutter,
        vertical: 2,
      ),
      leading: UserAvatar(name: user.name, seed: user.username),
      title: Text(
        user.name,
        style: theme.textTheme.titleSmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text('@${user.username}', style: theme.textTheme.bodySmall),
      trailing: user.isMe
          ? null
          : FollowButton(
              username: user.username,
              initiallyFollowing: user.isFollowing,
              compact: true,
            ),
    );
  }
}
