import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/widgets/widgets.dart';
import 'follow_controller.dart';

/// Follow / Following toggle backed by the server. Hidden for yourself.
class FollowButton extends ConsumerWidget {
  const FollowButton({
    super.key,
    required this.username,
    required this.initiallyFollowing,
    this.followersCount,
    this.compact = false,
  });

  final String username;

  /// Server value from the list/profile this button was built from.
  final bool initiallyFollowing;
  final int? followersCount;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final following = ref.watch(
      followProvider.select(
        (m) => m[username]?.following ?? initiallyFollowing,
      ),
    );
    void onPressed() => guarded(
      context,
      () => ref
          .read(followProvider.notifier)
          .toggle(
            username,
            currentlyFollowing: following,
            followersCount: followersCount,
          ),
      fallback: 'Could not update follow. Please try again.',
    );
    final text = Text(following ? 'Following' : 'Follow');
    // Compact buttons sit in tight rows; don't let huge text push them off-screen.
    final label = compact
        ? MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3, child: text)
        : text;
    final size = compact ? const Size(0, 34) : const Size(110, 44);
    return following
        ? OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              minimumSize: size,
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: label,
          )
        : FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              minimumSize: size,
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: label,
          );
  }
}
