import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/post.dart';
import '../../services/providers.dart';
import '../auth/auth_controller.dart';

enum FeedStatus { loading, ready, error }

class FeedState {
  const FeedState({
    this.status = FeedStatus.loading,
    this.posts = const [],
    this.nextCursor,
    this.error,
    this.loadingMore = false,
    this.loadMoreError,
    this.refreshError,
  });

  final FeedStatus status;
  final List<Post> posts;
  final String? nextCursor;

  /// Set when [status] is [FeedStatus.error] (initial load failed).
  final Object? error;
  final bool loadingMore;

  /// Pagination failed; existing posts stay visible with a retry footer.
  final Object? loadMoreError;

  /// Pull-to-refresh failed; existing posts stay visible.
  final Object? refreshError;

  bool get hasMore => nextCursor != null;
  bool get isEmpty => status == FeedStatus.ready && posts.isEmpty;

  FeedState copyWith({
    FeedStatus? status,
    List<Post>? posts,
    Object? nextCursor = _keep,
    Object? error = _keep,
    bool? loadingMore,
    Object? loadMoreError = _keep,
    Object? refreshError = _keep,
  }) => FeedState(
    status: status ?? this.status,
    posts: posts ?? this.posts,
    nextCursor: identical(nextCursor, _keep)
        ? this.nextCursor
        : nextCursor as String?,
    error: identical(error, _keep) ? this.error : error,
    loadingMore: loadingMore ?? this.loadingMore,
    loadMoreError: identical(loadMoreError, _keep)
        ? this.loadMoreError
        : loadMoreError,
    refreshError: identical(refreshError, _keep)
        ? this.refreshError
        : refreshError,
  );
}

const _keep = Object();

/// State for the Home feed. Server state is authoritative: the list is only
/// ever replaced by (or appended with) what the API returned.
class FeedController extends Notifier<FeedState> {
  /// Bumped on every full (re)load so late responses from older loads are ignored.
  int _generation = 0;

  @override
  FeedState build() {
    // A different signed-in user must never see the previous user's feed.
    ref.watch(
      authControllerProvider.select(
        (s) => s is Authenticated ? s.user.id : null,
      ),
    );
    _generation++;
    Future.microtask(_loadFirstPage);
    return const FeedState();
  }

  Future<void> _loadFirstPage() async {
    final gen = ++_generation;
    try {
      final page = await ref.read(postRepositoryProvider).fetchFeed();
      if (gen != _generation) return;
      state = FeedState(
        status: FeedStatus.ready,
        posts: page.items,
        nextCursor: page.nextCursor,
      );
    } catch (e) {
      if (gen != _generation) return;
      state = FeedState(status: FeedStatus.error, error: e);
    }
  }

  /// Retry after an initial-load failure.
  Future<void> retry() async {
    state = const FeedState();
    await _loadFirstPage();
  }

  /// Pull-to-refresh. Keeps the current posts if the refresh fails.
  Future<void> refresh() async {
    final gen = ++_generation;
    try {
      final page = await ref.read(postRepositoryProvider).fetchFeed();
      if (gen != _generation) return;
      state = FeedState(
        status: FeedStatus.ready,
        posts: page.items,
        nextCursor: page.nextCursor,
      );
    } catch (e) {
      if (gen != _generation) return;
      if (state.posts.isEmpty) {
        state = FeedState(status: FeedStatus.error, error: e);
      } else {
        state = state.copyWith(refreshError: e);
      }
    }
  }

  Future<void> loadMore() async {
    final current = state;
    if (current.status != FeedStatus.ready ||
        current.loadingMore ||
        !current.hasMore) {
      return;
    }
    final gen = _generation;
    state = current.copyWith(loadingMore: true, loadMoreError: null);
    try {
      final page = await ref
          .read(postRepositoryProvider)
          .fetchFeed(cursor: current.nextCursor);
      if (gen != _generation) return;
      final known = {for (final p in state.posts) p.id};
      state = state.copyWith(
        posts: [
          ...state.posts,
          ...page.items.where((p) => !known.contains(p.id)),
        ],
        nextCursor: page.nextCursor,
        loadingMore: false,
      );
    } catch (e) {
      if (gen != _generation) return;
      state = state.copyWith(loadingMore: false, loadMoreError: e);
    }
  }
}

final feedControllerProvider = NotifierProvider<FeedController, FeedState>(
  FeedController.new,
);
