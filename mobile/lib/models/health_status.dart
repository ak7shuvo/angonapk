/// Response of `GET /api/v1/health`.
class HealthStatus {
  const HealthStatus({
    required this.status,
    required this.environment,
    required this.database,
  });

  final String status;
  final String environment;

  /// `ok` or `unavailable`.
  final String database;

  bool get isHealthy => status == 'ok';

  factory HealthStatus.fromJson(Map<String, dynamic> json) => HealthStatus(
    status: json['status'] as String,
    environment: json['environment'] as String,
    database: json['database'] as String,
  );
}
