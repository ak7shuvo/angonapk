import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef Page<T> = ({List<T> items, String? nextCursor});

enum PagedStatus { loading, ready, error }

class PagedState<T> {
  const PagedState({
    this.status = PagedStatus.loading,
    this.items = const [],
    this.nextCursor,
    this.error,
    this.loadingMore = false,
    this.loadMoreError,
    this.refreshError,
  });

  final PagedStatus status;
  final List<T> items;
  final String? nextCursor;
  final Object? error;
  final bool loadingMore;
  final Object? loadMoreError;
  final Object? refreshError;

  bool get hasMore => nextCursor != null;
  bool get isEmpty => status == PagedStatus.ready && items.isEmpty;

  PagedState<T> copyWith({
    PagedStatus? status,
    List<T>? items,
    Object? nextCursor = _keep,
    Object? error = _keep,
    bool? loadingMore,
    Object? loadMoreError = _keep,
    Object? refreshError = _keep,
  }) => PagedState<T>(
    status: status ?? this.status,
    items: items ?? this.items,
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

/// Cursor-paginated list with loading / error / empty states, pull-to-refresh and
/// load-more. Items only ever come from the server; late responses from a
/// superseded load are ignored. Subclasses provide [fetch] and [idOf].
abstract class PagedController<T> extends Notifier<PagedState<T>> {
  int _generation = 0;

  /// Fetch one page; [cursor] is null for the first page.
  Future<Page<T>> fetch(String? cursor);

  /// Stable id used to drop duplicates across pages.
  String idOf(T item);

  /// Called with each freshly loaded batch (e.g. to refresh engagement state).
  void onLoaded(List<T> items) {}

  @override
  PagedState<T> build() {
    Future.microtask(_first);
    return PagedState<T>();
  }

  Future<void> _first() async {
    final gen = ++_generation;
    try {
      final page = await fetch(null);
      if (!ref.mounted || gen != _generation) return;
      onLoaded(page.items);
      state = PagedState<T>(
        status: PagedStatus.ready,
        items: page.items,
        nextCursor: page.nextCursor,
      );
    } catch (e) {
      if (!ref.mounted || gen != _generation) return;
      state = PagedState<T>(status: PagedStatus.error, error: e);
    }
  }

  Future<void> retry() {
    state = PagedState<T>();
    return _first();
  }

  /// Pull-to-refresh; keeps showing the current items if it fails.
  Future<void> refresh() async {
    final gen = ++_generation;
    try {
      final page = await fetch(null);
      if (!ref.mounted || gen != _generation) return;
      onLoaded(page.items);
      state = PagedState<T>(
        status: PagedStatus.ready,
        items: page.items,
        nextCursor: page.nextCursor,
      );
    } catch (e) {
      if (!ref.mounted || gen != _generation) return;
      state = state.items.isEmpty
          ? PagedState<T>(status: PagedStatus.error, error: e)
          : state.copyWith(refreshError: e);
    }
  }

  Future<void> loadMore() async {
    final current = state;
    if (current.status != PagedStatus.ready ||
        current.loadingMore ||
        !current.hasMore) {
      return;
    }
    final gen = _generation;
    state = current.copyWith(loadingMore: true, loadMoreError: null);
    try {
      final page = await fetch(current.nextCursor);
      if (!ref.mounted || gen != _generation) return;
      onLoaded(page.items);
      final known = {for (final i in state.items) idOf(i)};
      state = state.copyWith(
        items: [
          ...state.items,
          ...page.items.where((i) => !known.contains(idOf(i))),
        ],
        nextCursor: page.nextCursor,
        loadingMore: false,
      );
    } catch (e) {
      if (!ref.mounted || gen != _generation) return;
      state = state.copyWith(loadingMore: false, loadMoreError: e);
    }
  }

  /// Local removal after a server-confirmed delete/unsave.
  void removeWhere(bool Function(T) test) {
    state = state.copyWith(items: [...state.items.where((i) => !test(i))]);
  }

  /// Swap an item for an updated copy (same id), keeping its position.
  void replaceItem(T item) {
    state = state.copyWith(
      items: [for (final i in state.items) idOf(i) == idOf(item) ? item : i],
    );
  }

  /// A server-confirmed new item appears at the top.
  void prepend(T item) {
    if (state.status != PagedStatus.ready) return;
    state = state.copyWith(
      items: [item, ...state.items.where((i) => idOf(i) != idOf(item))],
    );
  }
}
