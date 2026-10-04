import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/post.dart';
import '../../models/social.dart';
import '../../services/providers.dart';
import 'engagement_controller.dart';

class CommentsState {
  const CommentsState({
    this.loading = true,
    this.items = const [],
    this.nextCursor,
    this.error,
    this.loadingMore = false,
    this.sending = false,
  });

  final bool loading;
  final List<Comment> items;
  final String? nextCursor;
  final Object? error;
  final bool loadingMore;
  final bool sending;

  bool get hasMore => nextCursor != null;

  CommentsState copyWith({
    bool? loading,
    List<Comment>? items,
    Object? nextCursor = _keep,
    Object? error = _keep,
    bool? loadingMore,
    bool? sending,
  }) => CommentsState(
    loading: loading ?? this.loading,
    items: items ?? this.items,
    nextCursor: identical(nextCursor, _keep)
        ? this.nextCursor
        : nextCursor as String?,
    error: identical(error, _keep) ? this.error : error,
    loadingMore: loadingMore ?? this.loadingMore,
    sending: sending ?? this.sending,
  );
}

const _keep = Object();

/// Comments of one post. Items only change from server responses.
class CommentsController extends Notifier<CommentsState> {
  CommentsController(this.post);
  final Post post;

  @override
  CommentsState build() {
    Future.microtask(load);
    return const CommentsState();
  }

  Future<void> load() async {
    state = const CommentsState();
    try {
      final page = await ref.read(postRepositoryProvider).comments(post.id);
      if (!ref.mounted) return;
      state = CommentsState(
        loading: false,
        items: page.items,
        nextCursor: page.nextCursor,
      );
    } catch (e) {
      if (ref.mounted) state = CommentsState(loading: false, error: e);
    }
  }

  Future<void> loadMore() async {
    if (state.loading || state.loadingMore || !state.hasMore) return;
    state = state.copyWith(loadingMore: true);
    try {
      final page = await ref
          .read(postRepositoryProvider)
          .comments(post.id, cursor: state.nextCursor);
      if (!ref.mounted) return;
      final known = {for (final c in state.items) c.id};
      state = state.copyWith(
        items: [
          ...state.items,
          ...page.items.where((c) => !known.contains(c.id)),
        ],
        nextCursor: page.nextCursor,
        loadingMore: false,
      );
    } catch (_) {
      if (ref.mounted) state = state.copyWith(loadingMore: false);
    }
  }

  /// Throws on failure so the input keeps the user's text.
  Future<void> add(String body) async {
    state = state.copyWith(sending: true);
    try {
      final comment = await ref
          .read(postRepositoryProvider)
          .addComment(post.id, body);
      if (!ref.mounted) return;
      state = state.copyWith(items: [...state.items, comment], sending: false);
      ref.read(engagementProvider.notifier).commentCountChanged(post, 1);
    } catch (_) {
      if (ref.mounted) state = state.copyWith(sending: false);
      rethrow;
    }
  }

  Future<void> delete(Comment comment) async {
    await ref.read(postRepositoryProvider).deleteComment(comment.id);
    if (!ref.mounted) return;
    state = state.copyWith(
      items: [...state.items.where((c) => c.id != comment.id)],
    );
    ref.read(engagementProvider.notifier).commentCountChanged(post, -1);
  }
}

final commentsControllerProvider = NotifierProvider.autoDispose
    .family<CommentsController, CommentsState, Post>(CommentsController.new);
