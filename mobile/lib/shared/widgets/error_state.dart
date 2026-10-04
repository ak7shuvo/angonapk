import 'package:flutter/material.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_spacing.dart';

/// Error view that maps any thrown object to a safe, human message.
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  String get _message => error is AppException
      ? (error as AppException).message
      : 'Something went wrong. Please try again.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              error is NetworkException
                  ? Icons.wifi_off_rounded
                  : Icons.error_outline_rounded,
              size: 40,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              _message,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton(
                onPressed: onRetry,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(140, 48),
                ),
                child: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
