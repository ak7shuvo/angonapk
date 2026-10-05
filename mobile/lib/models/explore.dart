import 'place.dart';
import 'post.dart';
import 'social.dart';
import 'story.dart';

class Category {
  const Category({
    required this.slug,
    required this.label,
    required this.postCount,
    required this.storyCount,
  });
  final String slug;
  final String label;
  final int postCount;
  final int storyCount;

  factory Category.fromJson(Map<String, dynamic> json) => Category(
    slug: json['slug'] as String,
    label: json['label'] as String,
    postCount: json['post_count'] as int? ?? 0,
    storyCount: json['story_count'] as int? ?? 0,
  );
}

class ExploreData {
  const ExploreData({
    required this.categories,
    required this.trendingPosts,
    required this.featuredStories,
    required this.popularPlaces,
    required this.creators,
  });

  final List<Category> categories;
  final List<Post> trendingPosts;
  final List<StorySummary> featuredStories;
  final List<PlaceSummary> popularPlaces;
  final List<UserSummary> creators;

  bool get hasContent =>
      trendingPosts.isNotEmpty ||
      featuredStories.isNotEmpty ||
      popularPlaces.isNotEmpty ||
      creators.isNotEmpty;

  factory ExploreData.fromJson(
    Map<String, dynamic> json, {
    String mediaBaseUrl = '',
  }) => ExploreData(
    categories: [
      for (final c in json['categories'] as List)
        Category.fromJson(c as Map<String, dynamic>),
    ],
    trendingPosts: [
      for (final p in json['trending_posts'] as List)
        Post.fromJson(p as Map<String, dynamic>, mediaBaseUrl: mediaBaseUrl),
    ],
    featuredStories: [
      for (final s in json['featured_stories'] as List)
        StorySummary.fromJson(
          s as Map<String, dynamic>,
          mediaBaseUrl: mediaBaseUrl,
        ),
    ],
    popularPlaces: [
      for (final p in json['popular_places'] as List)
        PlaceSummary.fromJson(p as Map<String, dynamic>),
    ],
    creators: [
      for (final u in json['creators'] as List)
        UserSummary.fromJson(u as Map<String, dynamic>),
    ],
  );
}

enum SearchType { all, users, stories, posts, places }

class SearchResults {
  const SearchResults({
    this.query = '',
    this.users = const [],
    this.stories = const [],
    this.posts = const [],
    this.places = const [],
  });

  final String query;
  final List<UserSummary> users;
  final List<StorySummary> stories;
  final List<Post> posts;
  final List<PlaceSummary> places;

  bool get isEmpty =>
      users.isEmpty && stories.isEmpty && posts.isEmpty && places.isEmpty;

  factory SearchResults.fromJson(
    Map<String, dynamic> json, {
    String mediaBaseUrl = '',
  }) => SearchResults(
    query: json['query'] as String? ?? '',
    users: [
      for (final u in json['users'] as List)
        UserSummary.fromJson(u as Map<String, dynamic>),
    ],
    stories: [
      for (final s in json['stories'] as List)
        StorySummary.fromJson(
          s as Map<String, dynamic>,
          mediaBaseUrl: mediaBaseUrl,
        ),
    ],
    posts: [
      for (final p in json['posts'] as List)
        Post.fromJson(p as Map<String, dynamic>, mediaBaseUrl: mediaBaseUrl),
    ],
    places: [
      for (final p in json['places'] as List)
        PlaceSummary.fromJson(p as Map<String, dynamic>),
    ],
  );
}
