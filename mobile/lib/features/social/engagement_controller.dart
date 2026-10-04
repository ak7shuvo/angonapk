import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/post.dart';
import '../../models/social.dart';
import '../../services/providers.dart';

/// Live like / save / comment-count state for posts, shared by every list and
/// screen that shows the same post.
///
/// Taps are optimistic (instant), then replaced by the server's answer; if the
/// request fails the previous state is restored and the error is rethrown so the
/// UI can say so. Lists call [ingest] with freshly loaded posts so server data
/// always wins over stale local state.
class EngagementController extends Notifier<Map<String, Engagement>> {
  final _inFlight = <String>{};

  @override
  Map<String, Engagement> build() => {};

  Engagement of(Post post) => state[post.id] ?? Engagement.of(post);

  /// Freshly loaded posts are authoritative: drop any local overlay for them.
  void ingest(Iterable<Post> posts) {
    final ids = posts.map((p) => p.id).toSet();
    if (state.keys.every((k) => !ids.contains(k))) return;
    state = {
      for (final e in state.entries)
        if (!ids.contains(e.key)) e.key: e.value,
    };
  }

  void _set(String id, Engagement value) => state = {...state, id: value};

  void _restore(String id, Engagement previous, Post post) {
    state = {...state, id: previous};
  }

  Future<void> toggleLike(Post post) async {
    final key = 'like:${post.id}';
    if (!_inFlight.add(key)) return; // ignore taps while a request is pending
    final before = of(post);
    final wantLiked = !before.liked;
    _set(
      post.id,
      before.copyWith(
        liked: wantLiked,
        likeCount: (before.likeCount + (wantLiked ? 1 : -1)).clamp(0, 1 << 31),
      ),
    );
    try {
      final repo = ref.read(postRepositoryProvider);
      final result = wantLiked
          ? await repo.like(post.id)
          : await repo.unlike(post.id);
      if (!ref.mounted) return;
      _set(
        post.id,
        of(post).copyWith(liked: result.liked, likeCount: result.likeCount),
      );
    } catch (_) {
      if (ref.mounted) _restore(post.id, before, post);
      rethrow;
    } finally {
      _inFlight.remove(key);
    }
  }

  Future<void> toggleSave(Post post) async {
    final key = 'save:${post.id}';
    if (!_inFlight.add(key)) return;
    final before = of(post);
    final wantSaved = !before.saved;
    _set(post.id, before.copyWith(saved: wantSaved));
    try {
      final repo = ref.read(postRepositoryProvider);
      wantSaved ? await repo.save(post.id) : await repo.unsave(post.id);
    } catch (_) {
      if (ref.mounted) _restore(post.id, before, post);
      rethrow;
    } finally {
      _inFlight.remove(key);
    }
  }

  /// A comment was added/removed (server confirmed): keep the count in sync.
  void commentCountChanged(Post post, int delta) {
    final current = of(post);
    _set(
      post.id,
      current.copyWith(
        commentCount: (current.commentCount + delta).clamp(0, 1 << 31),
      ),
    );
  }
}

final engagementProvider =
    NotifierProvider<EngagementController, Map<String, Engagement>>(
      EngagementController.new,
    );
