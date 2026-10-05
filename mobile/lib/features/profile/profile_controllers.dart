import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/post.dart';
import '../../models/public_profile.dart';
import '../../models/story.dart';
import '../../services/providers.dart';
import '../../shared/paged/paged_controller.dart';
import '../auth/auth_controller.dart';
import '../social/engagement_controller.dart';
import '../stories/story_controllers.dart';

final userProfileProvider = FutureProvider.autoDispose
    .family<PublicProfile, String>(
      (ref, username) => ref.watch(userRepositoryProvider).profile(username),
    );

/// A user's posts (profile "Posts" and "Photos" tabs share it).
class UserPostsController extends PagedController<Post> {
  UserPostsController(this.username);
  final String username;

  @override
  Future<Page<Post>> fetch(String? cursor) async {
    final page = await ref
        .read(userRepositoryProvider)
        .posts(username, cursor: cursor);
    return (items: page.items, nextCursor: page.nextCursor);
  }

  @override
  String idOf(Post item) => item.id;

  @override
  void onLoaded(List<Post> items) =>
      ref.read(engagementProvider.notifier).ingest(items);
}

final userPostsProvider =
    NotifierProvider.family<UserPostsController, PagedState<Post>, String>(
      UserPostsController.new,
    );

class UserStoriesController extends PagedController<StorySummary> {
  UserStoriesController(this.username);
  final String username;

  @override
  Future<Page<StorySummary>> fetch(String? cursor) async {
    final page = await ref
        .read(storyRepositoryProvider)
        .feed(author: username, cursor: cursor);
    return (items: page.items, nextCursor: page.nextCursor);
  }

  @override
  String idOf(StorySummary item) => item.id;

  @override
  void onLoaded(List<StorySummary> items) =>
      ref.read(storyEngagementProvider.notifier).ingest(items);
}

final userStoriesProvider =
    NotifierProvider.family<
      UserStoriesController,
      PagedState<StorySummary>,
      String
    >(UserStoriesController.new);

/// Your saved posts (most recently saved first). Re-fetched whenever opened.
class SavedPostsController extends PagedController<Post> {
  @override
  Future<Page<Post>> fetch(String? cursor) async {
    ref.watch(
      authControllerProvider.select(
        (s) => s is Authenticated ? s.user.id : null,
      ),
    );
    final page = await ref
        .read(postRepositoryProvider)
        .savedPosts(cursor: cursor);
    return (items: page.items, nextCursor: page.nextCursor);
  }

  @override
  String idOf(Post item) => item.id;

  @override
  void onLoaded(List<Post> items) =>
      ref.read(engagementProvider.notifier).ingest(items);
}

final savedPostsProvider =
    NotifierProvider.autoDispose<SavedPostsController, PagedState<Post>>(
      SavedPostsController.new,
    );

class SavedStoriesController extends PagedController<StorySummary> {
  @override
  Future<Page<StorySummary>> fetch(String? cursor) async {
    ref.watch(
      authControllerProvider.select(
        (s) => s is Authenticated ? s.user.id : null,
      ),
    );
    final page = await ref.read(storyRepositoryProvider).saved(cursor: cursor);
    return (items: page.items, nextCursor: page.nextCursor);
  }

  @override
  String idOf(StorySummary item) => item.id;

  @override
  void onLoaded(List<StorySummary> items) =>
      ref.read(storyEngagementProvider.notifier).ingest(items);
}

final savedStoriesProvider =
    NotifierProvider.autoDispose<
      SavedStoriesController,
      PagedState<StorySummary>
    >(SavedStoriesController.new);
