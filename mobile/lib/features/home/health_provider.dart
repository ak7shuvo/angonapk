import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/health_status.dart';
import '../../services/providers.dart';

/// Backend reachability, shown as a development status chip on Home.
final healthProvider = FutureProvider.autoDispose<HealthStatus>(
  (ref) => ref.watch(healthRepositoryProvider).check(),
  // A dev status probe: surface failures immediately instead of auto-retrying.
  retry: (_, _) => null,
);
