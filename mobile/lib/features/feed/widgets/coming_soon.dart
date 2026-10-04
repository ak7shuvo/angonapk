import 'package:flutter/material.dart';

/// Feedback for actions whose backend does not exist yet. It never pretends
/// the action succeeded.
void showComingSoon(BuildContext context, String feature) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text('$feature is coming soon.'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
}
