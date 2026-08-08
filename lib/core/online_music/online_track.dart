class OnlineTrack {
  const OnlineTrack({
    required this.provider,
    required this.trackId,
    required this.title,
    required this.artists,
    required this.album,
    required this.playable,
    required this.capabilities,
    this.durationMs,
    this.artworkUrl,
  });

  final String provider;
  final String trackId;
  final String title;
  final List<String> artists;
  final String album;
  final int? durationMs;
  final String? artworkUrl;
  final bool playable;
  final Set<String> capabilities;

  String get id => '$provider:$trackId';

  factory OnlineTrack.fromJson(Map<String, dynamic> json) => OnlineTrack(
    provider: json['provider'] as String,
    trackId: json['trackId'] as String,
    title: json['title'] as String,
    artists: (json['artists'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList(growable: false),
    album: json['album'] as String? ?? '',
    durationMs: json['durationMs'] as int?,
    artworkUrl: json['artworkUrl'] as String?,
    playable: json['playable'] as bool? ?? false,
    capabilities: (json['capabilities'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toSet(),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OnlineTrack &&
          provider == other.provider &&
          trackId == other.trackId;

  @override
  int get hashCode => Object.hash(provider, trackId);
}

class OnlineMusicWarning {
  const OnlineMusicWarning({
    required this.provider,
    required this.code,
    required this.message,
  });

  final String provider;
  final String code;
  final String message;

  factory OnlineMusicWarning.fromJson(Map<String, dynamic> json) =>
      OnlineMusicWarning(
        provider: json['provider'] as String,
        code: json['code'] as String,
        message: json['message'] as String,
      );
}

class OnlineMusicSearchResult {
  const OnlineMusicSearchResult({
    required this.items,
    required this.partial,
    required this.warnings,
    this.nextCursor,
  });

  final List<OnlineTrack> items;
  final bool partial;
  final List<OnlineMusicWarning> warnings;
  final String? nextCursor;

  factory OnlineMusicSearchResult.fromJson(Map<String, dynamic> json) =>
      OnlineMusicSearchResult(
        items: (json['items'] as List<dynamic>? ?? const [])
            .map(
              (value) =>
                  OnlineTrack.fromJson((value as Map).cast<String, dynamic>()),
            )
            .toList(growable: false),
        partial: json['partial'] as bool? ?? false,
        warnings: (json['warnings'] as List<dynamic>? ?? const [])
            .map(
              (value) => OnlineMusicWarning.fromJson(
                (value as Map).cast<String, dynamic>(),
              ),
            )
            .toList(growable: false),
        nextCursor: json['nextCursor'] as String?,
      );
}

class OnlinePlaybackSource {
  const OnlinePlaybackSource({
    required this.url,
    required this.expiresAt,
    required this.headers,
    this.mimeType,
  });

  final Uri url;
  final DateTime expiresAt;
  final Map<String, String> headers;
  final String? mimeType;
}
