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
    final playlists = <BackendPlaylist>[];
    for (final playlist in localPlaylists) {
      final tracks = await _database.watchPlaylistTracks(playlist.id).first;
      playlists.add(
        BackendPlaylist(
          remoteId: playlist.remoteId ?? 'playlist-${playlist.id}',
          name: playlist.name,
          updatedAt: playlist.updatedAt,
          tracks: tracks.map(BackendTrack.fromLocal).toList(growable: false),
        ),
      );
    }
    final localLikes = await _database.allLikedTracksForSync();
    final likedTracks = localLikes
        .map(
          (item) =>
              BackendTrack.fromLocal(item.track, updatedAt: item.updatedAt),
        )
        .toList(growable: false);
    final localPresets = await _database.allEqualizerPresets();
    final presets = localPresets
        .map(BackendEqualizerPreset.fromLocal)
        .toList(growable: false);
    final localTombstones = await _database.syncTombstonesForAccount(
      account.id,
    );
    final deletions = localTombstones
        .map(
          (row) => BackendDeletion(
            entityType: SyncEntityType.fromWireName(row.entityType),
            remoteKey: row.remoteKey,
            deletedAt: row.deletedAt,
          ),
        )
        .toList(growable: false);

    final remote = await _syncWithRefresh(
      playlists,
      likedTracks,
      presets,
      deletions,
    );
    String deletionKey(String entityType, String remoteKey) =>
        '$entityType\u0000$remoteKey';

    final currentPlaylists = await _database.watchPlaylists().first;
    final playlistByRemoteId = {
      for (final playlist in currentPlaylists)
        (playlist.remoteId ?? 'playlist-${playlist.id}'): playlist,
    };
    final currentLikes = await _database.allLikedTracksForSync();
    final likeByUri = {for (final item in currentLikes) item.track.uri: item};
    final currentPresets = await _database.allEqualizerPresets();
    final presetByRemoteId = {
      for (final preset in currentPresets)
        (preset.remoteId ?? 'preset-${preset.id}'): preset,
    };

    for (final deletion in remote.deletions) {
      switch (deletion.entityType) {
        case SyncEntityType.playlist:
          final local = playlistByRemoteId[deletion.remoteKey];
          if (local != null && !local.updatedAt.isAfter(deletion.deletedAt)) {
            await _database.deletePlaylistFromSync(local.id);
            playlistByRemoteId.remove(deletion.remoteKey);
          }
        case SyncEntityType.likedTrack:
          final local = likeByUri[deletion.remoteKey];
          if (local != null && !local.updatedAt.isAfter(deletion.deletedAt)) {
            await _database.setTrackLikedFromSync(local.track.id, false);
            likeByUri.remove(deletion.remoteKey);
          }
        case SyncEntityType.equalizerPreset:
          final local = presetByRemoteId[deletion.remoteKey];
          if (local != null && !local.updatedAt.isAfter(deletion.deletedAt)) {
            await _database.deleteEqualizerPresetFromSync(local.id);
            presetByRemoteId.remove(deletion.remoteKey);
          }
      }
    }

    var downloaded = 0;
    for (final remotePlaylist in remote.playlists) {
      final local = playlistByRemoteId[remotePlaylist.remoteId];
      if (local != null && local.updatedAt.isAfter(remotePlaylist.updatedAt)) {
        continue;
      }
      final matchedTracks = await Future.wait(
        remotePlaylist.tracks.map(
          (track) => _database.findTrackByUri(track.uri),
        ),
      );
      await _database.savePlaylistFromSync(
        id:
            local?.id ??
            _uuid.v5(
              Namespace.url.value,
              'playlist:${remotePlaylist.remoteId}',
            ),
        remoteId: remotePlaylist.remoteId,
        accountId: account.id,
        name: remotePlaylist.name,
        createdAt: local?.createdAt ?? remotePlaylist.updatedAt,
        updatedAt: remotePlaylist.updatedAt,
        trackIds: [
          for (final track in matchedTracks)
            if (track != null) track.id,
        ],
      );
      if (local == null) downloaded++;
    }

    var downloadedLikes = 0;
    for (final track in remote.likedTracks) {
      final localTrack = await _database.findTrackByUri(track.uri);
      if (localTrack == null) continue;
      final updatedAt = track.updatedAt ?? DateTime.now();
      final local = likeByUri[track.uri];
      if (local != null && local.updatedAt.isAfter(updatedAt)) continue;
      await _database.setTrackLikedFromSync(
        localTrack.id,
        true,
        updatedAt: updatedAt,
      );
      if (local == null) downloadedLikes++;
    }

    var downloadedPresets = 0;
    for (final remotePreset in remote.equalizerPresets) {
      final local = presetByRemoteId[remotePreset.remoteId];
      if (local != null && local.updatedAt.isAfter(remotePreset.updatedAt)) {
        continue;
      }
      await _database.saveEqualizerPreset(
        EqualizerPresetsCompanion.insert(
          id:
              local?.id ??
              _uuid.v5(
                Namespace.url.value,
                'equalizer:${remotePreset.remoteId}',
              ),
          remoteId: Value(remotePreset.remoteId),
          accountId: Value(account.id),
          name: remotePreset.name,
          gainsJson: remotePreset.gainsJson,
          preampDb: Value(remotePreset.preampDb),
          createdAt: local?.createdAt ?? remotePreset.updatedAt,
          updatedAt: remotePreset.updatedAt,
        ),
      );
      if (local == null) downloadedPresets++;
    }

    final uploadedDeletionByKey = {
      for (final deletion in deletions)
        deletionKey(deletion.entityType.wireName, deletion.remoteKey): deletion,
    };
    final mergedDeletions = <String, BackendDeletion>{
      for (final deletion in remote.deletions)
        deletionKey(deletion.entityType.wireName, deletion.remoteKey): deletion,
    };
    final latestLocalTombstones = await _database.syncTombstonesForAccount(
      account.id,
    );
    for (final row in latestLocalTombstones) {
      final key = deletionKey(row.entityType, row.remoteKey);
      final uploaded = uploadedDeletionByKey[key];
      if (uploaded != null && !row.deletedAt.isAfter(uploaded.deletedAt)) {
        continue;
      }
      final pending = BackendDeletion(
        entityType: SyncEntityType.fromWireName(row.entityType),
        remoteKey: row.remoteKey,
        deletedAt: row.deletedAt,
      );
      final existing = mergedDeletions[key];
      if (existing == null || pending.deletedAt.isAfter(existing.deletedAt)) {
        mergedDeletions[key] = pending;
      }
    }
    await _database.replaceSyncTombstonesForAccount(
      account.id,
      mergedDeletions.values.map(
        (deletion) => SyncTombstonesCompanion.insert(
          accountId: account.id,
          entityType: deletion.entityType.wireName,
          remoteKey: deletion.remoteKey,
          deletedAt: deletion.deletedAt,
        ),
      ),
    );
    return SyncResult(
      uploaded: playlists.length,
      downloaded: downloaded,
      uploadedLikes: likedTracks.length,
      downloadedLikes: downloadedLikes,
      uploadedPresets: presets.length,
      downloadedPresets: downloadedPresets,
    );
  }

  Future<BackendLibrary> _syncWithRefresh(
    List<BackendPlaylist> playlists,
    List<BackendTrack> likedTracks,
    List<BackendEqualizerPreset> equalizerPresets,
    List<BackendDeletion> deletions,
  ) async {
    var session = await currentSession();
    if (session == null) throw StateError('请先登录账号。');
    try {
      return await _gateway.syncLibrary(
        session,
        playlists,
        likedTracks,
        equalizerPresets,
        deletions,
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
        deletions,
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
