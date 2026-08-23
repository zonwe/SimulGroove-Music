import '../database/app_database.dart';

const defaultBackendBaseUrl = String.fromEnvironment(
  'MUSIC_API_URL',
  defaultValue: 'http://localhost:5080',
);

class BackendAccount {
  const BackendAccount({
    required this.remoteId,
    required this.username,
    required this.displayName,
    this.avatarUri,
  });

  final String remoteId;
  final String username;
  final String displayName;
  final String? avatarUri;

  factory BackendAccount.fromJson(Map<String, dynamic> json) => BackendAccount(
    remoteId: json['remoteId'] as String,
    username: json['username'] as String,
    displayName: json['displayName'] as String,
    avatarUri: json['avatarUri'] as String?,
  );
}

class BackendSession {
  const BackendSession({
    required this.token,
    required this.refreshToken,
    required this.expiresAt,
    required this.account,
  });

  final String token;
  final String refreshToken;
  final DateTime expiresAt;
  final BackendAccount account;

  bool get shouldRefresh => expiresAt.isBefore(
    DateTime.now().toUtc().add(const Duration(seconds: 30)),
  );

  factory BackendSession.fromJson(Map<String, dynamic> json) => BackendSession(
    token: json['token'] as String,
    refreshToken: json['refreshToken'] as String,
    expiresAt: DateTime.parse(json['expiresAt'] as String).toUtc(),
    account: BackendAccount.fromJson(
      (json['account'] as Map).cast<String, dynamic>(),
    ),
  );
}

class BackendPlaylist {
  const BackendPlaylist({
    required this.remoteId,
    required this.name,
    required this.updatedAt,
    required this.tracks,
  });

  final String remoteId;
  final String name;
  final DateTime updatedAt;
  final List<BackendTrack> tracks;

  factory BackendPlaylist.fromJson(Map<String, dynamic> json) =>
      BackendPlaylist(
        remoteId: json['remoteId'] as String,
        name: json['name'] as String,
        updatedAt: DateTime.parse(json['updatedAt'] as String).toLocal(),
        tracks: (json['tracks'] as List<dynamic>)
            .map(
              (value) =>
                  BackendTrack.fromJson((value as Map).cast<String, dynamic>()),
            )
            .toList(growable: false),
      );

  Map<String, dynamic> toJson() => {
    'remoteId': remoteId,
    'name': name,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'tracks': tracks.map((track) => track.toJson()).toList(growable: false),
  };
}

class BackendTrack {
  const BackendTrack({
    required this.uri,
    required this.title,
    required this.artist,
    required this.album,
    this.durationMs,
  });

  final String uri;
  final String title;
  final String artist;
  final String album;
  final int? durationMs;

  factory BackendTrack.fromLocal(Track track) => BackendTrack(
    uri: track.uri,
    title: track.title,
    artist: track.artist,
    album: track.album,
    durationMs: track.durationMs,
  );

  factory BackendTrack.fromJson(Map<String, dynamic> json) => BackendTrack(
    uri: json['uri'] as String,
    title: json['title'] as String,
    artist: json['artist'] as String,
    album: json['album'] as String,
    durationMs: json['durationMs'] as int?,
  );

  Map<String, dynamic> toJson() => {
    'uri': uri,
    'title': title,
    'artist': artist,
    'album': album,
    'durationMs': durationMs,
  };
}

class BackendEqualizerPreset {
  const BackendEqualizerPreset({
    required this.remoteId,
    required this.name,
    required this.gainsJson,
    required this.preampDb,
    required this.updatedAt,
  });

  final String remoteId;
  final String name;
  final String gainsJson;
  final double preampDb;
  final DateTime updatedAt;

  factory BackendEqualizerPreset.fromLocal(EqualizerPresetData preset) =>
      BackendEqualizerPreset(
        remoteId: preset.remoteId ?? 'preset-${preset.id}',
        name: preset.name,
        gainsJson: preset.gainsJson,
        preampDb: preset.preampDb,
        updatedAt: preset.updatedAt,
      );

  factory BackendEqualizerPreset.fromJson(Map<String, dynamic> json) =>
      BackendEqualizerPreset(
        remoteId: json['remoteId'] as String,
        name: json['name'] as String,
        gainsJson: json['gainsJson'] as String,
        preampDb: (json['preampDb'] as num?)?.toDouble() ?? 0.0,
        updatedAt: DateTime.parse(json['updatedAt'] as String).toLocal(),
      );

  Map<String, dynamic> toJson() => {
    'remoteId': remoteId,
    'name': name,
    'gainsJson': gainsJson,
    'preampDb': preampDb,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };
}

class BackendLibrary {
  const BackendLibrary({
    required this.playlists,
    required this.likedTracks,
    this.equalizerPresets = const [],
  });

  final List<BackendPlaylist> playlists;
  final List<BackendTrack> likedTracks;
  final List<BackendEqualizerPreset> equalizerPresets;
}

class BackendException implements Exception {
  const BackendException(this.message, {this.statusCode, this.code});

  final String message;
  final int? statusCode;
  final String? code;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

abstract interface class BackendGateway {
  Future<BackendSession> signIn({
    required String username,
    required String password,
  });

  Future<BackendSession> refreshSession(String refreshToken);

  Future<void> signOut(String token);

  Future<BackendLibrary> syncLibrary(
    BackendSession session,
    List<BackendPlaylist> playlists,
    List<BackendTrack> likedTracks, [
    List<BackendEqualizerPreset> equalizerPresets = const [],
  ]);
}
