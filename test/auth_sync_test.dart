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
