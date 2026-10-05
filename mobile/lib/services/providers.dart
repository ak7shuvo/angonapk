import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../core/maps/map_provider.dart';
import '../core/maps/osm_map_adapter.dart';
import '../core/network/api_client.dart';
import '../features/auth/auth_controller.dart';
import '../repositories/auth_repository.dart';
import '../repositories/explore_repository.dart';
import '../repositories/health_repository.dart';
import '../repositories/media_repository.dart';
import '../repositories/notification_repository.dart';
import '../repositories/place_repository.dart';
import '../repositories/post_repository.dart';
import '../repositories/story_repository.dart';
import '../repositories/user_repository.dart';
import 'draft_store.dart';
import 'image_picker_service.dart';
import 'token_storage.dart';

final appConfigProvider = Provider<AppConfig>(
  (_) => AppConfig.fromEnvironment(),
);

final tokenStorageProvider = Provider<TokenStorage>(
  (_) => SecureTokenStorage(),
);

final apiClientProvider = Provider<ApiClient>((ref) {
  final client = HttpApiClient(
    config: ref.watch(appConfigProvider),
    tokenProvider: () => ref.read(tokenStorageProvider).read(),
    // A rejected token means the session is gone: drop to signed-out state.
    onUnauthorized: () =>
        ref.read(authControllerProvider.notifier).sessionExpired(),
  );
  ref.onDispose(client.close);
  return client;
});

final healthRepositoryProvider = Provider<HealthRepository>(
  (ref) => HealthRepository(ref.watch(apiClientProvider)),
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(apiClientProvider)),
);

final postRepositoryProvider = Provider<PostRepository>(
  (ref) => PostRepository(
    ref.watch(apiClientProvider),
    mediaBaseUrl: ref.watch(appConfigProvider).apiBaseUrl,
  ),
);

final mediaRepositoryProvider = Provider<MediaRepository>(
  (ref) => MediaRepository(
    ref.watch(apiClientProvider),
    mediaBaseUrl: ref.watch(appConfigProvider).apiBaseUrl,
  ),
);

final imagePickerProvider = Provider<ImagePickerService>(
  (_) => DeviceImagePicker(),
);

final draftStoreProvider = Provider<DraftStore>((_) => PrefsDraftStore());

final userRepositoryProvider = Provider<UserRepository>(
  (ref) => UserRepository(
    ref.watch(apiClientProvider),
    mediaBaseUrl: ref.watch(appConfigProvider).apiBaseUrl,
  ),
);

final storyRepositoryProvider = Provider<StoryRepository>(
  (ref) => StoryRepository(
    ref.watch(apiClientProvider),
    mediaBaseUrl: ref.watch(appConfigProvider).apiBaseUrl,
  ),
);

final placeRepositoryProvider = Provider<PlaceRepository>(
  (ref) => PlaceRepository(
    ref.watch(apiClientProvider),
    mediaBaseUrl: ref.watch(appConfigProvider).apiBaseUrl,
  ),
);

final exploreRepositoryProvider = Provider<ExploreRepository>(
  (ref) => ExploreRepository(
    ref.watch(apiClientProvider),
    mediaBaseUrl: ref.watch(appConfigProvider).apiBaseUrl,
  ),
);

/// The map implementation, chosen by `MAP_PROVIDER`. Null means "no map": the
/// Map screen then shows places as a list.
final mapAdapterProvider = Provider<MapProviderAdapter?>((ref) {
  final config = ref.watch(appConfigProvider);
  return switch (config.mapProvider) {
    MapProviderKind.osm => OsmMapAdapter(
      tileUrl: config.mapTileUrl,
      attribution: config.mapAttribution,
    ),
    MapProviderKind.none => null,
  };
});

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => NotificationRepository(ref.watch(apiClientProvider)),
);
