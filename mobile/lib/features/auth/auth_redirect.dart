import '../../routing/routes.dart';
import 'auth_controller.dart';

/// Pure routing rule: where should the user be, given auth state and location?
/// Returns null when the current location is fine.
String? authRedirect(AuthState auth, String location) {
  final isAuthArea = AppRoutes.authRoutes.contains(location);
  switch (auth) {
    case AuthChecking() || AuthCheckFailed():
      return location == AppRoutes.splash ? null : AppRoutes.splash;
    case Unauthenticated():
      return isAuthArea ? null : AppRoutes.welcome;
    case Authenticated(:final user):
      if (!user.profile.isComplete) {
        return location == AppRoutes.profileSetup
            ? null
            : AppRoutes.profileSetup;
      }
      if (isAuthArea ||
          location == AppRoutes.splash ||
          location == AppRoutes.profileSetup) {
        return AppRoutes.home;
      }
      return null;
  }
}
