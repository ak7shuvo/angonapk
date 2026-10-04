// Real client ↔ real API: likes, saves, comments, follows, following feed.
//   flutter test test/e2e --dart-define=E2E_API_BASE_URL=http://127.0.0.1:8000
import 'package:angon/config/app_config.dart';
import 'package:angon/core/errors/app_exception.dart';
import 'package:angon/features/auth/auth_controller.dart';
import 'package:angon/features/social/engagement_controller.dart';
import 'package:angon/features/social/follow_controller.dart';
import 'package:angon/services/providers.dart';
import 'package:angon/services/token_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _baseUrl = String.fromEnvironment('E2E_API_BASE_URL');

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

  test('social interactions against the real API', () async {
    final stamp = DateTime.now().microsecondsSinceEpoch.toString();
    final aName = 'sa_$stamp'.substring(0, 18);
    final bName = 'sb_$stamp'.substring(0, 18);
    final a = await _signedIn(aName);
    final b = await _signedIn(bName);
    final aPosts = a.read(postRepositoryProvider);
    final bPosts = b.read(postRepositoryProvider);

    final post = await bPosts.createPost(body: 'by B', tags: ['culture']);

    // Like: optimistic controller, server truth, idempotent, viewer-relative.
    final engagement = a.read(engagementProvider.notifier);
    await engagement.toggleLike(post);
    expect(a.read(engagementProvider)[post.id]!.liked, isTrue);
    expect(a.read(engagementProvider)[post.id]!.likeCount, 1);
    expect((await bPosts.getPost(post.id)).likeCount, 1);
    expect(
      (await bPosts.getPost(post.id)).likedByMe,
      isFalse,
    ); // B has not liked it
    expect((await aPosts.getPost(post.id)).likedByMe, isTrue);
    await engagement.toggleLike(post);
    expect((await aPosts.getPost(post.id)).likeCount, 0);

    // Save / saved list.
    await engagement.toggleSave(post);
    final saved = await aPosts.savedPosts();
    expect(saved.items.map((p) => p.id), contains(post.id));
    expect(saved.items.first.savedByMe, isTrue);
    await engagement.toggleSave(post);
    expect((await aPosts.savedPosts()).items, isEmpty);

    // Comments: add (Bengali), list, permissions, delete.
    final comment = await aPosts.addComment(post.id, 'সুন্দর ছবি!');
    expect(comment.isMine, isTrue);
    final listed = await bPosts.comments(post.id);
    expect(listed.items.single.body, 'সুন্দর ছবি!');
    expect(listed.items.single.isMine, isFalse);
    await expectLater(
      bPosts.deleteComment(comment.id),
      throwsA(isA<ForbiddenException>()),
    );
    await aPosts.deleteComment(comment.id);
    expect((await bPosts.comments(post.id)).items, isEmpty);

    // Follow graph + the Following feed.
    expect((await aPosts.fetchFeed(scope: 'following')).items, isEmpty);
    await a
        .read(followProvider.notifier)
        .toggle(bName, currentlyFollowing: false);
    expect(a.read(followProvider)[bName]!.followersCount, 1);
    final followers = await a.read(userRepositoryProvider).followers(bName);
    expect(followers.items.single.username, aName);
    expect(followers.items.single.isMe, isTrue);
    final following = await a.read(userRepositoryProvider).following(aName);
    expect(following.items.single.username, bName);
    expect(
      (await aPosts.fetchFeed(scope: 'following')).items.single.id,
      post.id,
    );
    expect((await aPosts.getPost(post.id)).followingAuthor, isTrue);
    await expectLater(
      a.read(userRepositoryProvider).follow(aName),
      throwsA(isA<ValidationException>()),
    );
    await a
        .read(followProvider.notifier)
        .toggle(bName, currentlyFollowing: true);
    expect((await aPosts.fetchFeed(scope: 'following')).items, isEmpty);

    await bPosts.deletePost(post.id);
  }, skip: skip);
}
