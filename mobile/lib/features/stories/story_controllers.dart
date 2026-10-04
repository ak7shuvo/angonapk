import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/social.dart';
import '../../models/story.dart';
import '../../services/providers.dart';
import '../../shared/paged/paged_controller.dart';
import '../auth/auth_controller.dart';

/// Live like/save state for stories (same optimistic-then-server pattern as posts).
class StoryEngagementController extends Notifier<Map<String, Engagement>> {
  final _inFlight = <String>{};

  @override
  Map<String, Engagement> build() => {};

  Engagement of(StorySummary s) =>
      state[s.id] ??
      Engagement(
        liked: s.likedByMe,
        likeCount: s.likeCount,
        saved: s.savedByMe,
        commentCount: 0,
      );

  void ingest(Iterable<StorySummary> stories) {
    final ids = stories.map((s) => s.id).toSet();
    if (state.keys.every((k) => !ids.contains(k))) return;
    state = {
      for (final e in state.entries)
        if (!ids.contains(e.key)) e.key: e.value,
    };
  }

  Future<void> toggleLike(StorySummary story) async {
    final key = 'like:${story.id}';
    if (!_inFlight.add(key)) return;
    final before = of(story);
    final want = !before.liked;
    state = {
      ...state,
      story.id: before.copyWith(
        liked: want,
        likeCount: (before.likeCount + (want ? 1 : -1)).clamp(0, 1 << 31),
      ),
    };
    try {
      final repo = ref.read(storyRepositoryProvider);
      final result = want
          ? await repo.like(story.id)
          : await repo.unlike(story.id);
      if (ref.mounted) {
        state = {
          ...state,
          story.id: of(story)
              .copyWith(liked: result.liked, likeCount: result.likeCount),
        };
      }
    } catch (_) {
      if (ref.mounted) state = {...state, story.id: before};
      rethrow;
    } finally {
      _inFlight.remove(key);
    }
  }

  Future<void> toggleSave(StorySummary story) async {
    final key = 'save:${story.id}';
    if (!_inFlight.add(key)) return;
    final before = of(story);
    final want = !before.saved;
    state = {...state, story.id: before.copyWith(saved: want)};
    try {
      final repo = ref.read(storyRepositoryProvider);
      want ? await repo.save(story.id) : await repo.unsave(story.id);
    } catch (_) {
      if (ref.mounted) state = {...state, story.id: before};
      rethrow;
    } finally {
      _inFlight.remove(key);
    }
  }
}

final storyEngagementProvider =
    NotifierProvider<StoryEngagementController, Map<String, Engagement>>(
      StoryEngagementController.new,
    );

/// Published stories, newest first (the Stories tab).
class StoriesFeedController extends PagedController<StorySummary> {
  @override
  Future<Page<StorySummary>> fetch(String? cursor) async {
    // A different signed-in user gets a fresh list.
    ref.watch(
      authControllerProvider.select(
        (s) => s is Authenticated ? s.user.id : null,
      ),
    );
    final page = await ref.read(storyRepositoryProvider).feed(cursor: cursor);
    return (items: page.items, nextCursor: page.nextCursor);
  }

  @override
  String idOf(StorySummary item) => item.id;

  @override
  void onLoaded(List<StorySummary> items) =>
      ref.read(storyEngagementProvider.notifier).ingest(items);
}

final storiesFeedProvider =
    NotifierProvider<StoriesFeedController, PagedState<StorySummary>>(
      StoriesFeedController.new,
    );

/// Your own stories by status: 'draft' or 'published'.
class MyStoriesController extends PagedController<StorySummary> {
  MyStoriesController(this.status);
  final String status;

  @override
  Future<Page<StorySummary>> fetch(String? cursor) async {
    ref.watch(
      authControllerProvider.select(
        (s) => s is Authenticated ? s.user.id : null,
      ),
    );
    final page = await ref
        .read(storyRepositoryProvider)
        .mine(status: status, cursor: cursor);
    return (items: page.items, nextCursor: page.nextCursor);
  }

  @override
  String idOf(StorySummary item) => item.id;

  @override
  void onLoaded(List<StorySummary> items) =>
      ref.read(storyEngagementProvider.notifier).ingest(items);
}

final myStoriesProvider =
    NotifierProvider.family<
      MyStoriesController,
      PagedState<StorySummary>,
      String
    >(MyStoriesController.new);

/// A full story by id or slug.
final storyProvider = FutureProvider.autoDispose.family<Story, String>((
  ref,
  id,
) async {
  final story = await ref.watch(storyRepositoryProvider).get(id);
  ref.read(storyEngagementProvider.notifier).ingest([story]);
  return story;
});

final relatedStoriesProvider = FutureProvider.autoDispose
    .family<List<StorySummary>, String>((ref, id) async {
      final stories = await ref.watch(storyRepositoryProvider).related(id);
      ref.read(storyEngagementProvider.notifier).ingest(stories);
      return stories;
    });

/// After a story is created/edited/published/deleted, lists must be refetched.
void invalidateStoryLists(WidgetRef ref) {
  ref.invalidate(storiesFeedProvider);
  ref.invalidate(myStoriesProvider);
}
