import 'package:angon/services/image_picker_service.dart';

PickedImage fakeImage(
  String name, {
  String type = 'image/png',
  int size = 1024,
}) => PickedImage(
  bytes: List<int>.filled(size, 7),
  filename: name,
  contentType: type,
);

/// Returns whatever the test queues; never touches the platform.
class FakeImagePicker implements ImagePickerService {
  List<PickedImage> next = [];

  @override
  Future<List<PickedImage>> pickImages({int limit = 10}) async =>
      next.take(limit).toList();

  @override
  Future<PickedImage?> pickImage() async => next.isEmpty ? null : next.first;
}
