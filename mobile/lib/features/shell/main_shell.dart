import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Bottom navigation shell: HOME · EXPLORE · CREATE · STORIES · PROFILE.
class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home_rounded),
      label: 'HOME',
    ),
    NavigationDestination(
      icon: Icon(Icons.travel_explore_outlined),
      selectedIcon: Icon(Icons.travel_explore),
      label: 'EXPLORE',
    ),
    NavigationDestination(
      icon: Icon(Icons.add_circle_outline),
      selectedIcon: Icon(Icons.add_circle),
      label: 'CREATE',
    ),
    NavigationDestination(
      icon: Icon(Icons.auto_stories_outlined),
      selectedIcon: Icon(Icons.auto_stories),
      label: 'STORIES',
    ),
    NavigationDestination(
      icon: Icon(Icons.person_outline),
      selectedIcon: Icon(Icons.person),
      label: 'PROFILE',
    ),
  ];

  @override
  Widget build(BuildContext context) => PopScope(
    // Android back from another tab returns to HOME first; only HOME exits.
    canPop: navigationShell.currentIndex == 0,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) navigationShell.goBranch(0);
    },
    child: Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        destinations: _destinations,
        onDestinationSelected: (i) => navigationShell.goBranch(
          i,
          initialLocation: i == navigationShell.currentIndex,
        ),
      ),
    ),
  );
}
