import '../core/utils/unchanged.dart';
import '../core/network/api_client.dart';
import '../models/user.dart';

/// Talks to `/auth` and `/users/me`. Contains no token persistence.
class AuthRepository {
  const AuthRepository(this._api);
  final ApiClient _api;

  Future<AuthSession> register({
    required String email,
    required String username,
    required String password,
  }) async {
    final json = await _api.post(
      '/auth/register',
      body: {'email': email, 'username': username, 'password': password},
    );
    return AuthSession.fromJson(json as Map<String, dynamic>);
  }

  Future<AuthSession> login({
    required String identifier,
    required String password,
  }) async {
    final json = await _api.post(
      '/auth/login',
      body: {'identifier': identifier, 'password': password},
    );
    return AuthSession.fromJson(json as Map<String, dynamic>);
  }

  Future<void> logout() => _api.post('/auth/logout');

  Future<AppUser> currentUser() async {
    final json = await _api.get('/users/me');
    return AppUser.fromJson(json as Map<String, dynamic>);
  }

  /// `avatarMediaId` / `coverMediaId`: an id from `POST /media`, `null` to remove
  /// the image, or omitted to leave it unchanged.
  Future<AppUser> updateProfile({
    String? displayName,
    String? bio,
    String? location,
    CreatorType? creatorType,
    Object? avatarMediaId = unchanged,
    Object? coverMediaId = unchanged,
  }) async {
    final json = await _api.patch(
      '/users/me/profile',
      body: {
        'display_name': ?displayName,
        'bio': ?bio,
        'location': ?location,
        'creator_type': ?creatorType?.apiValue,
        if (!identical(avatarMediaId, unchanged))
          'avatar_media_id': avatarMediaId,
        if (!identical(coverMediaId, unchanged)) 'cover_media_id': coverMediaId,
      },
    );
    return AppUser.fromJson(json as Map<String, dynamic>);
  }
}
