// Opening a screen must not fire the same GET twice (wasted data on slow links).
import 'package:angon/routing/app_router.dart';
import 'package:angon/services/providers.dart';
import 'package:angon/services/token_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_backend.dart';
import '../support/fake_map.dart';
import '../support/harness.dart';

void main() {
  testWidgets('each screen loads its data once', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final backend = FakeBackend()..seedUser('rahim_bd', 'pw-12345678');
    backend.feed.add(postJson('p1', body: 'hello', username: 'other'));
    backend.stories.add(storyJson('s1', title: 'A story'));
    backend.places.add(placeJson('jaflong'));
    backend.notifications.add(notificationJson('n1'));
    final storage = InMemoryTokenStorage(backend.issueToken('rahim_bd'));
    await tester.pumpWidget(
      buildTestApp(
        backend,
        storage,
        overrides: [mapAdapterProvider.overrideWithValue(FakeMapAdapter())],
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();
    final router = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    ).read(routerProvider);

    Map<String, int> gets(Iterable<String> calls) {
      final counts = <String, int>{};
      for (final c in calls.where((c) => c.startsWith('GET '))) {
        counts[c] = (counts[c] ?? 0) + 1;
      }
      return counts;
    }

    // Boot: feed once, badge once.
    expect(gets(backend.calls)['GET /posts'], 1);
    expect(gets(backend.calls)['GET /notifications/unread-count'], 1);

    for (final route in [
      '/explore',
      '/stories',
      '/profile',
      '/notifications',
      '/places/jaflong',
      '/posts/p1',
      '/story/s1',
      '/search',
    ]) {
      final before = backend.calls.length;
      router.go(route);
      await tester.pumpAndSettle();
      final fresh = gets(backend.calls.skip(before));
      final dupes = fresh.entries.where((e) => e.value > 1).toList();
      expect(dupes, isEmpty, reason: '$route repeated: $dupes');
    }
  });
}
