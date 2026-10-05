import 'package:angon/core/errors/app_exception.dart';
import 'package:angon/features/auth/auth_controller.dart';
import 'package:angon/features/profile/edit_profile_controller.dart';
import 'package:angon/features/profile/profile_view.dart';
import 'package:angon/models/public_profile.dart';
import 'package:angon/models/user.dart';
import 'package:angon/routing/app_router.dart';
import 'package:angon/services/providers.dart';
import 'package:angon/services/token_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_backend.dart';
import '../support/fake_picker.dart';
import '../support/harness.dart';

late FakeBackend backend;
late FakeImagePicker picker;

Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 30));

ProviderContainer container({CreatorType type = CreatorType.traveler}) {
  backend.seedUser('rahim_bd', 'pw-12345678');
  (backend.users['rahim_bd']!['profile'] as Map)['creator_type'] =
      type.apiValue;
  final storage = InMemoryTokenStorage(backend.issueToken('rahim_bd'));
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

  test('PublicProfile parses counts, flags and Bengali text', () {
    final p = PublicProfile.fromJson({
      'id': '1',
      'username': 'nusrat',
      'display_name': 'নুসরাত',
      'bio': 'গল্প বলি',
      'location': 'ঢাকা',
      'creator_type': 'storyteller',
      'avatar_url': '/media/u/a.png',
      'cover_url': null,
      'joined_at': '2026-01-01T00:00:00+00:00',
      'counts': {
        'posts': 3,
        'stories': 2,
        'followers': 10,
        'following': 4,
        'places': 1,
      },
      'is_following': true,
      'is_me': false,
    });
    expect(p.name, 'নুসরাত');
    expect(p.creatorType, CreatorType.storyteller);
    expect((p.counts.posts, p.counts.followers, p.counts.places), (3, 10, 1));
    expect(p.isFollowing, isTrue);
  });

  test('creator type decides which sections lead the profile', () {
    expect(
      tabsFor(CreatorType.photographer, isMe: false).first,
      ProfileTab.photos,
    );
    expect(
      tabsFor(CreatorType.videographer, isMe: false).first,
      ProfileTab.photos,
    );
    for (final t in [
      CreatorType.storyteller,
      CreatorType.blogger,
      CreatorType.researcher,
    ]) {
      expect(tabsFor(t, isMe: false).first, ProfileTab.stories);
    }
    expect(tabsFor(CreatorType.traveler, isMe: false).first, ProfileTab.posts);
    expect(tabsFor(null, isMe: false).first, ProfileTab.posts);
    // Everyone gets every public section (incl. Places); only you get Saved.
    expect(tabsFor(CreatorType.guide, isMe: false), hasLength(4));
    expect(
      tabsFor(CreatorType.guide, isMe: false),
      contains(ProfileTab.places),
    );
    expect(tabsFor(CreatorType.guide, isMe: true).last, ProfileTab.saved);
  });

  group('EditProfileController', () {
    test('starts from the signed-in profile; dirty/canSave rules', () async {
      final c = container();
      await pump();
      final e = c.read(editProfileProvider.notifier);
      c.listen(editProfileProvider, (_, _) {});
      var s = c.read(editProfileProvider);
      expect(s.creatorType, CreatorType.traveler);
      expect(s.canSave, isFalse); // not dirty
      e.setName('');
      expect(c.read(editProfileProvider).canSave, isFalse); // name required
      e.setName('রহিম');
      expect(c.read(editProfileProvider).canSave, isTrue);
      s = c.read(editProfileProvider);
      expect(s.displayName, 'রহিম');
    });

    test(
      'avatar upload uses the avatar purpose; only changed images are sent',
      () async {
        final c = container();
        await pump();
        c.listen(editProfileProvider, (_, _) {});
        final e = c.read(editProfileProvider.notifier);
        e.setName('Rahim');
        picker.next = [fakeImage('me.png')];
        await e.pickAvatar();
        expect(backend.calls, contains('UPLOAD /media?purpose=avatar'));
        expect(c.read(editProfileProvider).avatar!.id, 'asset-0');
        expect(await e.save(), isTrue);
        expect(backend.lastProfilePatch!['avatar_media_id'], 'asset-0');
        expect(
          backend.lastProfilePatch!.containsKey('cover_media_id'),
          isFalse,
        );
        final auth = c.read(authControllerProvider) as Authenticated;
        expect(auth.user.profile.avatarUrl, '/media/u/asset-0.png');
        expect(auth.user.profile.displayName, 'Rahim');

        // Removing sends an explicit null.
        e.setBio('changed');
        e.removeAvatar();
        expect(await e.save(), isTrue);
        expect(backend.lastProfilePatch!['avatar_media_id'], isNull);
        expect(
          backend.lastProfilePatch!.containsKey('avatar_media_id'),
          isTrue,
        );
        expect(
          (c.read(
            authControllerProvider,
          ) as Authenticated).user.profile.avatarUrl,
          isNull,
        );
      },
    );

    test(
      'invalid image is rejected locally; failed save keeps edits',
      () async {
        final c = container();
        await pump();
        c.listen(editProfileProvider, (_, _) {});
        final e = c.read(editProfileProvider.notifier);
        picker.next = [fakeImage('x.gif', type: 'image/gif')];
        await e.pickAvatar();
        expect(
          c.read(editProfileProvider).notice,
          contains('JPEG, PNG and WebP'),
        );
        expect(backend.calls.where((x) => x.startsWith('UPLOAD')), isEmpty);

        e.setName('Name');
        backend.failWith = const ServerException();
        expect(await e.save(), isFalse);
        expect(c.read(editProfileProvider).error, isNotNull);
        expect(c.read(editProfileProvider).displayName, 'Name');
        expect(c.read(editProfileProvider).dirty, isTrue);
      },
    );
  });

  group('Profile UI', () {
    Future<void> boot(
      WidgetTester tester, {
      CreatorType type = CreatorType.traveler,
    }) async {
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      if (!backend.users.containsKey('rahim_bd')) {
        backend.seedUser('rahim_bd', 'pw-12345678');
      }
      final me = backend.users['rahim_bd']!['profile'] as Map;
      me['creator_type'] = type.apiValue;
      me['bio'] = 'Chasing haors.';
      me['location'] = 'Sylhet';
      final storage = InMemoryTokenStorage(backend.issueToken('rahim_bd'));
      await tester.pumpWidget(buildTestApp(backend, storage, picker: picker));
      await tester.pump();
      await tester.pumpAndSettle();
    }

    String myId() => backend.users['rahim_bd']!['id'] as String;

    testWidgets('own profile shows identity, stats, and my posts', (
      tester,
    ) async {
      backend.seedUser('rahim_bd', 'pw-12345678');
      backend.feed.add(
        postJson(
          'mine',
          body: 'My haor post',
          authorId: myId(),
          username: 'rahim_bd',
          displayName: 'Name rahim_bd',
        ),
      );
      await boot(tester);
      await tester.tap(find.text('PROFILE'));
      await tester.pumpAndSettle();
      expect(find.text('Name rahim_bd'), findsWidgets);
      expect(find.text('@rahim_bd'), findsWidgets);
      expect(find.text('TRAVELLER'), findsOneWidget);
      expect(find.text('Sylhet'), findsOneWidget);
      expect(find.text('Chasing haors.'), findsOneWidget);
      expect(find.text('Edit profile'), findsWidgets);
      expect(find.widgetWithText(FilledButton, 'Follow'), findsNothing);
      expect(find.text('My haor post'), findsOneWidget);
      expect(find.text('Saved'), findsOneWidget); // only on your own profile
    });

    testWidgets(
      'photographers see Photos first as a grid; storytellers see Stories first',
      (tester) async {
        backend.seedUser('rahim_bd', 'pw-12345678');
        backend.feed.add(
          postJson(
            'ph',
            body: 'cap',
            authorId: myId(),
            username: 'rahim_bd',
            media: [
              {
                'id': 'm',
                'type': 'image',
                'url': 'http://127.0.0.1:1/a.png',
                'width': 100,
                'height': 100,
                'alt_text': null,
              },
            ],
          ),
        );
        await boot(tester, type: CreatorType.photographer);
        await tester.tap(find.text('PROFILE'));
        await tester.pumpAndSettle();
        expect(find.byType(SliverGrid), findsOneWidget);
        expect(find.text('PHOTOGRAPHER'), findsOneWidget);
      },
    );

    testWidgets('storyteller profile leads with their stories', (tester) async {
      backend.seedUser('rahim_bd', 'pw-12345678');
      backend.stories.add(
        storyJson(
          's1',
          username: 'rahim_bd',
          authorId: myId(),
          title: 'জাফলংয়ের গল্প',
        ),
      );
      await boot(tester, type: CreatorType.storyteller);
      await tester.tap(find.text('PROFILE'));
      await tester.pumpAndSettle();
      expect(find.text('জাফলংয়ের গল্প'), findsOneWidget);
      expect(find.text('STORYTELLER'), findsOneWidget);
    });

    testWidgets(
      "another user's profile: follow updates the count; lists open",
      (tester) async {
        backend.seedUser('rahim_bd', 'pw-12345678');
        backend.seedUser('nusrat', 'pw-12345678');
        final nusrat = backend.users['nusrat']!;
        (nusrat['profile'] as Map)['bio'] = 'গল্প বলি';
        backend.feed.add(
          postJson(
            'np',
            body: 'Nusrat writes',
            authorId: nusrat['id'] as String,
            username: 'nusrat',
            displayName: 'Nusrat',
          ),
        );
        await boot(tester);
        // Tap the author in the feed.
        await tester.tap(find.text('Nusrat').first);
        await tester.pumpAndSettle();
        expect(find.text('গল্প বলি'), findsOneWidget);
        expect(find.text('0'), findsWidgets);
        await tester.tap(find.widgetWithText(FilledButton, 'Follow').last);
        await tester.pumpAndSettle();
        expect(backend.follows['rahim_bd'], {'nusrat'});
        expect(
          find.widgetWithText(OutlinedButton, 'Following'),
          findsOneWidget,
        );
        // Followers count is now 1 and opens the list.
        await tester.tap(find.text('Followers'));
        await tester.pumpAndSettle();
        expect(find.text('@rahim_bd'), findsOneWidget);
        expect(find.text('Followers'), findsWidgets);
      },
    );

    testWidgets('unknown profile shows an error with retry', (tester) async {
      await boot(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(Scaffold).first),
      );
      container.read(routerProvider).push('/u/ghost');
      await tester.pumpAndSettle();
      expect(find.text('We could not find that.'), findsNothing);
      expect(find.text('User not found'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('saved tab lists saved posts and stories', (tester) async {
      backend.seedUser('rahim_bd', 'pw-12345678');
      backend.feed.add(
        postJson('sp', body: 'A saved post', authorId: 'x', username: 'other'),
      );
      backend.saves['sp'] = ['rahim_bd'];
      backend.stories.add(storyJson('ss', title: 'A saved story'));
      backend.storySaves['ss'] = ['rahim_bd'];
      await boot(tester);
      await tester.tap(find.text('PROFILE'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Saved'));
      await tester.pumpAndSettle();
      expect(find.text('A saved post'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Stories'));
      await tester.pumpAndSettle();
      expect(find.text('A saved story'), findsOneWidget);
    });

    testWidgets('edit profile: change name and save, profile reflects it', (
      tester,
    ) async {
      await boot(tester);
      await tester.tap(find.text('PROFILE'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit profile'));
      await tester.pumpAndSettle();
      expect(find.text('Edit profile'), findsWidgets);
      final save = find.widgetWithText(FilledButton, 'Save');
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await tester.enterText(
        find.widgetWithText(TextField, 'Name'),
        'রহিম উদ্দিন',
      );
      await tester.pump();
      expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.text('রহিম উদ্দিন'), findsWidgets);
      expect(backend.lastProfilePatch!['display_name'], 'রহিম উদ্দিন');
    });

    testWidgets('edit profile asks before discarding changes', (tester) async {
      await boot(tester);
      await tester.tap(find.text('PROFILE'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit profile'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Bio'), 'new bio');
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.text('Edit profile'), findsWidgets);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('sign out lives in the account menu', (tester) async {
      await boot(tester);
      await tester.tap(find.text('PROFILE'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Account menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(find.text('Create account'), findsOneWidget);
    });
  });
}
