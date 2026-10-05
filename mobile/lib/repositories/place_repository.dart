import '../core/network/api_client.dart';
import '../models/place.dart';
import '../models/post.dart';
import '../models/social.dart';
import '../models/story.dart';

typedef Bounds = ({double minLat, double maxLat, double minLng, double maxLng});

/// Talks to `/places`.
class PlaceRepository {
  const PlaceRepository(this._api, {required this.mediaBaseUrl});
  final ApiClient _api;
  final String mediaBaseUrl;

  /// Search/filter. [near] sorts by distance; [bounds] is a map viewport.
  Future<PlaceList> search({
    String? q,
    String? division,
    String? district,
    Bounds? bounds,
    ({double lat, double lng})? near,
    double radiusKm = 50,
    int limit = 50,
    int offset = 0,
  }) async {
    final json = await _api.get(
      '/places',
      query: {
        if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
        'division': ?division,
        'district': ?district,
        if (bounds != null) ...{
          'min_lat': '${bounds.minLat}',
          'max_lat': '${bounds.maxLat}',
          'min_lng': '${bounds.minLng}',
          'max_lng': '${bounds.maxLng}',
        },
        if (near != null) ...{
          'near_lat': '${near.lat}',
          'near_lng': '${near.lng}',
          'radius_km': '$radiusKm',
        },
        'limit': '$limit',
        'offset': '$offset',
      },
    );
    return PlaceList.fromJson(json as Map<String, dynamic>);
  }

  Future<PlaceDetail> get(String slug) async => PlaceDetail.fromJson(
    await _api.get('/places/$slug') as Map<String, dynamic>,
  );

  Future<FeedPage> posts(String slug, {String? cursor, int limit = 20}) async =>
      FeedPage.fromJson(
        await _api.get(
          '/places/$slug/posts',
          query: {'limit': '$limit', 'cursor': ?cursor},
        ) as Map<String, dynamic>,
        mediaBaseUrl: mediaBaseUrl,
      );

  Future<StoryPage> stories(
    String slug, {
    String? cursor,
    int limit = 20,
  }) async => StoryPage.fromJson(
    await _api.get(
      '/places/$slug/stories',
      query: {'limit': '$limit', 'cursor': ?cursor},
    ) as Map<String, dynamic>,
    mediaBaseUrl: mediaBaseUrl,
  );

  Future<PlacePhotoPage> photos(
    String slug, {
    String? cursor,
    int limit = 30,
  }) async {
    final json = await _api.get(
      '/places/$slug/photos',
      query: {'limit': '$limit', 'cursor': ?cursor},
    ) as Map<String, dynamic>;
    return PlacePhotoPage(
      items: [
        for (final p in json['items'] as List)
          PlacePhoto.fromJson(
            p as Map<String, dynamic>,
            mediaBaseUrl: mediaBaseUrl,
          ),
      ],
      nextCursor: json['next_cursor'] as String?,
    );
  }

  Future<List<UserSummary>> creators(String slug, {int limit = 20}) async => [
    for (final u in await _api.get(
      '/places/$slug/creators',
      query: {'limit': '$limit'},
    ) as List)
      UserSummary.fromJson(u as Map<String, dynamic>),
  ];

  /// Places a user has documented.
  Future<List<PlaceSummary>> documentedBy(String username) async => [
    for (final p in await _api.get('/users/$username/places') as List)
      PlaceSummary.fromJson(p as Map<String, dynamic>),
  ];
}
