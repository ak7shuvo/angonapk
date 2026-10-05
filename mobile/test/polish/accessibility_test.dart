// Tap targets (48dp) and semantic labels on the main screens.
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
  testWidgets('main screens meet tap-target and label guidelines', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final backend = FakeBackend()..seedUser('rahim_bd', 'pw-12345678');
    backend.feed.add(postJson('p1', body: 'hello', username: 'other'));
    backend.stories.add(storyJson('s1', title: 'A story'));
    backend.places.add(placeJson('jaflong'));
    backend.notifications.add(notificationJson('n1'));
    await tester.pumpWidget(
      buildTestApp(
        backend,
        InMemoryTokenStorage(backend.issueToken('rahim_bd')),
        overrides: [mapAdapterProvider.overrideWithValue(FakeMapAdapter())],
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();
    final router = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    ).read(routerProvider);

    for (final route in [
      '/',
      '/explore',
      '/stories',
      '/profile',
      '/notifications',
      '/places/jaflong',
      '/posts/p1',
      '/story/s1',
    ]) {
      router.go(route);
      await tester.pumpAndSettle();
      // The reader's paragraphs are selectable text (content, not controls),
      // which the guideline would misreport as undersized tap targets.
      if (route != '/story/s1') {
        await expectLater(
          tester,
          meetsGuideline(androidTapTargetGuideline),
          reason: 'tap targets on $route',
        );
      }
      await expectLater(
        tester,
        meetsGuideline(labeledTapTargetGuideline),
        reason: 'labels on $route',
      );
    }
    handle.dispose();
  });
}
