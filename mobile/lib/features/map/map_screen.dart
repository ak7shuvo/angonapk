import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/maps/map_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../models/place.dart';
import '../../routing/routes.dart';
import '../../services/providers.dart';
import '../../shared/widgets/widgets.dart';
import '../places/widgets/place_tile.dart';
import 'map_controller.dart';

/// Place discovery on a map: markers for destinations, a division filter,
/// "search this area", and what is nearby a selected place. Falls back to a
/// list when no map provider is configured or tiles cannot load.
class MapScreen extends ConsumerWidget {
  const MapScreen({super.key, this.placeSlug});

  /// Open focused on this place.
  final String? placeSlug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(placeMapProvider(placeSlug));
    final controller = ref.read(placeMapProvider(placeSlug).notifier);
    final adapter = ref.watch(mapAdapterProvider);
    final theme = Theme.of(context);
    final showMap = adapter != null && state.mode == MapMode.map;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Map'),
        actions: [
          if (adapter != null)
            IconButton(
              tooltip: showMap ? 'Show as list' : 'Show map',
              icon: Icon(
                showMap ? Icons.view_list_outlined : Icons.map_outlined,
              ),
              onPressed: () =>
                  controller.setMode(showMap ? MapMode.list : MapMode.map),
            ),
        ],
      ),
      body: Column(
        children: [
          _Filters(state: state, controller: controller),
          if (state.tilesFailed)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.gutter,
                vertical: 8,
              ),
              color: theme.colorScheme.error.withValues(alpha: 0.08),
              child: Text(
                'The map could not load, so places are shown as a list.',
                style: theme.textTheme.bodySmall,
              ),
            )
          else if (adapter == null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.gutter,
                vertical: 8,
              ),
              color: context.placeholder.withValues(alpha: 0.6),
              child: Text(
                'Map view is not configured (MAP_PROVIDER). Showing places as a list.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          Expanded(
            child: state.error != null && state.places.isEmpty
                ? ErrorState(error: state.error!, onRetry: controller.load)
                : showMap
                ? _MapStack(
                    adapter: adapter,
                    state: state,
                    controller: controller,
                    slug: placeSlug,
                  )
                : _PlaceList(state: state, controller: controller),
          ),
        ],
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({required this.state, required this.controller});
  final PlaceMapState state;
  final PlaceMapController controller;

  @override
  Widget build(BuildContext context) {
    if (state.divisions.isEmpty) return const SizedBox(height: 0);
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.gutter,
          vertical: 8,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: ChoiceChip(
              label: const Text('All Bangladesh'),
              selected: state.division == null,
              onSelected: (_) => controller.setDivision(null),
            ),
          ),
          for (final d in state.divisions)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: ChoiceChip(
                label: Text(d),
                selected: state.division == d,
                onSelected: (_) => controller.setDivision(d),
              ),
            ),
        ],
      ),
    );
  }
}

class _MapStack extends ConsumerWidget {
  const _MapStack({
    required this.adapter,
    required this.state,
    required this.controller,
    required this.slug,
  });
  final MapProviderAdapter adapter;
  final PlaceMapState state;
  final PlaceMapController controller;
  final String? slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final selected = state.selected;
    final startAt = selected != null ? pointOf(selected) : bangladeshCenter;
    return Stack(
      children: [
        Positioned.fill(
          child: adapter.build(
            context,
            initial: MapViewport(
              center: startAt,
              zoom: selected != null ? 11 : bangladeshZoom,
            ),
            markers: [
              for (final p in state.places)
                MapMarkerData(id: p.id, point: pointOf(p), label: p.name),
            ],
            selectedId: selected?.id,
            focus: state.focus,
            onMarkerTap: (m) => controller.select(
              state.places.where((p) => p.id == m.id).firstOrNull,
            ),
            onViewportChanged: controller.onViewportChanged,
            onTilesFailed: controller.tilesFailed,
          ),
        ),
        if (state.loading)
          const Positioned(
            top: 12,
            left: 0,
            right: 0,
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
          )
        else if (state.canSearchHere)
          Positioned(
            top: 12,
            left: 0,
            right: 0,
            child: Center(
              child: FilledButton.icon(
                onPressed: controller.searchThisArea,
                icon: const Icon(Icons.search, size: 18),
                label: const Text('Search this area'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              ),
            ),
          )
        else if (state.inView != null)
          Positioned(
            top: 12,
            left: 0,
            right: 0,
            child: Center(
              child: Material(
                color: theme.colorScheme.surface,
                elevation: 2,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  child: Text(
                    state.inView == 1
                        ? '1 place in this area'
                        : '${state.inView} places in this area',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ),
            ),
          ),
        if (!state.loading && state.places.isEmpty && state.error == null)
          const Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: EmptyState(
                  icon: Icons.travel_explore_outlined,
                  title: 'No places here',
                ),
              ),
            ),
          ),
        if (selected != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _SelectedSheet(
              place: selected,
              onClose: () => controller.select(null),
            ),
          ),
      ],
    );
  }
}

class _SelectedSheet extends ConsumerWidget {
  const _SelectedSheet({required this.place, required this.onClose});
  final PlaceSummary place;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final nearby = ref.watch(
      nearbyProvider((lat: place.latitude, lng: place.longitude)),
    );
    return Material(
      color: theme.colorScheme.surface,
      elevation: 8,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppSpacing.radiusLg),
      ),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.42,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppSpacing.sm),
                PlaceTile(
                  place: place,
                  trailing: IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close),
                    onPressed: onClose,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.gutter,
                  ),
                  child: FilledButton(
                    onPressed: () =>
                        context.push(AppRoutes.placePath(place.slug)),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                    ),
                    child: Text('Open ${place.name}'),
                  ),
                ),
                nearby.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(AppSpacing.lg),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.all(AppSpacing.gutter),
                    child: Text(
                      'Could not load nearby content.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  data: (data) {
                    final others = data.places
                        .where((p) => p.id != place.id)
                        .take(4)
                        .toList();
                    if (data.stories.isEmpty &&
                        data.posts.isEmpty &&
                        others.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(AppSpacing.gutter),
                        child: Text(
                          'Nothing nearby yet.',
                          style: theme.textTheme.bodySmall,
                        ),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.gutter,
                        AppSpacing.md,
                        AppSpacing.gutter,
                        AppSpacing.md,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('NEARBY', style: theme.textTheme.labelMedium),
                          const SizedBox(height: AppSpacing.sm),
                          for (final s in data.stories.take(3))
                            _NearbyRow(
                              icon: Icons.auto_stories_outlined,
                              text: s.displayTitle,
                              onTap: () => context.push(
                                AppRoutes.storyReadPath(s.slug),
                                extra: s,
                              ),
                            ),
                          for (final p in data.posts.take(3))
                            _NearbyRow(
                              icon: Icons.photo_camera_outlined,
                              text: p.body ?? 'Photo post by ${p.author.name}',
                              onTap: () => context.push(
                                AppRoutes.postPath(p.id),
                                extra: p,
                              ),
                            ),
                          for (final o in others)
                            _NearbyRow(
                              icon: Icons.place_outlined,
                              text:
                                  '${o.name}${o.distanceKm != null ? ' · ${o.distanceKm!.toStringAsFixed(0)} km' : ''}',
                              onTap: () =>
                                  context.push(AppRoutes.placePath(o.slug)),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NearbyRow extends StatelessWidget {
  const _NearbyRow({
    required this.icon,
    required this.text,
    required this.onTap,
  });
  final IconData icon;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: context.inkSoft),
          const SizedBox(width: AppSpacing.sm + 2),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.sans(size: 14, weight: 500),
            ),
          ),
        ],
      ),
    ),
  );
}

class _PlaceList extends StatelessWidget {
  const _PlaceList({required this.state, required this.controller});
  final PlaceMapState state;
  final PlaceMapController controller;

  @override
  Widget build(BuildContext context) {
    if (state.loading && state.places.isEmpty) return const LoadingView();
    if (state.places.isEmpty) {
      return const EmptyState(
        icon: Icons.travel_explore_outlined,
        title: 'No places found',
      );
    }
    return ListView.builder(
      itemCount: state.places.length,
      itemBuilder: (context, i) => PlaceTile(place: state.places[i]),
    );
  }
}
