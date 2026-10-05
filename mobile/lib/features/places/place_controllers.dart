import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/place.dart';
import '../../models/post.dart';
import '../../models/social.dart';
import '../../models/story.dart';
import '../../services/providers.dart';
import '../../shared/paged/paged_controller.dart';
import '../social/engagement_controller.dart';
import '../stories/story_controllers.dart';

final placeProvider = FutureProvider.autoDispose.family<PlaceDetail, String>(
  (ref, slug) => ref.watch(placeRepositoryProvider).get(slug),
);

class PlacePostsController extends PagedController<Post> {
  PlacePostsController(this.slug);
  final String slug;

  @override
  Future<Page<Post>> fetch(String? cursor) async {
    final page = await ref
        .read(placeRepositoryProvider)
        .posts(slug, cursor: cursor);
    return (items: page.items, nextCursor: page.nextCursor);
  }

  @override
  String idOf(Post item) => item.id;

  @override
  void onLoaded(List<Post> items) =>
      ref.read(engagementProvider.notifier).ingest(items);
}

final placePostsProvider = NotifierProvider.autoDispose
    .family<PlacePostsController, PagedState<Post>, String>(
      PlacePostsController.new,
    );

class PlaceStoriesController extends PagedController<StorySummary> {
  PlaceStoriesController(this.slug);
  final String slug;

  @override
  Future<Page<StorySummary>> fetch(String? cursor) async {
    final page = await ref
        .read(placeRepositoryProvider)
        .stories(slug, cursor: cursor);
    return (items: page.items, nextCursor: page.nextCursor);
  }

  @override
  String idOf(StorySummary item) => item.id;

  @override
  void onLoaded(List<StorySummary> items) =>
      ref.read(storyEngagementProvider.notifier).ingest(items);
}

final placeStoriesProvider = NotifierProvider.autoDispose
    .family<PlaceStoriesController, PagedState<StorySummary>, String>(
      PlaceStoriesController.new,
    );

class PlacePhotosController extends PagedController<PlacePhoto> {
  PlacePhotosController(this.slug);
  final String slug;

  @override
  Future<Page<PlacePhoto>> fetch(String? cursor) async {
    final page = await ref
        .read(placeRepositoryProvider)
        .photos(slug, cursor: cursor);
    return (items: page.items, nextCursor: page.nextCursor);
  }

  @override
  String idOf(PlacePhoto item) => item.id;
}

final placePhotosProvider = NotifierProvider.autoDispose
    .family<PlacePhotosController, PagedState<PlacePhoto>, String>(
      PlacePhotosController.new,
    );

final placeCreatorsProvider = FutureProvider.autoDispose
    .family<List<UserSummary>, String>(
      (ref, slug) => ref.watch(placeRepositoryProvider).creators(slug),
    );

/// Places a given user has documented.
final userPlacesProvider = FutureProvider.autoDispose
    .family<List<PlaceSummary>, String>(
      (ref, username) =>
          ref.watch(placeRepositoryProvider).documentedBy(username),
    );
