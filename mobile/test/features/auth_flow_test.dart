import 'package:angon/core/errors/app_exception.dart';
import 'package:angon/services/token_storage.dart';
import 'package:angon/features/auth/auth_controller.dart';
import 'package:angon/services/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_backend.dart';
import '../support/harness.dart';

late FakeBackend backend;
late InMemoryTokenStorage storage;

Future<void> boot(WidgetTester tester) async {
  // Tall surface so lazily-built list children (long forms) are all on screen.
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(buildTestApp(backend, storage));
  await tester.pumpAndSettle();
}

Finder field(String label) => find.widgetWithText(TextFormField, label);

Future<void> tapText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    backend = FakeBackend();
    storage = InMemoryTokenStorage();
  });

  testWidgets('cold start without a session lands on Welcome', (tester) async {
    await boot(tester);
    expect(find.text('Create account'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('HOME'), findsNothing);
    expect(backend.calls, isEmpty); // nothing to verify without a token
  });

  testWidgets('unauthenticated users cannot reach app tabs', (tester) async {
    await boot(tester);
    expect(find.text('HOME'), findsNothing);
  });

  testWidgets('register → profile setup → home, token persisted', (
    tester,
  ) async {
    await boot(tester);
    await tapText(tester, 'Create account');
    expect(find.text('Create your account'), findsOneWidget);

    // Client-side validation blocks an empty submit; nothing hits the API.
    await tapText(tester, 'Create account'); // button (title differs)
    expect(find.text('Enter your email'), findsOneWidget);
    expect(find.text('Choose a username'), findsOneWidget);
    expect(backend.calls, isEmpty);

    await tester.enterText(field('Email'), 'rahim@example.com');
    await tester.enterText(field('Username'), 'rahim_bd');
    await tester.enterText(field('Password'), 'correct-horse-1');
    await tapText(tester, 'Create account');

    // Authenticated but incomplete profile → forced into setup.
    expect(find.text('Tell us about you'), findsOneWidget);
    expect(storage.current, isNotNull);
    expect(backend.calls, contains('POST /auth/register'));

    // Name and creator type are required.
    await tapText(tester, 'Continue');
    expect(find.text('Enter your name'), findsOneWidget);
    expect(find.text('Pick what describes you best'), findsOneWidget);
    expect(find.text('Tell us about you'), findsOneWidget);

    await tester.enterText(field('Name'), 'রহিম');
    await tapText(tester, 'Photographer');
    await tapText(tester, 'Continue');

    expect(find.text('HOME'), findsOneWidget);
    expect(find.text('Tell us about you'), findsNothing);
    expect(
      backend.users['rahim_bd']!['profile']['creator_type'],
      'photographer',
    );
  });

  testWidgets('register shows server-side duplicate errors on the field', (
    tester,
  ) async {
    backend.seedUser('rahim_bd', 'pw-12345678');
    await boot(tester);
    await tapText(tester, 'Create account');
    await tester.enterText(field('Email'), 'new@example.com');
    await tester.enterText(field('Username'), 'rahim_bd');
    await tester.enterText(field('Password'), 'correct-horse-1');
    await tapText(tester, 'Create account');

    expect(find.text('Username is already taken'), findsOneWidget);
    expect(find.text('Create your account'), findsOneWidget);
    expect(storage.current, isNull);
  });

  testWidgets('login with wrong password shows error and stays signed out', (
    tester,
  ) async {
    backend.seedUser('rahim_bd', 'right-password');
    await boot(tester);
    await tapText(tester, 'Sign in');
    await tester.enterText(field('Email or username'), 'rahim_bd');
    await tester.enterText(field('Password'), 'wrong-password');
    await tapText(tester, 'Sign in');

    expect(find.text('Incorrect email/username or password'), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(storage.current, isNull);
  });

  testWidgets('login success with completed profile goes straight to Home', (
    tester,
  ) async {
    backend.seedUser('rahim_bd', 'right-password');
    await boot(tester);
    await tapText(tester, 'Sign in');
    await tester.enterText(field('Email or username'), 'rahim_bd');
    await tester.enterText(field('Password'), 'right-password');
    await tapText(tester, 'Sign in');

    expect(find.text('HOME'), findsOneWidget);
    expect(storage.current, isNotNull);
  });

  testWidgets('login with incomplete profile is sent to profile setup', (
    tester,
  ) async {
    backend.seedUser('rahim_bd', 'right-password', complete: false);
    await boot(tester);
    await tapText(tester, 'Sign in');
    await tester.enterText(field('Email or username'), 'rahim_bd');
    await tester.enterText(field('Password'), 'right-password');
    await tapText(tester, 'Sign in');
    expect(find.text('Tell us about you'), findsOneWidget);
  });

  testWidgets('valid stored session is restored without logging in', (
    tester,
  ) async {
    backend.seedUser('rahim_bd', 'pw-12345678');
    storage = InMemoryTokenStorage(backend.issueToken('rahim_bd'));
    await boot(tester);
    expect(find.text('HOME'), findsOneWidget);
    expect(backend.calls, contains('GET /users/me'));
  });

  testWidgets('rejected stored token is cleared and user sees Welcome', (
    tester,
  ) async {
    storage = InMemoryTokenStorage('stale-token');
    await boot(tester);
    expect(find.text('Create account'), findsOneWidget);
    expect(storage.current, isNull);
  });

  testWidgets('offline at startup keeps the token and offers retry', (
    tester,
  ) async {
    backend.seedUser('rahim_bd', 'pw-12345678');
    storage = InMemoryTokenStorage(backend.issueToken('rahim_bd'));
    backend.failWith = const NetworkException();
    await boot(tester);

    expect(find.textContaining('Cannot reach ANGON'), findsOneWidget);
    expect(storage.current, isNotNull); // not signed out by a network blip

    backend.failWith = null;
    await tapText(tester, 'Try again');
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets(
    'sign out revokes server-side, clears token, returns to Welcome',
    (tester) async {
      backend.seedUser('rahim_bd', 'pw-12345678');
      final token = backend.issueToken('rahim_bd');
      storage = InMemoryTokenStorage(token);
      await boot(tester);

      await tapText(tester, 'PROFILE');
      expect(find.text('@rahim_bd'), findsWidgets);
      await tester.tap(find.byTooltip('Account menu'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Sign out');

      expect(find.text('Create account'), findsOneWidget);
      expect(storage.current, isNull);
      expect(backend.calls, contains('POST /auth/logout'));
      expect(backend.revoked, contains(token));
    },
  );

  test(
    'server rejecting the token mid-request signs the controller out',
    () async {
      backend.seedUser('rahim_bd', 'pw-12345678');
      final token = backend.issueToken('rahim_bd');
      storage = InMemoryTokenStorage(token);
      final container = ProviderContainer(
        overrides: [
          tokenStorageProvider.overrideWithValue(storage),
          apiClientProvider.overrideWith((ref) {
            backend.currentToken = () => storage.current;
            backend.onUnauthorized = () =>
                ref.read(authControllerProvider.notifier).sessionExpired();
            return backend;
          }),
        ],
      );
      addTearDown(container.dispose);

      container.read(authControllerProvider); // starts bootstrap
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(container.read(authControllerProvider), isA<Authenticated>());

      backend.revoked.add(token); // e.g. revoked from another device
      await expectLater(
        container.read(authControllerProvider.notifier).updateProfile(bio: 'x'),
        throwsA(isA<UnauthorizedException>()),
      );
      expect(container.read(authControllerProvider), isA<Unauthenticated>());
      expect(storage.current, isNull);
    },
  );
}
