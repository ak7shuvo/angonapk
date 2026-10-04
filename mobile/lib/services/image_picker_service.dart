import 'package:image_picker/image_picker.dart';

class PickedImage {
  const PickedImage({
    required this.bytes,
    required this.filename,
    required this.contentType,
  });
  final List<int> bytes;
  final String filename;
  final String contentType;
}

/// Local gallery access. Abstracted so the composer can be tested without a
/// platform picker.
abstract interface class ImagePickerService {
  /// Returns the images the user chose (empty if cancelled).
  Future<List<PickedImage>> pickImages({int limit = 10});

  /// Single image (avatars, covers).
  Future<PickedImage?> pickImage();
}

class DeviceImagePicker implements ImagePickerService {
  DeviceImagePicker([ImagePicker? picker]) : _picker = picker ?? ImagePicker();
  final ImagePicker _picker;

  // Downscale/compress on-device first: faster uploads, fewer rejected files.
  static const _maxEdge = 2560.0;
  static const _quality = 85;

  @override
  Future<List<PickedImage>> pickImages({int limit = 10}) async {
    final files = await _picker.pickMultiImage(
      maxWidth: _maxEdge,
      maxHeight: _maxEdge,
      imageQuality: _quality,
      limit: limit,
    );
    return [for (final f in files) await _convert(f)];
  }

  @override
  Future<PickedImage?> pickImage() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: _maxEdge,
      maxHeight: _maxEdge,
      imageQuality: _quality,
    );
    return file == null ? null : _convert(file);
  }

  Future<PickedImage> _convert(XFile file) async => PickedImage(
    bytes: await file.readAsBytes(),
    filename: file.name,
    contentType: contentTypeFor(file.name, file.mimeType),
  );
}

/// Best-effort content type from the picker's mime type or the file extension.
String contentTypeFor(String filename, [String? mime]) {
  if (mime != null && mime.startsWith('image/')) return mime;
  final ext = filename.toLowerCase().split('.').last;
  return switch (ext) {
    'png' => 'image/png',
    'webp' => 'image/webp',
    'gif' => 'image/gif',
    _ => 'image/jpeg',
  };
}
