import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_spacing.dart';
import '../../routing/routes.dart';
import '../../shared/widgets/widgets.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        // Scrolls (instead of overflowing) with large text or short screens.
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.gutter),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - AppSpacing.gutter * 2,
              ),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Spacer(),
                    const AngonWordmark(size: 44),
                    const SizedBox(height: AppSpacing.lg),
                    Text('Places. People. Stories.', style: text.displayMedium),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Discover destinations, share what you find, and keep the '
                      'stories and culture of Bangladesh alive.',
                      style: text.bodyLarge,
                    ),
                    const Spacer(flex: 2),
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton(
                      onPressed: () => context.go(AppRoutes.register),
                      child: const Text('Create account'),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    OutlinedButton(
                      onPressed: () => context.go(AppRoutes.login),
                      child: const Text('Sign in'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
