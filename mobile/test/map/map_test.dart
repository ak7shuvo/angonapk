import 'package:angon/config/app_config.dart';
import 'package:angon/core/errors/app_exception.dart';
import 'package:angon/core/maps/map_provider.dart';
import 'package:angon/core/maps/osm_map_adapter.dart';
import 'package:angon/features/auth/auth_controller.dart';
import 'package:angon/features/map/map_controller.dart';
import 'package:angon/routing/app_router.dart';
import 'package:angon/services/providers.dart';
import 'package:angon/services/token_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_backend.dart';
import '../support/fake_map.dart';
import '../support/harness.dart';

late FakeBackend backend;
late FakeMapAdapter map;

Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 30));

void seedWorld() {
  backend.places
    ..add(
      placeJson(
        'jaflong',
        name: 'Jaflong',
        lat: 25.17,
        lng: 92.02,
        division: 'Sylhet',
      ),
    )
    ..add(
      placeJson(
        'sreemangal',
        name: 'Sreemangal',
        lat: 24.31,
        lng: 91.73,
        division: 'Sylhet',
        district: 'Moulvibazar',
      ),
    )
    ..add(
      placeJson(
        'coxs-bazar',
        name: "Cox's Bazar",
        lat: 21.43,
        lng: 92.01,
        division: 'Chattogram',
        district: "Cox's Bazar",
      ),
    );
}

ProviderContainer container() {
  backend.seedUser('rahim_bd', 'pw-12345678');
  final storage = InMemoryTokenStorage(backend.issueToken('rahim_bd'));
  final c = ProviderContainer(
    overrides: [
      tokenStorageProvider.overrideWithValue(storage),
      mapAdapterProvider.overrideWithValue(map),
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

void main() {
  setUp(() {
    backend = FakeBackend();
    map = FakeMapAdapter();
  });

  test('GeoBounds.around finds the enclosing box', () {
    final b = GeoBounds.around(const [
      GeoPoint(24, 90),
      GeoPoint(26, 92),
      GeoPoint(25, 91),
    ])!;
    expect((b.south, b.north, b.west, b.east), (24, 26, 90, 92));
    expect(GeoBounds.around(const []), isNull);
  });

  test('AppConfig defaults to OpenStreetMap with attribution', () {
    const c = AppConfig(
      environment: AppEnvironment.development,
      apiBaseUrl: 'http://x',
    );
    expect(c.mapProvider, MapProviderKind.osm);
    expect(c.mapTileUrl, contains('{z}/{x}/{y}'));
    expect(c.mapAttribution, contains('OpenStreetMap'));
  });

  group('PlaceMapController', () {
    test('loads all places and the divisions for the filter', () async {
      seedWorld();
      final c = container();
      c.listen(placeMapProvider(null), (_, _) {});
      await pump();
      await pump();
      final s = c.read(placeMapProvider(null));
      expect(s.loading, isFalse);
      expect(s.places, hasLength(3));
      expect(s.divisions, ['Chattogram', 'Sylhet']);
      expect(s.selected, isNull);
    });

    test('division filter reloads and fits the camera', () async {
      seedWorld();
      final c = container();
      c.listen(placeMapProvider(null), (_, _) {});
      await pump();
      await pump();
      await c.read(placeMapProvider(null).notifier).setDivision('Sylhet');
      final s = c.read(placeMapProvider(null));
      expect(s.places.map((p) => p.slug), ['jaflong', 'sreemangal']);
      expect(s.divisions, ['Chattogram', 'Sylhet']); // chips stay available
      expect(s.focus!.fit, isNotNull);
      expect(s.focus!.fit!.north, 25.17);
      await c.read(placeMapProvider(null).notifier).setDivision(null);
      expect(c.read(placeMapProvider(null)).places, hasLength(3));
    });

    test('search this area queries the viewport bounds', () async {
      seedWorld();
      final c = container();
      c.listen(placeMapProvider(null), (_, _) {});
      await pump();
      await pump();
      final n = c.read(placeMapProvider(null).notifier);
      // A programmatic move does not offer "search this area"; a user pan does.
      n.onViewportChanged(const MapViewport(center: GeoPoint(24, 91), zoom: 8));
      expect(c.read(placeMapProvider(null)).canSearchHere, isFalse);
      n.onViewportChanged(
        const MapViewport(
          center: GeoPoint(24.5, 91.8),
          zoom: 8,
          bounds: GeoBounds(south: 24, west: 91, north: 26, east: 93),
          byUser: true,
        ),
      );
      expect(c.read(placeMapProvider(null)).canSearchHere, isTrue);
      await n.searchThisArea();
      final s = c.read(placeMapProvider(null));
      expect(s.places.map((p) => p.slug), [
        'jaflong',
        'sreemangal',
      ]); // Cox's Bazar is outside
      expect(s.inView, 2);
      expect(s.canSearchHere, isFalse);
    });

    test('opens focused on a given place', () async {
      seedWorld();
      final c = container();
      c.listen(placeMapProvider('sreemangal'), (_, _) {});
      await pump();
      await pump();
      final s = c.read(placeMapProvider('sreemangal'));
      expect(s.selected!.slug, 'sreemangal');
      expect(s.focus!.point!.lat, 24.31);
    });

    test(
      'select moves the camera; deselect clears; failed tiles switch to list',
      () async {
        seedWorld();
        final c = container();
        c.listen(placeMapProvider(null), (_, _) {});
        await pump();
        await pump();
        final n = c.read(placeMapProvider(null).notifier);
        final jaflong = c.read(placeMapProvider(null)).places.first;
        n.select(jaflong);
        expect(c.read(placeMapProvider(null)).focus!.point!.lng, 92.02);
        n.select(null);
        expect(c.read(placeMapProvider(null)).selected, isNull);
        n.tilesFailed();
        expect(c.read(placeMapProvider(null)).mode, MapMode.list);
        expect(c.read(placeMapProvider(null)).tilesFailed, isTrue);
      },
    );

    test('a failed load keeps an error until retried', () async {
      seedWorld();
      final c = container();
      backend.failWith = const NetworkException();
      c.listen(placeMapProvider(null), (_, _) {});
      await pump();
      await pump();
      expect(c.read(placeMapProvider(null)).error, isA<NetworkException>());
      backend.failWith = null;
      await c.read(placeMapProvider(null).notifier).load();
      expect(c.read(placeMapProvider(null)).places, hasLength(3));
      expect(c.read(placeMapProvider(null)).error, isNull);
    });
  });

  group('Map UI', () {
    Future<void> boot(
      WidgetTester tester, {
      List<dynamic> extra = const [],
    }) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      if (!backend.users.containsKey('rahim_bd')) {
        backend.seedUser('rahim_bd', 'pw-12345678');
      }
      final storage = InMemoryTokenStorage(backend.issueToken('rahim_bd'));
      await tester.pumpWidget(
        buildTestApp(
          backend,
          storage,
          overrides: [mapAdapterProvider.overrideWithValue(map)],
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();
    }

    Future<void> openMap(WidgetTester tester, [String path = '/map']) async {
      final container = ProviderScope.containerOf(
        tester.element(find.byType(Scaffold).first),
      );
      container.read(routerProvider).push(path);
      await tester.pumpAndSettle();
    }

    testWidgets(
      'shows a marker per place; selecting one shows the sheet with nearby content',
      (tester) async {
        seedWorld();
        backend.seedUser('other', 'pw-12345678');
        final jaflong = backend.places.first;
        backend.feed.add(
          postJson(
            'p1',
            body: 'Stones at dawn',
            authorId: 'x',
            username: 'other',
            place: placeBrief(jaflong),
          ),
        );
        backend.stories.add(
          storyJson('s1', title: 'জাফলংয়ের গল্প', place: placeBrief(jaflong)),
        );
        await boot(tester);
        await openMap(tester);
        expect(find.text('pin:Jaflong'), findsOneWidget);
        expect(find.text('pin:Sreemangal'), findsOneWidget);
        expect(find.text("pin:Cox's Bazar"), findsOneWidget);

        await tester.tap(find.text('pin:Jaflong'));
        await tester.pumpAndSettle();
        expect(find.text('Open Jaflong'), findsOneWidget);
        expect(find.text('NEARBY'), findsOneWidget);
        expect(find.text('জাফলংয়ের গল্প'), findsOneWidget);
        expect(find.text('Stones at dawn'), findsOneWidget);
        expect(find.text('pin:Jaflong*'), findsOneWidget); // marked selected

        await tester.tap(find.text('Open Jaflong'));
        await tester.pumpAndSettle();
        expect(find.text('Posts'), findsWidgets); // the place page
      },
    );

    testWidgets('division chips filter the markers', (tester) async {
      seedWorld();
      await boot(tester);
      await openMap(tester);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Chattogram'));
      await tester.pumpAndSettle();
      expect(find.text("pin:Cox's Bazar"), findsOneWidget);
      expect(find.text('pin:Jaflong'), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, 'All Bangladesh'));
      await tester.pumpAndSettle();
      expect(find.text('pin:Jaflong'), findsOneWidget);
    });

    testWidgets(
      'panning offers "Search this area", which narrows the markers',
      (tester) async {
        seedWorld();
        await boot(tester);
        await openMap(tester);
        expect(find.text('Search this area'), findsNothing);
        map.pan(const GeoBounds(south: 24, west: 91, north: 26, east: 93));
        await tester.pump();
        expect(find.text('Search this area'), findsOneWidget);
        await tester.tap(find.text('Search this area'));
        await tester.pumpAndSettle();
        expect(find.text("pin:Cox's Bazar"), findsNothing);
        expect(find.text('2 places in this area'), findsOneWidget);
      },
    );

    testWidgets('list toggle and the tile-failure fallback', (tester) async {
      seedWorld();
      await boot(tester);
      await openMap(tester);
      await tester.tap(find.byTooltip('Show as list'));
      await tester.pumpAndSettle();
      expect(find.text('Jaflong'), findsOneWidget);
      expect(find.text('pin:Jaflong'), findsNothing);
      await tester.tap(find.byTooltip('Show map'));
      await tester.pumpAndSettle();
      expect(find.text('pin:Jaflong'), findsOneWidget);
      map.failTiles();
      await tester.pumpAndSettle();
      expect(find.textContaining('could not load'), findsOneWidget);
      expect(find.text('Jaflong'), findsOneWidget); // now a list
    });

    testWidgets('opens focused on a place from a link', (tester) async {
      seedWorld();
      await boot(tester);
      await openMap(tester, '/map?place=sreemangal');
      expect(find.text('Open Sreemangal'), findsOneWidget);
      expect(map.focuses, isNotEmpty);
    });

    testWidgets('no configured provider shows a graceful list fallback', (
      tester,
    ) async {
      seedWorld();
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      backend.seedUser('rahim_bd', 'pw-12345678');
      final storage = InMemoryTokenStorage(backend.issueToken('rahim_bd'));
      await tester.pumpWidget(
        buildTestApp(
          backend,
          storage,
          overrides: [mapAdapterProvider.overrideWithValue(null)],
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();
      await openMap(tester);
      expect(find.textContaining('not configured'), findsOneWidget);
      expect(find.text('Jaflong'), findsOneWidget);
      expect(find.byTooltip('Show map'), findsNothing); // nothing to toggle to
    });

    testWidgets('error state offers retry', (tester) async {
      seedWorld();
      await boot(tester);
      backend.failWith = const NetworkException();
      await openMap(tester);
      expect(find.textContaining('Cannot reach ANGON'), findsOneWidget);
      backend.failWith = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('pin:Jaflong'), findsOneWidget);
    });
  });

  testWidgets('OsmMapAdapter renders markers, attribution and reports taps', (
    tester,
  ) async {
    MapMarkerData? tapped;
    const adapter = OsmMapAdapter(
      tileUrl: 'https://tiles.example/{z}/{x}/{y}.png',
      attribution: '© Test Map Credit',
      tilesEnabled: false, // no network in tests
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 600,
            child: Builder(
              builder: (context) => adapter.build(
                context,
                initial: const MapViewport(
                  center: GeoPoint(25.17, 92.02),
                  zoom: 10,
                ),
                markers: const [
                  MapMarkerData(
                    id: 'a',
                    point: GeoPoint(25.17, 92.02),
                    label: 'Jaflong',
                  ),
                ],
                onMarkerTap: (m) => tapped = m,
                onViewportChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.bySemanticsLabel('Jaflong'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.place));
    expect(tapped?.id, 'a');
  });
}
