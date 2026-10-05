import '../core/network/api_client.dart';
import '../models/post.dart';
import '../models/public_profile.dart';
import '../models/social.dart';

/// People: follow graph. Public profiles are added with the profile phase.
class UserRepository {
  const UserRepository(this._api, {this.mediaBaseUrl = ''});
  final ApiClient _api;
  final String mediaBaseUrl;

  Future<PublicProfile> profile(String username) async =>
      PublicProfile.fromJson(
        await _api.get('/users/$username') as Map<String, dynamic>,
      );

  /// A user's posts, newest first.
  Future<FeedPage> posts(
    String username, {
    String? cursor,
    int limit = 20,
  }) async => FeedPage.fromJson(
    await _api.get(
      '/users/$username/posts',
      query: {'limit': '$limit', 'cursor': ?cursor},
    ) as Map<String, dynamic>,
    mediaBaseUrl: mediaBaseUrl,
  );

  Future<FollowState> follow(String username) async => FollowState.fromJson(
    await _api.put('/users/$username/follow') as Map<String, dynamic>,
  );

  Future<FollowState> unfollow(String username) async => FollowState.fromJson(
    await _api.delete('/users/$username/follow') as Map<String, dynamic>,
  );

  Future<UserPage> followers(
    String username, {
    String? cursor,
    int limit = 30,
  }) async => UserPage.fromJson(
    await _api.get(
      '/users/$username/followers',
      query: {'limit': '$limit', 'cursor': ?cursor},
    ) as Map<String, dynamic>,
  );

  Future<UserPage> following(
    String username, {
    String? cursor,
    int limit = 30,
  }) async => UserPage.fromJson(
    await _api.get(
      '/users/$username/following',
      query: {'limit': '$limit', 'cursor': ?cursor},
    ) as Map<String, dynamic>,
  );
}
