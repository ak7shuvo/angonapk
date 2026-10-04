import '../core/network/api_client.dart';
import '../models/story.dart';

const _unset = Object();

/// Talks to `/stories`.
class StoryRepository {
  const StoryRepository(this._api, {required this.mediaBaseUrl});
  final ApiClient _api;
  final String mediaBaseUrl;

  StorySummary _summary(Object? j) => StorySummary.fromJson(
    j as Map<String, dynamic>,
    mediaBaseUrl: mediaBaseUrl,
  );
  Story _story(Object? j) =>
      Story.fromJson(j as Map<String, dynamic>, mediaBaseUrl: mediaBaseUrl);
  StoryPage _page(Object? j) =>
      StoryPage.fromJson(j as Map<String, dynamic>, mediaBaseUrl: mediaBaseUrl);

  Future<StoryPage> feed({
    String? cursor,
    String? author,
    String? tag,
    int limit = 20,
  }) async => _page(
    await _api.get(
      '/stories',
      query: {
        'limit': '$limit',
        'cursor': ?cursor,
        'author': ?author,
        'tag': ?tag,
      },
    ),
  );

  /// Your own stories (drafts included). [status]: draft | published | all.
  Future<StoryPage> mine({
    String status = 'all',
    String? cursor,
    int limit = 20,
  }) async => _page(
    await _api.get(
      '/stories/mine',
      query: {'status': status, 'limit': '$limit', 'cursor': ?cursor},
    ),
  );

  Future<Story> get(String ref) async =>
      _story(await _api.get('/stories/$ref'));

  Future<List<StorySummary>> related(String ref, {int limit = 5}) async => [
    for (final s in await _api.get(
      '/stories/$ref/related',
      query: {'limit': '$limit'},
    ) as List)
      _summary(s),
  ];

  Future<Story> create({
    required String title,
    required String content,
    String? coverAssetId,
    String? locationText,
    List<String> tags = const [],
    bool publish = false,
  }) async => _story(
    await _api.post(
      '/stories',
      body: {
        'title': title,
        'content': content,
        'cover_asset_id': coverAssetId,
        'location_text': locationText,
        'tags': tags,
        'status': publish ? 'published' : 'draft',
      },
    ),
  );

  /// Pass `coverAssetId: null` to remove the cover; omit it to leave it unchanged.
  Future<Story> update(
    String id, {
    String? title,
    String? content,
    Object? coverAssetId = _unset,
    Object? locationText = _unset,
    List<String>? tags,
  }) async => _story(
    await _api.patch(
      '/stories/$id',
      body: {
        'title': ?title,
        'content': ?content,
        if (!identical(coverAssetId, _unset)) 'cover_asset_id': coverAssetId,
        if (!identical(locationText, _unset)) 'location_text': locationText,
        'tags': ?tags,
      },
    ),
  );

  Future<Story> publish(String id) async =>
      _story(await _api.post('/stories/$id/publish'));
  Future<Story> unpublish(String id) async =>
      _story(await _api.post('/stories/$id/unpublish'));
  Future<void> delete(String id) => _api.delete('/stories/$id');

  Future<({bool liked, int likeCount})> like(String id) async {
    final j = await _api.put('/stories/$id/like') as Map<String, dynamic>;
    return (liked: j['liked'] as bool, likeCount: j['like_count'] as int);
  }

  Future<({bool liked, int likeCount})> unlike(String id) async {
    final j = await _api.delete('/stories/$id/like') as Map<String, dynamic>;
    return (liked: j['liked'] as bool, likeCount: j['like_count'] as int);
  }

  Future<void> save(String id) => _api.put('/stories/$id/save');
  Future<void> unsave(String id) => _api.delete('/stories/$id/save');

  Future<StoryPage> saved({String? cursor, int limit = 20}) async => _page(
    await _api.get(
      '/users/me/saved/stories',
      query: {'limit': '$limit', 'cursor': ?cursor},
    ),
  );
}
