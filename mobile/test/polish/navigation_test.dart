import 'package:angon/services/token_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_backend.dart';
import '../support/harness.dart';

void main() {
  testWidgets(
    'Android back from another tab goes to HOME, not out of the app',
    (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final backend = FakeBackend()..seedUser('rahim_bd', 'pw-12345678');
      await tester.pumpWidget(
        buildTestApp(
          backend,
          InMemoryTokenStorage(backend.issueToken('rahim_bd')),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();
      int selected() => tester
          .widget<NavigationBar>(find.byType(NavigationBar))
          .selectedIndex;

      expect(selected(), 0);
      await tester.tap(find.text('STORIES'));
      await tester.pumpAndSettle();
      expect(selected(), 3);

      final handled = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(handled, isTrue);
      expect(selected(), 0);
    },
  );
}
