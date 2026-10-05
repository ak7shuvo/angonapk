// Real client ↔ real API: map data (needs the dev seed for places).
//   flutter test test/e2e --dart-define=E2E_API_BASE_URL=http://127.0.0.1:8000
import 'package:angon/config/app_config.dart';
import 'package:angon/features/auth/auth_controller.dart';
import 'package:angon/services/providers.dart';
import 'package:angon/services/token_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _baseUrl = String.fromEnvironment('E2E_API_BASE_URL');

void main() {
  final skip = _baseUrl.isEmpty ? 'set E2E_API_BASE_URL to run' : null;

  test('nearby places and content against the real API', () async {
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
    final stamp = DateTime.now().microsecondsSinceEpoch.toString();
    final name = 'mp_$stamp'.substring(0, 18);
    await c
        .read(authControllerProvider.notifier)
        .register(
          email: '$name@example.com',
          username: name,
          password: 'correct-horse-1',
        );
    final places = c.read(placeRepositoryProvider);
    final jaflong = await places.get('jaflong');
    final post = await c
        .read(postRepositoryProvider)
        .createPost(body: 'Map test $stamp', placeId: jaflong.id);

    final nearby = await places.nearby(
      jaflong.latitude,
      jaflong.longitude,
      radiusKm: 15,
    );
    expect(nearby.places.first.slug, 'jaflong');
    expect(nearby.places.first.distanceKm, 0);
    expect(
      nearby.places.map((p) => p.slug),
      contains('bichanakandi'),
    ); // a few km away
    expect(nearby.places.map((p) => p.slug), isNot(contains('coxs-bazar')));
    expect(nearby.posts.map((p) => p.id), contains(post.id));

    final inView = await places.search(
      bounds: (minLat: 24.0, maxLat: 26.0, minLng: 91.0, maxLng: 93.0),
    );
    expect(inView.items.map((p) => p.slug), contains('jaflong'));
    await c.read(postRepositoryProvider).deletePost(post.id);
  }, skip: skip);
}
