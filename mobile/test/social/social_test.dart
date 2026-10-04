import 'package:angon/core/errors/app_exception.dart';
import 'package:angon/features/auth/auth_controller.dart';
import 'package:angon/features/social/comments_controller.dart';
import 'package:angon/features/social/engagement_controller.dart';
import 'package:angon/features/social/follow_controller.dart';
import 'package:angon/models/post.dart';
import 'package:angon/models/social.dart';
import 'package:angon/routing/app_router.dart';
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

Post post0([String id = 'p1']) => Post.fromJson(postJson(id, body: 'hello'));

void main() {
  setUp(() => backend = FakeBackend());

  group('models', () {
    test('Post parses engagement fields; Engagement.of mirrors them', () {
      final p = Post.fromJson({
        ...postJson('p'),
        'like_count': 3,
        'comment_count': 2,
        'liked_by_me': true,
        'saved_by_me': true,
        'following_author': true,
      });
      final e = Engagement.of(p);
      expect(
        (e.likeCount, e.commentCount, e.liked, e.saved),
        (3, 2, true, true),
      );
      expect(p.followingAuthor, isTrue);
    });

    test('Comment and UserPage parse', () {
      final page = CommentPage.fromJson({
        'items': [
          {
            'id': 'c',
            'post_id': 'p',
            'body': 'সুন্দর',
            'author': {'id': 'u', 'username': 'a', 'display_name': null},
            'created_at': '2026-01-01T00:00:00+00:00',
            'is_mine': true,
          },
        ],
        'next_cursor': 'n',
      });
      expect(page.items.single.body, 'সুন্দর');
      expect(page.items.single.isMine, isTrue);
      expect(page.nextCursor, 'n');
      final users = UserPage.fromJson({
        'items': [
          {
            'id': '1',
            'username': 'bob',
            'display_name': 'Bob',
            'creator_type': 'guide',
            'is_following': true,
            'is_me': false,
          },
        ],
        'next_cursor': null,
      });
      expect(users.items.single.isFollowing, isTrue);
      expect(users.items.single.name, 'Bob');
    });
  });

  group('EngagementController', () {
    setUp(() {
      backend.feed.add(
        postJson('p1', body: 'hello', authorId: 'x', username: 'other'),
      );
    });

    test('like is optimistic, then takes the server count', () async {
      final c = container();
      await pump();
      // Someone else already liked it.
      backend.likes['p1'] = {'someone'};
      final notifier = c.read(engagementProvider.notifier);
      final future = notifier.toggleLike(post0());
      // Optimistic state is visible before the server answers.
      expect(c.read(engagementProvider)['p1']!.liked, isTrue);
      expect(c.read(engagementProvider)['p1']!.likeCount, 1);
      await future;
      expect(c.read(engagementProvider)['p1']!.likeCount, 2); // server truth
      expect(backend.likes['p1'], contains('rahim_bd'));

      await notifier.toggleLike(post0()); // unlike
      expect(c.read(engagementProvider)['p1']!.liked, isFalse);
      expect(c.read(engagementProvider)['p1']!.likeCount, 1);
    });

    test('failed like rolls back and rethrows', () async {
      final c = container();
      await pump();
      backend.failWith = const NetworkException();
      final notifier = c.read(engagementProvider.notifier);
      await expectLater(
        notifier.toggleLike(post0()),
        throwsA(isA<NetworkException>()),
      );
      final e = c.read(engagementProvider)['p1']!;
      expect((e.liked, e.likeCount), (false, 0));
    });

    test('taps while a request is in flight are ignored', () async {
      final c = container();
      await pump();
      final notifier = c.read(engagementProvider.notifier);
      final first = notifier.toggleLike(post0());
      await notifier.toggleLike(post0()); // ignored
      await first;
      expect(
        backend.calls.where((x) => x == 'PUT /posts/p1/like'),
        hasLength(1),
      );
      expect(backend.calls.where((x) => x == 'DELETE /posts/p1/like'), isEmpty);
    });

    test(
      'save toggles with rollback; ingest lets fresh server data win',
      () async {
        final c = container();
        await pump();
        final notifier = c.read(engagementProvider.notifier);
        await notifier.toggleSave(post0());
        expect(c.read(engagementProvider)['p1']!.saved, isTrue);
        expect(backend.saves['p1'], ['rahim_bd']);

        backend.failWith = const ServerException();
        await expectLater(
          notifier.toggleSave(post0()),
          throwsA(isA<ServerException>()),
        );
        expect(
          c.read(engagementProvider)['p1']!.saved,
          isTrue,
        ); // rolled back to saved
        backend.failWith = null;

        notifier.ingest([post0()]);
        expect(c.read(engagementProvider), isEmpty); // overlay dropped
      },
    );
  });

  group('FollowController', () {
    setUp(() => backend.seedUser('bob', 'pw-12345678'));

    test('optimistic follow then server count; rollback on failure', () async {
      final c = container();
      await pump();
      final notifier = c.read(followProvider.notifier);
      final future = notifier.toggle(
        'bob',
        currentlyFollowing: false,
        followersCount: 4,
      );
      expect(c.read(followProvider)['bob']!.following, isTrue);
      expect(c.read(followProvider)['bob']!.followersCount, 5);
      await future;
      expect(c.read(followProvider)['bob']!.followersCount, 1); // server truth
      expect(backend.follows['rahim_bd'], {'bob'});

      backend.failWith = const NetworkException();
      await expectLater(
        notifier.toggle('bob', currentlyFollowing: true),
        throwsA(isA<NetworkException>()),
      );
      expect(c.read(followProvider)['bob']!.following, isTrue); // restored
    });
  });

  group('CommentsController', () {
    test(
      'adds, lists, deletes and keeps the post comment count in sync',
      () async {
        backend.feed.add(
          postJson('p1', body: 'hello', authorId: 'x', username: 'other'),
        );
        final c = container();
        await pump();
        final post = post0();
        c.listen(commentsControllerProvider(post), (_, _) {});
        await pump();
        expect(c.read(commentsControllerProvider(post)).items, isEmpty);

        await c
            .read(commentsControllerProvider(post).notifier)
            .add('সুন্দর ছবি');
        var state = c.read(commentsControllerProvider(post));
        expect(state.items.single.body, 'সুন্দর ছবি');
        expect(c.read(engagementProvider)['p1']!.commentCount, 1);

        await c
            .read(commentsControllerProvider(post).notifier)
            .delete(state.items.single);
        state = c.read(commentsControllerProvider(post));
        expect(state.items, isEmpty);
        expect(c.read(engagementProvider)['p1']!.commentCount, 0);
      },
    );

    test('a failed comment throws and leaves the list untouched', () async {
      backend.feed.add(
        postJson('p1', body: 'hello', authorId: 'x', username: 'other'),
      );
      final c = container();
      await pump();
      final post = post0();
      c.listen(commentsControllerProvider(post), (_, _) {});
      await pump();
      backend.failWith = const ServerException();
      await expectLater(
        c.read(commentsControllerProvider(post).notifier).add('x'),
        throwsA(isA<ServerException>()),
      );
      expect(c.read(commentsControllerProvider(post)).items, isEmpty);
      expect(c.read(commentsControllerProvider(post)).sending, isFalse);
    });
  });

  group('UI', () {
    Future<void> boot(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      if (!backend.users.containsKey('rahim_bd')) {
        backend.seedUser('rahim_bd', 'pw-12345678');
      }
      storage = InMemoryTokenStorage(backend.issueToken('rahim_bd'));
      await tester.pumpWidget(buildTestApp(backend, storage));
      await tester.pump();
      await tester.pumpAndSettle();
    }

    void otherPost() => backend.feed.add(
      postJson(
        'p1',
        body: 'Early light over the haor.',
        authorId: 'x',
        username: 'other',
        displayName: 'Other',
      ),
    );

    testWidgets(
      'like: heart fills and the count appears; a failure reverts it',
      (tester) async {
        otherPost();
        await boot(tester);
        expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
        await tester.tap(find.byIcon(Icons.favorite_border_rounded));
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
        expect(find.text('1'), findsOneWidget);
        expect(backend.likes['p1'], {'rahim_bd'});

        backend.failWith = const NetworkException();
        await tester.tap(find.byIcon(Icons.favorite_rounded));
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.favorite_rounded), findsOneWidget); // reverted
        expect(
          find.textContaining('Could not update your like'),
          findsNothing,
        ); // typed message wins
        expect(find.textContaining('Cannot reach ANGON'), findsOneWidget);
      },
    );

    testWidgets('save toggles the bookmark', (tester) async {
      otherPost();
      await boot(tester);
      await tester.tap(find.byIcon(Icons.bookmark_border_rounded));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.bookmark_rounded), findsOneWidget);
      expect(backend.saves['p1'], ['rahim_bd']);
      await tester.tap(find.byIcon(Icons.bookmark_rounded));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.bookmark_border_rounded), findsOneWidget);
      expect(backend.saves['p1'], isEmpty);
    });

    testWidgets(
      'follow button appears on others\' posts only, then goes away',
      (tester) async {
        backend.seedUser('rahim_bd', 'pw-12345678');
        backend.seedUser('other', 'pw-12345678');
        final me = backend.users['rahim_bd']!['id'] as String;
        backend.feed
          ..add(
            postJson(
              'mine',
              body: 'my post',
              authorId: me,
              username: 'rahim_bd',
            ),
          )
          ..add(
            postJson(
              'p1',
              body: 'their post',
              authorId: 'x',
              username: 'other',
              displayName: 'Other',
            ),
          );
        await boot(tester);
        expect(find.widgetWithText(FilledButton, 'Follow'), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, 'Follow'));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(FilledButton, 'Follow'), findsNothing);
        expect(backend.follows['rahim_bd'], {'other'});
      },
    );

    testWidgets(
      'Following tab lists only followed authors; empty state otherwise',
      (tester) async {
        backend.seedUser('rahim_bd', 'pw-12345678');
        backend.seedUser('other', 'pw-12345678');
        backend.feed
          ..add(
            postJson(
              'a',
              body: 'from other',
              authorId: 'x',
              username: 'other',
              displayName: 'Other',
            ),
          )
          ..add(
            postJson(
              'b',
              body: 'from stranger',
              authorId: 'y',
              username: 'stranger',
              displayName: 'Stranger',
            ),
          );
        await boot(tester);
        await tester.tap(find.text('Following'));
        await tester.pumpAndSettle();
        expect(find.text('Follow storytellers'), findsOneWidget);

        backend.follows['rahim_bd'] = {'other'};
        await tester.tap(find.text('Discover').first); // tab in the app bar
        await tester.pumpAndSettle();
        await tester.tap(find.text('Following'));
        await tester.pumpAndSettle();
        // (Following feed was already loaded empty; pull to refresh.)
        await tester.drag(find.byType(CustomScrollView), const Offset(0, 1500));
        await tester.pumpAndSettle();
        expect(find.text('from other'), findsOneWidget);
        expect(find.text('from stranger'), findsNothing);
      },
    );

    testWidgets('comments: open from the card, add, see count, delete own', (
      tester,
    ) async {
      otherPost();
      backend.seedUser('other', 'pw-12345678');
      backend.comments['p1'] = [
        {
          'id': 'theirs',
          'post_id': 'p1',
          'body': 'Lovely light',
          'author': {'id': 'x', 'username': 'other', 'display_name': 'Other'},
          'created_at': '2026-01-01T00:00:00+00:00',
        },
      ];
      await boot(tester);
      await tester.tap(find.byIcon(Icons.chat_bubble_outline_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Lovely light'), findsOneWidget);
      expect(find.byTooltip('Delete comment'), findsNothing); // not mine

      await tester.enterText(find.byType(TextField), 'সুন্দর!');
      await tester.tap(find.byTooltip('Send comment'));
      await tester.pumpAndSettle();
      expect(find.text('সুন্দর!'), findsOneWidget);
      expect(find.byTooltip('Delete comment'), findsOneWidget); // only mine
      expect(find.text('2'), findsOneWidget); // comment count on the card

      await tester.tap(find.byTooltip('Delete comment'));
      await tester.pumpAndSettle();
      expect(find.text('সুন্দর!'), findsNothing);
      expect(find.text('Lovely light'), findsOneWidget);
    });

    testWidgets('a rejected comment keeps the typed text', (tester) async {
      otherPost();
      await boot(tester);
      await tester.tap(find.byIcon(Icons.chat_bubble_outline_rounded));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'keep this');
      backend.failWith = const ServerException();
      await tester.tap(find.byTooltip('Send comment'));
      await tester.pumpAndSettle();
      expect(find.text('keep this'), findsOneWidget);
      expect(find.textContaining('went wrong'), findsOneWidget);
    });

    testWidgets('followers screen lists people with working follow buttons', (
      tester,
    ) async {
      backend.seedUser('rahim_bd', 'pw-12345678');
      backend.seedUser('bob', 'pw-12345678');
      backend.seedUser('carol', 'pw-12345678');
      backend.follows['bob'] = {'carol'};
      await boot(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(Scaffold).first),
      );
      container.read(routerProvider).push('/u/carol/followers');
      await tester.pumpAndSettle();
      expect(find.text('Followers'), findsOneWidget);
      expect(find.text('@bob'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Follow'));
      await tester.pumpAndSettle();
      expect(backend.follows['rahim_bd'], {'bob'});
      expect(find.widgetWithText(OutlinedButton, 'Following'), findsOneWidget);
    });

    testWidgets('followers screen empty state', (tester) async {
      backend.seedUser('rahim_bd', 'pw-12345678');
      backend.seedUser('carol', 'pw-12345678');
      await boot(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(Scaffold).first),
      );
      container.read(routerProvider).push('/u/carol/following');
      await tester.pumpAndSettle();
      expect(find.text('Not following anyone yet'), findsOneWidget);
    });
  });
}
