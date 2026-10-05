import '../core/network/api_client.dart';
import '../models/notification.dart';

/// Talks to `/notifications`.
class NotificationRepository {
  const NotificationRepository(this._api);
  final ApiClient _api;

  Future<NotificationPage> list({
    String? cursor,
    int limit = 30,
    bool unreadOnly = false,
  }) async => NotificationPage.fromJson(
    await _api.get(
      '/notifications',
      query: {
        'limit': '$limit',
        'cursor': ?cursor,
        if (unreadOnly) 'unread_only': 'true',
      },
    ) as Map<String, dynamic>,
  );

  Future<int> unreadCount() async =>
      (await _api.get('/notifications/unread-count')
              as Map<String, dynamic>)['unread']
          as int;

  Future<AppNotification> markRead(String id) async => AppNotification.fromJson(
    await _api.post('/notifications/$id/read') as Map<String, dynamic>,
  );

  Future<void> markAllRead() => _api.post('/notifications/read-all');
}
