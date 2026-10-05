import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import 'profile_view.dart';

/// The Profile tab: always the signed-in user's own profile.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    if (auth is! Authenticated) return const SizedBox.shrink();
    return ProfileView(username: auth.user.username, isOwnTab: true);
  }
}

/// Someone else's (or your own, via a link) profile, pushed on top of the tabs.
class PublicProfileScreen extends StatelessWidget {
  const PublicProfileScreen({super.key, required this.username});
  final String username;

  @override
  Widget build(BuildContext context) => ProfileView(username: username);
}
