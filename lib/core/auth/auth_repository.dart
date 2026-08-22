import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import 'auth_token_store.dart';
import 'backend_gateway.dart';

class SyncResult {
  const SyncResult({
    required this.uploaded,
    required this.downloaded,
    required this.uploadedLikes,
    required this.downloadedLikes,
    this.uploadedPresets = 0,
    this.downloadedPresets = 0,
  });

  final int uploaded;
  final int downloaded;
  final int uploadedLikes;
  final int downloadedLikes;
  final int uploadedPresets;
  final int downloadedPresets;
}

abstract interface class AuthRepository {
  Future<void> signIn({required String username, required String password});

  Future<void> signOut();

  Future<BackendSession?> currentSession({bool forceRefresh = false});

  Future<SyncResult> syncNow();
}

class BackendAuthRepository implements AuthRepository {
  BackendAuthRepository(this._database, this._gateway, this._tokenStore);

  // This was used by the former Mock implementation. Clear it after a real
  // login/logout so an old plaintext token is never considered active.
  static const _legacySessionKey = 'auth.session.token';

  final AppDatabase _database;
  final BackendGateway _gateway;
  final AuthTokenStore _tokenStore;
  final Uuid _uuid = const Uuid();
  BackendSession? _session;
  Future<BackendSession?>? _refreshing;

  @override
  Future<void> signIn({
    required String username,
    required String password,
  }) async {
    final normalized = username.trim();
    if (normalized.isEmpty || password.isEmpty) {
      throw const FormatException('请输入账号和密码。');
    }
    final session = await _gateway.signIn(
      username: normalized,
      password: password,
    );
    await _saveSession(session);
    await _database.setSetting(_legacySessionKey, '');
  }

  @override
  Future<void> signOut() async {
    try {
      final session = await currentSession();
      if (session != null) await _gateway.signOut(session.token);
    } on BackendException {
      // Local sign-out must still succeed when the backend is unavailable.
    } finally {
      await _clearSession();
    }
  }

  @override
  Future<BackendSession?> currentSession({bool forceRefresh = false}) async {
    final cached = _session;
    if (!forceRefresh && cached != null && !cached.shouldRefresh) return cached;

    if (!forceRefresh && cached == null) {
      final tokens = await _tokenStore.read();
      final account = await _database.watchCurrentAccount().first;
      if (tokens == null || account == null) {
        if (tokens != null || account != null) await _clearSession();
        return null;
      }
      _session = BackendSession(
        token: tokens.token,
        refreshToken: tokens.refreshToken,
        expiresAt: tokens.expiresAt,
        account: BackendAccount(
          remoteId: account.remoteId ?? account.id,
          username: account.username,
          displayName: account.displayName,
          avatarUri: account.avatarUri,
        ),
      );
      if (!_session!.shouldRefresh) return _session;
    }

    return _refreshSession();
  }

  @override
  Future<SyncResult> syncNow() async {
    final account = await _database.watchCurrentAccount().first;
    if (account == null) throw StateError('请先登录账号。');

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
    final likedTracks = (await _database.watchLikedTracks().first)
        .map(BackendTrack.fromLocal)
        .toList(growable: false);

    final localPresets = await _database.allEqualizerPresets();
    final payloadPresets = localPresets
        .map(BackendEqualizerPreset.fromLocal)
        .toList(growable: false);

    final remote = await _syncWithRefresh(payload, likedTracks, payloadPresets);
    final localByRemoteId = {
      for (final playlist in localPlaylists)
        (playlist.remoteId ?? 'playlist-${playlist.id}'): playlist,
    };
    var downloaded = 0;
    for (final remotePlaylist in remote.playlists) {
      var local = localByRemoteId[remotePlaylist.remoteId];
      if (local == null) {
        final now = DateTime.now();
        final localId = _uuid.v4();
        await _database.createPlaylist(
          PlaylistsCompanion.insert(
            id: localId,
            remoteId: Value(remotePlaylist.remoteId),
            accountId: Value(account.id),
            name: remotePlaylist.name,
            syncState: const Value('synced'),
            createdAt: now,
            updatedAt: remotePlaylist.updatedAt,
          ),
        );
        local = (await _database.watchPlaylists().first).firstWhere(
          (item) => item.id == localId,
        );
        downloaded++;
        for (final track in remotePlaylist.tracks) {
          final localTrack = await _database.findTrackByUri(track.uri);
          if (localTrack != null) {
            await _database.addTrackToPlaylist(local.id, localTrack.id);
          }
        }
      }
      await _database.updatePlaylistSync(
        id: local.id,
        remoteId: remotePlaylist.remoteId,
        accountId: account.id,
      );
    }

    var downloadedLikes = 0;
    for (final track in remote.likedTracks) {
      final localTrack = await _database.findTrackByUri(track.uri);
      if (localTrack == null) continue;
      await _database.setTrackLiked(localTrack.id, true);
      downloadedLikes++;
    }

    final localPresetByRemoteId = {
      for (final p in localPresets) (p.remoteId ?? 'preset-${p.id}'): p,
    };
    var downloadedPresets = 0;
    for (final remotePreset in remote.equalizerPresets) {
      final local = localPresetByRemoteId[remotePreset.remoteId];
      if (local == null) {
        final localId = _uuid.v4();
        await _database.saveEqualizerPreset(
          EqualizerPresetsCompanion.insert(
            id: localId,
            remoteId: Value(remotePreset.remoteId),
            accountId: Value(account.id),
            name: remotePreset.name,
            gainsJson: remotePreset.gainsJson,
            preampDb: Value(remotePreset.preampDb),
            createdAt: remotePreset.updatedAt,
            updatedAt: remotePreset.updatedAt,
          ),
        );
        downloadedPresets++;
      } else if (remotePreset.updatedAt.isAfter(local.updatedAt)) {
        await _database.saveEqualizerPreset(
          EqualizerPresetsCompanion.insert(
            id: local.id,
            remoteId: Value(remotePreset.remoteId),
            accountId: Value(account.id),
            name: remotePreset.name,
            gainsJson: remotePreset.gainsJson,
            preampDb: Value(remotePreset.preampDb),
            createdAt: local.createdAt,
            updatedAt: remotePreset.updatedAt,
          ),
        );
      }
    }

    return SyncResult(
      uploaded: payload.length,
      downloaded: downloaded,
      uploadedLikes: likedTracks.length,
      downloadedLikes: downloadedLikes,
      uploadedPresets: payloadPresets.length,
      downloadedPresets: downloadedPresets,
    );
  }

  Future<BackendLibrary> _syncWithRefresh(
    List<BackendPlaylist> playlists,
    List<BackendTrack> likedTracks,
    List<BackendEqualizerPreset> equalizerPresets,
  ) async {
    var session = await currentSession();
    if (session == null) throw StateError('请先登录账号。');
    try {
      return await _gateway.syncLibrary(
        session,
        playlists,
        likedTracks,
        equalizerPresets,
      );
    } on BackendException catch (error) {
      if (!error.isUnauthorized) rethrow;
      session = await currentSession(forceRefresh: true);
      if (session == null) throw StateError('登录已过期，请重新登录。');
      return _gateway.syncLibrary(
        session,
        playlists,
        likedTracks,
        equalizerPresets,
      );
    }
  }

  Future<BackendSession?> _refreshSession() {
    final active = _refreshing;
    if (active != null) return active;
    final future = _performRefresh();
    _refreshing = future;
    return future.whenComplete(() => _refreshing = null);
  }

  Future<BackendSession?> _performRefresh() async {
    final stored = await _tokenStore.read();
    final refreshToken = _session?.refreshToken ?? stored?.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) return null;
    try {
      final refreshed = await _gateway.refreshSession(refreshToken);
      await _saveSession(refreshed);
      return refreshed;
    } on BackendException catch (error) {
      if (!error.isUnauthorized) rethrow;
      await _clearSession();
      return null;
    }
  }

  Future<void> _saveSession(BackendSession session) async {
    _session = session;
    final now = DateTime.now();
    final account = session.account;
    await _database.saveAccount(
      AccountsCompanion.insert(
        id: _uuid.v5(Namespace.url.value, 'account:${account.remoteId}'),
        remoteId: Value(account.remoteId),
        username: account.username,
        displayName: account.displayName,
        avatarUri: Value(account.avatarUri),
        createdAt: now,
        updatedAt: now,
        isMock: const Value(false),
      ),
    );
    await _tokenStore.write(
      StoredAuthTokens(
        token: session.token,
        refreshToken: session.refreshToken,
        expiresAt: session.expiresAt,
      ),
    );
  }

  Future<void> _clearSession() async {
    _session = null;
    await _tokenStore.clear();
    await _database.setSetting(_legacySessionKey, '');
    await _database.clearAccounts();
  }
}
