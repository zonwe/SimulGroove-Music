import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_music/core/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => database.close());

  test(
    'deleting a Windows source keeps tracks from sibling directories',
    () async {
      const source = r'C:\Music';
      await database.upsertTracks([
        _track(id: 'inside', path: r'C:\Music\Album\inside.mp3'),
        _track(id: 'sibling', path: r'C:\Music-old\sibling.mp3'),
      ]);
      await database.saveScanSource(_source(id: 'music', uri: source));

      final scanSource = (await database.watchScanSources().first).single;
      await database.deleteScanSource(scanSource);

      expect((await database.allTracks()).map((track) => track.id), [
        'sibling',
      ]);
    },
  );

  test('rescanning a Windows source does not prune a sibling source', () async {
    const source = r'C:\Music';
    await database.upsertTracks([
      _track(id: 'stale', path: r'C:\Music\stale.mp3'),
      _track(id: 'sibling', path: r'C:\Music-old\sibling.mp3'),
    ]);
    await database.saveScanSource(_source(id: 'music', uri: source));
    final scanSource = (await database.watchScanSources().first).single;

    await database.replaceScanSourceTracks(scanSource, const []);

    expect((await database.allTracks()).map((track) => track.id), ['sibling']);
  });

  test(
    'source paths containing SQL pattern characters are matched literally',
    () async {
      const source = r'C:\100%_Music';
      await database.upsertTracks([
        _track(id: 'inside', path: r'C:\100%_Music\inside.mp3'),
        _track(id: 'similar', path: r'C:\100 HitsMusic\similar.mp3'),
      ]);
      await database.saveScanSource(_source(id: 'music', uri: source));

      await database.deleteScanSource(
        (await database.watchScanSources().first).single,
      );

      expect((await database.allTracks()).map((track) => track.id), [
        'similar',
      ]);
    },
  );

  test('rescanning a Linux source prunes only that path boundary', () async {
    const source = '/home/user/Music';
    await database.upsertTracks([
      _track(
        id: 'linux-stale',
        path: '/home/user/Music/stale.flac',
        sourceType: 'linux_file',
        windowsUri: false,
      ),
      _track(
        id: 'linux-sibling',
        path: '/home/user/Music-old/sibling.flac',
        sourceType: 'linux_file',
        windowsUri: false,
      ),
    ]);
    await database.saveScanSource(
      _source(id: 'linux-music', uri: source, platform: 'linux_file'),
    );

    final scanSource = (await database.watchScanSources().first).single;
    await database.replaceScanSourceTracks(scanSource, const []);

    expect((await database.allTracks()).map((track) => track.id), [
      'linux-sibling',
    ]);
  });

  test(
    'schema 4 upgrades tracks with a nullable content fingerprint',
    () async {
      final warnBefore = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(() {
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = warnBefore;
      });

      final directory = await Directory.systemTemp.createTemp(
        'flutter_music_schema_4_',
      );
      final file = File('${directory.path}/music.db');
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });

      var fileDatabase = AppDatabase.forTesting(NativeDatabase(file));
      await fileDatabase.upsertTracks([
        _track(id: 'existing', path: r'C:\Music\existing.mp3'),
      ]);
      await fileDatabase.customStatement(
        'ALTER TABLE tracks DROP COLUMN content_fingerprint',
      );
      // v4 的封面还内嵌在 tracks 里；把它加回来再升级，才能覆盖真实的旧库形态。
      await fileDatabase.customStatement(
        'ALTER TABLE tracks ADD COLUMN artwork BLOB',
      );
      await fileDatabase.customStatement('DROP TABLE track_artworks');
      await fileDatabase.customStatement('PRAGMA user_version = 4');
      await fileDatabase.close();

      fileDatabase = AppDatabase.forTesting(NativeDatabase(file));
      addTearDown(fileDatabase.close);

      final tracks = await fileDatabase.allTracks();
      expect(tracks.single.id, 'existing');
      expect(tracks.single.contentFingerprint, isNull);
      final columns = await fileDatabase
          .customSelect('PRAGMA table_info(tracks)')
          .get();
      expect(
        columns.map((row) => row.read<String>('name')),
        contains('content_fingerprint'),
      );
    },
  );

  test(
    'schema 5 moves embedded artwork into track_artworks without losing links',
    () async {
      final warnBefore = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(() {
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = warnBefore;
      });

      final directory = await Directory.systemTemp.createTemp(
        'flutter_music_schema_5_',
      );
      final file = File('${directory.path}/music.db');
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      final cover = Uint8List.fromList([0x0A, 0x0B, 0x0C]);

      var fileDatabase = AppDatabase.forTesting(NativeDatabase(file));
      await fileDatabase.upsertTracks(
        [_track(id: 'kept', path: r'C:\Music\kept.mp3')],
        artworks: {'kept': cover},
      );
      await fileDatabase.createPlaylist(
        PlaylistsCompanion.insert(
          id: 'list',
          name: 'list',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      );
      await fileDatabase.addTrackToPlaylist('list', 'kept');
      await fileDatabase.setTrackLiked('kept', true);

      // 还原成 v5：封面回到 tracks 列，独立表不存在。
      await fileDatabase.customStatement('DROP TABLE track_artworks');
      await fileDatabase.customStatement(
        'ALTER TABLE tracks ADD COLUMN artwork BLOB',
      );
      await fileDatabase.customStatement(
        "UPDATE tracks SET artwork = X'0A0B0C' WHERE id = 'kept'",
      );
      await fileDatabase.customStatement('PRAGMA user_version = 5');
      await fileDatabase.close();

      fileDatabase = AppDatabase.forTesting(NativeDatabase(file));
      addTearDown(fileDatabase.close);

      expect(await fileDatabase.trackArtwork('kept'), cover);
      final columns = await fileDatabase
          .customSelect('PRAGMA table_info(tracks)')
          .get();
      expect(
        columns.map((row) => row.read<String>('name')),
        isNot(contains('artwork')),
      );
      // 重建 tracks 表时不能级联删掉歌单条目和喜欢关系。
      expect(
        (await fileDatabase.playlistTracks('list')).map((track) => track.id),
        ['kept'],
      );
      expect(await fileDatabase.watchLikedTrackIds().first, {'kept'});
      expect(
        await fileDatabase.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    },
  );
}

TracksCompanion _track({
  required String id,
  required String path,
  String sourceType = 'windows_file',
  bool windowsUri = true,
}) {
  return TracksCompanion.insert(
    id: id,
    sourceType: sourceType,
    sourceId: path,
    uri: Uri.file(path, windows: windowsUri).toString(),
    title: id,
    updatedAt: DateTime(2026),
  );
}

ScanSourcesCompanion _source({
  required String id,
  required String uri,
  String platform = 'windows_file',
}) {
  return ScanSourcesCompanion.insert(
    id: id,
    platform: platform,
    uri: uri,
    label: id,
  );
}
