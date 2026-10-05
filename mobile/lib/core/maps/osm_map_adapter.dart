import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'map_provider.dart';

/// flutter_map adapter for any raster tile server (OpenStreetMap by default).
class OsmMapAdapter implements MapProviderAdapter {
  const OsmMapAdapter({
    required this.tileUrl,
    required this.attribution,
    this.tilesEnabled = true,
  });

  final String tileUrl;
  final String attribution;

  /// Tests turn tiles off so no network requests are made.
  final bool tilesEnabled;

  @override
  String get name => 'osm';

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
  }) => _OsmMap(
    adapter: this,
    initial: initial,
    markers: markers,
    selectedId: selectedId,
    focus: focus,
    onMarkerTap: onMarkerTap,
    onViewportChanged: onViewportChanged,
    onTilesFailed: onTilesFailed,
  );
}

class _OsmMap extends StatefulWidget {
  const _OsmMap({
    required this.adapter,
    required this.initial,
    required this.markers,
    required this.selectedId,
    required this.focus,
    required this.onMarkerTap,
    required this.onViewportChanged,
    required this.onTilesFailed,
  });

  final OsmMapAdapter adapter;
  final MapViewport initial;
  final List<MapMarkerData> markers;
  final String? selectedId;
  final MapFocus? focus;
  final ValueChanged<MapMarkerData> onMarkerTap;
  final ValueChanged<MapViewport> onViewportChanged;
  final VoidCallback? onTilesFailed;

  @override
  State<_OsmMap> createState() => _OsmMapState();
}

class _OsmMapState extends State<_OsmMap> {
  final _controller = MapController();
  bool _reportedTileFailure = false;

  @override
  void didUpdateWidget(_OsmMap old) {
    super.didUpdateWidget(old);
    final focus = widget.focus;
    if (focus == null || identical(focus, old.focus)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (focus.fit != null) {
        final b = focus.fit!;
        _controller.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds(
              LatLng(b.south, b.west),
              LatLng(b.north, b.east),
            ),
            padding: const EdgeInsets.fromLTRB(48, 120, 48, 220),
            maxZoom: 12,
          ),
        );
      } else if (focus.point != null) {
        _controller.move(
          LatLng(focus.point!.lat, focus.point!.lng),
          focus.zoom ?? 11,
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FlutterMap(
      mapController: _controller,
      options: MapOptions(
        initialCenter: LatLng(
          widget.initial.center.lat,
          widget.initial.center.lng,
        ),
        initialZoom: widget.initial.zoom,
        minZoom: 3,
        maxZoom: 18,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
        onPositionChanged: (camera, hasGesture) {
          final b = camera.visibleBounds;
          widget.onViewportChanged(
            MapViewport(
              center: GeoPoint(camera.center.latitude, camera.center.longitude),
              zoom: camera.zoom,
              bounds: GeoBounds(
                south: b.south,
                west: b.west,
                north: b.north,
                east: b.east,
              ),
              byUser: hasGesture,
            ),
          );
        },
      ),
      children: [
        if (widget.adapter.tilesEnabled)
          TileLayer(
            urlTemplate: widget.adapter.tileUrl,
            userAgentPackageName: 'com.angon.angon',
            errorTileCallback: (tile, error, stackTrace) {
              if (!_reportedTileFailure) {
                _reportedTileFailure = true;
                widget.onTilesFailed?.call();
              }
            },
          ),
        MarkerLayer(
          markers: [
            for (final m in widget.markers)
              Marker(
                point: LatLng(m.point.lat, m.point.lng),
                width: 56,
                height: 56,
                alignment: Alignment.topCenter,
                child: Semantics(
                  button: true,
                  label: m.label,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => widget.onMarkerTap(m),
                    child: Icon(
                      Icons.place,
                      size: m.id == widget.selectedId ? 52 : 40,
                      color: m.id == widget.selectedId
                          ? scheme.secondary
                          : scheme.primary,
                      shadows: const [
                        Shadow(blurRadius: 4, color: Colors.black26),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        RichAttributionWidget(
          alignment: AttributionAlignment.bottomLeft,
          attributions: [TextSourceAttribution(widget.adapter.attribution)],
        ),
      ],
    );
  }
}
