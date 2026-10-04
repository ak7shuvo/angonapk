import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_spacing.dart';
import '../auth/auth_controller.dart';

/// Minimal account view (Phase 02). The full creator profile arrives in Phase 07.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final user = auth is Authenticated ? auth.user : null;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: user == null
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.gutter),
              children: [
                Text(user.displayName, style: theme.textTheme.displayMedium),
                const SizedBox(height: AppSpacing.xs),
                Text('@${user.username}', style: theme.textTheme.bodyMedium),
                if (user.profile.creatorType != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    user.profile.creatorType!.label.toUpperCase(),
                    style: theme.textTheme.labelMedium,
                  ),
                ],
                if (user.profile.location != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    user.profile.location!,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
                if (user.profile.bio != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(user.profile.bio!, style: theme.textTheme.bodyLarge),
                ],
                const SizedBox(height: AppSpacing.xl),
                OutlinedButton(
                  onPressed: () =>
                      ref.read(authControllerProvider.notifier).logout(),
                  child: const Text('Sign out'),
                ),
              ],
            ),
    );
  }
}
