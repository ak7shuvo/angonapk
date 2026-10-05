import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/utils/time_format.dart';
import '../../models/notification.dart';
import '../../routing/routes.dart';
import '../../shared/paged/paged_views.dart';
import '../../shared/widgets/widgets.dart';
import 'notification_controllers.dart';

/// Where tapping a notification leads, or null when it has no destination.
String? notificationRoute(AppNotification n) {
  switch (n.type) {
    case 'like':
      if (n.targetId == null) return null;
      return n.targetType == 'story'
          ? AppRoutes.storyReadPath(
              (n.data['story_slug'] as String?) ?? n.targetId!,
            )
          : AppRoutes.postPath(n.targetId!);
    case 'comment':
      final postId = n.data['post_id'] as String?;
      return postId == null ? null : AppRoutes.postPath(postId);
    case 'follow':
      final username = (n.data['username'] as String?) ?? n.actor?.username;
      return username == null ? null : AppRoutes.userPath(username);
    default:
      return null;
  }
}

/// In-app notification inbox: likes, comments and new followers.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notificationsProvider);
    final controller = ref.read(notificationsProvider.notifier);
    listenForRefreshErrors(ref, notificationsProvider, context);
    final hasUnread = state.items.any((n) => !n.isRead);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (hasUnread)
            TextButton(
              onPressed: () async {
                try {
                  await controller.markAllRead();
                } catch (e) {
                  if (context.mounted) {
                    showAppSnack(
                      context,
                      errorMessage(
                        e,
                        fallback: 'Could not update notifications.',
                      ),
                    );
                  }
                }
              },
              child: const Text('Mark all read'),
            ),
        ],
      ),
      body: PagedScrollView(
        onRefresh: controller.refresh,
        onLoadMore: controller.loadMore,
        slivers: pagedSlivers<AppNotification>(
          state: state,
          onRetry: controller.retry,
          onLoadMore: controller.loadMore,
          empty: const EmptyState(
            icon: Icons.notifications_none,
            title: 'Nothing here yet',
            message: 'Likes, comments and new followers will show up here.',
          ),
          itemBuilder: (context, n) => NotificationTile(
            key: ValueKey(n.id),
            notification: n,
            onTap: () {
              controller.markRead(n);
              final route = notificationRoute(n);
              if (route != null) context.push(route);
            },
          ),
        ),
      ),
    );
  }
}

class NotificationTile extends StatelessWidget {
  const NotificationTile({
    super.key,
    required this.notification,
    required this.onTap,
  });
  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final n = notification;
    final actor = n.actor;
    final detail = n.detail;
    return Semantics(
      label: n.isRead ? null : 'Unread',
      child: Material(
        color: n.isRead
            ? Colors.transparent
            : theme.colorScheme.primary.withValues(alpha: 0.07),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.gutter,
              vertical: AppSpacing.md,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (actor != null)
                  UserAvatar(
                    name: actor.name,
                    seed: actor.username,
                    imageUrl: actor.avatarUrl,
                    size: 40,
                  )
                else
                  const CircleAvatar(
                    radius: 20,
                    child: Icon(Icons.notifications_none),
                  ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            if (actor != null)
                              TextSpan(
                                text: '${actor.name} ',
                                style: theme.textTheme.titleSmall,
                              ),
                            TextSpan(
                              text: n.action,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                      if (detail != null && detail.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          detail,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 2),
                      Text(
                        formatRelativeTime(n.createdAt),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (!n.isRead)
                  Padding(
                    padding: const EdgeInsets.only(left: AppSpacing.sm, top: 6),
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
