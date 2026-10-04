import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/home/home_screen.dart';
import '../features/shell/main_shell.dart';
import '../features/shell/placeholder_screen.dart';

abstract final class AppRoutes {
  static const home = '/';
  static const explore = '/explore';
  static const create = '/create';
  static const stories = '/stories';
  static const profile = '/profile';
}

GoRouter buildRouter() => GoRouter(
  initialLocation: AppRoutes.home,
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => MainShell(navigationShell: shell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.home,
              builder: (_, _) => const HomeScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.explore,
              builder: (_, _) => const PlaceholderScreen(
                title: 'Explore',
                icon: Icons.travel_explore_outlined,
                message: 'Discover destinations, culture and heritage. Coming in Phase 08.',
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.create,
              builder: (_, _) => const PlaceholderScreen(
                title: 'Create',
                icon: Icons.edit_outlined,
                message: 'What are you discovering? The composer arrives in Phase 04.',
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.stories,
              builder: (_, _) => const PlaceholderScreen(
                title: 'Stories',
                icon: Icons.auto_stories_outlined,
                message: 'Long-form travel and cultural stories. Coming in Phase 06.',
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.profile,
              builder: (_, _) => const PlaceholderScreen(
                title: 'Profile',
                icon: Icons.person_outline,
                message:
                    'Your traveller identity. Sign-in arrives in Phase 02.',
              ),
            ),
          ],
        ),
      ],
    ),
  ],
);
