import 'package:flutter/material.dart';

import '../../core/theme/app_typography.dart';

/// The ANGON wordmark with its tagline.
class AngonWordmark extends StatelessWidget {
  const AngonWordmark({super.key, this.size = 28, this.showTagline = false});

  final double size;
  final bool showTagline;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ANGON',
          style: AppTypography.serif(
            size: size,
            weight: 700,
            letterSpacing: size * 0.18,
          ).copyWith(color: scheme.primary),
        ),
        if (showTagline)
          Text(
            'Places. People. Stories.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }
}
