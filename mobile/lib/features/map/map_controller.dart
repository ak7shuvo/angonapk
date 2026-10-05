import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/maps/map_provider.dart';
import '../../models/nearby.dart';
import '../../models/place.dart';
import '../../services/providers.dart';
import '../../repositories/place_repository.dart';

/// Bangladesh at country zoom.
const bangladeshCenter = GeoPoint(23.7, 90.4);
const bangladeshZoom = 6.4;

GeoPoint pointOf(PlaceSummary p) => GeoPoint(p.latitude, p.longitude);

enum MapMode { map, list }

class PlaceMapState {
  const PlaceMapState({
    this.loading = true,
    this.places = const [],
    this.divisions = const [],
    this.division,
    this.selected,
    this.error,
    this.mode = MapMode.map,
    this.focus,
    this.canSearchHere = false,
    this.inView,
    this.tilesFailed = false,
  });

  final bool loading;

  /// Places currently shown as markers / list rows.
  final List<PlaceSummary> places;

  /// All divisions seen in the unfiltered data, for the filter chips.
  final List<String> divisions;
  final String? division;
  final PlaceSummary? selected;
  final Object? error;
  final MapMode mode;
  final MapFocus? focus;

  /// The user moved the map since the last query: offer "Search this area".
  final bool canSearchHere;

  /// Set after "Search this area": how many places the viewport contained.
  final int? inView;
  final bool tilesFailed;

  PlaceMapState copyWith({
    bool? loading,
    List<PlaceSummary>? places,
    List<String>? divisions,
    Object? division = _keep,
    Object? selected = _keep,
    Object? error = _keep,
    MapMode? mode,
    Object? focus = _keep,
    bool? canSearchHere,
    Object? inView = _keep,
    bool? tilesFailed,
  }) => PlaceMapState(
    loading: loading ?? this.loading,
    places: places ?? this.places,
    divisions: divisions ?? this.divisions,
    division: identical(division, _keep) ? this.division : division as String?,
    selected: identical(selected, _keep)
        ? this.selected
        : selected as PlaceSummary?,
    error: identical(error, _keep) ? this.error : error,
    mode: mode ?? this.mode,
    focus: identical(focus, _keep) ? this.focus : focus as MapFocus?,
    canSearchHere: canSearchHere ?? this.canSearchHere,
    inView: identical(inView, _keep) ? this.inView : inView as int?,
    tilesFailed: tilesFailed ?? this.tilesFailed,
  );
}

const _keep = Object();

/// State of the Map screen: which places are shown, the filter, the selection.
/// [initialSlug] opens the map focused on one place.
class PlaceMapController extends Notifier<PlaceMapState> {
  PlaceMapController(this.initialSlug);
  final String? initialSlug;

  GeoBounds? _viewBounds;
  int _seq = 0;

  PlaceRepository get _repo => ref.read(placeRepositoryProvider);

  @override
  PlaceMapState build() {
    Future.microtask(load);
    return PlaceMapState(
      mode: ref.read(mapAdapterProvider) == null ? MapMode.list : MapMode.map,
    );
  }

  Future<void> load() async {
    final seq = ++_seq;
    state = state.copyWith(loading: true, error: null);
    try {
      final list = await _repo.search(limit: 100);
      PlaceSummary? initial;
      if (initialSlug != null) {
        initial =
            list.items.where((p) => p.slug == initialSlug).firstOrNull ??
            await _repo.get(initialSlug!);
      }
      if (!ref.mounted || seq != _seq) return;
      final divisions = ({for (final p in list.items) ?p.division}.toList()
        ..sort());
      state = state.copyWith(
        loading: false,
        places: list.items,
        divisions: divisions,
        selected: initial,
        focus: initial != null
            ? MapFocus.point(pointOf(initial), zoom: 11)
            : null,
      );
    } catch (e) {
      if (ref.mounted && seq == _seq) {
        state = state.copyWith(loading: false, error: e);
      }
    }
  }

  /// Filter by division (null clears). The camera fits the matching places.
  Future<void> setDivision(String? division) async {
    final seq = ++_seq;
    state = state.copyWith(
      division: division,
      loading: true,
      error: null,
      selected: null,
      inView: null,
    );
    try {
      final list = await _repo.search(division: division, limit: 100);
      if (!ref.mounted || seq != _seq) return;
      final bounds = GeoBounds.around(list.items.map(pointOf));
      state = state.copyWith(
        loading: false,
        places: list.items,
        canSearchHere: false,
        focus: bounds != null
            ? MapFocus.fit(bounds)
            : const MapFocus.point(bangladeshCenter, zoom: bangladeshZoom),
      );
    } catch (e) {
      if (ref.mounted && seq == _seq) {
        state = state.copyWith(loading: false, error: e);
      }
    }
  }

  void onViewportChanged(MapViewport viewport) {
    _viewBounds = viewport.bounds;
    if (viewport.byUser && !state.canSearchHere) {
      state = state.copyWith(canSearchHere: true);
    }
  }

  /// Show only the places inside the visible map area.
  Future<void> searchThisArea() async {
    final b = _viewBounds;
    if (b == null) return;
    final seq = ++_seq;
    state = state.copyWith(loading: true, error: null, canSearchHere: false);
    try {
      final list = await _repo.search(
        division: state.division,
        bounds: (
          minLat: b.south,
          maxLat: b.north,
          minLng: b.west,
          maxLng: b.east,
        ),
        limit: 100,
      );
      if (!ref.mounted || seq != _seq) return;
      state = state.copyWith(
        loading: false,
        places: list.items,
        inView: list.total,
        selected: list.items.any((p) => p.id == state.selected?.id)
            ? state.selected
            : null,
      );
    } catch (e) {
      if (ref.mounted && seq == _seq) {
        state = state.copyWith(loading: false, error: e);
      }
    }
  }

  void select(PlaceSummary? place) => state = state.copyWith(
    selected: place,
    focus: place == null ? null : MapFocus.point(pointOf(place), zoom: 11),
  );

  void setMode(MapMode mode) => state = state.copyWith(mode: mode);

  void tilesFailed() =>
      state = state.copyWith(tilesFailed: true, mode: MapMode.list);
}

final placeMapProvider = NotifierProvider.autoDispose
    .family<PlaceMapController, PlaceMapState, String?>(PlaceMapController.new);

typedef NearbyKey = ({double lat, double lng});

/// Content around a selected place.
final nearbyProvider = FutureProvider.autoDispose.family<NearbyData, NearbyKey>(
  (ref, key) => ref.watch(placeRepositoryProvider).nearby(key.lat, key.lng),
);
