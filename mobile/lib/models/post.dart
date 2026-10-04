enum MediaType { image, video }

class PostMedia {
  const PostMedia({
    required this.id,
    required this.type,
    required this.url,
    this.width,
    this.height,
    this.altText,
  });

  final String id;
  final MediaType type;

  /// Absolute, already resolved against the API host when needed.
  final String url;
  final int? width;
  final int? height;
  final String? altText;

  /// width / height when both are known.
  double? get aspectRatio => (width != null && height != null && height! > 0)
      ? width! / height!
      : null;

  factory PostMedia.fromJson(
    Map<String, dynamic> json, {
    String mediaBaseUrl = '',
  }) {
    final raw = json['url'] as String;
    return PostMedia(
      id: json['id'] as String,
      type: json['type'] == 'video' ? MediaType.video : MediaType.image,
      // Storage-relative paths (e.g. "/media/x.png") live on the API host.
      url: raw.startsWith('/') ? '$mediaBaseUrl$raw' : raw,
      width: json['width'] as int?,
      height: json['height'] as int?,
      altText: json['alt_text'] as String?,
    );
  }
}

class PostAuthor {
  const PostAuthor({
    required this.id,
    required this.username,
    this.displayName,
  });

  final String id;
  final String username;
  final String? displayName;

  String get name => (displayName != null && displayName!.trim().isNotEmpty)
      ? displayName!
      : username;

  factory PostAuthor.fromJson(Map<String, dynamic> json) => PostAuthor(
    id: json['id'] as String,
    username: json['username'] as String,
    displayName: json['display_name'] as String?,
  );
}

class Post {
  const Post({
    required this.id,
    required this.author,
    required this.createdAt,
    this.body,
    this.locationText,
    this.media = const [],
    this.tags = const [],
    this.likeCount = 0,
    this.commentCount = 0,
    this.likedByMe = false,
    this.savedByMe = false,
    this.followingAuthor = false,
  });

  final String id;
  final PostAuthor author;
  final String? body;
  final String? locationText;
  final List<PostMedia> media;
  final List<String> tags;
  final DateTime createdAt;

  /// Server-provided engagement as of when the post was loaded. Live (optimistic)
  /// state is layered on top by `EngagementController`.
  final int likeCount;
  final int commentCount;
  final bool likedByMe;
  final bool savedByMe;
  final bool followingAuthor;

  bool get hasMedia => media.isNotEmpty;
  bool get hasText => body != null && body!.trim().isNotEmpty;

  factory Post.fromJson(
    Map<String, dynamic> json, {
    String mediaBaseUrl = '',
  }) => Post(
    id: json['id'] as String,
    author: PostAuthor.fromJson(json['author'] as Map<String, dynamic>),
    body: json['body'] as String?,
    locationText: json['location_text'] as String?,
    media: [
      for (final m in json['media'] as List)
        PostMedia.fromJson(
          m as Map<String, dynamic>,
          mediaBaseUrl: mediaBaseUrl,
        ),
    ],
    tags: [for (final t in (json['tags'] as List? ?? const [])) t as String],
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    likeCount: json['like_count'] as int? ?? 0,
    commentCount: json['comment_count'] as int? ?? 0,
    likedByMe: json['liked_by_me'] as bool? ?? false,
    savedByMe: json['saved_by_me'] as bool? ?? false,
    followingAuthor: json['following_author'] as bool? ?? false,
  );
}

/// One page of the feed. [nextCursor] is null on the last page.
class FeedPage {
  const FeedPage({required this.items, this.nextCursor});

  final List<Post> items;
  final String? nextCursor;

  factory FeedPage.fromJson(
    Map<String, dynamic> json, {
    String mediaBaseUrl = '',
  }) => FeedPage(
    items: [
      for (final p in json['items'] as List)
        Post.fromJson(p as Map<String, dynamic>, mediaBaseUrl: mediaBaseUrl),
    ],
    nextCursor: json['next_cursor'] as String?,
  );
}
