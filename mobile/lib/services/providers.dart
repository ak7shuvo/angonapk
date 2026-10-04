import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../core/network/api_client.dart';
import '../features/auth/auth_controller.dart';
import '../repositories/auth_repository.dart';
import '../repositories/health_repository.dart';
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
