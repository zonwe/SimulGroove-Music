import 'package:drift/native.dart';
import 'package:flutter_music/core/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    await database.createPlaylist(
      PlaylistsCompanion.insert(
        id: 'playlist',
        name: '测试歌单',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    );
    await database.upsertTracks([_track('first'), _track('second')]);
  });

  tearDown(() => database.close());

  test('playlist positions preserve insertion order', () async {
    await database.addTrackToPlaylist('playlist', 'first');
    await database.addTrackToPlaylist('playlist', 'second');

    expect(
      (await database.watchPlaylistTracks('playlist').first).map(
        (track) => track.id,
      ),
      ['first', 'second'],
    );
  });

  test(
    'adding an existing track keeps the existing move-to-end behavior',
    () async {
      await database.addTrackToPlaylist('playlist', 'first');
      await database.addTrackToPlaylist('playlist', 'second');
      await database.addTrackToPlaylist('playlist', 'first');

      expect(
        (await database.watchPlaylistTracks('playlist').first).map(
          (track) => track.id,
        ),
        ['second', 'first'],
      );
    },
  );

  test(
    'batch-adding tracks keeps move-to-end semantics and deduplicates',
    () async {
      await database.addTrackToPlaylist('playlist', 'first');
      await database.addExistingTracksToPlaylist('playlist', [
        'second',
        'first',
        'second',
      ]);

      expect(
        (await database.watchPlaylistTracks('playlist').first).map(
          (track) => track.id,
        ),
        ['second', 'first'],
      );
    },
  );

  test('batch-adding an empty selection is a no-op', () async {
    await database.addExistingTracksToPlaylist('playlist', const []);

    expect(await database.watchPlaylistTracks('playlist').first, isEmpty);
  });

  test('synced playlists tolerate one local track arriving twice', () async {
    // 两台设备各自以不同 uri 上传同一首歌时，服务端会按 uri 存成两条；拉回本机
    // 后两条都解析到同一个 trackId，而歌单主键是 (playlistId, trackId)。
    await database.savePlaylistFromSync(
      id: 'synced-playlist',
      remoteId: 'playlist-remote',
      accountId: 'account',
      name: '同步歌单',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      trackIds: const ['first', 'second', 'first'],
    );

    expect(
      (await database.watchPlaylistTracks('synced-playlist').first).map(
        (track) => track.id,
      ),
      ['first', 'second'],
    );
  });

  test('cleanup removes only unreferenced online placeholders', () async {
    await database.upsertTracks([
      _track(
        'referenced-placeholder',
        sourceType: 'online',
        uri: 'online-music://track/provider/1',
      ),
      _track(
        'orphan-placeholder',
        sourceType: 'online',
        uri: 'online-music://track/provider/2',
      ),
      _track(
        'liked-placeholder',
        sourceType: 'online',
        uri: 'online-music://track/provider/3',
      ),
      _track(
        'downloaded-copy',
        sourceType: 'android_media_store',
        uri: 'content://media/external/audio/media/9',
      ),
      _track(
        'local-file',
        sourceType: 'windows_file',
        uri: 'file:///D:/Music/local.mp3',
      ),
    ]);
    await database.addTrackToPlaylist('playlist', 'referenced-placeholder');
    await database.setTrackLikedFromSync('liked-placeholder', true);

    await database.deleteUnreferencedOnlineTrackPlaceholders();

    final remaining = (await database.allTracks())
        .map((track) => track.id)
        .toSet();
    expect(remaining, contains('referenced-placeholder'));
    expect(remaining, contains('liked-placeholder'));
    // 已下载副本与本地扫描曲目都不是占位行，必须保留。
    expect(remaining, contains('downloaded-copy'));
    expect(remaining, contains('local-file'));
    expect(remaining, isNot(contains('orphan-placeholder')));
  });
}

TracksCompanion _track(String id, {String sourceType = 'test', String? uri}) =>
    TracksCompanion.insert(
      id: id,
      sourceType: sourceType,
      sourceId: id,
      uri: uri ?? 'test://$id',
      title: id,
      updatedAt: DateTime(2026),
    );
