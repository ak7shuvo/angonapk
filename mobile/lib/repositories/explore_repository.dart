import '../core/network/api_client.dart';
import '../models/explore.dart';

/// Talks to `/explore` and `/search`.
class ExploreRepository {
  const ExploreRepository(this._api, {required this.mediaBaseUrl});
  final ApiClient _api;
  final String mediaBaseUrl;

  Future<ExploreData> explore() async => ExploreData.fromJson(
    await _api.get('/explore') as Map<String, dynamic>,
    mediaBaseUrl: mediaBaseUrl,
  );

  Future<SearchResults> search(
    String q, {
    SearchType type = SearchType.all,
    int limit = 5,
    int offset = 0,
  }) async => SearchResults.fromJson(
    await _api.get(
      '/search',
      query: {
        'q': q,
        'type': type.name,
        'limit': '$limit',
        'offset': '$offset',
      },
    ) as Map<String, dynamic>,
    mediaBaseUrl: mediaBaseUrl,
  );
}
