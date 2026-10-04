import 'package:angon/app.dart';
import 'package:angon/features/auth/auth_controller.dart';
import 'package:angon/services/providers.dart';
import 'package:angon/services/draft_store.dart';
import 'package:angon/services/token_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'fake_backend.dart';
import 'fake_picker.dart';

/// Builds the real app (real router, controller, repository, screens) with
/// only the HTTP layer and token store swapped for test doubles.
Widget buildTestApp(
  FakeBackend backend,
  InMemoryTokenStorage storage, {
  List<Override> overrides = const [],
  FakeImagePicker? picker,
  InMemoryDraftStore? drafts,
}) {
  return ProviderScope(
    overrides: [
      draftStoreProvider.overrideWithValue(drafts ?? InMemoryDraftStore()),
      imagePickerProvider.overrideWithValue(picker ?? FakeImagePicker()),
      tokenStorageProvider.overrideWithValue(storage),
      apiClientProvider.overrideWith((ref) {
        backend.currentToken = () => storage.current;
        backend.onUnauthorized = () =>
            ref.read(authControllerProvider.notifier).sessionExpired();
        return backend;
      }),
      ...overrides,
    ],
    child: const AngonApp(),
  );
}
