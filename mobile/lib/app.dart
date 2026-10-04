import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/app_theme.dart';
import 'routing/app_router.dart';

class AngonApp extends StatefulWidget {
  const AngonApp({super.key, this.router});

  /// Injectable for tests.
  final GoRouter? router;

  @override
  State<AngonApp> createState() => _AngonAppState();
}

class _AngonAppState extends State<AngonApp> {
  late final GoRouter _router = widget.router ?? buildRouter();

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'ANGON',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    routerConfig: _router,
  );
}
