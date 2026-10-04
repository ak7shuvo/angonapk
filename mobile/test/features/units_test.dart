import 'package:angon/features/auth/auth_controller.dart';
import 'package:angon/features/auth/auth_redirect.dart';
import 'package:angon/features/auth/validators.dart';
import 'package:angon/models/user.dart';
import 'package:angon/routing/routes.dart';
import 'package:flutter_test/flutter_test.dart';

AppUser user({required bool complete}) => AppUser(
  id: '1',
  email: 'a@b.co',
  username: 'abc',
  profile: Profile(isComplete: complete),
);

void main() {
  group('authRedirect', () {
    test('checking / failed startup always shows splash', () {
      expect(
        authRedirect(const AuthChecking(), AppRoutes.home),
        AppRoutes.splash,
      );
      expect(
        authRedirect(const AuthCheckFailed('x'), AppRoutes.login),
        AppRoutes.splash,
      );
      expect(authRedirect(const AuthChecking(), AppRoutes.splash), isNull);
    });

    test('signed-out users are confined to auth screens', () {
      for (final protected in [
        AppRoutes.home,
        AppRoutes.profile,
        AppRoutes.create,
        AppRoutes.profileSetup,
        AppRoutes.splash,
      ]) {
        expect(
          authRedirect(const Unauthenticated(), protected),
          AppRoutes.welcome,
        );
      }
      for (final open in AppRoutes.authRoutes) {
        expect(authRedirect(const Unauthenticated(), open), isNull);
      }
    });

    test('incomplete profile is forced to setup', () {
      final s = Authenticated(user(complete: false));
      expect(authRedirect(s, AppRoutes.home), AppRoutes.profileSetup);
      expect(authRedirect(s, AppRoutes.profileSetup), isNull);
    });

    test('complete users leave auth screens and setup', () {
      final s = Authenticated(user(complete: true));
      for (final from in [
        AppRoutes.splash,
        AppRoutes.welcome,
        AppRoutes.login,
        AppRoutes.register,
        AppRoutes.profileSetup,
      ]) {
        expect(authRedirect(s, from), AppRoutes.home);
      }
      expect(authRedirect(s, AppRoutes.profile), isNull);
    });
  });

  group('Validators', () {
    test('email', () {
      expect(Validators.email(''), isNotNull);
      expect(Validators.email('nope'), isNotNull);
      expect(Validators.email(' a@b.co '), isNull);
    });
    test('username', () {
      expect(Validators.username('ab'), isNotNull);
      expect(Validators.username('has space'), isNotNull);
      expect(Validators.username('Rahim_01'), isNull);
    });
    test('password', () {
      expect(Validators.newPassword('short'), isNotNull);
      expect(Validators.newPassword('long-enough-1'), isNull);
    });
  });

  test('CreatorType maps API values', () {
    expect(
      CreatorType.fromApi('local_storyteller'),
      CreatorType.localStoryteller,
    );
    expect(CreatorType.fromApi('admin'), isNull);
  });

  test('AppUser parses API payload', () {
    final u = AppUser.fromJson({
      'id': 'x',
      'email': 'a@b.co',
      'username': 'abc',
      'role': 'user',
      'created_at': '2026-01-01T00:00:00Z',
      'profile': {
        'display_name': 'রহিম',
        'bio': null,
        'location': 'Sylhet',
        'creator_type': 'guide',
        'is_complete': true,
      },
    });
    expect(u.displayName, 'রহিম');
    expect(u.profile.creatorType, CreatorType.guide);
  });
}
