import 'place.dart';
import 'post.dart';
import 'story.dart';

/// Places around a point plus the latest content about them.
class NearbyData {
  const NearbyData({
    required this.places,
    required this.posts,
    required this.stories,
  });
  final List<PlaceSummary> places;
  final List<Post> posts;
  final List<StorySummary> stories;

  bool get isEmpty => places.isEmpty && posts.isEmpty && stories.isEmpty;

  factory NearbyData.fromJson(
    Map<String, dynamic> json, {
    String mediaBaseUrl = '',
  }) => NearbyData(
    places: [
      for (final p in json['places'] as List)
        PlaceSummary.fromJson(p as Map<String, dynamic>),
    ],
    posts: [
      for (final p in json['posts'] as List)
        Post.fromJson(p as Map<String, dynamic>, mediaBaseUrl: mediaBaseUrl),
    ],
    stories: [
      for (final s in json['stories'] as List)
        StorySummary.fromJson(
          s as Map<String, dynamic>,
          mediaBaseUrl: mediaBaseUrl,
        ),
    ],
  );
}
