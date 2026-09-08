import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import 'auth_token_store.dart';
import 'backend_gateway.dart';
import 'track_match_token.dart';

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
    var session = await _gateway.signIn(
      username: normalized,
      password: password,
    );
    final matchSalt = session.trackMatchSalt;
    if (matchSalt != null && matchSalt.isNotEmpty) {
      session = session.withTrackMatchKey(
        await deriveTrackMatchKey(password: password, salt: matchSalt),
      );
    }
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
      final accountRemoteId = account.remoteId ?? account.id;
      if (tokens.accountRemoteId != accountRemoteId) {
        await _clearSession();
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
        trackMatchKey: tokens.trackMatchKey,
      );
      if (!_session!.shouldRefresh) return _session;
    }

    return _refreshSession();
  }

  @override
  Future<SyncResult> syncNow() async {
    final session = await currentSession();
    if (session == null) throw StateError('请先登录账号。');
    final account = await _database.watchCurrentAccount().first;
    if (account == null) throw StateError('请先登录账号。');
    if ((account.remoteId ?? account.id) != session.account.remoteId) {
      await _clearSession();
      throw StateError('账号会话不一致，请重新登录。');
    }
    final localTrackMatcher = _LocalTrackMatcher(
      await _database.tracksForSync(account.id),
      trackMatchKey: session.trackMatchKey,
    );

    final localPlaylists = await _database.playlistsForSync(account.id);
    final playlists = <BackendPlaylist>[];
    for (final playlist in localPlaylists) {
      final tracks = (await _database.watchPlaylistTracks(playlist.id).first)
          .where(
            (track) => track.accountId == null || track.accountId == account.id,
          )
          .toList(growable: false);
      playlists.add(
        BackendPlaylist(
          remoteId: playlist.remoteId ?? 'playlist-${playlist.id}',
          name: playlist.name,
          updatedAt: playlist.updatedAt,
          tracks: tracks
              .map(
                (track) => BackendTrack.fromLocal(
                  track,
                  trackMatchKey: session.trackMatchKey,
                ),
              )
              .toList(growable: false),
        ),
      );
    }
    final localLikes = await _database.allLikedTracksForSync(
      accountId: account.id,
    );
    final likedTracks = localLikes
        .map(
          (item) => BackendTrack.fromLocal(
            item.track,
            updatedAt: item.updatedAt,
            trackMatchKey: session.trackMatchKey,
          ),
        )
        .toList(growable: false);
    final localPresets = await _database.equalizerPresetsForSync(account.id);
    final presets = localPresets
        .map(BackendEqualizerPreset.fromLocal)
        .toList(growable: false);
    final localTombstones = await _database.syncTombstonesForAccount(
      account.id,
    );
    final deletions = localTombstones
        .map((row) => _backendDeletion(row, localTrackMatcher))
        .toList(growable: false);

    final remote = await _syncWithRefresh(
      playlists,
      likedTracks,
      presets,
      deletions,
    );
    String deletionKey(String entityType, String remoteKey) =>
        '$entityType\u0000$remoteKey';

    final currentPlaylists = await _database.playlistsForSync(account.id);
    final playlistByRemoteId = {
      for (final playlist in currentPlaylists)
        (playlist.remoteId ?? 'playlist-${playlist.id}'): playlist,
    };
    final currentLikes = await _database.allLikedTracksForSync(
      accountId: account.id,
    );
    final likeByUri = {for (final item in currentLikes) item.track.uri: item};
    final currentPresets = await _database.equalizerPresetsForSync(account.id);
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
          final matchedTrack = isTrackMatchToken(deletion.remoteKey)
              ? localTrackMatcher.findByMatchToken(deletion.remoteKey)
              : localTrackMatcher.findByUri(deletion.remoteKey);
          final local = matchedTrack == null
              ? null
              : likeByUri[matchedTrack.uri];
          if (local != null && !local.updatedAt.isAfter(deletion.deletedAt)) {
            await _database.setTrackLikedFromSync(local.track.id, false);
            likeByUri.remove(local.track.uri);
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
      final remoteTracks = <BackendTrack>[];
      final seenTrackUris = <String>{};
      for (final track in remotePlaylist.tracks) {
        if (track.uri.trim().isNotEmpty && seenTrackUris.add(track.uri)) {
          remoteTracks.add(track);
        }
      }
      final matchedTracks = remoteTracks
          .map(localTrackMatcher.find)
          .toList(growable: false);
      final trackIds = <String>[];
      final missingTracks = <TracksCompanion>[];
      for (var index = 0; index < remoteTracks.length; index++) {
        final matched = matchedTracks[index];
        if (matched != null) {
          trackIds.add(matched.id);
          continue;
        }
        final track = remoteTracks[index];
        final uri = Uri.tryParse(track.uri);
        if (!_isOnlineTrackUri(uri)) continue;
        final id = _onlineTrackId(uri!);
        trackIds.add(id);
        missingTracks.add(
          _onlineTrackCompanion(
            track,
            id: id,
            accountId: account.id,
            playlistUpdatedAt: remotePlaylist.updatedAt,
          ),
        );
      }
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
        trackIds: trackIds,
        missingTracks: missingTracks,
      );
      if (local == null) downloaded++;
    }
    await _database.deleteUnreferencedSyncedTrackPlaceholders();

    var downloadedLikes = 0;
    for (final track in remote.likedTracks) {
      final localTrack = localTrackMatcher.find(track);
      if (localTrack == null) continue;
      final updatedAt = track.updatedAt ?? DateTime.now();
      final local = likeByUri[localTrack.uri];
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
      final pending = _backendDeletion(row, localTrackMatcher);
      final key = deletionKey(pending.entityType.wireName, pending.remoteKey);
      final uploaded = uploadedDeletionByKey[key];
      if (uploaded != null && !row.deletedAt.isAfter(uploaded.deletedAt)) {
        continue;
      }
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
      final expectedAccountId =
          _session?.account.remoteId ?? stored?.accountRemoteId;
      if (expectedAccountId != null &&
          refreshed.account.remoteId != expectedAccountId) {
        await _clearSession();
        return null;
      }
      final effective = refreshed.withTrackMatchKey(
        _session?.trackMatchKey ?? stored?.trackMatchKey,
      );
      await _saveSession(effective);
      return effective;
    } on BackendException catch (error) {
      if (!error.isUnauthorized) rethrow;
      await _clearSession();
      return null;
    }
  }

  Future<void> _saveSession(BackendSession session) async {
    final now = DateTime.now();
    final account = session.account;
    try {
      await _database.replaceCurrentAccount(
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
          accountRemoteId: account.remoteId,
          trackMatchKey: session.trackMatchKey,
        ),
      );
      _session = session;
    } catch (_) {
      _session = null;
      try {
        await _tokenStore.clear();
      } catch (_) {
        // Keep the original persistence error; restoration also checks the
        // account binding before accepting any remaining token material.
      }
      try {
        await _database.clearAccounts();
      } catch (_) {
        // Keep the original persistence error.
      }
      rethrow;
    }
  }

  Future<void> _clearSession() async {
    _session = null;
    await _tokenStore.clear();
    await _database.setSetting(_legacySessionKey, '');
    await _database.clearAccounts();
  }

  TracksCompanion _onlineTrackCompanion(
    BackendTrack track, {
    required String id,
    required String accountId,
    required DateTime playlistUpdatedAt,
  }) {
    final uri = Uri.parse(track.uri);
    return TracksCompanion.insert(
      id: id,
      accountId: Value(accountId),
      sourceType: 'online',
      sourceId: '${uri.pathSegments[0]}:${uri.pathSegments[1]}',
      uri: track.uri,
      title: track.title,
      artist: Value(track.artist),
      album: Value(track.album),
      durationMs: Value(track.durationMs),
      isAvailable: const Value(true),
      syncState: const Value('synced'),
      updatedAt: track.updatedAt ?? playlistUpdatedAt,
    );
  }
}

BackendDeletion _backendDeletion(
  SyncTombstoneData row,
  _LocalTrackMatcher matcher,
) {
  final entityType = SyncEntityType.fromWireName(row.entityType);
  var remoteKey = row.remoteKey;
  if (entityType == SyncEntityType.likedTrack &&
      !isTrackMatchToken(remoteKey)) {
    final track = matcher.findByUri(remoteKey);
    remoteKey = track == null
        ? remoteKey
        : matcher.matchTokenFor(track) ?? remoteKey;
  }
  return BackendDeletion(
    entityType: entityType,
    remoteKey: remoteKey,
    deletedAt: row.deletedAt,
  );
}

String _onlineTrackId(Uri uri) =>
    'online:${uri.pathSegments[0]}:${uri.pathSegments[1]}';

bool _isOnlineTrackUri(Uri? uri) =>
    uri != null &&
    uri.scheme == 'online-music' &&
    uri.host == 'track' &&
    uri.pathSegments.length == 2;

const _indexedLocalSourceTypes = {
  'windows_file',
  'linux_file',
  'android_media_store',
  'android_document_tree',
};

class _LocalTrackMatcher {
  _LocalTrackMatcher(Iterable<Track> tracks, {required this.trackMatchKey}) {
    for (final track in tracks) {
      if (!track.isAvailable) continue;
      _availableByUri[track.uri] = track;
      _availableById[track.id] = track;
      final matchToken = matchTokenFor(track);
      if (matchToken != null) {
        _tracksByMatchToken.putIfAbsent(matchToken, () => []).add(track);
      }
      if (!_indexedLocalSourceTypes.contains(track.sourceType)) continue;
      final title = _normalizeSyncValue(track.title);
      if (title.isNotEmpty) {
        _tracksByTitle.putIfAbsent(title, () => []).add(track);
      }
      final fileName = _localTrackFileName(track);
      if (fileName.isNotEmpty) {
        _tracksByFileName.putIfAbsent(fileName, () => []).add(track);
      }
    }
  }

  final Map<String, Track> _availableByUri = {};
  final Map<String, Track> _availableById = {};
  final Map<String, List<Track>> _tracksByTitle = {};
  final Map<String, List<Track>> _tracksByFileName = {};
  final Map<String, List<Track>> _tracksByMatchToken = {};
  final String? trackMatchKey;

  Track? findByUri(String uri) => _availableByUri[uri];

  Track? findByMatchToken(String token) {
    final matches = _tracksByMatchToken[token];
    return matches?.length == 1 ? matches!.single : null;
  }

  String? matchTokenFor(Track track) => createTrackMatchToken(
    contentFingerprint: track.contentFingerprint,
    trackMatchKey: trackMatchKey,
  );

  Track? find(BackendTrack remote) {
    final exact = _availableByUri[remote.uri];
    if (exact != null) return exact;

    final uri = Uri.tryParse(remote.uri);
    if (_isOnlineTrackUri(uri)) {
      return _availableById[_onlineTrackId(uri!)];
    }

    final tokenMatch = remote.matchToken == null
        ? null
        : findByMatchToken(remote.matchToken!);
    if (tokenMatch != null) return tokenMatch;

    final candidates = <String, Track>{};
    void addCandidates(List<Track>? values) {
      if (values == null) return;
      for (final track in values) {
        candidates[track.id] = track;
      }
    }

    addCandidates(_tracksByTitle[_normalizeSyncValue(remote.title)]);
    addCandidates(_tracksByFileName[_remoteTrackFileName(remote.uri)]);

    Track? best;
    var bestScore = -1;
    var ambiguous = false;
    for (final candidate in candidates.values) {
      final score = _syncMatchScore(remote, candidate);
      if (score > bestScore) {
        best = candidate;
        bestScore = score;
        ambiguous = false;
      } else if (score >= 0 && score == bestScore) {
        ambiguous = true;
      }
    }
    return bestScore < 0 || ambiguous ? null : best;
  }
}

int _syncMatchScore(BackendTrack remote, Track local) {
  final remoteTitle = _normalizeSyncValue(remote.title);
  final localTitle = _normalizeSyncValue(local.title);
  final titleMatches =
      remoteTitle.isNotEmpty &&
      localTitle.isNotEmpty &&
      remoteTitle == localTitle;

  final fileName = _remoteTrackFileName(remote.uri);
  final fileNameMatches =
      fileName.isNotEmpty && fileName == _localTrackFileName(local);
  if (!titleMatches && !fileNameMatches) return -1;

  final artistMatches = _meaningfulMetadataMatches(remote.artist, local.artist);
  final albumMatches = _meaningfulMetadataMatches(remote.album, local.album);
  final remoteDuration = remote.durationMs;
  final localDuration = local.durationMs;
  if (remoteDuration != null &&
      localDuration != null &&
      (remoteDuration - localDuration).abs() > 3000) {
    return -1;
  }
  if (!fileNameMatches && !(artistMatches && albumMatches)) return -1;

  return (titleMatches ? 10 : 0) +
      (fileNameMatches ? 8 : 0) +
      (artistMatches ? 4 : 0) +
      (albumMatches ? 2 : 0) +
      (remoteDuration != null && localDuration != null ? 4 : 0);
}

bool _meaningfulMetadataMatches(String first, String second) {
  final normalizedFirst = _normalizeSyncValue(first);
  final normalizedSecond = _normalizeSyncValue(second);
  const unknownValues = {
    '',
    '未知艺术家',
    '未知专辑',
    'unknown artist',
    'unknown album',
  };
  return !unknownValues.contains(normalizedFirst) &&
      !unknownValues.contains(normalizedSecond) &&
      normalizedFirst == normalizedSecond;
}

String _localTrackFileName(Track track) {
  final filePath = track.filePath;
  if (filePath != null && filePath.isNotEmpty) {
    return _pathFileName(filePath);
  }
  final uriFileName = _remoteTrackFileName(track.uri);
  if (_hasFileExtension(uriFileName)) return uriFileName;
  final sourceFileName = _pathFileName(track.sourceId);
  return _hasFileExtension(sourceFileName) ? sourceFileName : uriFileName;
}

String _remoteTrackFileName(String rawUri) {
  final uri = Uri.tryParse(rawUri);
  if (uri == null || uri.pathSegments.isEmpty) return '';
  return _pathFileName(uri.pathSegments.last);
}

String _pathFileName(String value) =>
    _normalizeSyncValue(value.split(RegExp(r'[/\\]')).last);

bool _hasFileExtension(String value) {
  final dot = value.lastIndexOf('.');
  return dot > 0 && dot < value.length - 1;
}

String _normalizeSyncValue(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
