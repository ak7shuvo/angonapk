import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_spacing.dart';
import '../widgets/widgets.dart';
import 'paged_controller.dart';

/// Slivers for a [PagedState]: loading, error(+retry), empty, items, footer.
List<Widget> pagedSlivers<T>({
  required PagedState<T> state,
  required Widget Function(BuildContext, T) itemBuilder,
  required Widget empty,
  required VoidCallback onRetry,
  required VoidCallback onLoadMore,
}) {
  switch (state.status) {
    case PagedStatus.loading:
      return const [
        SliverFillRemaining(hasScrollBody: false, child: LoadingView()),
      ];
    case PagedStatus.error:
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: ErrorState(error: state.error!, onRetry: onRetry),
        ),
      ];
    case PagedStatus.ready when state.isEmpty:
      return [SliverFillRemaining(hasScrollBody: false, child: empty)];
    case PagedStatus.ready:
      return [
        SliverList.builder(
          itemCount: state.items.length,
          itemBuilder: (context, i) => itemBuilder(context, state.items[i]),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Center(
              child: state.loadMoreError != null
                  ? TextButton(
                      onPressed: onLoadMore,
                      child: const Text('Could not load more. Tap to retry'),
                    )
                  : state.hasMore
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ];
  }
}

/// Pull-to-refresh + infinite-scroll scaffold around [slivers].
class PagedScrollView extends StatelessWidget {
  const PagedScrollView({
    super.key,
    required this.slivers,
    required this.onRefresh,
    required this.onLoadMore,
    this.headerSlivers = const [],
  });

  final List<Widget> slivers;
  final List<Widget> headerSlivers;
  final Future<void> Function() onRefresh;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: onRefresh,
    child: NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.extentAfter < 800) onLoadMore();
        return false;
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [...headerSlivers, ...slivers],
      ),
    ),
  );
}

/// Shows a snack when a pull-to-refresh fails while content is on screen.
void listenForRefreshErrors<T>(
  WidgetRef ref,
  NotifierProvider<PagedController<T>, PagedState<T>> provider,
  BuildContext context,
) {
  ref.listen(provider.select((s) => s.refreshError), (_, error) {
    if (error != null) {
      showAppSnack(
        context,
        errorMessage(error, fallback: 'Could not refresh.'),
      );
    }
  });
}
