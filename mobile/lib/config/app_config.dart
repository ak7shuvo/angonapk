/// Build-time environment configuration.
///
/// Values come from `--dart-define` so no secrets or hosts are hard-coded:
///
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
///
/// `10.0.2.2` is the Android emulator's alias for the host machine.
enum AppEnvironment { development, staging, production }

class AppConfig {
  const AppConfig({required this.environment, required this.apiBaseUrl});

  final AppEnvironment environment;
  final String apiBaseUrl;

  static const String apiVersionPath = '/api/v1';

  bool get isProduction => environment == AppEnvironment.production;

  /// Reads configuration from compile-time `--dart-define` values.
  factory AppConfig.fromEnvironment() {
    const env = String.fromEnvironment('APP_ENV', defaultValue: 'development');
    const baseUrl = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://10.0.2.2:8000',
    );
    return AppConfig(
      environment: AppEnvironment.values.firstWhere(
        (e) => e.name == env,
        orElse: () => AppEnvironment.development,
      ),
      apiBaseUrl: baseUrl,
    );
  }
}
