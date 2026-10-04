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
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.gutter),
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
    );
  }
}
