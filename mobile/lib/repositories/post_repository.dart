import '../core/network/api_client.dart';
import '../models/post.dart';

/// Talks to `/posts`. No UI or state here.
class PostRepository {
  const PostRepository(this._api, {required this.mediaBaseUrl});

  final ApiClient _api;

  /// API origin used to resolve storage-relative media paths.
  final String mediaBaseUrl;

  Future<FeedPage> fetchFeed({String? cursor, int limit = 20}) async {
    final json = await _api.get(
      '/posts',
      query: {'limit': '$limit', 'cursor': ?cursor},
    );
    return FeedPage.fromJson(
      json as Map<String, dynamic>,
      mediaBaseUrl: mediaBaseUrl,
    );
  }

  Future<Post> getPost(String id) async {
    final json = await _api.get('/posts/$id');
    return Post.fromJson(
      json as Map<String, dynamic>,
      mediaBaseUrl: mediaBaseUrl,
    );
  }

  /// [media] are ids returned by `MediaRepository.uploadImage`.
  Future<Post> createPost({
    String? body,
    String? locationText,
    List<String> mediaIds = const [],
    List<String> tags = const [],
  }) async {
    final json = await _api.post(
      '/posts',
      body: {
        'body': ?body,
        'location_text': ?locationText,
        'media': [
          for (final id in mediaIds) {'asset_id': id},
        ],
        'tags': tags,
      },
    );
    return Post.fromJson(
      json as Map<String, dynamic>,
      mediaBaseUrl: mediaBaseUrl,
    );
  }

  Future<void> deletePost(String id) => _api.delete('/posts/$id');
}
