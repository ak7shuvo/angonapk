import 'place.dart';
import 'post.dart';

enum StoryStatus { draft, published }

/// An image attached to a story (cover or inline), with a resolved absolute URL.
class StoryImage {
  const StoryImage({
    required this.id,
    required this.url,
    this.width,
    this.height,
  });

  final String id;
  final String url;
  final int? width;
  final int? height;

  double? get aspectRatio => (width != null && height != null && height! > 0)
      ? width! / height!
      : null;

  factory StoryImage.fromJson(
    Map<String, dynamic> json, {
    String mediaBaseUrl = '',
  }) {
    final raw = json['url'] as String;
    return StoryImage(
      id: json['id'] as String,
      url: raw.startsWith('/') ? '$mediaBaseUrl$raw' : raw,
      width: json['width'] as int?,
      height: json['height'] as int?,
    );
  }
}

/// Story as shown in lists (no body).
class StorySummary {
  const StorySummary({
    required this.id,
    required this.slug,
    required this.title,
    required this.summary,
    required this.author,
    required this.status,
    required this.updatedAt,
    required this.readingMinutes,
    this.cover,
    this.locationText,
    this.tags = const [],
    this.publishedAt,
    this.likeCount = 0,
    this.likedByMe = false,
    this.savedByMe = false,
    this.followingAuthor = false,
    this.place,
  });

  final String id;
  final String slug;
  final String title;
  final String summary;
  final StoryImage? cover;
  final String? locationText;
  final List<String> tags;
  final StoryStatus status;
  final DateTime? publishedAt;
  final DateTime updatedAt;
  final int readingMinutes;
  final PostAuthor author;
  final int likeCount;
  final bool likedByMe;
  final bool savedByMe;
  final bool followingAuthor;
  final PlaceBrief? place;

  bool get isDraft => status == StoryStatus.draft;
  String get displayTitle => title.trim().isEmpty ? 'Untitled story' : title;

  factory StorySummary.fromJson(
    Map<String, dynamic> json, {
    String mediaBaseUrl = '',
  }) => StorySummary(
    id: json['id'] as String,
    slug: json['slug'] as String,
    title: json['title'] as String,
    summary: json['summary'] as String? ?? '',
    cover: json['cover'] == null
        ? null
        : StoryImage.fromJson(
            json['cover'] as Map<String, dynamic>,
            mediaBaseUrl: mediaBaseUrl,
          ),
    locationText: json['location_text'] as String?,
    tags: [for (final t in (json['tags'] as List? ?? const [])) t as String],
    status: json['status'] == 'published'
        ? StoryStatus.published
        : StoryStatus.draft,
    publishedAt: json['published_at'] == null
        ? null
        : DateTime.parse(json['published_at'] as String).toLocal(),
    updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
    readingMinutes: json['reading_minutes'] as int? ?? 1,
    author: PostAuthor.fromJson(json['author'] as Map<String, dynamic>),
    likeCount: json['like_count'] as int? ?? 0,
    likedByMe: json['liked_by_me'] as bool? ?? false,
    savedByMe: json['saved_by_me'] as bool? ?? false,
    followingAuthor: json['following_author'] as bool? ?? false,
    place: json['place'] == null
        ? null
        : PlaceBrief.fromJson(json['place'] as Map<String, dynamic>),
  );
}

/// Full story with body and the images referenced inside it.
class Story extends StorySummary {
  const Story({
    required super.id,
    required super.slug,
    required super.title,
    required super.summary,
    required super.author,
    required super.status,
    required super.updatedAt,
    required super.readingMinutes,
    required this.content,
    this.media = const [],
    super.cover,
    super.locationText,
    super.tags,
    super.publishedAt,
    super.likeCount,
    super.likedByMe,
    super.savedByMe,
    super.followingAuthor,
    super.place,
  });

  final String content;
  final List<StoryImage> media;

  factory Story.fromJson(
    Map<String, dynamic> json, {
    String mediaBaseUrl = '',
  }) {
    final s = StorySummary.fromJson(json, mediaBaseUrl: mediaBaseUrl);
    return Story(
      id: s.id,
      slug: s.slug,
      title: s.title,
      summary: s.summary,
      author: s.author,
      status: s.status,
      updatedAt: s.updatedAt,
      readingMinutes: s.readingMinutes,
      cover: s.cover,
      locationText: s.locationText,
      tags: s.tags,
      publishedAt: s.publishedAt,
      likeCount: s.likeCount,
      likedByMe: s.likedByMe,
      savedByMe: s.savedByMe,
      followingAuthor: s.followingAuthor,
      place: s.place,
      content: json['content'] as String,
      media: [
        for (final m in json['media'] as List)
          StoryImage.fromJson(
            m as Map<String, dynamic>,
            mediaBaseUrl: mediaBaseUrl,
          ),
      ],
    );
  }
}

class StoryPage {
  const StoryPage({required this.items, this.nextCursor});
  final List<StorySummary> items;
  final String? nextCursor;

  factory StoryPage.fromJson(
    Map<String, dynamic> json, {
    String mediaBaseUrl = '',
  }) => StoryPage(
    items: [
      for (final s in json['items'] as List)
        StorySummary.fromJson(
          s as Map<String, dynamic>,
          mediaBaseUrl: mediaBaseUrl,
        ),
    ],
    nextCursor: json['next_cursor'] as String?,
  );
}
