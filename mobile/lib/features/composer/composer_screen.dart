import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../routing/routes.dart';
import '../../shared/widgets/widgets.dart';
import '../auth/auth_controller.dart';
import '../places/widgets/place_field.dart';
import 'composer_controller.dart';

/// Suggested categories (also the Explore categories) as one-tap tags.
const categoryTags = [
  'travel',
  'culture',
  'heritage',
  'nature',
  'food',
  'photography',
  'people',
];

class ComposerScreen extends ConsumerStatefulWidget {
  const ComposerScreen({super.key});

  @override
  ConsumerState<ComposerScreen> createState() => _ComposerScreenState();
}

class _ComposerScreenState extends ConsumerState<ComposerScreen> {
  final _text = TextEditingController();
  final _location = TextEditingController();
  final _tag = TextEditingController();
  bool _synced = false;

  @override
  void dispose() {
    _text.dispose();
    _location.dispose();
    _tag.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    final post = await ref.read(composerControllerProvider.notifier).submit();
    if (post != null && mounted) {
      _text.clear();
      _location.clear();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Shared.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      context.go(AppRoutes.home);
    }
  }

  void _addTag() {
    final ok = ref.read(composerControllerProvider.notifier).addTag(_tag.text);
    if (ok || _tag.text.trim().isEmpty) {
      _tag.clear();
    } else {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Tags are 2–30 letters or numbers, up to 8.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(composerControllerProvider);
    final controller = ref.read(composerControllerProvider.notifier);
    final auth = ref.watch(authControllerProvider);
    final me = auth is Authenticated ? auth.user : null;
    final theme = Theme.of(context);

    // Fill the fields once the saved draft has been restored.
    if (state.restored && !_synced) {
      _synced = true;
      _text.text = state.text;
      _location.text = state.location;
    }
    ref.listen(composerControllerProvider.select((s) => s.notice), (_, notice) {
      if (notice == null) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(notice), behavior: SnackBarBehavior.floating),
        );
      controller.clearNotice();
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('New post'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.gutter),
            child: FilledButton(
              onPressed: state.canSubmit ? _share : null,
              style: FilledButton.styleFrom(minimumSize: const Size(88, 40)),
              child: state.submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Share'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(AppSpacing.gutter),
          children: [
            if (me != null)
              Row(
                children: [
                  UserAvatar(
                    name: me.displayName,
                    seed: me.username,
                    imageUrl: me.profile.avatarUrl,
                  ),
                  const SizedBox(width: AppSpacing.md - 4),
                  Expanded(
                    child: Text(
                      me.displayName,
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _text,
              onChanged: controller.setText,
              maxLines: null,
              minLines: 5,
              maxLength: maxPostLength,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              style: AppTypography.serif(
                size: 20,
                weight: 500,
                height: 1.5,
              ).copyWith(color: theme.colorScheme.onSurface),
              decoration: InputDecoration(
                hintText: 'What are you discovering?',
                hintStyle: AppTypography.serif(
                  size: 20,
                  weight: 400,
                  height: 1.5,
                ).copyWith(color: AppColors.inkFaint),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _PhotoStrip(state: state, controller: controller),
            const SizedBox(height: AppSpacing.lg),
            PlaceField(place: state.place, onChanged: controller.setPlace),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _location,
              onChanged: controller.setLocation,
              maxLength: 120,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.place_outlined),
                hintText: 'Where? e.g. Jaflong, Sylhet',
                counterText: '',
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('TAGS', style: theme.textTheme.labelMedium),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final category in categoryTags)
                  FilterChip(
                    label: Text(category),
                    selected: state.tags.contains(category),
                    onSelected: (_) => controller.toggleTag(category),
                  ),
                for (final tag in state.tags.where(
                  (t) => !categoryTags.contains(t),
                ))
                  InputChip(
                    label: Text('#$tag'),
                    onDeleted: () => controller.removeTag(tag),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _tag,
              onSubmitted: (_) => _addTag(),
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: 'Add your own tag',
                suffixIcon: IconButton(
                  tooltip: 'Add tag',
                  icon: const Icon(Icons.add),
                  onPressed: _addTag,
                ),
              ),
            ),
            if (state.error != null) ...[
              const SizedBox(height: AppSpacing.md),
              FormErrorBanner(state.error!),
            ],
            if (state.hasFailed)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.md),
                child: Text(
                  'Some photos failed to upload. Retry or remove them to share.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class FormErrorBanner extends StatelessWidget {
  const FormErrorBanner(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: scheme.error, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _PhotoStrip extends StatelessWidget {
  const _PhotoStrip({required this.state, required this.controller});
  final ComposerState state;
  final ComposerController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 104,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final a in state.attachments)
            _Thumb(
              key: ValueKey(a.localId),
              attachment: a,
              onRemove: () => controller.removeAttachment(a.localId),
              onRetry: () => controller.retryUpload(a.localId),
            ),
          if (state.attachments.length < maxPostImages)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: Semantics(
                button: true,
                label: 'Add photos',
                child: InkWell(
                  onTap: controller.pickPhotos,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  child: Container(
                    width: 104,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color:
                            Theme.of(context).dividerTheme.color ??
                            AppColors.line,
                      ),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.add_photo_alternate_outlined,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Add photos',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({
    super.key,
    required this.attachment,
    required this.onRemove,
    required this.onRetry,
  });
  final Attachment attachment;
  final VoidCallback onRemove;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final a = attachment;
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: SizedBox(
          width: 104,
          height: 104,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.memory(
                Uint8List.fromList(a.image.bytes),
                fit: BoxFit.cover,
                cacheWidth: 300,
                errorBuilder: (_, _, _) =>
                    ColoredBox(color: context.placeholder),
              ),
              if (a.status == UploadStatus.uploading)
                ColoredBox(
                  color: Colors.black.withValues(alpha: 0.35),
                  child: Center(
                    child: Semantics(
                      label: 'Uploading photo',
                      child: CircularProgressIndicator(
                        value: a.queued || a.progress == 0 ? null : a.progress,
                        strokeWidth: 3,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              if (a.status == UploadStatus.failed)
                ColoredBox(
                  color: Colors.black.withValues(alpha: 0.55),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.white),
                      TextButton(
                        onPressed: onRetry,
                        child: const Text(
                          'Retry',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              Positioned(
                top: 2,
                right: 2,
                child: IconButton(
                  tooltip: 'Remove photo',
                  visualDensity: VisualDensity.compact,
                  style: IconButton.styleFrom(backgroundColor: Colors.black54),
                  icon: const Icon(Icons.close, size: 16, color: Colors.white),
                  onPressed: onRemove,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
