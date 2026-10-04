import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_spacing.dart';
import '../../shared/widgets/widgets.dart';
import 'health_provider.dart';

/// Phase 01 placeholder. The real feed arrives in Phase 03.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(healthProvider);
    return Scaffold(
      appBar: AppBar(title: const AngonWordmark(size: 22)),
      body: Column(
        children: [
          const Expanded(
            child: EmptyState(
              icon: Icons.explore_outlined,
              title: 'Your journal starts here',
              message: 'Posts from travellers and storytellers you follow will appear in your feed.',
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.gutter),
            child: _BackendStatus(
              health: health,
              onRetry: () => ref.invalidate(healthProvider),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackendStatus extends StatelessWidget {
  const _BackendStatus({required this.health, required this.onRetry});
  final AsyncValue<dynamic> health;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    final text = health.when(
      data: (h) => 'Backend: ${h.status} · db ${h.database} · ${h.environment}',
      loading: () => 'Backend: checking…',
      error: (_, _) => 'Backend: unreachable',
    );
    return TextButton(
      onPressed: onRetry,
      child: Text(text, style: style),
    );
  }
}
