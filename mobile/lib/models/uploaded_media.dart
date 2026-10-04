/// A file already uploaded to the server (response of `POST /media`).
class UploadedMedia {
  const UploadedMedia({
    required this.id,
    required this.url,
    this.width,
    this.height,
  });

  final String id;

  /// Absolute URL (storage-relative paths are resolved against the API origin).
  final String url;
  final int? width;
  final int? height;

  factory UploadedMedia.fromJson(
    Map<String, dynamic> json, {
    String mediaBaseUrl = '',
  }) {
    final raw = json['url'] as String;
    return UploadedMedia(
      id: json['id'] as String,
      url: raw.startsWith('/') ? '$mediaBaseUrl$raw' : raw,
      width: json['width'] as int?,
      height: json['height'] as int?,
    );
  }
}
