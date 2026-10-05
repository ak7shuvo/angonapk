import 'package:flutter/widgets.dart';

/// Provider-neutral map types. Screens only know these, so the underlying map
/// SDK (flutter_map today; Google/Mapbox later) can be swapped in one place.
class GeoPoint {
  const GeoPoint(this.lat, this.lng);
  final double lat;
  final double lng;

  @override
  bool operator ==(Object other) =>
      other is GeoPoint && other.lat == lat && other.lng == lng;

  @override
  int get hashCode => Object.hash(lat, lng);
}

class GeoBounds {
  const GeoBounds({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });
  final double south;
  final double west;
  final double north;
  final double east;

  /// Smallest box around [points] (null if empty).
  static GeoBounds? around(Iterable<GeoPoint> points) {
    if (points.isEmpty) return null;
    var s = 90.0, n = -90.0, w = 180.0, e = -180.0;
    for (final p in points) {
      if (p.lat < s) s = p.lat;
      if (p.lat > n) n = p.lat;
      if (p.lng < w) w = p.lng;
      if (p.lng > e) e = p.lng;
    }
    return GeoBounds(south: s, west: w, north: n, east: e);
  }
}

class MapMarkerData {
  const MapMarkerData({
    required this.id,
    required this.point,
    required this.label,
  });
  final String id;
  final GeoPoint point;
  final String label;
}

/// Where the camera currently is.
class MapViewport {
  const MapViewport({
    required this.center,
    required this.zoom,
    this.bounds,
    this.byUser = false,
  });
  final GeoPoint center;
  final double zoom;
  final GeoBounds? bounds;

  /// True when the user panned/zoomed (as opposed to a programmatic move).
  final bool byUser;
}

/// A request to move the camera. A *new instance* triggers a move.
class MapFocus {
  const MapFocus.point(GeoPoint this.point, {this.zoom = 11}) : fit = null;
  const MapFocus.fit(GeoBounds this.fit) : point = null, zoom = null;

  final GeoPoint? point;
  final double? zoom;
  final GeoBounds? fit;
}

/// Renders a map. Implementations must never throw when tiles fail to load.
abstract interface class MapProviderAdapter {
  String get name;

  Widget build(
    BuildContext context, {
    required MapViewport initial,
    required List<MapMarkerData> markers,
    required ValueChanged<MapMarkerData> onMarkerTap,
    required ValueChanged<MapViewport> onViewportChanged,
    String? selectedId,
    MapFocus? focus,
    VoidCallback? onTilesFailed,
  });
}
