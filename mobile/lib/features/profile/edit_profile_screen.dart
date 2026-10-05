import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../models/user.dart';
import '../../shared/widgets/widgets.dart';
import '../auth/auth_controller.dart';
import '../composer/composer_screen.dart' show FormErrorBanner;
import '../../core/utils/media_url.dart';
import '../../services/providers.dart';
import 'edit_profile_controller.dart';
import 'profile_controllers.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  late final TextEditingController _name;
  late final TextEditingController _bio;
  late final TextEditingController _location;

  @override
  void initState() {
    super.initState();
    final s = ref.read(editProfileProvider);
    _name = TextEditingController(text: s.displayName);
    _bio = TextEditingController(text: s.bio);
    _location = TextEditingController(text: s.location);
  }

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final auth = ref.read(authControllerProvider);
    final ok = await ref.read(editProfileProvider.notifier).save();
    if (!ok || !mounted) return;
    if (auth is Authenticated) {
      ref.invalidate(userProfileProvider(auth.user.username));
    }
    showAppSnack(context, 'Profile updated.');
    context.pop();
  }

  Future<bool> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Your unsaved changes will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return discard == true;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(editProfileProvider);
    final controller = ref.read(editProfileProvider.notifier);
    final auth = ref.watch(authControllerProvider);
    final username = auth is Authenticated ? auth.user.username : '';
    final theme = Theme.of(context);

    ref.listen(editProfileProvider.select((s) => s.notice), (_, notice) {
      if (notice != null) {
        showAppSnack(context, notice);
        controller.clearNotice();
      }
    });

    return PopScope(
      canPop: !state.dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await _confirmDiscard();
        if (discard && context.mounted) context.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Edit profile'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.gutter),
              child: FilledButton(
                onPressed: state.canSave ? _save : null,
                style: FilledButton.styleFrom(minimumSize: const Size(88, 40)),
                child: state.saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.only(bottom: AppSpacing.xl),
            children: [
              _CoverEditor(state: state, controller: controller),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.gutter,
                  AppSpacing.md,
                  AppSpacing.gutter,
                  0,
                ),
                child: Row(
                  children: [
                    Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        UserAvatar(
                          name: state.displayName.isEmpty
                              ? username
                              : state.displayName,
                          seed: username,
                          imageUrl: state.avatar?.url,
                          size: 88,
                        ),
                        if (state.uploading > 0)
                          const Positioned.fill(
                            child: Center(child: CircularProgressIndicator()),
                          ),
                      ],
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Wrap(
                        spacing: AppSpacing.sm,
                        children: [
                          OutlinedButton(
                            onPressed: state.uploading > 0
                                ? null
                                : controller.pickAvatar,
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 40),
                            ),
                            child: Text(
                              state.avatar == null
                                  ? 'Add photo'
                                  : 'Change photo',
                            ),
                          ),
                          if (state.avatar != null)
                            TextButton(
                              onPressed: controller.removeAvatar,
                              child: const Text('Remove'),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.gutter,
                  AppSpacing.lg,
                  AppSpacing.gutter,
                  0,
                ),
                child: Column(
                  children: [
                    TextField(
                      controller: _name,
                      onChanged: controller.setName,
                      maxLength: 80,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      controller: _location,
                      onChanged: controller.setLocation,
                      maxLength: 120,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Location',
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      controller: _bio,
                      onChanged: controller.setBio,
                      maxLines: 4,
                      maxLength: 500,
                      decoration: const InputDecoration(
                        labelText: 'Bio',
                        alignLabelWithHint: true,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.gutter,
                  AppSpacing.lg,
                  AppSpacing.gutter,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('I AM A', style: theme.textTheme.labelMedium),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final t in CreatorType.values)
                          ChoiceChip(
                            label: Text(t.label),
                            selected: state.creatorType == t,
                            onSelected: (_) => controller.setType(t),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (state.error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.gutter,
                    AppSpacing.lg,
                    AppSpacing.gutter,
                    0,
                  ),
                  child: FormErrorBanner(state.error!),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoverEditor extends ConsumerWidget {
  const _CoverEditor({required this.state, required this.controller});
  final EditProfileState state;
  final EditProfileController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return AspectRatio(
      aspectRatio: 16 / 7,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (state.cover?.url != null)
            _CoverImage(url: state.cover!.url!)
          else
            ColoredBox(
              color: theme.brightness == Brightness.dark
                  ? AppColors.nightCard
                  : AppColors.paperDeep,
            ),
          Positioned(
            right: 8,
            bottom: 8,
            child: Row(
              children: [
                FilledButton.tonal(
                  onPressed: state.uploading > 0 ? null : controller.pickCover,
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 36)),
                  child: Text(
                    state.cover == null ? 'Add cover' : 'Change cover',
                  ),
                ),
                if (state.cover != null) ...[
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Remove cover',
                    onPressed: controller.removeCover,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CoverImage extends ConsumerWidget {
  const _CoverImage({required this.url});
  final String url;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Image.network(
    resolveMediaUrl(ref.watch(appConfigProvider).apiBaseUrl, url),
    fit: BoxFit.cover,
    semanticLabel: 'Cover photo',
    errorBuilder: (_, _, _) => const ColoredBox(color: AppColors.paperDeep),
  );
}
