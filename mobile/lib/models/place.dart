/// Compact reference embedded in posts and stories.
class PlaceBrief {
  const PlaceBrief({
    required this.id,
    required this.slug,
    required this.name,
    this.nameLocal,
  });

  final String id;
  final String slug;
  final String name;
  final String? nameLocal;

  factory PlaceBrief.fromJson(Map<String, dynamic> json) => PlaceBrief(
    id: json['id'] as String,
    slug: json['slug'] as String,
    name: json['name'] as String,
    nameLocal: json['name_local'] as String?,
  );
}

/// Place as listed (search, map, explore).
class PlaceSummary extends PlaceBrief {
  const PlaceSummary({
    required super.id,
    required super.slug,
    required super.name,
    super.nameLocal,
    required this.latitude,
    required this.longitude,
    this.coverUrl,
    this.division,
    this.district,
    this.postCount = 0,
    this.storyCount = 0,
    this.distanceKm,
  });

  final double latitude;
  final double longitude;

  /// Raw API value (may be storage-relative).
  final String? coverUrl;
  final String? division;
  final String? district;
  final int postCount;
  final int storyCount;

  /// Only for proximity searches.
  final double? distanceKm;

  /// "Sylhet, Sylhet Division" style line (skips duplicates and blanks).
  String get locationLine {
    final parts = <String>[?district, if (division != district) ?division];
    return parts.join(', ');
  }

  factory PlaceSummary.fromJson(Map<String, dynamic> json) => PlaceSummary(
    id: json['id'] as String,
    slug: json['slug'] as String,
    name: json['name'] as String,
    nameLocal: json['name_local'] as String?,
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
    coverUrl: json['cover_url'] as String?,
    division: json['division'] as String?,
    district: json['district'] as String?,
    postCount: json['post_count'] as int? ?? 0,
    storyCount: json['story_count'] as int? ?? 0,
    distanceKm: (json['distance_km'] as num?)?.toDouble(),
  );
}

class PlaceDetail extends PlaceSummary {
  const PlaceDetail({
    required super.id,
    required super.slug,
    required super.name,
    super.nameLocal,
    required super.latitude,
    required super.longitude,
    super.coverUrl,
    super.division,
    super.district,
    super.postCount,
    super.storyCount,
    super.distanceKm,
    required this.description,
    required this.country,
    this.upazila,
    this.metadata = const {},
  });

  final String description;
  final String country;
  final String? upazila;
  final Map<String, dynamic> metadata;

  /// True for development seed content (never shown as verified information).
  bool get isSeed => metadata['seed'] == true;

  @override
  String get locationLine {
    final parts = <String>[
      ?upazila,
      ?district,
      if (division != district) ?division,
    ];
    return parts.join(', ');
  }

  factory PlaceDetail.fromJson(Map<String, dynamic> json) {
    final s = PlaceSummary.fromJson(json);
    return PlaceDetail(
      id: s.id,
      slug: s.slug,
      name: s.name,
      nameLocal: s.nameLocal,
      latitude: s.latitude,
      longitude: s.longitude,
      coverUrl: s.coverUrl,
      division: s.division,
      district: s.district,
      postCount: s.postCount,
      storyCount: s.storyCount,
      distanceKm: s.distanceKm,
      description: json['description'] as String? ?? '',
      country: json['country'] as String? ?? 'Bangladesh',
      upazila: json['upazila'] as String?,
      metadata: Map<String, dynamic>.from(json['metadata'] as Map? ?? const {}),
    );
  }
}

class PlaceList {
  const PlaceList({required this.items, required this.total});
  final List<PlaceSummary> items;
  final int total;

  factory PlaceList.fromJson(Map<String, dynamic> json) => PlaceList(
    items: [
      for (final p in json['items'] as List)
        PlaceSummary.fromJson(p as Map<String, dynamic>),
    ],
    total: json['total'] as int,
  );
}

class PlacePhoto {
  const PlacePhoto({
    required this.id,
    required this.url,
    required this.postId,
    this.width,
    this.height,
  });
  final String id;
  final String url;
  final String postId;
  final int? width;
  final int? height;

  factory PlacePhoto.fromJson(
    Map<String, dynamic> json, {
    String mediaBaseUrl = '',
  }) {
    final raw = json['url'] as String;
    return PlacePhoto(
      id: json['id'] as String,
      url: raw.startsWith('/') ? '$mediaBaseUrl$raw' : raw,
      postId: json['post_id'] as String,
      width: json['width'] as int?,
      height: json['height'] as int?,
    );
  }
}

class PlacePhotoPage {
  const PlacePhotoPage({required this.items, this.nextCursor});
  final List<PlacePhoto> items;
  final String? nextCursor;
}
