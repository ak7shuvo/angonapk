// Real client ↔ real API: in-app notifications.
//   flutter test test/e2e --dart-define=E2E_API_BASE_URL=http://127.0.0.1:8000
import 'package:angon/config/app_config.dart';
import 'package:angon/core/errors/app_exception.dart';
import 'package:angon/features/auth/auth_controller.dart';
import 'package:angon/features/notifications/notification_controllers.dart';
import 'package:angon/features/social/engagement_controller.dart';
import 'package:angon/features/social/follow_controller.dart';
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

  test('like, comment and follow notify the author', () async {
    final stamp = DateTime.now().microsecondsSinceEpoch.toString();
    final author = await _signedIn('na_$stamp'.substring(0, 18));
    final fan = await _signedIn('nb_$stamp'.substring(0, 18));
    final fanName = fan.read(authControllerProvider) is Authenticated
        ? (fan.read(authControllerProvider) as Authenticated).user.username
        : '';

    final post = await author
        .read(postRepositoryProvider)
        .createPost(body: 'notify me', tags: ['culture']);
    final repo = author.read(notificationRepositoryProvider);
    expect(await repo.unreadCount(), 0);

    await fan.read(engagementProvider.notifier).toggleLike(post);
    await fan.read(postRepositoryProvider).addComment(post.id, 'Lovely!');
    await fan
        .read(followProvider.notifier)
        .toggle(
          (author.read(authControllerProvider) as Authenticated).user.username,
          currentlyFollowing: false,
        );
    expect(await repo.unreadCount(), 3);

    // Own actions never notify yourself.
    await author.read(engagementProvider.notifier).toggleLike(post);
    expect(await repo.unreadCount(), 3);

    final page = await repo.list();
    expect(page.items.map((n) => n.type), ['follow', 'comment', 'like']);
    expect(page.items.first.actor!.username, fanName);
    expect(page.items[1].data['post_id'], post.id);
    expect(page.items[1].preview, 'Lovely!');

    // Controller + badge against the real server.
    author.listen(unreadCountProvider, (_, _) {});
    author.listen(notificationsProvider, (_, _) {});
    for (var i = 0; i < 100 && author.read(unreadCountProvider) != 3; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    expect(author.read(unreadCountProvider), 3);
    await author
        .read(notificationsProvider.notifier)
        .markRead(page.items.first);
    expect(await repo.unreadCount(), 2);
    await author.read(notificationsProvider.notifier).markAllRead();
    expect(await repo.unreadCount(), 0);

    // Strangers cannot read someone else's notification.
    await expectLater(
      fan.read(notificationRepositoryProvider).markRead(page.items.first.id),
      throwsA(isA<AppException>()),
    );
  }, skip: skip);
}
