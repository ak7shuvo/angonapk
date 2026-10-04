// Real Dart HTTP client + FeedController against a running FastAPI server.
//
//   flutter test test/e2e --dart-define=E2E_API_BASE_URL=http://127.0.0.1:8000
//
// Skipped unless the URL is provided. Uses plain `test` so real HTTP is allowed.
import 'package:angon/config/app_config.dart';
import 'package:angon/core/errors/app_exception.dart';
import 'package:angon/features/auth/auth_controller.dart';
import 'package:angon/features/feed/feed_controller.dart';
import 'package:angon/services/providers.dart';
import 'package:angon/services/token_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _baseUrl = String.fromEnvironment('E2E_API_BASE_URL');

Future<void> _until(bool Function() cond) async {
  for (var i = 0; i < 200 && !cond(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

ProviderContainer _container() {
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
  return c;
}

void main() {
  final skip = _baseUrl.isEmpty ? 'set E2E_API_BASE_URL to run' : null;

  test(
    'create, page through, fetch and delete posts via the real API',
    () async {
      final suffix = DateTime.now().microsecondsSinceEpoch.toString();
      final username = 'feed_$suffix'.substring(0, 20);
      final c = _container();
      c.read(authControllerProvider);
      await _until(() => c.read(authControllerProvider) is! AuthChecking);

      // Unauthenticated feed access is rejected by the server.
      await expectLater(
        c.read(postRepositoryProvider).fetchFeed(),
        throwsA(isA<UnauthorizedException>()),
      );

      await c
          .read(authControllerProvider.notifier)
          .register(
            email: '$username@example.com',
            username: username,
            password: 'correct-horse-1',
          );
      await c
          .read(authControllerProvider.notifier)
          .updateProfile(displayName: "নুসরাত");

      final repo = c.read(postRepositoryProvider);
      final bengali = await repo.createPost(
        body: 'আজ জাফলংয়ে পাহাড়ের নিচে স্বচ্ছ জল।',
        locationText: 'জাফলং, সিলেট',
        media: [
          {
            'type': 'image',
            'url': '/media/seed/placeholder-0.png',
            'width': 1200,
            'height': 900,
          },
        ],
      );
      await repo.createPost(body: 'Second post, English');
      final third = await repo.createPost(body: 'Third post');

      expect(bengali.author.username, username);
      expect(
        bengali.media.single.url,
        '$_baseUrl/media/seed/placeholder-0.png',
      );

      // Pagination through the real keyset cursor, 2 at a time.
      final first = await repo.fetchFeed(limit: 2);
      expect(first.items.first.id, third.id); // newest first
      expect(first.nextCursor, isNotNull);
      final second = await repo.fetchFeed(limit: 2, cursor: first.nextCursor);
      final ids = [...first.items, ...second.items].map((p) => p.id).toList();
      expect(ids.toSet().length, ids.length); // no duplicates across pages
      expect(ids, contains(bengali.id));

      // Round-trips Bengali text byte-for-byte.
      final fetched = await repo.getPost(bengali.id);
      expect(fetched.body, 'আজ জাফলংয়ে পাহাড়ের নিচে স্বচ্ছ জল।');
      expect(fetched.locationText, 'জাফলং, সিলেট');

      // The controller loads the same data through the real client.
      await _until(
        () => c.read(feedControllerProvider).status == FeedStatus.ready,
      );
      c.listen(feedControllerProvider, (_, _) {});
      await c.read(feedControllerProvider.notifier).refresh();
      expect(c.read(feedControllerProvider).posts.first.id, third.id);

      // Invalid input and delete semantics.
      await expectLater(repo.createPost(), throwsA(isA<ValidationException>()));
      await repo.deletePost(third.id);
      await expectLater(
        repo.getPost(third.id),
        throwsA(isA<NotFoundException>()),
      );
      await repo.deletePost(bengali.id);
      await repo.deletePost(
        ids.firstWhere((id) => id != bengali.id && id != third.id),
      );
    },
    skip: skip,
  );
}
