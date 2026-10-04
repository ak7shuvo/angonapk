import 'dart:convert';

import 'package:angon/core/errors/app_exception.dart';
import 'package:angon/core/network/api_client.dart';
import 'package:angon/config/app_config.dart';
import 'package:angon/features/auth/auth_controller.dart';
import 'package:angon/features/composer/composer_controller.dart';
import 'package:angon/features/feed/feed_controller.dart';
import 'package:angon/services/draft_store.dart';
import 'package:angon/services/image_picker_service.dart';
import 'package:angon/services/providers.dart';
import 'package:angon/services/token_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/fake_backend.dart';
import '../support/fake_picker.dart';
import '../support/harness.dart';

late FakeBackend backend;
late InMemoryTokenStorage storage;
late InMemoryDraftStore drafts;
late FakeImagePicker picker;

Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 30));

ProviderContainer container() {
  backend.seedUser('rahim_bd', 'pw-12345678');
  storage = InMemoryTokenStorage(backend.issueToken('rahim_bd'));
  final c = ProviderContainer(
    overrides: [
      tokenStorageProvider.overrideWithValue(storage),
      draftStoreProvider.overrideWithValue(drafts),
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

Future<ComposerController> readyComposer(ProviderContainer c) async {
  await pump();
  c.listen(composerControllerProvider, (_, _) {});
  await pump();
  return c.read(composerControllerProvider.notifier);
}

void main() {
  setUp(() {
    backend = FakeBackend();
    drafts = InMemoryDraftStore();
    picker = FakeImagePicker();
  });

  group('normalizeTag', () {
    test('mirrors server rules', () {
      expect(normalizeTag('#Culture'), 'culture');
      expect(normalizeTag('  food_2 '), 'food_2');
      expect(
        normalizeTag('ঐতিহ্য'),
        'ঐতিহ্য',
      ); // Bengali combining marks allowed
      expect(normalizeTag('x'), isNull);
      expect(normalizeTag('has space'), isNull);
      expect(normalizeTag('bad-dash'), isNull);
      expect(normalizeTag('a' * 31), isNull);
    });
  });

  group('ComposerController', () {
    test('cannot submit empty; text enables submit', () async {
      final c = container();
      final composer = await readyComposer(c);
      expect(c.read(composerControllerProvider).canSubmit, isFalse);
      composer.setText('  ');
      expect(c.read(composerControllerProvider).canSubmit, isFalse);
      composer.setText('Hello Sylhet');
      expect(c.read(composerControllerProvider).canSubmit, isTrue);
      composer.setText('x' * (maxPostLength + 1));
      expect(c.read(composerControllerProvider).canSubmit, isFalse);
    });

    test('rejects unsupported type, oversized file and excess photos with a notice', () async {
      final c = container();
      final composer = await readyComposer(c);
      composer.addImages([fakeImage('a.gif', type: 'image/gif')]);
      expect(c.read(composerControllerProvider).attachments, isEmpty);
      expect(
        c.read(composerControllerProvider).notice,
        contains('JPEG, PNG and WebP'),
      );

      composer.addImages([fakeImage('big.png', size: 11 * 1024 * 1024)]);
      expect(c.read(composerControllerProvider).attachments, isEmpty);
      expect(c.read(composerControllerProvider).notice, contains('10 MB'));

      composer.addImages([for (var i = 0; i < 12; i++) fakeImage('$i.png')]);
      expect(
        c.read(composerControllerProvider).attachments,
        hasLength(maxPostImages),
      );
      expect(c.read(composerControllerProvider).notice, contains('up to 10'));
      await pump();
    });

    test(
      'uploads photos with progress and attaches their ids on submit',
      () async {
        final c = container();
        final composer = await readyComposer(c);
        composer.addImages([
          fakeImage('a.png'),
          fakeImage('b.png'),
          fakeImage('c.png'),
        ]);
        expect(c.read(composerControllerProvider).hasUploading, isTrue);
        expect(
          c.read(composerControllerProvider).canSubmit,
          isFalse,
        ); // still uploading
        await pump();
        await pump();
        final state = c.read(composerControllerProvider);
        expect(
          state.attachments.every((a) => a.status == UploadStatus.uploaded),
          isTrue,
        );
        expect(state.attachments.every((a) => a.progress == 1), isTrue);
        expect(state.canSubmit, isTrue); // photo-only posts are fine

        composer
          ..setText('Three photos')
          ..setLocation('Jaflong, Sylhet')
          ..addTag('#Travel');
        final post = await composer.submit();
        expect(post, isNotNull);
        expect(backend.calls, contains('POST /posts'));
        final sent = backend.created.single;
        expect(sent['media'], hasLength(3));
        expect(sent['tags'], ['travel']);
        expect(sent['location_text'], 'Jaflong, Sylhet');
        // State resets after success and the draft is gone.
        expect(c.read(composerControllerProvider).text, '');
        expect(c.read(composerControllerProvider).attachments, isEmpty);
        expect(
          await drafts.load(
            c
                .read(authControllerProvider)
                .let((a) => (a as Authenticated).user.id),
          ),
          isNull,
        );
      },
    );

    test('failed upload blocks submit until retried or removed', () async {
      final c = container();
      final composer = await readyComposer(c);
      composer.setText('with a photo');
      var failures = 1;
      backend.uploadFailure = (_) =>
          failures-- > 0 ? const NetworkException() : null;
      composer.addImages([fakeImage('a.png')]);
      await pump();
      var state = c.read(composerControllerProvider);
      expect(state.attachments.single.status, UploadStatus.failed);
      expect(state.attachments.single.error, contains('Cannot reach ANGON'));
      expect(state.hasFailed, isTrue);
      expect(state.canSubmit, isFalse);

      composer.retryUpload(state.attachments.single.localId);
      await pump();
      state = c.read(composerControllerProvider);
      expect(state.attachments.single.status, UploadStatus.uploaded);
      expect(state.canSubmit, isTrue);

      // A failed one can also just be removed.
      backend.uploadFailure = (_) => const ServerException();
      composer.addImages([fakeImage('b.png')]);
      await pump();
      expect(c.read(composerControllerProvider).canSubmit, isFalse);
      composer.removeAttachment(
        c.read(composerControllerProvider).attachments.last.localId,
      );
      expect(c.read(composerControllerProvider).canSubmit, isTrue);
    });

    test('removing an uploaded photo discards it on the server', () async {
      final c = container();
      final composer = await readyComposer(c);
      composer.addImages([fakeImage('a.png')]);
      await pump();
      final a = c.read(composerControllerProvider).attachments.single;
      composer.removeAttachment(a.localId);
      await pump();
      expect(backend.deletedMedia, [a.uploaded!.id]);
    });

    test('submit failure keeps everything the user entered', () async {
      final c = container();
      final composer = await readyComposer(c);
      composer
        ..setText('keep me')
        ..addTag('culture');
      backend.failWith = const ServerException();
      expect(await composer.submit(), isNull);
      final state = c.read(composerControllerProvider);
      expect(state.error, isNotNull);
      expect(state.submitting, isFalse);
      expect(state.text, 'keep me');
      expect(state.tags, ['culture']);
      backend.failWith = null;
      expect(await composer.submit(), isNotNull);
    });

    test(
      'text, location and tags persist as a draft and restore later',
      () async {
        final c = container();
        final composer = await readyComposer(c);
        composer
          ..setText('আজ জাফলং')
          ..setLocation('জাফলং')
          ..addTag('nature');
        await pump();
        c.dispose();

        // A fresh composer (new app session) restores the draft for the same user.
        final c2 = ProviderContainer(
          overrides: [
            tokenStorageProvider.overrideWithValue(storage),
            draftStoreProvider.overrideWithValue(drafts),
            apiClientProvider.overrideWithValue(backend),
          ],
        );
        addTearDown(c2.dispose);
        backend.currentToken = () => storage.current;
        c2.read(authControllerProvider);
        await pump();
        c2.listen(composerControllerProvider, (_, _) {});
        await pump();
        final restored = c2.read(composerControllerProvider);
        expect(restored.text, 'আজ জাফলং');
        expect(restored.location, 'জাফলং');
        expect(restored.tags, ['nature']);
        expect(restored.restored, isTrue);
      },
    );

    test('tags: duplicates, invalid and over-limit are rejected', () async {
      final c = container();
      final composer = await readyComposer(c);
      expect(composer.addTag('food'), isTrue);
      expect(composer.addTag('FOOD'), isFalse);
      expect(composer.addTag('no spaces'), isFalse);
      for (var i = 0; i < 10; i++) {
        composer.addTag('tag$i');
      }
      expect(c.read(composerControllerProvider).tags, hasLength(maxTags));
      composer.toggleTag('food');
      expect(c.read(composerControllerProvider).tags, isNot(contains('food')));
    });

    test('created post is prepended to the feed', () async {
      backend.feed.add(postJson('old', body: 'older'));
      final c = container();
      c.listen(feedControllerProvider, (_, _) {});
      await pump();
      final composer = await readyComposer(c);
      composer.setText('brand new');
      await composer.submit();
      expect(c.read(feedControllerProvider).posts.first.body, 'brand new');
      expect(c.read(feedControllerProvider).posts, hasLength(2));
    });
  });

  group('HttpApiClient.upload', () {
    const config = AppConfig(
      environment: AppEnvironment.development,
      apiBaseUrl: 'http://api.test',
    );

    test('sends multipart with auth header and reports progress', () async {
      http.BaseRequest? seen;
      final client = HttpApiClient(
        config: config,
        tokenProvider: () => 'tok',
        client: MockClient.streaming((request, bodyStream) async {
          seen = request;
          await bodyStream.drain<void>();
          return http.StreamedResponse(
            Stream.value(utf8.encode('{"id":"x"}')),
            201,
          );
        }),
      );
      final progress = <double>[];
      final json = await client.upload(
        '/media',
        bytes: List.filled(5000, 1),
        filename: 'a.png',
        contentType: 'image/png',
        onProgress: progress.add,
      );
      expect(json, {'id': 'x'});
      expect(seen!.url.toString(), 'http://api.test/api/v1/media');
      expect(seen!.headers['Authorization'], 'Bearer tok');
      expect(seen!.headers['content-type'], startsWith('multipart/form-data'));
      expect(progress, isNotEmpty);
      expect(progress.last, closeTo(1.0, 1e-9));
      expect(progress, orderedEquals([...progress]..sort())); // monotonic
    });

    test('maps 413/415/429 and network failures', () async {
      Future<Object> errorFor(http.StreamedResponse Function() make) async {
        final client = HttpApiClient(
          config: config,
          client: MockClient.streaming((r, b) async {
            await b.drain<void>();
            return make();
          }),
        );
        try {
          await client.upload(
            '/media',
            bytes: [1],
            filename: 'a.png',
            contentType: 'image/png',
          );
        } catch (e) {
          return e;
        }
        fail('no error');
      }

      http.StreamedResponse res(int code, String body) =>
          http.StreamedResponse(Stream.value(utf8.encode(body)), code);
      expect(
        await errorFor(() => res(413, '{"detail":"too big"}')),
        isA<ValidationException>(),
      );
      expect(
        await errorFor(() => res(415, '{"detail":"nope"}')),
        isA<ValidationException>(),
      );
      expect(await errorFor(() => res(429, '{}')), isA<RateLimitedException>());
      expect(
        await errorFor(() => res(401, '{}')),
        isA<UnauthorizedException>(),
      );

      final offline = HttpApiClient(
        config: config,
        client: MockClient.streaming(
          (r, b) async => throw http.ClientException('down'),
        ),
      );
      expect(
        offline.upload(
          '/media',
          bytes: [1],
          filename: 'a.png',
          contentType: 'image/png',
        ),
        throwsA(isA<NetworkException>()),
      );
    });
  });

  test('contentTypeFor falls back to the extension', () {
    expect(contentTypeFor('x.PNG'), 'image/png');
    expect(contentTypeFor('x.webp'), 'image/webp');
    expect(contentTypeFor('x.jpg'), 'image/jpeg');
    expect(contentTypeFor('x.bin', 'image/png'), 'image/png');
  });

  group('Composer screen', () {
    late FakeImagePicker pickerForUi;
    late InMemoryDraftStore draftsForUi;

    Future<void> boot(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      pickerForUi = FakeImagePicker();
      draftsForUi = InMemoryDraftStore();
      backend.seedUser('rahim_bd', 'pw-12345678');
      storage = InMemoryTokenStorage(backend.issueToken('rahim_bd'));
      await tester.pumpWidget(
        buildTestApp(
          backend,
          storage,
          picker: pickerForUi,
          drafts: draftsForUi,
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();
      await tester.tap(find.text('CREATE'));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'share is disabled until there is content; posting returns to the feed',
      (tester) async {
        await boot(tester);
        final share = find.widgetWithText(FilledButton, 'Share');
        expect(tester.widget<FilledButton>(share).onPressed, isNull);
        expect(find.text('What are you discovering?'), findsOneWidget);

        await tester.enterText(
          find.byType(TextField).first,
          'আজ জাফলংয়ে গিয়েছিলাম',
        );
        await tester.pump();
        expect(tester.widget<FilledButton>(share).onPressed, isNotNull);

        await tester.tap(find.widgetWithText(FilterChip, 'nature'));
        await tester.pump();
        await tester.tap(share);
        await tester.pumpAndSettle();

        expect(backend.created.single['body'], 'আজ জাফলংয়ে গিয়েছিলাম');
        expect(backend.created.single['tags'], ['nature']);
        expect(
          find.text('আজ জাফলংয়ে গিয়েছিলাম'),
          findsOneWidget,
        ); // now in the feed
        expect(find.text('#nature'), findsOneWidget);
      },
    );

    testWidgets(
      'picking photos shows thumbnails that upload, then share works',
      (tester) async {
        await boot(tester);
        pickerForUi.next = [fakeImage('a.png'), fakeImage('b.png')];
        await tester.tap(find.text('Add photos'));
        await tester.pump();
        expect(
          find.byType(CircularProgressIndicator),
          findsWidgets,
        ); // uploading
        await tester.pumpAndSettle();
        expect(find.byTooltip('Remove photo'), findsNWidgets(2));
        await tester.tap(find.widgetWithText(FilledButton, 'Share'));
        await tester.pumpAndSettle();
        expect((backend.created.single['media'] as List), hasLength(2));
      },
    );

    testWidgets('failed upload shows retry and blocks sharing', (tester) async {
      await boot(tester);
      var fail = true;
      backend.uploadFailure = (_) => fail ? const NetworkException() : null;
      pickerForUi.next = [fakeImage('a.png')];
      await tester.tap(find.text('Add photos'));
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
      expect(find.textContaining('Some photos failed'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Share'))
            .onPressed,
        isNull,
      );
      fail = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Share'))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('draft text survives leaving and returning to the tab', (
      tester,
    ) async {
      await boot(tester);
      await tester.enterText(
        find.byType(TextField).first,
        'half-written thought',
      );
      await tester.tap(find.text('HOME'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CREATE'));
      await tester.pumpAndSettle();
      expect(find.text('half-written thought'), findsOneWidget);
    });
  });

  group('Delete post', () {
    Future<void> bootFeed(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      backend.seedUser('rahim_bd', 'pw-12345678');
      final me = backend.users['rahim_bd']!['id'] as String;
      backend.feed
        ..add(
          postJson(
            'mine',
            body: 'my own post',
            authorId: me,
            username: 'rahim_bd',
            displayName: 'Rahim',
          ),
        )
        ..add(
          postJson(
            'theirs',
            body: 'their post',
            authorId: 'x',
            username: 'other',
            displayName: 'Other',
          ),
        );
      storage = InMemoryTokenStorage(backend.issueToken('rahim_bd'));
      await tester.pumpWidget(buildTestApp(backend, storage));
      await tester.pump();
      await tester.pumpAndSettle();
    }

    testWidgets('only own posts offer delete; confirming removes the post', (
      tester,
    ) async {
      await bootFeed(tester);
      expect(find.byTooltip('Post options'), findsOneWidget);
      await tester.tap(find.byTooltip('Post options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete post'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this post?'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('my own post'), findsNothing);
      expect(find.text('their post'), findsOneWidget);
      expect(backend.calls, contains('DELETE /posts/mine'));
    });

    testWidgets('cancel keeps the post; a server error keeps it and says why', (
      tester,
    ) async {
      await bootFeed(tester);
      await tester.tap(find.byTooltip('Post options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete post'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('my own post'), findsOneWidget);

      await tester.tap(find.byTooltip('Post options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete post'));
      await tester.pumpAndSettle();
      backend.failWith = const ServerException();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('my own post'), findsOneWidget);
      expect(find.textContaining('went wrong'), findsOneWidget);
    });
  });
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
