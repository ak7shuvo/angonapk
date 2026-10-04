import '../core/network/api_client.dart';
import '../models/health_status.dart';

class HealthRepository {
  const HealthRepository(this._api);
  final ApiClient _api;

  Future<HealthStatus> check() async {
    final json = await _api.get('/health') as Map<String, dynamic>;
    return HealthStatus.fromJson(json);
  }
}
