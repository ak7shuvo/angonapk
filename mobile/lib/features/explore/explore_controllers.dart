import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/debouncer.dart';
import '../../models/explore.dart';
import '../../models/post.dart';
import '../../models/story.dart';
import '../../services/providers.dart';
import '../../shared/paged/paged_controller.dart';
import '../auth/auth_controller.dart';
import '../social/engagement_controller.dart';
import '../stories/story_controllers.dart';

/// Explore home content. Re-fetched when the signed-in user changes or on refresh.
final exploreProvider = FutureProvider.autoDispose<ExploreData>((ref) async {
  ref.watch(
    authControllerProvider.select((s) => s is Authenticated ? s.user.id : null),
  );
  final data = await ref.watch(exploreRepositoryProvider).explore();
  ref.read(engagementProvider.notifier).ingest(data.trendingPosts);
  ref.read(storyEngagementProvider.notifier).ingest(data.featuredStories);
  return data;
});

/// Posts and stories carrying a category tag.
class CategoryPostsController extends PagedController<Post> {
  CategoryPostsController(this.tag);
  final String tag;

  @override
  Future<Page<Post>> fetch(String? cursor) async {
    final page = await ref
        .read(postRepositoryProvider)
        .fetchFeed(cursor: cursor, tag: tag);
    return (items: page.items, nextCursor: page.nextCursor);
  }

  @override
  String idOf(Post item) => item.id;

  @override
  void onLoaded(List<Post> items) =>
      ref.read(engagementProvider.notifier).ingest(items);
}

final categoryPostsProvider = NotifierProvider.autoDispose
    .family<CategoryPostsController, PagedState<Post>, String>(
      CategoryPostsController.new,
    );

class CategoryStoriesController extends PagedController<StorySummary> {
  CategoryStoriesController(this.tag);
  final String tag;

  @override
  Future<Page<StorySummary>> fetch(String? cursor) async {
    final page = await ref
        .read(storyRepositoryProvider)
        .feed(cursor: cursor, tag: tag);
    return (items: page.items, nextCursor: page.nextCursor);
  }

  @override
  String idOf(StorySummary item) => item.id;

  @override
  void onLoaded(List<StorySummary> items) =>
      ref.read(storyEngagementProvider.notifier).ingest(items);
}

final categoryStoriesProvider = NotifierProvider.autoDispose
    .family<CategoryStoriesController, PagedState<StorySummary>, String>(
      CategoryStoriesController.new,
    );

const searchPageSize = 20;

class SearchState {
  const SearchState({
    this.query = '',
    this.type = SearchType.all,
    this.loading = false,
    this.results = const SearchResults(),
    this.error,
    this.hasMore = false,
    this.loadingMore = false,
  });

  /// What the user typed (not necessarily what the results are for yet).
  final String query;
  final SearchType type;
  final bool loading;
  final SearchResults results;
  final Object? error;
  final bool hasMore;
  final bool loadingMore;

  bool get idle => query.trim().isEmpty;

  SearchState copyWith({
    String? query,
    SearchType? type,
    bool? loading,
    SearchResults? results,
    Object? error = _keep,
    bool? hasMore,
    bool? loadingMore,
  }) => SearchState(
    query: query ?? this.query,
    type: type ?? this.type,
    loading: loading ?? this.loading,
    results: results ?? this.results,
    error: identical(error, _keep) ? this.error : error,
    hasMore: hasMore ?? this.hasMore,
    loadingMore: loadingMore ?? this.loadingMore,
  );
}

const _keep = Object();

/// Debounced search over people, stories, posts and places.
class DiscoverySearchController extends Notifier<SearchState> {
  final _debounce = Debouncer(const Duration(milliseconds: 300));
  int _seq = 0;

  @override
  SearchState build() {
    ref.onDispose(_debounce.cancel);
    return const SearchState();
  }

  void setQuery(String q) {
    if (q.trim().isEmpty) {
      _seq++;
      _debounce.cancel();
      state = SearchState(type: state.type, query: q);
      return;
    }
    state = state.copyWith(query: q, loading: true, error: null);
    _debounce.run(_run);
  }

  void setType(SearchType type) {
    if (type == state.type) return;
    state = state.copyWith(
      type: type,
      results: const SearchResults(),
      hasMore: false,
    );
    if (!state.idle) {
      state = state.copyWith(loading: true, error: null);
      _run();
    }
  }

  Future<void> retry() {
    state = state.copyWith(loading: true, error: null);
    return _run();
  }

  int _countFor(SearchResults r, SearchType t) => switch (t) {
    SearchType.users => r.users.length,
    SearchType.stories => r.stories.length,
    SearchType.posts => r.posts.length,
    SearchType.places => r.places.length,
    SearchType.all => 0,
  };

  Future<void> _run() async {
    final seq = ++_seq;
    final q = state.query.trim();
    final type = state.type;
    try {
      final results = await ref
          .read(exploreRepositoryProvider)
          .search(
            q,
            type: type,
            limit: type == SearchType.all ? 5 : searchPageSize,
          );
      if (!ref.mounted || seq != _seq) return;
      ref.read(engagementProvider.notifier).ingest(results.posts);
      ref.read(storyEngagementProvider.notifier).ingest(results.stories);
      state = state.copyWith(
        loading: false,
        results: results,
        hasMore:
            type != SearchType.all &&
            _countFor(results, type) >= searchPageSize,
      );
    } catch (e) {
      if (!ref.mounted || seq != _seq) return;
      state = state.copyWith(loading: false, error: e);
    }
  }

  /// Next page for a single-type search.
  Future<void> loadMore() async {
    final type = state.type;
    if (type == SearchType.all ||
        !state.hasMore ||
        state.loadingMore ||
        state.loading) {
      return;
    }
    final seq = _seq;
    state = state.copyWith(loadingMore: true);
    try {
      final current = state.results;
      final page = await ref
          .read(exploreRepositoryProvider)
          .search(
            state.query.trim(),
            type: type,
            limit: searchPageSize,
            offset: _countFor(current, type),
          );
      if (!ref.mounted || seq != _seq) return;
      state = state.copyWith(
        loadingMore: false,
        hasMore: _countFor(page, type) >= searchPageSize,
        results: SearchResults(
          query: current.query,
          users: [...current.users, ...page.users],
          stories: [...current.stories, ...page.stories],
          posts: [...current.posts, ...page.posts],
          places: [...current.places, ...page.places],
        ),
      );
    } catch (_) {
      if (ref.mounted) state = state.copyWith(loadingMore: false);
    }
  }
}

final searchControllerProvider =
    NotifierProvider.autoDispose<DiscoverySearchController, SearchState>(
      DiscoverySearchController.new,
    );
