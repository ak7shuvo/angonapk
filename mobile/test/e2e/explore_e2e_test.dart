// Real client ↔ real API: Explore and search (uses the dev seed for places).
//   flutter test test/e2e --dart-define=E2E_API_BASE_URL=http://127.0.0.1:8000
import 'package:angon/config/app_config.dart';
import 'package:angon/features/auth/auth_controller.dart';
import 'package:angon/models/explore.dart';
import 'package:angon/models/user.dart';
import 'package:angon/services/providers.dart';
import 'package:angon/services/token_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _baseUrl = String.fromEnvironment('E2E_API_BASE_URL');

Future<ProviderContainer> _signedIn(String username) async {
  final c = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(
        const AppConfig(
          environment: AppEnvironment.development,
          apiBaseUrl: _baseUrl,
        ),
      ),
      tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
    ],
  );
  addTearDown(c.dispose);
  c.read(authControllerProvider);
  for (
    var i = 0;
    i < 100 && c.read(authControllerProvider) is AuthChecking;
    i++
  ) {
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  await c
      .read(authControllerProvider.notifier)
      .register(
        email: '$username@example.com',
        username: username,
        password: 'correct-horse-1',
      );
  return c;
}

void main() {
  final skip = _baseUrl.isEmpty ? 'set E2E_API_BASE_URL to run' : null;

  test('explore and search against the real API', () async {
    final stamp = DateTime.now().microsecondsSinceEpoch.toString();
    final name = 'ex_$stamp'.substring(0, 18);
    final c = await _signedIn(name);
    await c
        .read(authControllerProvider.notifier)
        .updateProfile(
          displayName: 'Explorer $stamp'.substring(0, 24),
          creatorType: CreatorType.blogger,
        );
    final marker = 'zq${stamp.substring(stamp.length - 8)}';
    final posts = c.read(postRepositoryProvider);
    final post = await posts.createPost(
      body: 'Unique $marker haor note',
      tags: ['nature'],
    );
    final story = await c
        .read(storyRepositoryProvider)
        .create(
          title: 'Story $marker',
          content: 'Body',
          tags: ['nature'],
          publish: true,
        );

    final explore = await c.read(exploreRepositoryProvider).explore();
    expect(explore.categories.map((x) => x.slug), contains('nature'));
    expect(
      explore.categories.firstWhere((x) => x.slug == 'nature').postCount,
      greaterThanOrEqualTo(1),
    );
    expect(explore.popularPlaces, isNotEmpty);
    expect(explore.trendingPosts.map((p) => p.id), contains(post.id));

    final repo = c.read(exploreRepositoryProvider);
    final all = await repo.search(marker);
    expect(all.posts.single.id, post.id);
    expect(all.stories.single.id, story.id);
    final places = await repo.search('জাফলং', type: SearchType.places);
    expect(places.places.first.slug, 'jaflong');
    expect(
      (await repo.search(name, type: SearchType.users)).users.single.username,
      name,
    );
    expect((await repo.search('definitely-no-match-$marker')).isEmpty, isTrue);

    // Category feeds use the tag filters.
    expect(
      (await posts.fetchFeed(tag: 'nature')).items.map((p) => p.id),
      contains(post.id),
    );
    expect(
      (await c.read(storyRepositoryProvider).feed(tag: 'nature')).items
          .map((s) => s.id),
      contains(story.id),
    );

    await posts.deletePost(post.id);
    await c.read(storyRepositoryProvider).delete(story.id);
  }, skip: skip);
}
