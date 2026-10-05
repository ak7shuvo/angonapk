import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/post.dart';
import '../features/social/post_detail_screen.dart';
import '../features/stories/stories_screen.dart';
import '../features/stories/story_editor_screen.dart';
import '../features/stories/story_reader_screen.dart';
import '../features/social/user_list_screen.dart';

import '../features/auth/auth_controller.dart';
import '../features/auth/auth_redirect.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/profile_setup_screen.dart';
import '../features/auth/register_screen.dart';
import '../features/auth/splash_screen.dart';
import '../features/auth/welcome_screen.dart';
import '../features/composer/composer_screen.dart';
import '../features/explore/category_screen.dart';
import '../features/explore/explore_screen.dart';
import '../features/explore/search_screen.dart';
import '../features/home/home_screen.dart';
import '../features/places/place_screen.dart';
import '../features/profile/edit_profile_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/shell/main_shell.dart';
import 'routes.dart';

export 'routes.dart';

final routerProvider = Provider<GoRouter>((ref) {
  // Re-evaluate redirects whenever the auth state changes.
  final refresh = ValueNotifier<int>(0);
  ref.listen(authControllerProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  final router = GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: refresh,
    redirect: (context, state) =>
        authRedirect(ref.read(authControllerProvider), state.uri.path),
    routes: [
      GoRoute(path: AppRoutes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(
        path: AppRoutes.welcome,
        builder: (_, _) => const WelcomeScreen(),
      ),
      GoRoute(path: AppRoutes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(
        path: AppRoutes.register,
        builder: (_, _) => const RegisterScreen(),
      ),
      GoRoute(
        path: AppRoutes.profileSetup,
        builder: (_, _) => const ProfileSetupScreen(),
      ),
      GoRoute(
        path: '/posts/:id',
        builder: (_, state) => PostDetailScreen(
          postId: state.pathParameters['id']!,
          initial: state.extra is Post ? state.extra as Post : null,
        ),
      ),
      GoRoute(
        path: '/u/:username/followers',
        builder: (_, state) => UserListScreen(
          username: state.pathParameters['username']!,
          kind: UserListKind.followers,
        ),
      ),
      GoRoute(
        path: '/u/:username/following',
        builder: (_, state) => UserListScreen(
          username: state.pathParameters['username']!,
          kind: UserListKind.following,
        ),
      ),
      GoRoute(path: AppRoutes.search, builder: (_, _) => const SearchScreen()),
      GoRoute(
        path: '/explore/category/:slug',
        builder: (_, state) =>
            CategoryScreen(slug: state.pathParameters['slug']!),
      ),
      GoRoute(
        path: '/places/:slug',
        builder: (_, state) => PlaceScreen(slug: state.pathParameters['slug']!),
      ),
      GoRoute(
        path: AppRoutes.profileEdit,
        builder: (_, _) => const EditProfileScreen(),
      ),
      GoRoute(
        path: '/u/:username',
        builder: (_, state) =>
            PublicProfileScreen(username: state.pathParameters['username']!),
      ),
      GoRoute(
        path: AppRoutes.storyNew,
        builder: (_, _) => const StoryEditorScreen(),
      ),
      GoRoute(
        path: '/story/:id/edit',
        builder: (_, state) =>
            StoryEditorScreen(storyId: state.pathParameters['id']),
      ),
      GoRoute(
        path: '/story/:ref',
        builder: (_, state) =>
            StoryReaderScreen(refId: state.pathParameters['ref']!),
      ),
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
                builder: (_, _) => const ExploreScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.create,
                builder: (_, _) => const ComposerScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.stories,
                builder: (_, _) => const StoriesScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.profile,
                builder: (_, _) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
