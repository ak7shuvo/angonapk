import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../models/post.dart';
import '../../models/uploaded_media.dart';
import '../../services/draft_store.dart';
import '../../services/image_picker_service.dart';
import '../../services/providers.dart';
import '../auth/auth_controller.dart';
import '../feed/feed_controller.dart';

const maxPostImages = 10;
const maxPostLength = 2000;
const maxTags = 8;
const _maxUploadBytes = 10 * 1024 * 1024;
const _allowedTypes = {'image/jpeg', 'image/png', 'image/webp'};
const _parallelUploads = 2;

enum UploadStatus { uploading, uploaded, failed }

/// One photo in the composer, from pick → upload → (maybe) attached to a post.
class Attachment {
  const Attachment({
    required this.localId,
    required this.image,
    this.status = UploadStatus.uploading,
    this.progress = 0,
    this.uploaded,
    this.error,
    this.queued = true,
  });

  final int localId;
  final PickedImage image;
  final UploadStatus status;
  final double progress;
  final UploadedMedia? uploaded;
  final String? error;

  /// True until the upload has actually started (waiting for a free slot).
  final bool queued;

  Attachment copyWith({
    UploadStatus? status,
    double? progress,
    UploadedMedia? uploaded,
    Object? error = _keep,
    bool? queued,
  }) => Attachment(
    localId: localId,
    image: image,
    status: status ?? this.status,
    progress: progress ?? this.progress,
    uploaded: uploaded ?? this.uploaded,
    error: identical(error, _keep) ? this.error : error as String?,
    queued: queued ?? this.queued,
  );
}

const _keep = Object();

class ComposerState {
  const ComposerState({
    this.text = '',
    this.location = '',
    this.tags = const [],
    this.attachments = const [],
    this.submitting = false,
    this.error,
    this.notice,
    this.restored = false,
  });

  final String text;
  final String location;
  final List<String> tags;
  final List<Attachment> attachments;
  final bool submitting;

  /// Last submit failure (kept so the user can retry without losing input).
  final String? error;

  /// Non-fatal message, e.g. a rejected file.
  final String? notice;

  /// True once the saved draft (if any) has been loaded.
  final bool restored;

  bool get hasUploading =>
      attachments.any((a) => a.status == UploadStatus.uploading);
  bool get hasFailed => attachments.any((a) => a.status == UploadStatus.failed);
  int get uploadedCount =>
      attachments.where((a) => a.status == UploadStatus.uploaded).length;
  bool get hasContent => text.trim().isNotEmpty || uploadedCount > 0;

  bool get canSubmit =>
      restored &&
      !submitting &&
      !hasUploading &&
      !hasFailed &&
      hasContent &&
      text.length <= maxPostLength;

  ComposerState copyWith({
    String? text,
    String? location,
    List<String>? tags,
    List<Attachment>? attachments,
    bool? submitting,
    Object? error = _keep,
    Object? notice = _keep,
    bool? restored,
  }) => ComposerState(
    text: text ?? this.text,
    location: location ?? this.location,
    tags: tags ?? this.tags,
    attachments: attachments ?? this.attachments,
    submitting: submitting ?? this.submitting,
    error: identical(error, _keep) ? this.error : error as String?,
    notice: identical(notice, _keep) ? this.notice : notice as String?,
    restored: restored ?? this.restored,
  );
}

/// Draft-friendly composer: text, location and tags persist locally as you
/// type; photos upload as soon as they are picked, with progress and retry.
class ComposerController extends Notifier<ComposerState> {
  int _nextId = 0;
  int _activeUploads = 0;
  late String _userId;

  @override
  ComposerState build() {
    final auth = ref.watch(authControllerProvider);
    _userId = auth is Authenticated ? auth.user.id : '';
    Future.microtask(_restoreDraft);
    return const ComposerState();
  }

  Future<void> _restoreDraft() async {
    final draft = _userId.isEmpty
        ? null
        : await ref.read(draftStoreProvider).load(_userId);
    if (!ref.mounted) return;
    state = state.copyWith(
      text: state.text.isEmpty ? draft?.text : null,
      location: state.location.isEmpty ? draft?.location : null,
      tags: state.tags.isEmpty ? draft?.tags : null,
      restored: true,
    );
  }

  void _persistDraft() {
    if (_userId.isEmpty) return;
    ref
        .read(draftStoreProvider)
        .save(
          _userId,
          PostDraft(
            text: state.text,
            location: state.location,
            tags: state.tags,
          ),
        );
  }

  void setText(String value) {
    state = state.copyWith(text: value, error: null);
    _persistDraft();
  }

  void setLocation(String value) {
    state = state.copyWith(location: value, error: null);
    _persistDraft();
  }

  /// Returns false if the tag was rejected (invalid, duplicate or over the limit).
  bool addTag(String raw) {
    final tag = normalizeTag(raw);
    if (tag == null ||
        state.tags.contains(tag) ||
        state.tags.length >= maxTags) {
      return false;
    }
    state = state.copyWith(tags: [...state.tags, tag], error: null);
    _persistDraft();
    return true;
  }

  void removeTag(String tag) {
    state = state.copyWith(tags: [...state.tags]..remove(tag));
    _persistDraft();
  }

  void toggleTag(String tag) {
    state.tags.contains(tag) ? removeTag(tag) : addTag(tag);
  }

  void clearNotice() => state = state.copyWith(notice: null);

  Future<void> pickPhotos() async {
    final room = maxPostImages - state.attachments.length;
    if (room <= 0) {
      state = state.copyWith(
        notice: 'You can add up to $maxPostImages photos.',
      );
      return;
    }
    final picked = await ref.read(imagePickerProvider).pickImages(limit: room);
    addImages(picked);
  }

  void addImages(List<PickedImage> images) {
    final accepted = <Attachment>[];
    String? notice;
    for (final image in images) {
      if (state.attachments.length + accepted.length >= maxPostImages) {
        notice = 'You can add up to $maxPostImages photos.';
        break;
      }
      if (!_allowedTypes.contains(image.contentType)) {
        notice = 'Only JPEG, PNG and WebP photos are supported.';
        continue;
      }
      if (image.bytes.length > _maxUploadBytes) {
        notice = '“${image.filename}” is larger than 10 MB.';
        continue;
      }
      accepted.add(Attachment(localId: _nextId++, image: image));
    }
    state = state.copyWith(
      attachments: [...state.attachments, ...accepted],
      notice: notice,
    );
    _pump();
  }

  void _pump() {
    for (final a in state.attachments) {
      if (_activeUploads >= _parallelUploads) return;
      if (a.status == UploadStatus.uploading && a.queued) {
        _activeUploads++;
        _update(a.localId, (x) => x.copyWith(queued: false));
        _upload(a.localId);
      }
    }
  }

  Attachment? _find(int id) {
    for (final a in state.attachments) {
      if (a.localId == id) return a;
    }
    return null;
  }

  void _update(int id, Attachment Function(Attachment) fn) {
    state = state.copyWith(
      attachments: [
        for (final a in state.attachments) a.localId == id ? fn(a) : a,
      ],
    );
  }

  Future<void> _upload(int id) async {
    final attachment = _find(id);
    if (attachment == null) return;
    try {
      final media = await ref
          .read(mediaRepositoryProvider)
          .uploadImage(
            bytes: attachment.image.bytes,
            filename: attachment.image.filename,
            contentType: attachment.image.contentType,
            onProgress: (p) {
              if (ref.mounted && _find(id) != null) {
                _update(id, (a) => a.copyWith(progress: p));
              }
            },
          );
      if (!ref.mounted) return;
      if (_find(id) == null) {
        // Removed while uploading: discard the orphan on the server.
        ref.read(mediaRepositoryProvider).deleteUnattached(media.id).ignore();
      } else {
        _update(
          id,
          (a) => a.copyWith(
            status: UploadStatus.uploaded,
            progress: 1,
            uploaded: media,
            error: null,
          ),
        );
      }
    } catch (e) {
      if (!ref.mounted) return;
      final message = e is AppException ? e.message : 'Upload failed.';
      if (_find(id) != null) {
        _update(
          id,
          (a) => a.copyWith(status: UploadStatus.failed, error: message),
        );
      }
    } finally {
      _activeUploads--;
      if (ref.mounted) _pump();
    }
  }

  void retryUpload(int id) {
    _update(
      id,
      (a) => a.copyWith(
        status: UploadStatus.uploading,
        progress: 0,
        error: null,
        queued: true,
      ),
    );
    _pump();
  }

  void removeAttachment(int id) {
    final a = _find(id);
    if (a == null) return;
    state = state.copyWith(
      attachments: [...state.attachments]..removeWhere((x) => x.localId == id),
    );
    if (a.uploaded != null) {
      ref
          .read(mediaRepositoryProvider)
          .deleteUnattached(a.uploaded!.id)
          .ignore();
    }
  }

  /// Creates the post. On success the draft is cleared and the post is added to
  /// the top of the feed; on failure everything the user typed is kept.
  Future<Post?> submit() async {
    if (!state.canSubmit) return null;
    state = state.copyWith(submitting: true, error: null);
    try {
      final post = await ref
          .read(postRepositoryProvider)
          .createPost(
            body: state.text.trim().isEmpty ? null : state.text.trim(),
            locationText: state.location.trim().isEmpty
                ? null
                : state.location.trim(),
            mediaIds: [for (final a in state.attachments) a.uploaded!.id],
            tags: state.tags,
          );
      if (_userId.isNotEmpty) await ref.read(draftStoreProvider).clear(_userId);
      ref.read(feedControllerProvider.notifier).prependPost(post);
      ref.read(followingFeedProvider.notifier).prependPost(post);
      if (ref.mounted) state = ComposerState(restored: true);
      return post;
    } catch (e) {
      if (ref.mounted) {
        state = state.copyWith(
          submitting: false,
          error: e is AppException
              ? e.message
              : 'Could not share your post. Please try again.',
        );
      }
      return null;
    }
  }
}

/// Mirrors the server's tag rules: letters/digits/underscore (any script,
/// including Bengali combining marks), 2–30 chars, no leading '#'.
String? normalizeTag(String raw) {
  final tag = raw.trim().replaceFirst(RegExp(r'^#+'), '').trim().toLowerCase();
  if (tag.length < 2 || tag.length > 30) return null;
  final valid = RegExp(r'^[\p{L}\p{N}\p{M}_]+$', unicode: true);
  return valid.hasMatch(tag) ? tag : null;
}

final composerControllerProvider =
    NotifierProvider<ComposerController, ComposerState>(ComposerController.new);
