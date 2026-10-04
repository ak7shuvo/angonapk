import 'package:angon/core/errors/app_exception.dart';
import 'package:angon/features/auth/auth_controller.dart';
import 'package:angon/features/stories/story_controllers.dart';
import 'package:angon/features/stories/story_editor_controller.dart';
import 'package:angon/features/stories/story_markup.dart';
import 'package:angon/models/story.dart';
import 'package:angon/services/providers.dart';
import 'package:angon/services/token_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_backend.dart';
import '../support/fake_picker.dart';
import '../support/harness.dart';

late FakeBackend backend;
late InMemoryTokenStorage storage;
late FakeImagePicker picker;

Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 30));

ProviderContainer container() {
  backend.seedUser('rahim_bd', 'pw-12345678');
  storage = InMemoryTokenStorage(backend.issueToken('rahim_bd'));
  final c = ProviderContainer(
    overrides: [
      tokenStorageProvider.overrideWithValue(storage),
      imagePickerProvider.overrideWithValue(picker),
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
    picker = FakeImagePicker();
  });

  group('story markup', () {
    const id = '123e4567-e89b-12d3-a456-426614174000';

    test('parses paragraphs, headings, quotes and images', () {
      final blocks = parseStory(
        'Intro line.\n\n## A heading\n\n> Said the boatman\n> across two lines\n\n![River at dawn]($id)\n\n![River at dawn](asset:$id)\n\nOutro.',
      );
      expect(blocks[0], isA<ParagraphBlock>());
      expect((blocks[1] as HeadingBlock).text, 'A heading');
      expect(
        (blocks[2] as QuoteBlock).text,
        'Said the boatman\nacross two lines',
      );
      // Only the asset: syntax is an image; the bare one stays a paragraph.
      expect(blocks[3], isA<ParagraphBlock>());
      expect((blocks[4] as ImageBlock).assetId, id);
      expect((blocks[4] as ImageBlock).caption, 'River at dawn');
      expect((blocks[5] as ParagraphBlock).text, 'Outro.');
      expect(blocks, hasLength(6));
    });

    test('ignores blank input and keeps Bengali text', () {
      expect(parseStory('  \n\n  '), isEmpty);
      expect(
        (parseStory('পাহাড় আর নদী')[0] as ParagraphBlock).text,
        'পাহাড় আর নদী',
      );
    });

    test('toggleLinePrefix adds and removes prefixes on the caret line', () {
      var r = toggleLinePrefix('one\ntwo\nthree', 5, '## ');
      expect(r.text, 'one\n## two\nthree');
      expect(r.caret, 8);
      r = toggleLinePrefix(r.text, r.caret, '## ');
      expect(r.text, 'one\ntwo\nthree');
      expect(toggleLinePrefix('', 0, '> ').text, '> ');
    });

    test('insertBlock puts the block in its own paragraph', () {
      expect(insertBlock('Hello', 5, 'X').text, 'Hello\n\nX');
      expect(insertBlock('A\n\nB', 3, 'X').text, 'A\n\nX\n\nB');
      expect(insertBlock('', 0, 'X').text, 'X');
      expect(imageToken('abc', 'My [cap]'), '![My  cap](asset:abc)');
    });
  });

  test('Story models parse the API payload (Bengali, cover, media, flags)', () {
    final story = Story.fromJson({
      ...storyJson(
        's1',
        title: 'জাফলংয়ের গল্প',
        cover: {
          'id': 'c1',
          'url': '/media/u/c1.png',
          'width': 1600,
          'height': 900,
        },
        media: [
          {
            'id': 'm1',
            'url': 'https://cdn.example.com/m.png',
            'width': 800,
            'height': 600,
          },
        ],
      ),
      'like_count': 3,
      'liked_by_me': true,
      'following_author': true,
    }, mediaBaseUrl: 'http://api.test');
    expect(story.displayTitle, 'জাফলংয়ের গল্প');
    expect(story.cover!.url, 'http://api.test/media/u/c1.png');
    expect(story.cover!.aspectRatio, closeTo(16 / 9, 1e-9));
    expect(story.media.single.url, 'https://cdn.example.com/m.png');
    expect(
      (story.likeCount, story.likedByMe, story.followingAuthor),
      (3, true, true),
    );
    expect(story.isDraft, isFalse);
    expect(
      Story.fromJson(storyJson('d', title: '  ', status: 'draft')).displayTitle,
      'Untitled story',
    );
  });

  group('StoryEditorController', () {
    StoryEditorController editor(ProviderContainer c, [String? id]) {
      c.listen(storyEditorProvider(id), (_, _) {});
      return c.read(storyEditorProvider(id).notifier);
    }

    test('draft → publish lifecycle against the API contract', () async {
      final c = container();
      await pump();
      final e = editor(c);
      expect(c.read(storyEditorProvider(null)).canPublish, isFalse);
      e.setTitle('জাফলং');
      expect(
        c.read(storyEditorProvider(null)).canPublish,
        isFalse,
      ); // no content yet
      e.setContent('গল্প শুরু হয়।');
      e.addTag('heritage');
      e.setLocation('Sylhet');
      expect(c.read(storyEditorProvider(null)).dirty, isTrue);
      expect(c.read(storyEditorProvider(null)).canPublish, isTrue);

      final draft = await e.save();
      expect(draft!.status, StoryStatus.draft);
      var state = c.read(storyEditorProvider(null));
      expect(state.id, draft.id);
      expect(state.dirty, isFalse);
      expect(backend.stories.single['tags'], ['heritage']);
      expect(backend.stories.single['location_text'], 'Sylhet');

      e.setContent('গল্প চলতে থাকে।');
      final published = await e.save(publish: true);
      expect(published!.status, StoryStatus.published);
      state = c.read(storyEditorProvider(null));
      expect(state.isPublished, isTrue);
      expect(backend.stories, hasLength(1)); // updated, not duplicated
      expect(backend.stories.single['content'], 'গল্প চলতে থাকে।');
    });

    test(
      'publishing without a title or content is blocked client-side',
      () async {
        final c = container();
        await pump();
        final e = editor(c);
        e.setTitle('Only a title');
        expect(await e.save(publish: true), isNull);
        expect(
          c.read(storyEditorProvider(null)).error,
          contains('title and some content'),
        );
        expect(backend.stories, isEmpty);
      },
    );

    test('a failed save keeps the text and reports the error', () async {
      final c = container();
      await pump();
      final e = editor(c);
      e.setTitle('T');
      e.setContent('Body');
      backend.failWith = const NetworkException();
      expect(await e.save(), isNull);
      final state = c.read(storyEditorProvider(null));
      expect(state.error, contains('Cannot reach ANGON'));
      expect(
        (state.title, state.content, state.dirty, state.saving),
        ('T', 'Body', true, false),
      );
      backend.failWith = null;
      expect(await e.save(), isNotNull);
    });

    test('cover upload, replacement and removal are sent to the API', () async {
      final c = container();
      await pump();
      final e = editor(c);
      e.setTitle('T');
      e.setContent('Body');
      picker.next = [fakeImage('cover.png')];
      await e.pickCover();
      expect(c.read(storyEditorProvider(null)).cover, isNotNull);
      await e.save();
      expect((backend.stories.single['cover'] as Map)['id'], 'asset-0');
      e.removeCover();
      await e.save();
      expect(backend.stories.single['cover'], isNull);
    });

    test('rejects unsupported or oversized images without uploading', () async {
      final c = container();
      await pump();
      final e = editor(c);
      picker.next = [fakeImage('a.gif', type: 'image/gif')];
      await e.pickCover();
      expect(
        c.read(storyEditorProvider(null)).notice,
        contains('JPEG, PNG and WebP'),
      );
      expect(c.read(storyEditorProvider(null)).cover, isNull);
      expect(backend.calls.where((x) => x.startsWith('UPLOAD')), isEmpty);
    });

    test('inline photo returns an insertable token and is tracked', () async {
      final c = container();
      await pump();
      final e = editor(c);
      picker.next = [fakeImage('inline.png')];
      final token = await e.addInlineImage();
      expect(token, '![](asset:asset-0)');
      expect(c.read(storyEditorProvider(null)).images.keys, ['asset-0']);
      expect(c.read(storyEditorProvider(null)).uploads, 0);
    });

    test('editing an existing story loads it, then saves changes', () async {
      final c = container();
      backend.stories.add(
        storyJson(
          's9',
          status: 'draft',
          username: 'rahim_bd',
          title: 'Old',
          content: 'Old body',
        ),
      );
      await pump();
      final e = editor(c, 's9');
      await pump();
      var state = c.read(storyEditorProvider('s9'));
      expect(
        (state.loading, state.title, state.status),
        (false, 'Old', StoryStatus.draft),
      );
      e.setTitle('New');
      await e.save();
      expect(backend.stories.single['title'], 'New');
      expect(backend.stories, hasLength(1));
      state = c.read(storyEditorProvider('s9'));
      expect(state.dirty, isFalse);
    });

    test('loading someone else\'s draft fails with not-found', () async {
      final c = container();
      backend.stories.add(storyJson('x', status: 'draft', username: 'other'));
      await pump();
      editor(c, 'x');
      await pump();
      expect(
        c.read(storyEditorProvider('x')).loadError,
        isA<NotFoundException>(),
      );
    });
  });

  group('StoryEngagementController', () {
    StorySummary story() => StorySummary.fromJson(storyJson('s1'));

    test('like is optimistic then server truth; rollback on failure', () async {
      backend.stories.add(storyJson('s1'));
      final c = container();
      await pump();
      final n = c.read(storyEngagementProvider.notifier);
      final f = n.toggleLike(story());
      expect(c.read(storyEngagementProvider)['s1']!.liked, isTrue);
      await f;
      expect(c.read(storyEngagementProvider)['s1']!.likeCount, 1);
      backend.failWith = const ServerException();
      await expectLater(n.toggleLike(story()), throwsA(isA<ServerException>()));
      expect(c.read(storyEngagementProvider)['s1']!.liked, isTrue); // restored
    });

    test('save toggles', () async {
      backend.stories.add(storyJson('s1'));
      final c = container();
      await pump();
      await c.read(storyEngagementProvider.notifier).toggleSave(story());
      expect(backend.storySaves['s1'], ['rahim_bd']);
      expect(c.read(storyEngagementProvider)['s1']!.saved, isTrue);
    });
  });

  group('Stories UI', () {
    late InMemoryTokenStorage uiStorage;

    Future<void> boot(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      if (!backend.users.containsKey('rahim_bd')) {
        backend.seedUser('rahim_bd', 'pw-12345678');
      }
      uiStorage = InMemoryTokenStorage(backend.issueToken('rahim_bd'));
      await tester.pumpWidget(buildTestApp(backend, uiStorage, picker: picker));
      await tester.pump();
      await tester.pumpAndSettle();
      await tester.tap(find.text('STORIES'));
      await tester.pumpAndSettle();
    }

    testWidgets('empty Stories tab invites writing', (tester) async {
      await boot(tester);
      expect(find.text('No stories yet'), findsOneWidget);
      await tester.tap(find.text('Write a story').last);
      await tester.pumpAndSettle();
      expect(find.text('Tell your story…'), findsOneWidget);
    });

    testWidgets('lists published stories and opens the editorial reader', (
      tester,
    ) async {
      const imageId = '123e4567-e89b-12d3-a456-426614174000';
      backend.stories.add(
        storyJson(
          's1',
          title: 'জাফলংয়ের গল্প',
          content:
              'পাহাড় আর নদীর মিলনস্থল।\n\n## ভোরের আলো\n\n> নৌকা ভাসে ধীরে\n\n![ভোরের নদী](asset:$imageId)\n\nশেষ অনুচ্ছেদ।',
          media: [
            {'id': imageId, 'url': 'x', 'width': 800, 'height': 600},
          ],
        ),
      );
      backend.stories.add(
        storyJson('s2', title: 'Second story', tags: const ['heritage']),
      );
      await boot(tester);
      expect(find.text('জাফলংয়ের গল্প'), findsOneWidget);
      expect(find.text('Second story'), findsOneWidget);

      await tester.tap(find.text('জাফলংয়ের গল্প'));
      await tester.pumpAndSettle();
      // Reader: title, byline, and each block type rendered.
      expect(find.text('জাফলংয়ের গল্প'), findsOneWidget);
      expect(
        find.textContaining('1 min read'),
        findsWidgets,
      ); // byline + related card
      expect(find.text('ভোরের আলো'), findsOneWidget); // heading
      expect(find.text('নৌকা ভাসে ধীরে'), findsOneWidget); // pull quote
      expect(find.text('ভোরের নদী'), findsOneWidget); // image caption
      expect(find.text('WRITTEN BY'), findsOneWidget);
      expect(find.text('MORE STORIES'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('reader like and save are server-backed', (tester) async {
      backend.stories.add(storyJson('s1', title: 'A story'));
      await boot(tester);
      await tester.tap(find.text('A story'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Like'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Like'));
      await tester.pumpAndSettle();
      expect(backend.storyLikes['s1'], {'rahim_bd'});
      expect(find.text('1'), findsWidgets);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(backend.storySaves['s1'], ['rahim_bd']);
      expect(find.text('Saved'), findsOneWidget);
    });

    testWidgets(
      'write → save draft → shows under My drafts → publish → reader',
      (tester) async {
        await boot(tester);
        await tester.tap(find.byTooltip('Write a story'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Title'),
          'My first story',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Tell your story…'),
          'It began on the water.',
        );
        await tester.pump();
        await tester.tap(find.text('Save draft'));
        await tester.pumpAndSettle();
        expect(find.text('Draft saved.'), findsOneWidget);
        expect(backend.stories.single['status'], 'draft');

        await tester.tap(find.text('Publish'));
        await tester.pumpAndSettle();
        expect(backend.stories.single['status'], 'published');
        expect(find.text('My first story'), findsOneWidget); // reader
        expect(find.text('It began on the water.'), findsOneWidget);
        expect(backend.stories, hasLength(1));
      },
    );

    testWidgets('closing the editor with unsaved changes asks first', (
      tester,
    ) async {
      await boot(tester);
      await tester.tap(find.byTooltip('Write a story'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Title'),
        'Unsaved',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsNothing);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.text('Stories'), findsWidgets); // back on the tab
      expect(backend.stories, isEmpty);
    });

    testWidgets('Publish stays disabled until title and content exist', (
      tester,
    ) async {
      await boot(tester);
      await tester.tap(find.byTooltip('Write a story'));
      await tester.pumpAndSettle();
      FilledButton publish() =>
          tester.widget(find.widgetWithText(FilledButton, 'Publish'));
      expect(publish().onPressed, isNull);
      await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Title');
      await tester.pump();
      expect(publish().onPressed, isNull);
      await tester.enterText(
        find.widgetWithText(TextField, 'Tell your story…'),
        'Body',
      );
      await tester.pump();
      expect(publish().onPressed, isNotNull);
    });

    testWidgets('drafts open in the editor; own story menu can delete', (
      tester,
    ) async {
      backend.seedUser('rahim_bd', 'pw-12345678');
      backend.stories
        ..add(
          storyJson(
            'd1',
            status: 'draft',
            username: 'rahim_bd',
            title: 'Half done',
            content: 'Half',
          ),
        )
        ..add(
          storyJson(
            'p1',
            authorId: backend.users['rahim_bd']!['id'] as String,
            username: 'rahim_bd',
            title: 'Finished one',
            displayName: 'Rahim',
          ),
        );
      await boot(tester);
      await tester.tap(find.text('My drafts'));
      await tester.pumpAndSettle();
      expect(find.text('Half done'), findsOneWidget);
      expect(find.text('Finished one'), findsNothing);
      await tester.tap(find.text('Half done'));
      await tester.pumpAndSettle();
      expect(find.text('New story'), findsOneWidget); // editor, prefilled
      expect(find.text('Half'), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Published'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Finished one'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Story options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete story'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(backend.stories.where((s) => s['id'] == 'p1'), isEmpty);
    });

    testWidgets('error and retry on the story feed', (tester) async {
      backend.stories.add(storyJson('s1', title: 'Resilient story'));
      backend.seedUser('rahim_bd', 'pw-12345678');
      uiStorage = InMemoryTokenStorage(backend.issueToken('rahim_bd'));
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(buildTestApp(backend, uiStorage));
      await tester.pump();
      await tester.pumpAndSettle();
      backend.failWith = const NetworkException();
      await tester.tap(find.text('STORIES'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Cannot reach ANGON'), findsOneWidget);
      backend.failWith = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Resilient story'), findsOneWidget);
    });
  });
}
