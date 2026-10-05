import 'package:angon/models/place.dart';
import 'package:angon/models/post.dart';
import 'package:angon/models/story.dart';
import 'package:angon/services/token_storage.dart';
import 'package:angon/routing/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_backend.dart';
import '../support/fake_picker.dart';
import '../support/harness.dart';

late FakeBackend backend;

void main() {
  setUp(() => backend = FakeBackend());

  group('place models', () {
    test('summary parses coordinates, counts and the location line', () {
      final p = PlaceSummary.fromJson(
        placeJson(
          'jaflong',
          name: 'Jaflong',
          nameLocal: 'জাফলং',
          lat: 25.165,
          lng: 92.017,
          postCount: 3,
          storyCount: 1,
        ),
      );
      expect(p.nameLocal, 'জাফলং');
      expect((p.latitude, p.longitude), (25.165, 92.017));
      expect((p.postCount, p.storyCount), (3, 1));
      expect(p.locationLine, 'Sylhet'); // district == division collapses
      expect(
        PlaceSummary.fromJson(
          placeJson('x', district: 'Bandarban', division: 'Chattogram'),
        ).locationLine,
        'Bandarban, Chattogram',
      );
    });

    test('detail adds upazila, description and the seed flag', () {
      final d = PlaceDetail.fromJson(
        placeJson(
          'jaflong',
          name: 'Jaflong',
          upazila: 'Gowainghat',
          district: 'Sylhet',
          division: 'Sylhet',
        ),
      );
      expect(d.locationLine, 'Gowainghat, Sylhet');
      expect(d.isSeed, isTrue);
      expect(
        PlaceDetail.fromJson(placeJson('y', metadata: const {})).isSeed,
        isFalse,
      );
    });

    test('posts and stories carry an optional place', () {
      final place = placeBrief(placeJson('jaflong', name: 'Jaflong'));
      expect(Post.fromJson(postJson('p', place: place)).place!.slug, 'jaflong');
      expect(Post.fromJson(postJson('p')).place, isNull);
      expect(
        Story.fromJson(storyJson('s', place: place)).place!.name,
        'Jaflong',
      );
    });
  });

  group('places UI', () {
    late FakeImagePicker picker;

    Future<void> boot(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      picker = FakeImagePicker();
      if (!backend.users.containsKey('rahim_bd')) {
        backend.seedUser('rahim_bd', 'pw-12345678');
      }
      final storage = InMemoryTokenStorage(backend.issueToken('rahim_bd'));
      await tester.pumpWidget(buildTestApp(backend, storage, picker: picker));
      await tester.pump();
      await tester.pumpAndSettle();
    }

    void seedPlaces() {
      backend.places
        ..add(
          placeJson(
            'jaflong',
            name: 'Jaflong',
            nameLocal: 'জাফলং',
            upazila: 'Gowainghat',
            postCount: 1,
          ),
        )
        ..add(
          placeJson('sreemangal', name: 'Sreemangal', district: 'Moulvibazar'),
        )
        ..add(
          placeJson(
            'coxs-bazar',
            name: "Cox's Bazar",
            division: 'Chattogram',
            district: "Cox's Bazar",
          ),
        );
    }

    testWidgets(
      'composer: tag a place via debounced search, then share with it',
      (tester) async {
        seedPlaces();
        await boot(tester);
        await tester.tap(find.text('CREATE'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextField).first,
          'Stones everywhere',
        );
        await tester.tap(find.text('Tag a place'));
        await tester.pumpAndSettle();
        expect(find.text('Jaflong'), findsWidgets);
        expect(find.text('Sreemangal'), findsOneWidget);

        await tester.enterText(
          find.widgetWithText(TextField, 'Search places, e.g. Jaflong, Sylhet'),
          'জাফ',
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          find.text('Sreemangal'),
          findsOneWidget,
        ); // debounce: nothing fired yet
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        expect(find.text('Sreemangal'), findsNothing);
        expect(find.text('Jaflong'), findsWidgets);

        await tester.tap(find.text('Jaflong').last);
        await tester.pumpAndSettle();
        expect(find.byTooltip('Remove place'), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, 'Share'));
        await tester.pumpAndSettle();
        expect(backend.created.single['place_id'], 'place-jaflong');
        // The new post shows the place; tapping it opens the place page.
        expect(find.text('Jaflong'), findsWidgets);
      },
    );

    testWidgets('place picker shows an empty state for unknown names', (
      tester,
    ) async {
      seedPlaces();
      await boot(tester);
      await tester.tap(find.text('CREATE'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tag a place'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Search places, e.g. Jaflong, Sylhet'),
        'atlantis',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('No places found'), findsOneWidget);
    });

    testWidgets('a post at a place links to the place page with its content', (
      tester,
    ) async {
      seedPlaces();
      final jaflong = backend.places.first;
      backend.feed.add(
        postJson(
          'p1',
          body: 'Stones, water and clouds.',
          location: 'Jaflong, Sylhet',
          place: placeBrief(jaflong),
          authorId: 'x',
          username: 'other',
          displayName: 'Other',
        ),
      );
      backend.seedUser('other', 'pw-12345678');
      backend.stories.add(
        storyJson('s1', title: 'জাফলংয়ের গল্প', place: placeBrief(jaflong)),
      );
      backend.placePhotos['jaflong'] = [
        {
          'id': 'ph1',
          'url': 'http://127.0.0.1:1/a.png',
          'width': 10,
          'height': 10,
          'post_id': 'p1',
        },
      ];
      await boot(tester);
      await tester.tap(find.text('Jaflong, Sylhet'));
      await tester.pumpAndSettle();
      // Place page: names (English + Bengali), area, seed disclaimer, tabs.
      expect(find.text('Jaflong'), findsWidgets);
      expect(find.text('জাফলং'), findsOneWidget);
      expect(find.text('GOWAINGHAT, SYLHET'), findsOneWidget);
      expect(find.textContaining('not verified'), findsOneWidget);
      expect(find.text('Stones, water and clouds.'), findsOneWidget);

      await tester.tap(find.text('Stories'));
      await tester.pumpAndSettle();
      expect(find.text('জাফলংয়ের গল্প'), findsOneWidget);
      await tester.tap(find.text('Photos'));
      await tester.pumpAndSettle();
      expect(find.byType(SliverGrid), findsOneWidget);
      await tester.tap(find.text('Creators'));
      await tester.pumpAndSettle();
      expect(find.text('@other'), findsOneWidget);
    });

    testWidgets('place page empty states and unknown place error', (
      tester,
    ) async {
      seedPlaces();
      await boot(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(Scaffold).first),
      );
      container.read(routerProvider).push('/places/sreemangal');
      await tester.pumpAndSettle();
      expect(find.text('No posts from Sreemangal yet'), findsOneWidget);
      await tester.tap(find.text('Stories'));
      await tester.pumpAndSettle();
      expect(find.text('No stories about Sreemangal yet'), findsOneWidget);
      await tester.tap(find.text('Photos'));
      await tester.pumpAndSettle();
      expect(find.text('No photos yet'), findsOneWidget);
      await tester.tap(find.text('Creators'));
      await tester.pumpAndSettle();
      expect(find.text('No creators yet'), findsOneWidget);

      container.read(routerProvider).push('/places/nowhere');
      await tester.pumpAndSettle();
      expect(find.text('Place not found'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('profile Places tab lists the places a person documented', (
      tester,
    ) async {
      seedPlaces();
      backend.seedUser('rahim_bd', 'pw-12345678');
      final me = backend.users['rahim_bd']!;
      backend.feed.add(
        postJson(
          'mine',
          body: 'x',
          authorId: me['id'] as String,
          username: 'rahim_bd',
          place: placeBrief(backend.places.first),
        ),
      );
      await boot(tester);
      await tester.tap(find.text('PROFILE'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Places'));
      await tester.pumpAndSettle();
      expect(find.text('Jaflong'), findsOneWidget);
      expect(
        find.text("Cox's Bazar"),
        findsNothing,
      ); // only what they documented
    });

    testWidgets('story editor can tag a place and saves its id', (
      tester,
    ) async {
      seedPlaces();
      await boot(tester);
      await tester.tap(find.text('STORIES'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Write a story'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Title'), 'T');
      await tester.enterText(
        find.widgetWithText(TextField, 'Tell your story…'),
        'Body',
      );
      await tester.ensureVisible(find.text('Tag a place'));
      await tester.tap(find.text('Tag a place'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sreemangal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save draft'));
      await tester.pumpAndSettle();
      expect(backend.stories.single['place_id'], 'place-sreemangal');
    });
  });
}
