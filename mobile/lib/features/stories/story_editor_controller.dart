import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../models/place.dart';
import '../../models/story.dart';
import '../../models/uploaded_media.dart';
import '../../services/image_picker_service.dart';
import '../../services/providers.dart';
import '../composer/composer_controller.dart' show normalizeTag, maxTags;
import 'story_markup.dart';

const maxStoryLength = 50000;

class StoryEditorState {
  const StoryEditorState({
    this.loading = false,
    this.loadError,
    this.id,
    this.slug,
    this.status = StoryStatus.draft,
    this.title = '',
    this.content = '',
    this.location = '',
    this.tags = const [],
    this.cover,
    this.place,
    this.images = const {},
    this.uploads = 0,
    this.saving = false,
    this.dirty = false,
    this.error,
    this.notice,
  });

  final bool loading;
  final Object? loadError;

  /// Null until the story has been saved once.
  final String? id;
  final String? slug;
  final StoryStatus status;
  final String title;
  final String content;
  final String location;
  final List<String> tags;
  final StoryImage? cover;
  final PlaceBrief? place;

  /// Inline images known to the editor, by asset id (for thumbnails).
  final Map<String, StoryImage> images;
  final int uploads;
  final bool saving;
  final bool dirty;
  final String? error;
  final String? notice;

  bool get isPublished => status == StoryStatus.published;
  bool get busy => saving || uploads > 0;
  bool get canPublish =>
      title.trim().isNotEmpty &&
      content.trim().isNotEmpty &&
      !busy &&
      content.length <= maxStoryLength;
  bool get canSaveDraft =>
      !busy &&
      (title.trim().isNotEmpty || content.trim().isNotEmpty || id != null);

  StoryEditorState copyWith({
    bool? loading,
    Object? loadError = _keep,
    String? id,
    String? slug,
    StoryStatus? status,
    String? title,
    String? content,
    String? location,
    List<String>? tags,
    Object? cover = _keep,
    Object? place = _keep,
    Map<String, StoryImage>? images,
    int? uploads,
    bool? saving,
    bool? dirty,
    Object? error = _keep,
    Object? notice = _keep,
  }) => StoryEditorState(
    loading: loading ?? this.loading,
    loadError: identical(loadError, _keep) ? this.loadError : loadError,
    id: id ?? this.id,
    slug: slug ?? this.slug,
    status: status ?? this.status,
    title: title ?? this.title,
    content: content ?? this.content,
    location: location ?? this.location,
    tags: tags ?? this.tags,
    cover: identical(cover, _keep) ? this.cover : cover as StoryImage?,
    place: identical(place, _keep) ? this.place : place as PlaceBrief?,
    images: images ?? this.images,
    uploads: uploads ?? this.uploads,
    saving: saving ?? this.saving,
    dirty: dirty ?? this.dirty,
    error: identical(error, _keep) ? this.error : error as String?,
    notice: identical(notice, _keep) ? this.notice : notice as String?,
  );
}

const _keep = Object();

/// Create or edit a story. [storyId] null starts a new draft.
class StoryEditorController extends Notifier<StoryEditorState> {
  StoryEditorController(this.storyId);
  final String? storyId;

  @override
  StoryEditorState build() {
    if (storyId != null) {
      Future.microtask(_load);
    }
    return StoryEditorState(loading: storyId != null);
  }

  Future<void> _load() async {
    try {
      final story = await ref.read(storyRepositoryProvider).get(storyId!);
      if (!ref.mounted) return;
      state = StoryEditorState(
        id: story.id,
        slug: story.slug,
        status: story.status,
        title: story.title,
        content: story.content,
        location: story.locationText ?? '',
        tags: story.tags,
        cover: story.cover,
        place: story.place,
        images: {for (final m in story.media) m.id: m},
      );
    } catch (e) {
      if (ref.mounted) state = StoryEditorState(loadError: e);
    }
  }

  Future<void> reload() {
    state = StoryEditorState(loading: storyId != null);
    return _load();
  }

  void setTitle(String v) =>
      state = state.copyWith(title: v, dirty: true, error: null);
  void setContent(String v) =>
      state = state.copyWith(content: v, dirty: true, error: null);
  void setLocation(String v) =>
      state = state.copyWith(location: v, dirty: true);
  void clearNotice() => state = state.copyWith(notice: null);

  bool addTag(String raw) {
    final tag = normalizeTag(raw);
    if (tag == null ||
        state.tags.contains(tag) ||
        state.tags.length >= maxTags) {
      return false;
    }
    state = state.copyWith(tags: [...state.tags, tag], dirty: true);
    return true;
  }

  void removeTag(String tag) =>
      state = state.copyWith(tags: [...state.tags]..remove(tag), dirty: true);

  void toggleTag(String tag) =>
      state.tags.contains(tag) ? removeTag(tag) : addTag(tag);

  Future<UploadedMedia?> _pickAndUpload(PickedImage? image) async {
    if (image == null) return null;
    if (!{
      'image/jpeg',
      'image/png',
      'image/webp',
    }.contains(image.contentType)) {
      state = state.copyWith(
        notice: 'Only JPEG, PNG and WebP photos are supported.',
      );
      return null;
    }
    if (image.bytes.length > 10 * 1024 * 1024) {
      state = state.copyWith(notice: 'That photo is larger than 10 MB.');
      return null;
    }
    state = state.copyWith(uploads: state.uploads + 1);
    try {
      return await ref
          .read(mediaRepositoryProvider)
          .uploadImage(
            bytes: image.bytes,
            filename: image.filename,
            contentType: image.contentType,
          );
    } catch (e) {
      if (ref.mounted) {
        state = state.copyWith(
          notice: e is AppException ? e.message : 'Upload failed.',
        );
      }
      return null;
    } finally {
      if (ref.mounted) state = state.copyWith(uploads: state.uploads - 1);
    }
  }

  Future<void> pickCover() async {
    final media = await _pickAndUpload(
      await ref.read(imagePickerProvider).pickImage(),
    );
    if (media == null || !ref.mounted) return;
    state = state.copyWith(
      cover: StoryImage(
        id: media.id,
        url: media.url,
        width: media.width,
        height: media.height,
      ),
      dirty: true,
    );
  }

  void setPlace(PlaceBrief? place) =>
      state = state.copyWith(place: place, dirty: true);

  void removeCover() => state = state.copyWith(cover: null, dirty: true);

  /// Uploads a photo for the body and returns the token to insert (or null).
  Future<String?> addInlineImage() async {
    final media = await _pickAndUpload(
      await ref.read(imagePickerProvider).pickImage(),
    );
    if (media == null || !ref.mounted) return null;
    state = state.copyWith(
      images: {
        ...state.images,
        media.id: StoryImage(
          id: media.id,
          url: media.url,
          width: media.width,
          height: media.height,
        ),
      },
    );
    return imageToken(media.id);
  }

  /// Saves as a draft (or saves edits of a published story). With [publish]
  /// the story is also published. Returns the saved story, or null on failure.
  Future<Story?> save({bool publish = false}) async {
    if (state.busy) return null;
    if (publish && !state.canPublish) {
      state = state.copyWith(
        error: 'Add a title and some content before publishing.',
      );
      return null;
    }
    state = state.copyWith(saving: true, error: null);
    try {
      final repo = ref.read(storyRepositoryProvider);
      final location = state.location.trim().isEmpty
          ? null
          : state.location.trim();
      Story story;
      if (state.id == null) {
        story = await repo.create(
          title: state.title.trim(),
          content: state.content,
          coverAssetId: state.cover?.id,
          locationText: location,
          placeId: state.place?.id,
          tags: state.tags,
          publish: publish,
        );
      } else {
        story = await repo.update(
          state.id!,
          title: state.title.trim(),
          content: state.content,
          coverAssetId: state.cover?.id,
          locationText: location,
          placeId: state.place?.id,
          tags: state.tags,
        );
        if (publish && story.status != StoryStatus.published) {
          story = await repo.publish(story.id);
        }
      }
      if (!ref.mounted) return story;
      state = state.copyWith(
        id: story.id,
        slug: story.slug,
        status: story.status,
        cover: story.cover,
        place: story.place,
        images: {for (final m in story.media) m.id: m},
        saving: false,
        dirty: false,
      );
      return story;
    } catch (e) {
      if (ref.mounted) {
        state = state.copyWith(
          saving: false,
          error: e is AppException
              ? e.message
              : 'Could not save your story. Please try again.',
        );
      }
      return null;
    }
  }

  Future<void> deleteStory() async {
    final id = state.id;
    if (id == null) return;
    await ref.read(storyRepositoryProvider).delete(id);
  }
}

final storyEditorProvider = NotifierProvider.autoDispose
    .family<StoryEditorController, StoryEditorState, String?>(
      StoryEditorController.new,
    );
