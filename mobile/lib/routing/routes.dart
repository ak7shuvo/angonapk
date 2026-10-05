abstract final class AppRoutes {
  static const splash = '/splash';
  static const welcome = '/welcome';
  static const login = '/login';
  static const register = '/register';
  static const profileSetup = '/profile-setup';

  static const home = '/';
  static const explore = '/explore';
  static const create = '/create';
  static const stories = '/stories';
  static const profile = '/profile';

  static const storyNew = '/story/new';
  static String storyReadPath(String ref) => '/story/$ref';
  static String storyEditPath(String id) => '/story/$id/edit';
  static const profileEdit = '/profile/edit';
  static String userPath(String username) => '/u/$username';
  static String placePath(String slug) => '/places/$slug';
  static const map = '/map';
  static const search = '/search';
  static String categoryPath(String slug) => '/explore/category/$slug';
  static String postPath(String id) => '/posts/$id';
  static String followersPath(String username) => '/u/$username/followers';
  static String followingPath(String username) => '/u/$username/following';

  /// Screens for signed-out users.
  static const authRoutes = {welcome, login, register};
}
