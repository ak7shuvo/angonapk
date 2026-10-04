/// Creator identity chosen during profile setup. Values match the API enum.
enum CreatorType {
  traveler('traveler', 'Traveller'),
  storyteller('storyteller', 'Storyteller'),
  blogger('blogger', 'Blogger'),
  photographer('photographer', 'Photographer'),
  videographer('videographer', 'Videographer'),
  localStoryteller('local_storyteller', 'Local storyteller'),
  researcher('researcher', 'Researcher'),
  tourismBusiness('tourism_business', 'Tourism business'),
  guide('guide', 'Guide'),
  communityOrganization('community_organization', 'Community organisation');

  const CreatorType(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static CreatorType? fromApi(String? value) {
    for (final t in values) {
      if (t.apiValue == value) return t;
    }
    return null;
  }
}

class Profile {
  const Profile({
    this.displayName,
    this.bio,
    this.location,
    this.creatorType,
    required this.isComplete,
  });

  final String? displayName;
  final String? bio;
  final String? location;
  final CreatorType? creatorType;

  /// Computed by the server; drives the profile-setup redirect.
  final bool isComplete;

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
    displayName: json['display_name'] as String?,
    bio: json['bio'] as String?,
    location: json['location'] as String?,
    creatorType: CreatorType.fromApi(json['creator_type'] as String?),
    isComplete: json['is_complete'] as bool,
  );
}

class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.username,
    required this.profile,
  });

  final String id;
  final String email;
  final String username;
  final Profile profile;

  String get displayName => profile.displayName ?? username;

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: json['id'] as String,
    email: json['email'] as String,
    username: json['username'] as String,
    profile: Profile.fromJson(json['profile'] as Map<String, dynamic>),
  );
}

/// Response of register / login.
class AuthSession {
  const AuthSession({required this.accessToken, required this.user});

  final String accessToken;
  final AppUser user;

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
    accessToken: json['access_token'] as String,
    user: AppUser.fromJson(json['user'] as Map<String, dynamic>),
  );
}
