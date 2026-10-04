import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/widgets/widgets.dart';
import 'auth_controller.dart';

/// Shown while the stored session is verified with the server.
/// Navigation away is handled by the router's auth redirect.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: auth is AuthCheckFailed
              ? ErrorState(
                  error: auth.error,
                  onRetry: () =>
                      ref.read(authControllerProvider.notifier).bootstrap(),
                )
              : const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AngonWordmark(size: 40, showTagline: true),
                    SizedBox(height: 32),
                    LoadingView(),
                  ],
                ),
        ),
      ),
    );
  }
}
