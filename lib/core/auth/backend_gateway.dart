import '../database/app_database.dart';
import 'track_match_token.dart';

/// 编译期注入的后端地址兜底值。仓库内不再包含任何真实内网 IP，
/// 运行时地址优先读取 AppSettings（backend.base_url，账号页可配置）。
const defaultBackendBaseUrl = String.fromEnvironment(
  'MUSIC_API_URL',
  defaultValue: '',
);

/// AppSettings 中保存后端服务器地址的键。
const backendBaseUrlSettingKey = 'backend.base_url';

/// 规范化用户输入或存储的服务器地址：去空白并去掉结尾多余的斜杠。
String normalizeBackendBaseUrl(String value) =>
    value.trim().replaceFirst(RegExp(r'/+$'), '');

/// 每次请求前读取运行时配置的后端地址（AppSettings）。
typedef BackendBaseUrlReader = Future<String?> Function();

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
    this.trackMatchSalt,
    this.trackMatchKey,
  });

  final String token;
  final String refreshToken;
  final DateTime expiresAt;
  final BackendAccount account;
  final String? trackMatchSalt;

  /// 仅保存在本机安全存储中，绝不发送给后端。
  final String? trackMatchKey;

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
    trackMatchSalt: json['trackMatchSalt'] as String?,
  );

  BackendSession withTrackMatchKey(String? value) => BackendSession(
    token: token,
    refreshToken: refreshToken,
    expiresAt: expiresAt,
    account: account,
    trackMatchSalt: trackMatchSalt,
    trackMatchKey: value,
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
    this.updatedAt,
    this.matchToken,
  });

  final String uri;
  final String title;
  final String artist;
  final String album;
  final int? durationMs;
  final DateTime? updatedAt;
  final String? matchToken;

  factory BackendTrack.fromLocal(
    Track track, {
    DateTime? updatedAt,
    String? trackMatchKey,
  }) => BackendTrack(
    uri: track.uri,
    title: track.title,
    artist: track.artist,
    album: track.album,
    durationMs: track.durationMs,
    updatedAt: updatedAt,
    matchToken: createTrackMatchToken(
      contentFingerprint: track.contentFingerprint,
      trackMatchKey: trackMatchKey,
    ),
  );

  factory BackendTrack.fromJson(Map<String, dynamic> json) => BackendTrack(
    uri: json['uri'] as String,
    title: json['title'] as String,
    artist: json['artist'] as String,
    album: json['album'] as String,
    durationMs: json['durationMs'] as int?,
    updatedAt: json['updatedAt'] is String
        ? DateTime.parse(json['updatedAt'] as String).toLocal()
        : null,
    matchToken: json['matchToken'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'uri': uri,
    'title': title,
    'artist': artist,
    'album': album,
    'durationMs': durationMs,
    if (updatedAt case final value?)
      'updatedAt': value.toUtc().toIso8601String(),
    'matchToken': matchToken,
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

enum SyncEntityType {
  playlist('playlist'),
  likedTrack('likedTrack'),
  equalizerPreset('equalizerPreset');

  const SyncEntityType(this.wireName);

  final String wireName;

  static SyncEntityType fromWireName(String value) => values.firstWhere(
    (type) => type.wireName == value,
    orElse: () => throw FormatException('未知同步删除类型：$value'),
  );
}

class BackendDeletion {
  const BackendDeletion({
    required this.entityType,
    required this.remoteKey,
    required this.deletedAt,
  });

  final SyncEntityType entityType;
  final String remoteKey;
  final DateTime deletedAt;

  factory BackendDeletion.fromJson(Map<String, dynamic> json) =>
      BackendDeletion(
        entityType: SyncEntityType.fromWireName(json['entityType'] as String),
        remoteKey: json['remoteKey'] as String,
        deletedAt: DateTime.parse(json['deletedAt'] as String).toLocal(),
      );

  Map<String, dynamic> toJson() => {
    'entityType': entityType.wireName,
    'remoteKey': remoteKey,
    'deletedAt': deletedAt.toUtc().toIso8601String(),
  };
}

class BackendLibrary {
  const BackendLibrary({
    required this.playlists,
    required this.likedTracks,
    this.equalizerPresets = const [],
    this.deletions = const [],
  });

  final List<BackendPlaylist> playlists;
  final List<BackendTrack> likedTracks;
  final List<BackendEqualizerPreset> equalizerPresets;
  final List<BackendDeletion> deletions;
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
    List<BackendDeletion> deletions = const [],
  ]);
}
