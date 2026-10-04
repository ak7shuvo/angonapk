import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/social.dart';
import '../../services/providers.dart';

/// Live follow state per username, shared by post cards, profiles and lists.
/// Optimistic with rollback; the server's follower count replaces any guess.
class FollowController extends Notifier<Map<String, FollowState>> {
  final _inFlight = <String>{};

  @override
  Map<String, FollowState> build() => {};

  bool isFollowing(String username, {required bool fallback}) =>
      state[username]?.following ?? fallback;

  Future<void> toggle(
    String username, {
    required bool currentlyFollowing,
    int? followersCount,
  }) async {
    if (!_inFlight.add(username)) return;
    final previous = state[username];
    final want = !currentlyFollowing;
    state = {
      ...state,
      username: FollowState(
        following: want,
        followersCount:
            ((followersCount ?? previous?.followersCount ?? 0) +
                    (want ? 1 : -1))
                .clamp(0, 1 << 31),
      ),
    };
    try {
      final repo = ref.read(userRepositoryProvider);
      final result = want
          ? await repo.follow(username)
          : await repo.unfollow(username);
      if (ref.mounted) state = {...state, username: result};
    } catch (_) {
      if (ref.mounted) {
        final copy = {...state};
        previous == null ? copy.remove(username) : copy[username] = previous;
        state = copy;
      }
      rethrow;
    } finally {
      _inFlight.remove(username);
    }
  }
}

final followProvider =
    NotifierProvider<FollowController, Map<String, FollowState>>(
      FollowController.new,
    );
