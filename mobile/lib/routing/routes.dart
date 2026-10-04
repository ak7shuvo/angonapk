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

  /// Screens for signed-out users.
  static const authRoutes = {welcome, login, register};
}
