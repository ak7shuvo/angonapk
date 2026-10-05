import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/notification.dart';
import '../../services/providers.dart';
import '../../shared/paged/paged_controller.dart';
import '../auth/auth_controller.dart';

/// Number of unread notifications, for the badge on Home.
///
/// Refreshed on demand (opening Home, returning from the inbox) and on a slow
/// timer while the app is open. There is no push channel in V1.
class UnreadCountController extends Notifier<int> {
  static const pollInterval = Duration(seconds: 90);

  @override
  int build() {
    final signedIn = ref.watch(
      authControllerProvider.select((s) => s is Authenticated),
    );
    if (!signedIn) return 0;
    final timer = Timer.periodic(pollInterval, (_) => refresh());
    ref.onDispose(timer.cancel);
    Future.microtask(refresh);
    return 0;
  }

  Future<void> refresh() async {
    try {
      final count = await ref
          .read(notificationRepositoryProvider)
          .unreadCount();
      if (ref.mounted) state = count;
    } catch (_) {
      // The badge is a convenience: stay quiet when offline.
    }
  }

  void set(int count) => state = count;
}

final unreadCountProvider = NotifierProvider<UnreadCountController, int>(
  UnreadCountController.new,
);

/// Your notifications, newest first.
class NotificationsController extends PagedController<AppNotification> {
  @override
  Future<Page<AppNotification>> fetch(String? cursor) async {
    ref.watch(
      authControllerProvider.select(
        (s) => s is Authenticated ? s.user.id : null,
      ),
    );
    final page = await ref
        .read(notificationRepositoryProvider)
        .list(cursor: cursor);
    return (items: page.items, nextCursor: page.nextCursor);
  }

  @override
  String idOf(AppNotification item) => item.id;

  @override
  void onLoaded(List<AppNotification> items) =>
      ref.read(unreadCountProvider.notifier).refresh();

  /// Optimistic (safe: it only flips a flag); reverted if the server refuses.
  Future<void> markRead(AppNotification n) async {
    if (n.isRead) return;
    replaceItem(n.copyWith(isRead: true));
    final badge = ref.read(unreadCountProvider.notifier);
    badge.set((ref.read(unreadCountProvider) - 1).clamp(0, 1 << 31));
    try {
      await ref.read(notificationRepositoryProvider).markRead(n.id);
    } catch (_) {
      if (ref.mounted) replaceItem(n);
    } finally {
      unawaited(badge.refresh());
    }
  }

  Future<void> markAllRead() async {
    await ref.read(notificationRepositoryProvider).markAllRead();
    if (!ref.mounted) return;
    state = state.copyWith(
      items: [for (final n in state.items) n.copyWith(isRead: true)],
    );
    ref.read(unreadCountProvider.notifier).set(0);
  }
}

final notificationsProvider =
    NotifierProvider.autoDispose<
      NotificationsController,
      PagedState<AppNotification>
    >(NotificationsController.new);
