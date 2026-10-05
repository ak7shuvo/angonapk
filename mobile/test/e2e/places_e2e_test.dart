// Real client ↔ real API: places. Needs the development seed
// (`python -m scripts.seed_dev`) so there are places to find.
//   flutter test test/e2e --dart-define=E2E_API_BASE_URL=http://127.0.0.1:8000
import 'package:angon/config/app_config.dart';
import 'package:angon/core/errors/app_exception.dart';
import 'package:angon/features/auth/auth_controller.dart';
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

  test('places against the real API', () async {
    final stamp = DateTime.now().microsecondsSinceEpoch.toString();
    final user = await _signedIn('pl_$stamp'.substring(0, 18));
    final places = user.read(placeRepositoryProvider);

    // Search in English and Bengali.
    final english = await places.search(q: 'jaflong');
    expect(english.items.map((p) => p.slug), contains('jaflong'));
    final bengali = await places.search(q: 'জাফলং');
    expect(bengali.items.first.nameLocal, 'জাফলং');
    final all = await places.search(limit: 100);
    expect(all.total, greaterThanOrEqualTo(12));

    // Bounding box (Sylhet region) and proximity.
    final box = await places.search(
      bounds: (minLat: 24.0, maxLat: 26.0, minLng: 91.0, maxLng: 93.0),
    );
    expect(
      box.items.map((p) => p.slug),
      containsAll(['jaflong', 'sreemangal']),
    );
    expect(box.items.map((p) => p.slug), isNot(contains('coxs-bazar')));
    final near = await places.search(
      near: (lat: 25.17, lng: 92.02),
      radiusKm: 30,
    );
    expect(near.items.first.slug, 'jaflong');
    expect(near.items.first.distanceKm, lessThan(5));

    // Detail + seed flag.
    final detail = await places.get('jaflong');
    expect(detail.isSeed, isTrue);
    expect(detail.upazila, 'Gowainghat');
    await expectLater(
      places.get('atlantis'),
      throwsA(isA<NotFoundException>()),
    );

    // Tag a place on a post and a story; they show up on the place.
    final post = await user
        .read(postRepositoryProvider)
        .createPost(body: 'পাথরের নদী', placeId: detail.id);
    expect(post.place!.slug, 'jaflong');
    expect(post.locationText, 'Jaflong'); // filled from the place
    final story = await user
        .read(storyRepositoryProvider)
        .create(
          title: 'Jaflong notes',
          content: 'Text',
          placeId: detail.id,
          publish: true,
        );
    expect(story.place!.name, 'Jaflong');
    expect(
      (await places.posts('jaflong')).items.map((p) => p.id),
      contains(post.id),
    );
    expect(
      (await places.stories('jaflong')).items.map((s) => s.id),
      contains(story.id),
    );
    expect(
      (await places.creators('jaflong')).map((u) => u.username),
      isNotEmpty,
    );
    final me = (user.read(authControllerProvider) as Authenticated).user;
    expect((await places.documentedBy(me.username)).map((p) => p.slug), [
      'jaflong',
    ]);
    expect(
      (await user.read(userRepositoryProvider).profile(me.username))
          .counts
          .places,
      1,
    );

    await expectLater(
      user
          .read(postRepositoryProvider)
          .createPost(
            body: 'x',
            placeId: '00000000-0000-0000-0000-000000000000',
          ),
      throwsA(isA<ValidationException>()),
    );
    await user.read(postRepositoryProvider).deletePost(post.id);
    await user.read(storyRepositoryProvider).delete(story.id);
  }, skip: skip);
}
