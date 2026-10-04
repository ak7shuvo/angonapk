import 'package:flutter/material.dart';

import '../../shared/widgets/widgets.dart';

/// Temporary tab body for features scheduled in later phases.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({
    super.key,
    required this.title,
    required this.icon,
    required this.message,
  });

  final String title;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: EmptyState(icon: icon, title: title, message: message),
  );
}
