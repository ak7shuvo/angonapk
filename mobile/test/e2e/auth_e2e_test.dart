// End-to-end check of the real Dart client + AuthController against a running
// FastAPI server. Skipped unless a server URL is provided:
//
//   flutter test test/e2e --dart-define=E2E_API_BASE_URL=http://127.0.0.1:8000
//
// Uses plain `test` (not testWidgets) so real HTTP is allowed.
import 'package:angon/config/app_config.dart';
import 'package:angon/core/errors/app_exception.dart';
import 'package:angon/features/auth/auth_controller.dart';
import 'package:angon/models/user.dart';
import 'package:angon/services/providers.dart';
import 'package:angon/services/token_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _baseUrl = String.fromEnvironment('E2E_API_BASE_URL');

Future<void> _settle(ProviderContainer c) async {
  for (
    var i = 0;
    i < 100 && c.read(authControllerProvider) is AuthChecking;
    i++
  ) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

ProviderContainer _container(InMemoryTokenStorage storage) {
  final c = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(
        const AppConfig(
          environment: AppEnvironment.development,
          apiBaseUrl: _baseUrl,
        ),
      ),
      tokenStorageProvider.overrideWithValue(storage),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  final skip = _baseUrl.isEmpty ? 'set E2E_API_BASE_URL to run' : null;

  test('register → profile → restore → logout against the real API', () async {
    final suffix = DateTime.now().microsecondsSinceEpoch.toString();
    final username = 'e2e_$suffix'.substring(0, 20);
    final email = '$username@example.com';
    const password = 'correct-horse-1';

    final storage = InMemoryTokenStorage();
    final c = _container(storage);
    await _settle(c);
    expect(c.read(authControllerProvider), isA<Unauthenticated>());

    final auth = c.read(authControllerProvider.notifier);
    await auth.register(email: email, username: username, password: password);
    var state = c.read(authControllerProvider) as Authenticated;
    expect(state.user.username, username);
    expect(state.user.profile.isComplete, isFalse);
    expect(storage.current, isNotNull);
    final firstToken = storage.current!;

    // Duplicate registration surfaces per-field errors from the real server.
    final other = _container(InMemoryTokenStorage());
    await _settle(other);
    await expectLater(
      other
          .read(authControllerProvider.notifier)
          .register(email: email, username: username, password: password),
      throwsA(
        isA<ValidationException>().having(
          (e) => e.fieldErrors.keys.toSet(),
          'fields',
          {'email', 'username'},
        ),
      ),
    );

    await auth.updateProfile(
      displayName: 'রহিম',
      location: 'Sylhet',
      creatorType: CreatorType.photographer,
    );
    state = c.read(authControllerProvider) as Authenticated;
    expect(state.user.profile.isComplete, isTrue);
    expect(state.user.profile.displayName, 'রহিম');

    // A fresh app start with the stored token restores the session from the server.
    final restored = _container(InMemoryTokenStorage(firstToken));
    await _settle(restored);
    final restoredState = restored.read(authControllerProvider);
    expect(restoredState, isA<Authenticated>());
    expect(
      (restoredState as Authenticated).user.profile.creatorType,
      CreatorType.photographer,
    );

    // Wrong password is rejected.
    await expectLater(
      other
          .read(authControllerProvider.notifier)
          .login(identifier: username, password: 'wrong-pass-1'),
      throwsA(isA<UnauthorizedException>()),
    );
    await other
        .read(authControllerProvider.notifier)
        .login(identifier: email, password: password);
    expect(other.read(authControllerProvider), isA<Authenticated>());

    // Logout revokes the token on the server: the old token no longer restores.
    await auth.logout();
    expect(c.read(authControllerProvider), isA<Unauthenticated>());
    expect(storage.current, isNull);
    final afterLogout = _container(InMemoryTokenStorage(firstToken));
    await _settle(afterLogout);
    expect(afterLogout.read(authControllerProvider), isA<Unauthenticated>());
  }, skip: skip);
}
