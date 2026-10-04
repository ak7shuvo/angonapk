import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/providers.dart';

/// Ids of posts the user has deleted this session. Every list renders through
/// `PostTile`, which hides these, so one deletion updates all lists at once.
class PostRemovals extends Notifier<Set<String>> {
  @override
  Set<String> build() => {};

  /// Deletes on the server; the post disappears only after that succeeds.
  Future<void> delete(String postId) async {
    await ref.read(postRepositoryProvider).deletePost(postId);
    if (ref.mounted) state = {...state, postId};
  }
}

final postRemovalsProvider = NotifierProvider<PostRemovals, Set<String>>(
  PostRemovals.new,
);
