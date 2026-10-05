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

  /// Body of the most recent PATCH /users/me/profile (to assert what was sent).
  Map<String, dynamic>? lastProfilePatch;

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

  /// Reports filed via `POST /reports`.
  final reports = <Map<String, dynamic>>[];

  /// Notifications served by `/notifications`, newest first.
  final notifications = <Map<String, dynamic>>[];

  /// Query strings of every GET /search the app made (to assert debouncing).
  final searchCalls = <Map<String, String>>[];

  // Places (by slug) and the photos shown on a place page.
  final places = <Map<String, dynamic>>[];
  final placePhotos = <String, List<Map<String, dynamic>>>{};

  // Stories.
  final stories = <Map<String, dynamic>>[];
  final storyLikes = <String, Set<String>>{};
  final storySaves = <String, List<String>>{};
  int _storySeq = 0;

  Map<String, dynamic> decorateStory(
    Map<String, dynamic> story,
    String viewer,
  ) {
    final id = story['id'] as String;
    final author = (story['author'] as Map)['username'] as String;
    return {
      ...story,
      'like_count': storyLikes[id]?.length ?? 0,
      'liked_by_me': storyLikes[id]?.contains(viewer) ?? false,
      'saved_by_me': storySaves[id]?.contains(viewer) ?? false,
      'following_author': follows[viewer]?.contains(author) ?? false,
    };
  }

  Map<String, dynamic> _summaryOf(Map<String, dynamic> story) {
    final copy = {...story}
      ..remove('content')
      ..remove('media');
    return copy;
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
    if (method == 'POST' && path == '/reports') {
      final me = requireUser();
      final key = '${data!['target_type']}:${data['target_id']}';
      if (reports.any((r) => r['key'] == key && r['reporter'] == me)) {
        throw const ValidationException('You have already reported this');
      }
      reports.add({...data, 'key': key, 'reporter': me});
      return {
        'id': 'r${reports.length}',
        'target_type': data['target_type'],
        'target_id': data['target_id'],
        'reason': data['reason'],
        'status': 'open',
      };
    }
    if (path.startsWith('/notifications')) {
      requireUser();
      if (method == 'GET' && path == '/notifications/unread-count') {
        return {
          'unread': notifications.where((n) => n['is_read'] != true).length,
        };
      }
      if (method == 'POST' && path == '/notifications/read-all') {
        for (final n in notifications) {
          n['is_read'] = true;
        }
        return null;
      }
      final read = RegExp(r'^/notifications/([^/]+)/read$').firstMatch(path);
      if (method == 'POST' && read != null) {
        final n = notifications.firstWhere((n) => n['id'] == read.group(1));
        n['is_read'] = true;
        return n;
      }
      if (method == 'GET' && path == '/notifications') {
        final unreadOnly = query?['unread_only'] == 'true';
        return _page([
          for (final n in notifications)
            if (!unreadOnly || n['is_read'] != true) n,
        ], query);
      }
    }
    if (path == '/map/nearby') {
      final viewer = requireUser();
      return {
        'places': [for (final p in places) placeSummary(p)],
        'posts': [
          for (final p in feed)
            if (p['place'] != null) decorate(p, viewer),
        ],
        'stories': [
          for (final s in stories)
            if (s['status'] == 'published' && s['place'] != null)
              _summaryOf(decorateStory(s, viewer)),
        ],
      };
    }
    if (path == '/explore') {
      final viewer = requireUser();
      return _explore(viewer);
    }
    if (path == '/search') {
      final viewer = requireUser();
      searchCalls.add({...?query});
      return _search(viewer, query!);
    }
    if (path == '/places' || path.startsWith('/places/')) {
      final viewer = requireUser();
      return _handlePlaces(path, query, viewer);
    }
    final userPlaces = RegExp(r'^/users/([^/]+)/places$').firstMatch(path);
    if (userPlaces != null) {
      requireUser();
      final target = userPlaces.group(1)!;
      if (!users.containsKey(target)) {
        throw const NotFoundException('User not found');
      }
      final slugs = {
        for (final p in feed)
          if ((p['author'] as Map)['username'] == target && p['place'] != null)
            (p['place'] as Map)['slug'],
      };
      return [
        for (final pl in places)
          if (slugs.contains(pl['slug'])) placeSummary(pl),
      ];
    }
    if (path == '/stories' ||
        path.startsWith('/stories/') ||
        path == '/users/me/saved/stories') {
      final viewer = requireUser();
      final result = _handleStories(method, path, data, query, viewer);
      return result;
    }
    if (path == '/users/me/saved/posts') {
      final viewer = requireUser();
      return _page([
        for (final p in feed)
          if (saves[p['id']]?.contains(viewer) ?? false) decorate(p, viewer),
      ], query);
    }
    final userPosts = RegExp(r'^/users/([^/]+)/posts$').firstMatch(path);
    if (userPosts != null && method == 'GET') {
      final viewer = requireUser();
      final target = userPosts.group(1)!;
      if (!users.containsKey(target)) {
        throw const NotFoundException('User not found');
      }
      return _page([
        for (final p in feed)
          if ((p['author'] as Map)['username'] == target) decorate(p, viewer),
      ], query);
    }
    final publicProfile = RegExp(r'^/users/([^/]+)$').firstMatch(path);
    if (publicProfile != null &&
        method == 'GET' &&
        publicProfile.group(1) != 'me') {
      final viewer = requireUser();
      final target = publicProfile.group(1)!;
      final u = users[target];
      if (u == null) throw const NotFoundException('User not found');
      final profile = u['profile'] as Map;
      return {
        'id': u['id'],
        'username': target,
        'display_name': profile['display_name'],
        'bio': profile['bio'],
        'location': profile['location'],
        'creator_type': profile['creator_type'],
        'avatar_url': profile['avatar_url'],
        'cover_url': profile['cover_url'],
        'joined_at': '2026-01-01T00:00:00+00:00',
        'counts': {
          'posts': feed
              .where((p) => (p['author'] as Map)['username'] == target)
              .length,
          'stories': stories
              .where(
                (s) =>
                    (s['author'] as Map)['username'] == target &&
                    s['status'] == 'published',
              )
              .length,
          'followers': follows.values.where((f) => f.contains(target)).length,
          'following': follows[target]?.length ?? 0,
          'places': 0,
        },
        'is_following': follows[viewer]?.contains(target) ?? false,
        'is_me': target == viewer,
      };
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
        final placeId = data['place_id'] as String?;
        final place = placeId == null
            ? null
            : places.firstWhere(
                (p) => p['id'] == placeId,
                orElse: () => throw const ValidationException('Unknown place'),
              );
        final post = postJson(
          'created-${created.length}',
          body: data['body'] as String?,
          location:
              data['location_text'] as String? ?? place?['name'] as String?,
          place: place == null ? null : placeBrief(place),
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
        for (final e in data!.entries) {
          switch (e.key) {
            case 'avatar_media_id':
              profile['avatar_url'] = e.value == null
                  ? null
                  : '/media/u/${e.value}.png';
            case 'cover_media_id':
              profile['cover_url'] = e.value == null
                  ? null
                  : '/media/u/${e.value}.png';
            default:
              profile[e.key] = e.value;
          }
        }
        lastProfilePatch = Map.of(data);
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
  Map<String, dynamic>? place,
}) => {
  'id': id,
  'body': body,
  'location_text': location,
  'place_id': place?['id'],
  'place': place,
  'media': media,
  'author': {'id': authorId, 'username': username, 'display_name': displayName},
  'created_at': createdAt,
  'updated_at': createdAt,
};

extension _StoryRoutes on FakeBackend {
  dynamic _handleStories(
    String method,
    String path,
    Map<String, dynamic>? data,
    Map<String, String>? query,
    String viewer,
  ) {
    Map<String, dynamic>? byRef(String ref) {
      final found = stories.where((s) => s['id'] == ref || s['slug'] == ref);
      if (found.isEmpty) return null;
      final story = found.first;
      final mine = (story['author'] as Map)['username'] == viewer;
      if (story['status'] != 'published' && !mine) return null;
      return story;
    }

    Map<String, dynamic> owned(String id) {
      final story = byRef(id);
      if (story == null) throw const NotFoundException('Story not found');
      if ((story['author'] as Map)['username'] != viewer) {
        throw const ForbiddenException('You can only change your own stories');
      }
      return story;
    }

    int readingMinutes(String content) {
      final words = content
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .length;
      return (words / 200).ceil().clamp(1, 1 << 30);
    }

    void applyFields(Map<String, dynamic> story, Map<String, dynamic> d) {
      for (final key in ['title', 'content', 'location_text', 'tags']) {
        if (d.containsKey(key)) story[key] = d[key];
      }
      if (d.containsKey('cover_asset_id')) {
        final id = d['cover_asset_id'];
        story['cover'] = id == null
            ? null
            : {
                'id': id,
                'url': '/media/u/$id.png',
                'width': 1600,
                'height': 900,
              };
      }
      if (d.containsKey('place_id')) {
        final id = d['place_id'];
        story['place_id'] = id;
        story['place'] = id == null
            ? null
            : placeBrief(places.firstWhere((p) => p['id'] == id));
      }
      story['summary'] = (story['content'] as String)
          .split(RegExp(r'\n\s*\n'))
          .firstWhere((p) => p.trim().isNotEmpty, orElse: () => '');
      story['reading_minutes'] = readingMinutes(story['content'] as String);
      story['updated_at'] = '2026-02-01T00:00:00+00:00';
    }

    void requirePublishable(Map<String, dynamic> story) {
      if ((story['title'] as String).trim().isEmpty ||
          (story['content'] as String).trim().isEmpty) {
        throw const ValidationException(
          'A story needs a title and some content to be published',
        );
      }
    }

    if (method == 'POST' && path == '/stories') {
      final me = users[viewer]!;
      final id = 'story-${_storySeq++}';
      final story = <String, dynamic>{
        'id': id,
        'slug': 'slug-$id',
        'title': '',
        'content': '',
        'summary': '',
        'cover': null,
        'location_text': null,
        'place_id': null,
        'tags': <String>[],
        'status': 'draft',
        'published_at': null,
        'reading_minutes': 1,
        'media': <Map<String, dynamic>>[],
        'author': {
          'id': me['id'],
          'username': viewer,
          'display_name': (me['profile'] as Map)['display_name'],
        },
      };
      applyFields(story, data!);
      if (data['status'] == 'published') {
        requirePublishable(story);
        story['status'] = 'published';
        story['published_at'] = '2026-02-01T00:00:00+00:00';
      }
      stories.insert(0, story);
      return decorateStory(story, viewer);
    }
    if (method == 'GET' && path == '/stories') {
      var list = [
        for (final s in stories)
          if (s['status'] == 'published') s,
      ];
      final author = query?['author'];
      if (author != null) {
        list = [
          for (final s in list)
            if ((s['author'] as Map)['username'] == author) s,
        ];
      }
      final tag = query?['tag'];
      if (tag != null) {
        list = [
          for (final s in list)
            if ((s['tags'] as List).contains(tag)) s,
        ];
      }
      return _pageOf([
        for (final s in list) _summaryOf(decorateStory(s, viewer)),
      ], query);
    }
    if (method == 'GET' && path == '/stories/mine') {
      final status = query?['status'] ?? 'all';
      return _pageOf([
        for (final s in stories)
          if ((s['author'] as Map)['username'] == viewer &&
              (status == 'all' || s['status'] == status))
            _summaryOf(decorateStory(s, viewer)),
      ], query);
    }
    if (method == 'GET' && path == '/users/me/saved/stories') {
      return _pageOf([
        for (final s in stories)
          if (storySaves[s['id']]?.contains(viewer) ?? false)
            _summaryOf(decorateStory(s, viewer)),
      ], query);
    }
    final m = RegExp(
      r'^/stories/([^/]+)(?:/(related|publish|unpublish|like|save))?$',
    ).firstMatch(path);
    if (m == null) throw const NotFoundException();
    final ref = m.group(1)!;
    switch ((method, m.group(2))) {
      case ('GET', null):
        final story = byRef(ref);
        if (story == null) throw const NotFoundException('Story not found');
        return decorateStory(story, viewer);
      case ('GET', 'related'):
        final story = byRef(ref);
        if (story == null) throw const NotFoundException('Story not found');
        return [
          for (final s in stories)
            if (s['status'] == 'published' && s['id'] != story['id'])
              _summaryOf(decorateStory(s, viewer)),
        ];
      case ('PATCH', null):
        final story = owned(ref);
        applyFields(story, data!);
        if (story['status'] == 'published') requirePublishable(story);
        return decorateStory(story, viewer);
      case ('POST', 'publish'):
        final story = owned(ref);
        requirePublishable(story);
        story['status'] = 'published';
        story['published_at'] ??= '2026-02-01T00:00:00+00:00';
        return decorateStory(story, viewer);
      case ('POST', 'unpublish'):
        final story = owned(ref);
        story['status'] = 'draft';
        return decorateStory(story, viewer);
      case ('DELETE', null):
        final story = owned(ref);
        stories.remove(story);
        return null;
      case ('PUT', 'like'):
        (storyLikes[ref] ??= {}).add(viewer);
        return {'liked': true, 'like_count': storyLikes[ref]!.length};
      case ('DELETE', 'like'):
        storyLikes[ref]?.remove(viewer);
        return {'liked': false, 'like_count': storyLikes[ref]?.length ?? 0};
      case ('PUT', 'save'):
        final list = storySaves[ref] ??= [];
        if (!list.contains(viewer)) {
          list.add(viewer);
        }
        return null;
      case ('DELETE', 'save'):
        storySaves[ref]?.remove(viewer);
        return null;
    }
    throw const NotFoundException();
  }

  Map<String, dynamic> _pageOf(
    List<Map<String, dynamic>> all,
    Map<String, String>? query,
  ) => _page(all, query);
}

/// A published story as the API would return it (full body).
Map<String, dynamic> storyJson(
  String id, {
  String title = 'Jaflong: Beyond the Tourist View',
  String content =
      'The stones at Jaflong tell a quieter story.\n\nSecond paragraph.',
  String status = 'published',
  String username = 'seed_nusrat',
  String authorId = 'author-2',
  String? displayName = '[Seed] Nusrat',
  List<String> tags = const ['heritage'],
  String? location = 'Jaflong, Sylhet',
  Map<String, dynamic>? cover,
  List<Map<String, dynamic>> media = const [],
  Map<String, dynamic>? place,
}) => {
  'id': id,
  'slug': 'slug-$id',
  'title': title,
  'content': content,
  'summary': content.split('\n\n').first,
  'cover': cover,
  'location_text': location,
  'place_id': place?['id'],
  'place': place,
  'tags': tags,
  'status': status,
  'published_at': status == 'published' ? '2026-01-01T00:00:00+00:00' : null,
  'updated_at': '2026-01-01T00:00:00+00:00',
  'reading_minutes': 1,
  'media': media,
  'author': {'id': authorId, 'username': username, 'display_name': displayName},
};

/// A place as the API lists it (summary fields).
Map<String, dynamic> placeJson(
  String slug, {
  String? name,
  String? nameLocal,
  double lat = 25.0,
  double lng = 92.0,
  String? division = 'Sylhet',
  String? district = 'Sylhet',
  String? upazila,
  String description = 'A sample destination.',
  Map<String, dynamic> metadata = const {'seed': true},
  int postCount = 0,
  int storyCount = 0,
  String? coverUrl,
}) => {
  'id': 'place-$slug',
  'slug': slug,
  'name': name ?? slug,
  'name_local': nameLocal,
  'cover_url': coverUrl,
  'latitude': lat,
  'longitude': lng,
  'division': division,
  'district': district,
  'upazila': upazila,
  'country': 'Bangladesh',
  'description': description,
  'metadata': metadata,
  'post_count': postCount,
  'story_count': storyCount,
  'distance_km': null,
};

Map<String, dynamic> placeBrief(Map<String, dynamic> place) => {
  'id': place['id'],
  'slug': place['slug'],
  'name': place['name'],
  'name_local': place['name_local'],
};

Map<String, dynamic> placeSummary(Map<String, dynamic> place) => {...place}
  ..remove('description')
  ..remove('metadata');

extension _PlaceRoutes on FakeBackend {
  dynamic _handlePlaces(
    String path,
    Map<String, String>? query,
    String viewer,
  ) {
    Map<String, dynamic> bySlug(String slug) {
      final found = places.where((p) => p['slug'] == slug);
      if (found.isEmpty) throw const NotFoundException('Place not found');
      return found.first;
    }

    if (path == '/places') {
      final q = (query?['q'] ?? '').toLowerCase();
      final division = query?['division']?.toLowerCase();
      final filtered = [
        for (final p in places)
          if ((q.isEmpty ||
                  '${p['name']} ${p['name_local'] ?? ''} ${p['district']} ${p['division']}'
                      .toLowerCase()
                      .contains(q)) &&
              (division == null ||
                  (p['division'] as String?)?.toLowerCase() == division))
            p,
      ];
      final hasBounds = query?['min_lat'] != null;
      final result = [
        for (final p in filtered)
          if (!hasBounds ||
              ((p['latitude'] as double) >= double.parse(query!['min_lat']!) &&
                  (p['latitude'] as double) <=
                      double.parse(query['max_lat']!) &&
                  (p['longitude'] as double) >=
                      double.parse(query['min_lng']!) &&
                  (p['longitude'] as double) <=
                      double.parse(query['max_lng']!)))
            placeSummary(p),
      ];
      return {'items': result, 'total': result.length};
    }
    final m = RegExp(r'^/places/([^/]+)(?:/(posts|stories|photos|creators))?$')
        .firstMatch(path);
    if (m == null) throw const NotFoundException();
    final place = bySlug(m.group(1)!);
    switch (m.group(2)) {
      case null:
        return place;
      case 'posts':
        return _page([
          for (final p in feed)
            if ((p['place'] as Map?)?['slug'] == place['slug'])
              decorate(p, viewer),
        ], query);
      case 'stories':
        return _page([
          for (final s in stories)
            if (s['status'] == 'published' &&
                (s['place'] as Map?)?['slug'] == place['slug'])
              _summaryOf(decorateStory(s, viewer)),
        ], query);
      case 'photos':
        return _page(placePhotos[place['slug']] ?? [], query);
      case 'creators':
        final names = {
          for (final p in feed)
            if ((p['place'] as Map?)?['slug'] == place['slug'])
              (p['author'] as Map)['username'] as String,
        };
        return [for (final n in names) userSummary(n, viewer)];
    }
    throw const NotFoundException();
  }
}

extension _DiscoveryRoutes on FakeBackend {
  Map<String, dynamic> _explore(String viewer) {
    const categories = [
      ['travel', 'Travel'],
      ['culture', 'Culture'],
      ['heritage', 'Heritage'],
      ['nature', 'Nature'],
      ['food', 'Food'],
      ['photography', 'Photography'],
      ['people', 'People'],
    ];
    return {
      'categories': [
        for (final c in categories)
          {
            'slug': c[0],
            'label': c[1],
            'post_count': feed
                .where((p) => (p['tags'] as List? ?? []).contains(c[0]))
                .length,
            'story_count': stories
                .where(
                  (s) =>
                      s['status'] == 'published' &&
                      (s['tags'] as List).contains(c[0]),
                )
                .length,
          },
      ],
      'trending_posts': [for (final p in feed.take(10)) decorate(p, viewer)],
      'featured_stories': [
        for (final s
            in stories.where((s) => s['status'] == 'published').take(6))
          _summaryOf(decorateStory(s, viewer)),
      ],
      'popular_places': [for (final p in places.take(8)) placeSummary(p)],
      'creators': [
        for (final u in users.keys)
          if (u != viewer &&
              (users[u]!['profile'] as Map)['is_complete'] == true)
            userSummary(u, viewer),
      ],
    };
  }

  Map<String, dynamic> _search(String viewer, Map<String, String> query) {
    final q = query['q']!.trim().toLowerCase();
    final type = query['type'] ?? 'all';
    final limit = int.parse(query['limit'] ?? '5');
    final offset = type == 'all' ? 0 : int.parse(query['offset'] ?? '0');
    List<T> window<T>(Iterable<T> all) => all.skip(offset).take(limit).toList();
    bool has(Object? v) => '$v'.toLowerCase().contains(q);
    return {
      'query': q,
      'users': type == 'all' || type == 'users'
          ? window([
              for (final u in users.keys)
                if (has(u) ||
                    has((users[u]!['profile'] as Map)['display_name']))
                  userSummary(u, viewer),
            ])
          : [],
      'stories': type == 'all' || type == 'stories'
          ? window([
              for (final s in stories)
                if (s['status'] == 'published' &&
                    (has(s['title']) || has(s['content'])))
                  _summaryOf(decorateStory(s, viewer)),
            ])
          : [],
      'posts': type == 'all' || type == 'posts'
          ? window([
              for (final p in feed)
                if (has(p['body']) || has(p['location_text']))
                  decorate(p, viewer),
            ])
          : [],
      'places': type == 'all' || type == 'places'
          ? window([
              for (final p in places)
                if (has(p['name']) ||
                    has(p['name_local']) ||
                    has(p['district']))
                  placeSummary(p),
            ])
          : [],
    };
  }
}

/// A notification as the API returns it.
Map<String, dynamic> notificationJson(
  String id, {
  String type = 'like',
  String? actor = 'maya',
  String? targetType = 'post',
  String? targetId = 'p1',
  Map<String, dynamic> data = const {},
  bool isRead = false,
}) => {
  'id': id,
  'type': type,
  'actor': actor == null
      ? null
      : {
          'id': 'u-$actor',
          'username': actor,
          'display_name': 'Name $actor',
          'avatar_url': null,
        },
  'target_type': targetType,
  'target_id': targetId,
  'data': data,
  'is_read': isRead,
  'created_at': '2026-01-02T00:00:00Z',
};
