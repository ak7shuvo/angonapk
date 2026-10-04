import 'package:flutter/material.dart';

import '../../core/errors/app_exception.dart';

/// Human message for any thrown error.
String errorMessage(
  Object error, {
  String fallback = 'Something went wrong. Please try again.',
}) => error is AppException ? error.message : fallback;

void showAppSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
}

/// Runs [action]; on failure shows the error as a snack instead of throwing.
Future<void> guarded(
  BuildContext context,
  Future<void> Function() action, {
  String? fallback,
}) async {
  try {
    await action();
  } catch (e) {
    if (context.mounted) {
      showAppSnack(
        context,
        errorMessage(
          e,
          fallback: fallback ?? 'Something went wrong. Please try again.',
        ),
      );
    }
  }
}
