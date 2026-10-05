import '../core/network/api_client.dart';
import '../models/post.dart';
import '../models/social.dart';

/// Talks to `/posts`. No UI or state here.
class PostRepository {
  const PostRepository(this._api, {required this.mediaBaseUrl});

  final ApiClient _api;

  /// API origin used to resolve storage-relative media paths.
  final String mediaBaseUrl;

  Future<FeedPage> fetchFeed({
    String? cursor,
    int limit = 20,
    String scope = 'all',
  }) async {
    final json = await _api.get(
      '/posts',
      query: {'limit': '$limit', 'scope': scope, 'cursor': ?cursor},
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
    String? placeId,
  }) async {
    final json = await _api.post(
      '/posts',
      body: {
        'place_id': ?placeId,
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

  // --- engagement -------------------------------------------------------------

  Future<LikeState> like(String id) async => LikeState.fromJson(
    await _api.put('/posts/$id/like') as Map<String, dynamic>,
  );

  Future<LikeState> unlike(String id) async => LikeState.fromJson(
    await _api.delete('/posts/$id/like') as Map<String, dynamic>,
  );

  Future<void> save(String id) => _api.put('/posts/$id/save');

  Future<void> unsave(String id) => _api.delete('/posts/$id/save');

  Future<CommentPage> comments(
    String postId, {
    String? cursor,
    int limit = 20,
  }) async {
    final json = await _api.get(
      '/posts/$postId/comments',
      query: {'limit': '$limit', 'cursor': ?cursor},
    );
    return CommentPage.fromJson(json as Map<String, dynamic>);
  }

  Future<Comment> addComment(String postId, String body) async =>
      Comment.fromJson(
        await _api.post('/posts/$postId/comments', body: {'body': body})
            as Map<String, dynamic>,
      );

  Future<void> deleteComment(String commentId) =>
      _api.delete('/comments/$commentId');

  Future<FeedPage> savedPosts({String? cursor, int limit = 20}) async {
    final json = await _api.get(
      '/users/me/saved/posts',
      query: {'limit': '$limit', 'cursor': ?cursor},
    );
    return FeedPage.fromJson(
      json as Map<String, dynamic>,
      mediaBaseUrl: mediaBaseUrl,
    );
  }
}
