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

  /// Posts served by `GET /posts`, newest first. Pagination uses an integer
  /// offset as the cursor (opaque to the app, like the real API).
  final feed = <Map<String, dynamic>>[];

  @override
  Future<dynamic> get(String path, {Map<String, String>? query}) =>
      _handle('GET', path, null, query);
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

  /// Uploads accepted so far (id → filename) and a hook to make uploads fail.
  final uploads = <String, String>{};
  final deletedMedia = <String>[];
  Object? Function(String filename)? uploadFailure;
  final created = <Map<String, dynamic>>[];

  @override
  Future<dynamic> upload(
    String path, {
    required List<int> bytes,
    required String filename,
    required String contentType,
    String field = 'file',
    void Function(double progress)? onProgress,
  }) async {
    calls.add('UPLOAD $path');
    if (failWith != null) throw failWith!;
    onProgress?.call(0.5);
    await Future<void>.delayed(Duration.zero);
    final failure = uploadFailure?.call(filename);
    if (failure != null) throw failure;
    onProgress?.call(1);
    final id = 'asset-${uploads.length}';
    uploads[id] = filename;
    return {
      'id': id,
      'url': '/media/u/$id.png',
      'kind': 'image',
      'content_type': contentType,
      'size_bytes': bytes.length,
      'width': 100,
      'height': 80,
    };
  }

  // Social state, keyed by post id / username.
  final likes = <String, Set<String>>{};
  final saves = <String, List<String>>{}; // post id -> usernames (save order)
  final comments = <String, List<Map<String, dynamic>>>{};
  final follows = <String, Set<String>>{}; // follower -> followees
  int _commentSeq = 0;

  /// Posts as the given viewer sees them (counts + viewer-relative flags).
  Map<String, dynamic> decorate(Map<String, dynamic> post, String viewer) {
    final id = post['id'] as String;
    final author = (post['author'] as Map)['username'] as String;
    return {
      ...post,
      'like_count': likes[id]?.length ?? 0,
      'comment_count': comments[id]?.length ?? 0,
      'liked_by_me': likes[id]?.contains(viewer) ?? false,
      'saved_by_me': saves[id]?.contains(viewer) ?? false,
      'following_author': follows[viewer]?.contains(author) ?? false,
    };
  }

  Map<String, dynamic> userSummary(String username, String viewer) {
    final u = users[username]!;
    final profile = u['profile'] as Map;
    return {
      'id': u['id'],
      'username': username,
      'display_name': profile['display_name'],
      'creator_type': profile['creator_type'],
      'is_following': follows[viewer]?.contains(username) ?? false,
      'is_me': username == viewer,
    };
  }

  Map<String, dynamic> _page(
    List<Map<String, dynamic>> all,
    Map<String, String>? query,
  ) {
    final limit = int.parse(query?['limit'] ?? '20');
    final start = int.parse(query?['cursor'] ?? '0');
    final end = (start + limit).clamp(0, all.length);
    return {
      'items': all.sublist(start.clamp(0, all.length), end),
      'next_cursor': end < all.length ? '$end' : null,
    };
  }

  /// Returns the token the app would send (wired by the test harness).
  String? Function()? currentToken;

  /// Mirrors HttpApiClient: invoked when a request carrying a token gets 401.
  void Function()? onUnauthorized;

  Future<dynamic> _handle(
    String method,
    String path,
    Object? body, [
    Map<String, String>? query,
  ]) async {
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

    if (method == 'DELETE' && path.startsWith('/media/')) {
      requireUser();
      deletedMedia.add(path.substring('/media/'.length));
      return null;
    }
    if (method == 'DELETE' && RegExp(r'^/posts/[^/]+$').hasMatch(path)) {
      requireUser();
      final id = path.substring('/posts/'.length);
      feed.removeWhere((p) => p['id'] == id);
      return null;
    }
    final social = RegExp(r'^/posts/([^/]+)/(like|save|comments)$')
        .firstMatch(path);
    if (social != null) {
      final viewer = requireUser();
      final id = social.group(1)!;
      if (!feed.any((p) => p['id'] == id)) throw const NotFoundException();
      switch ((method, social.group(2))) {
        case ('PUT', 'like'):
          (likes[id] ??= {}).add(viewer);
          return {'liked': true, 'like_count': likes[id]!.length};
        case ('DELETE', 'like'):
          likes[id]?.remove(viewer);
          return {'liked': false, 'like_count': likes[id]?.length ?? 0};
        case ('PUT', 'save'):
          final list = saves[id] ??= [];
          if (!list.contains(viewer)) {
            list.add(viewer);
          }
          return null;
        case ('DELETE', 'save'):
          saves[id]?.remove(viewer);
          return null;
        case ('GET', 'comments'):
          return _page([
            for (final c in comments[id] ?? <Map<String, dynamic>>[])
              {...c, 'is_mine': (c['author'] as Map)['username'] == viewer},
          ], query);
        case ('POST', 'comments'):
          final me = users[viewer]!;
          final comment = {
            'id': 'c-${_commentSeq++}',
            'post_id': id,
            'body': (data!['body'] as String).trim(),
            'author': {
              'id': me['id'],
              'username': viewer,
              'display_name': (me['profile'] as Map)['display_name'],
            },
            'created_at': '2026-01-01T00:00:00+00:00',
            'is_mine': true,
          };
          (comments[id] ??= []).add(comment);
          return comment;
      }
    }
    final commentDelete = RegExp(r'^/comments/([^/]+)$').firstMatch(path);
    if (commentDelete != null && method == 'DELETE') {
      requireUser();
      for (final list in comments.values) {
        list.removeWhere((c) => c['id'] == commentDelete.group(1));
      }
      return null;
    }
    final follow = RegExp(r'^/users/([^/]+)/(follow|followers|following)$')
        .firstMatch(path);
    if (follow != null) {
      final viewer = requireUser();
      final target = follow.group(1)!;
      if (!users.containsKey(target)) throw const NotFoundException();
      switch ((method, follow.group(2))) {
        case ('PUT', 'follow'):
          if (target == viewer) {
            throw const ValidationException('You cannot follow yourself');
          }
          (follows[viewer] ??= {}).add(target);
          return {
            'following': true,
            'followers_count': follows.values
                .where((f) => f.contains(target))
                .length,
          };
        case ('DELETE', 'follow'):
          follows[viewer]?.remove(target);
          return {
            'following': false,
            'followers_count': follows.values
                .where((f) => f.contains(target))
                .length,
          };
        case ('GET', 'followers'):
          return _page([
            for (final e in follows.entries)
              if (e.value.contains(target)) userSummary(e.key, viewer),
          ], query);
        case ('GET', 'following'):
          return _page([
            for (final f in follows[target] ?? <String>{})
              userSummary(f, viewer),
          ], query);
      }
    }
    final single = RegExp(r'^/posts/([^/]+)$').firstMatch(path);
    if (single != null && method == 'GET') {
      final viewer = requireUser();
      final found = feed.where((p) => p['id'] == single.group(1));
      if (found.isEmpty) throw const NotFoundException();
      return decorate(found.first, viewer);
    }
    switch ('$method $path') {
      case 'GET /health':
        return {'status': 'ok', 'environment': 'test', 'database': 'ok'};
      case 'GET /posts':
        final viewer = requireUser();
        var source = feed;
        if (query?['scope'] == 'following') {
          source = [
            for (final p in feed)
              if ((follows[viewer]?.contains(
                        (p['author'] as Map)['username'],
                      ) ??
                      false) ||
                  (p['author'] as Map)['username'] == viewer)
                p,
          ];
        }
        return _page([for (final p in source) decorate(p, viewer)], query);
      case 'POST /posts':
        final username = requireUser();
        final me = users[username]!;
        final media = [
          for (final m in (data!['media'] as List))
            {
              'id': 'pm-${m['asset_id']}',
              'type': 'image',
              'url': '/media/u/${m['asset_id']}.png',
              'width': 100,
              'height': 80,
              'alt_text': null,
            },
        ];
        final post = postJson(
          'created-${created.length}',
          body: data['body'] as String?,
          location: data['location_text'] as String?,
          username: username,
          authorId: me['id'] as String,
          displayName: (me['profile'] as Map)['display_name'] as String?,
          media: media,
        )..['tags'] = data['tags'];
        created.add(post);
        feed.insert(0, post);
        return decorate(post, username);
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

/// Builds a post JSON payload shaped like the API's `PostRead`.
Map<String, dynamic> postJson(
  String id, {
  String? body = 'A sample post',
  String? location,
  String username = 'seed_rahim',
  String authorId = 'author-1',
  String? displayName = '[Seed] Rahim',
  List<Map<String, dynamic>> media = const [],
  String createdAt = '2026-01-01T00:00:00+00:00',
}) => {
  'id': id,
  'body': body,
  'location_text': location,
  'place_id': null,
  'media': media,
  'author': {'id': authorId, 'username': username, 'display_name': displayName},
  'created_at': createdAt,
  'updated_at': createdAt,
};
