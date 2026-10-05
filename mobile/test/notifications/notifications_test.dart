import 'package:angon/core/errors/app_exception.dart';
import 'package:angon/features/auth/auth_controller.dart';
import 'package:angon/features/notifications/notification_controllers.dart';
import 'package:angon/features/notifications/notifications_screen.dart';
import 'package:angon/models/notification.dart';
import 'package:angon/services/providers.dart';
import 'package:angon/services/token_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_backend.dart';
import '../support/harness.dart';

late FakeBackend backend;
late InMemoryTokenStorage storage;

Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 30));

/// Waits (briefly) until [done] holds; avoids depending on microtask counts.
Future<void> until(bool Function() done) async {
  for (var i = 0; i < 50 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

ProviderContainer container() {
  backend.seedUser('rahim_bd', 'pw-12345678');
  storage = InMemoryTokenStorage(backend.issueToken('rahim_bd'));
  final c = ProviderContainer(
    overrides: [
      tokenStorageProvider.overrideWithValue(storage),
      apiClientProvider.overrideWith((ref) {
        backend.currentToken = () => storage.current;
        return backend;
      }),
    ],
  );
  addTearDown(c.dispose);
  c.read(authControllerProvider);
  return c;
}

void seed() => backend.notifications.addAll([
  notificationJson('n1', data: {'preview': 'Sunrise at Ratargul'}),
  notificationJson(
    'n2',
    type: 'comment',
    targetType: 'comment',
    targetId: 'c1',
    data: {'post_id': 'p1', 'preview': 'সুন্দর ছবি!'},
  ),
  notificationJson(
    'n3',
    type: 'follow',
    actor: 'tania',
    targetType: 'user',
    targetId: 'u1',
    data: {'username': 'tania'},
    isRead: true,
  ),
]);

void main() {
  setUp(() => backend = FakeBackend());

  group('model', () {
    test('known types get tailored text; unknown types fall back to data', () {
      final like = AppNotification.fromJson(
        notificationJson('a', targetType: 'story'),
      );
      expect(like.action, 'liked your story');
      final unknown = AppNotification.fromJson(
        notificationJson(
          'b',
          type: 'booking',
          actor: null,
          data: {'title': 'Trip confirmed', 'body': 'See you'},
        ),
      );
      expect(unknown.action, 'Trip confirmed');
      expect(unknown.detail, 'See you');
      expect(unknown.actor, isNull);
    });

    test('notificationRoute maps types to screens', () {
      String? route(Map<String, dynamic> j) =>
          notificationRoute(AppNotification.fromJson(j));
      expect(route(notificationJson('a')), '/posts/p1');
      expect(
        route(
          notificationJson(
            'a',
            targetType: 'story',
            targetId: 's1',
            data: {'story_slug': 'jaflong'},
          ),
        ),
        '/story/jaflong',
      );
      expect(
        route(notificationJson('a', type: 'comment', data: {'post_id': 'p9'})),
        '/posts/p9',
      );
      expect(
        route(
          notificationJson('a', type: 'follow', data: {'username': 'tania'}),
        ),
        '/u/tania',
      );
      expect(
        route(notificationJson('a', type: 'booking', actor: null)),
        isNull,
      );
    });
  });

  group('controllers', () {
    test(
      'badge counts unread; mark read decrements; read-all clears',
      () async {
        seed();
        final c = container();
        c.listen(unreadCountProvider, (_, _) {});
        c.listen(notificationsProvider, (_, _) {});
        await until(() => c.read(unreadCountProvider) == 2);
        expect(c.read(unreadCountProvider), 2);
        expect(c.read(notificationsProvider).items, hasLength(3));

        final first = c.read(notificationsProvider).items.first;
        await c.read(notificationsProvider.notifier).markRead(first);
        await pump();
        expect(c.read(notificationsProvider).items.first.isRead, isTrue);
        expect(c.read(unreadCountProvider), 1);

        await c.read(notificationsProvider.notifier).markAllRead();
        expect(c.read(unreadCountProvider), 0);
        expect(
          c.read(notificationsProvider).items.every((n) => n.isRead),
          isTrue,
        );
        expect(
          backend.notifications.every((n) => n['is_read'] == true),
          isTrue,
        );
      },
    );

    test('a failed mark-read reverts the optimistic flag', () async {
      seed();
      final c = container();
      c.listen(notificationsProvider, (_, _) {});
      await pump();
      final first = c.read(notificationsProvider).items.first;
      backend.failWith = const NetworkException();
      await c.read(notificationsProvider.notifier).markRead(first);
      expect(c.read(notificationsProvider).items.first.isRead, isFalse);
    });

    test('signed-out badge stays at zero', () async {
      final c = ProviderContainer(
        overrides: [
          tokenStorageProvider.overrideWithValue(InMemoryTokenStorage(null)),
          apiClientProvider.overrideWithValue(backend),
        ],
      );
      addTearDown(c.dispose);
      c.listen(unreadCountProvider, (_, _) {});
      await pump();
      expect(c.read(unreadCountProvider), 0);
      expect(backend.calls.where((x) => x.contains('/notifications')), isEmpty);
    });
  });

  group('screen', () {
    Future<void> boot(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      backend.seedUser('rahim_bd', 'pw-12345678');
      storage = InMemoryTokenStorage(backend.issueToken('rahim_bd'));
      await tester.pumpWidget(buildTestApp(backend, storage));
      await tester.pump();
      await tester.pumpAndSettle();
    }

    testWidgets('bell shows the unread count and opens the inbox', (
      tester,
    ) async {
      seed();
      await boot(tester);
      expect(find.text('2'), findsOneWidget); // badge
      await tester.tap(find.byIcon(Icons.notifications_none));
      await tester.pumpAndSettle();
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.textContaining('liked your post'), findsOneWidget);
      expect(find.text('Sunrise at Ratargul'), findsOneWidget);
      expect(find.text('সুন্দর ছবি!'), findsOneWidget);
      expect(find.textContaining('started following you'), findsOneWidget);
      expect(find.text('Mark all read'), findsOneWidget);
    });

    testWidgets('mark all read clears the badge and the button', (
      tester,
    ) async {
      seed();
      await boot(tester);
      await tester.tap(find.byIcon(Icons.notifications_none));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark all read'));
      await tester.pumpAndSettle();
      expect(find.text('Mark all read'), findsNothing);
      expect(backend.notifications.every((n) => n['is_read'] == true), isTrue);
    });

    testWidgets('empty inbox explains itself', (tester) async {
      await boot(tester);
      await tester.tap(find.byIcon(Icons.notifications_none));
      await tester.pumpAndSettle();
      expect(find.text('Nothing here yet'), findsOneWidget);
      expect(find.text('Mark all read'), findsNothing);
    });

    testWidgets(
      'tapping a follow notification opens that profile and marks it read',
      (tester) async {
        backend.users['tania'] = {};
        seed();
        backend.notifications[0]['is_read'] = true;
        backend.notifications[1]['is_read'] = true;
        backend.notifications[2]['is_read'] = false;
        await boot(tester);
        await tester.tap(find.byIcon(Icons.notifications_none));
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('started following you'));
        await tester.pumpAndSettle();
        expect(backend.notifications[2]['is_read'], isTrue);
        expect(backend.calls, contains('POST /notifications/n3/read'));
      },
    );
  });
}
