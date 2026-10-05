import 'package:angon/core/errors/app_exception.dart';
import 'package:angon/models/report.dart';
import 'package:angon/services/token_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_backend.dart';
import '../support/harness.dart';

late FakeBackend backend;
late InMemoryTokenStorage storage;

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

Future<void> openMenu(WidgetTester tester, String tooltip, String entry) async {
  await tester.tap(find.byTooltip(tooltip));
  await tester.pumpAndSettle();
  await tester.tap(find.text(entry));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => backend = FakeBackend());

  test('enums map to the API vocabulary', () {
    expect(ReportTarget.values.map((t) => t.apiName), [
      'post',
      'story',
      'comment',
      'user',
    ]);
    expect(
      ReportReason.values.map((r) => r.apiName),
      containsAll(['spam', 'harassment', 'hate', 'other']),
    );
  });

  testWidgets('report a post: pick a reason, add details, send', (
    tester,
  ) async {
    otherPost();
    await boot(tester);
    await openMenu(tester, 'Post options', 'Report post');
    expect(find.text('Report this post'), findsOneWidget);
    final send = find.widgetWithText(FilledButton, 'Send report');
    expect(
      tester.widget<FilledButton>(send).onPressed,
      isNull,
    ); // needs a reason

    await tester.tap(find.text('Spam or misleading'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '  an advert  ');
    await tester.pump();
    await tester.tap(send);
    await tester.pumpAndSettle();

    expect(find.text('Report this post'), findsNothing); // sheet closed
    expect(find.text('Thanks. Our team will take a look.'), findsOneWidget);
    expect(backend.reports, hasLength(1));
    expect(backend.reports.single, containsPair('target_type', 'post'));
    expect(backend.reports.single, containsPair('target_id', 'p1'));
    expect(backend.reports.single, containsPair('reason', 'spam'));
    expect(backend.reports.single, containsPair('details', 'an advert'));
  });

  testWidgets('a repeat report shows the server message and stays open', (
    tester,
  ) async {
    otherPost();
    await boot(tester);
    backend.reports.add({'key': 'post:p1', 'reporter': 'rahim_bd'});
    await openMenu(tester, 'Post options', 'Report post');
    await tester.tap(find.text('Hate speech'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Send report'));
    await tester.pumpAndSettle();
    expect(find.text('You have already reported this'), findsOneWidget);
    expect(find.text('Report this post'), findsOneWidget);
    expect(backend.reports, hasLength(1));
  });

  testWidgets('a network failure keeps the sheet and lets you retry', (
    tester,
  ) async {
    otherPost();
    await boot(tester);
    await openMenu(tester, 'Post options', 'Report post');
    await tester.tap(find.text('Something else'));
    await tester.pump();
    backend.failWith = const NetworkException();
    await tester.tap(find.widgetWithText(FilledButton, 'Send report'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Cannot reach ANGON'), findsOneWidget);
    backend.failWith = null;
    await tester.tap(find.widgetWithText(FilledButton, 'Send report'));
    await tester.pumpAndSettle();
    expect(backend.reports, hasLength(1));
    expect(find.text('Report this post'), findsNothing);
  });

  testWidgets('you cannot report your own post', (tester) async {
    backend.seedUser('rahim_bd', 'pw-12345678');
    backend.feed.add(
      postJson(
        'mine',
        body: 'my words',
        authorId: backend.users['rahim_bd']!['id'] as String,
        username: 'rahim_bd',
      ),
    );
    await boot(tester);
    await tester.tap(find.byTooltip('Post options'));
    await tester.pumpAndSettle();
    expect(find.text('Delete post'), findsOneWidget);
    expect(find.text('Report post'), findsNothing);
  });

  testWidgets('report a comment from the post screen', (tester) async {
    otherPost();
    backend.seedUser('other', 'pw-12345678');
    backend.comments['p1'] = [
      {
        'id': 'c9',
        'post_id': 'p1',
        'body': 'rude remark',
        'author': {'id': 'x', 'username': 'other', 'display_name': 'Other'},
        'created_at': '2026-01-01T00:00:00+00:00',
        'is_mine': false,
      },
    ];
    await boot(tester);
    await tester.tap(find.byIcon(Icons.chat_bubble_outline_rounded));
    await tester.pumpAndSettle();
    await openMenu(tester, 'Comment options', 'Report comment');
    expect(find.text('Report this comment'), findsOneWidget);
    await tester.tap(find.text('Harassment or bullying'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Send report'));
    await tester.pumpAndSettle();
    expect(backend.reports.single, containsPair('target_type', 'comment'));
    expect(backend.reports.single, containsPair('target_id', 'c9'));
  });

  testWidgets('report a story', (tester) async {
    backend.stories.add(storyJson('s1', title: 'Spammy story'));
    await boot(tester);
    await tester.tap(find.text('STORIES'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spammy story'));
    await tester.pumpAndSettle();
    await openMenu(tester, 'Story options', 'Report story');
    await tester.tap(find.text('Spam or misleading'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Send report'));
    await tester.pumpAndSettle();
    expect(backend.reports.single, containsPair('target_type', 'story'));
    expect(backend.reports.single, containsPair('target_id', 's1'));
  });

  testWidgets('report a profile, but not your own', (tester) async {
    backend.seedUser('other', 'pw-12345678');
    otherPost();
    await boot(tester);
    await tester.tap(find.text('Other').first);
    await tester.pumpAndSettle();
    await openMenu(tester, 'Profile options', 'Report profile');
    expect(find.text('Report this profile'), findsOneWidget);
    await tester.tap(find.text('Nudity or sexual content'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Send report'));
    await tester.pumpAndSettle();
    expect(backend.reports.single, containsPair('target_type', 'user'));
    expect(backend.reports.single['target_id'], backend.users['other']!['id']);
  });
}
