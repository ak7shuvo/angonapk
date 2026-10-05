import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/utils/time_format.dart';
import '../../models/post.dart';
import '../../models/social.dart';
import '../../services/providers.dart';
import '../../shared/widgets/widgets.dart';
import '../auth/auth_controller.dart';
import '../feed/widgets/post_card.dart';
import '../feed/widgets/post_tile.dart';
import 'comments_controller.dart';
import 'engagement_controller.dart';
import 'post_removals.dart';

final _postDetailProvider = FutureProvider.autoDispose.family<Post, String>((
  ref,
  id,
) async {
  final post = await ref.watch(postRepositoryProvider).getPost(id);
  ref.read(engagementProvider.notifier).ingest([post]);
  return post;
});

/// A post with its conversation. [initial] avoids a refetch when opened from a list.
class PostDetailScreen extends ConsumerWidget {
  const PostDetailScreen({super.key, required this.postId, this.initial});
  final String postId;
  final Post? initial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (initial != null) return _PostConversation(post: initial!);
    final async = ref.watch(_postDetailProvider(postId));
    return async.when(
      data: (post) => _PostConversation(post: post),
      loading: () => Scaffold(appBar: AppBar(), body: const LoadingView()),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: ErrorState(
          error: e,
          onRetry: () => ref.invalidate(_postDetailProvider(postId)),
        ),
      ),
    );
  }
}

class _PostConversation extends ConsumerStatefulWidget {
  const _PostConversation({required this.post});
  final Post post;

  @override
  ConsumerState<_PostConversation> createState() => _PostConversationState();
}

class _PostConversationState extends ConsumerState<_PostConversation> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    try {
      await ref
          .read(commentsControllerProvider(widget.post).notifier)
          .add(text);
      _input.clear();
    } catch (e) {
      if (mounted) {
        showAppSnack(
          context,
          errorMessage(e, fallback: 'Could not post your comment.'),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final comments = ref.watch(commentsControllerProvider(post));
    final auth = ref.watch(authControllerProvider);
    final myId = auth is Authenticated ? auth.user.id : null;
    final isMine = post.author.id == myId;
    final removed = ref.watch(postRemovalsProvider).contains(post.id);
    final theme = Theme.of(context);

    if (removed) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.delete_outline,
          title: 'This post was deleted',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Post')),
      body: Column(
        children: [
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.metrics.extentAfter < 400) {
                  ref
                      .read(commentsControllerProvider(post).notifier)
                      .loadMore();
                }
                return false;
              },
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  PostCard(
                    post: post,
                    isMine: isMine,
                    onAuthorTap: () => openProfile(
                      context,
                      post.author.username,
                      isMe: isMine,
                    ),
                    onDelete: isMine
                        ? () async {
                            if (await confirmDeletePost(context, ref, post) &&
                                context.mounted) {
                              context.pop();
                            }
                          }
                        : null,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.gutter,
                      AppSpacing.lg,
                      AppSpacing.gutter,
                      AppSpacing.sm,
                    ),
                    child: Text('COMMENTS', style: theme.textTheme.labelMedium),
                  ),
                  if (comments.loading)
                    const Padding(
                      padding: EdgeInsets.all(AppSpacing.lg),
                      child: LoadingView(),
                    )
                  else if (comments.error != null)
                    SizedBox(
                      height: 160,
                      child: ErrorState(
                        error: comments.error!,
                        onRetry: () => ref
                            .read(commentsControllerProvider(post).notifier)
                            .load(),
                      ),
                    )
                  else if (comments.items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.gutter),
                      child: Text(
                        'No comments yet. Start the conversation.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    )
                  else ...[
                    for (final c in comments.items)
                      _CommentTile(
                        key: ValueKey(c.id),
                        comment: c,
                        onDelete: c.isMine
                            ? () => guarded(
                                context,
                                () => ref
                                    .read(
                                      commentsControllerProvider(post).notifier,
                                    )
                                    .delete(c),
                                fallback: 'Could not delete the comment.',
                              )
                            : null,
                      ),
                    if (comments.hasMore)
                      const Padding(
                        padding: EdgeInsets.all(AppSpacing.lg),
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: theme.dividerTheme.color ?? Colors.grey,
                  ),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                AppSpacing.sm,
                AppSpacing.sm,
                AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 1000,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        hintText: 'Add a comment…',
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  IconButton.filled(
                    tooltip: 'Send comment',
                    onPressed: comments.sending ? null : _send,
                    icon: comments.sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    super.key,
    required this.comment,
    required this.onDelete,
  });
  final Comment comment;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.gutter,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserAvatar(
            name: comment.author.name,
            seed: comment.author.username,
            imageUrl: comment.author.avatarUrl,
            size: 32,
          ),
          const SizedBox(width: AppSpacing.md - 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: comment.author.name,
                        style: theme.textTheme.titleSmall,
                      ),
                      TextSpan(
                        text: '  ${formatRelativeTime(comment.createdAt)}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(comment.body, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
          if (onDelete != null)
            IconButton(
              tooltip: 'Delete comment',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }
}
