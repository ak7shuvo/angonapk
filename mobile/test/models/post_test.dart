import 'package:angon/core/utils/time_format.dart';
import 'package:angon/models/post.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_backend.dart';

void main() {
  group('Post model', () {
    test('parses a post with Bengali text and media', () {
      final post = Post.fromJson(
        postJson(
          'p1',
          body: 'আজ জাফলং গিয়েছিলাম',
          location: 'জাফলং, সিলেট',
          displayName: 'নুসরাত',
          media: [
            {
              'id': 'm1',
              'type': 'image',
              'url': '/media/seed/a.png',
              'width': 1200,
              'height': 900,
              'alt_text': null,
            },
            {
              'id': 'm2',
              'type': 'video',
              'url': 'https://cdn.example.com/v.mp4',
              'width': null,
              'height': null,
              'alt_text': null,
            },
          ],
          createdAt: '2026-03-05T10:00:00+00:00',
        ),
        mediaBaseUrl: 'http://api.test',
      );
      expect(post.body, 'আজ জাফলং গিয়েছিলাম');
      expect(post.locationText, 'জাফলং, সিলেট');
      expect(post.author.name, 'নুসরাত');
      expect(post.media[0].url, 'http://api.test/media/seed/a.png'); // resolved
      expect(post.media[0].aspectRatio, closeTo(4 / 3, 1e-9));
      expect(post.media[1].url, 'https://cdn.example.com/v.mp4'); // untouched
      expect(post.media[1].type, MediaType.video);
      expect(post.media[1].aspectRatio, isNull);
      expect(post.hasMedia, isTrue);
      expect(post.createdAt.toUtc(), DateTime.utc(2026, 3, 5, 10));
    });

    test('author falls back to username without a display name', () {
      final post = Post.fromJson(
        postJson('p', displayName: null, username: 'abc'),
      );
      expect(post.author.name, 'abc');
    });

    test('FeedPage parses cursor', () {
      final page = FeedPage.fromJson({
        'items': [postJson('a'), postJson('b')],
        'next_cursor': 'xyz',
      });
      expect(page.items.map((p) => p.id), ['a', 'b']);
      expect(page.nextCursor, 'xyz');
      expect(
        FeedPage.fromJson({'items': [], 'next_cursor': null}).nextCursor,
        isNull,
      );
    });
  });

  group('formatRelativeTime', () {
    final now = DateTime(2026, 6, 15, 12);
    test('relative ranges', () {
      expect(
        formatRelativeTime(now.subtract(const Duration(seconds: 20)), now: now),
        'now',
      );
      expect(
        formatRelativeTime(now.subtract(const Duration(minutes: 5)), now: now),
        '5m',
      );
      expect(
        formatRelativeTime(now.subtract(const Duration(hours: 3)), now: now),
        '3h',
      );
      expect(
        formatRelativeTime(now.subtract(const Duration(days: 2)), now: now),
        '2d',
      );
    });
    test('older posts show a date', () {
      expect(formatRelativeTime(DateTime(2026, 3, 12), now: now), '12 Mar');
      expect(formatRelativeTime(DateTime(2025, 12, 1), now: now), '1 Dec 2025');
    });
    test('future timestamps (clock skew) read as now', () {
      expect(
        formatRelativeTime(now.add(const Duration(minutes: 3)), now: now),
        'now',
      );
    });
  });
}
