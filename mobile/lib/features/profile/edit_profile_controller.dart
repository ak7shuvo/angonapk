import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/unchanged.dart';
import '../../models/user.dart';
import '../../services/image_picker_service.dart';
import '../../services/providers.dart';
import '../auth/auth_controller.dart';

/// A profile image that is either the saved one or a fresh upload.
class ProfileImage {
  const ProfileImage({this.id, this.url});

  /// Set for a new upload (to be attached on save); null for the saved image.
  final String? id;
  final String? url;
}

class EditProfileState {
  const EditProfileState({
    this.displayName = '',
    this.bio = '',
    this.location = '',
    this.creatorType,
    this.avatar,
    this.cover,
    this.avatarChanged = false,
    this.coverChanged = false,
    this.uploading = 0,
    this.saving = false,
    this.dirty = false,
    this.error,
    this.notice,
  });

  final String displayName;
  final String bio;
  final String location;
  final CreatorType? creatorType;
  final ProfileImage? avatar;
  final ProfileImage? cover;
  final bool avatarChanged;
  final bool coverChanged;
  final int uploading;
  final bool saving;
  final bool dirty;
  final String? error;
  final String? notice;

  bool get canSave =>
      dirty &&
      !saving &&
      uploading == 0 &&
      displayName.trim().isNotEmpty &&
      creatorType != null;

  EditProfileState copyWith({
    String? displayName,
    String? bio,
    String? location,
    CreatorType? creatorType,
    Object? avatar = _keep,
    Object? cover = _keep,
    bool? avatarChanged,
    bool? coverChanged,
    int? uploading,
    bool? saving,
    bool? dirty,
    Object? error = _keep,
    Object? notice = _keep,
  }) => EditProfileState(
    displayName: displayName ?? this.displayName,
    bio: bio ?? this.bio,
    location: location ?? this.location,
    creatorType: creatorType ?? this.creatorType,
    avatar: identical(avatar, _keep) ? this.avatar : avatar as ProfileImage?,
    cover: identical(cover, _keep) ? this.cover : cover as ProfileImage?,
    avatarChanged: avatarChanged ?? this.avatarChanged,
    coverChanged: coverChanged ?? this.coverChanged,
    uploading: uploading ?? this.uploading,
    saving: saving ?? this.saving,
    dirty: dirty ?? this.dirty,
    error: identical(error, _keep) ? this.error : error as String?,
    notice: identical(notice, _keep) ? this.notice : notice as String?,
  );
}

const _keep = Object();

class EditProfileController extends Notifier<EditProfileState> {
  @override
  EditProfileState build() {
    final auth = ref.read(authControllerProvider);
    if (auth is! Authenticated) return const EditProfileState();
    final p = auth.user.profile;
    return EditProfileState(
      displayName: p.displayName ?? '',
      bio: p.bio ?? '',
      location: p.location ?? '',
      creatorType: p.creatorType,
      avatar: p.avatarUrl == null ? null : ProfileImage(url: p.avatarUrl),
      cover: p.coverUrl == null ? null : ProfileImage(url: p.coverUrl),
    );
  }

  void setName(String v) =>
      state = state.copyWith(displayName: v, dirty: true, error: null);
  void setBio(String v) => state = state.copyWith(bio: v, dirty: true);
  void setLocation(String v) =>
      state = state.copyWith(location: v, dirty: true);
  void setType(CreatorType t) =>
      state = state.copyWith(creatorType: t, dirty: true);
  void clearNotice() => state = state.copyWith(notice: null);

  Future<ProfileImage?> _upload(PickedImage? image, String purpose) async {
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
    state = state.copyWith(uploading: state.uploading + 1);
    try {
      final media = await ref
          .read(mediaRepositoryProvider)
          .uploadImage(
            bytes: image.bytes,
            filename: image.filename,
            contentType: image.contentType,
            purpose: purpose,
          );
      return ProfileImage(id: media.id, url: media.url);
    } catch (e) {
      if (ref.mounted) {
        state = state.copyWith(
          notice: e is AppException ? e.message : 'Upload failed.',
        );
      }
      return null;
    } finally {
      if (ref.mounted) state = state.copyWith(uploading: state.uploading - 1);
    }
  }

  Future<void> pickAvatar() async {
    final image = await _upload(
      await ref.read(imagePickerProvider).pickImage(),
      'avatar',
    );
    if (image != null && ref.mounted) {
      state = state.copyWith(avatar: image, avatarChanged: true, dirty: true);
    }
  }

  Future<void> pickCover() async {
    final image = await _upload(
      await ref.read(imagePickerProvider).pickImage(),
      'image',
    );
    if (image != null && ref.mounted) {
      state = state.copyWith(cover: image, coverChanged: true, dirty: true);
    }
  }

  void removeAvatar() =>
      state = state.copyWith(avatar: null, avatarChanged: true, dirty: true);
  void removeCover() =>
      state = state.copyWith(cover: null, coverChanged: true, dirty: true);

  /// Saves to the server; returns true on success.
  Future<bool> save() async {
    if (!state.canSave) return false;
    state = state.copyWith(saving: true, error: null);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .updateProfile(
            displayName: state.displayName.trim(),
            bio: state.bio.trim(),
            location: state.location.trim(),
            creatorType: state.creatorType,
            // Only send images that changed: a new upload's id, or null to remove.
            avatarMediaId: state.avatarChanged ? state.avatar?.id : unchanged,
            coverMediaId: state.coverChanged ? state.cover?.id : unchanged,
          );
      if (ref.mounted) state = state.copyWith(saving: false, dirty: false);
      return true;
    } catch (e) {
      if (ref.mounted) {
        state = state.copyWith(
          saving: false,
          error: e is AppException
              ? e.message
              : 'Could not save your profile. Please try again.',
        );
      }
      return false;
    }
  }
}

final editProfileProvider =
    NotifierProvider.autoDispose<EditProfileController, EditProfileState>(
      EditProfileController.new,
    );
