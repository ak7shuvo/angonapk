import 'package:angon/core/errors/app_exception.dart';
import 'package:angon/features/feed/widgets/post_tile.dart';
import 'package:angon/models/explore.dart';
import 'package:angon/services/token_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_backend.dart';
import '../support/harness.dart';

late FakeBackend backend;

void main() {
  setUp(() => backend = FakeBackend());

  test('ExploreData and SearchResults parse the API payloads', () {
    final data = ExploreData.fromJson({
      'categories': [
        {'slug': 'food', 'label': 'Food', 'post_count': 2, 'story_count': 1},
      ],
      'trending_posts': [postJson('p')],
      'featured_stories': [storyJson('s')],
      'popular_places': [placeJson('jaflong', name: 'Jaflong')],
      'creators': [
        {
          'id': '1',
          'username': 'a',
          'display_name': 'A',
          'creator_type': 'guide',
          'avatar_url': null,
          'is_following': false,
          'is_me': false,
        },
      ],
    });
    expect(data.categories.single.label, 'Food');
    expect(data.hasContent, isTrue);
    expect(data.trendingPosts.single.id, 'p');
    expect(
      ExploreData.fromJson({
        'categories': [],
        'trending_posts': [],
        'featured_stories': [],
        'popular_places': [],
        'creators': [],
      }).hasContent,
      isFalse,
    );
    final r = SearchResults.fromJson({
      'query': 'x',
      'users': [],
      'stories': [],
      'posts': [],
      'places': [placeJson('x')],
    });
    expect(r.isEmpty, isFalse);
    expect(const SearchResults().isEmpty, isTrue);
  });

  group('Explore UI', () {
    Future<void> boot(WidgetTester tester, {bool settle = true}) async {
      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      if (!backend.users.containsKey('rahim_bd')) {
        backend.seedUser('rahim_bd', 'pw-12345678');
      }
      final storage = InMemoryTokenStorage(backend.issueToken('rahim_bd'));
      await tester.pumpWidget(buildTestApp(backend, storage));
      await tester.pump();
      Future<void> settleOrPump() async {
        if (settle) {
          await tester.pumpAndSettle();
        } else {
          // A looping "load more" spinner on Home means it never settles.
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
        }
      }

      await settleOrPump();
      await tester.tap(find.text('EXPLORE'));
      await settleOrPump();
    }

    void seedContent() {
      backend.seedUser('nusrat', 'pw-12345678');
      backend.seedUser('rahim_bd', 'pw-12345678');
      backend.places
        ..add(placeJson('jaflong', name: 'Jaflong', nameLocal: 'জাফলং'))
        ..add(
          placeJson('sreemangal', name: 'Sreemangal', district: 'Moulvibazar'),
        );
      backend.feed.add(
        postJson(
          'p1',
          body: 'Early light over the haor.',
          location: 'Tanguar Haor',
          authorId: 'x',
          username: 'nusrat',
          displayName: 'Nusrat',
        ),
      );
      backend.stories.add(
        storyJson('s1', title: 'জাফলংয়ের গল্প', tags: const ['heritage']),
      );
      (backend.users['nusrat']!['profile'] as Map)
        ..['display_name'] = 'Nusrat'
        ..['creator_type'] = 'storyteller'
        ..['is_complete'] = true;
    }

    testWidgets('shows every section with real content', (tester) async {
      seedContent();
      await boot(tester);
      for (final label in [
        'Travel',
        'Culture',
        'Heritage',
        'Nature',
        'Food',
        'Photography',
        'People',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('Trending now'), findsOneWidget);
      expect(find.text('Early light over the haor.'), findsOneWidget);
      expect(find.text('Stories'), findsWidgets);
      expect(find.text('জাফলংয়ের গল্প'), findsOneWidget);
      expect(find.text('Places'), findsOneWidget);
      expect(find.text('Jaflong'), findsOneWidget);
      expect(find.text('Creators'), findsOneWidget);
      expect(find.text('Nusrat'), findsWidgets);
      expect(find.text('Storyteller'), findsOneWidget);
      expect(find.text('Heritage'), findsOneWidget);
    });

    testWidgets('empty database still shows categories and a gentle message', (
      tester,
    ) async {
      await boot(tester);
      expect(find.text('Travel'), findsOneWidget);
      expect(find.text('Nothing to discover yet'), findsOneWidget);
      expect(find.text('Trending now'), findsNothing);
    });

    testWidgets('error then retry', (tester) async {
      seedContent();
      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final storage = InMemoryTokenStorage(backend.issueToken('rahim_bd'));
      await tester.pumpWidget(buildTestApp(backend, storage));
      await tester.pump();
      await tester.pumpAndSettle();
      backend.failWith = const NetworkException();
      await tester.tap(find.text('EXPLORE'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Cannot reach ANGON'), findsOneWidget);
      backend.failWith = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Trending now'), findsOneWidget);
    });

    testWidgets('a category opens its posts and stories', (tester) async {
      seedContent();
      backend.feed.first['tags'] = ['heritage'];
      await boot(tester);
      await tester.tap(find.text('Heritage'));
      await tester.pumpAndSettle();
      expect(find.text('Heritage'), findsWidgets);
      expect(backend.calls.where((c) => c == 'GET /posts'), isNotEmpty);
    });

    testWidgets('tapping a place, story and creator navigates', (tester) async {
      seedContent();
      await boot(tester);
      await tester.tap(find.text('Jaflong'));
      await tester.pumpAndSettle();
      expect(find.text('জাফলং'), findsWidgets);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Storyteller')); // the creator card
      await tester.pumpAndSettle();
      expect(find.text('@nusrat'), findsWidgets);
    });

    testWidgets(
      'search: debounced, sectioned, filtered, with empty and idle states',
      (tester) async {
        seedContent();
        await boot(tester);
        await tester.tap(find.text('Search places, people, stories'));
        await tester.pumpAndSettle();
        expect(find.text('Search ANGON'), findsOneWidget); // idle

        final field = find.byType(TextField);
        await tester.enterText(field, 'ja');
        await tester.pump(const Duration(milliseconds: 100));
        await tester.enterText(field, 'jaflong');
        await tester.pump(const Duration(milliseconds: 100));
        expect(backend.searchCalls, isEmpty); // still typing: nothing sent yet
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        expect(
          backend.searchCalls,
          hasLength(1),
        ); // one request for the final text
        expect(backend.searchCalls.single['q'], 'jaflong');
        expect(find.text('PLACES'), findsOneWidget);
        expect(find.text('Jaflong'), findsOneWidget);
        expect(
          find.text('জাফলংয়ের গল্প'),
          findsOneWidget,
        ); // story content mentions Jaflong

        await tester.tap(find.widgetWithText(ChoiceChip, 'Stories'));
        await tester.pumpAndSettle();
        expect(backend.searchCalls.last['type'], 'stories');
        expect(find.text('PLACES'), findsNothing);

        await tester.enterText(field, 'zzzz');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        expect(find.text('No results for “zzzz”'), findsOneWidget);

        await tester.tap(find.byTooltip('Clear search'));
        await tester.pumpAndSettle();
        expect(find.text('Search ANGON'), findsOneWidget);
      },
    );

    testWidgets('search finds Bengali text and people; errors can be retried', (
      tester,
    ) async {
      seedContent();
      await boot(tester);
      await tester.tap(find.text('Search places, people, stories'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'জাফলং');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('জাফলং'), findsWidgets);
      await tester.enterText(find.byType(TextField), 'nusrat');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('PEOPLE'), findsOneWidget);
      expect(find.text('@nusrat'), findsOneWidget);

      backend.failWith = const ServerException();
      await tester.enterText(find.byType(TextField), 'haor');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('Try again'), findsOneWidget);
      backend.failWith = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Early light over the haor.'), findsOneWidget);
    });

    testWidgets('single-type search loads more pages', (tester) async {
      seedContent();
      for (var i = 0; i < 25; i++) {
        backend.feed.add(
          postJson(
            'bulk$i',
            body: 'haor memory $i',
            authorId: 'x',
            username: 'nusrat',
            displayName: 'Nusrat',
          ),
        );
      }
      await boot(tester, settle: false);
      await tester.tap(find.text('Search places, people, stories'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Posts'));
      await tester.enterText(find.byType(TextField), 'haor');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 100));
      for (var i = 0; i < 8; i++) {
        await tester.drag(find.byType(PostTile).first, const Offset(0, -2500));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
      }
      final offsets = backend.searchCalls.map((c) => c['offset']).toList();
      expect(offsets, containsAll(['0', '20'])); // second page was requested
    });
  });
}
