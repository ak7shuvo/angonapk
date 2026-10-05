/// Build-time environment configuration.
///
/// Values come from `--dart-define` so no secrets or hosts are hard-coded:
///
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
///
/// or collect them in a JSON file (see `config/dev.example.json`):
///
///   flutter run --dart-define-from-file=config/dev.json
///
/// `10.0.2.2` is the Android emulator's alias for the host machine.
enum AppEnvironment { development, staging, production }

/// Which map implementation to use (see `core/maps`).
enum MapProviderKind {
  /// Raster tiles through flutter_map (OpenStreetMap-compatible tile server).
  osm,

  /// No map: the Map screen shows a list of places instead.
  none,
}

class AppConfig {
  const AppConfig({
    required this.environment,
    required this.apiBaseUrl,
    this.mapProvider = MapProviderKind.osm,
    this.mapTileUrl = defaultTileUrl,
    this.mapAttribution = defaultAttribution,
  });

  final AppEnvironment environment;
  final String apiBaseUrl;
  final MapProviderKind mapProvider;

  /// Raster tile URL template with {z}/{x}/{y}. The default is the public
  /// OpenStreetMap server, which is meant for light use only; point
  /// `MAP_TILE_URL` at a tile provider you have an agreement with for real traffic.
  final String mapTileUrl;
  final String mapAttribution;

  static const String apiVersionPath = '/api/v1';
  static const String defaultTileUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const String defaultAttribution = '© OpenStreetMap contributors';

  bool get isProduction => environment == AppEnvironment.production;

  /// Reads configuration from compile-time `--dart-define` values.
  factory AppConfig.fromEnvironment() {
    const env = String.fromEnvironment('APP_ENV', defaultValue: 'development');
    const baseUrl = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://10.0.2.2:8000',
    );
    const map = String.fromEnvironment('MAP_PROVIDER', defaultValue: 'osm');
    return AppConfig(
      environment: AppEnvironment.values.firstWhere(
        (e) => e.name == env,
        orElse: () => AppEnvironment.development,
      ),
      apiBaseUrl: baseUrl,
      mapProvider: MapProviderKind.values.firstWhere(
        (e) => e.name == map,
        orElse: () => MapProviderKind.osm,
      ),
      mapTileUrl: const String.fromEnvironment(
        'MAP_TILE_URL',
        defaultValue: defaultTileUrl,
      ),
      mapAttribution: const String.fromEnvironment(
        'MAP_ATTRIBUTION',
        defaultValue: defaultAttribution,
      ),
    );
  }
}
