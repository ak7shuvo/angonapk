import '../core/network/api_client.dart';
import '../models/report.dart';

/// Files moderation reports (`POST /reports`).
class ReportRepository {
  const ReportRepository(this._api);
  final ApiClient _api;

  Future<void> report({
    required ReportTarget target,
    required String targetId,
    required ReportReason reason,
    String? details,
  }) async {
    final note = details?.trim();
    await _api.post(
      '/reports',
      body: {
        'target_type': target.apiName,
        'target_id': targetId,
        'reason': reason.apiName,
        if (note != null && note.isNotEmpty) 'details': note,
      },
    );
  }
}
