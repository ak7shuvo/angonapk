import 'package:angon/core/errors/app_exception.dart';
import 'package:angon/features/auth/auth_controller.dart';
import 'package:angon/features/feed/feed_controller.dart';
import 'package:angon/features/feed/widgets/post_card.dart';
import 'package:angon/models/post.dart';
import 'package:angon/services/providers.dart';
import 'package:angon/services/token_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_backend.dart';
import '../support/harness.dart';

late FakeBackend backend;
late InMemoryTokenStorage storage;

void seedFeed(int n) {
  for (var i = 0; i < n; i++) {
    backend.feed.add(
      postJson('p$i', body: 'Post number $i', location: 'Sylhet'),
    );
  }
}

/// Signed-in app whose Home is the real feed screen (tall surface for list building).
Future<void> bootHome(WidgetTester tester, {bool settle = true}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  if (!backend.users.containsKey('rahim_bd')) {
    backend.seedUser('rahim_bd', 'pw-12345678');
  }
  storage = InMemoryTokenStorage(backend.issueToken('rahim_bd'));
  await tester.pumpWidget(buildTestApp(backend, storage));
  await tester.pump();
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    // A looping footer spinner means we can never "settle"; advance manually.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
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
  return c;
}

Future<void> pumpEvents() =>
    Future<void>.delayed(const Duration(milliseconds: 30));

void main() {
  setUp(() {
    backend = FakeBackend();
  });

  group('FeedController', () {
    test('loads first page then paginates until the end', () async {
      seedFeed(45);
      final c = container();
      c.read(authControllerProvider);
      await pumpEvents();
      c.listen(feedControllerProvider, (_, _) {});
      await pumpEvents();

      var s = c.read(feedControllerProvider);
      expect(s.status, FeedStatus.ready);
      expect(s.posts, hasLength(20));
      expect(s.hasMore, isTrue);

      await c.read(feedControllerProvider.notifier).loadMore();
      await c.read(feedControllerProvider.notifier).loadMore();
      s = c.read(feedControllerProvider);
      expect(s.posts, hasLength(45));
      expect(s.hasMore, isFalse);
      expect({for (final p in s.posts) p.id}, hasLength(45)); // no duplicates

      // No more pages: further calls are no-ops.
      final callsBefore = backend.calls.length;
      await c.read(feedControllerProvider.notifier).loadMore();
      expect(backend.calls.length, callsBefore);
    });

    test('initial failure → error state → retry succeeds', () async {
      seedFeed(2);
      final c = container();
      c.read(authControllerProvider);
      await pumpEvents();
      backend.failWith = const NetworkException();
      c.listen(feedControllerProvider, (_, _) {});
      await pumpEvents();
      var s = c.read(feedControllerProvider);
      expect(s.status, FeedStatus.error);
      expect(s.error, isA<NetworkException>());

      backend.failWith = null;
      await c.read(feedControllerProvider.notifier).retry();
      s = c.read(feedControllerProvider);
      expect(s.status, FeedStatus.ready);
      expect(s.posts, hasLength(2));
    });

    test('failed pagination keeps posts and can be retried', () async {
      seedFeed(30);
      final c = container();
      c.read(authControllerProvider);
      await pumpEvents();
      c.listen(feedControllerProvider, (_, _) {});
      await pumpEvents();

      backend.failWith = const ServerException();
      await c.read(feedControllerProvider.notifier).loadMore();
      var s = c.read(feedControllerProvider);
      expect(s.posts, hasLength(20));
      expect(s.loadMoreError, isA<ServerException>());
      expect(s.loadingMore, isFalse);

      backend.failWith = null;
      await c.read(feedControllerProvider.notifier).loadMore();
      s = c.read(feedControllerProvider);
      expect(s.posts, hasLength(30));
      expect(s.loadMoreError, isNull);
    });

    test(
      'refresh replaces the list; a failed refresh keeps old posts',
      () async {
        seedFeed(3);
        final c = container();
        c.read(authControllerProvider);
        await pumpEvents();
        c.listen(feedControllerProvider, (_, _) {});
        await pumpEvents();

        backend.feed.insert(0, postJson('fresh', body: 'new one'));
        await c.read(feedControllerProvider.notifier).refresh();
        expect(c.read(feedControllerProvider).posts.first.id, 'fresh');

        backend.failWith = const NetworkException();
        await c.read(feedControllerProvider.notifier).refresh();
        final s = c.read(feedControllerProvider);
        expect(s.posts, hasLength(4)); // not wiped
        expect(s.status, FeedStatus.ready);
        expect(s.refreshError, isA<NetworkException>());
      },
    );
  });

  group('Home feed UI', () {
    testWidgets('shows loading, then posts from the backend', (tester) async {
      seedFeed(3);
      await bootHome(tester);
      expect(find.text('Post number 0'), findsOneWidget);
      expect(find.text('Post number 2'), findsOneWidget);
      expect(find.text('HOME'), findsOneWidget);
      expect(find.byTooltip('Your profile'), findsOneWidget);
      expect(find.text("You're all caught up"), findsOneWidget);
    });

    testWidgets('shows a loading indicator while the first page is in flight', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      backend.seedUser('rahim_bd', 'pw-12345678');
      storage = InMemoryTokenStorage(backend.issueToken('rahim_bd'));
      await tester.pumpWidget(buildTestApp(backend, storage));
      // Auth restore + feed request are still pending on the first frames.
      await tester.pump();
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      await tester.pumpAndSettle();
    });

    testWidgets('empty feed shows the empty state with a call to action', (
      tester,
    ) async {
      await bootHome(tester);
      expect(find.text('Nothing here yet'), findsOneWidget);
      await tester.tap(find.text('Share a discovery'));
      await tester.pumpAndSettle();
      expect(
        find.text('What are you discovering?'),
        findsOneWidget,
      ); // Create tab
    });

    testWidgets('error state offers retry that recovers', (tester) async {
      seedFeed(2);
      backend.failWith = null;
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      backend.seedUser('rahim_bd', 'pw-12345678');
      storage = InMemoryTokenStorage(backend.issueToken('rahim_bd'));
      await tester.pumpWidget(buildTestApp(backend, storage));
      await tester.pump(); // auth bootstrap starts
      await tester.pumpAndSettle();
      // Break the network only for the feed: simulate by failing then reloading.
      backend.failWith = const NetworkException();
      final element = tester.element(find.byType(Scaffold).first);
      ProviderScope.containerOf(element).invalidate(feedControllerProvider);
      await tester.pumpAndSettle();

      expect(find.textContaining('Cannot reach ANGON'), findsOneWidget);
      backend.failWith = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Post number 0'), findsOneWidget);
    });

    testWidgets('pull-to-refresh fetches new posts', (tester) async {
      seedFeed(2);
      await bootHome(tester);
      backend.feed.insert(0, postJson('fresh', body: 'Fresh from the server'));
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 1500));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(
        backend.calls.where((c) => c == 'GET /posts').length,
        2,
        reason: 'refresh not triggered',
      );
      expect(find.text('Fresh from the server'), findsOneWidget);
    });

    testWidgets('infinite scroll loads the next page', (tester) async {
      seedFeed(30);
      await bootHome(tester, settle: false);
      final callsAfterFirst = backend.calls
          .where((c) => c == 'GET /posts')
          .length;
      expect(callsAfterFirst, 1);
      for (var i = 0; i < 6; i++) {
        await tester.drag(
          find.byType(CustomScrollView),
          const Offset(0, -3000),
        );
        await tester.pumpAndSettle();
      }
      expect(backend.calls.where((c) => c == 'GET /posts').length, 2);
      expect(find.text('Post number 29'), findsOneWidget);
      expect(find.text("You're all caught up"), findsOneWidget);
    });

    testWidgets('renders Bengali and English content side by side', (
      tester,
    ) async {
      backend.feed
        ..add(
          postJson(
            'bn',
            body: 'আজ জাফলংয়ে পাহাড়ের নিচে স্বচ্ছ জল।',
            location: 'জাফলং, সিলেট',
            displayName: 'নুসরাত',
            username: 'seed_nusrat',
          ),
        )
        ..add(
          postJson(
            'en',
            body: 'Early light over the haor.',
            location: 'Tanguar Haor',
          ),
        );
      await bootHome(tester);
      expect(find.text('আজ জাফলংয়ে পাহাড়ের নিচে স্বচ্ছ জল।'), findsOneWidget);
      expect(find.text('জাফলং, সিলেট'), findsOneWidget);
      expect(find.text('নুসরাত'), findsOneWidget);
      expect(find.text('Early light over the haor.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('header avatar navigates to the profile tab', (tester) async {
      seedFeed(1);
      await bootHome(tester);
      await tester.tap(find.byTooltip('Your profile'));
      await tester.pumpAndSettle();
      expect(find.text('@rahim_bd'), findsWidgets);
      expect(find.text('Edit profile'), findsWidgets);
    });

    testWidgets(
      'tapping an author opens their profile; your own opens the Profile tab',
      (tester) async {
        final me =
            (backend..seedUser('rahim_bd', 'pw-12345678')).users['rahim_bd']!;
        backend.feed
          ..add(
            postJson(
              'mine',
              body: 'my post',
              authorId: me['id'] as String,
              username: 'rahim_bd',
              displayName: 'Rahim',
            ),
          )
          ..add(
            postJson(
              'theirs',
              body: 'their post',
              authorId: 'other',
              username: 'someone',
              displayName: 'Someone',
            ),
          );
        backend.seedUser('someone', 'pw-12345678');
        await bootHome(tester);
        await tester.tap(find.text('Someone'));
        await tester.pumpAndSettle();
        expect(find.text('@someone'), findsWidgets); // their profile, pushed
        expect(find.widgetWithText(FilledButton, 'Follow'), findsWidgets);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Rahim').first);
        await tester.pumpAndSettle();
        expect(find.text('Edit profile'), findsWidgets); // my own profile tab
      },
    );

    testWidgets(
      'share is an honest placeholder: says coming soon, sends nothing',
      (tester) async {
        seedFeed(1);
        await bootHome(tester);
        final callsBefore = backend.calls.length;
        await tester.tap(find.byIcon(Icons.ios_share_rounded));
        await tester.pump();
        expect(find.text('Share is coming soon.'), findsOneWidget);
        expect(backend.calls.length, callsBefore);
      },
    );
  });

  group('PostCard', () {
    Widget host(Post post) => ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PostCard(post: post, now: DateTime.utc(2026, 1, 1, 3)),
          ),
        ),
      ),
    );

    testWidgets('renders author, handle, time, location and text', (
      tester,
    ) async {
      final post = Post.fromJson(
        postJson('p', body: 'Hello', location: 'Sylhet', displayName: 'Rahim'),
      );
      await tester.pumpWidget(host(post));
      expect(find.text('Rahim'), findsOneWidget);
      expect(find.text('@seed_rahim · 3h'), findsOneWidget);
      expect(find.text('Sylhet'), findsOneWidget);
      expect(find.text('Hello'), findsOneWidget);
      expect(
        find.byIcon(Icons.ios_share_rounded),
        findsOneWidget,
      ); // share placeholder
    });

    testWidgets('long text collapses and expands', (tester) async {
      final long = 'শব্দ ' * 120;
      await tester.pumpWidget(host(Post.fromJson(postJson('p', body: long))));
      expect(find.text('Read more'), findsOneWidget);
      await tester.tap(find.text('Read more'));
      await tester.pump();
      expect(find.text('Show less'), findsOneWidget);
    });

    testWidgets(
      'multi-image posts show a counter; failed images degrade gracefully',
      (tester) async {
        final media = [
          for (var i = 0; i < 3; i++)
            {
              'id': 'm$i',
              'type': 'image',
              'url': 'http://127.0.0.1:1/x$i.png',
              'width': 1200,
              'height': 900,
              'alt_text': null,
            },
        ];
        await tester.pumpWidget(
          host(Post.fromJson(postJson('p', media: media))),
        );
        expect(find.text('1/3'), findsOneWidget);
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );
  });
}
