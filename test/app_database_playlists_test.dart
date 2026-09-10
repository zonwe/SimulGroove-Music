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
}

TracksCompanion _track(String id) => TracksCompanion.insert(
  id: id,
  sourceType: 'test',
  sourceId: id,
  uri: 'test://$id',
  title: id,
  updatedAt: DateTime(2026),
);
