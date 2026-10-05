import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../routing/routes.dart';
import '../../shared/widgets/widgets.dart';
import '../composer/composer_screen.dart' show categoryTags, FormErrorBanner;
import '../places/widgets/place_field.dart';
import 'story_controllers.dart';
import 'story_editor_controller.dart';
import 'story_markup.dart';

/// Write or edit a story. Drafts are saved on the server; publishing is explicit.
class StoryEditorScreen extends ConsumerStatefulWidget {
  const StoryEditorScreen({super.key, this.storyId});

  /// Null for a new story.
  final String? storyId;

  @override
  ConsumerState<StoryEditorScreen> createState() => _StoryEditorScreenState();
}

class _StoryEditorScreenState extends ConsumerState<StoryEditorScreen> {
  final _title = TextEditingController();
  final _content = TextEditingController();
  final _location = TextEditingController();
  final _tag = TextEditingController();
  bool _synced = false;

  StoryEditorController get _controller =>
      ref.read(storyEditorProvider(widget.storyId).notifier);

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    _location.dispose();
    _tag.dispose();
    super.dispose();
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

  Future<void> _saveDraft() async {
    final story = await _controller.save();
    if (story == null || !mounted) return;
    invalidateStoryLists(ref);
    showAppSnack(context, 'Draft saved.');
  }

  Future<void> _publish() async {
    final wasPublished = ref
        .read(storyEditorProvider(widget.storyId))
        .isPublished;
    final story = await _controller.save(publish: true);
    if (story == null || !mounted) return;
    invalidateStoryLists(ref);
    ref.invalidate(storyProvider(story.id));
    ref.invalidate(storyProvider(story.slug));
    if (wasPublished) {
      context.pop();
    } else {
      showAppSnack(context, 'Published.');
      context.pushReplacement(AppRoutes.storyReadPath(story.slug));
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this story?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await guarded(context, () async {
      await _controller.deleteStory();
      invalidateStoryLists(ref);
      if (mounted) {
        // Leave without the dirty-confirmation.
        ref
            .read(storyEditorProvider(widget.storyId).notifier)
            .setTitle(_title.text);
        context.go(AppRoutes.stories);
      }
    }, fallback: 'Could not delete the story.');
  }

  void _applyEdit(EditResult r) {
    _content.value = TextEditingValue(
      text: r.text,
      selection: TextSelection.collapsed(offset: r.caret),
    );
    _controller.setContent(r.text);
  }

  int get _caret => _content.selection.isValid
      ? _content.selection.start
      : _content.text.length;

  Future<void> _insertPhoto() async {
    final token = await _controller.addInlineImage();
    if (token == null || !mounted) return;
    _applyEdit(insertBlock(_content.text, _caret, token));
  }

  void _addTag() {
    final ok = _controller.addTag(_tag.text);
    if (ok || _tag.text.trim().isEmpty) {
      _tag.clear();
    } else {
      showAppSnack(context, 'Tags are 2–30 letters or numbers, up to 8.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(storyEditorProvider(widget.storyId));
    final theme = Theme.of(context);

    ref.listen(storyEditorProvider(widget.storyId).select((s) => s.notice), (
      _,
      notice,
    ) {
      if (notice != null) {
        showAppSnack(context, notice);
        _controller.clearNotice();
      }
    });

    if (state.loading) {
      return Scaffold(appBar: AppBar(), body: const LoadingView());
    }
    if (state.loadError != null) {
      return Scaffold(
        appBar: AppBar(),
        body: ErrorState(error: state.loadError!, onRetry: _controller.reload),
      );
    }
    if (!_synced) {
      _synced = true;
      _title.text = state.title;
      _content.text = state.content;
      _location.text = state.location;
    }

    final referenced = [
      for (final id in state.images.keys)
        if (_content.text.contains('asset:$id')) state.images[id]!,
    ];

    final largeText = MediaQuery.textScalerOf(context).scale(14) > 18;

    return PopScope(
      canPop: !state.dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await _confirmDiscard();
        if (discard && context.mounted) context.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: Text(state.isPublished ? 'Edit story' : 'New story'),
          actions: [
            if (!state.isPublished && !largeText)
              TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(48, 40),
                ),
                onPressed: state.canSaveDraft && state.dirty
                    ? _saveDraft
                    : null,
                child: const Text('Save draft'),
              ),
            Padding(
              padding: const EdgeInsets.only(left: 4, right: AppSpacing.sm),
              child: FilledButton(
                onPressed: state.canPublish ? _publish : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(72, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                child: state.saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(state.isPublished ? 'Save' : 'Publish'),
              ),
            ),
            if (state.id != null || (!state.isPublished && largeText))
              PopupMenuButton<String>(
                tooltip: 'More',
                onSelected: (v) => v == 'draft' ? _saveDraft() : _delete(),
                itemBuilder: (_) => [
                  // With large text the draft button no longer fits the bar.
                  if (!state.isPublished && largeText)
                    PopupMenuItem(
                      value: 'draft',
                      enabled: state.canSaveDraft && state.dirty,
                      child: const Text('Save draft'),
                    ),
                  if (state.id != null)
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete story'),
                    ),
                ],
              ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              _CoverPicker(
                state: state,
                onPick: _controller.pickCover,
                onRemove: _controller.removeCover,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.gutter,
                  AppSpacing.lg,
                  AppSpacing.gutter,
                  0,
                ),
                child: TextField(
                  controller: _title,
                  onChanged: _controller.setTitle,
                  maxLength: 200,
                  maxLines: null,
                  textCapitalization: TextCapitalization.sentences,
                  style: AppTypography.serif(
                    size: 30,
                    weight: 700,
                    height: 1.25,
                  ).copyWith(color: theme.colorScheme.onSurface),
                  decoration: InputDecoration(
                    hintText: 'Title',
                    hintStyle: AppTypography.serif(
                      size: 30,
                      weight: 600,
                      height: 1.25,
                    ).copyWith(color: AppColors.inkFaint),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    counterText: '',
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.gutter,
                  AppSpacing.md,
                  AppSpacing.gutter,
                  0,
                ),
                child: TextField(
                  controller: _content,
                  onChanged: _controller.setContent,
                  maxLines: null,
                  minLines: 12,
                  maxLength: maxStoryLength,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  style: AppTypography.serif(
                    size: 19,
                    weight: 400,
                    height: 1.8,
                    letterSpacing: 0,
                  ).copyWith(color: theme.colorScheme.onSurface),
                  decoration: InputDecoration(
                    hintText: 'Tell your story…',
                    hintStyle: AppTypography.serif(
                      size: 19,
                      weight: 400,
                      height: 1.8,
                      letterSpacing: 0,
                    ).copyWith(color: AppColors.inkFaint),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    counterText: '',
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              if (referenced.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.gutter,
                    AppSpacing.md,
                    AppSpacing.gutter,
                    0,
                  ),
                  child: SizedBox(
                    height: 64,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final img in referenced)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.network(
                                img.url,
                                width: 64,
                                height: 64,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => SizedBox(
                                  width: 64,
                                  height: 64,
                                  child: ColoredBox(color: context.placeholder),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.gutter,
                  AppSpacing.lg,
                  AppSpacing.gutter,
                  0,
                ),
                child: PlaceField(
                  place: state.place,
                  onChanged: _controller.setPlace,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.gutter,
                  AppSpacing.lg,
                  AppSpacing.gutter,
                  0,
                ),
                child: TextField(
                  controller: _location,
                  onChanged: _controller.setLocation,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.place_outlined),
                    hintText: 'Where is this story set?',
                    counterText: '',
                  ),
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
                    Text('TAGS', style: theme.textTheme.labelMedium),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final c in categoryTags)
                          FilterChip(
                            label: Text(c),
                            selected: state.tags.contains(c),
                            onSelected: (_) => _controller.toggleTag(c),
                          ),
                        for (final t in state.tags.where(
                          (t) => !categoryTags.contains(t),
                        ))
                          InputChip(
                            label: Text('#$t'),
                            onDeleted: () => _controller.removeTag(t),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      controller: _tag,
                      onSubmitted: (_) => _addTag(),
                      decoration: InputDecoration(
                        hintText: 'Add your own tag',
                        suffixIcon: IconButton(
                          tooltip: 'Add tag',
                          icon: const Icon(Icons.add),
                          onPressed: _addTag,
                        ),
                      ),
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
        bottomNavigationBar: SafeArea(
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: theme.dividerTheme.color ?? AppColors.line,
                ),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _ToolButton(
                          label: 'Heading',
                          icon: Icons.title_rounded,
                          onTap: () => _applyEdit(
                            toggleLinePrefix(_content.text, _caret, '## '),
                          ),
                        ),
                        _ToolButton(
                          label: 'Quote',
                          icon: Icons.format_quote_rounded,
                          onTap: () => _applyEdit(
                            toggleLinePrefix(_content.text, _caret, '> '),
                          ),
                        ),
                        _ToolButton(
                          label: 'Photo',
                          icon: Icons.add_photo_alternate_outlined,
                          busy: state.uploads > 0,
                          onTap: state.uploads > 0 ? null : _insertPhoto,
                        ),
                      ],
                    ),
                  ),
                ),
                Text(
                  '${state.content.length}/$maxStoryLength',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.busy = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: label,
    onPressed: onTap,
    icon: busy
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(icon),
  );
}

class _CoverPicker extends StatelessWidget {
  const _CoverPicker({
    required this.state,
    required this.onPick,
    required this.onRemove,
  });
  final StoryEditorState state;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cover = state.cover;
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (cover != null)
            Image.network(
              cover.url,
              fit: BoxFit.cover,
              semanticLabel: 'Cover photo',
              errorBuilder: (_, _, _) => ColoredBox(color: context.placeholder),
            )
          else
            Semantics(
              button: true,
              label: 'Add a cover photo',
              child: InkWell(
                onTap: state.uploads > 0 ? null : onPick,
                child: ColoredBox(
                  color: theme.brightness == Brightness.dark
                      ? AppColors.nightCard
                      : context.placeholder,
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.add_photo_alternate_outlined,
                            size: 36,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Add a cover photo',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (state.uploads > 0)
            const ColoredBox(
              color: Colors.black26,
              child: Center(child: CircularProgressIndicator()),
            ),
          if (cover != null && state.uploads == 0)
            Positioned(
              right: 8,
              bottom: 8,
              child: Row(
                children: [
                  FilledButton.tonal(
                    onPressed: onPick,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 36),
                    ),
                    child: const Text('Change'),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Remove cover',
                    onPressed: onRemove,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
