// Real client ↔ real API: story lifecycle.
//   flutter test test/e2e --dart-define=E2E_API_BASE_URL=http://127.0.0.1:8000
import 'dart:convert';

import 'package:angon/config/app_config.dart';
import 'package:angon/core/errors/app_exception.dart';
import 'package:angon/features/auth/auth_controller.dart';
import 'package:angon/features/stories/story_markup.dart';
import 'package:angon/models/story.dart';
import 'package:angon/services/providers.dart';
import 'package:angon/services/token_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _baseUrl = String.fromEnvironment('E2E_API_BASE_URL');

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

Future<ProviderContainer> _signedIn(String username) async {
  final c = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(
        const AppConfig(
          environment: AppEnvironment.development,
          apiBaseUrl: _baseUrl,
        ),
      ),
      tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
    ],
  );
  addTearDown(c.dispose);
  c.read(authControllerProvider);
  for (
    var i = 0;
    i < 100 && c.read(authControllerProvider) is AuthChecking;
    i++
  ) {
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  await c
      .read(authControllerProvider.notifier)
      .register(
        email: '$username@example.com',
        username: username,
        password: 'correct-horse-1',
      );
  return c;
}

void main() {
  final skip = _baseUrl.isEmpty ? 'set E2E_API_BASE_URL to run' : null;

  test('story lifecycle against the real API', () async {
    final stamp = DateTime.now().microsecondsSinceEpoch.toString();
    final a = await _signedIn('wa_$stamp'.substring(0, 18));
    final b = await _signedIn('wb_$stamp'.substring(0, 18));
    final aStories = a.read(storyRepositoryProvider);
    final bStories = b.read(storyRepositoryProvider);
    final media = a.read(mediaRepositoryProvider);

    final cover = await media.uploadImage(
      bytes: _png,
      filename: 'c.png',
      contentType: 'image/png',
    );
    final inline = await media.uploadImage(
      bytes: _png,
      filename: 'i.png',
      contentType: 'image/png',
    );

    // Draft is private; Bengali content round-trips; inline image token works.
    final draft = await aStories.create(
      title: 'জাফলংয়ের গল্প',
      content:
          'পাহাড় আর নদী।\n\n## ভোর\n\n${imageToken(inline.id, 'নদী')}\n\n> উদ্ধৃতি',
      coverAssetId: cover.id,
      locationText: 'Jaflong, Sylhet',
      tags: ['heritage', 'ঐতিহ্য'],
    );
    expect(draft.status, StoryStatus.draft);
    expect(draft.cover!.url, cover.url);
    expect(draft.media.single.id, inline.id);
    await expectLater(
      bStories.get(draft.slug),
      throwsA(isA<NotFoundException>()),
    );
    expect((await aStories.mine(status: 'draft')).items.single.id, draft.id);

    // Publish → public, in the feed, readable by slug.
    final pub = await aStories.publish(draft.id);
    expect(pub.status, StoryStatus.published);
    final read = await bStories.get(pub.slug);
    expect(read.title, 'জাফলংয়ের গল্প');
    expect(
      parseStory(read.content).whereType<ImageBlock>().single.assetId,
      inline.id,
    );
    expect(
      (await bStories.feed(tag: 'heritage')).items.map((s) => s.id),
      contains(pub.id),
    );

    // Engagement + permissions.
    expect((await bStories.like(pub.id)).likeCount, 1);
    await bStories.save(pub.id);
    expect((await bStories.saved()).items.single.id, pub.id);
    await expectLater(
      bStories.update(pub.id, title: 'hijack'),
      throwsA(isA<ForbiddenException>()),
    );
    await expectLater(
      bStories.delete(pub.id),
      throwsA(isA<ForbiddenException>()),
    );

    // Edit, then related stories share tags.
    final edited = await aStories.update(
      pub.id,
      title: 'Edited title',
      coverAssetId: null,
    );
    expect(edited.title, 'Edited title');
    expect(edited.cover, isNull);
    final other = await bStories.create(
      title: 'Another heritage story',
      content: 'Text.',
      tags: ['heritage'],
      publish: true,
    );
    expect(
      (await aStories.related(pub.id)).map((s) => s.id),
      contains(other.id),
    );

    // Validation + cleanup.
    await expectLater(
      aStories.create(title: 'x', content: '', publish: true),
      throwsA(isA<ValidationException>()),
    );
    await aStories.delete(pub.id);
    await bStories.delete(other.id);
    await expectLater(
      bStories.get(pub.slug),
      throwsA(isA<NotFoundException>()),
    );
  }, skip: skip);
}
