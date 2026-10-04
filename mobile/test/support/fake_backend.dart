import 'package:angon/core/errors/app_exception.dart';
import 'package:angon/core/network/api_client.dart';

/// In-memory test double that mimics the ANGON API contract used by Phase 02.
/// Real client↔server behaviour is covered separately by test/e2e.
class FakeBackend implements ApiClient {
  final users = <String, Map<String, dynamic>>{}; // username -> user json
  final passwords = <String, String>{}; // username -> password
  final tokens = <String, String>{}; // token -> username
  final calls = <String>[];

  /// Set to make every request fail with this error.
  AppException? failWith;

  /// Tokens the server considers revoked/expired.
  final revoked = <String>{};

  int _n = 0;

  Map<String, dynamic> seedUser(
    String username,
    String password, {
    bool complete = true,
  }) {
    final user = {
      'id': 'id-${_n++}',
      'email': '$username@example.com',
      'username': username,
      'role': 'user',
      'created_at': '2026-01-01T00:00:00Z',
      'profile': {
        'display_name': complete ? 'Name $username' : null,
        'bio': null,
        'location': null,
        'creator_type': complete ? 'traveler' : null,
        'is_complete': complete,
      },
    };
    users[username] = user;
    passwords[username] = password;
    return user;
  }

  String issueToken(String username) {
    final token = 'tok-${_n++}-$username';
    tokens[token] = username;
    return token;
  }

  Map<String, dynamic> _session(String username) => {
    'access_token': issueToken(username),
    'token_type': 'bearer',
    'expires_at': '2030-01-01T00:00:00Z',
    'user': users[username],
  };

  @override
  Future<dynamic> get(String path, {Map<String, String>? query}) =>
      _handle('GET', path, null);
  @override
  Future<dynamic> post(String path, {Object? body}) =>
      _handle('POST', path, body);
  @override
  Future<dynamic> put(String path, {Object? body}) =>
      _handle('PUT', path, body);
  @override
  Future<dynamic> patch(String path, {Object? body}) =>
      _handle('PATCH', path, body);
  @override
  Future<dynamic> delete(String path) => _handle('DELETE', path, null);

  /// Returns the token the app would send (wired by the test harness).
  String? Function()? currentToken;

  /// Mirrors HttpApiClient: invoked when a request carrying a token gets 401.
  void Function()? onUnauthorized;

  Future<dynamic> _handle(String method, String path, Object? body) async {
    calls.add('$method $path');
    await Future<void>.delayed(Duration.zero);
    if (failWith != null) throw failWith!;
    final data = body as Map<String, dynamic>?;

    String requireUser() {
      final token = currentToken?.call();
      if (token == null ||
          revoked.contains(token) ||
          !tokens.containsKey(token)) {
        if (token != null) onUnauthorized?.call();
        throw const UnauthorizedException();
      }
      return tokens[token]!;
    }

    switch ('$method $path') {
      case 'GET /health':
        return {'status': 'ok', 'environment': 'test', 'database': 'ok'};
      case 'POST /auth/register':
        final fields = <String, String>{};
        if (users.values.any((u) => u['email'] == data!['email'])) {
          fields['email'] = 'Email is already registered';
        }
        if (users.containsKey(data!['username'])) {
          fields['username'] = 'Username is already taken';
        }
        if (fields.isNotEmpty) {
          throw ValidationException('conflict', fieldErrors: fields);
        }
        seedUser(
          data['username'] as String,
          data['password'] as String,
          complete: false,
        );
        users[data['username']]!['email'] = data['email'];
        return _session(data['username'] as String);
      case 'POST /auth/login':
        final id = (data!['identifier'] as String).toLowerCase();
        final username = users.values
            .where((u) => u['username'] == id || u['email'] == id)
            .map((u) => u['username'] as String)
            .firstOrNull;
        if (username == null || passwords[username] != data['password']) {
          throw const UnauthorizedException(
            'Incorrect email/username or password',
          );
        }
        return _session(username);
      case 'POST /auth/logout':
        final username = requireUser();
        revoked.add(currentToken!.call()!);
        users[username];
        return null;
      case 'GET /users/me':
        return users[requireUser()];
      case 'PATCH /users/me/profile':
        final username = requireUser();
        final profile = users[username]!['profile'] as Map<String, dynamic>;
        profile.addAll(data!);
        profile['is_complete'] =
            (profile['display_name'] as String?)?.isNotEmpty == true &&
            profile['creator_type'] != null;
        return users[username];
    }
    throw const NotFoundException();
  }
}
