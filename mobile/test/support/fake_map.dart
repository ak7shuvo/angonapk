import 'package:angon/core/maps/map_provider.dart';
import 'package:flutter/material.dart';

/// Map stand-in for widget tests: every marker is a tappable button, and tests
/// can simulate the user panning via [pan].
class FakeMapAdapter implements MapProviderAdapter {
  @override
  String get name => 'fake';

  ValueChanged<MapViewport>? _onViewport;
  final focuses = <MapFocus>[];
  VoidCallback? _tilesFailed;

  /// Simulates a user pan to a viewport.
  void pan(GeoBounds bounds) => _onViewport?.call(
    MapViewport(
      center: GeoPoint(
        (bounds.south + bounds.north) / 2,
        (bounds.west + bounds.east) / 2,
      ),
      zoom: 9,
      bounds: bounds,
      byUser: true,
    ),
  );

  void failTiles() => _tilesFailed?.call();

  @override
  Widget build(
    BuildContext context, {
    required MapViewport initial,
    required List<MapMarkerData> markers,
    required ValueChanged<MapMarkerData> onMarkerTap,
    required ValueChanged<MapViewport> onViewportChanged,
    String? selectedId,
    MapFocus? focus,
    VoidCallback? onTilesFailed,
  }) {
    _onViewport = onViewportChanged;
    _tilesFailed = onTilesFailed;
    if (focus != null && (focuses.isEmpty || !identical(focuses.last, focus))) {
      focuses.add(focus);
    }
    return ColoredBox(
      color: Colors.blueGrey.shade50,
      child: Wrap(
        children: [
          for (final m in markers)
            TextButton(
              key: ValueKey('marker-${m.id}'),
              onPressed: () => onMarkerTap(m),
              child: Text('pin:${m.label}${m.id == selectedId ? '*' : ''}'),
            ),
        ],
      ),
    );
  }
}
