import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_music/core/auth/auth_repository.dart';
import 'package:flutter_music/core/auth/auth_token_store.dart';
import 'package:flutter_music/core/auth/backend_gateway.dart';
import 'package:flutter_music/core/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeGateway implements BackendGateway {
  BackendLibrary response = const BackendLibrary(
    playlists: [],
    likedTracks: [],
  );
  List<BackendPlaylist> uploadedPlaylists = const [];
  List<BackendDeletion> uploadedDeletions = const [];
  Future<void> Function()? beforeResponse;

  @override
  Future<BackendSession> signIn({
    required String username,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<BackendSession> refreshSession(String refreshToken) =>
      throw UnimplementedError();

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
    uploadedPlaylists = List.of(playlists);
    uploadedDeletions = List.of(deletions);
    if (beforeResponse case final callback?) await callback();
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
  late BackendAuthRepository repository;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    gateway = _FakeGateway();
    final tokenStore = _MemoryTokenStore();
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
    );
    repository = BackendAuthRepository(database, gateway, tokenStore);
  });

  tearDown(() => database.close());

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
}

TracksCompanion _track(String id) => TracksCompanion.insert(
  id: id,
  sourceType: 'test',
  sourceId: id,
  uri: 'test://$id',
  title: id,
  artist: const Value('artist'),
  album: const Value('album'),
  updatedAt: DateTime(2026, 8, 23),
);
