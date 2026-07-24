import '../database/app_database.dart';

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
}

class BackendSession {
  const BackendSession({required this.token, required this.account});

  final String token;
  final BackendAccount account;
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
}

abstract interface class BackendGateway {
  Future<BackendSession> signIn({
    required String username,
    required String password,
  });

  Future<BackendSession?> restoreSession(String token);

  Future<List<BackendPlaylist>> syncPlaylists(
    BackendSession session,
    List<BackendPlaylist> playlists,
  );
}

/// A local stand-in for the future HTTP backend. It keeps the same boundaries
/// as a real service so the UI and database do not need to change later.
class MockBackendGateway implements BackendGateway {
  static final Map<String, List<BackendPlaylist>> _playlistsByUser = {};
  static final Map<String, BackendSession> _sessions = {};

  @override
  Future<BackendSession> signIn({
    required String username,
    required String password,
  }) async {
    final normalized = username.trim().toLowerCase();
    final account = BackendAccount(
      remoteId: 'account-$normalized',
      username: normalized,
      displayName: normalized.split('@').first,
    );
    final session = BackendSession(
      token: 'mock-session-$normalized',
      account: account,
    );
    _sessions[session.token] = session;
    _playlistsByUser.putIfAbsent(normalized, () => <BackendPlaylist>[]);
    return session;
  }

  @override
  Future<BackendSession?> restoreSession(String token) async {
    final existing = _sessions[token];
    if (existing != null) return existing;
    const prefix = 'mock-session-';
    if (!token.startsWith(prefix)) return null;
    final username = token.substring(prefix.length);
    if (username.isEmpty) return null;
    final session = BackendSession(
      token: token,
      account: BackendAccount(
        remoteId: 'account-$username',
        username: username,
        displayName: username.split('@').first,
      ),
    );
    _sessions[token] = session;
    _playlistsByUser.putIfAbsent(username, () => <BackendPlaylist>[]);
    return session;
  }

  @override
  Future<List<BackendPlaylist>> syncPlaylists(
    BackendSession session,
    List<BackendPlaylist> playlists,
  ) async {
    final username = session.account.username;
    final existing = _playlistsByUser[username] ?? <BackendPlaylist>[];
    final byId = {for (final item in existing) item.remoteId: item};
    for (final playlist in playlists) {
      byId[playlist.remoteId] = playlist;
    }
    final result = byId.values.toList(growable: false);
    _playlistsByUser[username] = result;
    return result;
  }
}
