import 'user.dart';

class ProfileCounts {
  const ProfileCounts({
    required this.posts,
    required this.stories,
    required this.followers,
    required this.following,
    required this.places,
  });

  final int posts;
  final int stories;
  final int followers;
  final int following;
  final int places;

  factory ProfileCounts.fromJson(Map<String, dynamic> json) => ProfileCounts(
    posts: json['posts'] as int,
    stories: json['stories'] as int,
    followers: json['followers'] as int,
    following: json['following'] as int,
    places: json['places'] as int? ?? 0,
  );
}

/// What anyone can see about a user.
class PublicProfile {
  const PublicProfile({
    required this.id,
    required this.username,
    required this.counts,
    required this.isFollowing,
    required this.isMe,
    required this.joinedAt,
    this.displayName,
    this.bio,
    this.location,
    this.creatorType,
    this.avatarUrl,
    this.coverUrl,
  });

  final String id;
  final String username;
  final String? displayName;
  final String? bio;
  final String? location;
  final CreatorType? creatorType;
  final String? avatarUrl;
  final String? coverUrl;
  final DateTime joinedAt;
  final ProfileCounts counts;
  final bool isFollowing;
  final bool isMe;

  String get name => (displayName != null && displayName!.trim().isNotEmpty)
      ? displayName!
      : username;

  factory PublicProfile.fromJson(Map<String, dynamic> json) => PublicProfile(
    id: json['id'] as String,
    username: json['username'] as String,
    displayName: json['display_name'] as String?,
    bio: json['bio'] as String?,
    location: json['location'] as String?,
    creatorType: CreatorType.fromApi(json['creator_type'] as String?),
    avatarUrl: json['avatar_url'] as String?,
    coverUrl: json['cover_url'] as String?,
    joinedAt: DateTime.parse(json['joined_at'] as String).toLocal(),
    counts: ProfileCounts.fromJson(json['counts'] as Map<String, dynamic>),
    isFollowing: json['is_following'] as bool? ?? false,
    isMe: json['is_me'] as bool? ?? false,
  );
}
