import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../core/network/api_client.dart';
import '../repositories/health_repository.dart';

final appConfigProvider = Provider<AppConfig>(
  (_) => AppConfig.fromEnvironment(),
);

final apiClientProvider = Provider<ApiClient>((ref) {
  final client = HttpApiClient(config: ref.watch(appConfigProvider));
  ref.onDispose(client.close);
  return client;
});

final healthRepositoryProvider = Provider<HealthRepository>(
  (ref) => HealthRepository(ref.watch(apiClientProvider)),
);
