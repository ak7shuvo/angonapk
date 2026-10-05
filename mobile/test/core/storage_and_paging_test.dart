import 'package:angon/core/utils/media_url.dart';
import 'package:angon/services/draft_store.dart';
import 'package:angon/services/token_storage.dart';
import 'package:angon/shared/paged/paged_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TestItems extends PagedController<String> {
  TestItems(this.pages);
  final List<Page<String>> pages;
  int calls = 0;
  Object? failNext;

  @override
  Future<Page<String>> fetch(String? cursor) async {
    calls++;
    if (failNext != null) {
      final e = failNext!;
      failNext = null;
      throw e;
    }
    return pages[cursor == null ? 0 : int.parse(cursor)];
  }

  @override
  String idOf(String item) => item;
}

late TestItems controller;
final provider = NotifierProvider.autoDispose<TestItems, PagedState<String>>(
  () => controller,
);

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  test('resolveMediaUrl joins storage paths to the API host only', () {
    expect(
      resolveMediaUrl('http://h:8000', '/media/u/a.png'),
      'http://h:8000/media/u/a.png',
    );
    expect(
      resolveMediaUrl('http://h:8000', 'https://cdn.example/a.png'),
      'https://cdn.example/a.png',
    );
  });

  group('SecureTokenStorage', () {
    test('round-trips and clears the token', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final storage = SecureTokenStorage();
      expect(await storage.read(), isNull);
      await storage.write('abc');
      expect(await storage.read(), 'abc');
      await storage.clear();
      expect(await storage.read(), isNull);
    });
  });

  group('PrefsDraftStore', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('saves, loads and clears per user', () async {
      final store = PrefsDraftStore();
      expect(await store.load('u1'), isNull);
      await store.save(
        'u1',
        const PostDraft(
          text: 'সুন্দর',
          tags: ['nature'],
          placeId: 'p',
          placeName: 'Jaflong',
        ),
      );
      final back = (await store.load('u1'))!;
      expect(back.text, 'সুন্দর');
      expect(back.tags, ['nature']);
      expect(back.placeName, 'Jaflong');
      expect(await store.load('u2'), isNull); // other accounts never see it
      await store.clear('u1');
      expect(await store.load('u1'), isNull);
    });

    test(
      'an empty draft is cleared instead of stored; junk is ignored',
      () async {
        final store = PrefsDraftStore();
        await store.save('u1', const PostDraft(text: 'x'));
        await store.save('u1', const PostDraft());
        expect(await store.load('u1'), isNull);
        SharedPreferences.setMockInitialValues({
          'angon_post_draft_u1': '{not json',
        });
        expect(await PrefsDraftStore().load('u1'), isNull);
      },
    );
  });

  group('PagedController', () {
    ProviderContainer make(List<Page<String>> pages) {
      controller = TestItems(pages);
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.listen(provider, (_, _) {});
      return c;
    }

    test('loads, pages without duplicates, and ends', () async {
      final c = make([
        (items: ['a', 'b'], nextCursor: '1'),
        (items: ['b', 'c'], nextCursor: null),
      ]);
      await settle();
      expect(c.read(provider).items, ['a', 'b']);
      expect(c.read(provider).hasMore, isTrue);
      await c.read(provider.notifier).loadMore();
      expect(c.read(provider).items, ['a', 'b', 'c']); // 'b' not repeated
      expect(c.read(provider).hasMore, isFalse);
      await c.read(provider.notifier).loadMore(); // nothing more: no extra call
      expect(controller.calls, 2);
    });

    test('a failed first load errors, retry recovers', () async {
      controller = TestItems([
        (items: ['a'], nextCursor: null),
      ])..failNext = StateError('x');
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.listen(provider, (_, _) {});
      await settle();
      expect(c.read(provider).status, PagedStatus.error);
      await c.read(provider.notifier).retry();
      expect(c.read(provider).items, ['a']);
    });

    test('load-more failure keeps items and records the error', () async {
      final c = make([
        (items: ['a'], nextCursor: '1'),
        (items: ['b'], nextCursor: null),
      ]);
      await settle();
      controller.failNext = StateError('offline');
      await c.read(provider.notifier).loadMore();
      expect(c.read(provider).items, ['a']);
      expect(c.read(provider).loadMoreError, isNotNull);
      await c.read(provider.notifier).loadMore(); // retry works
      expect(c.read(provider).items, ['a', 'b']);
    });

    test('refresh failure keeps showing what you had', () async {
      final c = make([
        (items: ['a', 'b'], nextCursor: null),
      ]);
      await settle();
      controller.failNext = StateError('offline');
      await c.read(provider.notifier).refresh();
      expect(c.read(provider).items, ['a', 'b']);
      expect(c.read(provider).refreshError, isNotNull);
    });

    test(
      'removeWhere, replaceItem and prepend edit the list locally',
      () async {
        final c = make([
          (items: ['a', 'b', 'c'], nextCursor: null),
        ]);
        await settle();
        final n = c.read(provider.notifier);
        n.removeWhere((i) => i == 'b');
        expect(c.read(provider).items, ['a', 'c']);
        n.replaceItem('c');
        n.prepend('z');
        n.prepend(
          'a',
        ); // moves an existing id to the top instead of duplicating
        expect(c.read(provider).items, ['a', 'z', 'c']);
      },
    );
  });
}
