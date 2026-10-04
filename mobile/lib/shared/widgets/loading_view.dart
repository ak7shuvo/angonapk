import 'package:flutter/material.dart';

/// Centered progress indicator for full-screen / section loading.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.label});
  final String? label;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
        if (label != null) ...[
          const SizedBox(height: 12),
          Text(label!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    ),
  );
}
