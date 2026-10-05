import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/utils/debouncer.dart';
import '../../models/place.dart';
import '../../services/providers.dart';
import '../../shared/widgets/widgets.dart';
import 'widgets/place_tile.dart';

class PlacePickerState {
  const PlacePickerState({
    this.query = '',
    this.loading = true,
    this.results = const [],
    this.error,
  });
  final String query;
  final bool loading;
  final List<PlaceSummary> results;
  final Object? error;
}

/// Debounced place search for tagging posts and stories.
class PlacePickerController extends Notifier<PlacePickerState> {
  final _debounce = Debouncer(const Duration(milliseconds: 300));
  int _seq = 0;

  @override
  PlacePickerState build() {
    ref.onDispose(_debounce.cancel);
    Future.microtask(() => _load(''));
    return const PlacePickerState();
  }

  void setQuery(String q) {
    state = PlacePickerState(query: q, loading: true, results: state.results);
    _debounce.run(() => _load(q));
  }

  Future<void> retry() => _load(state.query);

  Future<void> _load(String q) async {
    final seq = ++_seq;
    try {
      final list = await ref
          .read(placeRepositoryProvider)
          .search(q: q, limit: 30);
      if (ref.mounted && seq == _seq) {
        state = PlacePickerState(query: q, loading: false, results: list.items);
      }
    } catch (e) {
      if (ref.mounted && seq == _seq) {
        state = PlacePickerState(
          query: q,
          loading: false,
          results: state.results,
          error: e,
        );
      }
    }
  }
}

final placePickerProvider =
    NotifierProvider.autoDispose<PlacePickerController, PlacePickerState>(
      PlacePickerController.new,
    );

/// Opens the picker; returns the chosen place (or null if dismissed).
Future<PlaceBrief?> showPlacePicker(BuildContext context) =>
    showModalBottomSheet<PlaceBrief>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _PlacePickerSheet(),
    );

class _PlacePickerSheet extends ConsumerWidget {
  const _PlacePickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(placePickerProvider);
    final controller = ref.read(placePickerProvider.notifier);
    final height = MediaQuery.sizeOf(context).height * 0.8;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    Widget body;
    if (state.loading && state.results.isEmpty) {
      body = const LoadingView();
    } else if (state.error != null && state.results.isEmpty) {
      body = ErrorState(error: state.error!, onRetry: controller.retry);
    } else if (state.results.isEmpty) {
      body = EmptyState(
        icon: Icons.travel_explore_outlined,
        title: 'No places found',
        message: state.query.isEmpty
            ? 'Places will appear here.'
            : 'Try a different name or district.',
      );
    } else {
      body = ListView.builder(
        itemCount: state.results.length,
        itemBuilder: (context, i) {
          final place = state.results[i];
          return PlaceTile(
            place: place,
            onTap: () => Navigator.pop<PlaceBrief>(context, place),
          );
        },
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                0,
                AppSpacing.gutter,
                AppSpacing.sm,
              ),
              child: TextField(
                autofocus: false,
                onChanged: controller.setQuery,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search places, e.g. Jaflong, Sylhet',
                ),
              ),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}
