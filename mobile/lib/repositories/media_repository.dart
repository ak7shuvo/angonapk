import '../core/network/api_client.dart';
import '../models/uploaded_media.dart';

/// Uploads images to `/media`. The server validates, re-encodes and stores them;
/// the returned id is what posts, stories and profiles reference.
class MediaRepository {
  const MediaRepository(this._api, {required this.mediaBaseUrl});
  final ApiClient _api;
  final String mediaBaseUrl;

  Future<UploadedMedia> uploadImage({
    required List<int> bytes,
    required String filename,
    required String contentType,
    void Function(double progress)? onProgress,
    String purpose = 'image',
  }) async {
    final json = await _api.upload(
      purpose == 'image' ? '/media' : '/media?purpose=$purpose',
      bytes: bytes,
      filename: filename,
      contentType: contentType,
      onProgress: onProgress,
    );
    return UploadedMedia.fromJson(
      json as Map<String, dynamic>,
      mediaBaseUrl: mediaBaseUrl,
    );
  }

  /// Discards an uploaded image that was never attached to content.
  Future<void> deleteUnattached(String id) => _api.delete('/media/$id');
}
