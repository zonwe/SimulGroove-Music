import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import 'backend_gateway.dart';

class SyncResult {
  const SyncResult({required this.uploaded, required this.downloaded});

  final int uploaded;
  final int downloaded;
}

abstract interface class AuthRepository {
  Future<void> signIn({required String username, required String password});

  Future<void> signOut();

  Future<SyncResult> syncNow();
}

class MockAuthRepository implements AuthRepository {
  MockAuthRepository(this._database, this._gateway);

  static const _sessionKey = 'auth.session.token';

  final AppDatabase _database;
  final BackendGateway _gateway;
  final Uuid _uuid = const Uuid();
  BackendSession? _session;

  @override
  Future<void> signIn({
    required String username,
    required String password,
  }) async {
    final normalized = username.trim();
    if (normalized.isEmpty || password.isEmpty) {
      throw const FormatException('请输入账号和密码');
    }
    _session = await _gateway.signIn(username: normalized, password: password);
    final now = DateTime.now();
    final account = _session!.account;
    await _database.saveAccount(
      AccountsCompanion.insert(
        id: _uuid.v5(Namespace.url.value, 'account:${account.remoteId}'),
        remoteId: Value(account.remoteId),
        username: account.username,
        displayName: account.displayName,
        avatarUri: Value(account.avatarUri),
        createdAt: now,
        updatedAt: now,
        isMock: const Value(true),
      ),
    );
    await _database.setSetting(_sessionKey, _session!.token);
  }

  @override
  Future<void> signOut() async {
    _session = null;
    await _database.setSetting(_sessionKey, '');
    await _database.clearAccounts();
  }

  @override
  Future<SyncResult> syncNow() async {
    final session = await _loadSession();
    if (session == null) {
      throw StateError('请先登录账号');
    }
    final account = await _database.watchCurrentAccount().first;
    if (account == null) throw StateError('账号信息不存在，请重新登录');

    final localPlaylists = await _database.watchPlaylists().first;
    final payload = <BackendPlaylist>[];
    for (final playlist in localPlaylists) {
      final tracks = await _database.watchPlaylistTracks(playlist.id).first;
      payload.add(
        BackendPlaylist(
          remoteId: playlist.remoteId ?? 'playlist-${playlist.id}',
          name: playlist.name,
          updatedAt: playlist.updatedAt,
          tracks: tracks.map(BackendTrack.fromLocal).toList(growable: false),
        ),
      );
    }

    final remotePlaylists = await _gateway.syncPlaylists(session, payload);
    final localByRemoteId = {
      for (final playlist in localPlaylists)
        if (playlist.remoteId != null) playlist.remoteId!: playlist,
    };
    var downloaded = 0;
    for (final remote in remotePlaylists) {
      var local = localByRemoteId[remote.remoteId];
      if (local == null) {
        final now = DateTime.now();
        final localId = _uuid.v4();
        await _database.createPlaylist(
          PlaylistsCompanion.insert(
            id: localId,
            remoteId: Value(remote.remoteId),
            accountId: Value(account.id),
            name: remote.name,
            syncState: const Value('synced'),
            createdAt: now,
            updatedAt: remote.updatedAt,
          ),
        );
        local = (await _database.watchPlaylists().first).firstWhere(
          (item) => item.id == localId,
        );
        downloaded++;
        for (final track in remote.tracks) {
          final localTrack = await _database.findTrackByUri(track.uri);
          if (localTrack != null) {
            await _database.addTrackToPlaylist(local.id, localTrack.id);
          }
        }
      }
      await _database.updatePlaylistSync(
        id: local.id,
        remoteId: remote.remoteId,
        accountId: account.id,
      );
    }
    return SyncResult(uploaded: payload.length, downloaded: downloaded);
  }

  Future<BackendSession?> _loadSession() async {
    if (_session != null) return _session;
    final token = await _database.readSetting(_sessionKey);
    if (token == null || token.isEmpty) return null;
    _session = await _gateway.restoreSession(token);
    return _session;
  }
}
