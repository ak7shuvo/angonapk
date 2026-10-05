// Real client ↔ real API: profiles, avatar upload and public profile.
//   flutter test test/e2e --dart-define=E2E_API_BASE_URL=http://127.0.0.1:8000
import 'dart:convert';

import 'package:angon/config/app_config.dart';
import 'package:angon/core/errors/app_exception.dart';
import 'package:angon/features/auth/auth_controller.dart';
import 'package:angon/models/user.dart';
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

  test('profile editing and public profiles against the real API', () async {
    final stamp = DateTime.now().microsecondsSinceEpoch.toString();
    final aName = 'pa_$stamp'.substring(0, 18);
    final bName = 'pb_$stamp'.substring(0, 18);
    final a = await _signedIn(aName);
    final b = await _signedIn(bName);

    final avatar = await a
        .read(mediaRepositoryProvider)
        .uploadImage(
          bytes: _png,
          filename: 'me.png',
          contentType: 'image/png',
          purpose: 'avatar',
        );
    await a
        .read(authControllerProvider.notifier)
        .updateProfile(
          displayName: 'নুসরাত',
          bio: 'গল্প বলি',
          location: 'ঢাকা',
          creatorType: CreatorType.storyteller,
          avatarMediaId: avatar.id,
        );
    final me = (a.read(authControllerProvider) as Authenticated).user;
    expect(me.profile.avatarUrl, startsWith('/media/u/'));
    expect(me.profile.isComplete, isTrue);

    // Someone else sees the public profile with counts and relationship flags.
    await a.read(postRepositoryProvider).createPost(body: 'a post');
    await a
        .read(storyRepositoryProvider)
        .create(title: 'S', content: 'text', publish: true);
    await b.read(userRepositoryProvider).follow(aName);
    final profile = await b.read(userRepositoryProvider).profile(aName);
    expect(profile.displayName, 'নুসরাত');
    expect(profile.creatorType, CreatorType.storyteller);
    expect(profile.avatarUrl, me.profile.avatarUrl);
    expect(
      (profile.counts.posts, profile.counts.stories, profile.counts.followers),
      (1, 1, 1),
    );
    expect(profile.isFollowing, isTrue);
    expect(profile.isMe, isFalse);
    expect((await a.read(userRepositoryProvider).profile(aName)).isMe, isTrue);

    final posts = await b.read(userRepositoryProvider).posts(aName);
    expect(posts.items.single.author.avatarUrl, me.profile.avatarUrl);
    await expectLater(
      b.read(userRepositoryProvider).profile('nobody_here_x'),
      throwsA(isA<NotFoundException>()),
    );

    // Removing the avatar clears it everywhere.
    await a
        .read(authControllerProvider.notifier)
        .updateProfile(avatarMediaId: null);
    expect(
      (await b.read(userRepositoryProvider).profile(aName)).avatarUrl,
      isNull,
    );
  }, skip: skip);
}
