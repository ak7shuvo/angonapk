import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'error_state.dart';
import 'loading_view.dart';

/// Renders the three states of an [AsyncValue] consistently across screens.
class AsyncValueView<T> extends StatelessWidget {
  const AsyncValueView({
    super.key,
    required this.value,
    required this.data,
    this.onRetry,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => value.when(
    data: data,
    loading: () => const LoadingView(),
    error: (e, _) => ErrorState(error: e, onRetry: onRetry),
  );
}
