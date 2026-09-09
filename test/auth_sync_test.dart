import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_music/core/auth/auth_repository.dart';
import 'package:flutter_music/core/auth/auth_token_store.dart';
import 'package:flutter_music/core/auth/backend_gateway.dart';
import 'package:flutter_music/core/auth/track_match_token.dart';
import 'package:flutter_music/core/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

class _FakeGateway implements BackendGateway {
  BackendLibrary response = const BackendLibrary(
    playlists: [],
    likedTracks: [],
  );
  List<BackendPlaylist> uploadedPlaylists = const [];
  List<BackendTrack> uploadedLikedTracks = const [];
  List<BackendEqualizerPreset> uploadedEqualizerPresets = const [];
  List<BackendDeletion> uploadedDeletions = const [];
  final List<String> syncAccountRemoteIds = [];
  int syncCallCount = 0;
  int refreshCallCount = 0;
  BackendException? nextSyncException;
  Future<void> Function()? beforeResponse;
  BackendSession? signInResponse;
  BackendSession? refreshResponse;

  @override
  Future<BackendSession> signIn({
    required String username,
    required String password,
  }) async => signInResponse ?? (throw UnimplementedError());

  @override
  Future<BackendSession> refreshSession(String refreshToken) async {
    refreshCallCount++;
    return refreshResponse ?? (throw UnimplementedError());
  }

  @override
  Future<void> signOut(String token) async {}

  @override
  Future<BackendLibrary> syncLibrary(
    BackendSession session,
    List<BackendPlaylist> playlists,
    List<BackendTrack> likedTracks, [
    List<BackendEqualizerPreset> equalizerPresets = const [],
    List<BackendDeletion> deletions = const [],
  ]) async {
    syncCallCount++;
    syncAccountRemoteIds.add(session.account.remoteId);
    uploadedPlaylists = List.of(playlists);
    uploadedLikedTracks = List.of(likedTracks);
    uploadedEqualizerPresets = List.of(equalizerPresets);
    uploadedDeletions = List.of(deletions);
    if (beforeResponse case final callback?) await callback();
    final error = nextSyncException;
    nextSyncException = null;
    if (error != null) throw error;
    return response;
  }
}

class _MemoryTokenStore implements AuthTokenStore {
  StoredAuthTokens? tokens;

  @override
  Future<StoredAuthTokens?> read() async => tokens;

  @override
  Future<void> write(StoredAuthTokens value) async => tokens = value;

  @override
  Future<void> clear() async => tokens = null;
}

void main() {
  late AppDatabase database;
  late _FakeGateway gateway;
  late _MemoryTokenStore tokenStore;
  late BackendAuthRepository repository;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    gateway = _FakeGateway();
    tokenStore = _MemoryTokenStore();
    final now = DateTime.now();
    await database.saveAccount(
      AccountsCompanion.insert(
        id: 'account-1',
        remoteId: const Value('remote-account-1'),
        username: 'user@example.com',
        displayName: 'User',
        createdAt: now,
        updatedAt: now,
        isMock: const Value(false),
      ),
    );
    tokenStore.tokens = StoredAuthTokens(
      token: 'token',
      refreshToken: 'refresh',
      expiresAt: now.add(const Duration(hours: 1)),
      accountRemoteId: 'remote-account-1',
      trackMatchKey: _trackMatchKey,
    );
    repository = BackendAuthRepository(database, gateway, tokenStore);
  });

  tearDown(() => database.close());

  test('交互式登录派生并安全保存本地曲目匹配密钥', () async {
    await database.clearAccounts();
    tokenStore.tokens = null;
    gateway.signInResponse = BackendSession(
      token: 'new-token',
      refreshToken: 'new-refresh',
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      trackMatchSalt: 'c2FsdA',
      account: const BackendAccount(
        remoteId: 'signed-in-account',
        username: 'signed-in@example.com',
        displayName: 'Signed in',
      ),
    );

    await repository.signIn(
      username: 'signed-in@example.com',
      password: 'password',
    );

    expect(tokenStore.tokens?.trackMatchKey, isNot(null));
    expect(tokenStore.tokens?.trackMatchKey, hasLength(43));
    expect(tokenStore.tokens?.accountRemoteId, 'signed-in-account');
    expect((await repository.currentSession())?.trackMatchKey, isNot(null));
  });

  test('安全令牌绑定账号不一致时拒绝恢复并清除本地会话', () async {
    tokenStore.tokens = StoredAuthTokens(
      token: 'other-token',
      refreshToken: 'other-refresh',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
      accountRemoteId: 'remote-account-2',
      trackMatchKey: _trackMatchKey,
    );

    expect(await repository.currentSession(), equals(null));
    expect(tokenStore.tokens, equals(null));
    expect(await database.watchCurrentAccount().first, equals(null));
  });

  test('刷新响应切换账号时拒绝沿用原账号曲目密钥', () async {
    tokenStore.tokens = StoredAuthTokens(
      token: 'expired-token',
      refreshToken: 'refresh-account-1',
      expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      accountRemoteId: 'remote-account-1',
      trackMatchKey: _trackMatchKey,
    );
    gateway.refreshResponse = BackendSession(
      token: 'account-2-token',
      refreshToken: 'account-2-refresh',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
      account: const BackendAccount(
        remoteId: 'remote-account-2',
        username: 'other@example.com',
        displayName: 'Other',
      ),
    );

    expect(await repository.currentSession(), equals(null));
    expect(tokenStore.tokens, equals(null));
    expect(await database.watchCurrentAccount().first, equals(null));
  });

  test('同步期间切换账号时不应用旧账号响应', () async {
    gateway.response = BackendLibrary(
      playlists: [
        BackendPlaylist(
          remoteId: 'stale-remote-playlist',
          name: '旧账号云端歌单',
          updatedAt: DateTime(2026, 9, 8, 12),
          tracks: const [],
        ),
      ],
      likedTracks: const [],
    );
    gateway.signInResponse = _accountTwoSession();
    gateway.beforeResponse = () async {
      gateway.beforeResponse = null;
      await repository.signIn(
        username: 'other@example.com',
        password: 'password',
      );
    };

    await expectLater(
      repository.syncNow(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('账号已切换'),
        ),
      ),
    );

    expect(gateway.syncAccountRemoteIds, ['remote-account-1']);
    expect(
      (await database.watchCurrentAccount().first)?.remoteId,
      'remote-account-2',
    );
    expect(
      (await database.watchPlaylists().first).where(
        (playlist) => playlist.remoteId == 'stale-remote-playlist',
      ),
      isEmpty,
    );
  });

  test('401 后切换账号时不会把旧账号数据重试给新账号', () async {
    final now = DateTime(2026, 9, 8, 12);
    await database.savePlaylistFromSync(
      id: 'local-playlist',
      remoteId: 'remote-playlist',
      accountId: 'account-1',
      name: '旧账号本地歌单',
      createdAt: now,
      updatedAt: now,
      trackIds: const [],
    );
    gateway.nextSyncException = const BackendException(
      'unauthorized',
      statusCode: 401,
    );
    gateway.signInResponse = _accountTwoSession();
    gateway.beforeResponse = () async {
      gateway.beforeResponse = null;
      await repository.signIn(
        username: 'other@example.com',
        password: 'password',
      );
    };

    await expectLater(
      repository.syncNow(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('账号已切换'),
        ),
      ),
    );

    expect(gateway.syncCallCount, 1);
    expect(gateway.syncAccountRemoteIds, ['remote-account-1']);
    expect(gateway.uploadedPlaylists.single.name, '旧账号本地歌单');
  });

  test('401 后同账号会话只刷新并重试一次', () async {
    gateway.nextSyncException = const BackendException(
      'unauthorized',
      statusCode: 401,
    );
    gateway.refreshResponse = BackendSession(
      token: 'refreshed-token',
      refreshToken: 'refreshed-refresh-token',
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      account: const BackendAccount(
        remoteId: 'remote-account-1',
        username: 'user@example.com',
        displayName: 'User',
      ),
    );

    await repository.syncNow();

    expect(gateway.refreshCallCount, 1);
    expect(gateway.syncCallCount, 2);
    expect(gateway.syncAccountRemoteIds, [
      'remote-account-1',
      'remote-account-1',
    ]);
    expect(tokenStore.tokens?.token, 'refreshed-token');
  });

  test('同步不会上传其他账号遗留的云端数据', () async {
    final now = DateTime(2026, 9, 8, 10);
    await database.upsertTracks([
      _track('account-1-track', accountId: 'account-1'),
      _track('account-2-track', accountId: 'account-2'),
      _track('account-2-remote', accountId: 'account-2'),
    ]);
    await database.setTrackLikedFromSync(
      'account-1-track',
      true,
      updatedAt: now,
    );
    await database.setTrackLikedFromSync(
      'account-2-track',
      true,
      updatedAt: now,
    );
    await database.savePlaylistFromSync(
      id: 'account-1-playlist',
      remoteId: 'remote-playlist-1',
      accountId: 'account-1',
      name: '当前账号歌单',
      createdAt: now,
      updatedAt: now,
      trackIds: const ['account-1-track', 'account-2-track'],
    );
    await database.savePlaylistFromSync(
      id: 'account-2-playlist',
      remoteId: 'remote-playlist-2',
      accountId: 'account-2',
      name: '其他账号歌单',
      createdAt: now,
      updatedAt: now,
      trackIds: const ['account-2-track'],
    );
    await database.saveEqualizerPreset(
      EqualizerPresetsCompanion.insert(
        id: 'account-1-preset',
        remoteId: const Value('remote-preset-1'),
        accountId: const Value('account-1'),
        name: '当前账号预设',
        gainsJson: '[]',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await database.saveEqualizerPreset(
      EqualizerPresetsCompanion.insert(
        id: 'account-2-preset',
        remoteId: const Value('remote-preset-2'),
        accountId: const Value('account-2'),
        name: '其他账号预设',
        gainsJson: '[]',
        createdAt: now,
        updatedAt: now,
      ),
    );
    gateway.response = BackendLibrary(
      playlists: const [],
      likedTracks: [
        BackendTrack(
          uri: 'test://account-2-remote',
          title: 'account-2-remote',
          artist: 'artist',
          album: 'album',
          updatedAt: now,
        ),
      ],
    );

    await repository.syncNow();

    expect(gateway.uploadedPlaylists.map((playlist) => playlist.name), [
      '当前账号歌单',
    ]);
    expect(gateway.uploadedPlaylists.single.tracks.map((track) => track.uri), [
      'test://account-1-track',
    ]);
    expect(gateway.uploadedLikedTracks.map((track) => track.uri), [
      'test://account-1-track',
    ]);
    expect(gateway.uploadedEqualizerPresets.map((preset) => preset.name), [
      '当前账号预设',
    ]);
    expect(
      await database.watchLikedTrackIds().first,
      isNot(contains('account-2-remote')),
    );
  });

  test('不同账号使用相同远端 ID 时不会覆盖本地资源', () async {
    final now = DateTime(2026, 9, 8, 11);
    final legacyPlaylistId = const Uuid().v5(
      Namespace.url.value,
      'playlist:shared-playlist',
    );
    final legacyPresetId = const Uuid().v5(
      Namespace.url.value,
      'equalizer:shared-preset',
    );
    await database.savePlaylistFromSync(
      id: legacyPlaylistId,
      remoteId: 'shared-playlist',
      accountId: 'account-2',
      name: '其他账号同 ID 歌单',
      createdAt: now,
      updatedAt: now,
      trackIds: const [],
    );
    await database.saveEqualizerPreset(
      EqualizerPresetsCompanion.insert(
        id: legacyPresetId,
        remoteId: const Value('shared-preset'),
        accountId: const Value('account-2'),
        name: '其他账号同 ID 预设',
        gainsJson: '[]',
        createdAt: now,
        updatedAt: now,
      ),
    );
    gateway.response = BackendLibrary(
      playlists: [
        BackendPlaylist(
          remoteId: 'shared-playlist',
          name: '当前账号同 ID 歌单',
          updatedAt: now.add(const Duration(minutes: 1)),
          tracks: const [],
        ),
      ],
      likedTracks: const [],
      equalizerPresets: [
        BackendEqualizerPreset(
          remoteId: 'shared-preset',
          name: '当前账号同 ID 预设',
          gainsJson: '[]',
          preampDb: 0,
          updatedAt: now.add(const Duration(minutes: 1)),
        ),
      ],
    );

    await repository.syncNow();

    final playlists = await database.watchPlaylists().first;
    expect(playlists, hasLength(2));
    expect(
      playlists
          .where((playlist) => playlist.accountId == 'account-2')
          .single
          .name,
      '其他账号同 ID 歌单',
    );
    expect(
      playlists
          .where((playlist) => playlist.accountId == 'account-1')
          .single
          .name,
      '当前账号同 ID 歌单',
    );
    final presets = await database.allEqualizerPresets();
    expect(presets, hasLength(2));
    expect(
      presets.where((preset) => preset.accountId == 'account-2').single.name,
      '其他账号同 ID 预设',
    );
    expect(
      presets.where((preset) => preset.accountId == 'account-1').single.name,
      '当前账号同 ID 预设',
    );
  });

  test('newer remote playlist replaces local name and track order', () async {
    final oldTime = DateTime(2026, 8, 23, 8);
    final newTime = oldTime.add(const Duration(minutes: 1));
    await database.upsertTracks([_track('one'), _track('two')]);
    await database.savePlaylistFromSync(
      id: 'local-playlist',
      remoteId: 'remote-playlist',
      accountId: 'account-1',
      name: '旧名称',
      createdAt: oldTime,
      updatedAt: oldTime,
      trackIds: const ['one'],
    );
    gateway.response = BackendLibrary(
      playlists: [
        BackendPlaylist(
          remoteId: 'remote-playlist',
          name: '云端新名称',
          updatedAt: newTime,
          tracks: const [
            BackendTrack(
              uri: 'test://two',
              title: 'two',
              artist: 'artist',
              album: 'album',
            ),
          ],
        ),
      ],
      likedTracks: const [],
    );

    await repository.syncNow();

    final playlist = (await database.watchPlaylists().first).single;
    expect(playlist.name, '云端新名称');
    expect(
      (await database.watchPlaylistTracks(playlist.id).first).map((t) => t.id),
      ['two'],
    );
  });

  test(
    'remote playlist matches songs from local scanned directories',
    () async {
      final updatedAt = DateTime(2026, 8, 24, 8);
      const remoteFileUri = 'file:///D:/Music/missing.mp3';
      const localFileUri = 'file:///E:/Library/missing.mp3';
      const onlineUri =
          'online-music://track/provider/track-2?capabilities=playback';
      await database.upsertTracks([
        TracksCompanion.insert(
          id: 'local-file',
          sourceType: 'windows_file',
          sourceId: r'E:\Library\missing.mp3',
          uri: localFileUri,
          filePath: const Value(r'E:\Library\missing.mp3'),
          title: 'Missing local song',
          artist: const Value('Artist one'),
          album: const Value('Album one'),
          durationMs: const Value(180000),
          updatedAt: updatedAt,
        ),
      ]);
      gateway.response = BackendLibrary(
        playlists: [
          BackendPlaylist(
            remoteId: 'remote-playlist',
            name: 'Remote songs',
            updatedAt: updatedAt,
            tracks: const [
              BackendTrack(
                uri: remoteFileUri,
                title: 'Missing local song',
                artist: 'Artist one',
                album: 'Album one',
                durationMs: 180000,
              ),
              BackendTrack(
                uri: onlineUri,
                title: 'Online song',
                artist: 'Artist two',
                album: 'Album two',
              ),
            ],
          ),
        ],
        likedTracks: const [],
      );

      await repository.syncNow();

      final playlist = (await database.watchPlaylists().first).single;
      final storedTracks = await database
          .watchPlaylistTracks(playlist.id)
          .first;
      expect(storedTracks.map((track) => track.uri), const [
        localFileUri,
        onlineUri,
      ]);
      expect(storedTracks.map((track) => track.sourceType), const [
        'windows_file',
        'online',
      ]);
      expect(storedTracks.every((track) => track.isAvailable), isTrue);
      expect(storedTracks.first.id, 'local-file');
      expect(storedTracks.last.id, 'online:provider:track-2');

      await repository.syncNow();

      expect(
        gateway.uploadedPlaylists.single.tracks.map((track) => track.uri),
        const [localFileUri, onlineUri],
      );
    },
  );

  test('盲匹配令牌可跨设备关联歌单和喜欢歌曲', () async {
    final updatedAt = DateTime(2026, 8, 24, 8, 15);
    const fingerprint =
        'sha256:11111111111111111111111111111111'
        '11111111111111111111111111111111';
    final matchToken = createTrackMatchToken(
      contentFingerprint: fingerprint,
      trackMatchKey: _trackMatchKey,
    );
    await database.upsertTracks([
      TracksCompanion.insert(
        id: 'android-copy',
        sourceType: 'android_media_store',
        sourceId: '42',
        uri: 'content://media/external/audio/media/42',
        title: '本机标签已修改',
        artist: const Value('本机艺术家'),
        album: const Value('本机专辑'),
        contentFingerprint: const Value(fingerprint),
        updatedAt: updatedAt,
      ),
    ]);
    final remoteTrack = BackendTrack(
      uri: 'file:///D:/Music/original.mp3',
      title: '远端旧标题',
      artist: '远端旧艺术家',
      album: '远端旧专辑',
      updatedAt: updatedAt,
      matchToken: matchToken,
    );
    gateway.response = BackendLibrary(
      playlists: [
        BackendPlaylist(
          remoteId: 'fingerprint-playlist',
          name: '跨设备',
          updatedAt: updatedAt,
          tracks: [remoteTrack],
        ),
      ],
      likedTracks: [remoteTrack],
    );

    await repository.syncNow();

    final playlist = (await database.watchPlaylists().first).single;
    expect(
      (await database.watchPlaylistTracks(playlist.id).first).single.id,
      'android-copy',
    );
    expect(await database.watchLikedTrackIds().first, contains('android-copy'));
  });

  test(
    'Windows playlist matches Android MediaStore and document tree songs',
    () async {
      final updatedAt = DateTime(2026, 8, 24, 8, 30);
      const mediaStoreUri = 'content://media/external/audio/media/42';
      const documentUri =
          'content://com.android.externalstorage.documents/tree/'
          'primary%3AMusic/document/primary%3AMusic%2Fdocument-song.mp3';
      await database.upsertTracks([
        TracksCompanion.insert(
          id: 'android-media-store',
          sourceType: 'android_media_store',
          sourceId: '42',
          uri: mediaStoreUri,
          filePath: const Value('/storage/emulated/0/Music/untagged-song.mp3'),
          title: 'untagged-song.mp3',
          durationMs: const Value(180000),
          updatedAt: updatedAt,
        ),
        TracksCompanion.insert(
          id: 'android-document-tree',
          sourceType: 'android_document_tree',
          sourceId: 'primary:Music/document-song.mp3',
          uri: documentUri,
          title: 'document-song.mp3',
          durationMs: const Value(90000),
          updatedAt: updatedAt,
        ),
      ]);
      gateway.response = BackendLibrary(
        playlists: [
          BackendPlaylist(
            remoteId: 'windows-playlist',
            name: 'Windows songs',
            updatedAt: updatedAt,
            tracks: const [
              BackendTrack(
                uri: 'file:///D:/Music/untagged-song.mp3',
                title: 'untagged-song',
                artist: '未知艺术家',
                album: '未知专辑',
                durationMs: 180000,
              ),
              BackendTrack(
                uri: 'file:///D:/Music/document-song.mp3',
                title: 'document-song',
                artist: '未知艺术家',
                album: '未知专辑',
                durationMs: 90000,
              ),
            ],
          ),
        ],
        likedTracks: const [],
      );

      await repository.syncNow();

      final playlist = (await database.watchPlaylists().first).single;
      expect(
        (await database.watchPlaylistTracks(playlist.id).first).map(
          (track) => track.id,
        ),
        const ['android-media-store', 'android-document-tree'],
      );
    },
  );

  test('unmatched cross-device path is not kept as unavailable song', () async {
    final updatedAt = DateTime(2026, 8, 24, 9);
    const remoteFileUri = 'file:///D:/Music/not-on-this-device.mp3';
    await database.upsertTracks([
      TracksCompanion.insert(
        id: 'old-placeholder',
        sourceType: 'synced',
        sourceId: remoteFileUri,
        uri: remoteFileUri,
        title: 'Remote only',
        artist: const Value('Artist'),
        album: const Value('Album'),
        isAvailable: const Value(false),
        updatedAt: updatedAt,
      ),
    ]);
    await database.savePlaylistFromSync(
      id: 'local-playlist',
      remoteId: 'remote-playlist',
      accountId: 'account-1',
      name: 'Remote only',
      createdAt: updatedAt,
      updatedAt: updatedAt,
      trackIds: const ['old-placeholder'],
    );
    gateway.response = BackendLibrary(
      playlists: [
        BackendPlaylist(
          remoteId: 'remote-playlist',
          name: 'Remote only',
          updatedAt: updatedAt,
          tracks: const [
            BackendTrack(
              uri: remoteFileUri,
              title: 'Remote only',
              artist: 'Artist',
              album: 'Album',
            ),
          ],
        ),
      ],
      likedTracks: const [],
    );

    await repository.syncNow();

    expect(await database.watchPlaylistTracks('local-playlist').first, isEmpty);
    expect(await database.findTrackByUri(remoteFileUri), null);
  });

  test('local playlist deletion uploads and retains a tombstone', () async {
    final updatedAt = DateTime(2026, 8, 23, 8);
    await database.savePlaylistFromSync(
      id: 'local-playlist',
      remoteId: 'remote-playlist',
      accountId: 'account-1',
      name: '待删除',
      createdAt: updatedAt,
      updatedAt: updatedAt,
      trackIds: const [],
    );
    await database.deletePlaylist('local-playlist');
    final tombstone = (await database.syncTombstonesForAccount(
      'account-1',
    )).single;
    gateway.response = BackendLibrary(
      playlists: const [],
      likedTracks: const [],
      deletions: [
        BackendDeletion(
          entityType: SyncEntityType.playlist,
          remoteKey: tombstone.remoteKey,
          deletedAt: tombstone.deletedAt,
        ),
      ],
    );

    await repository.syncNow();

    expect(gateway.uploadedDeletions, hasLength(1));
    expect(gateway.uploadedDeletions.single.remoteKey, 'remote-playlist');
    expect(await database.watchPlaylists().first, isEmpty);
    expect(await database.syncTombstonesForAccount('account-1'), hasLength(1));
  });
  test('deletion created while syncing remains pending', () async {
    final updatedAt = DateTime(2026, 8, 23, 8);
    await database.savePlaylistFromSync(
      id: 'local-playlist',
      remoteId: 'remote-playlist',
      accountId: 'account-1',
      name: '同步期间删除',
      createdAt: updatedAt,
      updatedAt: updatedAt,
      trackIds: const [],
    );
    gateway.beforeResponse = () => database.deletePlaylist('local-playlist');

    await repository.syncNow();

    expect(gateway.uploadedDeletions, isEmpty);
    final tombstones = await database.syncTombstonesForAccount('account-1');
    expect(tombstones, hasLength(1));
    expect(tombstones.single.remoteKey, 'remote-playlist');
  });

  test('本地较新的歌单重命名不会被云端旧名称覆盖', () async {
    final oldTime = DateTime(2026, 8, 23, 8);
    await database.upsertTracks([_track('one')]);
    await database.savePlaylistFromSync(
      id: 'local-playlist',
      remoteId: 'remote-playlist',
      accountId: 'account-1',
      name: '本地新名称',
      createdAt: oldTime,
      updatedAt: oldTime.add(const Duration(minutes: 2)),
      trackIds: const ['one'],
    );
    gateway.response = BackendLibrary(
      playlists: [
        BackendPlaylist(
          remoteId: 'remote-playlist',
          name: '云端旧名称',
          updatedAt: oldTime.add(const Duration(minutes: 1)),
          tracks: const [],
        ),
      ],
      likedTracks: const [],
    );

    await repository.syncNow();

    final playlist = (await database.watchPlaylists().first).single;
    expect(playlist.name, '本地新名称');
    // 上传内容应携带本地较新的名称，云端最终会收敛到同一名称。
    expect(gateway.uploadedPlaylists.single.name, '本地新名称');
  });

  test('同步同时上传本地新增歌单并下载云端新增歌单', () async {
    await database.upsertTracks([_track('one')]);
    await database.createPlaylist(
      PlaylistsCompanion.insert(
        id: 'local-only',
        name: '本地新歌单',
        createdAt: DateTime(2026, 8, 25),
        updatedAt: DateTime(2026, 8, 25),
      ),
    );
    await database.addTrackToPlaylist('local-only', 'one');
    gateway.response = BackendLibrary(
      playlists: [
        BackendPlaylist(
          remoteId: 'remote-new',
          name: '云端新歌单',
          updatedAt: DateTime(2026, 8, 25),
          tracks: const [],
        ),
      ],
      likedTracks: const [],
    );

    await repository.syncNow();

    expect(gateway.uploadedPlaylists.single.name, '本地新歌单');
    expect(
      (await database.watchPlaylists().first).map((playlist) => playlist.name),
      containsAll(['本地新歌单', '云端新歌单']),
    );
  });

  test('同名同艺术家的两首本机歌曲与云端曲目有歧义时不误加入歌单', () async {
    final updatedAt = DateTime(2026, 8, 24, 8);
    await database.upsertTracks([
      TracksCompanion.insert(
        id: 'copy-a',
        sourceType: 'windows_file',
        sourceId: r'C:\Music\a1.mp3',
        uri: 'file:///C:/Music/a1.mp3',
        filePath: const Value(r'C:\Music\a1.mp3'),
        title: 'Same Song',
        artist: const Value('Artist'),
        album: const Value('Album'),
        durationMs: const Value(180000),
        updatedAt: updatedAt,
      ),
      TracksCompanion.insert(
        id: 'copy-b',
        sourceType: 'windows_file',
        sourceId: r'C:\Music\a2.mp3',
        uri: 'file:///C:/Music/a2.mp3',
        filePath: const Value(r'C:\Music\a2.mp3'),
        title: 'Same Song',
        artist: const Value('Artist'),
        album: const Value('Album'),
        durationMs: const Value(180000),
        updatedAt: updatedAt,
      ),
    ]);
    gateway.response = BackendLibrary(
      playlists: [
        BackendPlaylist(
          remoteId: 'remote-playlist',
          name: 'Ambiguous',
          updatedAt: updatedAt,
          tracks: const [
            BackendTrack(
              uri: 'file:///D:/Music/a.mp3',
              title: 'Same Song',
              artist: 'Artist',
              album: 'Album',
              durationMs: 180000,
            ),
          ],
        ),
      ],
      likedTracks: const [],
    );

    await repository.syncNow();

    final playlist = (await database.watchPlaylists().first).single;
    expect(await database.watchPlaylistTracks(playlist.id).first, isEmpty);
  });

  test('相同内容存在两份本机副本时不靠令牌任意选中', () async {
    final updatedAt = DateTime(2026, 8, 24, 8);
    const fingerprint =
        'sha256:22222222222222222222222222222222'
        '22222222222222222222222222222222';
    final matchToken = createTrackMatchToken(
      contentFingerprint: fingerprint,
      trackMatchKey: _trackMatchKey,
    );
    await database.upsertTracks([
      for (final id in ['copy-a', 'copy-b'])
        TracksCompanion.insert(
          id: id,
          sourceType: 'windows_file',
          sourceId: 'C:/Music/$id.mp3',
          uri: 'file:///C:/Music/$id.mp3',
          title: id,
          contentFingerprint: const Value(fingerprint),
          updatedAt: updatedAt,
        ),
    ]);
    gateway.response = BackendLibrary(
      playlists: [
        BackendPlaylist(
          remoteId: 'ambiguous-fingerprint',
          name: 'Ambiguous fingerprint',
          updatedAt: updatedAt,
          tracks: [
            BackendTrack(
              uri: 'file:///D:/Music/remote.mp3',
              title: 'Remote',
              artist: 'Artist',
              album: 'Album',
              matchToken: matchToken,
            ),
          ],
        ),
      ],
      likedTracks: const [],
    );

    await repository.syncNow();

    final playlist = (await database.watchPlaylists().first).single;
    expect(await database.watchPlaylistTracks(playlist.id).first, isEmpty);
  });

  test('时长相差超过 3 秒的同名歌曲不匹配', () async {
    final updatedAt = DateTime(2026, 8, 24, 8);
    await database.upsertTracks([
      TracksCompanion.insert(
        id: 'local-song',
        sourceType: 'windows_file',
        sourceId: r'C:\Music\song.mp3',
        uri: 'file:///C:/Music/song.mp3',
        filePath: const Value(r'C:\Music\song.mp3'),
        title: 'Song',
        artist: const Value('Artist'),
        album: const Value('Album'),
        durationMs: const Value(180000),
        updatedAt: updatedAt,
      ),
    ]);
    gateway.response = BackendLibrary(
      playlists: [
        BackendPlaylist(
          remoteId: 'remote-playlist',
          name: 'Duration mismatch',
          updatedAt: updatedAt,
          tracks: const [
            BackendTrack(
              uri: 'file:///D:/Music/song.mp3',
              title: 'Song',
              artist: 'Artist',
              album: 'Album',
              durationMs: 190000,
            ),
          ],
        ),
      ],
      likedTracks: const [],
    );

    await repository.syncNow();

    final playlist = (await database.watchPlaylists().first).single;
    expect(await database.watchPlaylistTracks(playlist.id).first, isEmpty);
  });

  test('云端较新的取消喜欢会撤回本地喜欢状态', () async {
    final likedAt = DateTime(2026, 8, 24, 8);
    await database.upsertTracks([_track('liked-one')]);
    await database.setTrackLikedFromSync('liked-one', true, updatedAt: likedAt);
    gateway.response = BackendLibrary(
      playlists: const [],
      likedTracks: const [],
      deletions: [
        BackendDeletion(
          entityType: SyncEntityType.likedTrack,
          remoteKey: 'test://liked-one',
          deletedAt: likedAt.add(const Duration(minutes: 1)),
        ),
      ],
    );

    await repository.syncNow();

    expect(await database.watchLikedTrackIds().first, isEmpty);
  });

  test('云端盲匹配令牌墓碑会撤回不同 URI 的本地喜欢', () async {
    final likedAt = DateTime(2026, 8, 24, 8);
    const fingerprint =
        'sha256:33333333333333333333333333333333'
        '33333333333333333333333333333333';
    final matchToken = createTrackMatchToken(
      contentFingerprint: fingerprint,
      trackMatchKey: _trackMatchKey,
    )!;
    await database.upsertTracks([
      TracksCompanion.insert(
        id: 'liked-fingerprint',
        sourceType: 'android_media_store',
        sourceId: '43',
        uri: 'content://media/external/audio/media/43',
        title: 'Song',
        contentFingerprint: const Value(fingerprint),
        updatedAt: likedAt,
      ),
    ]);
    await database.setTrackLikedFromSync(
      'liked-fingerprint',
      true,
      updatedAt: likedAt,
    );
    gateway.response = BackendLibrary(
      playlists: const [],
      likedTracks: const [],
      deletions: [
        BackendDeletion(
          entityType: SyncEntityType.likedTrack,
          remoteKey: matchToken,
          deletedAt: likedAt.add(const Duration(minutes: 1)),
        ),
      ],
    );

    await repository.syncNow();

    expect(await database.watchLikedTrackIds().first, isEmpty);
  });

  test('云端盲匹配令牌墓碑会撤回不可用曲目的本地喜欢', () async {
    final likedAt = DateTime(2026, 8, 24, 8);
    const fingerprint =
        'sha256:55555555555555555555555555555555'
        '55555555555555555555555555555555';
    final matchToken = createTrackMatchToken(
      contentFingerprint: fingerprint,
      trackMatchKey: _trackMatchKey,
    )!;
    await database.upsertTracks([
      TracksCompanion.insert(
        id: 'liked-unavailable-fingerprint',
        sourceType: 'android_media_store',
        sourceId: '44',
        uri: 'content://media/external/audio/media/44',
        title: 'Unavailable song',
        contentFingerprint: const Value(fingerprint),
        isAvailable: const Value(false),
        updatedAt: likedAt,
      ),
    ]);
    await database.setTrackLikedFromSync(
      'liked-unavailable-fingerprint',
      true,
      updatedAt: likedAt,
    );
    gateway.response = BackendLibrary(
      playlists: const [],
      likedTracks: const [],
      deletions: [
        BackendDeletion(
          entityType: SyncEntityType.likedTrack,
          remoteKey: matchToken,
          deletedAt: likedAt.add(const Duration(minutes: 1)),
        ),
      ],
    );

    await repository.syncNow();

    expect(await database.watchLikedTrackIds().first, isEmpty);
  });

  test('本地取消喜欢会把 URI 墓碑转换为盲匹配令牌上传', () async {
    final likedAt = DateTime(2026, 8, 24, 8);
    const fingerprint =
        'sha256:44444444444444444444444444444444'
        '44444444444444444444444444444444';
    await database.upsertTracks([
      TracksCompanion.insert(
        id: 'unliked-fingerprint',
        sourceType: 'windows_file',
        sourceId: r'C:\Music\song.mp3',
        uri: 'file:///C:/Music/song.mp3',
        title: 'Song',
        contentFingerprint: const Value(fingerprint),
        updatedAt: likedAt,
      ),
    ]);
    await database.setTrackLikedFromSync(
      'unliked-fingerprint',
      true,
      updatedAt: likedAt,
    );
    await database.setTrackLiked('unliked-fingerprint', false);
    gateway.beforeResponse = () async {
      gateway.response = BackendLibrary(
        playlists: const [],
        likedTracks: const [],
        deletions: gateway.uploadedDeletions,
      );
    };

    await repository.syncNow();

    final expected = createTrackMatchToken(
      contentFingerprint: fingerprint,
      trackMatchKey: _trackMatchKey,
    );
    expect(gateway.uploadedDeletions.single.remoteKey, expected);
    expect(
      (await database.syncTombstonesForAccount('account-1')).single.remoteKey,
      expected,
    );
  });

  test('本地不可用曲目的取消喜欢仍会上传盲匹配令牌', () async {
    final likedAt = DateTime(2026, 8, 24, 8);
    const fingerprint =
        'sha256:66666666666666666666666666666666'
        '66666666666666666666666666666666';
    TracksCompanion track({required bool isAvailable}) =>
        TracksCompanion.insert(
          id: 'unliked-unavailable-fingerprint',
          sourceType: 'windows_file',
          sourceId: r'C:\Music\offline-song.mp3',
          uri: 'file:///C:/Music/offline-song.mp3',
          title: 'Offline song',
          contentFingerprint: const Value(fingerprint),
          isAvailable: Value(isAvailable),
          updatedAt: likedAt,
        );
    await database.upsertTracks([track(isAvailable: true)]);
    await database.setTrackLikedFromSync(
      'unliked-unavailable-fingerprint',
      true,
      updatedAt: likedAt,
    );
    await database.setTrackLiked('unliked-unavailable-fingerprint', false);
    await database.upsertTracks([track(isAvailable: false)]);
    gateway.beforeResponse = () async {
      gateway.response = BackendLibrary(
        playlists: const [],
        likedTracks: const [],
        deletions: gateway.uploadedDeletions,
      );
    };

    await repository.syncNow();

    final expected = createTrackMatchToken(
      contentFingerprint: fingerprint,
      trackMatchKey: _trackMatchKey,
    );
    expect(gateway.uploadedDeletions.single.remoteKey, expected);
    expect(
      (await database.syncTombstonesForAccount('account-1')).single.remoteKey,
      expected,
    );
  });

  test('本地较新的喜欢不会被云端旧删除撤回', () async {
    final likedAt = DateTime(2026, 8, 24, 8);
    await database.upsertTracks([_track('liked-one')]);
    await database.setTrackLikedFromSync('liked-one', true, updatedAt: likedAt);
    gateway.response = BackendLibrary(
      playlists: const [],
      likedTracks: const [],
      deletions: [
        BackendDeletion(
          entityType: SyncEntityType.likedTrack,
          remoteKey: 'test://liked-one',
          deletedAt: likedAt.subtract(const Duration(minutes: 1)),
        ),
      ],
    );

    await repository.syncNow();

    expect(await database.watchLikedTrackIds().first, contains('liked-one'));
  });
}

const _trackMatchKey = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

BackendSession _accountTwoSession() => BackendSession(
  token: 'account-2-token',
  refreshToken: 'account-2-refresh',
  expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
  account: const BackendAccount(
    remoteId: 'remote-account-2',
    username: 'other@example.com',
    displayName: 'Other',
  ),
);

TracksCompanion _track(String id, {String? accountId}) =>
    TracksCompanion.insert(
      id: id,
      accountId: accountId == null ? const Value.absent() : Value(accountId),
      sourceType: 'test',
      sourceId: id,
      uri: 'test://$id',
      title: id,
      artist: const Value('artist'),
      album: const Value('album'),
      updatedAt: DateTime(2026, 8, 23),
    );
