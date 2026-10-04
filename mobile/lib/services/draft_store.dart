import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Locally persisted, unsent post text. Photos are intentionally not part of a
/// draft (they are uploaded immediately and could be orphaned).
class PostDraft {
  const PostDraft({this.text = '', this.location = '', this.tags = const []});
  final String text;
  final String location;
  final List<String> tags;

  bool get isEmpty =>
      text.trim().isEmpty && location.trim().isEmpty && tags.isEmpty;

  Map<String, dynamic> toJson() => {
    'text': text,
    'location': location,
    'tags': tags,
  };

  factory PostDraft.fromJson(Map<String, dynamic> json) => PostDraft(
    text: json['text'] as String? ?? '',
    location: json['location'] as String? ?? '',
    tags: [for (final t in (json['tags'] as List? ?? const [])) t as String],
  );
}

abstract interface class DraftStore {
  Future<PostDraft?> load(String userId);
  Future<void> save(String userId, PostDraft draft);
  Future<void> clear(String userId);
}

/// Drafts are keyed per user so accounts on one device never see each other's.
class PrefsDraftStore implements DraftStore {
  static String _key(String userId) => 'angon_post_draft_$userId';

  @override
  Future<PostDraft?> load(String userId) async {
    final raw = (await SharedPreferences.getInstance()).getString(_key(userId));
    if (raw == null) return null;
    try {
      return PostDraft.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null; // corrupt draft: ignore rather than crash the composer
    }
  }

  @override
  Future<void> save(String userId, PostDraft draft) async {
    final prefs = await SharedPreferences.getInstance();
    if (draft.isEmpty) {
      await prefs.remove(_key(userId));
    } else {
      await prefs.setString(_key(userId), jsonEncode(draft.toJson()));
    }
  }

  @override
  Future<void> clear(String userId) async =>
      (await SharedPreferences.getInstance()).remove(_key(userId));
}

class InMemoryDraftStore implements DraftStore {
  final _drafts = <String, PostDraft>{};

  @override
  Future<PostDraft?> load(String userId) async => _drafts[userId];

  @override
  Future<void> save(String userId, PostDraft draft) async {
    if (draft.isEmpty) {
      _drafts.remove(userId);
    } else {
      _drafts[userId] = draft;
    }
  }

  @override
  Future<void> clear(String userId) async => _drafts.remove(userId);
}
