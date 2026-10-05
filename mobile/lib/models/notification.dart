import 'post.dart';

/// An in-app notification. [type] is an open string: known types (like, comment,
/// follow) get tailored text; anything else falls back to `data.title`/`data.body`
/// so new server-side kinds (bookings, messages, moderation…) still display.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.isRead,
    required this.createdAt,
    this.actor,
    this.targetType,
    this.targetId,
    this.data = const {},
  });

  final String id;
  final String type;
  final PostAuthor? actor;
  final String? targetType;
  final String? targetId;
  final Map<String, dynamic> data;
  final bool isRead;
  final DateTime createdAt;

  String? get preview => data['preview'] as String?;

  AppNotification copyWith({bool? isRead}) => AppNotification(
    id: id,
    type: type,
    actor: actor,
    targetType: targetType,
    targetId: targetId,
    data: data,
    isRead: isRead ?? this.isRead,
    createdAt: createdAt,
  );

  /// The verb phrase shown after the actor's name.
  String get action {
    final what = targetType == 'story' ? 'story' : 'post';
    return switch (type) {
      'like' => 'liked your $what',
      'comment' => 'commented on your post',
      'follow' => 'started following you',
      _ => (data['title'] as String?) ?? 'sent you a notification',
    };
  }

  /// Secondary line: the comment text, post excerpt, story title, or a custom body.
  String? get detail =>
      type == 'follow' ? null : (preview ?? data['body'] as String?);

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: json['id'] as String,
        type: json['type'] as String,
        actor: json['actor'] == null
            ? null
            : PostAuthor.fromJson(json['actor'] as Map<String, dynamic>),
        targetType: json['target_type'] as String?,
        targetId: json['target_id'] as String?,
        data: Map<String, dynamic>.from(json['data'] as Map? ?? const {}),
        isRead: json['is_read'] as bool? ?? false,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      );
}

class NotificationPage {
  const NotificationPage({required this.items, this.nextCursor});
  final List<AppNotification> items;
  final String? nextCursor;

  factory NotificationPage.fromJson(Map<String, dynamic> json) =>
      NotificationPage(
        items: [
          for (final n in json['items'] as List)
            AppNotification.fromJson(n as Map<String, dynamic>),
        ],
        nextCursor: json['next_cursor'] as String?,
      );
}
