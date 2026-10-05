// Renders every major screen on a small phone with large text, in light and
// dark, with Bengali and long content, and fails on any layout overflow or
// framework exception.
import 'package:angon/routing/app_router.dart';
import 'package:angon/services/token_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_backend.dart';

import 'package:angon/services/providers.dart';

import '../support/fake_map.dart';
import '../support/harness.dart';

const _bengali =
    'সিলেটের জাফলং, শ্রীমঙ্গলের চা বাগান আর রাতারগুলের জলে ভাসা বন - বাংলাদেশের সৌন্দর্য কখনো ফুরোয় না। '
    'A very long unbroken token: Supercalifragilisticexpialidocious_Supercalifragilisticexpialidocious';

FakeBackend _populated() {
  final b = FakeBackend()..seedUser('rahim_bd', 'pw-12345678');
  b.seedUser('other_creator_with_long_name', 'pw-12345678');
  b.feed.add(
    postJson(
      'p1',
      body: _bengali,
      location: 'Jaflong, Sylhet — a long location label to test ellipsis',
      username: 'other_creator_with_long_name',
      displayName: 'A Very Long Display Name That Should Ellipsize Nicely',
    ),
  );
  b.stories.add(
    storyJson(
      's1',
      title: 'জাফলং: পর্যটকের চোখের বাইরে — A Long Story Title That Wraps',
      content: '$_bengali\n\n## Heading\n\n$_bengali',
      username: 'other_creator_with_long_name',
    ),
  );
  b.places.add(
    placeJson(
      'jaflong',
      name: 'Jaflong',
      nameLocal: 'জাফলং',
      description: _bengali,
      postCount: 1234,
      storyCount: 56,
    ),
  );
  b.notifications.addAll([
    notificationJson('n1', data: {'preview': _bengali}),
    notificationJson(
      'n2',
      type: 'follow',
      actor: 'other_creator_with_long_name',
      targetType: 'user',
      data: {'username': 'other_creator_with_long_name'},
    ),
    notificationJson(
      'n3',
      type: 'booking',
      actor: null,
      data: {'title': _bengali},
    ),
  ]);
  return b;
}

const _routes = [
  '/',
  '/explore',
  '/create',
  '/stories',
  '/profile',
  '/notifications',
  '/search',
  '/map',
  '/places/jaflong',
  '/posts/p1',
  '/story/s1',
  '/u/other_creator_with_long_name',
  '/profile/edit',
  '/story/new',
];

void main() {
  for (final dark in [false, true]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets(
        'screens fit a 320dp phone (${dark ? 'dark' : 'light'}, text x$scale)',
        (tester) async {
          tester.view.physicalSize = const Size(320, 640);
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.platformBrightnessTestValue = dark
              ? Brightness.dark
              : Brightness.light;
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(() {
            tester.view.reset();
            tester.platformDispatcher.clearAllTestValues();
          });

          final backend = _populated();
          final storage = InMemoryTokenStorage(backend.issueToken('rahim_bd'));
          await tester.pumpWidget(
            buildTestApp(
              backend,
              storage,
              overrides: [
                mapAdapterProvider.overrideWithValue(FakeMapAdapter()),
              ],
            ),
          );
          await tester.pump();
          await tester.pumpAndSettle();
          final container = ProviderScope.containerOf(
            tester.element(find.byType(MaterialApp)),
          );
          final router = container.read(routerProvider);

          final problems = <String>[];
          final previous = FlutterError.onError;
          var current = '';
          FlutterError.onError = (details) {
            final where = RegExp(r'lib/[\w/]+\.dart:\d+')
                .allMatches(details.toString())
                .map((m) => m.group(0))
                .toSet()
                .take(2)
                .join(' ');
            problems.add(
              '$current: ${details.exceptionAsString().split('\n').first} [$where]',
            );
            if (const bool.fromEnvironment('VERBOSE')) {
              debugPrint(details.toString());
            }
          };

          for (final route in _routes) {
            current = route;
            router.go(route);
            // Bounded: some screens legitimately keep a spinner running.
            for (var i = 0; i < 6; i++) {
              await tester.pump(const Duration(milliseconds: 300));
            }
          }
          FlutterError.onError =
              previous; // must be restored before the test ends
          expect(problems, isEmpty, reason: problems.join('\n'));
        },
      );
    }
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'signed-out screens fit with the keyboard open (text x$scale)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(() {
          tester.view.reset();
          tester.platformDispatcher.clearAllTestValues();
        });

        final backend = FakeBackend();
        await tester.pumpWidget(buildTestApp(backend, InMemoryTokenStorage()));
        await tester.pump();
        await tester.pumpAndSettle();
        final router = ProviderScope.containerOf(
          tester.element(find.byType(MaterialApp)),
        ).read(routerProvider);

        final problems = <String>[];
        final previous = FlutterError.onError;
        FlutterError.onError = (d) =>
            problems.add(d.exceptionAsString().split('\n').first);
        for (final route in ['/welcome', '/login', '/register']) {
          router.go(route);
          for (var i = 0; i < 4; i++) {
            await tester.pump(const Duration(milliseconds: 300));
          }
          if (find.byType(TextField).evaluate().isNotEmpty) {
            // Focus the last field: the form must scroll it into view, not overflow.
            await tester.showKeyboard(find.byType(TextField).last);
            await tester.pump(const Duration(milliseconds: 300));
          }
          if (problems.isNotEmpty) problems.add('on $route');
        }
        FlutterError.onError = previous;
        expect(problems, isEmpty, reason: problems.join('\n'));
      },
    );
  }

  testWidgets('profile setup fits with the keyboard open and large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(() {
      tester.view.reset();
      tester.platformDispatcher.clearAllTestValues();
    });
    final backend = FakeBackend()
      ..seedUser('newbie', 'pw-12345678', complete: false);
    final storage = InMemoryTokenStorage(backend.issueToken('newbie'));
    await tester.pumpWidget(buildTestApp(backend, storage));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Tell us about you'), findsOneWidget); // landed on setup
    // Scroll through the whole form; a lazily built list may not have every
    // field mounted, so just walk it and make sure nothing overflows.
    for (var i = 0; i < 4; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -200));
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(tester.takeException(), isNull);
  });
}
