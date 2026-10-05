import '../../core/utils/unchanged.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../models/user.dart';
import '../../services/providers.dart';

sealed class AuthState {
  const AuthState();
}

/// Startup: checking for a stored session.
class AuthChecking extends AuthState {
  const AuthChecking();
}

/// Startup check failed for a non-auth reason (offline / server error).
/// The stored token is kept; the user can retry.
class AuthCheckFailed extends AuthState {
  const AuthCheckFailed(this.error);
  final Object error;
}

class Unauthenticated extends AuthState {
  const Unauthenticated();
}

class Authenticated extends AuthState {
  const Authenticated(this.user);
  final AppUser user;
}

/// Single source of truth for the signed-in session.
///
/// The token lives only in secure storage; `Authenticated` is entered only
/// after the server has confirmed it (login/register response or `/users/me`).
class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    Future.microtask(bootstrap);
    return const AuthChecking();
  }

  Future<void> bootstrap() async {
    state = const AuthChecking();
    final storage = ref.read(tokenStorageProvider);
    try {
      final token = await storage.read();
      if (token == null) {
        state = const Unauthenticated();
        return;
      }
      final user = await ref.read(authRepositoryProvider).currentUser();
      state = Authenticated(user);
    } on UnauthorizedException {
      await storage.clear();
      state = const Unauthenticated();
    } catch (e) {
      state = AuthCheckFailed(e);
    }
  }

  Future<void> login({
    required String identifier,
    required String password,
  }) async {
    final session = await ref
        .read(authRepositoryProvider)
        .login(identifier: identifier, password: password);
    await _accept(session);
  }

  Future<void> register({
    required String email,
    required String username,
    required String password,
  }) async {
    final session = await ref
        .read(authRepositoryProvider)
        .register(email: email, username: username, password: password);
    await _accept(session);
  }

  Future<void> _accept(AuthSession session) async {
    await ref.read(tokenStorageProvider).write(session.accessToken);
    state = Authenticated(session.user);
  }

  Future<void> updateProfile({
    String? displayName,
    String? bio,
    String? location,
    CreatorType? creatorType,
    Object? avatarMediaId = unchanged,
    Object? coverMediaId = unchanged,
  }) async {
    final user = await ref
        .read(authRepositoryProvider)
        .updateProfile(
          displayName: displayName,
          bio: bio,
          location: location,
          creatorType: creatorType,
          avatarMediaId: avatarMediaId,
          coverMediaId: coverMediaId,
        );
    state = Authenticated(user);
  }

  /// Revokes the token on the server (best effort) and always clears it locally.
  Future<void> logout() async {
    try {
      await ref.read(authRepositoryProvider).logout();
    } catch (_) {
      // Offline or already expired: local sign-out must still succeed.
    }
    await ref.read(tokenStorageProvider).clear();
    state = const Unauthenticated();
  }

  /// Called by the API client when the server rejects our token.
  void sessionExpired() {
    if (state is! Authenticated) return;
    ref.read(tokenStorageProvider).clear();
    state = const Unauthenticated();
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);
