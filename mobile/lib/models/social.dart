import 'post.dart';

/// Live engagement for one post. The server is authoritative: values here are
/// either what the server last returned or a short-lived optimistic guess.
class Engagement {
  const Engagement({
    required this.liked,
    required this.likeCount,
    required this.saved,
    required this.commentCount,
  });

  final bool liked;
  final int likeCount;
  final bool saved;
  final int commentCount;

  factory Engagement.of(Post post) => Engagement(
    liked: post.likedByMe,
    likeCount: post.likeCount,
    saved: post.savedByMe,
    commentCount: post.commentCount,
  );

  Engagement copyWith({
    bool? liked,
    int? likeCount,
    bool? saved,
    int? commentCount,
  }) => Engagement(
    liked: liked ?? this.liked,
    likeCount: likeCount ?? this.likeCount,
    saved: saved ?? this.saved,
    commentCount: commentCount ?? this.commentCount,
  );
}

class LikeState {
  const LikeState({required this.liked, required this.likeCount});
  final bool liked;
  final int likeCount;

  factory LikeState.fromJson(Map<String, dynamic> json) => LikeState(
    liked: json['liked'] as bool,
    likeCount: json['like_count'] as int,
  );
}

class FollowState {
  const FollowState({required this.following, required this.followersCount});
  final bool following;
  final int followersCount;

  factory FollowState.fromJson(Map<String, dynamic> json) => FollowState(
    following: json['following'] as bool,
    followersCount: json['followers_count'] as int,
  );
}

class Comment {
  const Comment({
    required this.id,
    required this.postId,
    required this.body,
    required this.author,
    required this.createdAt,
    required this.isMine,
  });

  final String id;
  final String postId;
  final String body;
  final PostAuthor author;
  final DateTime createdAt;
  final bool isMine;

  factory Comment.fromJson(Map<String, dynamic> json) => Comment(
    id: json['id'] as String,
    postId: json['post_id'] as String,
    body: json['body'] as String,
    author: PostAuthor.fromJson(json['author'] as Map<String, dynamic>),
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    isMine: json['is_mine'] as bool? ?? false,
  );
}

class CommentPage {
  const CommentPage({required this.items, this.nextCursor});
  final List<Comment> items;
  final String? nextCursor;

  factory CommentPage.fromJson(Map<String, dynamic> json) => CommentPage(
    items: [
      for (final c in json['items'] as List)
        Comment.fromJson(c as Map<String, dynamic>),
    ],
    nextCursor: json['next_cursor'] as String?,
  );
}

/// Compact public user card (followers lists, search, Explore creators).
class UserSummary {
  const UserSummary({
    required this.id,
    required this.username,
    this.displayName,
    this.creatorType,
    this.avatarUrl,
    this.isFollowing = false,
    this.isMe = false,
  });

  final String id;
  final String username;
  final String? displayName;
  final String? creatorType;
  final String? avatarUrl;
  final bool isFollowing;
  final bool isMe;

  String get name => (displayName != null && displayName!.trim().isNotEmpty)
      ? displayName!
      : username;

  factory UserSummary.fromJson(Map<String, dynamic> json) => UserSummary(
    id: json['id'] as String,
    username: json['username'] as String,
    displayName: json['display_name'] as String?,
    creatorType: json['creator_type'] as String?,
    avatarUrl: json['avatar_url'] as String?,
    isFollowing: json['is_following'] as bool? ?? false,
    isMe: json['is_me'] as bool? ?? false,
  );
}

class UserPage {
  const UserPage({required this.items, this.nextCursor});
  final List<UserSummary> items;
  final String? nextCursor;

  factory UserPage.fromJson(Map<String, dynamic> json) => UserPage(
    items: [
      for (final u in json['items'] as List)
        UserSummary.fromJson(u as Map<String, dynamic>),
    ],
    nextCursor: json['next_cursor'] as String?,
  );
}
