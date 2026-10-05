import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../models/post.dart';
import '../../../routing/routes.dart';
import '../../../shared/widgets/widgets.dart';
import '../../auth/auth_controller.dart';
import '../../moderation/report_sheet.dart';
import '../../../models/report.dart';
import '../../social/post_removals.dart';
import 'post_card.dart';

/// A [PostCard] wired to the app: profile navigation, comments screen and
/// delete (own posts). Every post list uses this so behaviour is identical.
class PostTile extends ConsumerWidget {
  const PostTile({super.key, required this.post});
  final Post post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(postRemovalsProvider).contains(post.id)) {
      return const SizedBox.shrink();
    }
    final auth = ref.watch(authControllerProvider);
    final myId = auth is Authenticated ? auth.user.id : null;
    final isMine = post.author.id == myId;
    return PostCard(
      post: post,
      isMine: isMine,
      onAuthorTap: () =>
          openProfile(context, post.author.username, isMe: isMine),
      onDelete: isMine ? () => confirmDeletePost(context, ref, post) : null,
      onReport: isMine
          ? null
          : () => showReportSheet(
              context,
              target: ReportTarget.post,
              targetId: post.id,
            ),
      onOpenComments: () =>
          context.push(AppRoutes.postPath(post.id), extra: post),
    );
  }
}

/// Own profile lives in the tab bar; other people's open a pushed screen.
void openProfile(BuildContext context, String username, {required bool isMe}) {
  if (isMe) {
    context.go(AppRoutes.profile);
  } else {
    context.push(AppRoutes.userPath(username));
  }
}

Future<bool> confirmDeletePost(
  BuildContext context,
  WidgetRef ref,
  Post post,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete this post?'),
      content: const Text(
        'It will be removed for everyone, along with its photos.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  var deleted = false;
  await guarded(context, () async {
    await ref.read(postRemovalsProvider.notifier).delete(post.id);
    deleted = true;
  }, fallback: 'Could not delete the post.');
  return deleted;
}
